%STEP4_VALIDATION  Final model, validated the way the competition scores it.
%
% Leave-one-sensor-out: each Foshan static sensor in turn is the test site
% (all its data removed from training). A forecast every 3 h, each from
% the 3 days before it. Noise 0 / 0.5 / 1.0 sigma on training PM only.
% tau is chosen on the FIRST half of the origins (development) and the
% model is scored once on the SECOND half (held-out test).
%   4a tau selection (development half)
%   4b held-out test: final model, ablations, tau sensitivity, baselines
%   4c uncertainty calibration (pred_sd coverage)
%   4d missing static data at the forecast time (mobile fallback)
%   4e one forecast, step by step
% RECOMPUTE = false (default): saved results (seconds). true: ~1 h.
% Saves figures/st_validation.png.

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
if ~exist('RECOMPUTE', 'var'), RECOMPUTE = false; end
fprintf('\n===== STEP 4: VALIDATION OF THE FINAL MODEL =====\n');
if RECOMPUTE || isempty(dir(fullfile(P.results, 'validate_split_*.mat')))
    NOISE = [0 0.5 1.0]; run(fullfile(P.dir, 'step4_validation', 'st_validate.m'));   % includes 4d
else
    run(fullfile(P.dir, 'step4_validation', 'st_validate_summary.m'));                  % 4a, 4b
end
run(fullfile(P.dir, 'step4_validation', 'st_plot_validation.m'));

fprintf('\n--- 4c. Uncertainty calibration ---\n');
run(fullfile(P.dir, 'step4_validation', 'st_uncertainty.m'));
fprintf('  -> the 95%% intervals under-cover (heavy-tailed errors in pollution events).\n');

fprintf('\n--- 4d. Missing static data at the forecast time ---\n');
MF = fullfile(P.results, 'missing_data_check.mat');
if ~RECOMPUTE && exist(MF, 'file')
    load(MF, 'missing_full', 'missing_fallback');
    fprintf('  full data NRMSE %.4f | static data removed from the last 3 h -> mobile fallback %.4f\n', missing_full, missing_fallback);
elseif RECOMPUTE
    % already printed by st_validate.m above
else
    run(fullfile(P.dir, 'step4_validation', 'st_missing_data.m'));
end

fprintf('\n--- 4e. One forecast, step by step (static 3 held out, origin 13-Oct 12:00) ---\n');
S = load(fullfile(P.processed, 'devices_foshan.mat')); dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
[tr, te, y] = make_task(dev, is_static, 1, datenum(2018,10,13,12,0,0), st(3), 0, 1);
[p, sd, info] = pm_short_term(tr, te);
pb = baseline_pred(tr, te, 1, 'nearest_persist');
fprintf('  training rows %d, kept %s | static sites %d | level source: %s\n', size(tr,1), info.clean.kept, info.n_sites, info.level_source);
fprintf('  city level now %.1f | site offsets %s | IDW offset at the test site %.1f\n', info.level, mat2str(info.site_offsets, 2), p(1) - info.level);
fprintf('  %-6s %8s %8s %10s %16s\n', 'hour', 'truth', 'ours', '+/- 1 sd', 'nearest baseline');
for i = 1:3, fprintf('  h = %d  %8.1f %8.1f %10.1f %16.1f\n', i, y(i), p(i), sd(i), pb(i)); end
