function m = trailing_mean(x, k)
%TRAILING_MEAN  Mean of the last k samples (inclusive), ignoring NaN.
% Same result in MATLAB and Octave (Octave's movmean has no 'omitnan').
x = x(:); ok = isfinite(x); x(~ok) = 0;
m = movsum(x, [k-1 0]) ./ movsum(double(ok), [k-1 0]);
end
