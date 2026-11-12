%ST_PLOT_VALIDATION  Figure of the st_validate.m results (report sections g/h).
% Loads every short_term/validate_results_*.mat (one file per NOISE setting,
% so runs per noise level can be done in parallel) and draws grouped bars:
% NRMSE per model/ablation/baseline at noise 0, 0.5 and 1.0 sigma.
%   run('short_term/st_plot_validation.m')
ROOT = fileparts(fileparts(mfilename('fullpath')));
F = dir(fullfile(ROOT, 'short_term', 'validate_results_*.mat'));
noise = []; cols = {};
for i = 1:numel(F)
    D = load(fullfile(F(i).folder, F(i).name));
    if D.QUICK, continue; end                     % full runs only
    for q = 1:numel(D.NOISE)
        noise(end+1) = D.NOISE(q); cols{end+1} = D.RES(:, q); %#ok<SAGROW>
        labels = D.labels;
    end
end
[noise, o] = unique(noise); R = [cols{o}];
fprintf('%-32s', 'variant'); fprintf('  noise %.1f', noise); fprintf('\n');
for v = 1:numel(labels), fprintf('%-32s', labels{v}); fprintf('  %9.4f', R(v,:)); fprintf('\n'); end
% plot: drop the two far-off baselines so the important differences are visible
show = find(R(:,1) < 0.4);
f = figure('Color', 'w', 'Position', [80 80 1000 520]);
barh(R(show, :)); set(gca, 'YDir', 'reverse', 'YTick', 1:numel(show), 'YTickLabel', labels(show));
xlabel('NRMSE (lower is better)'); grid on;
legend(arrayfun(@(x) sprintf('noise %.1f\\sigma', x), noise, 'UniformOutput', false), 'Location', 'southeast');
title('Short-term (Foshan), leave-one-sensor-out, 585 test values per noise level');
xlim([0.15 max(max(R(show,:))) * 1.05]);
print(f, fullfile(ROOT, 'figures', 'st_validation.png'), '-dpng', '-r150');
fprintf('saved figures/st_validation.png\n');
