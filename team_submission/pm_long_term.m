function pred_pm2d5 = predict_long_term(train_data, test_data, var_level)
%PREDICT_LONG_TERM  24-h hourly PM2.5 forecast at held-out static locations.
%
%   pred_pm2d5 = predict_long_term(train_data, test_data, var_level)
%
%   train_data                  : struct loaded from separated_train_data_*.mat, with fields
%                                 train_data_static and train_data_mobile (any field names
%                                 containing 'static' / 'mobile' work). Each holds a table, or a
%                                 cell array of per-sensor tables, with columns
%                                 time, hmd, spd, tmp, pm2d5, lat, lon
%   test_data                   : table with columns time, hmd, spd, tmp, lat, lon (no pm2d5)
%   var_level                   : 0, 5 or 10 (training PM2.5 noise SD = 0 / 0.5 / 1.0 x clean SD)
%   pred_pm2d5                  : M-by-1 column, row i = prediction for row i of test_data
%
% MODEL: ridge regression on sliding windows
%   (historyDays in -> next 24 hourly PM2.5 values out, one coefficient set per lead hour).
%   Training targets = every static sensor. Each target's inputs come only from the OTHER
%   static sensors (inverse-distance weighted) plus the pooled mobile data, so the model
%   learns to predict a location from its neighbours, exactly like the held-out test sites.
%
%   For each lead hour h = 1..24:
%     PM2.5(h) = b0 + b1*weekMean + b2*latest_dev + b3*dailyPattern(h) + b4*lastDay_dev
%                   + b5*hmd(h) + b6*tmp(h) + b7*spd(h) + b8*north_km + b9*east_km
%
%     weekMean     = IDW neighbour mean PM2.5 over the history window before the origin
%     latest_dev   = latest 5-min neighbour reading (static + mobile) minus weekMean
%     dailyPattern = neighbours' value at the same clock hour on previous days minus weekMean
%     lastDay_dev  = last-24-h neighbour mean minus weekMean
%     hmd/tmp/spd  = target-window means of the target location (supplied in test_data)
%     north/east   = target location in km from the static sensors' centre
%
%   Target at time t = mean of observations in (t-60 min, t]  (window END timestamp).
%
% Toolboxes: none required. Uses Signal Processing Toolbox (butter/filtfilt) for the
% low-pass filter if it is installed and licensed; otherwise falls back to a moving mean.

%% ======================= Noise level =======================
if nargin < 3 || isempty(var_level), var_level = 0; end
switch var_level
    case 0,  lambda = 1;    % clean labels: light shrinkage
    case 5,  lambda = 3;    % noise SD = 0.5 x clean SD: shrink more
    case 10, lambda = 10;   % noise SD = 1.0 x clean SD: shrink most
    otherwise
        error('var_level must be 0, 5 or 10 (got %g).', var_level);
end
% These lambda values are starting points: tune them with training-only validation.

%% ======================= Settings =======================
historyDays   = 2;      % days of input per training window (only 7 days of training exist)
horizonH      = 24;     % forecast hours
originStepMin = 30;     % spacing of training window origins (min)
nowWin        = 5;      % minutes averaged for the static "latest" value
mobWin        = 5;      % minutes averaged for the mobile "latest" value
minBlockMin   = 15;     % min minutes with data for an hourly training target to count
minHistFrac   = 0.5;    % min fraction of history minutes with neighbour data
idwPow        = 2;      % inverse-distance weighting power
idwFloorKm    = 0.1;    % distance floor (km) so a very close sensor can't get infinite weight
pmMax         = 1000;   % impossible PM2.5 values above this -> NaN
locRound      = 4;      % decimals used to group static readings into sensors (~11 m)
lp_period     = 60;     % low-pass cutoff period (min)
lp_order      = 4;      % Butterworth order
maxGapFill    = 10;     % interpolate gaps up to this many minutes before filtering

%% ======================= Split train_data into static / mobile =======================
fn = fieldnames(train_data);
iS = find(contains(lower(fn), 'static'));
iM = find(contains(lower(fn), 'mobile'));
if numel(iS) ~= 1 || numel(iM) ~= 1
    error('train_data must have one field containing "static" and one containing "mobile" (found: %s).', ...
        strjoin(fn', ', '));
end
train_static = train_data.(fn{iS});
train_mobile = train_data.(fn{iM});

%% ======================= Inputs & time grid =======================
train_static = cleanTable(asTable(train_static), pmMax);
train_mobile = cleanTable(asTable(train_mobile), pmMax);

% Forecast origin = end of training. First target is 1 h after the origin.
s0 = min(test_data.time) - hours(1);
t0 = dateshift(min(train_static.time), 'start', 'minute');

% Minute grid: row r = bin [t0 + (r-1) min, t0 + r min). Rows 1..nT cover data before s0.
nT         = round(minutes(s0 - t0));
b0         = nT;                    % last input row = origin row for the test forecast
histMin    = historyDays * 1440;
horizonMin = horizonH * 60;
if nT - horizonMin < histMin
    error('Training record too short for %d-day history + %d-h horizon.', historyDays, horizonH);
end

%% ======================= Static sensors -> minute grid =======================
% Inputs have no device ID: static sensors are identified by their fixed location.
% Co-located sensors are merged automatically (same rounded lat/lon).
[~, ~, sid] = unique(round([train_static.lat train_static.lon], locRound), 'rows');
nS = max(sid);

kS  = floor(minutes(train_static.time - t0)) + 1;
inG = kS >= 1 & kS <= nT;

[PMs, PMc, HMs, HMc, TPs, TPc, SPs, SPc] = deal(zeros(nT, nS));
latS = nan(1, nS);  lonS = nan(1, nS);
for c = 1:nS
    r = inG & sid == c;
    [PMs(:,c), PMc(:,c)] = binSum(kS(r), train_static.pm2d5(r), nT);
    [HMs(:,c), HMc(:,c)] = binSum(kS(r), train_static.hmd(r),   nT);
    [TPs(:,c), TPc(:,c)] = binSum(kS(r), train_static.tmp(r),   nT);
    [SPs(:,c), SPc(:,c)] = binSum(kS(r), train_static.spd(r),   nT);
    latS(c) = median(train_static.lat(sid == c), 'omitnan');
    lonS(c) = median(train_static.lon(sid == c), 'omitnan');
end
PMm = PMs ./ PMc;                   % minute-mean PM2.5 (NaN where no data)

%% ======================= Remove faulty static sensors =======================
% Median PM2.5 is an outlier among sensors (robust to zero-mean training noise).
medPM = median(PMm, 1, 'omitnan');
bad   = isnan(medPM);
if nnz(~bad) >= 5
    bad = bad | isoutlier(medPM);
end
if nnz(~bad) < 3                    % never drop so many that nothing is left
    bad = isnan(medPM);
end
keep = ~bad;
PMs = PMs(:,keep);  PMc = PMc(:,keep);  PMm = PMm(:,keep);
HMs = HMs(:,keep);  HMc = HMc(:,keep);
TPs = TPs(:,keep);  TPc = TPc(:,keep);
SPs = SPs(:,keep);  SPc = SPc(:,keep);
latS = latS(keep);  lonS = lonS(keep);
nS   = nnz(keep);

%% ======================= Smoothed series for the INPUT features =======================
LP  = lowpassCols(PMm, lp_period, lp_order, maxGapFill);    % low-passed PM2.5 (denoised)
NOW = movmean(LP, [nowWin-1 0], 1, 'omitnan');              % trailing "latest" value

% Mobile data: no device ID, so pool all mobile readings into one neighbour signal.
if ~isempty(train_mobile) && height(train_mobile) > 0
    kM = floor(minutes(train_mobile.time - t0)) + 1;
    ok = kM >= 1 & kM <= nT;
    [mS, mC] = binSum(kM(ok), train_mobile.pm2d5(ok), nT);
    pM = movmean(mS ./ mC, [mobWin-1 0], 'omitnan');
else
    pM = nan(nT, 1);
end

%% ======================= Hourly TARGETS and covariates =======================
% Exact sample mean of raw readings in (t-60, t]: hour ending at row r = rows r-59..r.
hourMean = @(s, n) movsum(s, [59 0], 1) ./ movsum(n, [59 0], 1);
Yh  = hourMean(PMs, PMc);
cov = movsum(double(PMc > 0), [59 0], 1);
Yh(cov < minBlockMin) = NaN;
HMh = hourMean(HMs, HMc);
TPh = hourMean(TPs, TPc);
SPh = hourMean(SPs, SPc);

%% ======================= Locations (km from static centre) =======================
lat0 = mean(latS);  lon0 = mean(lonS);
kmN  = 111.32;  kmE = 111.32 * cosd(lat0);
XY   = [(latS(:) - lat0) * kmN, (lonS(:) - lon0) * kmE];    % nS x 2 (north, east)
D    = sqrt((XY(:,1) - XY(:,1)').^2 + (XY(:,2) - XY(:,2)').^2);
idw  = @(d) 1 ./ max(d, idwFloorKm) .^ idwPow;

%% ======================= Build training samples =======================
bv  = (histMin : originStepMin : nT - horizonMin)';         % origin rows (last input row)
tr  = bv + (1:horizonH) * 60;                               % target rows, nB x 24
nB  = numel(bv);

[Wk, WkC, Dev, Dy, Nn, Ee] = deal(nan(nB*nS, 1));
[Pf, Y, Hum, Tmp, Spd]     = deal(nan(nB*nS, horizonH));
for j = 1:nS
    nb = setdiff(1:nS, j);                                  % neighbours = all OTHER sensors
    F  = nbFeatures(LP(:,nb), NOW(:,nb), pM, idw(D(j,nb)), histMin);
    B  = baseAt(F, bv, horizonH, historyDays);
    rr = (j-1)*nB + (1:nB);
    Wk(rr) = B.wk;  WkC(rr) = B.wkCnt;  Dev(rr) = B.dv;  Dy(rr) = B.dy;  Pf(rr,:) = B.pf;
    Y(rr,:)   = reshape(Yh(tr, j),  size(tr));
    Hum(rr,:) = reshape(HMh(tr, j), size(tr));
    Tmp(rr,:) = reshape(TPh(tr, j), size(tr));
    Spd(rr,:) = reshape(SPh(tr, j), size(tr));
    Nn(rr) = XY(j,1);  Ee(rr) = XY(j,2);
end
covFill = [mean(Hum(:), 'omitnan'), mean(Tmp(:), 'omitnan'), mean(Spd(:), 'omitnan')];
covFill(isnan(covFill)) = 0;

%% ======================= Fit: one ridge regression per lead hour =======================
% Features standardised so the penalty treats them equally; intercept not penalised.
nFeat = 9;
coef  = nan(nFeat+1, horizonH);
for h = 1:horizonH
    Xh = [Wk Dev Pf(:,h) Dy Hum(:,h) Tmp(:,h) Spd(:,h) Nn Ee];
    Xh = fillCov(Xh, covFill);
    use = all(isfinite(Xh), 2) & isfinite(Y(:,h)) & WkC >= minHistFrac * histMin;
    if nnz(use) < nFeat + 2, continue; end
    Xu = Xh(use,:);  yu = Y(use,h);
    mu = mean(Xu, 1);  sd = std(Xu, 0, 1);  sd(sd == 0) = 1;
    Z  = (Xu - mu) ./ sd;
    b  = (Z'*Z + lambda*nnz(use)*eye(nFeat)) \ (Z'*(yu - mean(yu)));
    coef(2:end,h) = b ./ sd';
    coef(1,h)     = mean(yu) - mu*coef(2:end,h);
end

%% ======================= Predict test rows (in test_data order) =======================
pred = nan(height(test_data), 1);
[locT, ~, tid] = unique([test_data.lat test_data.lon], 'rows', 'stable');
for q = 1:size(locT, 1)
    xyT = [(locT(q,1) - lat0) * kmN, (locT(q,2) - lon0) * kmE];
    d   = sqrt((XY(:,1) - xyT(1)).^2 + (XY(:,2) - xyT(2)).^2)';
    F   = nbFeatures(LP, NOW, pM, idw(d), histMin);         % all static sensors are neighbours
    B   = baseAt(F, b0, horizonH, historyDays);
    for i = find(tid == q)'
        h  = round(hours(test_data.time(i) - s0));
        h  = min(max(h, 1), horizonH);
        cv = [test_data.hmd(i) test_data.tmp(i) test_data.spd(i)];
        cv(isnan(cv)) = covFill(isnan(cv));
        x  = [B.wk B.dv B.pf(h) B.dy cv xyT];
        if all(isfinite(x)) && all(isfinite(coef(:,h)))
            pred(i) = [1 x] * coef(:,h);
        else
            pred(i) = B.wk + B.pf(h);                       % fallback: neighbour daily pattern
        end
    end
end

%% ======================= Output checks =======================
pred = max(pred, 0);                                        % PM2.5 can't be negative
fallback = median(train_static.pm2d5, 'omitnan');
if ~isfinite(fallback), fallback = 0; end
pred(~isfinite(pred)) = fallback;
pred_pm2d5 = double(real(pred(:)));
end


%% ======================= Helper functions =======================
function T = asTable(T)
% Accept a table, or a cell array of per-device tables (stacked into one table).
if iscell(T)
    T = vertcat(T{:});
end
end

function T = cleanTable(T, pmMax)
% Remove physically impossible values. Negative PM2.5 is KEPT: at noise levels 5/10
% the training labels are perturbed by zero-mean noise, so dropping negatives biases upward.
if isempty(T) || height(T) == 0, return; end
T = sortrows(T, 'time');
T.pm2d5(T.pm2d5 > pmMax) = NaN;
T.hmd(T.hmd < 0   | T.hmd > 100) = NaN;
T.tmp(T.tmp < -30 | T.tmp > 50)  = NaN;
T.spd(T.spd < 0) = NaN;
end

function [s, n] = binSum(k, x, nT)
% Sum and count of non-NaN values of x in each minute bin k (1..nT).
ok = ~isnan(x);
s  = accumarray(k(ok), x(ok), [nT 1]);
n  = accumarray(k(ok), 1,     [nT 1]);
end

function out = wmeanRows(X, w)
% Row-wise weighted mean of X with weights w (1 x nCols), ignoring NaNs.
M = ~isnan(X);
X(~M) = 0;
num = X * w(:);
den = double(M) * w(:);
out = num ./ den;
out(den == 0) = NaN;
end

function F = nbFeatures(LP, NOW, pM, w, histMin)
% Neighbour series (IDW-weighted across the given static columns).
nb      = wmeanRows(LP,  w);
nowS    = wmeanRows(NOW, w);
F.wk    = movmean(nb, [histMin-1 0], 'omitnan');            % trailing history mean
F.wkCnt = movsum(double(~isnan(nb)), [histMin-1 0]);        % minutes it used
F.dy    = movmean(nb, [1439 0], 'omitnan');                 % trailing 24-h mean
F.blk   = movmean(nb, [59 0], 'omitnan');                   % hour ending at each row
F.pl    = mean([nowS pM], 2, 'omitnan');                    % latest static + mobile
end

function B = baseAt(F, bv, horizonH, historyDays)
% Origin-time features for origin rows bv (column vector). Uses only rows <= bv
% (dailyPattern looks at previous days, which are always before the origin).
bv      = bv(:);
B.wk    = F.wk(bv);
B.wkCnt = F.wkCnt(bv);
B.dv    = F.pl(bv) - B.wk;  B.dv(isnan(B.dv)) = 0;          % no recent data -> no correction
B.dy    = F.dy(bv) - B.wk;  B.dy(isnan(B.dy)) = 0;
B.pf    = zeros(numel(bv), horizonH);
for h = 1:horizonH
    idx = bv + h*60 - (1:historyDays)*1440;                 % same clock hour, previous days
    v   = reshape(F.blk(idx), size(idx));
    p   = mean(v, 2, 'omitnan') - B.wk;
    p(isnan(p)) = 0;
    B.pf(:,h) = p;
end
end

function X = fillCov(X, covFill)
% Fill missing humidity / temperature / speed (columns 5-7) with training means.
for c = 1:3
    m = isnan(X(:, 4+c));
    X(m, 4+c) = covFill(c);
end
end

function lp = lowpassCols(Y, period, order, maxGap)
% Zero-phase Butterworth low-pass per column (moving-mean fallback without the toolbox).
lp = nan(size(Y));
useButter = exist('butter', 'file') == 2 && exist('filtfilt', 'file') == 2 && ...
            license('test', 'Signal_Toolbox');
if useButter
    [bL, aL] = butter(order, (1/period) / 0.5);             % fs = 1/min, Nyquist = 0.5
end
minLen = max(3*order + 1, 2*period);
for c = 1:size(Y, 2)
    y   = fillmissing(Y(:,c), 'linear', 'MaxGap', maxGap, 'EndValues', 'none');
    ok  = ~isnan(y);
    seg = cumsum([ok(1); diff(ok) == 1]) .* ok;
    for s = 1:max(seg)
        k = seg == s;
        if useButter && nnz(k) >= minLen
            lp(k,c) = filtfilt(bL, aL, y(k));
        else
            lp(k,c) = movmean(y(k), period, 'omitnan');
        end
    end
end
