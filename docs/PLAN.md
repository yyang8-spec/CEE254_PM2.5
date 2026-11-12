# Game plan: winning the PM2.5 competition

Written 11/12. The numbers come from a leave-one-static-sensor-out backtest on the Canvas data (see "How we validate" below). Update this file as results change.

## 1. What the data says (and why it drives the design)

| Finding | Foshan | Tianjin | What it means for us |
|---|---|---|---|
| Hourly correlation between static sensors | 0.93–0.98 | 0.95–0.999 (excluding #6) | One city-wide signal explains almost everything |
| Spread across sites in one hour vs. spread of the city mean over time | 5.3 vs 18.9 µg/m³ | 10.6 vs 21.3 | Most of the error comes from **time**; what's left is a per-site **offset** |
| Mean static vs. mobile | 43–55 vs 58–69 | ~equal | Foshan mobile reads high, so calibrate before using it |
| Spikes | mobile up to 1494 | mobile up to 696 | Remove gross spikes only |
| Bad sensor | none | **static #6**: mean 15.7, corr 0.54; mobile within 300 m reads ~36 while #6 reads 7.6 | Drop sites that don't track the others automatically |
| Co-located sensors | – | static 1, 3, 4 sit at the same coordinates | Merge them; don't count them as 3 sites |
| Gaps | static: ≤75 s | mobile: 6–17 h overnight | Static sensors are the backbone; mobile coverage is daytime only |

**Noise robustness costs almost nothing if we aggregate.** The robustness test adds independent Gaussian noise to each 3-s sample. An hourly mean of ~1200 samples cuts the noise standard deviation by about 35×. In the backtest, NRMSE changed by under 0.002 between noise 0 and 1.0σ. The trap to avoid is **clipping negative values or using asymmetric filters**: noisy samples go negative, and clipping them biases every mean upward. The model never clips its inputs.

## 2. The model: `PM(site, t) = L(t) + o(site)`

All of it is in `src/pm2d5_pred_model.m`: one file, plain MATLAB with no toolboxes, and it also runs in Octave.

1. **Parse and clean.** Detect the time format (datenum, POSIX seconds or ms). Detect whether the columns are ordered speed/temperature or temperature/speed (the course PDF and the tables disagree). Drop NaN rows and bad GPS points. Remove gross spikes (> median + 12·MAD).
2. **Find static sites.** The competition matrix has *no device ID*. A coordinate counts as a static site if it has data in ≥50% of hours and its median speed is < 2. Bin each site's data: 10 min for type 1, 60 min for type 2, 5 min for type 3.
3. **Drop bad sites.** Remove any site whose correlation with the median of the others is < 0.7.
4. **Decompose** the binned matrix into a city level `L(t)` and a per-site offset `o_s`, alternating the two estimates for a few iterations so missing data is handled.
5. **Test-site offset** = IDW (power 2, minimum distance 0.2 km) of `o_s`. It can optionally be blended with nearby mobile data, calibrated to static, weighted by precision.
6. **Level by task:**
   * **Type 1, short-term (3 h):** persistence of the last 10 min of `L`, damped by AR(1) toward the last-24 h mean.
   * **Type 2, long-term (24 h):** ridge regression of `L` on humidity, temperature, and 24 h + 12 h harmonics, plus an AR(1) correction on the residual that decays with horizon. It uses the **future humidity and temperature that `test_data` gives us at the test site**, which is free information most teams will ignore.
   * **Type 3, interpolation:** IDW of the static readings in the same 5-min bin. If every sensor is blank in the window, it falls back to linear interpolation of `L` in time.
7. **Uncertainty (second output):** horizon-dependent persistence error, or residual standard deviation with AR decay, combined with the spread of the site offsets. The report needs this.

## 3. Results so far (MATLAB/Octave backtest, pooled NRMSE, lower is better)

From `validation/run_validation.m` on 11/12. Each held-out static sensor is a test site. Short-term uses windows every 3 h over the Foshan week; long-term and interpolation use one window every 2–3 days in Tianjin.

| Task | Train mean | Nearest sensor | Daily profile | **Ours (noise 0)** | **Ours (noise 1.0σ)** |
|---|---|---|---|---|---|
| 1 short-term, Foshan (585 values) | 0.527 | 0.216 | 0.601 | **0.187** | **0.189** |
| 2 long-term, Tianjin (648 values) | 0.543 | 0.599 | 0.552 | **0.371** | **0.370** |
| 3 interpolation, Tianjin (312 values) | 0.459 | 0.283 | 0.533 | **0.172** | **0.169** |

Ablations at noise 0 (report section h):

| Task | Variant | NRMSE | Takeaway |
|---|---|---|---|
| 1 | no site offset | 0.193 | offset helps |
| 1 | + AR damping toward the 24 h mean | 0.191 | damping hurts, so it's off |
| 1 | 60-min persistence instead of 10-min | 0.195 | the most recent level is best |
| 1 | + mobile offset | 0.191 | not yet useful |
| 2 | no humidity/temperature | 0.459 | the weather regression is the biggest single gain |
| 2 | no temperature | 0.388 | temperature adds a little |
| 2 | + 24 h/12 h harmonics | 0.413 | overfits one week, so it's off |
| 2 | no AR(1) residual | 0.450 | the residual correction matters |
| 2 | no site offset | 0.363 | **IDW offset slightly hurts in Tianjin**, so tune the shrinkage |
| 3 | no site offset | 0.165 | same as above |
| 3 | + mobile offset | 0.187 | hurts |

Bugs the backtest caught (report section j, failure conditions):
1. **Parked vehicles detected as static sites.** Foshan mobile #2's GPS jitter at its depot made ~70 fake "sites". Fixed by requiring ≥5% of the busiest coordinate's sample count. Short-term went 0.217 → 0.187, and 0.336 → 0.189 under noise.
2. **Met extrapolation.** Tianjin static #5's temperature is nearly constant (std 0.7 °C), so the coefficient blew up at test sites whose temperature varies, giving predictions of ~370. Fixed by clipping future met features to the training range. Long-term went 1.05 → 0.41.
3. **Sparse last bin under noise.** Fixed with a sample-weighted level over ≥1000 samples.

Interpolation note: `make_task` blanks the window for *all* sensors, so all interpolation modes reduce to temporal interpolation (they're identical above). If the competition only blanks the test site, the `idw_now` mode should do better. Test that case too.

## 4. Where to push to win (ranked by expected gain per hour of work)

1. **Long-term (largest error, so largest margin).**
   * Lagged and differenced humidity features; dew point or absolute humidity from humidity and temperature; humidity × hour interaction.
   * **Fit on more history than the given week.** We're allowed to train offline on all 4 weeks of Tianjin, so regression coefficients learned on 4 weeks are far more stable than ones learned on 1. Fit offline, save them in the function (e.g. a `persistent` variable or constants), and re-fit only the intercept and AR term on the given week. *Check with the TA that this is allowed.*
   * Compare against `fitrensemble` (boosted trees) and `fitrgp` on the same features (Statistics and ML Toolbox; Lectures 6–8). Only switch if the backtest improves.
   * Blend the forecast toward the weekly mean as the horizon grows. The AR(1) term already does this, but tune the decay rate on the backtest.
2. **Site offset (the remaining error in all 3 tasks).**
   * Ordinary kriging / a GP over space for `o_s` instead of IDW (Lecture 9, spatio-temporal).
   * Mobile data near the test location: the `use_mobile_offset` switch is already coded, but it currently *hurts* (see ablations). Fix the calibration or drop it.
   * Tune `offset_shrink` (0 to 1). The full IDW offset helps in Foshan but slightly hurts in Tianjin.
   * Regress offsets on outside data (LandScan population, OSM road density near the site). This is also a strong idea for the "best presentation" award.
3. **Short-term:** add the met regression residual (test_data has humidity and temperature for the next 3 h too) and tune the persistence window and damping on the backtest.
4. **Interpolation:** use the spatial value at the same moment and the temporal neighbors together (a space-time GP or a blend weight learned on the backtest). For the case where all sensors are blank in the window, use cubic or GP interpolation with the diurnal shape.
5. **Ensembling:** average the top 2–3 variants per task, weighted by inverse backtest MSE. This is nearly always a small, safe gain.

Rule: **nothing changes the default options without a better pooled NRMSE in `run_validation`, at both noise 0 and 1.0σ.**

## 5. How we validate

* `data_cleaning/export_device_matrices.m` converts the raw tables into numeric `dev{}` matrices in the competition column order and saves them to `data/processed/`.
* `validation/make_task.m` builds a competition-style `(train_data, test_data, truth)`. It holds out one static sensor as the test site (removed from training entirely, since the real test sites are "different from the sensor locations") and optionally adds noise.
* `validation/run_validation.m` slides windows across the whole dataset, holds out each good static sensor in turn, and prints pooled NRMSE for our model, the ablations and the baselines. The output feeds report sections (g) baselines, (h) ablation and (i) results directly.

## 6. Open questions: check these the moment the data drops on 11/16

* Column order of cols 3/4 and the time format. The code auto-detects both, but print them anyway.
* Is "hourly PM2.5" the mean over the hour or a point value? (`make_task` assumes the hour mean starting at the test timestamp.)
* Interpolation: is the 11:30–12:30 window blanked for *all* sensors or only the test site? The code handles both, but the best method differs. `make_task` currently blanks all sensors, which is the harder case; also test the other.
* How many test locations, and how far are they from our sensors?

## 7. Timeline and split for 4 people

| When | Person A: long-term | Person B: offsets / spatial | Person C: short-term + interp | Person D: validation + report |
|---|---|---|---|---|
| 11/12–11/15 | met features, multi-week coefficients, trees/GP comparison | kriging/GP offsets, mobile offset validation | tune windows/damping, met residual, interp blend | run the full backtest nightly, keep `RESULTS.md`, make figures |
| 11/16 | sanity-check the 9 given sets (plots, column checks) | | | write a `run_competition.m` that produces all 9 outputs |
| 11/17–11/19 | freeze defaults by 11/19 night | | | timing check (all 9 must finish well within limits) |
| 11/20 | **submit 9 predictions + code** | | | |
| 11/21–12/1 | slides (10 min + 3 min Q&A) | | | report draft (ACM template) |
| 12/4 | report + individual role pages + AI use statement | | | |
