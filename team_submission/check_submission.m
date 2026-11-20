%CHECK_SUBMISSION  Test the built single file the way the graders will run it.
%
%   run('team_submission/check_submission.m')
%
% Copies SUBMIT/pm2d5_pred_model.m into an empty temporary folder, runs it
% from there (so nothing else from this repo can be picked up), on all 9
% competition files in data/competition, and checks every output: size M x 1,
% finite, plausible range. For short-term it also compares with the
% predictions in short_term_pipeline/submissions (must be identical).

here = fileparts(mfilename('fullpath'));
if isempty(here), here = fullfile(pwd, 'team_submission'); end
root = fileparts(here); data = fullfile(root, 'data', 'competition');
src = fullfile(here, 'SUBMIT', 'pm2d5_pred_model.m');
if ~exist(src, 'file'), error('run build_submission.m first'); end
tmp = tempname; mkdir(tmp); copyfile(src, tmp);
old = pwd; cleanup = onCleanup(@() cd(old));
cd(tmp);                                   % the current folder wins over the path
isOct = exist('OCTAVE_VERSION', 'builtin') ~= 0;
names = {'short_term', 'long_term', 'interpolation'}; noise = {'0', '5', '10'};
fprintf('\nUsing %s\n', which('pm2d5_pred_model'));
allOK = true; okStr = {'PROBLEM', 'OK'};
for task = 1:3
    for q = 1:3
        tag = sprintf('%s_%s_var', names{task}, noise{q});
        if isOct                                        % Octave cannot read tables: numeric copies
            S = load(fullfile(root, 'data', 'processed', 'competition', [tag '.mat']));
            tr = S.train_data; te = S.test_data;
        else
            f = fullfile(data, ['train_data_' tag '.mat']);
            if exist(f, 'file'), S = load(f); tr = S.train_data;
            else, S = load(fullfile(data, ['separated_train_data_' tag '.mat'])); tr = [S.train_data_static; S.train_data_mobile]; end
            T = load(fullfile(data, ['test_data_' tag '.mat'])); te = T.test_data;
        end
        tic; p = pm2d5_pred_model(tr, te, task); el = toc;
        if isa(te, 'table'), M = height(te); else, M = size(te, 1); end
        ok = isequal(size(p), [M 1]) && all(isfinite(p)) && all(p >= 0 & p < 1000);
        extra = '';
        if task == 1
            R = load(fullfile(root, 'short_term_pipeline', 'submissions', ['pred_' tag '.mat']));
            same = max(abs(R.pred_pm2d5 - p)) < 1e-9; ok = ok && same;
            extra = sprintf('  identical to short_term_pipeline/submissions: %d', same);
        end
        allOK = allOK && ok;
        fprintf('  %-22s M = %3d  mean %6.2f  min %6.2f  max %6.2f  %5.1f s  %s%s\n', tag, M, mean(p), min(p), max(p), el, ...
            okStr{ok + 1}, extra);
    end
end
if allOK, fprintf('\nALL 9 TESTS OK - SUBMIT/pm2d5_pred_model.m is ready to hand in.\n');
else, fprintf('\nSOME TESTS FAILED - see above.\n'); end
