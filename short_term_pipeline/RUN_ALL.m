%RUN_ALL  Short-term PM2.5 pipeline, steps 1-5, with intermediate results.
%
%   run('short_term_pipeline/RUN_ALL.m')        (from the repo root)
% or open this file and press Run. Takes a few minutes: steps 3 and 4 show
% saved results of the long validations. Set RECOMPUTE = true before running
% to recompute everything (~1.5 h).
%
% Before the first run: step0_setup/export_device_matrices.m (once), which
% converts data/raw/*.mat into data/processed/devices_<city>.mat.
%
%   step 1  data preprocessing      -> cleaning log, device summary, parked-vehicle demo
%   step 2  variable correlation    -> correlation table, stability, change correlation
%   step 3  model comparison        -> baselines vs regression vs smoothing, 5 sensors
%   step 4  validation              -> tau on dev half, held-out test, ablations, uncertainty
%   step 5  competition             -> predictions for the 3 short-term test files
% Figures go to short_term_pipeline/figures, results to short_term_pipeline/results.

if ~exist('RECOMPUTE', 'var'), RECOMPUTE = false; end
here = fileparts(mfilename('fullpath')); if isempty(here), here = fullfile(pwd, 'short_term_pipeline'); end
addpath(here); P = st_paths();
if ~exist(fullfile(P.processed, 'devices_foshan.mat'), 'file')
    fprintf('data/processed/devices_foshan.mat not found -> running step 0 (data conversion)\n');
    run(fullfile(P.dir, 'step0_setup', 'export_device_matrices.m'));
end
steps = {'step1_preprocessing/step1_preprocessing.m', 'step2_correlation/step2_correlation.m', ...
         'step3_model_comparison/step3_model_comparison.m', 'step4_validation/step4_validation.m', ...
         'step5_competition/step5_competition.m'};
for k = 1:numel(steps)
    RECOMPUTE_KEEP = RECOMPUTE; run(fullfile(P.dir, steps{k})); RECOMPUTE = RECOMPUTE_KEEP;
    P = st_paths();
end
fprintf('\nDone. Figures: %s\nResults: %s\nSubmissions: %s\n', P.figures, P.results, P.submissions);
