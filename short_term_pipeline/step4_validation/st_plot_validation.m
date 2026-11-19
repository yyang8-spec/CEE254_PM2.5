%ST_PLOT_VALIDATION  Figure of the held-out TEST-half results (report g/h/i).
% Reads short_term/validate_test_table.mat (written by st_validate_summary.m).
%   run('short_term/st_plot_validation.m')
% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
D = load(fullfile(P.results, 'validate_test_table.mat'));
R = D.RT; labels = D.rowLabels; noise = D.nz;
fprintf('%-42s', 'model'); fprintf('  noise %.1f', noise); fprintf('\n');
for v = 1:numel(labels), fprintf('%-42s', labels{v}); fprintf('  %9.4f', R(v,:)); fprintf('\n'); end
show = find(R(:,1) < 0.3);                     % drop the far-off baselines
f = figure('Color', 'w', 'Position', [80 80 1000 560]);
barh(R(show, :)); set(gca, 'YDir', 'reverse', 'YTick', 1:numel(show), 'YTickLabel', labels(show));
xlabel('NRMSE on the held-out test half (lower is better)'); grid on;
legend(arrayfun(@(x) sprintf('noise %.1f\\sigma', x), noise, 'UniformOutput', false), 'Location', 'southeast');
title(sprintf('Short-term (Foshan), leave-one-sensor-out, tau = %g min chosen on the development half', D.tauBest));
xlim([0.18 min(0.8, max(max(R(show,:))) * 1.05)]);
print(f, fullfile(P.figures, 'st_validation.png'), '-dpng', '-r150');
fprintf('saved figures/st_validation.png\n');
