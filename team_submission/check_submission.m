%CHECK_SUBMISSION  Test the built single file the way the graders will run it.
%
%   run('team_submission/check_submission.m')
%
% Runs a copy of SUBMIT/pm2d5_pred_model.m (renamed pm2d5_submit_check, from an
% empty temporary folder, so no other repo file can be picked up) on all 9
% competition files in data/competition, and checks every output: size M x 1,
% finite, plausible range. For short-term it also compares with the
% predictions in short_term_pipeline/submissions (must agree to 1e-6;
% files produced on another machine can differ in the last digits).

here = fileparts(mfilename('fullpath'));
if isempty(here), here = fullfile(pwd, 'team_submission'); end
root = fileparts(here); data = fullfile(root, 'data', 'competition');
src = fullfile(here, 'SUBMIT', 'pm2d5_pred_model.m');
if ~exist(src, 'file'), error('run build_submission.m first'); end
% Test the built file WITHOUT changing the current folder: copy it into an
% empty temporary folder under a unique name (only the function name in the
% first line differs), put that folder on the path and call it from there.
tmp = tempname; mkdir(tmp);
txt = fileread(src);
first = regexp(txt, 'function\s*\[[^\]]*\]\s*=\s*pm2d5_pred_model\s*\(', 'match', 'once');
if isempty(first), error('first line of SUBMIT/pm2d5_pred_model.m not found'); end
txt = strrep(txt, first, strrep(first, 'pm2d5_pred_model', 'pm2d5_submit_check'));
fid = fopen(fullfile(tmp, 'pm2d5_submit_check.m'), 'w'); fwrite(fid, txt); fclose(fid);
addpath(tmp);
try
    isOct = exist('OCTAVE_VERSION', 'builtin') ~= 0;
    names = {'short_term', 'long_term', 'interpolation'}; noise = {'0', '5', '10'};
    fprintf('\nTesting a copy of %s\n  as %s\n', src, which('pm2d5_submit_check'));
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
            tic;
        try
            p = pm2d5_submit_check(tr, te, task);
        catch e
            fprintf('  %-22s ERROR: %s\n', tag, e.message); allOK = false; continue
        end
        el = toc;
            if isa(te, 'table'), M = height(te); else, M = size(te, 1); end
            ok = isequal(size(p), [M 1]) && all(isfinite(p)) && all(p >= 0 & p < 1000);
            extra = '';
            if task == 1
                R = load(fullfile(root, 'short_term_pipeline', 'submissions', ['pred_' tag '.mat']));
                d = max(abs(R.pred_pm2d5 - p));            % stored file may come from another machine:
                same = d < 1e-6; ok = ok && same;           % allow floating-point round-off only
                extra = sprintf('  max |diff| vs short_term_pipeline/submissions: %.1e', d);
            end
            allOK = allOK && ok;
            fprintf('  %-22s M = %3d  mean %6.2f  min %6.2f  max %6.2f  %5.1f s  %s%s\n', tag, M, mean(p), min(p), max(p), el, ...
                okStr{ok + 1}, extra);
        end
    end
catch err
    rmpath(tmp); rethrow(err);
end
rmpath(tmp);
if allOK, fprintf('\nALL 9 TESTS OK - SUBMIT/pm2d5_pred_model.m is ready to hand in.\n');
else, fprintf('\nSOME TESTS FAILED - see above.\n'); end
