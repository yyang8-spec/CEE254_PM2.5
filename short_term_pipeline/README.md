# Short-term PM2.5 prediction pipeline (problem_type 1)

Everything for the short-term task is in this folder: preprocessing, correlation, model comparison, validation, the final model and the competition predictions. Each step is a MATLAB script that prints its intermediate results and saves a figure.

## Run it in MATLAB

Set MATLAB's current folder to the **repo root** (the folder that contains `short_term_pipeline/` and `data/`).

```matlab
run('short_term_pipeline/step0_setup/export_device_matrices.m')   % once: data/raw -> data/processed
run('short_term_pipeline/RUN_ALL.m')                               % steps 1-5, a few minutes
```

You can also open any step script and press **Run**, or run it one section at a time (click inside a `%%` section, then Ctrl+Enter / Cmd+Enter). Steps 3 and 4 show **saved** results of the long validations by default. Set `RECOMPUTE = true` first to recompute them (about 30 min and 1 h).

| Step | Script | Shows |
|---|---|---|
| 0 | `step0_setup/export_device_matrices.m` | Converts the Canvas tables into numeric device matrices (`data/processed/devices_<city>.mat`) |
| 1 | `step1_preprocessing/step1_preprocessing.m` | Per-device summary; missing values and GPS; spike removal (rows per device); live demo of the static/mobile separation and the parked-vehicle rule (4 vs 72 "sites"); faulty-site correlation check; noise reduction from binning; the model's cleaning log on one window |
| 2 | `step2_correlation/step2_correlation.m` | Pearson/Spearman r of each variable with PM2.5; stability per 3-day window; partial correlation of humidity given temperature; correlation with the 1–3 h **change**; autocorrelation; vehicle speed; keep/drop decision |
| 3 | `step3_model_comparison/step3_model_comparison.m` | Single-sensor study on all 5 sensors: baselines, linear regression, ridge (λ on validation), EWMA smoothing, trailing means; validation vs test NRMSE at 3 noise levels |
| 4 | `step4_validation/step4_validation.m` | Final model, leave-one-sensor-out: τ chosen on the development half; held-out test NRMSE with ablations, τ sensitivity and baselines; uncertainty calibration; missing-data fallback; one forecast step by step |
| 5 | `step5_competition/step5_competition.m` | Predictions for the 3 short-term competition files (noise 0 / 0.5 / 1.0σ), written to `submissions/` |

## Folders

| Folder | Contents |
|---|---|
| `model/` | **`pm_short_term.m`** (the short-term model) and `pm2d5_pred_model.m` (competition entry point; calls `pm_short_term` for problem_type 1; it also contains draft long-term and interpolation models) |
| `utils/` | `make_task.m` (competition-style tasks from the device data), `baseline_pred.m`, `nrmse.m`, correlation helpers, `run_validation.m` (backtest for all 3 tasks) |
| `step*/` | The step scripts above and the scripts they call (`st_single_sensor.m`, `st_compare_sensors.m`, `st_validate.m`, ...) |
| `results/` | Saved results of the long runs (`.mat`), read by steps 3 and 4 |
| `figures/` | Figures written by the steps |
| `submissions/` | Competition predictions `pred_<task>_<n>_var.mat` (`pred_pm2d5`, `pred_sd`) |
| `docs/` | `short_term_report.md` (report text), `short_term_notes.md` (detailed experiment log), `PLAN.md` (whole-project plan) |

## Final model in one paragraph

**Multi-sensor persistence with exponential smoothing and a spatial offset correction.**
1. Clean the 3-day training window: missing rows, GPS errors, gross spikes (median + 12·MAD); negative values are never clipped.
2. Find the static sensors from repeated coordinates, using the parked-vehicle rule. Drop sensors that don't track the others.
3. From 10-min bin means, estimate a city level and a fixed offset per sensor.
4. The current level is an EWMA (τ = 2 min, chosen on the development half) of the raw offset-corrected static samples. It is held for the next 3 hours.
5. Add the test site's offset, an inverse-distance weighting of the sensors' offsets.

Held-out test NRMSE: 0.2038 / 0.2052 / 0.2073 at noise 0 / 0.5 / 1.0σ, against 0.2332 / 0.2329 / 0.2327 for nearest-sensor last-hour persistence.

Tested in GNU Octave 8.4; the code uses base MATLAB only, and an earlier version matched a MATLAB run to 4 decimals.
