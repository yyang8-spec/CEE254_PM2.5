function pred_pm2d5 = pm_long_term(train_data, test_data, opts)
%PM_LONG_TERM  Long-term (next 24 h) prediction, problem_type 2.
%
%   >>> PLACEHOLDER: the long-term owner replaces the body of this function
%   >>> with their model (see team_submission/README.md for the contract).
%
%   Inputs exactly as the graders pass them: train_data / test_data are
%   MATLAB tables (columns time hmd spd tmp pm2d5 lat lon) or the handout
%   matrices. Output: M x 1 PM2.5, same row order as test_data.

if nargin < 3, opts = struct(); end
pred_pm2d5 = pm_draft_level_model(train_data, test_data, 2, opts);   % DRAFT model
end
