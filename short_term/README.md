# Short-term prediction: single-sensor study

`st_single_sensor.m` runs three stages on **Foshan static #3**: cleaning, correlation, models. Set `SENSOR` to use another one. Run from the repo root:

```matlab
run('short_term/st_single_sensor.m')     % needs data/processed/devices_foshan.mat
```

The script saves `figures/st_s3_cleaning.png`, `st_s3_correlation.png` and `st_s3_forecasts.png`.

**Why #3:** all five Foshan static sensors are equally clean (6–9 gaps > 6 s, longest 72–75 s). #3 has the highest mean hourly correlation with the other four (0.969), so it is the most representative of the city-wide signal.

**Task:** from each hourly origin (11-Oct 00:00 to 15-Oct 21:00, 118 origins), use only the previous 3 days to predict the mean PM2.5 of each of the next 3 hours. Origins are split by time: the first 59 are validation (model and λ selection), the last 59 are test (reported once). The truth is always the clean signal; noise is added only to the training input, as in the competition.

## Results (11/12, Octave)

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

## All 5 sensors + exponential smoothing (`st_compare_sensors.m`)

Test NRMSE pooled over the 5 Foshan static sensors (59 test origins each):

| Model | s1 | s2 | s3 | s4 | s5 | **Pooled, noise 0** | **0.5σ** | **1.0σ** | Δ from noise 0 to 1.0σ |
|---|---|---|---|---|---|---|---|---|---|
| B2 persistence, last 10 min | 0.161 | 0.144 | 0.152 | 0.135 | 0.145 | **0.1486** | 0.1512 | 0.1551 | +0.0065 |
| S1 EWMA τ = 5 min | 0.163 | 0.143 | 0.154 | 0.136 | 0.145 | 0.1495 | 0.1520 | 0.1557 | +0.0062 |
| S2 EWMA τ = 10 min | 0.162 | 0.148 | 0.152 | 0.140 | 0.152 | 0.1513 | 0.1528 | **0.1548** | +0.0035 |
| S3 EWMA τ = 20 min | 0.163 | 0.156 | 0.156 | 0.146 | 0.161 | 0.1567 | 0.1574 | 0.1585 | +0.0018 |
| S4 EWMA τ = 30 min | 0.166 | 0.162 | 0.162 | 0.151 | 0.168 | 0.1619 | 0.1625 | 0.1633 | +0.0014 |
| W1 mean of last 20 min | 0.161 | 0.149 | 0.149 | 0.142 | 0.156 | 0.1517 | 0.1529 | 0.1549 | +0.0032 |
| W2 mean of last 30 min | 0.163 | 0.155 | 0.154 | 0.145 | 0.161 | 0.1556 | 0.1561 | 0.1571 | +0.0015 |
| S* EWMA, τ chosen on val | 0.171 | 0.140 | 0.160 | 0.132 | 0.168 | 0.1560 | 0.1537 | 0.1559 | – |
| M2 ridge on change | 0.166 | 0.145 | 0.157 | 0.136 | 0.146 | 0.1514 | 0.1543 | 0.1601 | +0.0087 |
| M3 ridge + met | 0.164 | 0.145 | 0.158 | 0.136 | 0.145 | 0.1511 | 0.1541 | 0.1580 | +0.0069 |
| B1 persistence, last 1 h | 0.167 | 0.167 | 0.165 | 0.153 | 0.171 | 0.1648 | 0.1651 | 0.1657 | +0.0009 |
| M1 linear on levels | 0.159 | 0.160 | 0.161 | 0.164 | 0.165 | 0.1620 | 0.1653 | 0.1707 | +0.0087 |
| B0 training mean | 0.351 | 0.364 | 0.383 | 0.325 | 0.377 | 0.3624 | 0.3621 | 0.3618 | – |

τ chosen on validation (minutes):

| Sensor | Noise 0 | 0.5σ | 1.0σ |
|---|---|---|---|
| s1–s3 | 2 | 5 / 5 / 10 | 10 |
| s4 | 2 | 5 | 5 |
| s5 | 30 | 20 | 20 |

**Findings**
1. **The trade-off is real but small.** A longer τ averages more samples and so loses less accuracy to noise (+0.0014 at τ = 30 vs +0.0065 for the single 10-min bin). It also reacts more slowly, and that lag costs more than the noise it removes: τ = 30 is the worst smoother even at 1.0σ.
2. **The optimal τ grows with the noise.** Validation picks 2 min clean, 5 min at 0.5σ and 10 min at 1.0σ, which is the textbook bias–variance behaviour.
3. **At the competition's noise levels the gain is negligible.** At 1.0σ the best smoother (τ = 10 min, 0.1548) beats the 10-min bin (0.1551) by 0.0003. On clean data it loses by 0.0027.
4. **The ranking holds on all 5 sensors.** Recent-level persistence (B2/S1) is in the top group everywhere. Ridge wins on validation but not on test, on every sensor (it overfits), and it degrades fastest with noise.
5. **Sensors differ more than methods do.** Sensor-to-sensor spread (0.135–0.161) is about 5× the spread among the top methods. To win, look at spatial information, not at smoothing.

**Decision:** use EWMA with τ = 10 min. It costs 0.003 on clean data, gains a little at 1.0σ, and loses half as much to noise. A noise-adaptive τ (estimate the noise from the short-scale variance of the 3-s data, then pick 2–10 min) would capture both ends, but the possible gain is under 0.002.

## Next steps

1. **Use the other sensors.** The multi-sensor version in `src/pm2d5_pred_model.m` scores 0.187 against 0.216 for the nearest sensor (leave-one-out). The remaining gain is spatial rather than temporal.
2. ~~Exponential smoothing~~ and ~~all 5 sensors~~: done (above).
3. Put EWMA τ = 10 min into `src/pm2d5_pred_model.m` for problem type 1 and confirm it in `run_validation`.
