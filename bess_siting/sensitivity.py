"""Scenario and sensitivity runs around the $6B baseline (report Section 5),
plus extensions that test the model's key assumptions.

The decomposition decides how much work each scenario costs:
  * budget / capex / objective changes  -> only the knapsack re-runs (milliseconds)
  * efficiency / curtailment / price    -> the 123 dispatch LPs re-run (~2 s)
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from .config import ModelConfig
from .data import Inputs, allocate_curtailment
from .siting import optimize, revenue_table, Solution


def compress_spread(lmp: pd.DataFrame, factor: float) -> pd.DataFrame:
    """Price-cannibalization proxy: shrink each day's prices toward the daily mean.
    factor=0.8 means intraday spreads are 20% narrower."""
    daily_mean = lmp.groupby(lmp.index.normalize()).transform("mean")
    return daily_mean + factor * (lmp - daily_mean)


def budget_sweep(R: pd.DataFrame, cfg: ModelConfig, budgets) -> pd.DataFrame:
    rows = [optimize(R, cfg.with_(budget=b)).summary() for b in budgets]
    df = pd.DataFrame(rows)
    # marginal revenue per extra $ of investment between consecutive budgets
    df["marginal_rev_per_$capex_%"] = 100 * df["revenue_$M_per_yr"].diff() / (df["investment_$B"].diff() * 1e3)
    return df


def run_sensitivities(inp: Inputs, base: ModelConfig) -> tuple[pd.DataFrame, dict[str, Solution]]:
    curt0 = allocate_curtailment(inp)
    R0 = revenue_table(inp.lmp, curt0, base)

    def rerun(label, cfg=base, curt=curt0, lmp=inp.lmp, R=None):
        R = revenue_table(lmp, curt, cfg) if R is None else R
        return label, optimize(R, cfg)

    caiso_solar_mw = 24_700.0
    scenarios = [
        # --- report Section 5 ------------------------------------------------
        rerun("Baseline ($6B, eta_c = eta_d = 0.95)", R=R0),
        rerun("Battery capex -15%", cfg=base.with_(capex_multiplier=0.85), R=R0),
        rerun("Charging efficiency 0.85", cfg=base.with_(eta_c=0.85)),
        rerun("Discharging efficiency 0.85", cfg=base.with_(eta_d=0.85)),
        # --- extensions: assumptions the report flags as limitations ---------
        rerun("Curtailment allocated over all CAISO solar (24.7 GW)",
              curt=allocate_curtailment(inp, cap_total_mw=caiso_solar_mw)),
        rerun("Curtailment x0.5", curt=allocate_curtailment(inp, scale=0.5)),
        rerun("Curtailment x2", curt=allocate_curtailment(inp, scale=2.0)),
        rerun("Charge only when nodal LMP <= 0 (no pass-through)",
              curt=curt0.where(inp.lmp <= 0, 0.0)),
        rerun("Intraday LMP spread -20% (cannibalization proxy)", lmp=compress_spread(inp.lmp, 0.8)),
        rerun("Net-value objective, no RA payment",
              cfg=base.with_(objective="net"), R=R0),
        rerun("Net-value objective, RA $10/kW-month",
              cfg=base.with_(objective="net", ra_per_kw_month=10.0), R=R0),
    ]
    sols = dict(scenarios)
    base_rev = sols[scenarios[0][0]].revenue
    rows = []
    for label, s in scenarios:
        d = s.summary()
        d = {"scenario": label, **d, "revenue_vs_base_%": 100 * (s.revenue / base_rev - 1)}
        rows.append(d)
    return pd.DataFrame(rows), sols


def tier_value_table(R: pd.DataFrame, cfg: ModelConfig) -> pd.DataFrame:
    """Revenue per $ of capex by tier. Explains which tier the knapsack prefers."""
    costs = np.array([cfg.tier_capex(k) for k in range(len(cfg.tiers))])
    return (R / costs[None, :] * 100).describe().loc[["mean", "min", "max"]].round(2)
