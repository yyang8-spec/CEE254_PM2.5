# BESS siting & sizing in Python

A Python implementation of *Optimal Siting and Sizing of Utility-Scale Battery Storage
Co-Located with Large-Scale Solar in CAISO* (Wu & Yang, CEE 254 final report). The
original model was Julia/JuMP/HiGHS. For the interview story, read
[TALKING_POINTS.md](TALKING_POINTS.md).

## Layout

| file | what it does |
|---|---|
| `config.py` | every parameter: tiers (100/200/350 MW, 4 h), costs, efficiencies, budget |
| `data.py` | CSV loader for the real data, curtailment allocation, and a **synthetic** CAISO-like year for demos |
| `dispatch.py` | exact solver for one node's hourly dispatch LP (backward dynamic program) |
| `siting.py` | the decomposition: 123 dispatch LPs give a revenue table R[i,k], then an exact multiple-choice knapsack picks sites and sizes |
| `pyomo_model.py` | the full monolithic MILP, written line-for-line like the report, in Pyomo + HiGHS |
| `sensitivity.py` | budget sweep and the report's sensitivities, plus extensions |
| `run.py` | runs everything and writes `results/summary.md` and CSVs |
| `tests/` | independent correctness checks (greedy flow solver, brute force, random policies, Pyomo equivalence) |

## Run

```bash
python -m bess_siting.run                       # synthetic demo year
```

```bash
python -m bess_siting.run --data path/to/csvs   # your real GridStatus / OASIS / EIA data
```

```bash
python -m pytest bess_siting/tests -q
```

The core needs only `numpy` and `pandas`. The Pyomo cross-check also needs
`pip install pyomo highspy`, then `python -m bess_siting.pyomo_model --days 14`.

Real-data CSV layout (see `data.py`): `nodes.csv` (node, solar_mw),
`lmp.csv` (timestamp + one column per node), `curtailment.csv` (timestamp, MW, hourly).
If you start from CAISO's 5-minute curtailment, convert with `data.hourly_from_5min`,
which takes the mean of each hour, not the sum.

> **The numbers in `results/` come from synthetic data.** They show what the method
> does. They are not CAISO findings. Re-run with `--data` before quoting any figure.
