function [pred_pm2d5, pred_std] = pm2d5_pred_model(train_data, test_data, problem_type, opts)
%PM2D5_PRED_MODEL  CEE 254 competition entry point.
%
%   pred = pm2d5_pred_model(train_data, test_data, problem_type)
%   [pred, sd] = pm2d5_pred_model(..., opts)
%
%   train_data   P x 7  [time, humidity, temperature, speed, pm2d5, lat, lon]
%   test_data    M x 6  [time, humidity, temperature, speed, lat, lon]
%   problem_type 1 = short-term (3 h), 2 = long-term (24 h), 3 = interpolation
%   opts         (optional) struct overriding default_opts() - used for tuning
%                and ablations. The competition calls it with 3 arguments.
%
%   pred_pm2d5   M x 1 predicted PM2.5, same row order as test_data
%   pred_std     M x 1 rough 1-sigma predictive uncertainty
%
%   Model in one line:  PM(site, t) = L(t) + o(site)
%     L(t)    city-wide level, estimated from the static sensors
%             (type 1: last 10 min persistence,
%              type 2: humidity/temperature/diurnal regression + AR(1) residual,
%              type 3: level in the same 5-min bin, temporal interp if missing)
%     o(site) local offset, inverse-distance-weighted from the static sites'
%             mean offsets (optionally helped by calibrated mobile data)
%
%   Everything is plain MATLAB (no toolboxes) and also runs in GNU Octave.

if nargin < 4 || isempty(opts), opts = struct(); end
opts = fill_opts(opts, default_opts(problem_type));

% ---------- 1. parse and clean inputs ---------------------------------------
tr = parse_train(train_data);
te = parse_test(test_data);
tr = clean_train(tr, opts);

% ---------- 2. split static vs mobile, bin static sites --------------------
[site, isStaticRow] = find_static_sites(tr, opts);

M = numel(te.t);
pred_pm2d5 = nan(M, 1);
pred_std   = nan(M, 1);

% test locations (fixed sites); predict each separately
[locs, ~, locId] = unique(round([te.lat te.lon] * 1e5) / 1e5, 'rows');

for k = 1:size(locs, 1)
    rows = find(locId == k);
    tgt.lat = locs(k, 1); tgt.lon = locs(k, 2);
    tgt.t   = te.t(rows); tgt.hmd = te.hmd(rows); tgt.tmp = te.tmp(rows);

    off = site_offset_at(tgt, site, tr, isStaticRow, opts);

    switch problem_type
        case 1, [L, sL] = level_short(tgt, site, opts);
        case 2, [L, sL] = level_long(tgt, site, opts);
        case 3, [L, sL] = level_interp(tgt, site, opts);
        otherwise, error('problem_type must be 1, 2 or 3');
    end
    p = L + off.value;
    pred_pm2d5(rows) = max(p, opts.min_pred);
    pred_std(rows)   = sqrt(sL.^2 + off.sd.^2);
end

% last-resort fallback: never return NaN
bad = ~isfinite(pred_pm2d5);
if any(bad)
    pred_pm2d5(bad) = mean(tr.pm, 'omitnan');
    pred_std(bad) = std(tr.pm, 'omitnan');
end
end

% =============================================================================
% Options
% =============================================================================
function o = default_opts(problem_type)
o.min_pred        = 1;      % PM2.5 sensors floor at 1
o.spike_mad_k     = 12;     % remove PM > median + k*1.4826*MAD (gross spikes)
o.static_cover    = 0.5;    % a coordinate is "static" if it has data in >=50% of hours
o.static_max_spd  = 2;      % ...and its median speed is below this
o.static_min_frac = 0.05;   % ...and >= 5% of the busiest coordinate's samples (parked: <1%)
o.min_site_corr   = 0.7;    % drop static sites poorly correlated with the rest
o.idw_power       = 2;
o.idw_min_km      = 0.2;
o.offset_shrink   = 1.0;    % 0 = ignore local offsets, 1 = full IDW offset
o.use_mobile_offset = false;% use calibrated mobile data near the test site
o.mobile_radius_km  = 0.5;
o.mobile_min_hours  = 3;
switch problem_type
    case 1
        o.bin_min     = 10;   % static sites binned at 10 min
        o.persist_bins = 1;   % persistence of the last 10 min...
        o.min_samples = 1000; % ...or longer, until >= this many raw samples
        o.ar_damp     = false;% AR damping toward 24 h mean: hurt in backtest
    case 2
        o.bin_min     = 60;
        o.use_met     = true; % humidity regression
        o.use_tmp     = false;% separate temperature term (unstable corr; 0.369 with RH)
        o.hum_feature = 'dewpt'; % 'rh' | 'dewpt' | 'both'. Dew point: 0.361 vs RH+T 0.371
        o.use_diurnal = false;% 24 h/12 h harmonics: hurt in backtest (0.413 vs 0.371)
        o.use_ar_resid = true;
        o.ridge       = 1e-3;
    case 3
        o.bin_min     = 5;
        o.interp_mode = 'idw_now';  % 'idw_now' | 'city_now' | 'time_interp' | 'blend'
        o.blend_w     = 0.5;
end
end

function o = fill_opts(o, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end
end
end

% =============================================================================
% Parsing and cleaning
% =============================================================================
function tr = parse_train(X)
X = double(X);
tr.t   = to_days(X(:, 1));
c3 = X(:, 3); c4 = X(:, 4);
% Column order in the course text is [hmd tmp spd], but the provided tables
% are [hmd spd tmp]. Speed has a much smaller median (static/parked ~0.3).
if medn(c3) < medn(c4), tmp = c4; spd = c3; else, tmp = c3; spd = c4; end
tr.hmd = X(:, 2); tr.tmp = tmp; tr.spd = spd;
tr.pm  = X(:, 5); tr.lat = X(:, 6); tr.lon = X(:, 7);
end

function te = parse_test(X)
X = double(X);
te.t = to_days(X(:, 1));
c3 = X(:, 3); c4 = X(:, 4);
if medn(c3) < medn(c4), tmp = c4; spd = c3; else, tmp = c3; spd = c4; end
te.hmd = X(:, 2); te.tmp = tmp; te.spd = spd;
te.lat = X(:, 5); te.lon = X(:, 6);
end

function d = to_days(t)
% Accept MATLAB datenum (days), POSIX seconds or POSIX milliseconds.
m = medn(t);
if m > 1e11
    d = t / 86400000 + 719529;
elseif m > 1e8
    d = t / 86400 + 719529;
else
    d = t;
end
end

function tr = clean_train(tr, opts)
ok = isfinite(tr.t) & isfinite(tr.pm) & isfinite(tr.lat) & isfinite(tr.lon);
ok = ok & ~(tr.lat == 0 & tr.lon == 0);
% GPS glitches: far from the bulk of the data
mlat = median(tr.lat(ok)); mlon = median(tr.lon(ok));
ok = ok & abs(tr.lat - mlat) < 0.5 & abs(tr.lon - mlon) < 0.5;
% gross PM spikes only. NOTE: we deliberately do NOT clip negative values or
% apply asymmetric filters - the robustness test adds zero-mean Gaussian
% noise, and averaging unclipped values keeps the bin means unbiased.
p = tr.pm(ok);
med = median(p); s = 1.4826 * median(abs(p - med));
ok = ok & tr.pm <= med + opts.spike_mad_k * max(s, 1);
f = fieldnames(tr);
for i = 1:numel(f), tr.(f{i}) = tr.(f{i})(ok); end
end

% =============================================================================
% Static sites
% =============================================================================
function [site, isStaticRow] = find_static_sites(tr, opts)
th = floor(tr.t * 24);                      % absolute hour index
nHours = max(th) - min(th) + 1;
key = round([tr.lat tr.lon] * 1e5);
[ukey, ~, g] = unique(key, 'rows');
cnt = accumarray(g, 1);
% A real static sensor logs ~1200 samples/h at one exact coordinate. A parked
% vehicle's GPS jitters, spreading its samples over dozens of coordinates
% (Foshan mobile #2 at its depot: ~70 keys x ~300 samples, >50% hourly cover).
% So also require a sample count comparable to the busiest coordinate.
cand = find(cnt > 200 & cnt >= opts.static_min_frac * max(cnt));
isSite = false(size(ukey, 1), 1);
for c = cand'
    idx = (g == c);
    cover = numel(unique(th(idx))) / nHours;
    if cover >= opts.static_cover && median(tr.spd(idx)) < opts.static_max_spd
        isSite(c) = true;
    end
end
isStaticRow = isSite(g);
siteKeys = find(isSite);

% binning
binDays = opts.bin_min / 1440;
b0 = floor(min(tr.t) / binDays);
b1 = floor(max(tr.t) / binDays);
nb = b1 - b0 + 1;
S = nan(nb, numel(siteKeys)); H = S; T = S; N = zeros(nb, numel(siteKeys));
lat = zeros(1, numel(siteKeys)); lon = lat;
for j = 1:numel(siteKeys)
    idx = (g == siteKeys(j));
    b = floor(tr.t(idx) / binDays) - b0 + 1;
    n = accumarray(b, 1, [nb 1]);
    S(:, j) = accumarray(b, tr.pm(idx),  [nb 1]) ./ n;
    H(:, j) = accumarray(b, tr.hmd(idx), [nb 1]) ./ n;
    T(:, j) = accumarray(b, tr.tmp(idx), [nb 1]) ./ n;
    N(:, j) = n;
    lat(j) = ukey(siteKeys(j), 1) / 1e5; lon(j) = ukey(siteKeys(j), 2) / 1e5;
end
S(N == 0) = NaN; H(N == 0) = NaN; T(N == 0) = NaN;

% drop sites that do not move with the others (e.g. Tianjin static #6)
keep = true(1, size(S, 2));
if size(S, 2) >= 3
    for j = 1:size(S, 2)
        others = medn(S(:, setdiff(1:size(S, 2), j)), 2);
        v = isfinite(others) & isfinite(S(:, j));
        if sum(v) > 10
            r = corr_simple(S(v, j), others(v));
            if r < opts.min_site_corr, keep(j) = false; end
        end
    end
end
if ~any(keep), keep(:) = true; end
S = S(:, keep); H = H(:, keep); T = T(:, keep); N = N(:, keep);
lat = lat(keep); lon = lon(keep);

% decompose S = city level + site offset (2 sweeps handle missing sites)
o = zeros(1, size(S, 2));
for it = 1:3
    L = mean(S - o, 2, 'omitnan');
    o = mean(S - L, 1, 'omitnan');
    o = o - mean(o);
end

site.S = S; site.H = H; site.T = T; site.N = N;
site.lat = lat; site.lon = lon; site.offset = o;
site.L = L;                                   % city level per bin
site.Hc = mean(H, 2, 'omitnan'); site.Tc = mean(T, 2, 'omitnan');
site.tb = ((b0:b1)' + 0.5) * binDays;          % bin centre times (days)
site.binDays = binDays;
site.dropped = sum(~keep);
end

function r = corr_simple(a, b)
a = a - mean(a); b = b - mean(b);
r = sum(a .* b) / sqrt(sum(a .^ 2) * sum(b .^ 2) + eps);
end

function w = idw_weights(lat0, lon0, lat, lon, opts)
d = haversine_km(lat0, lon0, lat, lon);
w = 1 ./ max(d, opts.idw_min_km) .^ opts.idw_power;
w = w / sum(w);
end

function d = haversine_km(lat1, lon1, lat2, lon2)
p = pi / 180;
a = sin((lat2 - lat1) * p / 2) .^ 2 + cos(lat1 * p) .* cos(lat2 * p) .* sin((lon2 - lon1) * p / 2) .^ 2;
d = 2 * 6371 * asin(min(1, sqrt(a)));
end

% =============================================================================
% Local offset at the test location
% =============================================================================
function off = site_offset_at(tgt, site, tr, isStaticRow, opts)
w = idw_weights(tgt.lat, tgt.lon, site.lat, site.lon, opts);
o_idw = sum(w .* site.offset);
off.value = opts.offset_shrink * o_idw;
off.sd = std(site.offset);                    % spread of offsets = uncertainty
if isnan(off.sd), off.sd = 0; end

if opts.use_mobile_offset
    mob = ~isStaticRow;
    if any(mob)
        d = haversine_km(tgt.lat, tgt.lon, tr.lat(mob), tr.lon(mob));
        near = d < opts.mobile_radius_km;
        if any(near)
            tm = tr.t(mob); pm = tr.pm(mob);
            % calibrate mobile -> static by binwise ratio of medians
            b  = floor(tm / site.binDays);
            bs = floor(site.tb / site.binDays);
            [ub, ~, gb] = unique(b);
            medAll = accumarray(gb, pm, [], @median);
            [tf, loc] = ismember(ub, bs);
            Lb = nan(size(ub)); Lb(tf) = site.L(loc(tf));
            v = isfinite(Lb) & medAll > 0;
            ratio = median(Lb(v) ./ medAll(v));
            % local anomaly near target, per bin
            bn = b(near); [ubn, ~, gn] = unique(bn);
            mn = accumarray(gn, pm(near), [], @median) * ratio;
            [tf, loc] = ismember(ubn, bs);
            an = mn(tf) - site.L(loc(tf));
            an = an(isfinite(an));
            if numel(an) >= opts.mobile_min_hours * (60 / opts.bin_min)
                % precision-weighted blend of static-IDW and mobile estimates
                s2m = var(an) / numel(an) + (0.3 * std(an))^2;
                s2s = off.sd^2 + eps;
                wm = s2s / (s2s + s2m);
                off.value = (1 - wm) * off.value + wm * median(an);
                off.sd = sqrt(1 / (1 / s2s + 1 / s2m));
            end
        end
    end
end
end

% =============================================================================
% Level models
% =============================================================================
function [L, sL] = level_short(tgt, site, opts)
Lc = site.L; v = find(isfinite(Lc));
% Sample-weighted level over the most recent bins: take at least
% persist_bins bins and keep going back until min_samples raw samples are
% covered. A single sparse bin at a data edge is otherwise very noise-prone.
A = site.S - site.offset; Nw = site.N; Nw(~isfinite(A)) = 0; A(~isfinite(A)) = 0;
num = 0; den = 0; nb = 0;
for b = v(end):-1:1
    num = num + sum(Nw(b, :) .* A(b, :)); den = den + sum(Nw(b, :)); nb = nb + 1;
    if nb >= opts.persist_bins && den >= opts.min_samples, break; end
end
last = num / max(den, 1);
tLast = site.tb(v(end));
hz = max(tgt.t - tLast, 0) * 24;               % horizon in hours
if opts.ar_damp
    % hourly AR(1) on the level, damp toward the last-24h mean
    [phi, mu] = ar1_fit(Lc(v), round(60 / opts.bin_min), 24 * 60 / opts.bin_min);
    L = mu + phi .^ hz .* (last - mu);
else
    L = repmat(last, size(tgt.t));
end
% uncertainty: empirical persistence error growth in training
sL = persistence_sd(Lc(v), opts.bin_min, hz);
end

function [L, sL] = level_long(tgt, site, opts)
y = site.L; Hc = site.Hc; Tc = site.Tc; tb = site.tb;
v = isfinite(y) & isfinite(Hc) & isfinite(Tc);
Xtr = design(tb(v), Hc(v), Tc(v), opts);
ytr = y(v);
% standardize columns (except intercept) for ridge
mu = mean(Xtr(:, 2:end), 1); sd = std(Xtr(:, 2:end), 0, 1); sd(sd == 0) = 1;
Z = [ones(sum(v), 1), (Xtr(:, 2:end) - mu) ./ sd];
R = opts.ridge * eye(size(Z, 2)); R(1, 1) = 0;
beta = (Z' * Z + size(Z, 1) * R) \ (Z' * ytr);

% future met at the test site; fill gaps with the training diurnal mean
hf = tgt.hmd; tf = tgt.tmp;
hf(~isfinite(hf)) = mean(Hc(v));
tf(~isfinite(tf)) = mean(Tc(v));
Xf = design(tgt.t, hf, tf, opts);
% Never extrapolate the met features: the static enclosures' temperature can
% be almost constant during training (tiny std -> huge coefficient), while the
% test site's sensor varies. Clip each feature to its training range.
lo = min(Xtr, [], 1); hi = max(Xtr, [], 1);
Xf = min(max(Xf, lo), hi);
Zf = [ones(numel(tgt.t), 1), (Xf(:, 2:end) - mu) ./ sd];
L = Zf * beta;

res = ytr - Z * beta;
hz = max(tgt.t - tb(find(v, 1, 'last')), 0) * 24;
if opts.use_ar_resid && numel(res) > 5
    phi = max(0, min(1, sum(res(1:end-1) .* res(2:end)) / sum(res(1:end-1) .^ 2)));
    L = L + phi .^ hz .* res(end);
    sL = std(res) * sqrt(1 - phi .^ (2 * hz));
else
    sL = repmat(std(res), size(hz));
end
L = min(max(L, min(ytr)), max(ytr));          % stay inside the observed range
end

function X = design(t, h, tm, opts)
X = ones(numel(t), 1);
if opts.use_met
    switch opts.hum_feature
        case 'rh',     X = [X, h(:)];
        case 'dewpt',  X = [X, dewpoint(tm(:), h(:))];
        case 'both',   X = [X, h(:), dewpoint(tm(:), h(:))];
    end
end
if opts.use_met && opts.use_tmp, X = [X, tm(:)]; end
if opts.use_diurnal
    w = 2 * pi * mod(t(:), 1);                 % fraction of day
    X = [X, sin(w), cos(w), sin(2 * w), cos(2 * w)];
end
end

function [L, sL] = level_interp(tgt, site, opts)
tb = site.tb; binDays = site.binDays;
bt = floor(tgt.t / binDays);
bs = floor(tb / binDays);
[tf, loc] = ismember(bt, bs);
Lc = site.L;
% temporal interpolation of the level across the gap
v = isfinite(Lc);
Lint = interp1(tb(v), Lc(v), (bt + 0.5) * binDays, 'linear', 'extrap');

Lnow = nan(size(tgt.t)); Inow = Lnow;
w = idw_weights(tgt.lat, tgt.lon, site.lat, site.lon, opts);
for i = 1:numel(tgt.t)
    if tf(i)
        Lnow(i) = Lc(loc(i));
        s = site.S(loc(i), :); m = isfinite(s);
        if any(m), Inow(i) = sum(w(m) .* s(m)) / sum(w(m)); end
    end
end
off = opts.offset_shrink * sum(w .* site.offset);
switch opts.interp_mode
    case 'idw_now'
        % direct IDW of the simultaneous static readings (already local)
        L = Inow - off;                        % offset added back by caller
    case 'city_now'
        L = Lnow;
    case 'time_interp'
        L = Lint;
    case 'blend'
        L = opts.blend_w * (Inow - off) + (1 - opts.blend_w) * Lint;
end
miss = ~isfinite(L);
L(miss) = Lint(miss);                          % window blanked for every sensor
sL = repmat(std(site.offset), size(L));
sL(miss) = sL(miss) * 2;
end

% =============================================================================
% Small time-series helpers
% =============================================================================
function [phi, mu] = ar1_fit(x, lag, muWin)
x = x(:);
mu = mean(x(max(1, end - muWin + 1):end));
a = x(1:end-lag) - mu; b = x(1+lag:end) - mu;
phi = max(0, min(1, sum(a .* b) / sum(a .^ 2)));   % per "lag" bins = per hour
end

function s = persistence_sd(x, binMin, hz)
x = x(:); s = zeros(size(hz));
for i = 1:numel(hz)
    lag = max(1, round(hz(i) * 60 / binMin));
    if lag < numel(x)
        e = x(1+lag:end) - x(1:end-lag);
        s(i) = sqrt(mean(e .^ 2));
    else
        s(i) = std(x);
    end
end
end

function m = medn(x, dim)
% NaN-ignoring median (Octave's median has no 'omitnan').
if nargin < 2
    x = x(isfinite(x)); if isempty(x), m = NaN; else, m = median(x); end
    return
end
if dim == 2, x = x.'; end
m = nan(1, size(x, 2));
for j = 1:size(x, 2)
    c = x(isfinite(x(:, j)), j); if ~isempty(c), m(j) = median(c); end
end
if dim == 2, m = m.'; end
end

function td = dewpoint(T, RH)
% Magnus formula, deg C. Dew point tracks absolute moisture, which in the
% Tianjin data correlates with PM2.5 more strongly than relative humidity.
a = 17.62; b = 243.12;
g = log(min(max(RH, 1), 100) / 100) + a * T ./ (b + T);
td = b * g ./ (a - g);
end
