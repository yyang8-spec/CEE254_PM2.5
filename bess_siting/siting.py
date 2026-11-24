"""Siting + sizing: the outer MILP, solved via exact decomposition.

Full MILP (report Section 3):
    max  sum_{i,t} LMP_{i,t} Pdis_{i,t} dt
    s.t. sum_{i,k} C_k x_{i,k} <= B                         (budget)
         sum_k x_{i,k} <= 1                       for all i  (one tier per node)
         Cap_i = sum_k P_k x_{i,k}
         dispatch constraints at node i scaled by Cap_i      (see dispatch.py)
         x_{i,k} in {0,1}

Key observation: once x is fixed, the dispatch problem separates by node, and
node i's best revenue with tier k, R_{i,k}, does not depend on what is built
elsewhere (prices are exogenous, curtailment is pre-allocated, no network).
So the MILP is exactly equivalent to

    max  sum_{i,k} R_{i,k} x_{i,k}
    s.t. sum_{i,k} C_k x_{i,k} <= B,   sum_k x_{i,k} <= 1,   x binary

which is a multiple-choice knapsack. 41 nodes x 3 tiers = 123 LPs (each solved
exactly in dispatch.py) plus one knapsack, solved exactly by dynamic
programming over the budget. Capex and budget sensitivities only re-run the
knapsack, which takes milliseconds.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

from .config import ModelConfig
from .data import Inputs, allocate_curtailment
from .dispatch import solve_dispatch, DispatchResult


# --------------------------------------------------------------------------
# Stage 1: revenue table R[i, k]
# --------------------------------------------------------------------------
def revenue_table(lmp: pd.DataFrame, curt: pd.DataFrame, cfg: ModelConfig) -> pd.DataFrame:
    """R[i,k] = optimal annual dispatch revenue of tier k at node i ($)."""
    rows = {}
    for node in lmp.columns:
        p, c = lmp[node].to_numpy(), curt[node].to_numpy()
        rows[node] = [
            solve_dispatch(p, c, tier.power_mw, tier.energy_mwh,
                           cfg.eta_c, cfg.eta_d, cfg.dt_h).revenue
            for tier in cfg.tiers
        ]
    return pd.DataFrame.from_dict(rows, orient="index", columns=[t.name for t in cfg.tiers])


# --------------------------------------------------------------------------
# Stage 2: multiple-choice knapsack, exact DP
# --------------------------------------------------------------------------
def knapsack(values: np.ndarray, costs: np.ndarray, budget: float,
             unit: float = 1e5) -> tuple[np.ndarray, float]:
    """Pick at most one option per row to maximize total value within budget.

    values : (N, K) objective contribution of option k at node i
    costs  : (K,)   capex of option k (same for every node)
    unit   : budget resolution in $ (default $100k). Costs are rounded UP, so
             the returned portfolio is always truly within budget.

    Returns (choice, objective) where choice[i] in {-1 (nothing), 0..K-1}.
    Among all optimal portfolios it returns the cheapest one, so "investment
    consumed" is well defined even when the optimum is not unique.
    """
    N, K = values.shape
    w = np.ceil(np.asarray(costs) / unit - 1e-9).astype(int)
    Bu = int(np.floor(budget / unit + 1e-9))
    NEG = -1e30
    best = np.zeros(Bu + 1)                    # best[b] = max value with spend <= b
    choice = np.full((N, Bu + 1), -1, dtype=np.int8)
    for i in range(N):
        new = best.copy()
        for k in range(K):
            if w[k] > Bu or values[i, k] <= 0:
                continue                       # never worth building a negative-value option
            cand = np.full(Bu + 1, NEG)
            cand[w[k]:] = best[: Bu + 1 - w[k]] + values[i, k]
            better = cand > new + 1e-6
            new = np.where(better, cand, new)
            choice[i] = np.where(better, k, choice[i])
        best = new
    # cheapest budget level that already achieves the optimum
    opt = best[Bu]
    b = int(np.argmax(best >= opt - 1e-6))
    pick = np.full(N, -1, dtype=int)
    for i in range(N - 1, -1, -1):
        k = choice[i, b]
        pick[i] = k
        if k >= 0:
            b -= w[k]
    return pick, float(opt)


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------
@dataclass
class Solution:
    cfg: ModelConfig
    portfolio: pd.DataFrame        # one row per selected node
    revenue: float                 # annual $ (sum of R over selected)
    investment: float              # $
    objective: float               # what was maximized (revenue or net value)
    R: pd.DataFrame                # full revenue table, for inspection

    @property
    def n_nodes(self) -> int:
        return len(self.portfolio)

    @property
    def total_mw(self) -> float:
        return float(self.portfolio["power_mw"].sum())

    def summary(self) -> dict:
        tiers = self.portfolio["tier"].value_counts().to_dict()
        return {
            "budget_$B": self.cfg.budget / 1e9,
            "nodes": self.n_nodes,
            "MW": self.total_mw,
            "MWh": float(self.portfolio["energy_mwh"].sum()),
            "investment_$B": self.investment / 1e9,
            "revenue_$M_per_yr": self.revenue / 1e6,
            "revenue/capex_%_per_yr": 100 * self.revenue / self.investment if self.investment else 0.0,
            "simple_payback_yr": self.investment / self.revenue if self.revenue else np.inf,
            **{f"n_{t.name}": tiers.get(t.name, 0) for t in self.cfg.tiers},
        }


def optimize(R: pd.DataFrame, cfg: ModelConfig) -> Solution:
    """Stage 2 only: reuse a revenue table and re-solve the siting knapsack."""
    costs = np.array([cfg.tier_capex(k) for k in range(len(cfg.tiers))])
    vals = R.to_numpy().copy()
    if cfg.objective == "net":
        annual_cost = costs * (cfg.crf + cfg.fixed_om_frac)
        ra = np.array([t.power_mw * 1000 * cfg.ra_per_kw_month * 12 for t in cfg.tiers])
        vals = vals + ra[None, :] - annual_cost[None, :]
    elif cfg.objective != "revenue":
        raise ValueError(cfg.objective)
    unit = 1e4 if cfg.capex_multiplier != 1.0 else 1e5
    pick, obj = knapsack(vals, costs, cfg.budget, unit=unit)

    rows = []
    for i, node in enumerate(R.index):
        k = pick[i]
        if k < 0:
            continue
        t = cfg.tiers[k]
        rows.append({"node": node, "tier": t.name, "power_mw": t.power_mw,
                     "energy_mwh": t.energy_mwh, "capex": costs[k],
                     "revenue": R.iloc[i, k]})
    port = pd.DataFrame(rows).set_index("node") if rows else \
        pd.DataFrame(columns=["tier", "power_mw", "energy_mwh", "capex", "revenue"])
    return Solution(cfg=cfg, portfolio=port, revenue=float(port["revenue"].sum()),
                    investment=float(port["capex"].sum()), objective=obj, R=R)


def solve(inp: Inputs, cfg: ModelConfig, curt: pd.DataFrame | None = None,
          lmp: pd.DataFrame | None = None) -> Solution:
    """Full pipeline: allocate curtailment -> revenue table -> knapsack."""
    curt = allocate_curtailment(inp) if curt is None else curt
    lmp = inp.lmp if lmp is None else lmp
    return optimize(revenue_table(lmp, curt, cfg), cfg)


def node_dispatch(inp: Inputs, sol: Solution, node: str,
                  curt: pd.DataFrame | None = None) -> DispatchResult:
    """Re-run the hourly dispatch for one selected node (for plots and inspection)."""
    curt = allocate_curtailment(inp) if curt is None else curt
    row = sol.portfolio.loc[node]
    return solve_dispatch(inp.lmp[node].to_numpy(), curt[node].to_numpy(),
                          row["power_mw"], row["energy_mwh"], sol.cfg.eta_c, sol.cfg.eta_d, sol.cfg.dt_h)
