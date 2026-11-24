"""Model parameters for the BESS siting-and-sizing MILP.

Every number that the report states lives here so it can be changed in one
place and cited in one place.
"""
from dataclasses import dataclass, field, replace


@dataclass(frozen=True)
class Tier:
    """One discrete battery size option (index k in the formulation)."""
    name: str
    power_mw: float          # P_k  [MW]
    cost_per_kwh: float      # $/kWh of energy capacity (NREL ATB 2024 + scale discount)
    duration_h: float = 4.0  # 4-hour system

    @property
    def energy_mwh(self) -> float:          # E_k = P_k * duration
        return self.power_mw * self.duration_h

    @property
    def capex(self) -> float:               # C_k [$] = E_k[MWh] * 1000 kWh/MWh * $/kWh
        return self.energy_mwh * 1000.0 * self.cost_per_kwh


# $334/kWh baseline (NREL ATB 2024, 4-h), 15% and 25% economies-of-scale
# discounts for the medium and large tiers -> 334, ~284, ~250 $/kWh.
# Capex: $133.6M, $228M, $350M (matches report Table 2).
# Note: Table 2 of the report labels the middle tier "150 MW" but gives it
# 800 MWh, which is 200 MW x 4 h; Section 2 and 3.3 also say 200 MW.
DEFAULT_TIERS = (
    Tier("Small",  100.0, 334.0),
    Tier("Medium", 200.0, 285.0),
    Tier("Large",  350.0, 250.0),
)


@dataclass(frozen=True)
class ModelConfig:
    tiers: tuple = DEFAULT_TIERS
    budget: float = 6e9           # B [$]
    eta_c: float = 0.95           # charging efficiency
    eta_d: float = 0.95           # discharging efficiency
    dt_h: float = 1.0             # hourly time step
    capex_multiplier: float = 1.0  # sensitivity knob, e.g. 0.85 for -15%

    # Objective. "revenue": the report's objective (max discharge revenue s.t. budget).
    # "net": revenue minus annualized capital cost (lets the optimizer leave budget unspent).
    objective: str = "revenue"
    discount_rate: float = 0.07
    lifetime_yr: int = 15
    fixed_om_frac: float = 0.025   # fixed O&M as fraction of capex per year (net objective only)
    ra_per_kw_month: float = 0.0   # resource-adequacy capacity payment, $/kW-month (net objective only)

    def tier_capex(self, k: int) -> float:
        return self.tiers[k].capex * self.capex_multiplier

    @property
    def crf(self) -> float:
        """Capital recovery factor: converts a lump-sum capex into an equal annual payment."""
        r, n = self.discount_rate, self.lifetime_yr
        return r * (1 + r) ** n / ((1 + r) ** n - 1)

    def with_(self, **kw) -> "ModelConfig":
        return replace(self, **kw)
