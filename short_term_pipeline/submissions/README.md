# Competition predictions

`pred_<task>_<n>_var.mat` holds `pred_pm2d5` (M × 1, same row order as `test_data`) and `pred_sd` (1-σ uncertainty). The `.csv` copy has the columns `[pred_pm2d5, pred_sd]`.

Short-term (from `src/pm_short_term.m`, **τ = 2 min**; regenerated 11/19 after τ was re-selected on the development half of the backtest). In MATLAB: `TASKS = 1; run('run_competition.m')`.

| Test site (lat, lon) | Noise 0 | 0.5σ | 1.0σ |
|---|---|---|---|
| 23.057191, 113.142105 | 77.66 | 77.55 | 77.29 |
| 23.044381, 113.142363 | 80.08 | 79.97 | 79.65 |
| 23.048606, 113.156814 | 79.04 | 78.95 | 78.68 |

Expected `run_competition.m` means: 78.93 / 78.82 / 78.54. The previous τ = 5 version gave 78.28 / 78.25 / 77.82.

The same value applies to all 3 hours: persistence. `pred_sd` is 4.3 / 5.2 / 6.2 for the 07:00 / 08:00 / 09:00 rows.

Checks on the competition data:
* The code's static/mobile separation agrees with the `separated_*` files: 430,643 static rows, 5 sites, none dropped.
* The level comes from the static EWMA, not a fallback.
* The time stamps mark hour **ends**: the test humidity at 07:00 equals the [06:00, 07:00) mean of the co-located Canvas sensor.
