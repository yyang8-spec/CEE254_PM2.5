%STEP2_CORRELATION  Which variables are related to PM2.5? Intermediate results.
%
% On the hourly city level (mean of the Foshan static sensors), prints:
%   2a Pearson and Spearman r of PM2.5 with each candidate input
%   2b stability: r within each 3-day window (what the model is fitted on)
%   2c partial correlation of humidity given temperature
%   2d the forecasting question: correlation with the CHANGE over 1-3 h
%   2e autocorrelation (persistence) and vehicle speed (mobile sensors)
%   2f decision table: keep / drop each variable
% Saves results/step2_correlation.mat and figures/step2_correlation.png.
% (Both cities, raw + hourly: step2_correlation/variable_correlation.m)

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();
S = load(fullfile(P.processed, 'devices_foshan.mat'));
dev = S.dev; is_static = logical(S.is_static); st = find(is_static);
pr  = @(a, b) corr_nan(a, b);         % utils/corr_nan.m
spr = @(a, b) spearman_nan(a, b);     % utils/spearman_nan.m

X = cell2mat(dev(st)');
h = floor(X(:,1) * 24); [uh, ~, g] = unique(h);
hg = (uh(1):uh(end))'; n = numel(hg); k = uh - uh(1) + 1;
y = nan(n,1); rh = y; tm = y;
y(k) = accumarray(g, X(:,5), [], @mean); rh(k) = accumarray(g, X(:,2), [], @mean); tm(k) = accumarray(g, X(:,3), [], @mean);
hod = mod(hg, 24); lag = @(x, L) [nan(L,1); x(1:end-L)];
a = 17.62; bb = 243.12; gm = log(min(max(rh,1),100)/100) + a*tm./(bb+tm); td = bb*gm./(a-gm);

%% 2a. Correlation with hourly PM2.5
names = {'PM 1 h ago', 'PM 3 h ago', 'PM 24 h ago', 'temperature', 'humidity', 'dew point', 'hour of day (sin)', 'hour of day (cos)'};
F = {lag(y,1), lag(y,3), lag(y,24), tm, rh, td, sin(2*pi*hod/24), cos(2*pi*hod/24)};
fprintf('\n===== STEP 2: CORRELATION (Foshan hourly city level, %d hours) =====\n', sum(isfinite(y)));
fprintf('\n--- 2a / 2b. Correlation with PM2.5, and its stability per 3-day window ---\n');
fprintf('  %-20s %8s %9s   per-3-day-window Pearson\n', 'feature', 'Pearson', 'Spearman');
R = zeros(numel(names), 2); nW = floor(n / 72);
for i = 1:numel(names)
    R(i,:) = [pr(y, F{i}), spr(y, F{i})];
    rw = arrayfun(@(w) pr(y((w-1)*72 + (1:72)), F{i}((w-1)*72 + (1:72))), 1:nW);
    fprintf('  %-20s %8.3f %9.3f   %s\n', names{i}, R(i,1), R(i,2), sprintf('%7.2f', rw));
end

%% 2c. Partial correlation of humidity given temperature
v = isfinite(y) & isfinite(rh) & isfinite(tm);
r1 = pr(y(v), rh(v)); r2 = pr(y(v), tm(v)); r3 = pr(rh(v), tm(v));
pc = (r1 - r2*r3) / sqrt((1-r2^2)*(1-r3^2));
fprintf('\n--- 2c. Humidity vs temperature ---\n');
fprintf('  r(PM, humidity) = %.3f, r(humidity, temperature) = %.3f, partial r(PM, humidity | temperature) = %.3f\n', r1, r3, pc);
fprintf('  -> in a linear model humidity adds little beyond temperature (does not rule out nonlinear effects)\n');

%% 2d. The forecasting question: what is related to the CHANGE over the next h hours?
fprintf('\n--- 2d. Correlation with the change y(t+h) - y(t), features known at time t ---\n');
fprintf('  %-34s %8s %8s %8s\n', 'feature', 'h = 1', 'h = 2', 'h = 3');
chg = cell(1,3); for hh = 1:3, chg{hh} = [y(1+hh:end) - y(1:end-hh); nan(hh,1)]; end
cf = {'most recent 1-h trend y(t)-y(t-1)', y - lag(y,1); 'deviation from 3-day mean', y - trailing_mean(y, 72); 'hour of day (cos)', cos(2*pi*hod/24)};
D2 = zeros(size(cf,1) + 1, 3);
for i = 1:size(cf,1)
    D2(i,:) = arrayfun(@(hh) pr(chg{hh}, cf{i,2}), 1:3);
    fprintf('  %-34s %8.3f %8.3f %8.3f\n', cf{i,1}, D2(i,:));
end
for hh = 1:3, dT = [tm(1+hh:end) - tm(1:end-hh); nan(hh,1)]; D2(end,hh) = pr(chg{hh}, dT); end
fprintf('  %-34s %8.3f %8.3f %8.3f\n', 'temperature change over horizon', D2(end,:));
fprintf('  -> recent trend: moderate (momentum); weather / hour of day: weak.\n');
fprintf('     Whether the trend helps OUT OF SAMPLE is tested in step 3 (it does not).\n');

%% 2e. Autocorrelation and vehicle speed
acf = arrayfun(@(L) pr(y(1+L:end), y(1:end-L)), 1:48);
fprintf('\n--- 2e. Autocorrelation of hourly PM2.5 ---\n');
fprintf('  lag 1 h %.2f | 3 h %.2f | 6 h %.2f | 12 h %.2f | 24 h %.2f\n', acf([1 3 6 12 24]));
M = cell2mat(dev(~is_static)'); edges = [-1 1 10 30 60 200];
fprintf('  mobile PM median by vehicle speed bin:');
for i = 1:numel(edges)-1
    m = M(:,4) > edges(i) & M(:,4) <= edges(i+1);
    fprintf('  (%g,%g]: %.1f', edges(i), edges(i+1), median(M(m,5)));
end
fprintf('\n  -> PM is persistent over hours, not daily; speed has no visible effect (and test sites are fixed).\n');

%% 2f. Decision
fprintf('\n--- 2f. Decision for the short-term model ---\n');
fprintf('  keep : recent PM level (persistence, r = %.2f at lag 1 h)\n', acf(1));
fprintf('  test : recent trend, temperature/humidity change, hour of day -> regression in step 3\n');
fprintf('  drop : PM 24 h ago (r = %.2f), vehicle speed, lat/lon as linear inputs (location enters via site offsets)\n', R(3,1));

f = figure('Color', 'w', 'Name', 'Step 2: correlation', 'Position', [60 60 1200 400]);
subplot(1,3,1); barh(R(:,1)); set(gca, 'YTick', 1:numel(names), 'YTickLabel', names); xlim([-1 1]); grid on;
xlabel('Pearson r with PM2.5'); title('2a. level');
subplot(1,3,2); bar(D2'); set(gca, 'XTickLabel', {'h=1','h=2','h=3'}); grid on; ylim([-0.6 0.6]);
legend({'1-h trend', 'dev. from 3-day mean', 'hour (cos)', 'temp change'}, 'Location', 'southoutside'); title('2d. change over h hours');
subplot(1,3,3); stem(1:48, acf, 'filled'); grid on; xlabel('lag (h)'); ylabel('ACF'); title('2e. autocorrelation');
print(f, fullfile(P.figures, 'step2_correlation.png'), '-dpng', '-r150');
save(fullfile(P.results, 'step2_correlation.mat'), 'names', 'R', 'D2', 'acf', 'pc', '-v7');
fprintf('\nsaved figures/step2_correlation.png and results/step2_correlation.mat\n');
