function pred_pm2d5 = pm2d5_interp_model(train_data, test_data, opts)
%PM2D5_INTERP_MODEL  Space-time kernel interpolation of PM2.5 (problem_type 3).
%
%   pred_pm2d5 = pm2d5_interp_model(train_data, test_data)
%   pred_pm2d5 = pm2d5_interp_model(train_data, test_data, opts)
%
%   train_data : P x 7  [time, humidity, temperature, speed, pm2d5, lat, lon]
%   test_data  : M x 6  [time, humidity, temperature, speed, lat, lon]
%   pred_pm2d5 : M x 1
%
%   Each prediction is a weighted average of the training readings, where
%   the weight falls off with distance from the test location (Gaussian,
%   bandwidth opts.hs in km) and with time from the test time (Gaussian,
%   bandwidth opts.ht in minutes). This is kernel smoothing
%   applied in space and time together.
%
%   Steps:
%     1. Average raw readings into 1-minute, ~100 m bins (cuts noise and size).
%     2. Drop fixed sites whose median PM2.5 is less than half or more than
%        twice the overall median (catches a drifting sensor, such as
%        Tianjin static sensor 6 after early May).
%     3. Kernel-weighted average for each test row.
%
%   Weather columns are not used: they did not improve predictions in the
%   feature-combination tests.

if nargin < 3, opts = struct(); end
hs        = getOpt(opts, 'hs', 1.5);           % spatial bandwidth (km)
ht        = getOpt(opts, 'ht', 30);            % temporal bandwidth (minutes)
useFilter = getOpt(opts, 'siteFilter', true);  % drop drifting fixed sites

%%\ 1. Clean and convert times to minutes
[tTrain, tTest] = toMinutes(train_data(:, 1), test_data(:, 1));
pm  = train_data(:, 5);
lat = train_data(:, 6);
lon = train_data(:, 7);

ok = isfinite(tTrain) & isfinite(pm) & isfinite(lat) & isfinite(lon);
tTrain = tTrain(ok);  pm = pm(ok);  lat = lat(ok);  lon = lon(ok);

if isempty(pm)
    pred_pm2d5 = NaN(size(test_data, 1), 1);
    return
end

%%\ 2. Average into 1-minute, ~100 m bins
minuteKey = floor(tTrain - min(tTrain));
latKey    = round(lat / 0.001);
lonKey    = round(lon / 0.001);
[keys, ~, g] = unique([minuteKey, latKey, lonKey], 'rows');

nBin   = accumarray(g, 1);
binPM  = accumarray(g, pm)     ./ nBin;
binT   = accumarray(g, tTrain) ./ nBin;
binLat = accumarray(g, lat)    ./ nBin;
binLon = accumarray(g, lon)    ./ nBin;

%%\ 3. Drop fixed sites that disagree strongly with everyone else
if useFilter
    [~, ~, site] = unique(keys(:, 2:3), 'rows');
    siteCount = accumarray(site, 1);              % minutes of data per ~100 m cell
    siteMed   = accumarray(site, binPM, [], @median);
    allMed    = median(binPM);
    badSite   = siteCount >= 1000 & ...
                (siteMed < 0.5 * allMed | siteMed > 2 * allMed);
    keep = ~badSite(site);
    if any(keep)
        binPM = binPM(keep);  binT = binT(keep);
        binLat = binLat(keep);  binLon = binLon(keep);
    end
end

%%\ 4. Kernel-weighted average for each test row
kmPerDegLon = 111.32 * cosd(mean(binLat));
kmPerDegLat = 110.57;

M = size(test_data, 1);
pred_pm2d5 = NaN(M, 1);

for i = 1:M
    dt = binT - tTest(i);
    near = abs(dt) <= 4 * ht;                 % weights beyond 4*ht are ~0
    if ~any(near), near = true(size(dt)); end

    dx = (binLon(near) - test_data(i, 6)) * kmPerDegLon;
    dy = (binLat(near) - test_data(i, 5)) * kmPerDegLat;
    w  = exp(-0.5 * (dx.^2 + dy.^2) / hs^2 - 0.5 * (dt(near) / ht).^2);

    if sum(w) < 1e-12
        % No readings close in space: fall back to time weighting only
        w = exp(-0.5 * (dt(near) / ht).^2);
    end
    pred_pm2d5(i) = sum(w .* binPM(near)) / sum(w);
end
end


%%\ ---------------- Helpers ----------------
function v = getOpt(opts, name, default)
if isfield(opts, name), v = opts.(name); else, v = default; end
end

function [tTrainMin, tTestMin] = toMinutes(tTrain, tTest)
% Converts numeric times to minutes. Detects the unit from the size of the
% values: POSIX milliseconds, POSIX seconds, or MATLAB datenum (days).
ref = median(tTrain(isfinite(tTrain)));
if ref > 1e11
    scale = 1 / 60000;      % POSIX milliseconds
elseif ref > 1e8
    scale = 1 / 60;         % POSIX seconds
elseif ref > 1e5
    scale = 1440;           % datenum (days)
else
    error('pm2d5_interp_model:timeUnit', ...
        'Unrecognized time units (median value %g). Check column 1.', ref);
end
tTrainMin = tTrain * scale;
tTestMin  = tTest  * scale;
end


%[appendix]{"version":"1.0"}
%---
