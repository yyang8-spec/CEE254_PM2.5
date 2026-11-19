function r = corr_nan(a, b)
%CORR_NAN  Pearson correlation over the rows where both inputs are finite.
v = isfinite(a) & isfinite(b);
if sum(v) < 3, r = NaN; return; end
a = a(v) - mean(a(v)); b = b(v) - mean(b(v));
r = sum(a .* b) / sqrt(sum(a.^2) * sum(b.^2));
end
