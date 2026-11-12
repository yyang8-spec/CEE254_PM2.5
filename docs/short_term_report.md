# Short-term prediction: report material

Draft text and tables for the short-term part of the final report and slides. Every number comes from a script in this repo, named next to it. All of them were run on 11/12 in GNU Octave 8.4. The same code gives identical numbers in MATLAB: the quick `st_validate` run matched to 4 decimals.

**Task.** From 3 days of `train_data` (all static and mobile devices in Foshan, no device ID), predict the hourly mean PM2.5 for each of the next 3 hours at fixed test sites that have no data in `train_data`. The metric is NRMSE = RMSE / RMS(truth). The robustness tests add N(0, (0.5σ)²) and N(0, (1.0σ)²) noise to the training PM2.5.

**Code.**

| What | File |
|---|---|
| The function | `src/pm2d5_pred_model.m` → `src/pm_short_term.m` |
| Validation | `short_term/st_validate.m` |
| Single-sensor study | `short_term/st_single_sensor.m`, `short_term/st_compare_sensors.m` |
| Correlations | `analysis/variable_correlation.m` |
| Uncertainty check | `short_term/st_uncertainty.m` |

---

## d. Data (Foshan, 8–16 Oct 2018)

* 5 static and 8 mobile devices, 3-s sampling, 2,177,577 rows.
* No NaN values and no duplicate timestamps.
* Static sensors have no gaps longer than 75 s.
* Mobile sensors are off at night: 188 gaps longer than 1 h, the longest 16.9 h.
* Static sensors track each other closely: hourly correlation 0.93–0.98. The spread between sites in a given hour is about 5 µg/m³, against about 19 µg/m³ variation over time.
* The mobile sensors read about 10 µg/m³ above the static ones (means 58–69 vs 43–55).
* Figure: `figures/st_s3_cleaning.png` (raw 3-s data, the cleaned 10-min series, humidity and temperature for static #3).

## e. Signal processing (quantitative)

| Step | Rule | Effect | Why |
|---|---|---|---|
| Missing values | Drop rows with NaN time/PM/lat/lon | 0 rows in the Canvas data | The competition data "may contain missing values" |
| GPS errors | Drop (0,0) and points > 0.5° from the median | 0 rows | Same reason |
| Spikes | Drop PM > median + 12 × 1.4826 × MAD (threshold 243 µg/m³) | 2,962 rows (0.14%), all mobile; max raw value 1494 | MAD keeps the threshold robust to the spikes themselves |
| **No clipping** | Negative values are kept | — | The noise test creates negative samples, and clipping them would bias every mean upward |
| Static vs mobile | A coordinate is static if it has data in ≥ 50% of hours, median speed < 2, and ≥ 5% of the busiest coordinate's samples | 4–5 sites found per window | There is no device ID in the matrix |
| Parked-vehicle rule | (the 5% rule above) | Without it, a parked vehicle's GPS jitter creates ~70 fake "sites": NRMSE 0.2165 / 0.6052 / 0.6098 instead of 0.1856 / 0.1862 / 0.1873 (noise 0 / 0.5 / 1.0σ) | The most important cleaning step under noise |
| Faulty sites | Drop a site whose correlation with the others' median is < 0.7 | 0 in Foshan (sites are 0.93–0.98); catches Tianjin static #6 (0.54) | Robustness to a broken sensor |
| Binning | 10-min means per static site (~200 samples each) | Noise reduced about 14×: about 1.8 µg/m³ per site-bin at 1.0σ | This is why the noise tests barely change the score |
| Level smoothing | EWMA of the raw static samples, τ = 5 min | see section h | Trades noise against lag |

Single-sensor cleaning of static #3 (`st_single_sensor.m`): 2 Hampel spikes, 0 flat-lines of 10 min or more, 8 gaps longer than 6 s (longest 73 s), and 1 sparse 10-min bin. 99.999% of samples kept.

## Correlation and feature selection

Hourly city level, Foshan (`analysis/variable_correlation.m`; figure `figures/correlation_foshan.png`):

| Feature | Pearson r with PM2.5 | Per-window stability | Decision |
|---|---|---|---|
| PM 1 h ago | **0.963** | 0.92–0.97 | Keep (persistence) |
| PM 3 h ago | 0.816 | 0.59–0.82 | Captured by persistence |
| PM 24 h ago | 0.029 | −0.04 / −0.68 | Drop |
| Temperature | 0.554 | flips sign day to day (static #3: −0.89 to +0.88) | Drop |
| Humidity | −0.222 | partial correlation given temperature = **0.011** | Drop: its correlation only reflects temperature |
| Dew point | 0.348 | unstable | Drop |
| Hour of day | η² = 0.068 | — | Drop |
| Vehicle speed (mobile) | median PM 51.0–52.0 in every speed bin | — | Drop; test sites are fixed |

**The forecasting question** is whether anything predicts the 1–3 h change. Correlation with y(t+h) − y(t) for static #3 (`st_single_sensor.m`; figure `figures/st_s3_correlation.png`):

| Feature | Correlation with the change |
|---|---|
| Hour of day (cos) | −0.20 to −0.28 (strongest) |
| Dew-point change | −0.16 to −0.17 |
| Last-hour trend | +0.10 at h = 1, 0.00 at h = 3 |

Nothing exceeds |r| ≈ 0.28. This predicts that regression on the change will add little, and section f confirms it.

## f. Models and training

**Final model:** PM(site, t) = L(t) + o(site), forecast held flat over h = 1..3.

1. **Train** on the 3-day window. Alternate L(t) = mean over sites of (S − o_s) and o_s = mean over time of (S − L), centred to sum to 0. The site offsets o_s are the learned parameters.
2. **Level at the origin:** an exponentially weighted mean of every offset-corrected static sample in the last 3 h, w = exp(−age/τ) with τ = 5 min. τ was selected on the backtest from {5, 10, 20 min, last 10-min bin}.
3. **Offset at the test site:** inverse-distance weighting (power 2, minimum distance 0.2 km) of the o_s.
4. **Fallbacks:**
   * If the newest static sample is more than 30 min old, use calibrated mobile data. The readings are shifted by the median mobile-minus-level bias of the window, and smoothed with τ = 15 min.
   * Otherwise use the stale static level, then the last known level.
5. **Uncertainty:** sd = sqrt(persistence error at mid-target-hour² + std(o)²).

**Models tested and rejected**

1. **Single sensor, 5 sensors pooled.** Rolling origin with 118 hourly origins per sensor, split in time: validation is the first 59, test the last 59.

   | Model | Val | Test | Test at 1.0σ |
   |---|---|---|---|
   | Persistence, last 10 min | 0.1159 | **0.1486** | 0.1551 |
   | EWMA τ = 10 min | 0.1192 | 0.1513 | **0.1548** |
   | Linear regression on levels | 0.1459 | 0.1620 | 0.1707 |
   | Ridge on the change (no intercept, λ chosen on val = 1000) | **0.1125** | 0.1514 | 0.1601 |
   | Ridge on the change + future humidity/temperature | 0.1123 | 0.1511 | 0.1580 |
   | Training mean | 0.5750 | 0.3624 | 0.3618 |

   Ridge was set up as follows:
   * Features are standardized and the target is the change Δ = y(t+h) − y_last, so λ → ∞ gives persistence exactly.
   * There is no intercept, because it would learn the window's average drift and carry it forward as a bias.
   * λ ∈ {0, 1, 10, 100, 10³, 10⁴} was chosen on validation only.

   Ridge wins on validation but loses on test, on every sensor. The cause is overfitting: about 400 training pairs per window, but they overlap heavily (lag-1 autocorrelation 0.96), so the effective sample size is much smaller.

2. **Multi-sensor ridge** (leave-one-sensor-out). Features from the other 4 static sensors:
   * EWMA trends (5 vs 30 min and 5 vs 120 min), reversion to the 3-day mean;
   * spread, max and min of their 30-min changes, the nearest sensor's change;
   * hour of day and the future dew-point change.

   Validation 0.1424 vs 0.1467 for persistence; **test 0.1919 vs 0.1893**. Rejected.

3. **Calibrated mobile data for the offset.** Per-vehicle bias is estimated near the training static sites; passes within R of the test site are blended with IDW by number of passes. Chosen on validation (R = 1 km, n0 = 200): **test 0.1917 vs 0.1893**. Rejected (explanation in section j).

## g/h/i. Results: baselines and ablations

Leave-one-sensor-out over all 5 Foshan static sensors, forecasts every 3 h, 585 test values per noise level (`short_term/st_validate.m`; figure `figures/st_validation.png`):

| Model | Noise 0 | 0.5σ | 1.0σ |
|---|---|---|---|
| **Ours: EWMA τ = 5 + IDW offset** | **0.1856** | **0.1862** | **0.1873** |
| Ablation: τ = 10 min | 0.1874 | 0.1877 | 0.1884 |
| Ablation: τ = 20 min | 0.1908 | 0.1910 | 0.1913 |
| Ablation: no site offset | 0.1918 | 0.1924 | 0.1935 |
| Ablation: no parked-vehicle rule | 0.2165 | 0.6052 | 0.6098 |
| Ablation: keep faulty sites | 0.1856 | 0.1862 | 0.1873 (none in Foshan) |
| Baseline: nearest-sensor persistence | 0.2159 | 0.2152 | 0.2148 |
| Baseline: training mean | 0.5266 | 0.5266 | 0.5266 |
| Baseline: daily profile | 0.6006 | 0.6006 | 0.6005 |

* **14% better than the best baseline** (0.186 vs 0.216).
* Going from no noise to 1.0σ costs only 0.0017.
* The single-sensor optimum is τ = 10 min (`figures/st_smoothing_vs_noise.png`). Pooling 4 sites quadruples the samples per minute, so the noise is already averaged down and a shorter τ wins.

**Where the remaining error is** (oracle analysis; Python prototype with hourly origins, where ours = 0.175):

| | NRMSE |
|---|---|
| Ours | 0.175 |
| With the true site offset | 0.150 |
| With the true future city level | 0.130 |
| Both | 0.094 |

Error grows with horizon (0.138 / 0.172 / 0.208 for h = 1/2/3) only because the future level is unknown; with the true level it is flat at about 0.13.

## j. Uncertainty and limitations

**Uncertainty** (`short_term/st_uncertainty.m`, 585 values):

| Horizon | RMSE | Mean sd | Inside ±1 sd (68%) | Inside ±1.96 sd (95%) |
|---|---|---|---|---|
| h = 1 | 6.49 | 4.93 | 62.6% | 88.2% |
| h = 2 | 7.73 | 7.45 | 79.5% | 92.3% |
| h = 3 | 9.20 | 9.75 | 81.5% | 91.8% |
| All | 7.88 | 7.38 | 74.5% | 90.8% |

The ±1 sd band is about right. The 95% band under-covers (91%) because errors are heavy-tailed: pollution events produce a few large misses.

**Failure conditions**

1. **Sensor calibration offsets.** The static sites differ by up to ±7 µg/m³ (s2 −6.8, s3 +7.5), but mobile sensors passing within 200 m read close to the city average there. The mobile-minus-static difference at the same minute is +13.9 at s2 and +3.5 at s3. So the offsets are mostly sensor calibration, not real spatial differences in air quality. No method based on other sensors can predict a test sensor's own calibration: holding out s2 gives NRMSE 0.256, against 0.176 with its true offset.
2. **Sudden pollution events.** Persistence cannot anticipate a rise or fall within the next 3 h, and no available feature predicts it (|r| < 0.3). Errors peak at h = 3 and in events such as 14 Oct 06:00–12:00.
3. **Missing static data at the forecast time.** The mobile fallback raises NRMSE from 0.181 to 0.238 (missing-data check in `st_validate.m`). Before the stale-sample fix, this case gave 0.485.
4. **Extrapolation in space.** IDW cannot extrapolate beyond the sensors. A test site at the edge of the area, like s2, inherits a level that is too high.
5. **Extrapolation in PM range.** The static sensors in this week stay below 180 µg/m³ (static maxima 130–177 µg/m³). Persistence itself has no range limit, but the site offsets are additive and estimated at typical levels. If a sensor's error scales with concentration, the offset will be wrong during an extreme event outside the training range.

## k. Improvements

* **Data collection:**
  * Co-calibrate all sensors side by side before deployment, which removes failure condition 1.
  * Log a device ID in the data stream.
  * Keep mobile sensors running at night.
* **Analysis:**
  * Kriging or a GP for the offsets, with calibrated uncertainty.
  * A space-time model (Lecture 9).
  * Pre-training the change model on more weeks, if the course allows it.

## m. AI use (short-term part)

* **Tool:** Claude (Anthropic), used through Claude Code.
* **What it was used for:** EDA, writing the MATLAB/Octave code, setting up the leave-one-sensor-out backtest, and the ablation and oracle analyses.
* **Bugs it found during validation** (each one fixed and re-validated):
  * parked-vehicle GPS jitter detected as static sites;
  * sparse-last-bin noise sensitivity;
  * collinear features and intercept drift in the regression;
  * stale static samples used as the current level;
  * an understated h = 1 uncertainty.
* **Validation:** the team re-ran `st_validate.m` in MATLAB and the quick-mode results matched Octave to 4 decimals.

*(Edit this section to name the prompts and corrections that mattered to you.)*
