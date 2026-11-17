# Competition predictions

`pred_<task>_<n>_var.mat` holds `pred_pm2d5` (M × 1, same row order as `test_data`) and `pred_sd` (1-σ uncertainty). The `.csv` copy has the columns `[pred_pm2d5, pred_sd]`.

Short-term (from `src/pm_short_term.m`, generated 11/17 in Octave from `data/competition`; MATLAB: `TASKS = 1; run('run_competition.m')`):

| Test site (lat, lon) | Noise 0 | 0.5σ | 1.0σ |
|---|---|---|---|
| 23.057191, 113.142105 | 77.01 | 76.98 | 76.57 |
| 23.044381, 113.142363 | 79.44 | 79.40 | 78.93 |
| 23.048606, 113.156814 | 78.40 | 78.38 | 77.96 |

The same value applies to all 3 hours: persistence. `pred_sd` is 4.3 / 5.2 / 6.2 for the 07:00 / 08:00 / 09:00 rows.

Checks on the competition data:
* The code's static/mobile separation agrees with the `separated_*` files: 430,643 static rows, 5 sites, none dropped.
* The level comes from the static EWMA, not a fallback.
* The time stamps mark hour **ends**: the test humidity at 07:00 equals the [06:00, 07:00) mean of the co-located Canvas sensor.
