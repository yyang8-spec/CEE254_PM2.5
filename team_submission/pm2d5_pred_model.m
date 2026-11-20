function [pred_pm2d5, pred_std] = pm2d5_pred_model(train_data, test_data, problem_type, opts)
%PM2D5_PRED_MODEL  CEE 254 PM2.5 prediction.
%
%   pred_pm2d5 = pm2d5_pred_model(train_data, test_data, problem_type)
%
%   train_data    table, or P x 7 matrix [time hmd tmp spd pm2d5 lat lon]
%   test_data     table, or M x 6 matrix [time hmd tmp spd lat lon]
%   problem_type  1 = short-term, 2 = long-term, 3 = interpolation
%   pred_pm2d5    M x 1 predicted PM2.5, same row order as test_data
%   pred_std      M x 1 standard deviation if available, otherwise NaN

if nargin < 4 || isempty(opts), opts = struct(); end
M = n_rows(test_data);

switch problem_type
    case 1
        [pred_pm2d5, pred_std] = pm_short_term(train_data, test_data, opts);
    case 2
        pred_pm2d5 = pm_long_term(train_data, test_data, opts);
        pred_std = nan(M, 1);
    case 3
        pred_pm2d5 = pm_interpolation(train_data, test_data, opts);
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
    pm = train_pm(train_data); fill = mean(pm(isfinite(pm)));
    if ~isfinite(fill), fill = 0; end
    pred_pm2d5(bad) = fill;
end
pred_std = double(pred_std(:));
end

function n = n_rows(X)
if isa(X, 'table'), n = height(X); else, n = size(X, 1); end
end

function pm = train_pm(X)
if isa(X, 'table'), pm = X.pm2d5; else, pm = X(:, 5); end
end
