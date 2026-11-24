"""The monolithic MILP, written exactly as in the report, in Pyomo + HiGHS.

This is the Python counterpart of the original Julia/JuMP model, and it is the
version to show when asked "what does the formulation look like in code?". It
builds every variable for every node and hour, so it is much slower than the
decomposed solver in siting.py. Use it to cross-check that solver on a shorter
horizon:

    pip install pyomo highspy
    python -m bess_siting.pyomo_model --days 14 --budget 3e9

NOTE: this file could not be executed in the environment it was written in
(no package index access). bess_siting/tests/test_pyomo_equivalence.py checks
it against the decomposed solver; run that test once the packages are installed.
"""
from __future__ import annotations

import argparse

import pandas as pd
import pyomo.environ as pyo

from .config import ModelConfig
from .data import Inputs, allocate_curtailment, make_synthetic_inputs


def build_model(lmp: pd.DataFrame, curt: pd.DataFrame, cfg: ModelConfig) -> pyo.ConcreteModel:
    m = pyo.ConcreteModel("BESS_siting")

    # ---- Sets ----------------------------------------------------------------
    m.N = pyo.Set(initialize=list(lmp.columns), ordered=True)          # candidate nodes
    m.T = pyo.RangeSet(1, len(lmp))                                     # hours 1..|T|
    m.K = pyo.Set(initialize=[t.name for t in cfg.tiers], ordered=True)  # tiers

    # ---- Parameters ----------------------------------------------------------
    tier = {t.name: t for t in cfg.tiers}
    L, C = lmp.to_numpy(), curt.to_numpy()
    col = {n: j for j, n in enumerate(lmp.columns)}
    m.lmp = pyo.Param(m.N, m.T, initialize=lambda m, i, t: float(L[t - 1, col[i]]))
    m.curt = pyo.Param(m.N, m.T, initialize=lambda m, i, t: float(C[t - 1, col[i]]))
    m.P = pyo.Param(m.K, initialize={k: tier[k].power_mw for k in m.K})
    m.E = pyo.Param(m.K, initialize={k: tier[k].energy_mwh for k in m.K})
    m.Cost = pyo.Param(m.K, initialize={k: cfg.tier_capex(i) for i, k in enumerate(m.K)})
    dt, eta_c, eta_d = cfg.dt_h, cfg.eta_c, cfg.eta_d

    # ---- Decision variables ----------------------------------------------------
    m.x = pyo.Var(m.N, m.K, domain=pyo.Binary)                 # build tier k at node i?
    m.p_ch = pyo.Var(m.N, m.T, domain=pyo.NonNegativeReals)    # charge power [MW]
    m.p_dis = pyo.Var(m.N, m.T, domain=pyo.NonNegativeReals)   # discharge power [MW]
    m.soc = pyo.Var(m.N, m.T, domain=pyo.NonNegativeReals)     # state of charge [MWh]

    # Installed power and energy are LINEAR expressions of x, so the power and
    # SOC limits below need no big-M constants.
    m.cap = pyo.Expression(m.N, rule=lambda m, i: sum(m.P[k] * m.x[i, k] for k in m.K))
    m.ecap = pyo.Expression(m.N, rule=lambda m, i: sum(m.E[k] * m.x[i, k] for k in m.K))

    # ---- Objective: discharge revenue ------------------------------------------
    m.revenue = pyo.Objective(
        expr=sum(m.lmp[i, t] * m.p_dis[i, t] * dt for i in m.N for t in m.T),
        sense=pyo.maximize)

    # ---- Constraints ----------------------------------------------------------
    m.budget = pyo.Constraint(expr=sum(m.Cost[k] * m.x[i, k] for i in m.N for k in m.K) <= cfg.budget)
    m.one_tier = pyo.Constraint(m.N, rule=lambda m, i: sum(m.x[i, k] for k in m.K) <= 1)
    m.ch_limit = pyo.Constraint(m.N, m.T, rule=lambda m, i, t: m.p_ch[i, t] <= m.cap[i])
    m.dis_limit = pyo.Constraint(m.N, m.T, rule=lambda m, i, t: m.p_dis[i, t] <= m.cap[i])
    m.ch_source = pyo.Constraint(m.N, m.T, rule=lambda m, i, t: m.p_ch[i, t] <= m.curt[i, t])

    def balance(m, i, t):
        prev = m.soc[i, t - 1] if t > 1 else 0.0                # start empty: SOC_0 = 0
        return m.soc[i, t] == prev + (eta_c * m.p_ch[i, t] - m.p_dis[i, t] / eta_d) * dt
    m.energy_balance = pyo.Constraint(m.N, m.T, rule=balance)
    m.soc_limit = pyo.Constraint(m.N, m.T, rule=lambda m, i, t: m.soc[i, t] <= m.ecap[i])
    return m


def solve_model(m: pyo.ConcreteModel, mip_gap: float = 1e-6, time_limit: float = 3600, tee: bool = False):
    solver = pyo.SolverFactory("appsi_highs")          # HiGHS through Pyomo's persistent interface
    if not solver.available():
        solver = pyo.SolverFactory("highs")
    solver.options["mip_rel_gap"] = mip_gap            # stop when within this % of the LP bound
    solver.options["time_limit"] = time_limit
    res = solver.solve(m, tee=tee)
    picks = {i: k for i in m.N for k in m.K if pyo.value(m.x[i, k]) > 0.5}
    return res, pyo.value(m.revenue), picks


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--budget", type=float, default=3e9)
    args = ap.parse_args(argv)

    inp: Inputs = make_synthetic_inputs()
    H = 24 * args.days
    lmp = inp.lmp.iloc[:H]
    curt = allocate_curtailment(inp).iloc[:H]
    cfg = ModelConfig(budget=args.budget)

    m = build_model(lmp, curt, cfg)
    res, rev, picks = solve_model(m, tee=True)
    print(res.solver.termination_condition, f"revenue ${rev:,.0f}")
    for i, k in picks.items():
        print(f"  {i:14s} {k}")

    from .siting import revenue_table, optimize
    sol = optimize(revenue_table(lmp, curt, cfg), cfg)
    print(f"decomposed solver revenue ${sol.revenue:,.0f}  (should match)")


if __name__ == "__main__":
    main()
