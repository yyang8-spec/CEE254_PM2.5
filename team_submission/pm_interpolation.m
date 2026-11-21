function pred_pm2d5 = pm_interpolation(train_data, test_data, opts)
%PM_INTERPOLATION  PM2.5 interpolation (5-min values on day 2), problem_type 3.
%   pred_pm2d5: M x 1, same row order as test_data.
%   Converts the graders' tables to the matrix layout that
%   pm2d5_interp_model expects, then runs the space-time kernel model.

if nargin < 3, opts = struct(); end
Xtrain = interp_to_matrix(train_data, true);
Xtest  = interp_to_matrix(test_data, false);
pred_pm2d5 = pm2d5_interp_model(Xtrain, Xtest, opts);
end

function X = interp_to_matrix(T, hasPM)
% Table -> [time hmd tmp spd (pm2d5) lat lon]; matrices pass through unchanged.
% Only time, pm2d5, lat and lon are used by the model; weather is NaN-filled
% if a column is missing.
if ~istable(T), X = double(T); return, end
n = height(T);
t = T.time;
if isdatetime(t), t = datenum(t); end
X = [double(t), getCol(T, 'hmd', n), getCol(T, 'tmp', n), getCol(T, 'spd', n)];
if hasPM, X = [X, double(T.pm2d5)]; end
X = [X, double(T.lat), double(T.lon)];
end

function v = getCol(T, name, n)
if any(strcmp(T.Properties.VariableNames, name)), v = double(T.(name));
else, v = NaN(n, 1); end
end
