# Short-term prediction: text for the final report (sections a–m)

All numbers are from the final model (τ = 2 min) and the scripts in `short_term_pipeline/`. Figures are in `short_term_pipeline/figures/`.

## a. Abstract (short-term sentences)

For short-term prediction (the next 3 hours at sites with no sensor), we model PM2.5 as a city-wide level plus a fixed offset for each location. The level is an exponentially weighted average of the most recent static-sensor readings, and the offset at the test site is interpolated by inverse distance weighting. On a held-out test period, holding out each Foshan static sensor in turn, this model reached an NRMSE of 0.204, compared with 0.233 for nearest-sensor persistence. Its error rose only to 0.207 with the strongest added noise.

## b. Introduction (short-term goal and challenges)

**Goal.** Given three days of data from fixed and vehicle-mounted sensors in Foshan, predict the hourly mean PM2.5 for each of the next three hours at fixed locations that have no data in the training set.

**Challenges.**
1. The test sites have no history, so a model cannot learn their own behaviour.
2. The training matrix has no device ID, so fixed and mobile sensors must be told apart from the data itself.
3. The robustness tests add zero-mean Gaussian noise of 0.5σ and 1.0σ to every training reading.
4. Only three days are available to fit any parameters.

## d. Data (Foshan)

The Foshan dataset (8–16 October 2018) contains 2,177,577 readings from 5 fixed (static) and 8 vehicle-mounted (mobile) sensors, sampled about every 3 s. Each reading has time, humidity, temperature, speed, PM2.5, latitude and longitude.

* The static sensors have no gap longer than 75 s.
* The mobile sensors have 188 gaps longer than 1 hour (the longest 16.9 h). Many of them fall overnight; the cause is not recorded.
* Mobile sensors read higher on average than static ones (61.3 vs 48.7 µg/m³) and contain extreme values, up to 1,494 µg/m³.
* The static sensors move together: their hourly series correlate 0.93–0.98. The spread between sites in a given hour is about 5 µg/m³, against about 19 µg/m³ of variation over time.

This last property motivates modelling a shared city-wide level plus a site offset. In the competition data, the three short-term test sites are fixed sensors (speed ≈ 0.2–0.3), 0.80–0.94 km from the nearest training sensor. Their time stamps mark the end of each hour.

*Figure: `step1_preprocessing.png`, raw vs 10-min data for a static sensor, and mobile spikes above the threshold.*

## e. Signal processing

| Step | Rule | Effect (Foshan) |
|---|---|---|
| Missing values / GPS errors | drop rows with missing time, PM2.5 or position; drop (0, 0) or > 0.5° from the median position | 0 rows |
| Spike removal | drop PM2.5 > median + 12 × robust SD (1.4826 × MAD) = 243 µg/m³ | 2,962 rows (0.14%), all mobile |
| Negative values | kept | the noise test makes some readings negative; clipping them would bias every average upward |
| Static/mobile separation | a coordinate is static if it has data in ≥ 50% of hours, median speed < 2 and ≥ 5% of the busiest coordinate's readings | 4 static sites found, as expected; without the last rule, a parked vehicle's GPS jitter produced 72 "sites" |
| Faulty-site check | drop a static site whose correlation with the others is < 0.7 | none dropped in Foshan (min r = 0.93) |
| Aggregation | 10-min mean per static site (~200 readings) | 1.0σ noise falls from 22.7 µg/m³ per reading to about 1.6 per bin |
| Level smoothing | exponentially weighted mean of the raw readings, weight exp(−age/τ) | see h |

**Utility and cost.** Averaging is what makes the model robust to the noise test: 1.0σ noise raises the test NRMSE by only 0.0035. The parked-vehicle rule is the most important step: without it the error more than triples under noise (section h). All steps are linear-time operations, and one forecast takes under 0.5 s in MATLAB.

**Limitations.** The spike threshold is computed from the data, so under 1.0σ noise it rises and removes fewer real spikes. The static-site rule assumes static sensors run around the clock.

## Correlation analysis (feature selection; in d or f)

Correlation of each candidate input with the hourly city-level PM2.5 (Foshan):

| Variable | Pearson r | Note |
|---|---|---|
| PM2.5 1 h earlier | 0.963 | strongest predictor |
| PM2.5 3 h earlier | 0.816 | |
| PM2.5 24 h earlier | 0.029 | no daily repetition |
| Temperature | 0.554 | sign changes between days |
| Humidity | −0.222 | partial r given temperature = 0.011 |
| Hour of day (cos) | −0.215 | explains 6.8% of variance (η²) |
| Vehicle speed (mobile) | — | median PM2.5 is 51–52 µg/m³ in every speed bin |

For forecasting, what matters is the **change** over the next h hours.
* The most recent 1-hour trend is moderately related to it: r = 0.44 / 0.33 / 0.25 for h = 1 / 2 / 3.
* The deviation from the 3-day mean is weakly related (r = −0.04 / −0.13 / −0.19).
* Temperature change and hour of day are not (|r| < 0.07).

A weak linear association does not rule out nonlinear or joint effects. The regressions in section f test whether these features help on new data.

*Figure: `step2_correlation.png`.*

## f. Models and training

**Final model: multi-sensor persistence with exponential smoothing and a spatial offset correction.**

PM(site, t) = L(t) + o(site)

1. **Training.** From the 10-min bins of the static sites S, alternately estimate the city level, L(t) = mean over sites of (S − o), and the site offsets, o = mean over time of (S − L), with the offsets summing to zero. The offsets are the parameters fitted on the three-day window.
2. **Current level.** An exponentially weighted mean of all offset-corrected raw static readings from the last 3 hours, with weight exp(−age/τ) and τ = 2 min. A reading's weight halves every 1.4 min, so in practice the level reflects the last few minutes. It is held constant for the next 3 hours.
3. **Test-site offset.** Inverse distance weighting (power 2, minimum distance 0.2 km) of the site offsets.
4. **Fallback.** If no static reading is younger than 30 min, the level comes from mobile readings, shifted by their median difference from L.
5. **Uncertainty.** SD = sqrt(persistence error² + SD(o)²). The persistence error is the RMS change of L in training over the same horizon, measured to the middle of the target hour.

**Model and parameter selection.** τ was chosen from {2, 5, 10, 20} min on the development half of the backtest, using the mean NRMSE over the three noise levels:

| τ | 2 | 5 | 10 | 20 |
|---|---|---|---|---|
| Development NRMSE | **0.1472** | 0.1479 | 0.1511 | 0.1558 |

**Models tested and not adopted.** First, a single-sensor study: each of the 5 sensors was forecast from its own previous 3 days. The first half of the forecast times was used for validation and the second half for testing. Results pooled over 5 sensors, test NRMSE at noise 0 / 0.5σ / 1.0σ:

| Model | Validation | Test |
|---|---|---|
| Persistence, last 10 min | 0.1159 | 0.1486 / 0.1512 / 0.1551 |
| Exponential smoothing, τ = 10 min | 0.1192 | 0.1513 / 0.1528 / 0.1548 |
| Linear regression on levels | 0.1459 | 0.1620 / 0.1653 / 0.1707 |
| Ridge regression on the change (λ = 1000, chosen on validation) | 0.1125 | 0.1514 / 0.1543 / 0.1601 |
| Ridge + future humidity/temperature change | 0.1123 | 0.1511 / 0.1541 / 0.1580 |

The ridge models used these features:
* the recent trend (last 10 min minus last-hour mean),
* the deviation from the 3-day mean,
* hour of day,
* the change in weather between now and the target hour.

They were fitted on training pairs inside the 3-day window, with standardised features and no intercept, so that a large λ shrinks them to persistence. They beat persistence on validation but not on test, on every sensor, which indicates overfitting.

Two multi-sensor alternatives also did not beat persistence on the test half:
* **Ridge on features from the other four sensors** (trends, spread of their changes, nearest sensor's change): 0.1919 vs 0.1893.
* **Calibrated mobile readings near the test site to estimate its offset:** 0.1917 vs 0.1893.

**Metric.** NRMSE = RMSE / RMS(truth), pooled over all forecasts.

**Validation design.** The test sites have no history, so we validate by leaving one sensor out. Each Foshan static sensor in turn is removed from training and its hourly means are predicted. A forecast is made every 3 hours (39 origins), each using only the previous 3 days. The development half covers 11 Oct 00:00 – 13 Oct 06:00 (19 origins); the test half covers 13 Oct 09:00 – 15 Oct 21:00 (20 origins) and is scored once. Noise is added to the training PM2.5 only.

## g / h / i. Baselines, ablations and results

**Held-out test half (585 forecasts per noise level), NRMSE:**

| Model | Noise 0 | 0.5σ | 1.0σ |
|---|---|---|---|
| **Our model (τ = 2 min)** | **0.2038** | **0.2052** | **0.2073** |
| Baseline: nearest-sensor last-hour mean | 0.2332 | 0.2329 | 0.2327 |
| Baseline: training mean | 0.3627 | 0.3628 | 0.3628 |
| Baseline: daily profile (hour-of-day mean) | 0.4260 | 0.4261 | 0.4261 |
| Ablation: no site offset | 0.2102 | 0.2117 | 0.2137 |
| Ablation: no parked-vehicle rule | 0.2479 | 0.7613 | 0.7698 |
| Ablation: no smoothing (latest reading only) | 0.2028 | 0.2393 | 0.3195 |
| Sensitivity: τ = 5 / 10 / 20 min | 0.2029 / 0.2042 / 0.2070 | 0.2037 / 0.2046 / 0.2072 | 0.2048 / 0.2052 / 0.2075 |

* **Against the baseline:** our model reduced NRMSE by 11–13% relative to nearest-sensor persistence using the last-hour mean (12.6% / 11.9% / 10.9%). The two methods differ in the number of sensors, the smoothing and the offset correction, so the gain is not attributed to one component.
* **Ablations, each removing one component:**
  * **Site offset:** removing it costs 0.006–0.007. Sites have consistent level differences, so this is expected.
  * **Parked-vehicle rule:** removing it is the largest loss (0.25 clean, about 0.76 with noise). The parked vehicle's coordinates are counted as static sites and their noisy readings dominate the level.
  * **Smoothing:** removing it changes nothing on clean data (0.2028) but costs 0.034 at 0.5σ and 0.112 at 1.0σ. The smoothing exists for noise robustness, consistent with averaging N readings reducing noise by √N.
* **τ sensitivity:** on the test half, τ = 5 min would have been slightly better (by ≤ 0.0025). τ was fixed on the development half before the test half was scored. For a single sensor the best τ is about 10 min; pooling four sensors quadruples the readings per minute, so a shorter τ wins.
* **Whole-period scores** (both halves; a development backtest, since τ was tuned on part of it): 0.1857 / 0.1869 / 0.1894, against 0.2159 / 0.2152 / 0.2148.
* **Why the test half is harder:** it scores higher than the development half (0.204 vs 0.147) because it contains the 14 October pollution event.

**Where the error comes from** (oracle analysis, hourly origins: replace one component with the truth):

| | NRMSE |
|---|---|
| Our model | 0.175 |
| with the true site offset | 0.150 |
| with the true future city level | 0.130 |
| with both | 0.094 |

The error grows with the horizon (0.138 / 0.172 / 0.208 for h = 1 / 2 / 3) only because the future level is unknown. With the true level it stays at about 0.13 at every horizon.

**Competition predictions** (three fixed test sites, 14 Oct 07:00–09:00, hour-end stamps), in µg/m³:
* noise 0: 77.66 / 80.08 / 79.04
* 0.5σ: 77.55 / 79.97 / 78.95
* 1.0σ: 77.29 / 79.65 / 78.68

*Figures: `st_validation.png` (test-half NRMSE for all variants), `st_s3_forecasts.png` (1-h forecasts vs truth), `st_smoothing_vs_noise.png` (smoothing vs noise).*

## j. Uncertainty and limitations

**Uncertainty calibration** (585 forecasts):

| Horizon | RMSE | Mean SD | Inside ±1 SD (68%) | Inside ±1.96 SD (95%) |
|---|---|---|---|---|
| 1 h | 6.51 | 4.93 | 62.6% | 87.2% |
| 2 h | 7.73 | 7.45 | 80.5% | 92.8% |
| 3 h | 9.19 | 9.75 | 81.5% | 91.8% |
| All | 7.89 | 7.38 | 74.9% | 90.6% |

The ±1 SD band is close to nominal overall, but the 95% intervals under-cover (90.6%) because the errors are heavy-tailed: pollution events produce a few large misses.

**Failure conditions.**
1. **Sudden pollution events.** Persistence cannot anticipate a rise or fall within the next 3 hours. The recent trend is moderately correlated with the next change, but trend-based regressions did not improve on the test half. The competition window falls during a rise (the static mean went from about 60 µg/m³ at midnight to about 78 µg/m³ just before the forecast), so under-prediction is likely there.
2. **Site-specific offsets.** Static sites differ by up to ±7 µg/m³ (e.g. −6.8 and +7.5), while mobile sensors passing within 200 m read close to the city average. The offsets may therefore partly reflect sensor calibration rather than air quality; device, location and sampling conditions are confounded. A test sensor's own offset cannot be recovered from other sensors: holding out the sensor with offset −6.8 gives NRMSE 0.256, against 0.176 with its true offset.
3. **Missing static data at forecast time.** If no static reading is newer than 30 min, the mobile fallback raises NRMSE from 0.182 to 0.241.
4. **Spatial extrapolation.** IDW cannot extrapolate beyond the static sensors, so a test site at the edge of the network gets an offset weighted toward the interior sensors.
5. **PM2.5 range.** Static readings in the data stay below about 180 µg/m³. The additive offsets were estimated at typical levels and may not hold in extreme events.

## k. Improvements

* **Data collection:**
  * co-locate and calibrate all sensors before deployment, which addresses failure condition 2;
  * record a device ID;
  * keep coverage overnight, or record why mobile data stops.
* **Data analysis:**
  * kriging or Gaussian-process regression for the site offsets, with calibrated uncertainty;
  * a space-time model of the level;
  * fitting the change model on more weeks of data, if allowed.

## l. Conclusion (short-term sentences)

For 1–3 hour forecasts at unmonitored sites, the most recent city-wide level is the strongest information. A smoothed multi-sensor persistence model with a site offset beat nearest-sensor persistence by about 12% on held-out data and was robust to the added noise. More complex regressions did not generalise beyond a three-day window. The main remaining errors are unpredictable short-term changes and sensor-specific offsets.

## m. AI use statement (short-term part; complete with your own prompts and corrections)

* **Tool:** Claude (Anthropic), through Claude Code.
* **Used for:**
  * exploratory analysis of the Canvas data;
  * writing the MATLAB/Octave code for cleaning, the model and the validation;
  * designing the leave-one-sensor-out backtest, the ablations and the oracle analysis;
  * drafting report text.
* **Issues found and corrected during development:**
  * parked-vehicle GPS jitter detected as static sites;
  * sensitivity to sparse time bins under noise;
  * collinear features and intercept drift in the regression;
  * stale static readings used as the current level;
  * an understated 1-hour uncertainty;
  * a one-hour misalignment of the trend feature in the correlation check;
  * τ initially tuned on the same data it was evaluated on, after which the validation was changed to a development/test split.
* **Independent validation:** the team re-ran the validation and the competition pipeline in MATLAB, and the results matched the Octave runs to within floating-point round-off (≤ 5 × 10⁻⁹). A team member reviewed the code and the report claims.
* *Add: the prompts that materially influenced the work, and the corrections you made yourself.*
