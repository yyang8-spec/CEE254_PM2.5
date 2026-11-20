function pred_pm2d5 = pm_interpolation(train_data, test_data, opts)
%PM_INTERPOLATION  Interpolation (5-min values on day 2), problem_type 3.
%
%   >>> PLACEHOLDER: the interpolation owner replaces the body of this
%   >>> function with their model (see team_submission/README.md).
%
%   Note (11/16 files): the test window is 22:40-23:35 on day 2, not the
%   11:30-12:25 of the handout, and time stamps mark interval ENDS.

if nargin < 3, opts = struct(); end
pred_pm2d5 = pm_draft_level_model(train_data, test_data, 3, opts);   % DRAFT model
end
