# Raw data

These are the original files from Canvas, unmodified. **Don't edit or overwrite them.** Cleaning scripts read from here and write to `data/processed/`.

| File | Size | City | Contents |
|------|------|------|----------|
| `short_term_foshan_train_val.mat` | ~19 MB | Foshan | `data_static` (1×5 cell), `data_mobile` (1×8 cell) |
| `long_term_tianjin_train_val.mat` | ~69 MB | Tianjin | `data_static` (1×6 cell), `data_mobile` (1×7 cell) |

Each cell holds one device's record. Columns, in order:

| # | Variable | Notes |
|---|----------|-------|
| 1 | time | ~3 s sampling |
| 2 | humidity | |
| 3 | temperature | |
| 4 | vehicle speed | static sensors should be ~0 |
| 5 | pm2d5 | PM2.5 (target) |
| 6 | latitude | static sensors should be constant |
| 7 | longitude | |

**Heads-up:** the course description calls each cell an N×7 *matrix*, but in the files each cell is actually a MATLAB **`table`**. If you need the matrix, use `table2array(data_static{i})` (or `T{:,:}`). Run `head(data_static{1})` to check the column names and time format first.

## Loading
```matlab
S = load(fullfile('data','raw','short_term_foshan_train_val.mat'));
data_static = S.data_static;   % 1×5 cell of tables
data_mobile = S.data_mobile;   % 1×8 cell of tables
head(data_static{1})
```
