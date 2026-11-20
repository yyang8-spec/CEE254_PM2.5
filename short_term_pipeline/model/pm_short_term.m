function [pred, pred_sd, info] = pm_short_term(train_data, test_data, opts)
%PM_SHORT_TERM  Short-term PM2.5 prediction (next 3 hours), problem_type 1.
%
%   [pred, pred_sd, info] = pm_short_term(train_data, test_data, opts)
%
%   train_data  table or P x 7 matrix [time hmd tmp spd pm2d5 lat lon]
%   test_data   table or M x 6 matrix [time hmd tmp spd lat lon]
%   opts        optional, overrides the defaults in fill_defaults
%   pred        M x 1 predicted PM2.5 (same row order as test_data)
%   pred_sd     M x 1 standard deviation of the prediction
%   info        diagnostics (cleaning counts, sites, offsets, level)
%
% Model: PM(site, t) = L(t) + o(site)
%   L(t)     city-wide level from the static sensors (EWMA of recent readings),
%            held constant over the forecast horizon
%   o(site)  site offset, inverse-distance weighted from the static sites

if nargin < 3 || isempty(opts), opts = struct(); end
opts = fill_defaults(opts);
train_data = table_to_matrix(train_data, true);
test_data  = table_to_matrix(test_data, false);

%% 1. Parse (time format and column order are detected)
tr = parse_matrix(train_data, true);
te = parse_matrix(test_data, false);

%% 2. Clean
n0 = numel(tr.t);
ok = isfinite(tr.t) & isfinite(tr.pm) & isfinite(tr.lat) & isfinite(tr.lon);
info.clean.missing = sum(~ok);
% GPS errors: (0,0) or more than 0.5 deg from the median position
mlat = medn(tr.lat(ok)); mlon = medn(tr.lon(ok));
gps = (tr.lat == 0 & tr.lon == 0) | abs(tr.lat - mlat) > 0.5 | abs(tr.lon - mlon) > 0.5;
info.clean.gps = sum(ok & gps); ok = ok & ~gps;
% Spikes: PM > median + k * robust sd. Negative values are kept, because the
% robustness test adds zero-mean noise and clipping would bias the means.
p = tr.pm(ok); med = median(p); s = 1.4826 * median(abs(p - med));
spike = tr.pm > med + opts.spike_k * max(s, 1);
info.clean.spikes = sum(ok & spike); ok = ok & ~spike;
tr = subset(tr, ok);
info.clean.kept = sprintf('%d of %d rows', numel(tr.t), n0);

%% 3. Static vs mobile (no device ID in the data)
% A coordinate is a static site if it has data in most hours, a low median
% speed, and a sample count close to the busiest coordinate. The last
% condition excludes parked vehicles, whose GPS jitter spreads their samples
% over many nearby coordinates.
th = floor(tr.t * 24); nHours = max(th) - min(th) + 1;
key = round([tr.lat tr.lon] * 1e5);
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

%% 4. 10-min bin means for each static site
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

%% 5. Drop static sites that do not follow the others
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

%% 6. City level L and site offsets o (alternating means, offsets sum to 0)
o = zeros(1, nS);
for it = 1:3
    L = mean(S - o, 2, 'omitnan');
    o = mean(S - L, 1, 'omitnan'); o = o - mean(o);
end
info.site_offsets = o; info.site_latlon = [lat(:) lon(:)];

%% 7. Predict
pred = nan(numel(te.t), 1); pred_sd = pred;
[level, tRef, src] = current_level(tr, g, siteKeys, o, isStaticRow, L, opts);
info.level = level; info.level_source = src;
Lv = L;   % 10-min level, kept on its regular grid (NaN for empty bins)

[locs, ~, locId] = unique(round([te.lat te.lon] * 1e5) / 1e5, 'rows');
for k = 1:size(locs, 1)
    rows = (locId == k);
    % offset at the test site: inverse-distance weighting of the site offsets
    if nS > 0
        d = haversine_km(locs(k, 1), locs(k, 2), lat, lon);
        w = 1 ./ max(d, opts.idw_min_km) .^ opts.idw_power; w = w / sum(w);
        off = opts.offset_shrink * sum(w .* o);
        off_sd = std(o);
    else
        off = 0; off_sd = 0;
    end
    pred(rows) = max(level + off, opts.min_pred);
    % Uncertainty from the training-period change of L over the horizon,
    % measured to the middle of each target hour. Time stamps can mark the
    % start or the end of the hour; if the first one is about 1 h after the
    % training data ends, they mark the end.
    lead = (min(te.t(rows)) - tRef) * 24;
    if lead > 0.75, mid = -0.5; else, mid = 0.5; end
    hz = max((te.t(rows) - tRef) * 24 + mid, 0.1);
    pred_sd(rows) = sqrt(persist_sd(Lv, opts.bin_min, hz).^2 + off_sd^2);
end

bad = ~isfinite(pred);
pred(bad) = mean(tr.pm); pred_sd(bad) = std(tr.pm);
end

function [level, tRef, src] = current_level(tr, g, siteKeys, o, isStaticRow, L, opts)
% Current city level: EWMA of the offset-corrected static samples of the last
% 3 h, w = exp(-age / tau). Falls back to mobile data when the static data is
% older than max_stale_min.
tRef = max(tr.t);
lastStatic = max([tr.t(isStaticRow); -Inf]);
fresh = (tRef - lastStatic) * 1440 <= opts.max_stale_min;
if fresh
    [level, ok] = static_ewma(tr, g, siteKeys, o, tRef, opts);
    if ok, src = 'static EWMA'; return, end
end
% Fallback 1: recent mobile data, shifted by its median difference from L
mob = ~isStaticRow & tr.t >= tRef - 3/24;
if any(mob) && any(isfinite(L))
    bd = opts.bin_min / 1440;
    allMob = ~isStaticRow;
    b = floor(tr.t(allMob) / bd) - floor(min(tr.t) / bd) + 1;
    v = b <= numel(L) & b >= 1; b = b(v); pmM = tr.pm(allMob); pmM = pmM(v);
    bias = medn(pmM - L(b));
    if ~isfinite(bias), bias = 0; end
    w = exp(-(tRef - tr.t(mob)) * 1440 / (3 * opts.tau_min));
    level = sum(w .* (tr.pm(mob) - bias)) / sum(w); src = 'mobile EWMA (fallback)'; return
end
% Fallback 2: the most recent static data available
if isfinite(lastStatic)
    [level, ok] = static_ewma(tr, g, siteKeys, o, lastStatic, opts);
    if ok, src = 'stale static EWMA (fallback)'; return, end
end
% Fallback 3: last city level, else the training mean
v = find(isfinite(L), 1, 'last');
if ~isempty(v), level = L(v); src = 'last level (fallback)';
else, level = mean(tr.pm); src = 'training mean (fallback)'; end
end

function [level, ok] = static_ewma(tr, g, siteKeys, o, tRef, opts)
% level_method 'ewma': weighted mean of the last 3 h; 'last': latest sample only
num = 0; den = 0;
for j = 1:numel(siteKeys)
    idx = (g == siteKeys(j)) & tr.t >= tRef - 3/24 & tr.t <= tRef;
    if ~any(idx), continue; end
    if strcmp(opts.level_method, 'last')
        tj = tr.t(idx); pj = tr.pm(idx); [~, k] = max(tj);
        num = num + (pj(k) - o(j)); den = den + 1;
        continue
    end
    w = exp(-(tRef - tr.t(idx)) * 1440 / opts.tau_min);
    num = num + sum(w .* (tr.pm(idx) - o(j)));
    den = den + sum(w);
end
ok = den > 0; level = num / max(den, eps);
end

function o = fill_defaults(o)
d.tau_min         = 2;      % EWMA time constant (min)
d.level_method    = 'ewma'; % 'ewma' or 'last'
d.bin_min         = 10;     % bin size (min)
d.spike_k         = 12;     % spike threshold (robust sd)
d.static_cover    = 0.5;    % static site: fraction of hours with data
d.static_max_spd  = 2;      % static site: max median speed
d.static_min_frac = 0.05;   % static site: min fraction of the busiest count
d.min_site_corr   = 0.7;    % min correlation with the other sites
d.idw_power       = 2;
d.idw_min_km      = 0.2;
d.offset_shrink   = 1;      % 0 = no site offset
d.min_pred        = 1;      % lowest allowed prediction
d.max_stale_min   = 30;     % max age of static data used as "now" (min)
f = fieldnames(d);
for i = 1:numel(f), if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end, end
end

function s = parse_matrix(X, isTrain)
X = double(X);
t = X(:, 1); m = medn(t);
if m > 1e11, t = t / 86400000 + 719529;          % POSIX ms
elseif m > 1e8, t = t / 86400 + 719529; end      % POSIX s (else datenum)
s.t = t; s.hmd = X(:, 2);
c3 = X(:, 3); c4 = X(:, 4);
% speed has a much smaller median than temperature
if medn(c3) < medn(c4), s.tmp = c4; s.spd = c3; else, s.tmp = c3; s.spd = c4; end
if isTrain, s.pm = X(:, 5); s.lat = X(:, 6); s.lon = X(:, 7);
else, s.lat = X(:, 5); s.lon = X(:, 6); end
end

function X = table_to_matrix(X, isTrain)
% table -> [datenum hmd tmp spd (pm2d5) lat lon]; matrices are returned as is
if ~isa(X, 'table'), return; end
t = X.time;
if isdatetime(t), t.TimeZone = ''; t = datenum(t); end
if isTrain
    X = [t, X.hmd, X.tmp, X.spd, X.pm2d5, X.lat, X.lon];
else
    X = [t, X.hmd, X.tmp, X.spd, X.lat, X.lon];
end
end

function s = subset(s, ok)
f = fieldnames(s);
for i = 1:numel(f), s.(f{i}) = s.(f{i})(ok); end
end

function sd = persist_sd(Lv, binMin, hz)
% RMS change of the level over each horizon, using only pairs where both
% ends are observed
sd = zeros(size(hz));
for i = 1:numel(hz)
    lag = max(1, round(hz(i) * 60 / binMin));
    if lag < numel(Lv)
        d = Lv(1+lag:end) - Lv(1:end-lag); d = d(isfinite(d));
    else
        d = [];
    end
    if numel(d) >= 5, sd(i) = sqrt(mean(d.^2));
    else, v = Lv(isfinite(Lv)); sd(i) = std(v); end
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
% median ignoring NaN
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
