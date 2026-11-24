"""Input data: loading the real CSVs, or generating a synthetic stand-in.

Data the model needs (report Section 2):
  * nodes      : one row per candidate pricing node, with its nameplate solar MW
  * lmp        : hourly day-ahead LMP [$/MWh], one column per node   (GridStatus.io)
  * sys_curt   : hourly system-wide solar curtailment [MW]           (CAISO OASIS)

Expected CSV layout for real data (see load_csv_inputs):
  nodes.csv        columns: node, solar_mw  [, region, lat, lon]
  lmp.csv          first column timestamp, then one column per node name
  curtailment.csv  columns: timestamp, curtailment_mw   (hourly MW)
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


@dataclass
class Inputs:
    nodes: pd.DataFrame          # index = node name, column solar_mw (+ optional metadata)
    lmp: pd.DataFrame            # (T x N) $/MWh, columns = nodes
    sys_curt: pd.Series          # (T,) MW
    synthetic: bool = False

    @property
    def node_names(self) -> list[str]:
        return list(self.nodes.index)


# --------------------------------------------------------------------------
# Spatial curtailment allocation (report Section 3.4)
# --------------------------------------------------------------------------
def allocate_curtailment(inp: Inputs, cap_total_mw: float | None = None,
                         scale: float = 1.0) -> pd.DataFrame:
    """Curtailment_{i,t} = SysCurtailment_t * Cap_solar_i / Cap_total.

    cap_total_mw defaults to the sum over the candidate nodes, i.e. *all* system
    curtailment is attributed to the candidate plants. Passing CAISO's total
    utility solar (~24.7 GW) instead attributes only the candidates' share.
    That choice roughly halves the charging energy and is tested in
    sensitivity.py.
    """
    cap = inp.nodes["solar_mw"]
    if cap_total_mw is None:
        cap_total_mw = float(cap.sum())
    share = cap / cap_total_mw
    curt = np.outer(inp.sys_curt.to_numpy() * scale, share.to_numpy())
    return pd.DataFrame(curt, index=inp.lmp.index, columns=inp.node_names)


def hourly_from_5min(series_5min: pd.Series) -> pd.Series:
    """CAISO curtailment reports are 5-minute MW values.

    To get hourly MW (= MWh per hour), take the MEAN of the twelve intervals.
    Summing them overstates energy 12x, a classic unit bug.
    """
    return series_5min.resample("1h").mean()


# --------------------------------------------------------------------------
# Real data loader
# --------------------------------------------------------------------------
def load_csv_inputs(folder: str | Path) -> Inputs:
    folder = Path(folder)
    nodes = pd.read_csv(folder / "nodes.csv").set_index("node")
    lmp = pd.read_csv(folder / "lmp.csv", index_col=0, parse_dates=True)
    curt = pd.read_csv(folder / "curtailment.csv", index_col=0, parse_dates=True).iloc[:, 0]

    lmp = lmp[nodes.index]                                  # same node order everywhere
    idx = lmp.index.intersection(curt.index)
    lmp = lmp.loc[idx].interpolate(limit=3).ffill().bfill()  # small gaps only
    curt = curt.reindex(idx).fillna(0.0).clip(lower=0.0)     # report: missing days -> 0
    return Inputs(nodes=nodes, lmp=lmp, sys_curt=curt, synthetic=False)


# --------------------------------------------------------------------------
# Synthetic stand-in (for development and demos only)
# --------------------------------------------------------------------------
REGIONS = {
    # region: (number of nodes, LMP spread multiplier, evening premium $/MWh)
    "KERN":      (9, 1.00, 0.0),
    "MOJAVE":    (8, 1.05, 3.0),
    "ANTELOPE":  (6, 0.95, 2.0),
    "SJV":       (8, 0.90, -2.0),   # San Joaquin Valley
    "IMPERIAL":  (6, 1.20, 6.0),
    "CARRIZO":   (4, 0.85, -3.0),
}


def make_synthetic_inputs(seed: int = 7, start: str = "2025-05-01",
                          hours: int = 8760, total_solar_gw: float = 12.5,
                          annual_curtail_twh: float = 3.4) -> Inputs:
    """A plausible CAISO-like year: 41 nodes, ~12.5 GW of solar, a duck-curve
    LMP shape, and spring-heavy midday curtailment of ~3.4 TWh/yr.

    The numbers are calibrated to the report's description (41 nodes, the
    largest plant 950 MW, daily LMP spread of roughly $45-80/MWh, 2024 CAISO
    curtailment of about 3.4 TWh). They are NOT real data, so results from
    them demonstrate the method and must not be quoted as findings.
    """
    rng = np.random.default_rng(seed)
    idx = pd.date_range(start, periods=hours, freq="h")
    hod = idx.hour.to_numpy() + 0.5
    doy = idx.dayofyear.to_numpy()
    day = (np.arange(hours) // 24)
    n_days = day.max() + 1

    # ---- nodes -----------------------------------------------------------
    names, region, spread_mult, premium = [], [], [], []
    for reg, (n, m, prem) in REGIONS.items():
        for j in range(n):
            names.append(f"{reg}_{j + 1:02d}")
            region.append(reg)
            spread_mult.append(m * rng.uniform(0.9, 1.1))
            premium.append(prem + rng.normal(0, 2))
    N = len(names)                                          # 41
    cap = rng.lognormal(mean=0.0, sigma=0.55, size=N)
    cap = 100 + cap / cap.sum() * (total_solar_gw * 1000 - 100 * N)   # every plant >= 100 MW
    big = int(np.argmax(cap))
    cap[big] = 950.0                                        # largest plant, as in report
    cap *= total_solar_gw * 1000 / cap.sum()
    cap = np.clip(cap, 100, 950)
    cap[big] = 950.0
    nodes = pd.DataFrame({"solar_mw": cap.round(1), "region": region}, index=pd.Index(names, name="node"))

    # ---- solar shape and system curtailment ------------------------------
    season = np.cos(2 * np.pi * (doy - 172) / 365)          # +1 at summer solstice
    day_len = 12 + 2.3 * season
    sunrise = 12 - day_len / 2
    sun = np.clip(np.sin(np.pi * (hod - sunrise) / day_len), 0, None)

    spring = np.exp(-0.5 * ((doy - 105) / 40.0) ** 2)       # peak mid-April
    day_doy = doy[::24][:n_days]
    p_on = 0.15 + 0.8 * np.exp(-0.5 * ((day_doy - 105) / 55.0) ** 2)
    daily_level = (rng.random(n_days) < p_on) * rng.lognormal(0, 0.35, n_days)
    raw = (0.15 + 0.85 * spring) * daily_level[day] * np.clip(sun - 0.25, 0, None)
    raw = np.minimum(raw / np.quantile(raw[raw > 0], 0.995), 1.0)   # cap the extreme hours
    sys_curt = raw / raw.sum() * annual_curtail_twh * 1e6   # MW each hour, sums to target MWh
    sys_curt = pd.Series(sys_curt, index=idx, name="curtailment_mw")

    # ---- LMP: duck curve + node effects + noise --------------------------
    base = 42 + 10 * np.maximum(season, 0) + 6 * rng.standard_normal(n_days).cumsum()[day] * 0.15
    midday_dip = (18 + 20 * spring) * sun
    curt_dip = 30 * (sys_curt.to_numpy() / sys_curt.max()) ** 0.5
    evening = (24 + 20 * np.maximum(season, 0)) * np.exp(-0.5 * ((hod - 19.5) / 1.6) ** 2)
    morning = 10 * np.exp(-0.5 * ((hod - 7.5) / 1.2) ** 2)
    common = base - midday_dip - curt_dip + evening + morning

    lmp = np.empty((hours, N))
    for i in range(N):
        shape = spread_mult[i] * (common - common.mean()) + common.mean()
        prem = premium[i] * np.exp(-0.5 * ((hod - 19.5) / 2.0) ** 2)
        noise = rng.normal(0, 4.0, hours)
        spikes = (rng.random(hours) < 0.004) * (hod > 17) * (hod < 22) * rng.lognormal(4.3, 0.5, hours)
        lmp[:, i] = shape + prem + noise + spikes
    lmp = pd.DataFrame(lmp.round(2), index=idx, columns=names)

    return Inputs(nodes=nodes, lmp=lmp, sys_curt=sys_curt, synthetic=True)


def describe(inp: Inputs) -> dict:
    """Quick sanity statistics: do the inputs look like CAISO?"""
    daily = inp.lmp.resample("D")
    spread = (daily.max() - daily.min()).mean()
    return {
        "nodes": len(inp.nodes),
        "hours": len(inp.lmp),
        "solar_GW": inp.nodes["solar_mw"].sum() / 1000,
        "largest_plant_MW": inp.nodes["solar_mw"].max(),
        "mean_LMP": float(inp.lmp.to_numpy().mean()),
        "daily_spread_min_node": float(spread.min()),
        "daily_spread_max_node": float(spread.max()),
        "share_negative_LMP_hours": float((inp.lmp < 0).to_numpy().mean()),
        "curtailment_TWh": inp.sys_curt.sum() * 1e-6,
        "curtailment_hours": int((inp.sys_curt > 1).sum()),
        "peak_curtailment_MW": float(inp.sys_curt.max()),
    }
