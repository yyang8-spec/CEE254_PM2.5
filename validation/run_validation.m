%RUN_VALIDATION  Leave-one-static-sensor-out backtest for all 3 tasks x 3 noise
% levels, comparing our model, its ablations and the baselines.
% Run:  run('validation/run_validation.m')   (from the repo root)
% Needs data/processed/devices_*.mat (data_cleaning/export_device_matrices.m).
%
% Scores are pooled NRMSE over all (window, held-out sensor) pairs.

ROOT = fileparts(fileparts(mfilename('fullpath')));   % repo root
addpath(fullfile(ROOT, 'src')); addpath(fullfile(ROOT, 'validation'));
if ~exist('QUICK', 'var'), QUICK = true; end   % QUICK = fewer windows
if ~exist('TASKS', 'var'), TASKS = 1:3; end
if ~exist('NOISE', 'var'), NOISE = [0 0.5 1.0]; end

city  = {'foshan', 'tianjin', 'tianjin'};   % competition city per task
% variants: {label, opts struct or baseline name}
V = {
  'ours',            struct()
  'abl:no_offset',   struct('offset_shrink', 0)
  'abl:+mobile_off', struct('use_mobile_offset', true)
  'base:train_mean', 'train_mean'
  'base:nearest',    'nearest_persist'
  'base:daily_prof', 'daily_profile'
};
extra = { ...
  {'abl:ar_damp', struct('ar_damp', true); 'abl:persist60', struct('persist_bins', 6)}, ...
  {'abl:no_met', struct('use_met', false); 'abl:no_tmp', struct('use_tmp', false); 'abl:no_diurnal', struct('use_diurnal', false); 'abl:no_ar_resid', struct('use_ar_resid', false)}, ...
  {'abl:city_now', struct('interp_mode', 'city_now'); 'abl:time_interp', struct('interp_mode', 'time_interp'); 'abl:blend', struct('interp_mode', 'blend')} };

results = {};
for task = TASKS
    S = load(fullfile(ROOT, 'data', 'processed', ['devices_' city{task} '.mat']));
    dev = S.dev; is_static = logical(S.is_static);
    st = find(is_static);
    if strcmp(city{task}, 'tianjin')
        st = setdiff(st, [3 4 6]);   % 3,4 co-located with 1; 6 is faulty (see README)
    end
    tAll = cellfun(@(D) D(1,1), dev); t1All = cellfun(@(D) D(end,1), dev);
    tStart = floor(min(tAll)); tEnd = floor(max(t1All));
    switch task
        case 1, starts = (tStart + 3):(QUICK*0.5 + ~QUICK*(1/8)):(tEnd - 0.2);
        case 2, starts = (tStart + 7 + 0.25):(QUICK*2 + ~QUICK*0.5):(tEnd - 1);
        case 3, starts = tStart:(QUICK*3 + ~QUICK*1):(tEnd - 3);
    end
    Vt = [V; extra{task}];
    for nf = NOISE
        se = zeros(size(Vt,1),1); ss = 0; n = 0;
        for t0 = starts
            for h = st
                [tr, te, y] = make_task(dev, is_static, task, t0, h, nf, round(t0*100)+h);
                if any(~isfinite(y)) || isempty(tr), continue; end
                for v = 1:size(Vt,1)
                    if ischar(Vt{v,2})
                        p = baseline_pred(tr, te, task, Vt{v,2});
                    else
                        p = pm2d5_pred_model(tr, te, task, Vt{v,2});
                    end
                    se(v) = se(v) + sum((p - y).^2);
                end
                ss = ss + sum(y.^2); n = n + numel(y);
            end
        end
        sc = sqrt(se / n) / sqrt(ss / n);
        fprintf('\n=== task %d (%s)  noise %.1f sigma   [%d test values]\n', task, city{task}, nf, n);
        for v = 1:size(Vt,1)
            fprintf('  %-18s NRMSE = %.4f\n', Vt{v,1}, sc(v));
            results(end+1,:) = {task, nf, Vt{v,1}, sc(v)}; %#ok<SAGROW>
        end
    end
end
