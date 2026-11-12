function [pred, pred_sd, info] = pm_short_term(train_data, test_data, opts)
%PM_SHORT_TERM  Short-term (next 3 h) PM2.5 prediction - problem_type = 1.
%
%   pred = pm_short_term(train_data, test_data)
%   [pred, pred_sd, info] = pm_short_term(train_data, test_data, opts)
%
%   train_data  P x 7  [time, humidity, temperature, speed, pm2d5, lat, lon]
%               3 days of ALL devices (static + mobile, no device ID)
%   test_data   M x 6  [time, humidity, temperature, speed, lat, lon]
%               hourly rows for the next 3 h at one or more fixed test sites
%   opts        optional struct, only for tuning / ablations (see defaults)
%
%   pred        M x 1  predicted hourly PM2.5, same row order as test_data
%   pred_sd     M x 1  1-sigma predictive uncertainty (report section j)
%   info        diagnostics (number of sites, dropped sites, offsets, ...)
%
% MODEL
%   PM(site, t) = L(t) + o(site)
%     L(t)    city-wide PM2.5 level. The static sensors move together (hourly
%             correlation 0.93-0.98 in Foshan), so one shared level explains
%             most of the variance (spread between sites ~5 ug/m3 vs ~19 over
%             time).
%     o(site) the site's offset from the city level.
%   Forecast: L(t0 + h) = exponentially smoothed L at the forecast origin
%             (persistence), held flat for h = 1, 2, 3 h.
%
% WHY PERSISTENCE AND NOT REGRESSION (validated, see short_term/README.md)
%   * PM 1 h ago correlates 0.96 with PM now, but nothing correlates with the
%     1-3 h CHANGE by more than |r| ~ 0.28 (hour of day, dew-point change,
%     recent trend, other sensors' trends).
%   * Linear regression and ridge (lambda chosen on a chronological
%     validation split) beat persistence on validation but LOST on the
%     held-out test period, on all 5 sensors and with multi-sensor
%     features: they overfit one 3-day window.
%
% RESULTS (leave-one-static-sensor-out backtest, Foshan, 585 test values)
%   NRMSE   noise 0  /  0.5 sigma  /  1.0 sigma
%   ours    0.1856   /  0.1862     /  0.1873
%   nearest-sensor persistence baseline  0.2159 / 0.2152 / 0.2148
%
% Plain MATLAB, no toolboxes; also runs in GNU Octave.

if nargin < 3 || isempty(opts), opts = struct(); end
opts = fill_defaults(opts);

%% 1. PARSE ---------------------------------------------------------------
% The competition gives plain matrices. Two things are not guaranteed:
%  (a) time format: MATLAB datenum (days), POSIX seconds or milliseconds
%  (b) column order of temperature / speed: the course PDF says
%      [hmd tmp spd] but the Canvas tables are [hmd spd tmp].
% Both are detected from the data instead of assumed.
tr = parse_matrix(train_data, true);
te = parse_matrix(test_data, false);

%% 2. CLEAN ---------------------------------------------------------------
% Remove only what is clearly wrong. Every step is logged in info.clean.
n0 = numel(tr.t);
% 2a. rows without time / PM / position cannot be used
ok = isfinite(tr.t) & isfinite(tr.pm) & isfinite(tr.lat) & isfinite(tr.lon);
info.clean.missing = sum(~ok);
% 2b. GPS errors: (0,0) fixes or points far (> 0.5 deg ~ 50 km) from the bulk
%     of the data. None in the Canvas files, kept for the competition data.
mlat = medn(tr.lat(ok)); mlon = medn(tr.lon(ok));
gps = (tr.lat == 0 & tr.lon == 0) | abs(tr.lat - mlat) > 0.5 | abs(tr.lon - mlon) > 0.5;
info.clean.gps = sum(ok & gps); ok = ok & ~gps;
% 2c. gross spikes: PM > median + k * robust sd (MAD-based, so the
%     threshold itself is not inflated by the spikes). Mobile sensors spike
%     to 1494 in Foshan; this removes 2,962 rows (0.14%, all mobile).
%     NOTE: we never clip negative values. The robustness test adds
%     zero-mean Gaussian noise to every 3-s sample; clipping the resulting
%     negatives would bias every bin mean upward.
p = tr.pm(ok); med = median(p); s = 1.4826 * median(abs(p - med));
spike = tr.pm > med + opts.spike_k * max(s, 1);
info.clean.spikes = sum(ok & spike); ok = ok & ~spike;
tr = subset(tr, ok);
info.clean.kept = sprintf('%d of %d rows', numel(tr.t), n0);

%% 3. SEPARATE STATIC FROM MOBILE ------------------------------------------
% There is no device ID. A static sensor logs ~1200 samples/h at ONE exact
% coordinate. A coordinate is a static site if ALL of:
%   * it has data in >= 50% of the hours of the window (static sensors run
%     24 h; mobile sensors are off at night),
%   * its median speed is < 2,
%   * it has >= 5% of the samples of the busiest coordinate.
% The last rule fixes a real bug: Foshan mobile #2 parks at a depot, and its
% GPS jitter spreads it over ~70 coordinates with ~300 samples each and
% >50% hourly coverage. Those passed as "static sites", outvoted the 4 real
% ones, and short-term NRMSE under 1-sigma noise went 0.189 -> 0.336.
% (5%, not more: co-located sensors - Tianjin static 1/3/4 - triple the
% count of their shared coordinate.)
th = floor(tr.t * 24); nHours = max(th) - min(th) + 1;
key = round([tr.lat tr.lon] * 1e5);              % ~1 m resolution
[ukey, ~, g] = unique(key, 'rows');
cnt = accumarray(g, 1);
isSite = false(size(ukey, 1), 1);
for c = find(cnt > 200 & cnt >= opts.static_min_frac * max(cnt))'
    idx = (g == c);
    if numel(unique(th(idx))) / nHours >= opts.static_cover && ...
            median(tr.spd(idx)) < opts.static_max_spd
        isSite(c) = true;
    end
end
siteKeys = find(isSite);
isStaticRow = isSite(g);
info.n_static_rows = sum(isStaticRow); info.n_mobile_rows = sum(~isStaticRow);

%% 4. SIGNAL PROCESSING: BIN EACH STATIC SITE ------------------------------
% 10-min bin means per site. Averaging ~200 samples per bin cuts the
% injected noise by ~sqrt(200) = 14x (1-sigma noise ~27 ug/m3 per sample ->
% ~1.9 per site-bin), which is why the noise test barely moves the score.
bd = opts.bin_min / 1440;
b0 = floor(min(tr.t) / bd); nb = floor(max(tr.t) / bd) - b0 + 1;
nS = numel(siteKeys);
S = nan(nb, nS); N = zeros(nb, nS); lat = zeros(1, nS); lon = lat;
for j = 1:nS
    idx = (g == siteKeys(j));
    b = floor(tr.t(idx) / bd) - b0 + 1;
    N(:, j) = accumarray(b, 1, [nb 1]);
    S(:, j) = accumarray(b, tr.pm(idx), [nb 1]) ./ N(:, j);
    lat(j) = ukey(siteKeys(j), 1) / 1e5; lon(j) = ukey(siteKeys(j), 2) / 1e5;
end
S(N == 0) = NaN;

%% 5. DROP FAULTY STATIC SITES ---------------------------------------------
% A site that does not move with the others is broken or unrepresentative
% (Tianjin static #6: corr 0.54 with the rest, reads ~7.6 where passing
% mobile sensors read ~36). Foshan sites correlate 0.93-0.98, so 0.7 keeps
% all of them.
keep = true(1, nS);
if nS >= 3
    for j = 1:nS
        oth = medn(S(:, setdiff(1:nS, j)), 2);
        v = isfinite(oth) & isfinite(S(:, j));
        if sum(v) > 10 && corr_simple(S(v, j), oth(v)) < opts.min_site_corr
            keep(j) = false;
        end
    end
end
if ~any(keep), keep(:) = true; end
info.dropped_sites = sum(~keep);
S = S(:, keep); N = N(:, keep); lat = lat(keep); lon = lon(keep);
siteKeys = siteKeys(keep); nS = numel(siteKeys);
info.n_sites = nS;

%% 6. TRAIN: CITY LEVEL + SITE OFFSETS -------------------------------------
% Alternate L(t) = mean_s(S - o_s) and o_s = mean_t(S - L) so that bins
% where some sites are missing do not shift the level. Offsets are
% centred (sum to 0). These offsets are the "trained" parameters of the
% model: estimated from the 3-day training window.
o = zeros(1, nS);
for it = 1:3
    L = mean(S - o, 2, 'omitnan');
    o = mean(S - L, 1, 'omitnan'); o = o - mean(o);
end
info.site_offsets = o; info.site_latlon = [lat(:) lon(:)];

%% 7. PREDICT ---------------------------------------------------------------
pred = nan(numel(te.t), 1); pred_sd = pred;
[level, tRef, src] = current_level(tr, g, siteKeys, o, isStaticRow, L, opts);
info.level = level; info.level_source = src;

% uncertainty of the level: RMS change of the 10-min city level over the
% same horizon in the training window (empirical persistence error)
Lv = L(isfinite(L));

[locs, ~, locId] = unique(round([te.lat te.lon] * 1e5) / 1e5, 'rows');
for k = 1:size(locs, 1)
    rows = (locId == k);
    % 7a. offset at the test site: inverse-distance weighting (power 2,
    %     minimum distance 0.2 km) of the sites' offsets. Validated: removing
    %     it costs 0.006 NRMSE. (Calibrated mobile passes near the site were
    %     tried as well and were worse: the static offsets are mostly sensor
    %     calibration, which vehicles driving past do not see.)
    if nS > 0
        d = haversine_km(locs(k, 1), locs(k, 2), lat, lon);
        w = 1 ./ max(d, opts.idw_min_km) .^ opts.idw_power; w = w / sum(w);
        off = opts.offset_shrink * sum(w .* o);
        off_sd = std(o);
    else
        off = 0; off_sd = 0;
    end
    % 7b. forecast = level held flat (persistence) + offset
    hz = max(te.t(rows) - tRef, 0) * 24;           % horizon in hours
    pred(rows) = max(level + off, opts.min_pred);
    pred_sd(rows) = sqrt(persist_sd(Lv, opts.bin_min, hz).^2 + off_sd^2);
end

% last-resort fallback: never return NaN to the grader
bad = ~isfinite(pred);
pred(bad) = mean(tr.pm); pred_sd(bad) = std(tr.pm);
end

%% ===================== LEVEL AT THE FORECAST ORIGIN =====================
function [level, tRef, src] = current_level(tr, g, siteKeys, o, isStaticRow, L, opts)
% Exponentially weighted mean (EWMA) of EVERY raw static sample of the last
% 3 h, offset-corrected per site:  w = exp(-age / tau).
%   * tau trades noise against lag. tau chosen on the backtest:
%       tau  5 min: 0.1856 / 0.1862 / 0.1873   (noise 0 / 0.5 / 1.0 sigma)
%       tau 10 min: 0.1874 / 0.1877 / 0.1884
%       tau 20 min: 0.1908 / 0.1910 / 0.1913
%       last 10-min bin: 0.1873 / 0.1879 / 0.1888
%     On ONE sensor the optimum is 10 min (single-sensor study); pooling 4
%     sites gives 4x the samples, so a shorter, faster-reacting tau wins.
%   * Damping the level toward the 24-h mean (AR(1)) was worse (0.1914).
% Static data must be RECENT to count as "now": if the newest static
% sample is older than max_stale_min, a few stale samples would otherwise
% get all the weight and an hours-old level would be used as current
% (found by the missing-data check in st_validate.m).
tRef = max(tr.t);
lastStatic = max([tr.t(isStaticRow); -Inf]);
fresh = (tRef - lastStatic) * 1440 <= opts.max_stale_min;
if fresh
    [level, ok] = static_ewma(tr, g, siteKeys, o, tRef, opts);
    if ok, src = 'static EWMA'; return, end
end
% FALLBACK 1: no static data in the last 3 h -> calibrated mobile data.
% Mobile sensors read differently from static ones (Foshan: ~+10), so
% their readings are shifted by the median mobile-minus-level difference
% over the training window before smoothing.
mob = ~isStaticRow & tr.t >= tRef - 3/24;
if any(mob) && any(isfinite(L))
    bd = opts.bin_min / 1440;
    allMob = ~isStaticRow;
    b = floor(tr.t(allMob) / bd) - floor(min(tr.t) / bd) + 1;
    v = b <= numel(L) & b >= 1; b = b(v); pmM = tr.pm(allMob); pmM = pmM(v);
    bias = medn(pmM - L(b));
    if ~isfinite(bias), bias = 0; end
    w = exp(-(tRef - tr.t(mob)) * 1440 / (3 * opts.tau_min));  % fewer samples -> longer tau
    level = sum(w .* (tr.pm(mob) - bias)) / sum(w); src = 'mobile EWMA (fallback)'; return
end
% FALLBACK 2: no recent mobile data either -> smooth the newest static data
% we do have (ages measured from the last static sample)
if isfinite(lastStatic)
    [level, ok] = static_ewma(tr, g, siteKeys, o, lastStatic, opts);
    if ok, src = 'stale static EWMA (fallback)'; return, end
end
% FALLBACK 3: last known level, else the training mean
v = find(isfinite(L), 1, 'last');
if ~isempty(v), level = L(v); src = 'last level (fallback)';
else, level = mean(tr.pm); src = 'training mean (fallback)'; end
end

function [level, ok] = static_ewma(tr, g, siteKeys, o, tRef, opts)
num = 0; den = 0;
for j = 1:numel(siteKeys)
    idx = (g == siteKeys(j)) & tr.t >= tRef - 3/24 & tr.t <= tRef;
    if ~any(idx), continue; end
    w = exp(-(tRef - tr.t(idx)) * 1440 / opts.tau_min);
    num = num + sum(w .* (tr.pm(idx) - o(j)));   % offset-corrected samples
    den = den + sum(w);
end
ok = den > 0; level = num / max(den, eps);
end

%% ============================== DEFAULTS =================================
function o = fill_defaults(o)
d.tau_min         = 5;     % EWMA time constant (minutes), chosen on backtest
d.bin_min         = 10;    % bin size for offsets / site checks (minutes)
d.spike_k         = 12;    % spike threshold in robust sd
d.static_cover    = 0.5;   % static site: data in >= 50% of hours
d.static_max_spd  = 2;     % ... median speed below this
d.static_min_frac = 0.05;  % ... >= 5% of the busiest coordinate's samples
d.min_site_corr   = 0.7;   % drop sites that do not track the others
d.idw_power       = 2;     % inverse-distance weighting of offsets
d.idw_min_km      = 0.2;
d.offset_shrink   = 1;     % 0 = ignore offsets (ablation)
d.min_pred        = 1;     % PM2.5 sensors floor at 1
d.max_stale_min   = 30;    % static data older than this is not "now"
f = fieldnames(d);
for i = 1:numel(f), if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end, end
end

%% ============================== HELPERS ==================================
function s = parse_matrix(X, isTrain)
X = double(X);
t = X(:, 1); m = medn(t);
if m > 1e11, t = t / 86400000 + 719529;          % POSIX ms
elseif m > 1e8, t = t / 86400 + 719529; end      % POSIX s  (else datenum)
s.t = t; s.hmd = X(:, 2);
c3 = X(:, 3); c4 = X(:, 4);
% speed has a much smaller median than temperature (static/parked ~0.3)
if medn(c3) < medn(c4), s.tmp = c4; s.spd = c3; else, s.tmp = c3; s.spd = c4; end
if isTrain, s.pm = X(:, 5); s.lat = X(:, 6); s.lon = X(:, 7);
else, s.lat = X(:, 5); s.lon = X(:, 6); end
end

function s = subset(s, ok)
f = fieldnames(s);
for i = 1:numel(f), s.(f{i}) = s.(f{i})(ok); end
end

function sd = persist_sd(Lv, binMin, hz)
% empirical RMS of the level change over each horizon in the training data
sd = zeros(size(hz));
for i = 1:numel(hz)
    lag = max(1, round(hz(i) * 60 / binMin));
    if lag < numel(Lv), sd(i) = sqrt(mean((Lv(1+lag:end) - Lv(1:end-lag)).^2));
    else, sd(i) = std(Lv); end
end
end

function d = haversine_km(lat1, lon1, lat2, lon2)
p = pi / 180;
a = sin((lat2 - lat1) * p / 2).^2 + cos(lat1 * p) .* cos(lat2 * p) .* sin((lon2 - lon1) * p / 2).^2;
d = 2 * 6371 * asin(min(1, sqrt(a)));
end

function r = corr_simple(a, b)
a = a - mean(a); b = b - mean(b);
r = sum(a .* b) / sqrt(sum(a.^2) * sum(b.^2) + eps);
end

function m = medn(x, dim)
% NaN-ignoring median (Octave's median has no 'omitnan')
if nargin < 2
    x = x(isfinite(x)); if isempty(x), m = NaN; else, m = median(x); end, return
end
if dim == 2, x = x.'; end
m = nan(1, size(x, 2));
for j = 1:size(x, 2)
    c = x(isfinite(x(:, j)), j); if ~isempty(c), m(j) = median(c); end
end
if dim == 2, m = m.'; end
end
