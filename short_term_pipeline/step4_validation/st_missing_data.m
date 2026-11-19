%ST_MISSING_DATA  Robustness to missing static data at the forecast time.
% Removes ALL static data from the last 3 h of train_data (every 4th origin,
% noise 0), so pm_short_term must fall back to calibrated mobile data.
% Saves results/missing_data_check.mat.  ~10 min.

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
S = load(fullfile(P.processed, 'devices_foshan.mat'));
dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
tStart = floor(min(cellfun(@(D) D(1,1), dev))); tEnd = floor(max(cellfun(@(D) D(end,1), dev)));
starts = (tStart + 3):(1/8):(tEnd - 0.2);
stPos = zeros(numel(st), 2);
for i = 1:numel(st), stPos(i,:) = dev{st(i)}(1, 6:7); end   % static coordinates
se = [0 0]; ss = 0; n = 0; srcs = {};
for t0 = starts(1:4:end)
    for h = st
        [tr, te, y] = make_task(dev, is_static, 1, t0, h, 0, 1);
        if any(~isfinite(y)), continue; end
        stRow = ismember(round(tr(:,6:7)*1e5), round(stPos*1e5), 'rows');
        cut = stRow & tr(:,1) >= t0 - 3/24;
        [p1, ~, info] = pm_short_term(tr(~cut,:), te); srcs{end+1} = info.level_source; %#ok<SAGROW>
        p0 = pm_short_term(tr, te);
        se = se + [sum((p0 - y).^2) sum((p1 - y).^2)]; ss = ss + sum(y.^2); n = n + numel(y);
    end
end
fprintf('\n=== missing-data check (static data removed from the last 3 h, noise 0) ===\n');
fprintf('  full data                 NRMSE = %.4f\n', sqrt(se(1)/n)/sqrt(ss/n));
fprintf('  static gap -> fallback    NRMSE = %.4f   (level source: %s)\n', sqrt(se(2)/n)/sqrt(ss/n), strjoin(unique(srcs), ', '));
missing_full = sqrt(se(1)/n)/sqrt(ss/n); missing_fallback = sqrt(se(2)/n)/sqrt(ss/n); %#ok<NASGU>
save(fullfile(P.results, 'missing_data_check.mat'), 'missing_full', 'missing_fallback', '-v7');
