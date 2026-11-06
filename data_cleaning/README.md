# Data cleaning (in progress)

Scripts in this folder read from `data/raw/` and write cleaned data to `data/processed/`.

## Files
| File | Owner | Status |
|------|-------|--------|
| | | |

## Cleaning decisions log
Log each decision as you make it. This becomes section (e) of the report, which has to describe the processing *quantitatively* (e.g. how many points were removed and how that changed NRMSE).

| Step | Decision | Why | Effect (rows removed, NRMSE change, …) |
|------|----------|-----|-----|
| Missing values | | | |
| Outliers / spikes | | | |
| Time alignment / resampling | | | |
| GPS errors (mobile) | | | |
| Static vs. mobile merging | | | |

## Things to keep in mind
- Each device cell is a MATLAB `table` (see `data/raw/README.md`).
- The competition `train_data` will be a plain P×7 matrix that may contain missing values, so the cleaning has to run *inside* `pm2d5_pred_model` on that matrix as well, not only on the .mat files.
- The robustness tests add Gaussian noise to PM2.5. Smoothing or filtering here can help with those, but keep it consistent between training and the competition.
