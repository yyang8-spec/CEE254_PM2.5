%ST_SINGLE_SENSOR  Short-term (3 h ahead) PM2.5 forecasting on ONE sensor.
%
%   Stage 1  data cleaning      (what is wrong with the raw 3-s data, fixed how)
%   Stage 2  correlation check  (which inputs are worth keeping)
%   Stage 3  models             (baselines -> linear regression -> ridge),
%                               rolling-origin evaluation, chronological
%                               validation/test split, noise robustness
%
% Sensor: Foshan static #3. All 5 Foshan static sensors are similarly clean
% (6-9 gaps > 6 s, longest 72-75 s), and #3 has the highest mean hourly
% correlation with the other four (0.969), so it represents the city-wide
% signal best. Change SENSOR to repeat the analysis on another one.
%
% Task mimicked: at an origin time t0, use the 3 days before t0 to predict
% the mean PM2.5 of each of the next 3 hours [t0+(h-1)h, t0+h h), h = 1..3.
%
% Run from the repo root:  run('short_term/st_single_sensor.m')
% Needs data/processed/devices_foshan.mat  (data_cleaning/export_device_matrices.m)
% Plain MATLAB, no toolboxes; also runs in GNU Octave (set MAKE_FIGS = false
% if there is no display).

ROOT = fileparts(fileparts(mfilename('fullpath')));
if ~exist('SENSOR', 'var'),    SENSOR = 3;        end
if ~exist('MAKE_FIGS', 'var'), MAKE_FIGS = true;  end
FIGDIR = fullfile(ROOT, 'figures');

S = load(fullfile(ROOT, 'data', 'processed', 'devices_foshan.mat'));
stIdx = find(logical(S.is_static));
raw = S.dev{stIdx(SENSOR)};        % [datenum hmd tmp spd pm lat lon]
fprintf('Foshan static #%d: %d raw samples, %s to %s\n', SENSOR, size(raw,1), ...
    datestr(raw(1,1)), datestr(raw(end,1)));

%% ======================= STAGE 1: DATA CLEANING ===========================
cleanLog = {};                        % cleaning log: {step, rows affected, note}
X = raw;

% 1a. ordering, duplicates, NaN
[~, o] = sort(X(:,1)); X = X(o,:);
dup = [false; diff(X(:,1)) == 0];
cleanLog(end+1,:) = {'duplicate timestamps', sum(dup), 'removed'};
X = X(~dup,:);
nanRow = any(~isfinite(X(:,[1 2 3 5])), 2);
cleanLog(end+1,:) = {'NaN in time/hmd/tmp/pm', sum(nanRow), 'removed'};
X = X(~nanRow,:);

% 1b. sampling interval and gaps
dt = diff(X(:,1)) * 86400;
fprintf('\n[1] sampling: median dt %.1f s; gaps > 6 s: %d; > 60 s: %d; longest %.0f s\n', ...
    median(dt), sum(dt > 6), sum(dt > 60), max(dt));
cleanLog(end+1,:) = {'gaps > 6 s (not filled)', sum(dt > 6), sprintf('longest %.0f s', max(dt))};

% 1c. GPS / speed sanity for a static sensor
fprintf('    lat/lon unique values: %d / %d;  speed median %.2f, max %.2f\n', ...
    numel(unique(X(:,6))), numel(unique(X(:,7))), median(X(:,4)), max(X(:,4)));

% 1d. physical range checks
badRange = X(:,5) < 0 | X(:,5) > 1000 | X(:,2) < 0 | X(:,2) > 100 | X(:,3) < -30 | X(:,3) > 50;
cleanLog(end+1,:) = {'outside physical range', sum(badRange), 'PM [0,1000], RH [0,100], T [-30,50] -> removed'};
X = X(~badRange,:);

% 1e. flat-lines (sensor stuck): >= 10 min of identical PM readings
runId = cumsum([1; diff(X(:,5)) ~= 0]);
runLen = accumarray(runId, 1);
flat = runLen(runId) >= 200;       % 200 samples x 3 s = 10 min
cleanLog(end+1,:) = {'flat-line >= 10 min', sum(flat), sprintf('longest run %d samples', max(runLen))};
X = X(~flat,:);

% 1f. spikes: Hampel filter on a 5-min window (101 samples), k = 6 robust sd.
% Flagged points are REMOVED (set aside), never clipped: the robustness test
% adds zero-mean noise and clipping would bias the bin means.
pm = X(:,5);
med = movmedian(pm, 101);
madv = movmedian(abs(pm - med), 101) * 1.4826;
spike = abs(pm - med) > 6 * max(madv, 1);
cleanLog(end+1,:) = {'Hampel spikes (5 min, 6 sd)', sum(spike), sprintf('max |dev| %.0f', max(abs(pm - med)))};
X = X(~spike,:);

% 1g. aggregate to 10-min bins (features) and 1-h bins (targets)
B10 = bin_series(X, 10);
B60 = bin_series(X, 60);
minCount = 0.5 * 600 / 3;          % keep a 10-min bin only if >= 50% of its 200 samples
weak = B10.n < minCount & B10.n > 0;
B10.pm(weak) = NaN;
cleanLog(end+1,:) = {'10-min bins < 50% coverage', sum(weak), 'set to NaN'};
fprintf('    10-min bins: %d (%d empty);  hourly bins: %d\n', numel(B10.t), sum(B10.n == 0), numel(B60.t));

fprintf('\n[1] CLEANING LOG\n');
fprintf('    %-30s %10s   %s\n', 'step', 'rows', 'note');
for i = 1:size(cleanLog,1), fprintf('    %-30s %10d   %s\n', cleanLog{i,1}, cleanLog{i,2}, cleanLog{i,3}); end
fprintf('    kept %d of %d samples (%.3f%%)\n', size(X,1), size(raw,1), 100*size(X,1)/size(raw,1));

% noise reduction from binning: the robustness test adds N(0, s^2) per sample
sig = std(raw(:,5));
fprintf('    noise check: train-PM sd = %.1f -> 1.0-sigma noise per 10-min bin ~ %.2f, per hour ~ %.2f\n', ...
    sig, sig / sqrt(200), sig / sqrt(1200));

if MAKE_FIGS
    f = figure('Color','w','Position',[50 50 1200 600]);
    subplot(2,1,1); plot(raw(:,1), raw(:,5), '.', 'MarkerSize', 2); hold on;
    plot(B10.t, B10.pm, 'r-', 'LineWidth', 1); datetick('x', 'mm/dd'); grid on;
    ylabel('PM2.5'); legend('raw 3 s', 'clean 10-min mean'); title(sprintf('Foshan static #%d', SENSOR));
    subplot(2,1,2); plot(B60.t, B60.rh, 'b'); hold on; plot(B60.t, B60.tm, 'r'); datetick('x','mm/dd'); grid on;
    legend('humidity (%)', 'temperature (C)');
    print(f, fullfile(FIGDIR, sprintf('st_s%d_cleaning.png', SENSOR)), '-dpng', '-r150');
end

%% ===================== STAGE 2: CORRELATION CHECK ==========================
% On the hourly series. For forecasting, what matters is how PM at the
% TARGET hour relates to (i) PM history known at the origin and (ii) met at
% the target hour (test_data gives humidity/temperature at the test times).
y  = B60.pm; rh = B60.rh; tm = B60.tm; td = dewpoint(tm, rh);
hr = mod(B60.t, 1) * 24;
cands = struct( ...
  'humidity', rh, 'temperature', tm, 'dew_point', td, ...
  'hour_sin', sin(2*pi*hr/24), 'hour_cos', cos(2*pi*hr/24), ...
  'pm_lag1h', lagv(y,1), 'pm_lag2h', lagv(y,2), 'pm_lag3h', lagv(y,3), ...
  'pm_lag6h', lagv(y,6), 'pm_lag24h', lagv(y,24), ...
  'd_pm_1h', lagv(y,1) - lagv(y,2), ...            % last-hour change (trend)
  'd_temp_1h', tm - lagv(tm,1), 'd_hum_1h', rh - lagv(rh,1));
fn = fieldnames(cands);
nd = floor(numel(y) / 24);         % per-day stability
fprintf('\n[2] CORRELATION with hourly PM2.5 (n = %d h)\n', sum(isfinite(y)));
fprintf('    %-12s %8s %8s   per-day Pearson\n', 'feature', 'Pearson', 'Spearman');
R = zeros(numel(fn),1);
for k = 1:numel(fn)
    x = cands.(fn{k}); R(k) = pearson(y, x);
    rd = arrayfun(@(d) pearson(y((d-1)*24+(1:24)), x((d-1)*24+(1:24))), 1:nd);
    fprintf('    %-12s %8.3f %8.3f   %s\n', fn{k}, R(k), spearman(y, x), sprintf('%6.2f', rd));
end
v = isfinite(y) & isfinite(rh) & isfinite(tm);
r1 = pearson(y(v), rh(v)); r2 = pearson(y(v), tm(v)); r3 = pearson(rh(v), tm(v));
fprintf('    partial corr(PM, humidity | temperature) = %.3f   (raw %.3f; corr(RH,T) = %.3f)\n', ...
    (r1 - r2*r3) / sqrt((1-r2^2)*(1-r3^2)), r1, r3);

% the forecasting question: does a feature explain the CHANGE from now?
% corr( y(t+h) - y(t), feature ) for h = 1..3
fprintf('    corr with 1-3 h CHANGE  y(t+h)-y(t):\n');
chk = {'d_pm_1h', 'humidity', 'temperature', 'dew_point', 'hour_sin', 'hour_cos'};
for k = 1:numel(chk)
    x = cands.(chk{k}); s = '';
    for h = 1:3
        dy = [y(1+h:end) - y(1:end-h); nan(h,1)];
        if any(strcmp(chk{k}, {'humidity','temperature','dew_point','hour_sin','hour_cos'}))
            xx = [x(1+h:end) - x(1:end-h); nan(h,1)];    % change in met over the horizon
        else
            xx = x;                                       % trend known at the origin
        end
        s = [s sprintf('  h=%d: %6.3f', h, pearson(dy, xx))]; %#ok<AGROW>
    end
    fprintf('      %-12s%s\n', chk{k}, s);
end
% autocorrelation
acf = arrayfun(@(L) pearson(y(1+L:end), y(1:end-L)), 1:48);
fprintf('    ACF: lag1 %.2f  lag3 %.2f  lag6 %.2f  lag12 %.2f  lag24 %.2f\n', acf([1 3 6 12 24]));

if MAKE_FIGS
    f = figure('Color','w','Position',[50 50 1200 380]);
    subplot(1,3,1); stem(1:48, acf, 'filled'); xlabel('lag (h)'); ylabel('ACF'); grid on; title('autocorrelation');
    subplot(1,3,2); scatter(tm, y, 10, 'filled'); xlabel('temperature (C)'); ylabel('PM2.5'); grid on;
    title(sprintf('r = %.2f', pearson(y, tm)));
    subplot(1,3,3); barh(R); set(gca,'YTick',1:numel(fn),'YTickLabel',strrep(fn,'_',' ')); xlim([-1 1]);
    grid on; xlabel('Pearson r'); title('features vs PM2.5');
    print(f, fullfile(FIGDIR, sprintf('st_s%d_correlation.png', SENSOR)), '-dpng', '-r150');
end

%% ========================= STAGE 3: MODELS =================================
% Rolling origin: every hour from day 4 on. Each forecast uses ONLY the 3 days
% before its origin (as in the competition). Origins are split in time:
%   validation = first half of the origins  -> choose models / ridge lambda
%   test       = second half                -> reported once, untouched
NOISE = [0 0.5 1.0];
t10 = B10.t; nBin = numel(t10);
day0 = floor(raw(1,1));
origins = (day0 + 3):(1/24):(floor(raw(end,1)) - 3/24);
nO = numel(origins); isVal = (1:nO) <= floor(nO/2);
fprintf('\n[3] MODELS: %d hourly origins (%s .. %s); validation = first %d, test = last %d\n', ...
    nO, datestr(origins(1)), datestr(origins(end)), sum(isVal), sum(~isVal));

models = {'B0 train mean', 'B1 persist last 1 h', 'B2 persist last 10 min', ...
          'B3 daily profile', 'M1 linear (levels)', 'M2 ridge on change', 'M3 ridge on change + met', ...
          'S1 EWMA tau 5 min', 'S2 EWMA tau 10 min', 'S3 EWMA tau 20 min', 'S4 EWMA tau 30 min', ...
          'W1 mean last 20 min', 'W2 mean last 30 min', 'S* EWMA tau chosen on val'};
lambdas = [0 1 10 100 1e3 1e4];
% Exponential smoothing (simple exponential smoothing / EWMA) of the 1-min
% bins before the origin: level = sum(w.*pm)/sum(w), w = exp(-age/tau).
% Persistence of the last 10-min bin is the tau -> 0 / single-bin limit; a
% longer tau averages more samples (less noise) but reacts more slowly.
tausFixed = [5 10 20 30];               % minutes, models S1..S4
tauGrid   = [2 5 10 15 20 30 45 60];    % searched on validation for S*

results = struct();
for nf = NOISE
    % noisy copy of the clean 3-s series, re-binned (noise added per sample)
    Xn = X; randn('seed', 1); %#ok<RAND>
    Xn(:,5) = Xn(:,5) + nf * sig * randn(size(Xn,1),1);
    Bn = bin_series(Xn, 10); Bn.pm(Bn.n < minCount) = NaN;
    Bm = bin_series(Xn, 1);  Bm.pm(Bm.n < 10) = NaN;   % 1-min bins (>= half of 20 samples)

    errs = nan(nO, 3, numel(models)); truth = nan(nO, 3);
    errsL = nan(nO, 3, numel(lambdas), 2);       % ridge-lambda search for M2/M3
    errsT = nan(nO, 3, numel(tauGrid));           % EWMA tau search for S*
    for i = 1:nO
        t0 = origins(i);
        % truth: CLEAN hourly means of the next 3 hours (the grader's truth is noise-free)
        for h = 1:3
            m = X(:,1) >= t0 + (h-1)/24 & X(:,1) < t0 + h/24;
            if sum(m) > 600, truth(i,h) = mean(X(m,5)); end
        end
        if any(~isfinite(truth(i,:))), continue; end
        w = t10 >= t0 - 3 & t10 < t0;            % 3-day training window (10-min bins)
        P = Bn.pm(w); T = t10(w); RH = Bn.rh(w); TM = Bn.tm(w);
        % met at the target hours (test_data provides this)
        metF = zeros(3,2);
        for h = 1:3
            m = X(:,1) >= t0 + (h-1)/24 & X(:,1) < t0 + h/24;
            metF(h,:) = [mean(X(m,2)) mean(X(m,3))];
        end
        pr = zeros(3, numel(models));
        pr(:,1) = mean(P, 'omitnan');
        pr(:,2) = mean(P(end-5:end), 'omitnan');
        pr(:,3) = last_valid(P);
        hodT = mod(floor(T*24), 24);
        for h = 1:3
            hh = mod(floor((t0 + (h-1)/24)*24), 24);
            pr(h,4) = mean(P(hodT == hh), 'omitnan');
        end
        % regression models, fitted on training pairs inside the window
        [F, Y, Fq] = make_pairs(P, T, RH, TM, t0, metF);
        for h = 1:3
            pr(h,5) = fit_predict(F.lev{h}, Y.lev{h}, Fq.lev(h,:), 0, true);
            for li = 1:numel(lambdas)
                errsL(i,h,li,1) = Fq.last + fit_predict(F.chg{h}, Y.chg{h}, Fq.chg(h,:), lambdas(li), false) - truth(i,h);
                errsL(i,h,li,2) = Fq.last + fit_predict(F.met{h}, Y.chg{h}, Fq.met(h,:), lambdas(li), false) - truth(i,h);
            end
        end
        errs(i,:,1:5) = permute(pr(:,1:5) - truth(i,:)', [3 1 2]);
        % smoothing models on the 1-min bins of the last 3 h before t0
        r = Bm.t >= t0 - 3/24 & Bm.t < t0 & isfinite(Bm.pm);
        age = (t0 - Bm.t(r)) * 1440; pmr = Bm.pm(r);      % minutes before origin
        for j = 1:numel(tausFixed)
            errs(i,:,7+j) = ewma(pmr, age, tausFixed(j)) - truth(i,:);
        end
        errs(i,:,12) = mean(pmr(age <= 20)) - truth(i,:);
        errs(i,:,13) = mean(pmr(age <= 30)) - truth(i,:);
        for j = 1:numel(tauGrid)
            errsT(i,:,j) = ewma(pmr, age, tauGrid(j)) - truth(i,:);
        end
    end
    % choose ridge lambda on VALIDATION origins only
    for mm = 1:2
        score = squeeze(sqrt(mean(mean(errsL(isVal,:,:,mm).^2, 2, 'omitnan'), 1, 'omitnan')));
        [~, best] = min(score); bestL(mm) = lambdas(best); %#ok<SAGROW>
        errs(:,:,5+mm) = errsL(:,:,best,mm);
    end
    scoreT = squeeze(sqrt(mean(mean(errsT(isVal,:,:).^2, 2, 'omitnan'), 1, 'omitnan')));
    [~, bt] = min(scoreT); bestTau = tauGrid(bt);
    errs(:,:,14) = errsT(:,:,bt);
    key = sprintf('noise_%02d', round(nf*10));
    results.(key).errs = errs; results.(key).truth = truth; results.(key).lambda = bestL;
    results.(key).tau = bestTau; results.(key).tauGrid = tauGrid; results.(key).tauValScore = scoreT;

    fprintf('\n    noise %.1f sigma   (chosen on validation: ridge lambda M2 %g, M3 %g; EWMA tau %g min)\n', nf, bestL, bestTau);
    fprintf('    %-26s %10s %10s   test NRMSE by horizon h=1/2/3\n', 'model', 'val NRMSE', 'test NRMSE');
    for mdl = 1:numel(models)
        e = errs(:,:,mdl); ok = all(isfinite(e),2) & all(isfinite(truth),2);
        nv = nr(e(ok & isVal',:), truth(ok & isVal',:));
        nt = nr(e(ok & ~isVal',:), truth(ok & ~isVal',:));
        nh = arrayfun(@(h) nr(e(ok & ~isVal',h), truth(ok & ~isVal',h)), 1:3);
        fprintf('    %-26s %10.4f %10.4f   %.3f / %.3f / %.3f\n', models{mdl}, nv, nt, nh);
    end
end

if MAKE_FIGS
    e = results.noise_00.errs; tr = results.noise_00.truth;
    f = figure('Color','w','Position',[50 50 1200 380]);
    plot(origins, tr(:,1), 'k-', 'LineWidth', 1.2); hold on;
    plot(origins, tr(:,1) + e(:,1,3), 'b-'); plot(origins, tr(:,1) + e(:,1,7), 'r-');
    xline_compat(origins(find(~isVal,1)));
    datetick('x', 'mm/dd HH'); grid on; ylabel('PM2.5');
    legend('truth (next hour)', 'persistence 10 min', 'M3 ridge + met', 'val | test');
    title(sprintf('Foshan static #%d: 1-h-ahead forecasts', SENSOR));
    print(f, fullfile(FIGDIR, sprintf('st_s%d_forecasts.png', SENSOR)), '-dpng', '-r150');
end

% keep everything needed for the cross-sensor comparison (st_compare_sensors.m)
if exist('SAVE_RESULTS', 'var') && SAVE_RESULTS
    out = fullfile(ROOT, 'short_term', sprintf('results_s%d.mat', SENSOR));
    save(out, 'results', 'models', 'origins', 'isVal', 'SENSOR', 'NOISE', '-v7');
    fprintf('    saved %s\n', out);
end

%% =========================== helpers ======================================
function B = bin_series(X, binMin)
bd = binMin / 1440;
b = floor(X(:,1) / bd); b0 = min(b); idx = b - b0 + 1; nb = max(idx);
B.n  = accumarray(idx, 1, [nb 1]);
B.pm = accumarray(idx, X(:,5), [nb 1]) ./ B.n;
B.rh = accumarray(idx, X(:,2), [nb 1]) ./ B.n;
B.tm = accumarray(idx, X(:,3), [nb 1]) ./ B.n;
B.t  = ((b0:(b0+nb-1))' + 0.5) * bd;              % bin centres
B.pm(B.n == 0) = NaN; B.rh(B.n == 0) = NaN; B.tm(B.n == 0) = NaN;
end

function [F, Y, Fq] = make_pairs(P, T, RH, TM, t0, metF)
% Training pairs inside the 3-day window: every 10-min origin s that still
% has 3 h of data after it. Target for horizon h = mean of the six 10-min
% bins in hour h after s.  Features (all known at the origin):
%   last   = PM in the last 10-min bin            (level)
%   tr1h   = last - mean of the last hour          (trend)
%   anom   = last - mean of the window so far      (mean reversion)
%   dRH/dT = met change between origin hour and target hour
%   hs/hc  = hour of day of the target (sin, cos)
n = numel(P); F.lev = cell(1,3); F.chg = F.lev; F.met = F.lev; Y.lev = F.lev; Y.chg = F.lev;
mu = mean(P, 'omitnan');
lastP = P; tr1 = P - movmean_back(P, 6); anom = P - mu;
rhNow = movmean_back(RH, 6); tmNow = movmean_back(TM, 6);
for h = 1:3
    rows = (7:(n - 6*h))';
    tgt = zeros(numel(rows),1); rhF = tgt; tmF = tgt;
    for j = 1:numel(rows)
        k = rows(j) + 6*(h-1) + (1:6);
        tgt(j) = mean(P(k), 'omitnan'); rhF(j) = mean(RH(k), 'omitnan'); tmF(j) = mean(TM(k), 'omitnan');
    end
    th = mod(T(rows) + (h - 0.5)/24, 1) * 2 * pi;
    base = [lastP(rows) tr1(rows) anom(rows)];
    hrf  = [sin(th) cos(th)];
    met  = [rhF - rhNow(rows), tmF - tmNow(rows)];
    ok = all(isfinite([base met tgt]), 2);
    F.lev{h} = base(ok,1:2);  Y.lev{h} = tgt(ok);   % anom = last - const: collinear with last
    F.chg{h} = [base(ok,2:3) hrf(ok,:)];  Y.chg{h} = tgt(ok) - lastP(rows(ok));
    F.met{h} = [base(ok,2:3) hrf(ok,:) met(ok,:)];
end
% query features at the real origin t0
last = last_valid(P); i = find(isfinite(P), 1, 'last');
trq = last - mean(P(max(1,i-5):i), 'omitnan'); anq = last - mu;
rh0 = mean(RH(max(1,n-5):n), 'omitnan'); tm0 = mean(TM(max(1,n-5):n), 'omitnan');
Fq.last = last; Fq.lev = repmat([last trq], 3, 1);
thq = mod(t0 + ((1:3)' - 0.5)/24, 1) * 2 * pi;
Fq.chg = [repmat([trq anq], 3, 1) sin(thq) cos(thq)];
Fq.met = [Fq.chg, metF(:,1) - rh0, metF(:,2) - tm0];
end

function p = fit_predict(F, y, fq, lambda, intercept)
% (ridge) least squares on standardized features.
% intercept = false for the CHANGE models: a free intercept would learn the
% average drift of this particular 3-day window and carry it forward as a
% bias; without it, large lambda shrinks exactly to persistence.
mu = mean(F, 1); sd = std(F, 0, 1); sd(sd == 0) = 1;
Z = (F - mu) ./ sd; n = size(Z,1);
zq = (fq - mu) ./ sd; zq = max(min(zq, 4), -4);   % no wild extrapolation
if intercept
    A = [ones(n,1) Z]; aq = [1 zq];
    R = lambda * eye(size(A,2)); R(1,1) = 0;
else
    A = Z; aq = zq; R = lambda * eye(size(A,2));
end
b = (A'*A + R) \ (A'*y);
p = aq * b;
end

function m = movmean_back(x, k)
% trailing mean over the last k samples (inclusive), NaN-aware
m = nan(size(x));
for i = 1:numel(x)
    s = x(max(1, i-k+1):i); s = s(isfinite(s));
    if ~isempty(s), m(i) = mean(s); end
end
end

function m = ewma(p, age, tau)
% exponentially weighted mean of samples p that are age minutes old
w = exp(-age / tau);
m = sum(w .* p) / sum(w);
end

function v = last_valid(x)
i = find(isfinite(x), 1, 'last'); v = x(i);
end

function y = lagv(x, L)
y = [nan(L,1); x(1:end-L)];
end

function e = nr(err, truth)
e = sqrt(mean(err(:).^2)) / sqrt(mean(truth(:).^2));
end

function r = pearson(a, b)
v = isfinite(a) & isfinite(b); a = a(v); b = b(v);
if numel(a) < 3, r = NaN; return; end
a = a - mean(a); b = b - mean(b);
r = sum(a.*b) / sqrt(sum(a.^2) * sum(b.^2));
end

function r = spearman(a, b)
v = isfinite(a) & isfinite(b);
r = pearson(ranks(a(v)), ranks(b(v)));
end

function rk = ranks(x)
[~, ~, j] = unique(x(:)); cnt = accumarray(j, 1);
avg = cumsum(cnt) - (cnt - 1)/2; rk = avg(j);
end

function td = dewpoint(T, RH)
a = 17.62; b = 243.12;
g = log(min(max(RH,1),100)/100) + a*T./(b+T);
td = b*g./(a-g);
end

function xline_compat(x)
yl = ylim; plot([x x], yl, 'k--');
end
