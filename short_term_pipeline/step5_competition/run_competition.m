%RUN_COMPETITION  Produce the competition predictions from data/competition.
%
%   run('short_term_pipeline/step5_competition/run_competition.m')              % all 9 tests
%   TASKS = 1; run('short_term_pipeline/step5_competition/run_competition.m')   % short-term only
%
% Reads the 11/16 Canvas files (MATLAB tables):
%   train: train_data_<task>_<n>_var.mat            (variable train_data), or
%          separated_train_data_<task>_<n>_var.mat  (train_data_static + train_data_mobile)
%   test:  test_data_<task>_<n>_var.mat              (variable test_data)
% with <task> = short_term | long_term | interpolation and <n> = 0 | 5 | 10
% (noise 0, 0.5 and 1.0 sigma).
% Writes short_term_pipeline/submissions/pred_<task>_<n>_var.mat (variable pred_pm2d5, M x 1, same
% row order as test_data) and a .csv copy, and prints a summary.

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
DATA = P.competition;
OUT  = P.submissions;
if ~exist('TASKS', 'var'), TASKS = 1:3; end
names = {'short_term', 'long_term', 'interpolation'};
noise = {'0', '5', '10'};

for task = TASKS
    for q = 1:3
        tag = sprintf('%s_%s_var', names{task}, noise{q});
        f  = fullfile(DATA, ['train_data_' tag '.mat']);
        fs = fullfile(DATA, ['separated_train_data_' tag '.mat']);
        octNum = fullfile(P.processed, 'competition', [tag '.mat']);   % Octave only: numeric copies
        if exist('OCTAVE_VERSION', 'builtin') && exist(octNum, 'file')
            S = load(octNum); train_data = S.train_data; f = '';
        end
        if isempty(f)
            % (loaded above)
        elseif exist(f, 'file')
            S = load(f); train_data = S.train_data;
        elseif exist(fs, 'file')
            S = load(fs); train_data = [S.train_data_static; S.train_data_mobile];
        else
            fprintf('%-26s  MISSING train file, skipped\n', tag); continue
        end
        if isempty(f), test_data = S.test_data;
        else, T = load(fullfile(DATA, ['test_data_' tag '.mat'])); test_data = T.test_data; end
        tic;
        [pred_pm2d5, pred_sd] = pm2d5_pred_model(train_data, test_data, task);
        el = toc;
        save(fullfile(OUT, ['pred_' tag '.mat']), 'pred_pm2d5', 'pred_sd', '-v7');
        csvwrite(fullfile(OUT, ['pred_' tag '.csv']), [pred_pm2d5 pred_sd]);
        fprintf('%-26s  M = %3d  pred mean %6.2f  min %6.2f  max %6.2f  NaN %d  (%.1f s)\n', ...
            tag, numel(pred_pm2d5), mean(pred_pm2d5), min(pred_pm2d5), max(pred_pm2d5), ...
            sum(~isfinite(pred_pm2d5)), el);
    end
end
fprintf('\nPredictions written to %s\n', OUT);
