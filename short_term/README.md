# Short-term prediction: single-sensor study

`st_single_sensor.m` runs three stages on **Foshan static #3**: cleaning, correlation, models. Set `SENSOR` to use another one. Run from the repo root:

```matlab
run('short_term/st_single_sensor.m')     % needs data/processed/devices_foshan.mat
```

The script saves `figures/st_s3_cleaning.png`, `st_s3_correlation.png` and `st_s3_forecasts.png`.

**Why #3:** all five Foshan static sensors are equally clean (6–9 gaps > 6 s, longest 72–75 s). #3 has the highest mean hourly correlation with the other four (0.969), so it is the most representative of the city-wide signal.

**Task:** from each hourly origin (11-Oct 00:00 to 15-Oct 21:00, 118 origins), use only the previous 3 days to predict the mean PM2.5 of each of the next 3 hours. Origins are split by time: the first 59 are validation (model and λ selection), the last 59 are test (reported once). The truth is always the clean signal; noise is added only to the training input, as in the competition.

## Results (11/13, Octave)

| Model | Val NRMSE | Test NRMSE | Test 1.0σ noise | Test h=1/2/3 |
|---|---|---|---|---|
| B0 training mean | 0.565 | 0.383 | 0.382 | 0.37 / 0.38 / 0.39 |
| B3 daily profile | 0.689 | 0.444 | 0.443 | 0.44 / 0.44 / 0.45 |
| B1 persistence, last 1 h | 0.111 | 0.165 | 0.166 | 0.10 / 0.16 / 0.21 |
| **B2 persistence, last 10 min** | 0.097 | **0.152** | 0.161 | 0.07 / 0.15 / 0.20 |
| M1 linear regression on levels | 0.128 | 0.161 | 0.169 | 0.08 / 0.16 / 0.22 |
| M2 ridge on the change, no intercept (λ = 1000) | **0.091** | 0.157 | 0.167 | 0.07 / 0.16 / 0.21 |
| M3 = M2 + future humidity/temperature change | 0.091 | 0.158 | 0.168 | 0.07 / 0.16 / 0.21 |

**Conclusion:** for a single sensor, the 1–3 h change in PM2.5 is close to unpredictable from its own history, the weather, or the time of day. Nothing correlates with the change by more than |r| ≈ 0.28. Persistence of the last 10 minutes is the model to beat. Ridge wins on validation but not on test.

## What the cleaning found (static #3)

| Check | Result |
|---|---|
| Duplicates / NaN | 0 / 0 |
| Gaps > 6 s | 8 (longest 73 s), left unfilled |
| GPS / speed | 1 unique coordinate; speed median 0.16, max 0.88: a genuinely static sensor |
| Physical range | 0 rows outside |
| Flat-lines ≥ 10 min | 0 (longest run of identical readings: 18 samples ≈ 1 min) |
| Hampel spikes (5 min, 6 robust sd) | 2 rows removed |
| 10-min bins below 50% coverage | 1 set to NaN |
| Noise check | training PM sd 22.7, so 1σ noise is about 1.6 per 10-min bin and 0.65 per hour |

## What the correlation found (hourly)

* PM 1 h ago: r = 0.957 (0.85–0.97 every day). PM 24 h ago: r = 0.03. So recent history matters and yesterday doesn't.
* Temperature r = 0.55 and humidity r = −0.24, but the partial correlation of humidity given temperature is −0.05, so humidity's apparent effect is really temperature's. Both flip sign from one day to the next.
* Against the 1–3 h **change**, every feature is weak: hour of day (cos) −0.20 to −0.28, dew-point change −0.16, last-hour trend +0.10 falling to 0.00.

## Next steps

1. **Use the other sensors.** The multi-sensor version in `src/pm2d5_pred_model.m` scores 0.187 against 0.216 for the nearest sensor (leave-one-out). The remaining gain is spatial rather than temporal.
2. Damped trend or exponential smoothing over the last 10–30 min, which may be more noise-robust than one 10-min bin.
3. Rerun with `SENSOR = 1..5` to check whether the ranking holds on every sensor.
