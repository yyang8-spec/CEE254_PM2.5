function pred_pm2d5 = pm_interpolation(train_data, test_data, opts)
%PM_INTERPOLATION  PM2.5 interpolation (5-min values on day 2), problem_type 3.
%   pred_pm2d5: M x 1, same row order as test_data.
%   TODO (interpolation owner): replace the line below with the interpolation model.

if nargin < 3, opts = struct(); end
pred_pm2d5 = pm_draft_level_model(train_data, test_data, 3, opts);
end
