%STEP3_MODEL_COMPARISON  Which forecasting model? Baselines vs regression vs smoothing.
%
% Single-sensor study on all 5 Foshan static sensors: each sensor is
% forecast every hour from its own previous 3 days; the first half of the
% origins is validation (choose ridge lambda, EWMA tau), the second half is
% the test. Models: training mean, daily profile, persistence (1 h, 10 min),
% linear regression on levels, ridge on the change (with/without future
% humidity/temperature), EWMA smoothing (tau 5-30 min), trailing means.
%
% RECOMPUTE = false (default): print the saved results (seconds).
% RECOMPUTE = true: rerun st_single_sensor.m for all 5 sensors (~30 min);
%   it also prints that sensor's cleaning log, correlation table and model
%   table as it goes (stages 1-3).
% Saves figures/st_smoothing_vs_noise.png.

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
if ~exist('RECOMPUTE', 'var'), RECOMPUTE = false; end
fprintf('\n===== STEP 3: MODEL COMPARISON (single sensor, all 5 Foshan static sensors) =====\n');
if RECOMPUTE, SKIP_RUN = false; else, SKIP_RUN = true; end
MAKE_FIGS = true;
run(fullfile(P.dir, 'step3_model_comparison', 'st_compare_sensors.m'));

fprintf('\n--- What the table shows ---\n');
fprintf('  * Ridge (lambda chosen on validation) beats persistence on VALIDATION but LOSES on TEST,\n');
fprintf('    on every sensor: it overfits one 3-day window. The recent trend (step 2d) does not\n');
fprintf('    translate into an out-of-sample gain.\n');
fprintf('  * Longer smoothing (tau) loses less to noise but reacts later (figure st_smoothing_vs_noise).\n');
fprintf('\n--- Two further alternatives, tested as Python prototypes (leave-one-sensor-out; see docs) ---\n');
fprintf('  %-48s %8s %8s\n', '', 'val', 'test');
fprintf('  %-48s %8.4f %8.4f\n', 'persistence (EWMA 5 + IDW offset)', 0.1467, 0.1893);
fprintf('  %-48s %8.4f %8.4f\n', 'ridge on multi-sensor features (lambda on val)', 0.1424, 0.1919);
fprintf('  %-48s %8.4f %8.4f\n', 'calibrated mobile data for the site offset', 0.1512, 0.1917);
fprintf('  -> neither beats persistence on test.\n');
fprintf('\n--- Decision: multi-sensor persistence with exponential smoothing and a spatial offset ---\n');
fprintf('    (validated in step 4)\n');
