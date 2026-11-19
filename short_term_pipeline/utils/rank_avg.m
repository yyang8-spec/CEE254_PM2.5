function rk = rank_avg(x)
%RANK_AVG  Ranks with ties averaged (for Spearman correlation; no toolbox needed).
[~, ~, j] = unique(x(:)); cnt = accumarray(j, 1);
avg = cumsum(cnt) - (cnt - 1) / 2; rk = avg(j);
end
