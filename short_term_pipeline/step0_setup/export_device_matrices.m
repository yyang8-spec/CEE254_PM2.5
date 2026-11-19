%EXPORT_DEVICE_MATRICES  Convert the Canvas .mat tables into plain numeric
% matrices in the competition column order, so the validation harness (and
% Octave) can use them.
%
% Output: data/processed/devices_<city>.mat with
%   dev       1 x K cell, each N x 7 double
%             [datenum, humidity, temperature, speed, pm2d5, lat, lon]
%   is_static 1 x K logical
%
% Run once in MATLAB:  run('short_term_pipeline/step0_setup/export_device_matrices.m')

% --- folder setup: finds short_term_pipeline/st_paths.m (Run, Run Section or run()) ---
if exist('st_paths', 'file') ~= 2
    cand = {fileparts(fileparts(mfilename('fullpath'))), fullfile(pwd, 'short_term_pipeline'), fullfile(pwd, '..'), pwd};
    for c = cand, if exist(fullfile(c{1}, 'st_paths.m'), 'file'), addpath(c{1}); break, end, end
end
P = st_paths();

files = {'short_term_foshan_train_val', 'long_term_tianjin_train_val'};
names = {'foshan', 'tianjin'};
for f = 1:numel(files)
    S = load(fullfile(P.root, 'data', 'raw', [files{f} '.mat']));
    dev = {}; is_static = false(0);
    groups = {'data_static', 'data_mobile'};
    for gi = 1:2
        C = S.(groups{gi});
        for i = 1:numel(C)
            T = sortrows(C{i}, 'time');
            t = T.time; t.TimeZone = '';
            dev{end+1} = [datenum(t), T.hmd, T.tmp, T.spd, T.pm2d5, T.lat, T.lon]; %#ok<SAGROW>
            is_static(end+1) = (gi == 1); %#ok<SAGROW>
        end
    end
    out = fullfile(P.processed, ['devices_' names{f} '.mat']);
    save(out, 'dev', 'is_static', '-v7');
    fprintf('%s: %d devices -> %s\n', names{f}, numel(dev), out);
end
