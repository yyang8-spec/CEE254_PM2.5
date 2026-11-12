%ST_COMPARE_SENSORS  Run st_single_sensor.m on all 5 Foshan static sensors and
% compare the models (pooled and per sensor), with and without noise.
%
%   run('short_term/st_compare_sensors.m')
% Set SKIP_RUN = true to only summarize existing short_term/results_s*.mat.

ROOT_CMP = fileparts(fileparts(mfilename('fullpath')));
if ~exist('SKIP_RUN', 'var'), SKIP_RUN = false; end
SENSORS_CMP = 1:5;
if ~SKIP_RUN
    for sCmp = SENSORS_CMP
        SENSOR = sCmp; MAKE_FIGS = false; SAVE_RESULTS = true; %#ok<NASGU>
        run(fullfile(ROOT_CMP, 'short_term', 'st_single_sensor.m'));
    end
end

R = cell(1, numel(SENSORS_CMP));
for k = 1:numel(SENSORS_CMP)
    R{k} = load(fullfile(ROOT_CMP, 'short_term', sprintf('results_s%d.mat', SENSORS_CMP(k))));
end
mdl = R{1}.models; nM = numel(mdl);
keys = {'noise_00', 'noise_05', 'noise_10'}; labs = {'0', '0.5', '1.0'};

for part = {'test', 'val'}
    isTest = strcmp(part{1}, 'test');
    fprintf('\n=== %s NRMSE, per sensor (noise 0) and pooled over all 5 sensors ===\n', upper(part{1}));
    fprintf('%-28s', 'model'); fprintf('   s%d  ', SENSORS_CMP);
    fprintf('| pooled n=0  n=0.5  n=1.0 | rank(n=1)\n');
    pooled = zeros(nM, 3);
    for q = 1:3
        for m = 1:nM
            se = 0; ss = 0;
            for k = 1:numel(R)
                e = R{k}.results.(keys{q}).errs(:,:,m); t = R{k}.results.(keys{q}).truth;
                sel = all(isfinite(e),2) & all(isfinite(t),2) & (R{k}.isVal(:) ~= isTest);
                se = se + sum(sum(e(sel,:).^2)); ss = ss + sum(sum(t(sel,:).^2));
            end
            pooled(m,q) = sqrt(se / ss);
        end
    end
    [~, ord] = sort(pooled(:,3)); rk(ord) = 1:nM;
    for m = 1:nM
        fprintf('%-28s', mdl{m});
        for k = 1:numel(R)
            e = R{k}.results.noise_00.errs(:,:,m); t = R{k}.results.noise_00.truth;
            sel = all(isfinite(e),2) & all(isfinite(t),2) & (R{k}.isVal(:) ~= isTest);
            fprintf(' %.3f', sqrt(sum(sum(e(sel,:).^2)) / sum(sum(t(sel,:).^2))));
        end
        fprintf(' |  %.4f %.4f %.4f |  %2d\n', pooled(m,:), rk(m));
    end
end

fprintf('\nEWMA tau chosen on validation (minutes):\n');
for k = 1:numel(R)
    fprintf('  sensor %d:', SENSORS_CMP(k));
    for q = 1:3, fprintf('  noise %s -> %g', labs{q}, R{k}.results.(keys{q}).tau); end
    fprintf('\n');
end
