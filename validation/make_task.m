function [train_data, test_data, truth] = make_task(dev, is_static, problem_type, t0, holdout, noise_frac, seed)
%MAKE_TASK  Build one competition-style task from the device matrices.
%
%   dev, is_static  from data/processed/devices_<city>.mat
%   problem_type    1 short-term, 2 long-term, 3 interpolation
%   t0              datenum: forecast start (types 1/2) or day-1 midnight (type 3)
%   holdout         index into dev of the static sensor used as the test site.
%                   It is removed from train_data entirely, because the real
%                   test sites are "different from the sensor locations".
%   noise_frac      0, 0.5 or 1.0  (noise sd = noise_frac * std(train pm))
%
%   Ground truth = mean of the held-out sensor over [t, t+step).
%   ASSUMPTION: the course has not said whether "hourly PM2.5" is a bin mean
%   or a point value. Check this when the 11/16 data comes out.

if nargin < 6, noise_frac = 0; end
if nargin < 7, seed = 1; end
switch problem_type
    case 1, trWin = [t0 - 3, t0];  step = 1/24;  nOut = 3;  tq = t0 + (0:nOut-1)' * step;
    case 2, trWin = [t0 - 7, t0];  step = 1/24;  nOut = 24; tq = t0 + (0:nOut-1)' * step;
    case 3, trWin = [t0, t0 + 3];  step = 5/1440; nOut = 12;
            tq = t0 + 1 + 11.5/24 + (0:nOut-1)' * step;
end

train_data = [];
for i = 1:numel(dev)
    if i == holdout, continue; end
    D = dev{i};
    m = D(:,1) >= trWin(1) & D(:,1) < trWin(2);
    if problem_type == 3        % blank the test window (all devices)
        m = m & ~(D(:,1) >= tq(1) & D(:,1) < tq(end) + step);
    end
    train_data = [train_data; D(m,:)]; %#ok<AGROW>
end
if noise_frac > 0
    rand('seed', seed); randn('seed', seed); %#ok<RAND>
    sig = std(train_data(:,5));
    train_data(:,5) = train_data(:,5) + noise_frac * sig * randn(size(train_data,1),1);
end

H = dev{holdout};
test_data = nan(nOut, 6); truth = nan(nOut, 1);
for j = 1:nOut
    m = H(:,1) >= tq(j) & H(:,1) < tq(j) + step;
    test_data(j,:) = [tq(j), mean(H(m,2)), mean(H(m,3)), mean(H(m,4)), median(H(:,6)), median(H(:,7))];
    truth(j) = mean(H(m,5));
end
end
