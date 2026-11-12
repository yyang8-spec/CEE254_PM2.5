# Data cleaning (in progress)

Scripts in this folder read from `data/raw/` and write cleaned data to `data/processed/`.

## Files
| File | Owner | Status |
|------|-------|--------|
| `export_device_matrices.m` | | tables → numeric `dev{}` for validation |

## Cleaning decisions log
Log each decision as you make it. This becomes section (e) of the report, which has to describe the processing *quantitatively* (e.g. how many points were removed and how that changed NRMSE).

| Step | Decision | Why | Effect (rows removed, NRMSE change, …) |
|------|----------|-----|-----|
| Missing values | Drop rows with NaN time/PM/lat/lon; bins with no samples stay NaN and are skipped | The competition matrix "may contain missing values" | Raw Canvas files have 0 NaN PM; static gaps ≤ 75 s; mobile gaps up to 17 h (overnight) |
| Outliers / spikes | Drop PM > median + 12·1.4826·MAD (global); **no clipping of negatives** | Mobile spikes up to 1494 (Foshan) / 696 (Tianjin). Clipping noisy negatives would bias the means under the robustness test | TODO: count the rows removed per city |
| Time alignment / resampling | Bin means: 10 min (short-term), 60 min (long-term), 5 min (interp) | Bin averaging cuts the injected noise by ~√N (N ≈ 200–1200) | Backtest NRMSE changes < 0.002 from noise 0 to 1.0σ |
| GPS errors (mobile) | Drop (0,0) and points > 0.5° from the median | | TODO: count |
| Static vs. mobile merging | Static sites detected from repeated coordinates (≥ 50% hour coverage, median speed < 2). Co-located sensors merged. Sites with corr < 0.7 vs. the others dropped | No device ID in the competition matrix. Tianjin static #6 reads ~7.6 where mobile within 300 m reads ~36 | Mobile used only (optionally) for the local offset, after static calibration |

## Things to keep in mind
- Each device cell is a MATLAB `table` (see `data/raw/README.md`).
- The competition `train_data` will be a plain P×7 matrix that may contain missing values, so the cleaning has to run *inside* `pm2d5_pred_model` on that matrix as well, not only on the .mat files.
- The robustness tests add Gaussian noise to PM2.5. Smoothing or filtering here can help with those, but keep it consistent between training and the competition.
