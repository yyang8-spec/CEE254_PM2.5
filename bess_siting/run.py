"""End-to-end run: budget scenarios, sensitivity analysis, dispatch diagnostics.

    python -m bess_siting.run                      # synthetic demo data
    python -m bess_siting.run --data path/to/csvs  # real data (see data.py for layout)

Writes CSV tables and summary.md to bess_siting/results/ (or --out).
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np
import pandas as pd

from .config import ModelConfig
from .data import allocate_curtailment, describe, load_csv_inputs, make_synthetic_inputs
from .sensitivity import budget_sweep, run_sensitivities, tier_value_table
from .siting import node_dispatch, optimize, revenue_table


def md(df: pd.DataFrame, floatfmt=".2f") -> str:
    """Minimal markdown table (avoids the optional 'tabulate' dependency)."""
    cols = [str(c) for c in df.columns]
    fmt = lambda v: (f"{v:{floatfmt}}" if isinstance(v, (float, np.floating)) else str(v))
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    lines += ["| " + " | ".join(fmt(v) for v in row) + " |" for row in df.itertuples(index=False)]
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", help="folder with nodes.csv, lmp.csv, curtailment.csv")
    ap.add_argument("--out", default=str(Path(__file__).parent / "results"))
    ap.add_argument("--baseline-budget", type=float, default=6e9)
    args = ap.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    inp = load_csv_inputs(args.data) if args.data else make_synthetic_inputs()
    cfg = ModelConfig(budget=args.baseline_budget)
    report = []
    tag = "SYNTHETIC DEMO DATA, not real CAISO results" if inp.synthetic else "real input data"
    report.append(f"# BESS siting results ({tag})\n")
    report.append("## Inputs\n")
    report.append(md(pd.DataFrame([describe(inp)]).T.reset_index().rename(columns={"index": "stat", 0: "value"})))

    # ---- Stage 1: revenue table -------------------------------------------
    t0 = time.time()
    curt = allocate_curtailment(inp)
    R = revenue_table(inp.lmp, curt, cfg)
    t_R = time.time() - t0
    R.to_csv(out / "revenue_table.csv")
    report.append(f"\n## Revenue table R[i,k]\n\n{len(R)} nodes x {len(cfg.tiers)} tiers = "
                  f"{R.size} dispatch LPs ({len(inp.lmp)} h each) solved in {t_R:.1f} s.\n")
    report.append("Annual revenue per $ of capex, % per year (mean / min / max across nodes):\n")
    report.append(md(tier_value_table(R, cfg).reset_index().rename(columns={"index": "stat"})))

    # ---- Budget scenarios (report Section 4) ------------------------------
    scen = budget_sweep(R, cfg, [3e9, 6e9, 9e9])
    scen.to_csv(out / "budget_scenarios.csv", index=False)
    report.append("\n## Budget scenarios ($3B / $6B / $9B)\n")
    report.append(md(scen))

    sweep = budget_sweep(R, cfg, np.arange(0.5e9, 12.01e9, 0.5e9))
    sweep.to_csv(out / "budget_sweep.csv", index=False)
    report.append("\n## Budget sweep (efficient frontier)\n")
    report.append(md(sweep[["budget_$B", "nodes", "MW", "investment_$B", "revenue_$M_per_yr",
                            "revenue/capex_%_per_yr", "marginal_rev_per_$capex_%"]]))

    # ---- Portfolio at the baseline -----------------------------------------
    base = optimize(R, cfg)
    port = base.portfolio.copy()
    port["solar_mw"] = inp.nodes.loc[port.index, "solar_mw"]
    if "region" in inp.nodes:
        port["region"] = inp.nodes.loc[port.index, "region"]
    port = port.sort_values("revenue", ascending=False)
    port.to_csv(out / "portfolio_baseline.csv")
    report.append(f"\n## Baseline portfolio (${cfg.budget / 1e9:.0f}B), top 10 by revenue\n")
    report.append(md(port.head(10).reset_index().assign(capex=lambda d: d.capex / 1e6,
                                                        revenue=lambda d: d.revenue / 1e6)))

    # ---- Dispatch diagnostics for the top node -----------------------------
    top = port.index[0]
    dr = node_dispatch(inp, base, top, curt)
    hourly = pd.DataFrame({"lmp": inp.lmp[top], "curtailment_alloc": curt[top],
                           "p_ch": dr.p_ch, "p_dis": dr.p_dis, "soc": dr.soc,
                           "curt_value": dr.curt_value}, index=inp.lmp.index)
    hourly.to_csv(out / f"dispatch_{top}.csv")
    prof = hourly.groupby(hourly.index.hour)[["lmp", "p_ch", "p_dis"]].mean()
    used = dr.charged_mwh / curt[top].sum()
    same_hour = (dr.p_ch > 1e-6) & (dr.p_dis > 1e-6)
    passthru = np.minimum(dr.p_dis, dr.p_ch * cfg.eta_c * cfg.eta_d)[same_hour].sum() / dr.discharged_mwh
    report.append(f"\n## Dispatch diagnostics: {top}\n")
    report.append(f"- charged {dr.charged_mwh / 1e3:.1f} GWh of {curt[top].sum() / 1e3:.1f} GWh allocated curtailment "
                  f"({100 * used:.0f}% absorbed)\n"
                  f"- discharged {dr.discharged_mwh / 1e3:.1f} GWh, i.e. "
                  f"{dr.discharged_mwh / port.loc[top, 'energy_mwh']:.0f} full-cycle equivalents per year\n"
                  f"- {same_hour.sum()} hours charge and discharge in the same hour; that 'pass-through' "
                  f"of curtailed energy is ~{100 * passthru:.0f}% of discharged MWh\n"
                  f"- average realized price on discharge: ${dr.revenue / dr.discharged_mwh:.1f}/MWh\n"
                  f"- marginal value of +1 MWh curtailment (mean over curtailed hours): "
                  f"${dr.curt_value[curt[top].to_numpy() > 0].mean():.1f}/MWh\n")
    report.append("Average hourly profile (MW):\n")
    report.append(md(prof.reset_index().rename(columns={"index": "hour"})))

    # ---- Sensitivities (report Section 5 + extensions) ---------------------
    sens, _ = run_sensitivities(inp, cfg)
    sens.to_csv(out / "sensitivity.csv", index=False)
    report.append("\n## Sensitivity analysis (baseline $6B)\n")
    report.append(md(sens[["scenario", "nodes", "MW", "investment_$B", "revenue_$M_per_yr",
                           "revenue_vs_base_%", "simple_payback_yr"]]))

    (out / "summary.md").write_text("\n".join(report) + "\n")
    print("\n".join(report))
    print(f"\nWrote results to {out}")


if __name__ == "__main__":
    main()
