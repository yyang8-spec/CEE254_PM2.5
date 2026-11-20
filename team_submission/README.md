# Team submission: one code file for the graders

**The file to hand in is `SUBMIT/pm2d5_pred_model.m`.** It is a single, self-contained file: no data paths, no toolboxes, no other files needed. The TA can run it on their machine with

```matlab
pred_pm2d5 = pm2d5_pred_model(train_data, test_data, problem_type)   % 1, 2 or 3
```

`train_data` / `test_data` can be the MATLAB tables from the 11/16 files or the handout matrices.

Do not edit `SUBMIT/pm2d5_pred_model.m` by hand; it is generated.

## How it is put together

| File | What | Owner |
|---|---|---|
| `pm2d5_pred_model.m` | Dispatcher: calls the task model by problem_type, then a safety net (M × 1 output, NaN replaced, size check) | team |
| `../short_term_pipeline/model/pm_short_term.m` | Short-term model (problem_type 1), final | short-term lead |
| `pm_long_term.m` | Long-term model (problem_type 2). **Placeholder** that calls the draft model | long-term owner |
| `pm_interpolation.m` | Interpolation model (problem_type 3). **Placeholder** that calls the draft model | interpolation owner |
| `pm_draft_level_model.m` | Earlier all-in-one draft used by the two placeholders. Delete it once both are replaced | — |
| `build_submission.m` | Combines all of the above into `SUBMIT/pm2d5_pred_model.m` | — |
| `check_submission.m` | Runs the built file in an empty folder on all 9 competition files and checks every output | — |

## To plug in your model (long-term or interpolation)

1. Replace the body of `pm_long_term.m` (or `pm_interpolation.m`) with your model, keeping the first line:
   ```matlab
   function pred_pm2d5 = pm_long_term(train_data, test_data, opts)
   ```
   * **Inputs:** exactly what the graders pass, as tables with columns `time hmd spd tmp pm2d5 lat lon` (test: no `pm2d5`), or the handout matrices. Short-term and long-term train files come as `separated_*` (static + mobile tables), but the graders pass ONE `train_data`. Don't rely on knowing which rows are static.
   * **Output:** `pred_pm2d5`, M × 1, the same row order as `test_data`.
   * `opts` is optional (tuning only); the graders call with 3 arguments.
2. Helper functions can go at the bottom of the same file, or in extra `.m` function files in this folder. Name clashes with other people's helpers are handled automatically.
3. **Rules,** so the TA can run it:
   * functions only: no `clear`, `close all`, `load(...)` of data files, figures, `fprintf` loops or absolute paths inside the model;
   * every function ends with `end`;
   * base MATLAB only, unless the course allows toolboxes;
   * if your model needs coefficients fitted offline on the Canvas data, paste them in as numbers (and confirm with the TA that offline fitting is allowed);
   * if a Live Script was exported to `.m`, the saved-output appendix (`%[appendix]...`) is dropped automatically.
4. Rebuild and test (from the repo root):
   ```matlab
   run('team_submission/build_submission.m')
   run('team_submission/check_submission.m')
   ```
   It must end with `ALL 9 TESTS OK`.
5. Commit `team_submission/` including `SUBMIT/pm2d5_pred_model.m`.

## Competition-data facts every model should respect

* **Time stamps mark interval ENDS.** A row stamped 07:00 is the mean over [06:00, 07:00). This was checked against the co-located Canvas sensor's humidity.
* **Interpolation test window:** 22:40–23:35 on day 2, not the 11:30–12:25 of the handout.
* **Noise files contain negative PM values** (down to −115 at 1.0σ). Keep them: removing or clipping them biases every mean upward.
* **Test sites are fixed sensors** (speed ≈ 0) with no data in `train_data`.

## Current state (11/20)

`check_submission.m`: all 9 tests run and pass the format checks. Short-term is identical to `short_term_pipeline/submissions` (means 78.93 / 78.82 / 78.54). Long-term and interpolation still use the draft model.
