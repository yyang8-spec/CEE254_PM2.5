"""Correctness checks for the two exact solvers.

Run:  python -m pytest bess_siting/tests -q
"""
import itertools

import numpy as np
import pytest

from bess_siting.dispatch import solve_dispatch
from bess_siting.siting import knapsack


# ----------------------------------------------------------------------------
# Independent dispatch solver: polymatroid greedy.
# In deliverable-energy units the dispatch LP is a max-weight flow from a free
# source (curtailment) to hourly sinks (sales) through a storage path. The
# feasible sales vectors form a polymatroid, so serving hours in decreasing
# price order, each as much as possible, is optimal. "As much as possible" is
# f(A + v) - f(A), with f(A) = max total sales restricted to hours in A, computed
# by a forward "sell as soon as possible" pass. This algorithm shares no code or
# logic with the backward DP in dispatch.py.
# ----------------------------------------------------------------------------
def _max_flow(A, a_max, d_max, s_max):
    s, total = 0.0, 0.0
    for t in range(len(a_max)):
        y = s + a_max[t]
        d = min(d_max, y) if t in A else 0.0
        total += d
        s = min(s_max, y - d)
    return total


def greedy_revenue(lmp, curt, P, E, eta_c, eta_d):
    rt = eta_c * eta_d
    a_max = rt * np.minimum(P, curt)
    A, f_prev, rev = set(), 0.0, 0.0
    for t in sorted(range(len(lmp)), key=lambda t: -lmp[t]):
        if lmp[t] <= 0:
            break
        A.add(t)
        f = _max_flow(A, a_max, P, eta_d * E)
        rev += lmp[t] * (f - f_prev)
        f_prev = f
    return rev


def check_feasible(res, lmp, curt, P, E, eta_c, eta_d, tol=1e-6):
    assert np.all(res.p_dis >= -tol) and np.all(res.p_dis <= P + tol)
    assert np.all(res.p_ch >= -tol) and np.all(res.p_ch <= np.minimum(P, curt) + tol)
    assert np.all(res.soc >= -tol) and np.all(res.soc <= E + tol)
    soc_prev = np.concatenate([[0.0], res.soc[:-1]])
    balance = soc_prev + eta_c * res.p_ch - res.p_dis / eta_d
    assert np.allclose(balance, res.soc, atol=1e-6)
    assert np.isclose(res.revenue, float(lmp @ res.p_dis))


@pytest.mark.parametrize("seed", range(40))
def test_dispatch_matches_greedy(seed):
    rng = np.random.default_rng(seed)
    T = rng.integers(5, 60)
    hod = np.arange(T) % 24
    lmp = 40 + 40 * np.sin((hod - 13) / 24 * 2 * np.pi) + rng.normal(0, 25, T)
    curt = np.where(rng.random(T) < 0.4, rng.uniform(0, 300, T), 0.0)
    P = float(rng.choice([50, 100, 200]))
    E = P * float(rng.choice([1, 2, 4]))
    eta_c, eta_d = rng.uniform(0.8, 1.0, 2)
    res = solve_dispatch(lmp, curt, P, E, eta_c, eta_d)
    check_feasible(res, lmp, curt, P, E, eta_c, eta_d)
    assert np.isclose(res.revenue, greedy_revenue(lmp, curt, P, E, eta_c, eta_d), rtol=1e-9, atol=1e-6)


def test_textbook_day():
    # 1 hour of curtailment at noon, high price at 7pm: charge P, sell P*rt.
    lmp = np.array([20, 10, -5, 30, 120, 60.0])
    curt = np.array([0, 0, 500, 0, 0, 0.0])
    res = solve_dispatch(lmp, curt, 100, 400, 0.9, 0.9)
    assert np.isclose(res.p_ch[2], 100)
    assert np.isclose(res.p_dis[4], 81)          # 100 * 0.9 * 0.9
    assert np.isclose(res.revenue, 81 * 120)


# ----------------------------------------------------------------------------
# Knapsack: brute force over all (K+1)^N portfolios.
# ----------------------------------------------------------------------------
@pytest.mark.parametrize("seed", range(25))
def test_knapsack_matches_brute_force(seed):
    rng = np.random.default_rng(seed)
    N, K = 6, 3
    costs = np.array([133.6e6, 228e6, 350e6])
    vals = rng.uniform(0, 1, (N, K)) * costs * rng.uniform(0.05, 0.15)
    vals.sort(axis=1)
    budget = rng.uniform(0.3e9, 1.5e9)
    pick, obj = knapsack(vals, costs, budget)
    best = 0.0
    for combo in itertools.product(range(-1, K), repeat=N):
        c = sum(costs[k] for k in combo if k >= 0)
        if c <= budget:
            best = max(best, sum(vals[i, k] for i, k in enumerate(combo) if k >= 0))
    assert np.isclose(obj, best)
    assert sum(costs[k] for k in pick if k >= 0) <= budget
    assert np.isclose(sum(vals[i, k] for i, k in enumerate(pick) if k >= 0), obj)


@pytest.mark.parametrize("seed", range(10))
def test_no_random_feasible_policy_beats_dp(seed):
    """Upper-bound sanity check: 2,000 random feasible dispatches never beat the DP."""
    rng = np.random.default_rng(100 + seed)
    T = 48
    lmp = rng.normal(50, 40, T)
    curt = np.where(rng.random(T) < 0.5, rng.uniform(0, 250, T), 0.0)
    P, E, ec, ed = 100.0, 400.0, 0.92, 0.93
    opt = solve_dispatch(lmp, curt, P, E, ec, ed).revenue
    for _ in range(2000):
        soc, rev = 0.0, 0.0
        for t in range(T):
            ch = rng.uniform(0, min(P, curt[t], (E - soc) / ec))
            soc += ec * ch
            dis = rng.uniform(0, min(P, soc * ed)) * (lmp[t] > 0)
            soc -= dis / ed
            rev += lmp[t] * dis
        assert rev <= opt + 1e-6
