"""Exact single-node dispatch: the inner LP of the siting MILP.

For a fixed battery (power P, energy E) at one node, the report's model is the LP

    max   sum_t LMP_t * Pdis_t * dt
    s.t.  SOC_t = SOC_{t-1} + (eta_c * Pch_t - Pdis_t / eta_d) * dt,   SOC_0 = 0
          0 <= Pch_t  <= min(P, Curtailment_t)        (power limit + charging source)
          0 <= Pdis_t <= P                             (power limit)
          0 <= SOC_t  <= E                             (energy limit)

Why a custom solver instead of handing this to HiGHS? Two reasons:
  1. With prices fixed (price-taker) and curtailment pre-allocated, nodes do not
     interact except through the budget. So the full MILP splits exactly into
     (#nodes x #tiers) independent LPs plus a small knapsack (see siting.py).
  2. This LP has a closed-form dynamic program: the value of stored energy is a
     concave piecewise-linear function of SOC. Each hour inserts one segment
     (slope = LMP, length = P) and removes the energy that free curtailment
     fills. It solves 8,760 hours exactly in tens of milliseconds, with no
     solver dependency. The Pyomo/HiGHS version in pyomo_model.py solves the
     same formulation and is the cross-check.

Change of units used internally (removes the efficiencies from the dynamics):
    s_t   = eta_d * SOC_t                    "deliverable" energy, MWh at the grid
    a_t   = eta_c * eta_d * Pch_t * dt       deliverable energy added by charging
    d_t   = Pdis_t * dt                      energy sold
    s_t   = s_{t-1} + a_t - d_t,   0 <= s_t <= eta_d * E
"""
from __future__ import annotations

from bisect import bisect_left
from dataclasses import dataclass

import numpy as np


@dataclass
class DispatchResult:
    revenue: float              # $ over the horizon (objective value)
    p_dis: np.ndarray           # MW
    p_ch: np.ndarray            # MW
    soc: np.ndarray             # MWh, end of hour
    curt_value: np.ndarray      # $/MWh: marginal value of one more MWh of curtailment at hour t

    @property
    def discharged_mwh(self) -> float:
        return float(self.p_dis.sum())

    @property
    def charged_mwh(self) -> float:
        return float(self.p_ch.sum())


def solve_dispatch(lmp, curt_mw, power_mw: float, energy_mwh: float,
                   eta_c: float = 0.95, eta_d: float = 0.95, dt: float = 1.0) -> DispatchResult:
    lmp = np.asarray(lmp, dtype=float)
    curt_mw = np.asarray(curt_mw, dtype=float)
    T = len(lmp)
    rt = eta_c * eta_d
    s_max = eta_d * energy_mwh
    d_max = power_mw * dt
    a_max = rt * np.minimum(power_mw, np.maximum(curt_mw, 0.0)) * dt

    # ---- backward pass ----------------------------------------------------
    # V_t(s) = best revenue from hour t onward given deliverable energy s.
    # It is concave and nondecreasing on [0, s_max]. Store it as a list of
    # segments sorted by DECREASING slope: (-slope, length). Negative keys keep
    # bisect working on ascending order. Beyond the listed length, slope is 0.
    neg_slopes: list[float] = []
    lengths: list[float] = []
    z_star = np.empty(T)          # discharge threshold: discharge everything above z*
    mv = np.zeros(T)              # marginal value of deliverable energy added at hour t
    lmp_l, a_l = lmp.tolist(), a_max.tolist()
    for t in range(T - 1, -1, -1):
        p = lmp_l[t]
        # (1) discharge option: a segment of slope p and length d_max, inserted where
        #     the marginal value of keeping energy falls below the price.
        if p > 0.0:
            pos = bisect_left(neg_slopes, -p)
            z_star[t] = sum(lengths[:pos])
            neg_slopes.insert(pos, -p)
            lengths.insert(pos, d_max)
        else:
            z_star[t] = np.inf    # never sell at a non-positive price
        # (2) free charging of up to a_t: the top a_t of the value curve is "filled"
        #     at no cost. Pop it from the front (highest slopes).
        take = a_l[t]
        while take > 1e-12 and lengths:
            if lengths[0] <= take:
                take -= lengths[0]
                neg_slopes.pop(0)
                lengths.pop(0)
            else:
                lengths[0] -= take
                take = 0.0
        mv[t] = -neg_slopes[0] if lengths else 0.0
        # (3) storage capacity: keep only the first s_max of the curve.
        total, keep = 0.0, 0
        for keep, L in enumerate(lengths):
            if total + L >= s_max:
                lengths[keep] = s_max - total
                del lengths[keep + 1:], neg_slopes[keep + 1:]
                break
            total += L

    # ---- forward pass: recover the dispatch from the thresholds -----------
    s = 0.0
    d = np.zeros(T)
    a = np.zeros(T)
    soc = np.zeros(T)
    for t in range(T):
        y = s + a_l[t]                                   # energy available this hour
        dt_ = min(d_max, max(0.0, y - z_star[t]))        # sell what's above threshold
        s_new = min(s_max, y - dt_)                      # charge as much as fits
        a[t] = s_new - s + dt_
        d[t] = dt_
        soc[t] = s_new
        s = s_new

    revenue = float(lmp @ d)
    # Charging at hour t is worth mv[t] per deliverable MWh only when it is
    # limited by curtailment, not by the power rating.
    binding = np.maximum(curt_mw, 0.0) < power_mw
    curt_value = np.where(binding, mv * rt * dt, 0.0)
    return DispatchResult(revenue=revenue, p_dis=d / dt, p_ch=a / (rt * dt),
                          soc=soc / eta_d, curt_value=curt_value)
