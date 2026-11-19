function r = spearman_nan(a, b)
%SPEARMAN_NAN  Spearman correlation over the rows where both inputs are finite.
v = isfinite(a) & isfinite(b);
r = corr_nan(rank_avg(a(v)), rank_avg(b(v)));
end
