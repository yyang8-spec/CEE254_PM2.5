# CEE254_PM2.5

CEE 154/254 Data Analytics for Physical Systems (Fall 2026) final project/competition: predicting and interpolating PM2.5 from mobile crowdsensing and static sensors in Foshan and Tianjin, China.

**Team:** [Name 1], [Name 2], [Name 3], [Name 4]

## Key dates
| Date | What |
|------|------|
| Mon 11/16 | Course releases the 9 competition `train_data` / `test_data` sets |
| Fri 11/20, midnight | Submit the 9 predictions + code to Canvas |
| Tue 12/1 & Thu 12/3 | Final presentations (10 min + 3 min Q&A) |
| Fri 12/4, midnight | Final group report (4–5 pages, ACM format) + individual 1-page role description |

## Tasks
Our method has to handle all three problem types through one function:

```matlab
function pred_pm2d5 = pm2d5_pred_model(train_data, test_data, problem_type)
```

| `problem_type` | Task | Input (`train_data`) | Output (`pred_pm2d5`) |
|---|---|---|---|
| 1 | Short-term prediction (Foshan) | 3 days of data | Hourly PM2.5 for the next 3 hours at each test location |
| 2 | Long-term prediction (Tianjin) | 1 week of data | Hourly PM2.5 for the next 24 hours at each test location |
| 3 | Interpolation | 3 days, with the test window removed | PM2.5 every 5 min, 11:30–12:25 on day 2 (12 values per location) |

- `train_data`: P×7 matrix with columns `[time, humidity, temperature, speed, pm2d5, lat, lon]`
- `test_data`: M×6 matrix (same columns, but no PM2.5). Test locations are fixed sites, different from the sensor locations, that fall inside the area the sensors cover.
- `pred_pm2d5`: M×1 vector

**Robustness test:** all three tasks are rerun with zero-mean Gaussian noise added to the training PM2.5 (σ_noise = 0.5σ and 1.0σ, where σ is the std. dev. of the training PM2.5). That makes 9 tests in total.

**Metric:** NRMSE = RMSE(prediction, truth) / RMS(truth). Lower is better.

## Data
Downloaded from Canvas. See [`data/raw/README.md`](data/raw/README.md) for what's in each file.

| File | City | Static devices | Mobile devices | Used for |
|------|------|---|---|---|
| `short_term_foshan_train_val.mat` | Foshan | 5 | 8 | Short-term prediction |
| `long_term_tianjin_train_val.mat` | Tianjin | 6 | 7 | Long-term prediction, interpolation |

Sampling is every ~3 s. The competition draws from these cities, but we're free to train and test on either file during development.

Optional outside data suggested by the course:
- Population: https://landscan.ornl.gov/
- Building footprints/zoning: https://download.geofabrik.de/index.html

## Repo layout
```
data/raw/          original .mat files from Canvas; never edit these
data/processed/    cleaned outputs from data_cleaning/
data_cleaning/     cleaning scripts (in progress)
figures/           exported plots for the report/presentation
```

## Report checklist
Beyond the usual sections, the final report specifically needs:
- [ ] A simple **baseline** for each task (e.g. training mean, persistence, daily average, nearest sensor), compared on the same validation split
- [ ] An **ablation study**: drop ≥3 features, preprocessing steps or model components one at a time, and report the NRMSE for each
- [ ] ≥3 **failure conditions / limitations**, plus prediction uncertainty and how we estimated it
- [ ] A quantitative description of the **signal processing** (cleaning, normalizing, aggregating)
- [ ] An **AI Use Statement**: tool, how it was used, the prompts that mattered, the corrections we made, and how we validated the results

## Who owns what
| Person | Tasks / files |
|--------|---------------|
| | |

## Git workflow
- `git pull` before you start, then commit + `git push` when you stop.
- Stick to your own files where you can, and check in the group chat before editing someone else's.
- Write commit messages that say what changed (e.g. "remove PM2.5 spikes > 1000").
