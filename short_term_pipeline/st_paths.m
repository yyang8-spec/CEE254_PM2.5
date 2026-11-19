function P = st_paths()
%ST_PATHS  Folder layout of the short-term pipeline; adds its folders to the path.
%   P = st_paths()   P.dir (this folder), P.root (repo root), P.processed,
%                    P.competition, P.results, P.figures, P.submissions
% Every script in short_term_pipeline calls this first, so the scripts work
% whether they are run with Run, Run Section, run(...) or from RUN_ALL.m.
P.dir  = fileparts(mfilename('fullpath'));
P.root = fileparts(P.dir);
P.processed   = fullfile(P.root, 'data', 'processed');      % devices_<city>.mat (step 0)
P.competition = fullfile(P.root, 'data', 'competition');    % 11/16 Canvas files
P.results     = fullfile(P.dir, 'results');
P.figures     = fullfile(P.dir, 'figures');
P.submissions = fullfile(P.dir, 'submissions');
sub = {'model', 'utils', 'step0_setup', 'step1_preprocessing', 'step2_correlation', ...
       'step3_model_comparison', 'step4_validation', 'step5_competition'};
for i = 1:numel(sub), addpath(fullfile(P.dir, sub{i})); end
for f = {P.results, P.figures, P.submissions}
    if ~exist(f{1}, 'dir'), mkdir(f{1}); end
end
end
