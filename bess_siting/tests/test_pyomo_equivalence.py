"""The monolithic Pyomo MILP and the decomposed solver must agree.

Skipped automatically if pyomo/highspy are not installed:
    pip install pyomo highspy && python -m pytest bess_siting/tests -q
"""
import pytest

pytest.importorskip("pyomo")
pytest.importorskip("highspy")

from bess_siting.config import ModelConfig
from bess_siting.data import allocate_curtailment, make_synthetic_inputs
from bess_siting.siting import optimize, revenue_table


@pytest.mark.parametrize("budget", [0.5e9, 1.2e9])
def test_monolithic_equals_decomposed(budget):
    from bess_siting.pyomo_model import build_model, solve_model

    inp = make_synthetic_inputs()
    nodes = inp.node_names[:8]
    H = 24 * 7
    lmp = inp.lmp[nodes].iloc[2400:2400 + H]          # a spring week, curtailment present
    curt = allocate_curtailment(inp)[nodes].iloc[2400:2400 + H]
    cfg = ModelConfig(budget=budget)

    _, rev_milp, _ = solve_model(build_model(lmp, curt, cfg), mip_gap=1e-9)
    rev_dec = optimize(revenue_table(lmp, curt, cfg), cfg).revenue
    assert rev_milp == pytest.approx(rev_dec, rel=1e-6)
