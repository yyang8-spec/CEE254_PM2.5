%STEP1_PREPROCESSING  Data cleaning and signal processing, with intermediate results.
%
% Prints, section by section:
%   1a per-device summary (rows, PM mean/max, missing values, gaps)
%   1b missing values and GPS errors
%   1c spike removal (robust MAD threshold) - how many rows, which devices
%   1d static vs mobile without a device ID - the parked-vehicle rule, live
%   1e faulty-site check (hourly correlation between static sensors)
%   1f binning: samples per 10-min bin and how much it reduces the noise
%   1g the full cleaning log of pm_short_term on one 3-day training window
% Saves results/step1_preprocessing.mat and figures/step1_preprocessing.png.
% Needs data/processed/devices_foshan.mat (step0_setup/export_device_matrices.m).
% Runs in under a minute. Run it whole, or one section at a time (Ctrl+Enter).

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
S = load(fullfile(P.processed, 'devices_foshan.mat'));
dev = S.dev; is_static = logical(S.is_static); st = find(is_static); mb = find(~is_static);
kinds = {'mobile', 'static'};
name = @(i) sprintf('%s %d', kinds{is_static(i) + 1}, i - (~is_static(i)) * numel(st));

%% 1a. Per-device summary
fprintf('\n===== STEP 1: DATA PREPROCESSING (Foshan, %d devices, %d rows) =====\n', numel(dev), sum(cellfun(@(D) size(D,1), dev)));
fprintf('\n--- 1a. Per-device summary ---\n');
fprintf('%-10s %9s %8s %8s %8s %8s %11s %10s\n', 'device', 'rows', 'PM mean', 'PM sd', 'PM max', 'NaN', 'gaps > 1 h', 'max gap h');
summary = zeros(numel(dev), 7);
for i = 1:numel(dev)
    D = dev{i}; gap = diff(D(:,1)) * 24;
    summary(i,:) = [size(D,1), mean(D(:,5)), std(D(:,5)), max(D(:,5)), sum(any(isnan(D),2)), sum(gap > 1), max(gap)];
    fprintf('%-10s %9d %8.1f %8.1f %8.0f %8d %11d %10.1f\n', name(i), summary(i,:));
end
fprintf('-> static sensors: continuous (no gap > 1 h). Mobile: long gaps, many overnight (cause not confirmed).\n');
fprintf('-> mobile sensors read higher on average (%.1f vs %.1f ug/m3) and have extreme maxima.\n', ...
    mean(summary(mb,2)), mean(summary(st,2)));

%% 1b. Missing values and GPS errors
allX = cell2mat(dev(:));
nanRows = sum(any(~isfinite(allX(:,[1 5 6 7])), 2));
gps0 = sum(allX(:,6) == 0 & allX(:,7) == 0);
far = sum(abs(allX(:,6) - median(allX(:,6))) > 0.5 | abs(allX(:,7) - median(allX(:,7))) > 0.5);
fprintf('\n--- 1b. Missing values and GPS ---\n');
fprintf('  rows with NaN time/PM/lat/lon: %d | GPS (0,0): %d | > 0.5 deg from median: %d\n', nanRows, gps0, far);
fprintf('  -> none in the Canvas file; the rules stay in the model for the competition data.\n');

%% 1c. Spike removal: PM > median + 12 x 1.4826 x MAD (robust sd)
pm = allX(:,5); med = median(pm); s = 1.4826 * median(abs(pm - med)); thr = med + 12 * s;
isSp = pm > thr; devId = repelem((1:numel(dev))', cellfun(@(D) size(D,1), dev(:)));
fprintf('\n--- 1c. Spike removal: threshold = %.1f + 12 x %.1f = %.0f ug/m3 ---\n', med, s, thr);
fprintf('  removed %d of %d rows (%.2f%%)\n', sum(isSp), numel(pm), 100 * mean(isSp));
for i = 1:numel(dev)
    k = sum(isSp & devId == i);
    if k > 0, fprintf('    %-10s %6d rows (max %.0f)\n', name(i), k, max(pm(devId == i))); end
end
fprintf('  static rows removed: %d.  Negative values are NOT clipped: the robustness test adds\n', sum(isSp & ismember(devId, st)));
fprintf('  zero-mean noise, and clipping its negative samples would bias every mean upward.\n');

%% 1d. Static vs mobile without a device ID (the competition matrix has none)
% A coordinate is static if: data in >= 50% of hours, median speed < 2, and
% >= 5% of the busiest coordinate's samples (the parked-vehicle rule).
t0 = datenum(2018,10,15,3,0,0);
[tr, te] = make_task(dev, is_static, 1, t0, st(1), 0, 1);
[~, ~, infoFix] = pm_short_term(tr, te);
[~, ~, infoBug] = pm_short_term(tr, te, struct('static_min_frac', 0));
fprintf('\n--- 1d. Static-site detection, 3-day window ending %s (static 1 held out) ---\n', datestr(t0));
fprintf('  with the parked-vehicle rule:   %3d static sites   (truth: 4)\n', infoFix.n_sites);
fprintf('  without it:                     %3d static sites   (a parked vehicle''s GPS jitter)\n', infoBug.n_sites);

%% 1e. Faulty-site check: hourly correlation between static sensors
Hm = nan(24*10, numel(st)); h0 = floor(min(cellfun(@(D) D(1,1), dev(st))) * 24);
for j = 1:numel(st)
    D = dev{st(j)}; hh = floor(D(:,1) * 24) - h0 + 1;
    Hm(1:max(hh), j) = accumarray(hh, D(:,5), [max(hh) 1], @mean, NaN);
end
Hm = Hm(any(isfinite(Hm), 2), :);
C = corrcoef(Hm(all(isfinite(Hm), 2), :));
fprintf('\n--- 1e. Hourly correlation between the static sensors (drop a site if < 0.7) ---\n');
disp(round(C * 1000) / 1000);
fprintf('  -> min off-diagonal r = %.3f: all Foshan sites kept. (Tianjin static #6: r = 0.54, dropped.)\n', min(C(~eye(numel(st)))));

%% 1f. Binning and noise reduction
D = dev{st(3)}; b = floor(D(:,1) * 144); [~, ~, gb] = unique(b); nPer = accumarray(gb, 1);
sigPM = std(tr(:,5));
fprintf('\n--- 1f. 10-min bins (static 3): median %d samples per bin ---\n', round(median(nPer)));
fprintf('  1.0-sigma noise per 3-s sample: %.1f ug/m3 -> per 10-min site bin: %.2f -> per hour: %.2f\n', ...
    sigPM, sigPM / sqrt(median(nPer)), sigPM / sqrt(6 * median(nPer)));
fprintf('  -> averaging is why the robustness test barely changes the score.\n');

%% 1g. The full cleaning log of pm_short_term on this training window
fprintf('\n--- 1g. pm_short_term cleaning log, window ending %s ---\n', datestr(t0));
fprintf('  missing rows %d | GPS errors %d | spikes %d | kept %s\n', infoFix.clean.missing, infoFix.clean.gps, infoFix.clean.spikes, infoFix.clean.kept);
fprintf('  static rows %d | mobile rows %d | static sites %d | dropped as faulty %d\n', ...
    infoFix.n_static_rows, infoFix.n_mobile_rows, infoFix.n_sites, infoFix.dropped_sites);
fprintf('  site offsets (ug/m3): %s\n', mat2str(infoFix.site_offsets, 3));

f = figure('Color', 'w', 'Name', 'Step 1: preprocessing', 'Position', [60 60 1100 650]);
subplot(2,1,1); plot(D(:,1), D(:,5), '.', 'MarkerSize', 2); hold on;
plot(unique(b) / 144, accumarray(gb, D(:,5)) ./ nPer, 'r-', 'LineWidth', 1);
datetick('x', 'mm/dd'); grid on; ylabel('PM2.5'); legend('raw 3-s', '10-min mean'); title('Foshan static 3: raw vs binned');
subplot(2,1,2); M = dev{mb(6)}; plot(M(:,1), M(:,5), '.', 'MarkerSize', 2); hold on;
plot([M(1,1) M(end,1)], [thr thr], 'r--'); datetick('x', 'mm/dd'); grid on; ylabel('PM2.5');
legend('raw 3-s', sprintf('spike threshold %.0f', thr)); title('Foshan mobile 6: spikes above the threshold are removed');
print(f, fullfile(P.figures, 'step1_preprocessing.png'), '-dpng', '-r150');
save(fullfile(P.results, 'step1_preprocessing.mat'), 'summary', 'thr', 'C', '-v7');
fprintf('\nsaved figures/step1_preprocessing.png and results/step1_preprocessing.mat\n');
