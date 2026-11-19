function p = baseline_pred(train_data, test_data, problem_type, name)
%BASELINE_PRED  Simple baselines required by the report (section g).
%   'train_mean'       mean of all training PM2.5
%   'nearest_persist'  last hour (types 1/2) or nearest-time value (type 3)
%                      of the static sensor nearest the test site
%   'daily_profile'    hour-of-day mean of all static data (types 1/2)
t = train_data(:,1); pm = train_data(:,5);
key = round(train_data(:,6:7) * 1e5);
[u, ~, g] = unique(key, 'rows'); cnt = accumarray(g, 1);
st = find(cnt > 0.2 * max(cnt));          % crude static-site detection
p = nan(size(test_data,1), 1);
for i = 1:size(test_data,1)
    switch name
        case 'train_mean'
            p(i) = mean(pm);
        case 'nearest_persist'
            d = (u(st,1)/1e5 - test_data(i,5)).^2 + ((u(st,2)/1e5 - test_data(i,6)) * cosd(test_data(i,5))).^2;
            [~, j] = min(d); m = g == st(j);
            ts = t(m); ps = pm(m);
            if problem_type == 3
                [~, k] = min(abs(ts - test_data(i,1))); w = abs(ts - ts(k)) < 5/1440;
                p(i) = mean(ps(w));
            else
                p(i) = mean(ps(ts >= max(ts) - 1/24));
            end
        case 'daily_profile'
            hod = mod(floor(t * 24), 24); h0 = mod(floor(test_data(i,1) * 24), 24);
            p(i) = mean(pm(hod == h0));
    end
end
end
