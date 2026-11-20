function pred_pm2d5 = pm_long_term(train_data, test_data, opts)
%PM_LONG_TERM  Long-term PM2.5 prediction (next 24 hours), problem_type 2.
%   pred_pm2d5: M x 1, same row order as test_data.
%   TODO (long-term owner): replace the line below with the long-term model.

if nargin < 3, opts = struct(); end
pred_pm2d5 = pm_draft_level_model(train_data, test_data, 2, opts);
end
