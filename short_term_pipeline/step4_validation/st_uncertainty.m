%ST_UNCERTAINTY  Is pred_sd from pm_short_term honest? (report section j)
%
% For a well-calibrated 1-sigma uncertainty, about 68% of the true values
% should fall inside pred +/- 1*sd and about 95% inside pred +/- 1.96*sd.
% Same leave-one-sensor-out tasks as st_validate.m (noise 0).
%   run('short_term/st_uncertainty.m')

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
if ~exist('QUICK', 'var'), QUICK = false; end
if ~exist('RECOMPUTE', 'var'), RECOMPUTE = false; end
UFILE = fullfile(P.results, 'uncertainty.mat');
if ~RECOMPUTE && exist(UFILE, 'file')
    load(UFILE, 'E', 'SD', 'H'); fprintf('(loaded saved results/uncertainty.mat; RECOMPUTE = true to recompute, ~20 min)\n');
else
    S = load(fullfile(P.processed, 'devices_foshan.mat'));
    dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
    tStart = floor(min(cellfun(@(D) D(1,1), dev))); tEnd = floor(max(cellfun(@(D) D(end,1), dev)));
    step = 1/8; if QUICK, step = 0.5; end
    E = []; SD = []; H = [];
    for t0 = (tStart + 3):step:(tEnd - 0.2)
        for h = st
            [tr, te, y] = make_task(dev, is_static, 1, t0, h, 0, 1);
            if any(~isfinite(y)), continue; end
            [p, sd] = pm_short_term(tr, te);
            E = [E; p - y]; SD = [SD; sd]; H = [H; (1:3)']; %#ok<AGROW>
        end
    end
end
z = abs(E) ./ SD;
fprintf('\n=== pred_sd calibration (%d test values) ===\n', numel(E));
fprintf('  horizon   RMSE    mean sd   inside 1 sd (ideal 68%%)   inside 1.96 sd (ideal 95%%)\n');
for k = 1:3
    m = H == k;
    fprintf('  h = %d    %5.2f    %5.2f          %5.1f%%                   %5.1f%%\n', k, ...
        sqrt(mean(E(m).^2)), mean(SD(m)), 100*mean(z(m) <= 1), 100*mean(z(m) <= 1.96));
end
fprintf('  all      %5.2f    %5.2f          %5.1f%%                   %5.1f%%\n', ...
    sqrt(mean(E.^2)), mean(SD), 100*mean(z <= 1), 100*mean(z <= 1.96));
save(fullfile(P.results, 'uncertainty.mat'), 'E', 'SD', 'H', '-v7');
fprintf('  saved results/uncertainty.mat\n');
