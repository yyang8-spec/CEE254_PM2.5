%ST_VALIDATE  Validate pm_short_term.m the way the competition will score it.
%
% DESIGN (why it looks like this)
%   * The competition test sites are fixed locations with NO data in
%     train_data. So we hold out one Foshan static sensor at a time, remove
%     all of its data from training, and predict its hourly means
%     (leave-one-sensor-out). A plain chronological split on one sensor
%     would let the model see the test site's own history: too optimistic.
%   * Rolling origin: a forecast every 3 h across the whole week, each
%     using only the 3 days before it, as in the competition.
%   * Robustness test: zero-mean Gaussian noise with sd = 0.5 and 1.0 x the
%     std of the training PM2.5 is added to train_data only. The truth stays
%     clean.
%   * Metric: pooled NRMSE = RMSE / RMS(truth) over all forecasts.
%   * Baselines (report section g) and ablations (section h) use exactly the
%     same tasks.
%   * Last section: a missing-data check. Static data is removed from the
%     last 3 h of train_data, so the mobile fallback has to take over.
%
% Run from the repo root:  run('short_term/st_validate.m')
% Needs data/processed/devices_foshan.mat (data_cleaning/export_device_matrices.m).
% Set QUICK = true for a fast check (a forecast every 12 h instead of 3 h).

ROOT = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(ROOT, 'short_term')); addpath(fullfile(ROOT, 'validation'));
if ~exist('QUICK', 'var'), QUICK = false; end
if ~exist('NOISE', 'var'), NOISE = [0 0.5 1.0]; end

S = load(fullfile(ROOT, 'data', 'processed', 'devices_foshan.mat'));
dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
tStart = floor(min(cellfun(@(D) D(1,1), dev)));
tEnd   = floor(max(cellfun(@(D) D(end,1), dev)));
step = 1/8; if QUICK, step = 0.5; end
starts = (tStart + 3):step:(tEnd - 0.2);

% {label, opts struct for pm_short_term | baseline name}
V = {
  'OURS  EWMA tau 5 + IDW offset', struct()
  'abl: tau 10 min',               struct('tau_min', 10)
  'abl: tau 20 min',               struct('tau_min', 20)
  'abl: no site offset',           struct('offset_shrink', 0)
  'abl: keep faulty sites',        struct('min_site_corr', -Inf)
  'abl: no parked-vehicle rule',   struct('static_min_frac', 0)
  'base: training mean',           'train_mean'
  'base: nearest-sensor persist',  'nearest_persist'
  'base: daily profile',           'daily_profile'
};

for nf = NOISE
    se = zeros(size(V,1), 1); ss = 0; n = 0;
    for t0 = starts
        for h = st
            [tr, te, y] = make_task(dev, is_static, 1, t0, h, nf, round(t0*100) + h);
            if any(~isfinite(y)) || isempty(tr), continue; end
            for v = 1:size(V,1)
                if ischar(V{v,2}), p = baseline_pred(tr, te, 1, V{v,2});
                else,              p = pm_short_term(tr, te, V{v,2}); end
                se(v) = se(v) + sum((p - y).^2);
            end
            ss = ss + sum(y.^2); n = n + numel(y);
        end
    end
    fprintf('\n=== short-term, Foshan, noise %.1f sigma  [%d test values] ===\n', nf, n);
    for v = 1:size(V,1)
        fprintf('  %-32s NRMSE = %.4f\n', V{v,1}, sqrt(se(v)/n) / sqrt(ss/n));
    end
end

% ---- missing-data check: no static data in the last 3 h ------------------
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
fprintf('\n=== missing-data check (static data removed from the last 3 h) ===\n');
fprintf('  full data                 NRMSE = %.4f\n', sqrt(se(1)/n)/sqrt(ss/n));
fprintf('  static gap -> fallback    NRMSE = %.4f   (level source: %s)\n', sqrt(se(2)/n)/sqrt(ss/n), strjoin(unique(srcs), ', '));
