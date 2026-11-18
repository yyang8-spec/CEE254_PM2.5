%ST_VALIDATE  Validate src/pm_short_term.m the way the competition will score it.
%
% DESIGN
%   * Leave-one-sensor-out. The competition test sites are fixed locations
%     with NO data in train_data, so one Foshan static sensor at a time is
%     held out, all of its data is removed from training, and its hourly
%     means are predicted.
%   * Rolling origin: a forecast every 3 h, each using only the 3 days
%     before it, as in the competition.
%   * CHRONOLOGICAL SPLIT FOR MODEL SELECTION. The origins are split in time:
%       development = first half  -> choose tau (EWMA time constant)
%       test        = second half -> report the chosen model once, unchanged
%     tau is chosen on the mean development NRMSE over the noise levels, since
%     the competition scores all three. The full-period number is reported
%     too, but only as "development backtest" (tau was tuned on part of it).
%   * Robustness: zero-mean Gaussian noise (sd = 0.5 / 1.0 x std of the
%     training PM2.5) on train_data only; the truth stays clean.
%   * Metric: pooled NRMSE = RMSE / RMS(truth).
%   * Ablations REMOVE one component with everything else fixed (at the
%     chosen tau): the site offset, the parked-vehicle rule, the EWMA
%     smoothing (replaced by the latest sample of each site). Other tau
%     values are reported separately as a sensitivity analysis.
%   * Missing-data check at the end: static data removed from the last 3 h.
%
% Run from the repo root:  run('short_term/st_validate.m')
% Needs data/processed/devices_foshan.mat (data_cleaning/export_device_matrices.m).
% NOISE = [0 0.5 1.0] by default. Runs for single noise levels (e.g. in
% parallel) are saved and combined by short_term/st_validate_summary.m.

ROOT = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(ROOT, 'src')); addpath(fullfile(ROOT, 'validation')); addpath(fullfile(ROOT, 'short_term'));
if ~exist('QUICK', 'var'), QUICK = false; end
if ~exist('NOISE', 'var'), NOISE = [0 0.5 1.0]; end
if ~exist('SKIP_TAIL', 'var'), SKIP_TAIL = false; end   % true: only compute + save (parallel runs)

S = load(fullfile(ROOT, 'data', 'processed', 'devices_foshan.mat'));
dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
tStart = floor(min(cellfun(@(D) D(1,1), dev)));
tEnd   = floor(max(cellfun(@(D) D(end,1), dev)));
step = 1/8; if QUICK, step = 0.5; end
starts = (tStart + 3):step:(tEnd - 0.2);
isDev = starts < starts(1) + (starts(end) - starts(1)) / 2;   % first half in time

% candidates for tau; every pm_short_term variant is run at every tau so that
% the ablations can be reported at whichever tau the development half picks
TAUS = [2 5 10 20];
V = {};                                      % {label, opts | baseline name}
for k = 1:numel(TAUS)
    tau = TAUS(k);
    V(end+1,:) = {sprintf('full model, tau %g', tau),          struct('tau_min', tau)}; %#ok<SAGROW>
    V(end+1,:) = {sprintf('no site offset, tau %g', tau),      struct('tau_min', tau, 'offset_shrink', 0)}; %#ok<SAGROW>
    V(end+1,:) = {sprintf('no parked-vehicle rule, tau %g', tau), struct('tau_min', tau, 'static_min_frac', 0)}; %#ok<SAGROW>
end
V(end+1,:) = {'no EWMA smoothing (latest sample)', struct('level_method', 'last')};
V(end+1,:) = {'base: nearest-sensor last-hour mean', 'nearest_persist'};
V(end+1,:) = {'base: training mean', 'train_mean'};
V(end+1,:) = {'base: daily profile', 'daily_profile'};

nO = numel(starts); nV = size(V,1);
for q = 1:numel(NOISE)
    nf = NOISE(q);
    SE = nan(nV, nO); SS = nan(1, nO);       % per-origin squared errors (summed over held-out sensors)
    for i = 1:nO
        t0 = starts(i); se = zeros(nV,1); ss = 0; got = false;
        for h = st
            [tr, te, y] = make_task(dev, is_static, 1, t0, h, nf, round(t0*100) + h);
            if any(~isfinite(y)) || isempty(tr), continue; end
            for v = 1:nV
                if ischar(V{v,2}), p = baseline_pred(tr, te, 1, V{v,2});
                else,              p = pm_short_term(tr, te, V{v,2}); end
                se(v) = se(v) + sum((p - y).^2);
            end
            ss = ss + sum(y.^2); got = true;
        end
        if got, SE(:, i) = se; SS(i) = ss; end
    end
    labels = V(:,1); %#ok<NASGU>
    out = fullfile(ROOT, 'short_term', sprintf('validate_split_%s.mat', strrep(sprintf('%g', nf), '.', 'p')));
    save(out, 'SE', 'SS', 'labels', 'starts', 'isDev', 'TAUS', 'nf', 'QUICK', '-v7');
    fprintf('noise %.1f done -> %s\n', nf, out);
end

% ---- selection on development, evaluation on test -------------------------
if SKIP_TAIL, return, end
run(fullfile(ROOT, 'short_term', 'st_validate_summary.m'));

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
fprintf('\n=== missing-data check (static data removed from the last 3 h, noise 0) ===\n');
fprintf('  full data                 NRMSE = %.4f\n', sqrt(se(1)/n)/sqrt(ss/n));
fprintf('  static gap -> fallback    NRMSE = %.4f   (level source: %s)\n', sqrt(se(2)/n)/sqrt(ss/n), strjoin(unique(srcs), ', '));
