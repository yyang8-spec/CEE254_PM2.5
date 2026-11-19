%STEP5_COMPETITION  Short-term predictions on the 11/16 competition data.
% Runs run_competition.m for problem_type 1 (noise 0 / 0.5 / 1.0 sigma) and
% shows the predictions per test site and hour.
% Writes submissions/pred_short_term_<n>_var.mat (variable pred_pm2d5).

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
fprintf('\n===== STEP 5: COMPETITION PREDICTIONS (short-term) =====\n');
TASKS = 1; run(fullfile(P.dir, 'step5_competition', 'run_competition.m'));
for nv = {'0', '5', '10'}
    Pr = load(fullfile(P.submissions, ['pred_short_term_' nv{1} '_var.mat']));
    if exist('OCTAVE_VERSION', 'builtin')
        Tn = load(fullfile(P.processed, 'competition', ['short_term_' nv{1} '_var.mat'])); t = Tn.test_data(:,1); la = Tn.test_data(:,5); lo = Tn.test_data(:,6);
    else
        T = load(fullfile(P.competition, ['test_data_short_term_' nv{1} '_var.mat'])); T = T.test_data;
        t = datenum(T.time); la = T.lat; lo = T.lon;
    end
    fprintf('\n  noise %s/10 sigma:\n  %-18s %11s %11s %10s %8s\n', nv{1}, 'hour ending', 'lat', 'lon', 'pred', 'sd');
    for i = 1:numel(Pr.pred_pm2d5)
        fprintf('  %-18s %11.6f %11.6f %10.2f %8.2f\n', datestr(t(i), 'yyyy-mm-dd HH:MM'), la(i), lo(i), Pr.pred_pm2d5(i), Pr.pred_sd(i));
    end
end
fprintf('\n  (time stamps mark hour ENDS; the same level is held for the 3 hours: persistence)\n');
