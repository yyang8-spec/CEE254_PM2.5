%ST_VALIDATE_SUMMARY  Choose tau on the development half, report the test half.
%
% Loads short_term/validate_split_<noise>.mat (written by st_validate.m, one
% file per noise level) and:
%   1. picks tau among TAUS by the mean development NRMSE over the noise
%      levels present (full model only - nothing is chosen on test data),
%   2. reports the chosen model, the ablations at that tau, the other taus
%      (sensitivity) and the baselines on the TEST half,
%   3. also reports the whole period as "development backtest".
%   run('short_term/st_validate_summary.m')

ROOT = fileparts(fileparts(mfilename('fullpath')));
F = dir(fullfile(ROOT, 'short_term', 'validate_split_*.mat'));
if isempty(F), error('no validate_split_*.mat files: run st_validate.m first'); end
R = {}; nz = [];
for i = 1:numel(F)
    D = load(fullfile(F(i).folder, F(i).name));
    R{end+1} = D; nz(end+1) = D.nf; %#ok<SAGROW>
end
[nz, o] = sort(nz); R = R(o);
labels = R{1}.labels; TAUS = R{1}.TAUS; isDev = R{1}.isDev;
nr = @(D, v, sel) sqrt(sum(D.SE(v, sel & isfinite(D.SS)))) / sqrt(sum(D.SS(sel & isfinite(D.SS))));

% 1. choose tau on development only
devScore = zeros(numel(TAUS), numel(R));
for k = 1:numel(TAUS)
    v = find(strcmp(labels, sprintf('full model, tau %g', TAUS(k))));
    for q = 1:numel(R), devScore(k, q) = nr(R{q}, v, isDev); end
end
[~, kBest] = min(mean(devScore, 2)); tauBest = TAUS(kBest);
fprintf('\n=== tau selection on the DEVELOPMENT half (%d origins, %s to %s) ===\n', ...
    sum(isDev), datestr(R{1}.starts(find(isDev,1))), datestr(R{1}.starts(find(isDev,1,'last'))));
fprintf('  %-8s', 'tau'); fprintf('  noise %.1f', nz); fprintf('   mean\n');
for k = 1:numel(TAUS)
    fprintf('  %-8g', TAUS(k)); fprintf('  %9.4f', devScore(k,:)); fprintf('  %6.4f', mean(devScore(k,:)));
    if k == kBest, fprintf('   <- chosen'); end, fprintf('\n');
end

% 2. test half with tau fixed
rows = {sprintf('full model, tau %g', tauBest), 'OURS (chosen tau, held-out test)'
        sprintf('no site offset, tau %g', tauBest), 'ablation: no site offset'
        sprintf('no parked-vehicle rule, tau %g', tauBest), 'ablation: no parked-vehicle rule'
        'no EWMA smoothing (latest sample)', 'ablation: no EWMA smoothing'};
for k = setdiff(1:numel(TAUS), kBest)
    rows(end+1,:) = {sprintf('full model, tau %g', TAUS(k)), sprintf('sensitivity: tau %g min', TAUS(k))}; %#ok<SAGROW>
end
rows = [rows; {'base: nearest-sensor last-hour mean', 'baseline: nearest-sensor last-hour mean'
               'base: training mean', 'baseline: training mean'
               'base: daily profile', 'baseline: daily profile'}];
RT = nan(size(rows,1), numel(R));             % test-half table, saved for plotting
for part = {'TEST half (held out)', 'WHOLE period (development backtest)'}
    sel = ~isDev; isTest = ~strcmp(part{1}(1:5), 'WHOLE'); if ~isTest, sel = true(size(isDev)); end
    fprintf('\n=== %s, %d origins, chosen tau = %g min ===\n', part{1}, sum(sel), tauBest);
    fprintf('  %-42s', 'model'); fprintf('  noise %.1f', nz); fprintf('\n');
    for r = 1:size(rows,1)
        v = find(strcmp(labels, rows{r,1}));
        fprintf('  %-42s', rows{r,2});
        for q = 1:numel(R)
            x = nr(R{q}, v, sel); fprintf('  %9.4f', x);
            if isTest, RT(r, q) = x; end
        end
        fprintf('\n');
    end
end
rowLabels = rows(:,2); %#ok<NASGU>
save(fullfile(ROOT, 'short_term', 'validate_test_table.mat'), 'RT', 'rowLabels', 'nz', 'tauBest', 'devScore', 'TAUS', '-v7');
