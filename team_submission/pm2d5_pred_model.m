function [pred_pm2d5, pred_std] = pm2d5_pred_model(train_data, test_data, problem_type, opts)
%PM2D5_PRED_MODEL  CEE 254 PM2.5 prediction.
%
%   pred_pm2d5 = pm2d5_pred_model(train_data, test_data, problem_type)
%
%   train_data    table, P x 7 matrix [time hmd tmp spd pm2d5 lat lon], or a
%                 struct with static and mobile tables (separated_train_data)
%   test_data     table, or M x 6 matrix [time hmd tmp spd lat lon]
%   problem_type  1 = short-term, 2 = long-term, 3 = interpolation
%   pred_pm2d5    M x 1 predicted PM2.5, same row order as test_data
%   pred_std      M x 1 standard deviation if available, otherwise NaN

if nargin < 4 || isempty(opts), opts = struct(); end
M = n_rows(test_data);
merged = merge_train(train_data);          % one table / matrix with all devices

switch problem_type
    case 1
        [pred_pm2d5, pred_std] = pm_short_term(merged, test_data, opts);
    case 2
        % the long-term model takes static and mobile data separately and the
        % noise level of the training data
        if ~isstruct(train_data)
            isSt = static_rows(merged);
            train_data = struct('train_data_static', merged(isSt, :), ...
                                'train_data_mobile', merged(~isSt, :));
        end
        if ~isfield(opts, 'var_level')
            opts.var_level = noise_level(train_data.train_data_static);
        end
        pred_pm2d5 = pm_long_term(train_data, test_data, opts);
        pred_std = nan(M, 1);
    case 3
        pred_pm2d5 = pm_interpolation(merged, test_data, opts);
        pred_std = nan(M, 1);
    otherwise
        error('pm2d5_pred_model: problem_type must be 1, 2 or 3');
end

% output check: M x 1, missing values replaced by the training mean
pred_pm2d5 = double(pred_pm2d5(:));
if numel(pred_pm2d5) ~= M
    error('pm2d5_pred_model: task %d returned %d values for %d test rows', problem_type, numel(pred_pm2d5), M);
end
bad = ~isfinite(pred_pm2d5);
if any(bad)
    pm = col(merged, 'pm2d5'); fill = mean(pm(isfinite(pm)));
    if ~isfinite(fill), fill = 0; end
    pred_pm2d5(bad) = fill;
end
pred_std = double(pred_std(:));
end

function X = merge_train(X)
% struct of tables (e.g. train_data_static, train_data_mobile) -> one table
if isstruct(X)
    f = fieldnames(X); parts = {};
    for i = 1:numel(f), parts{end+1} = X.(f{i}); end %#ok<AGROW>
    X = vertcat(parts{:});
end
end

function n = n_rows(X)
if isa(X, 'table'), n = height(X); else, n = size(X, 1); end
end

function v = col(X, name)
% column of a table, or of a matrix [time hmd tmp spd pm2d5 lat lon]
if isa(X, 'table'), v = X.(name); return, end
switch name
    case 'time',  v = X(:, 1);
    case 'pm2d5', v = X(:, 5);
    case 'lat',   v = X(:, 6);
    case 'lon',   v = X(:, 7);
    case 'spd'
        if median(X(:, 3)) < median(X(:, 4)), v = X(:, 3); else, v = X(:, 4); end
end
end

function t = days_of(t)
if isa(t, 'datetime'), t.TimeZone = ''; t = datenum(t); end
end

function isSt = static_rows(X)
% static sensor rows: a fixed coordinate with data in at least half of the
% hours, low median speed, and at least 5% of the busiest coordinate's samples
t = days_of(col(X, 'time'));
[~, ~, g] = unique(round([col(X, 'lat') col(X, 'lon')] * 1e5), 'rows');
cnt = accumarray(g, 1);
th = floor(t * 24); nHours = max(th) - min(th) + 1;
spd = col(X, 'spd');
isSite = false(numel(cnt), 1);
for c = find(cnt > 200 & cnt >= 0.05 * max(cnt))'
    k = (g == c);
    isSite(c) = numel(unique(th(k))) / nHours >= 0.5 && median(spd(k)) < 2;
end
isSt = isSite(g);
end

function lvl = noise_level(S)
% Noise level of the training PM2.5 (0, 5 or 10 = 0, 0.5 or 1.0 x the clean
% sd), from the spread of consecutive readings of each static sensor.
t = days_of(col(S, 'time')); pm = col(S, 'pm2d5');
[~, ~, g] = unique(round([col(S, 'lat') col(S, 'lon')] * 1e5), 'rows');
[~, o] = sortrows([g t]); g = g(o); t = t(o); pm = pm(o);
same = diff(g) == 0 & diff(t) * 86400 <= 10;
d = diff(pm); d = d(same & isfinite(d));
if numel(d) < 100, lvl = 0; return, end
nsd = 1.4826 * median(abs(d - median(d))) / sqrt(2);
tot = std(pm(isfinite(pm)));
r = nsd / sqrt(max(tot^2 - nsd^2, eps));
if r < 0.25, lvl = 0; elseif r < 0.75, lvl = 5; else, lvl = 10; end
end
