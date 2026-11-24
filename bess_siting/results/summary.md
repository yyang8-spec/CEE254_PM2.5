# BESS siting results (SYNTHETIC DEMO DATA, not real CAISO results)

## Inputs

| stat | value |
|---|---|
| nodes | 41.00 |
| hours | 8760.00 |
| solar_GW | 12.51 |
| largest_plant_MW | 950.00 |
| mean_LMP | 53.12 |
| daily_spread_min_node | 54.19 |
| daily_spread_max_node | 86.73 |
| share_negative_LMP_hours | 0.03 |
| curtailment_TWh | 3.40 |
| curtailment_hours | 1690.00 |
| peak_curtailment_MW | 8988.06 |

## Revenue table R[i,k]

41 nodes x 3 tiers = 123 dispatch LPs (8760 h each) solved in 1.6 s.

Annual revenue per $ of capex, % per year (mean / min / max across nodes):

| stat | Small | Medium | Large |
|---|---|---|---|
| mean | 3.15 | 2.50 | 1.83 |
| min | 2.22 | 1.47 | 1.01 |
| max | 4.86 | 4.59 | 4.17 |

## Budget scenarios ($3B / $6B / $9B)

| budget_$B | nodes | MW | MWh | investment_$B | revenue_$M_per_yr | revenue/capex_%_per_yr | simple_payback_yr | n_Small | n_Medium | n_Large | marginal_rev_per_$capex_% |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 3.00 | 21 | 2300.00 | 9200.00 | 2.99 | 104.26 | 3.48 | 28.72 | 19 | 2 | 0 | nan |
| 6.00 | 39 | 4750.00 | 19000.00 | 5.99 | 188.23 | 3.14 | 31.84 | 32 | 6 | 1 | 2.80 |
| 9.00 | 41 | 7900.00 | 31600.00 | 8.99 | 236.78 | 2.63 | 37.95 | 9 | 28 | 4 | 1.62 |

## Budget sweep (efficient frontier)

| budget_$B | nodes | MW | investment_$B | revenue_$M_per_yr | revenue/capex_%_per_yr | marginal_rev_per_$capex_% |
|---|---|---|---|---|---|---|
| 0.50 | 3 | 400.00 | 0.50 | 20.99 | 4.24 | nan |
| 1.00 | 6 | 800.00 | 0.99 | 38.13 | 3.85 | 3.46 |
| 1.50 | 9 | 1200.00 | 1.49 | 54.60 | 3.68 | 3.33 |
| 2.00 | 14 | 1500.00 | 1.96 | 71.66 | 3.65 | 3.56 |
| 2.50 | 18 | 1900.00 | 2.50 | 88.94 | 3.56 | 3.23 |
| 3.00 | 21 | 2300.00 | 2.99 | 104.26 | 3.48 | 3.09 |
| 3.50 | 23 | 2750.00 | 3.48 | 119.11 | 3.42 | 3.07 |
| 4.00 | 28 | 3050.00 | 3.96 | 133.70 | 3.38 | 3.04 |
| 4.50 | 32 | 3450.00 | 4.49 | 149.32 | 3.32 | 2.92 |
| 5.00 | 35 | 3850.00 | 4.99 | 162.98 | 3.27 | 2.76 |
| 5.50 | 38 | 4250.00 | 5.48 | 176.23 | 3.21 | 2.68 |
| 6.00 | 39 | 4750.00 | 5.99 | 188.23 | 3.14 | 2.35 |
| 6.50 | 41 | 5150.00 | 6.45 | 198.32 | 3.08 | 2.21 |
| 7.00 | 40 | 5750.00 | 6.98 | 207.62 | 2.98 | 1.76 |
| 7.50 | 41 | 6250.00 | 7.49 | 216.84 | 2.90 | 1.80 |
| 8.00 | 41 | 6800.00 | 7.99 | 224.30 | 2.81 | 1.49 |
| 8.50 | 41 | 7350.00 | 8.49 | 230.92 | 2.72 | 1.33 |
| 9.00 | 41 | 7900.00 | 8.99 | 236.78 | 2.63 | 1.17 |
| 9.50 | 41 | 8450.00 | 9.49 | 241.29 | 2.54 | 0.90 |
| 10.00 | 41 | 9050.00 | 9.97 | 245.26 | 2.46 | 0.81 |
| 10.50 | 41 | 9600.00 | 10.47 | 248.75 | 2.38 | 0.70 |
| 11.00 | 41 | 10250.00 | 10.99 | 251.98 | 2.29 | 0.63 |
| 11.50 | 41 | 10850.00 | 11.48 | 254.44 | 2.22 | 0.50 |
| 12.00 | 41 | 11400.00 | 11.94 | 256.60 | 2.15 | 0.47 |

## Baseline portfolio ($6B), top 10 by revenue

| node | tier | power_mw | energy_mwh | capex | revenue | solar_mw | region |
|---|---|---|---|---|---|---|---|
| ANTELOPE_05 | Large | 350.00 | 1400.00 | 350.00 | 14.59 | 950.00 | ANTELOPE |
| IMPERIAL_06 | Medium | 200.00 | 800.00 | 228.00 | 8.10 | 424.80 | IMPERIAL |
| MOJAVE_03 | Medium | 200.00 | 800.00 | 228.00 | 7.76 | 439.50 | MOJAVE |
| KERN_07 | Medium | 200.00 | 800.00 | 228.00 | 7.32 | 461.50 | KERN |
| MOJAVE_05 | Medium | 200.00 | 800.00 | 228.00 | 6.85 | 362.00 | MOJAVE |
| MOJAVE_01 | Medium | 200.00 | 800.00 | 228.00 | 6.81 | 374.60 | MOJAVE |
| KERN_08 | Medium | 200.00 | 800.00 | 228.00 | 6.71 | 372.30 | KERN |
| IMPERIAL_04 | Small | 100.00 | 400.00 | 133.60 | 4.65 | 319.10 | IMPERIAL |
| SJV_06 | Small | 100.00 | 400.00 | 133.60 | 4.56 | 379.80 | SJV |
| MOJAVE_07 | Small | 100.00 | 400.00 | 133.60 | 4.54 | 329.80 | MOJAVE |

## Dispatch diagnostics: ANTELOPE_05

- charged 234.8 GWh of 258.1 GWh allocated curtailment (91% absorbed)
- discharged 211.9 GWh, i.e. 151 full-cycle equivalents per year
- 431 hours charge and discharge in the same hour; that 'pass-through' of curtailed energy is ~25% of discharged MWh
- average realized price on discharge: $68.8/MWh
- marginal value of +1 MWh curtailment (mean over curtailed hours): $66.3/MWh

Average hourly profile (MW):

| hour | lmp | p_ch | p_dis |
|---|---|---|---|
| 0 | 56.75 | 0.00 | 0.00 |
| 1 | 56.73 | 0.00 | 0.00 |
| 2 | 56.93 | 0.00 | 0.00 |
| 3 | 56.79 | 0.00 | 0.00 |
| 4 | 57.11 | 0.00 | 0.00 |
| 5 | 58.34 | 0.00 | 0.00 |
| 6 | 59.52 | 3.49 | 2.87 |
| 7 | 54.83 | 25.22 | 18.22 |
| 8 | 44.37 | 52.69 | 33.46 |
| 9 | 34.19 | 74.08 | 17.67 |
| 10 | 27.94 | 86.92 | 1.71 |
| 11 | 25.60 | 92.28 | 0.00 |
| 12 | 25.85 | 92.28 | 0.00 |
| 13 | 27.63 | 76.28 | 3.93 |
| 14 | 31.55 | 61.26 | 16.29 |
| 15 | 38.90 | 50.16 | 29.33 |
| 16 | 50.58 | 25.22 | 17.95 |
| 17 | 68.66 | 3.49 | 10.46 |
| 18 | 83.64 | 0.00 | 97.15 |
| 19 | 89.94 | 0.00 | 184.33 |
| 20 | 84.13 | 0.00 | 102.29 |
| 21 | 72.10 | 0.00 | 44.48 |
| 22 | 62.75 | 0.00 | 0.50 |
| 23 | 58.10 | 0.00 | 0.00 |

## Sensitivity analysis (baseline $6B)

| scenario | nodes | MW | investment_$B | revenue_$M_per_yr | revenue_vs_base_% | simple_payback_yr |
|---|---|---|---|---|---|---|
| Baseline ($6B, eta_c = eta_d = 0.95) | 39 | 4750.00 | 5.99 | 188.23 | 0.00 | 31.84 |
| Battery capex -15% | 41 | 5800.00 | 5.99 | 209.08 | 11.08 | 28.63 |
| Charging efficiency 0.85 | 41 | 4650.00 | 5.98 | 178.09 | -5.39 | 33.56 |
| Discharging efficiency 0.85 | 39 | 4750.00 | 5.99 | 170.30 | -9.52 | 35.19 |
| Curtailment allocated over all CAISO solar (24.7 GW) | 41 | 4650.00 | 5.98 | 125.63 | -33.26 | 47.58 |
| Curtailment x0.5 | 41 | 4650.00 | 5.98 | 124.41 | -33.91 | 48.05 |
| Curtailment x2 | 39 | 4750.00 | 5.99 | 250.82 | 33.25 | 23.89 |
| Charge only when nodal LMP <= 0 (no pass-through) | 31 | 5100.00 | 5.99 | 69.52 | -63.07 | 86.16 |
| Intraday LMP spread -20% (cannibalization proxy) | 41 | 4650.00 | 5.98 | 174.67 | -7.20 | 34.22 |
| Net-value objective, no RA payment | 0 | 0.00 | 0.00 | 0.00 | -100.00 | inf |
| Net-value objective, RA $10/kW-month | 17 | 5950.00 | 5.95 | 136.71 | -27.37 | 43.52 |
