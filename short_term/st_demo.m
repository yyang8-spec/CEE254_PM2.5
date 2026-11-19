%ST_DEMO  Short-term prediction: live walkthrough for the TA discussion.
%
% Open this file in MATLAB and run it ONE SECTION AT A TIME
% (click inside a section, then "Run Section" or Ctrl+Enter).
% Every section finishes in seconds to ~1 minute. The long validations
% (~40 min) were run beforehand and section 4 loads their saved results.
%
%   1. Data and cleaning        (live)
%   2. Correlation check        (live)
%   3. Model comparison         (saved: single-sensor study, 5 sensors)
%   4. Final model performance  (saved: leave-one-sensor-out, dev/test split)
%   5. One forecast, step by step (live)
%   6. Competition predictions  (live, 11/16 data)
%
% Needs: data/processed/devices_foshan.mat (run data_cleaning/export_device_matrices.m once)
%        data/competition/*.mat (section 6)
% Run from the repo root (the folder that contains src/ and short_term/).

%% 0. Setup
clear; clc; close all;
ROOT = pwd;
addpath(fullfile(ROOT, 'src')); addpath(fullfile(ROOT, 'validation')); addpath(fullfile(ROOT, 'short_term'));
S = load(fullfile(ROOT, 'data', 'processed', 'devices_foshan.mat'));
dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
pearson = @(a, b) corr_nan(a, b);
fprintf('Foshan: %d devices (%d static, %d mobile), %d rows in total\n', ...
    numel(dev), sum(is_static), sum(~is_static), sum(cellfun(@(D) size(D,1), dev)));

%% 1. DATA AND CLEANING
% Columns of every device matrix: [datenum hmd tmp spd pm2d5 lat lon]
fprintf('\n=== 1a. Per-device summary ===\n');
fprintf('%-10s %9s %7s %7s %8s %12s %10s\n', 'device', 'rows', 'PM mean', 'PM max', 'NaN PM', 'gaps > 1 h', 'max gap h');
for i = 1:numel(dev)
    D = dev{i}; gap = diff(D(:,1)) * 24;
    if is_static(i), nm = sprintf('static %d', i); else, nm = sprintf('mobile %d', i - sum(is_static)); end
    fprintf('%-10s %9d %7.1f %7.0f %8d %12d %10.1f\n', nm, size(D,1), mean(D(:,5)), max(D(:,5)), ...
        sum(isnan(D(:,5))), sum(gap > 1), max(gap));
end
allpm = cell2mat(cellfun(@(D) D(:,5), dev(:), 'UniformOutput', false));
med = median(allpm); s = 1.4826 * median(abs(allpm - med)); thr = med + 12 * s;
fprintf('\n=== 1b. Spike rule: PM > median + 12 x robust sd = %.0f ug/m3 ===\n', thr);
fprintf('  removes %d of %d rows (%.2f%%); static rows removed: %d\n', sum(allpm > thr), numel(allpm), ...
    100 * mean(allpm > thr), sum(cell2mat(cellfun(@(D) D(:,5), dev(st)', 'UniformOutput', false)) > thr));
fprintf('  negative values are NOT clipped (the robustness test adds zero-mean noise)\n');

% 1c. Static vs mobile without a device ID: the parked-vehicle bug, live.
t0 = datenum(2018,10,15,3,0,0);            % a window where a vehicle parks overnight
[tr, te, y] = make_task(dev, is_static, 1, t0, 1, 0, 1);
[~, ~, infoFix] = pm_short_term(tr, te);
[~, ~, infoBug] = pm_short_term(tr, te, struct('static_min_frac', 0));
fprintf('\n=== 1c. Static-site detection, window ending %s (static #1 held out) ===\n', datestr(t0));
fprintf('  with the parked-vehicle rule:    %3d static sites (correct: 4)\n', infoFix.n_sites);
fprintf('  without it:                      %3d static sites (GPS jitter of a parked vehicle)\n', infoBug.n_sites);

figure('Color', 'w', 'Name', '1. Data');
D = dev{st(3)}; plot(D(:,1), D(:,5), '.', 'MarkerSize', 2); hold on;
b = floor(D(:,1) * 144); [ub, ~, gb] = unique(b);
plot(ub / 144, accumarray(gb, D(:,5), [], @mean), 'r-', 'LineWidth', 1);
datetick('x', 'mm/dd'); grid on; ylabel('PM2.5 (\mug/m^3)');
legend('raw 3-s samples', '10-min mean'); title('Foshan static #3');

%% 2. CORRELATION CHECK (hourly city level from the static sensors)
X = cell2mat(cellfun(@(D) D, dev(st)', 'UniformOutput', false));
h = floor(X(:,1) * 24); [uh, ~, g] = unique(h);
hg = (uh(1):uh(end))'; n = numel(hg); k = uh - uh(1) + 1;
pm = nan(n,1); rh = pm; tm = pm;
pm(k) = accumarray(g, X(:,5), [], @mean); rh(k) = accumarray(g, X(:,2), [], @mean); tm(k) = accumarray(g, X(:,3), [], @mean);
hod = mod(hg, 24); lag = @(x, L) [nan(L,1); x(1:end-L)];
names = {'PM 1 h ago', 'PM 3 h ago', 'PM 24 h ago', 'temperature', 'humidity', 'hour of day (cos)'};
feats = {lag(pm,1), lag(pm,3), lag(pm,24), tm, rh, cos(2*pi*hod/24)};
fprintf('\n=== 2a. Pearson r with hourly PM2.5 (Foshan, %d h) ===\n', sum(isfinite(pm)));
r = zeros(numel(names),1);
for i = 1:numel(names), r(i) = pearson(pm, feats{i}); fprintf('  %-18s r = %6.3f\n', names{i}, r(i)); end
v = isfinite(pm) & isfinite(rh) & isfinite(tm);
a1 = pearson(pm(v), rh(v)); a2 = pearson(pm(v), tm(v)); a3 = pearson(rh(v), tm(v));
fprintf('  partial r(PM, humidity | temperature) = %.3f\n', (a1 - a2*a3) / sqrt((1-a2^2)*(1-a3^2)));
fprintf('\n=== 2b. The forecasting question: what predicts the CHANGE over the next 1-3 h? ===\n');
for hh = 1:3
    dy = [pm(1+hh:end) - pm(1:end-hh); nan(hh,1)];
    dtm = [tm(1+hh:end) - tm(1:end-hh); nan(hh,1)];
    tr1 = lag(pm,0) - lag(pm,1);
    fprintf('  h = %d:  r(change, last-hour trend) = %6.3f   r(change, temp change) = %6.3f   r(change, hour cos) = %6.3f\n', ...
        hh, pearson(dy, tr1), pearson(dy, dtm), pearson(dy, cos(2*pi*hod/24)));
end
fprintf('  -> PM now predicts PM next hour (r ~ 0.96). The most recent 1-h trend is moderately\n');
fprintf('     related to the next change (r ~ 0.44 at h = 1, falling with h); temperature change and\n');
fprintf('     hour of day are not. Section 3 tests whether a trend term helps OUT OF SAMPLE: it does not.\n');
figure('Color', 'w', 'Name', '2. Correlation');
barh(r); set(gca, 'YTick', 1:numel(names), 'YTickLabel', names); xlim([-1 1]); grid on;
xlabel('Pearson r with hourly PM2.5'); title('Foshan, hourly city level');

%% 3. MODEL COMPARISON (single-sensor study, all 5 static sensors; saved)
% Each sensor: forecast every hour from its own last 3 days; first half of
% the origins = validation (choose lambda, tau), second half = test.
% (Regenerate with:  run('short_term/st_compare_sensors.m')  ~30 min)
SKIP_RUN = true; MAKE_FIGS = true; %#ok<NASGU>
run(fullfile(ROOT, 'short_term', 'st_compare_sensors.m'));
fprintf('\n  -> ridge (lambda chosen on validation) wins on validation but LOSES on test\n');
fprintf('     on every sensor: it overfits one 3-day window. Persistence/smoothing kept.\n');

%% 4. FINAL MODEL PERFORMANCE (leave-one-sensor-out, dev/test split; saved)
% Hold out one static sensor at a time (the test sites have no history),
% forecast every 3 h, add 0 / 0.5 / 1.0 sigma noise to training PM only.
% tau chosen on the FIRST half of the origins, scored once on the SECOND half.
% (Regenerate with:  run('short_term/st_validate.m')  ~40 min)
run(fullfile(ROOT, 'short_term', 'st_validate_summary.m'));
run(fullfile(ROOT, 'short_term', 'st_plot_validation.m'));

%% 5. ONE FORECAST, STEP BY STEP (live)
t0 = datenum(2018,10,13,12,0,0); hold_out = st(3);
[tr, te, y] = make_task(dev, is_static, 1, t0, hold_out, 0, 1);
[p, sd, info] = pm_short_term(tr, te);
pb = baseline_pred(tr, te, 1, 'nearest_persist');
fprintf('\n=== 5. Forecast from %s, static #3 held out ===\n', datestr(t0));
fprintf('  training rows %d -> kept %s | static sites found %d | level source: %s\n', ...
    size(tr,1), info.clean.kept, info.n_sites, info.level_source);
fprintf('  city level now %.1f, site offsets %s\n', info.level, mat2str(info.site_offsets, 2));
fprintf('  %-6s %8s %10s %12s %10s\n', 'hour', 'truth', 'ours', '+/- 1 sd', 'baseline');
for i = 1:3, fprintf('  h = %d  %8.1f %10.1f %12.1f %10.1f\n', i, y(i), p(i), sd(i), pb(i)); end

%% 6. COMPETITION PREDICTIONS (11/16 data, short-term, 3 noise levels)
TASKS = 1; run(fullfile(ROOT, 'run_competition.m'));
T = load(fullfile(ROOT, 'data', 'competition', 'test_data_short_term_0_var.mat'));
P = load(fullfile(ROOT, 'submissions', 'pred_short_term_0_var.mat'));
disp(table(T.test_data.time, T.test_data.lat, T.test_data.lon, P.pred_pm2d5, P.pred_sd, ...
    'VariableNames', {'time_hour_end', 'lat', 'lon', 'pred_pm2d5', 'pred_sd'}));

%% helper (MATLAB R2016b+ allows local functions at the end of a script)
function r = corr_nan(a, b)
v = isfinite(a) & isfinite(b); a = a(v) - mean(a(v)); b = b(v) - mean(b(v));
r = sum(a .* b) / sqrt(sum(a.^2) * sum(b.^2));
end
