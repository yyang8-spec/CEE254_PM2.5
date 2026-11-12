function e = nrmse(pred, truth)
%NRMSE  RMSE(pred, truth) / RMS(truth), the competition metric.
v = isfinite(pred) & isfinite(truth);
e = sqrt(mean((pred(v) - truth(v)).^2)) / sqrt(mean(truth(v).^2));
end
