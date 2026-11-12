%VARIABLE_CORRELATION  Which variables are worth putting in the model?
%
% For each city, correlates PM2.5 with every candidate input at two scales:
%   (a) raw 3-s samples (static and mobile separately)
%   (b) hourly city level from the static sensors - the scale the model uses
% It also reports how stable each correlation is from one training window to
% the next, because the competition model is re-fitted on a single window
% (3 days or 1 week). A variable whose correlation flips sign between windows
% is risky even when its pooled correlation looks large.
%
% Run from the repo root (needs data/processed/devices_*.mat):
%   run('analysis/variable_correlation.m')
% Set MAKE_FIGS = false to skip plotting (e.g. in Octave without a display).
%
% Correlation only screens variables. The final in/out decision is the
% ablation NRMSE from validation/run_validation.m.

ROOT = fileparts(fileparts(mfilename('fullpath')));
if ~exist('MAKE_FIGS', 'var'), MAKE_FIGS = true; end
cities = {'foshan', 'tianjin'};
winDays = [3 7];           % competition training window per city
badStatic = {[], 6};       % Tianjin static #6 is faulty (see docs/PLAN.md)

for c = 1:2
    S = load(fullfile(ROOT, 'data', 'processed', ['devices_' cities{c} '.mat']));
    dev = S.dev; isSt = logical(S.is_static);
    stIdx = find(isSt); stIdx = setdiff(stIdx, badStatic{c});
    st = vertcat(dev{stIdx}); mob = vertcat(dev{~isSt});
    % columns: 1 t, 2 hmd, 3 tmp, 4 spd, 5 pm, 6 lat, 7 lon
    names = {'hmd', 'tmp', 'spd', 'lat', 'lon'}; cols = [2 3 4 6 7];

    fprintf('\n================ %s ================\n', upper(cities{c}));
    fprintf('(a) raw 3-s samples           Pearson / Spearman\n');
    for k = 1:numel(cols)
        fprintf('  %-4s  static %6.3f / %6.3f   mobile %6.3f / %6.3f\n', names{k}, ...
            pearson(st(:,5), st(:,cols(k))), spearman(st(:,5), st(:,cols(k))), ...
            pearson(mob(:,5), mob(:,cols(k))), spearman(mob(:,5), mob(:,cols(k))));
    end

    % ---- hourly city level --------------------------------------------------
    h = floor(st(:,1) * 24); [uh, ~, g] = unique(h);
    PM = accumarray(g, st(:,5), [], @mean);
    RH = accumarray(g, st(:,2), [], @mean);
    TM = accumarray(g, st(:,3), [], @mean);
    hod = mod(uh, 24);
    % put on a regular hourly grid so lags are real lags
    hg = (uh(1):uh(end))'; n = numel(hg);
    pm = nan(n,1); rh = pm; tm = pm; hd = mod(hg, 24);
    pm(uh - uh(1) + 1) = PM; rh(uh - uh(1) + 1) = RH; tm(uh - uh(1) + 1) = TM;
    td = dewpoint(tm, rh);
    F = struct();
    F.humidity      = rh;
    F.temperature   = tm;
    F.dew_point     = td;
    F.hour_sin      = sin(2*pi*hd/24);
    F.hour_cos      = cos(2*pi*hd/24);
    F.d_humidity_3h = [nan(3,1); rh(4:end) - rh(1:end-3)];
    F.pm_lag_1h     = [NaN; pm(1:end-1)];
    F.pm_lag_3h     = [nan(3,1); pm(1:end-3)];
    F.pm_lag_24h    = [nan(24,1); pm(1:end-24)];
    fn = fieldnames(F);

    fprintf('\n(b) hourly city level (static mean), %d hours\n', sum(isfinite(pm)));
    fprintf('  %-14s %8s %8s   per-%dd-window Pearson (stability)\n', 'feature', 'Pearson', 'Spearman', winDays(c));
    nWin = floor(n / (24 * winDays(c)));
    R = zeros(numel(fn), 2);
    for k = 1:numel(fn)
        x = F.(fn{k});
        R(k,:) = [pearson(pm, x), spearman(pm, x)];
        rw = zeros(1, nWin);
        for w = 1:nWin
            idx = (w-1)*24*winDays(c) + (1:24*winDays(c));
            rw(w) = pearson(pm(idx), x(idx));
        end
        fprintf('  %-14s %8.3f %8.3f   %s\n', fn{k}, R(k,1), R(k,2), sprintf('%6.2f', rw));
    end

    % hour-of-day: correlation ratio eta^2 (share of variance explained by hour)
    v = isfinite(pm); m = accumarray(hd(v) + 1, pm(v), [24 1], @mean);
    cnt = accumarray(hd(v) + 1, 1, [24 1]);
    eta2 = sum(cnt .* (m - mean(pm(v))).^2) / sum((pm(v) - mean(pm(v))).^2);
    fprintf('  hour-of-day correlation ratio eta^2 = %.3f\n', eta2);

    % partial correlation of humidity given temperature
    v = isfinite(pm) & isfinite(rh) & isfinite(tm);
    r_ph = pearson(pm(v), rh(v)); r_pt = pearson(pm(v), tm(v)); r_ht = pearson(rh(v), tm(v));
    pc = (r_ph - r_pt*r_ht) / sqrt((1 - r_pt^2) * (1 - r_ht^2));
    fprintf('  corr(humidity, temperature) = %.3f, partial corr(PM, humidity | temperature) = %.3f\n', r_ht, pc);

    % mobile: does vehicle speed matter?
    edges = [-1 1 10 30 60 200];
    fprintf('  mobile PM median by speed bin:');
    for b = 1:numel(edges)-1
        mb = mob(:,4) > edges(b) & mob(:,4) <= edges(b+1);
        fprintf('  (%g,%g]: %.1f', edges(b), edges(b+1), median(mob(mb,5)));
    end
    fprintf('\n');

    if MAKE_FIGS
        fig = figure('Color', 'w', 'Position', [100 100 1200 400]);
        subplot(1,3,1); scatter(rh, pm, 8, 'filled'); xlabel('humidity (%)'); ylabel('PM2.5');
        title(sprintf('%s hourly: r = %.2f', cities{c}, pearson(pm, rh))); grid on;
        subplot(1,3,2); scatter(tm, pm, 8, 'filled'); xlabel('temperature (C)'); ylabel('PM2.5');
        title(sprintf('r = %.2f', pearson(pm, tm))); grid on;
        subplot(1,3,3); barh(R(:,1)); set(gca, 'YTick', 1:numel(fn), 'YTickLabel', strrep(fn, '_', ' '));
        xlabel('Pearson r with hourly PM2.5'); xlim([-1 1]); grid on;
        title('candidate features');
        out = fullfile(ROOT, 'figures', ['correlation_' cities{c} '.png']);
        print(fig, out, '-dpng', '-r150'); fprintf('  saved %s\n', out);
    end
end

function r = pearson(a, b)
v = isfinite(a) & isfinite(b); a = a(v); b = b(v);
if numel(a) < 3, r = NaN; return; end
a = a - mean(a); b = b - mean(b);
r = sum(a .* b) / sqrt(sum(a.^2) * sum(b.^2));
end

function r = spearman(a, b)
v = isfinite(a) & isfinite(b);
r = pearson(ranks(a(v)), ranks(b(v)));
end

function rk = ranks(x)
% average ranks for ties, vectorized (no Statistics Toolbox needed)
[~, ~, j] = unique(x(:));          % j = index of each value in sorted uniques
cnt = accumarray(j, 1);
avg = cumsum(cnt) - (cnt - 1) / 2; % mean rank of each tie group
rk = avg(j);
end

function td = dewpoint(T, RH)
a = 17.62; b = 243.12;
g = log(min(max(RH, 1), 100) / 100) + a * T ./ (b + T);
td = b * g ./ (a - g);
end
