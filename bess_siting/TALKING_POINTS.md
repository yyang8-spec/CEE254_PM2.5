# Talking points: BESS siting & sizing MILP

How to explain the project: the formulation, the Python implementation, the
results, and the sensitivities. It also covers the questions you're likely to get.
Code references point into this folder.

---

## 1. The 30-second version

> California curtails terawatt-hours of solar at midday while evening prices spike.
> We asked: given a fixed capital budget, **where** should batteries co-located with
> large solar plants go, and **how big** should each one be, to capture the most of
> that spread? We built a mixed-integer linear program over 41 CAISO pricing nodes
> and 8,760 hours. Binary variables choose a battery size at each node. Continuous
> variables run the battery every hour: charge only from curtailed solar, discharge
> into the nodal day-ahead price. We solved it for $3B, $6B and $9B budgets and
> stress-tested costs, efficiencies, and the curtailment assumptions.

The one-line technical hook for the Python version:

> The full MILP has about a million variables. But once you notice that nodes interact
> **only through the budget**, it splits exactly into 123 small dispatch LPs plus a
> 123-item knapsack. I solve each piece exactly. The whole year takes about 2 seconds
> instead of minutes to hours, and I verified it against the monolithic Pyomo/HiGHS
> model.

---

## 2. The formulation (what to say about each piece)

**Sets.** N = candidate nodes (41), T = hours (8,760), K = {Small, Medium, Large}.

**Parameters.** LMP<sub>i,t</sub> (GridStatus day-ahead), system curtailment (CAISO OASIS),
solar nameplate (EIA-860), tier power P<sub>k</sub>, energy E<sub>k</sub> = 4·P<sub>k</sub>, capex C<sub>k</sub> (NREL ATB 2024),
efficiencies η<sub>c</sub> = η<sub>d</sub> = 0.95, budget B.
→ [`config.py`](config.py), [`data.py`](data.py)

| tier | MW | MWh | $/kWh | capex |
|---|---|---|---|---|
| Small | 100 | 400 | 334 | $133.6M |
| Medium | 200 | 800 | 285 (−15%) | $228M |
| Large | 350 | 1,400 | 250 (−25%) | $350M |

**Decision variables.**
- x<sub>i,k</sub> ∈ {0,1}: build tier k at node i. *The only integer variables, 123 of them.*
- P<sup>ch</sup><sub>i,t</sub>, P<sup>dis</sup><sub>i,t</sub> ≥ 0 [MW], SOC<sub>i,t</sub> ≥ 0 [MWh]: hourly operation.
- Installed power Cap<sub>i</sub> = Σ<sub>k</sub> P<sub>k</sub> x<sub>i,k</sub>.

**Objective:** max Σ<sub>i,t</sub> LMP<sub>i,t</sub> · P<sup>dis</sup><sub>i,t</sub> · Δt  → [`pyomo_model.py:58`](pyomo_model.py#L58)

What to say: *charging is free because it only uses curtailed solar, which would
otherwise be thrown away. So revenue is just what you sell. The cost of charging
shows up physically, through the energy balance: you can't sell energy you didn't
store, and you lose 1 − η<sub>c</sub>η<sub>d</sub> ≈ 10% of it on the round trip.*

**Constraints** → [`pyomo_model.py:63-73`](pyomo_model.py#L63)

| constraint | math | why |
|---|---|---|
| Budget | Σ C<sub>k</sub> x<sub>i,k</sub> ≤ B | the only thing linking nodes |
| One tier per node | Σ<sub>k</sub> x<sub>i,k</sub> ≤ 1 | mutual exclusivity |
| Power limits | P<sup>ch</sup>, P<sup>dis</sup> ≤ Cap<sub>i</sub> | inverter rating |
| Charging source | P<sup>ch</sup><sub>i,t</sub> ≤ Curt<sub>i,t</sub> | only charge from curtailed solar (no grid charging) |
| Energy balance | SOC<sub>t</sub> = SOC<sub>t−1</sub> + (η<sub>c</sub>P<sup>ch</sup> − P<sup>dis</sup>/η<sub>d</sub>)Δt, SOC<sub>0</sub> = 0 | storage physics |
| Energy limit | SOC ≤ 4 · Cap<sub>i</sub> | 4-hour duration |

**Curtailment allocation** (CAISO publishes curtailment only system-wide):
Curt<sub>i,t</sub> = SysCurt<sub>t</sub> · Cap<sup>solar</sup><sub>i</sub> / Cap<sup>total</sup> → [`data.py:37`](data.py#L37)

### Modeling choices you should be able to defend

- **Why discrete tiers instead of a continuous size?** Cost per kWh *falls* with size
  (fixed EPC, interconnection, and land costs get spread). A continuous size with a
  linear cost can't represent economies of scale: that would make cost concave, which
  is non-convex. Three binaries per node capture it exactly while staying linear.
  (Extension: an SOS2 piecewise-linear cost curve for a continuous size.)
- **No big-M needed.** Cap<sub>i</sub> is a *linear* expression in x, so "power ≤ Cap" turns
  itself off when nothing is built (Cap = 0). This keeps the LP relaxation tight.
  Interviewers like hearing that you thought about big-M.
- **Why it's a MILP and not just an LP.** Without the binaries you could build 37% of a
  Large battery. The relaxation is still useful: it gives the upper bound that
  branch-and-bound closes against.
- **Problem size:** 3 × 41 × 8,760 ≈ **1.08 M continuous variables**, 123 binaries, and
  ≈ 1.8 M constraints. (The report's "~0.5M variables" matches 43 nodes × ~5 months,
  so check which horizon you actually ran.)
- **What HiGHS does:** branch-and-bound on x, solving LP relaxations with dual simplex
  or interior point, plus cuts and presolve. It stops when the incumbent is within the
  MIP gap (default 0.01%) of the best bound.

---

## 3. The Python implementation (the "technology" story)

### 3.1 Two implementations that agree

1. **Monolithic MILP** in Pyomo + HiGHS ([`pyomo_model.py`](pyomo_model.py)). It reads
   like the math: `Set`, `Param`, `Var(domain=Binary)`, `Constraint(rule=...)`. It's the
   direct translation of the JuMP model. Good for showing the formulation; slow to
   build and solve at full scale.
2. **Exact decomposition** ([`siting.py`](siting.py) + [`dispatch.py`](dispatch.py)), which is
   what `run.py` uses.

### 3.2 Why the decomposition is exact (be ready to argue this)

Fix the siting decision x. Then:
- the objective is a **sum over nodes**,
- every dispatch constraint involves **only one node**,
- the budget involves **only x**.

So for each node and tier, the best revenue R<sub>i,k</sub> is an independent LP. The
whole MILP becomes

  max Σ R<sub>i,k</sub> x<sub>i,k</sub>  s.t.  Σ C<sub>k</sub> x<sub>i,k</sub> ≤ B,  Σ<sub>k</sub> x<sub>i,k</sub> ≤ 1

which is a **multiple-choice knapsack**. This isn't a heuristic. It's a reformulation
with the same optimum.

**When it breaks** (the follow-up question): anything that couples nodes in operation.
Examples: transmission limits (DC-OPF), prices that respond to battery dispatch, or a
shared curtailment pool where one battery's charging reduces another's. Then you go
back to the monolithic model, or use **Benders decomposition**: x in the master
problem, dispatch LPs as subproblems that send back optimality cuts.

### 3.3 Solving the dispatch LP exactly: a backward dynamic program

[`dispatch.py:53`](dispatch.py#L53). Intuition you can say out loud:

> Every MWh in the battery has a "water value": the best future price you could sell
> it at. Walking backward through the year, I keep a sorted list of future selling
> opportunities, each a segment of energy with a price. At hour t, three things happen.
> (1) Selling now adds a segment worth LMP<sub>t</sub> with length P. (2) Free curtailment
> fills the most valuable segments first. (3) The battery size cuts the list off at
> E. The list *is* the value function, which is concave and piecewise linear in SOC.
> A forward pass then reads off the policy: "sell everything above threshold z*<sub>t</sub>."

- Trick: measure energy in *deliverable* units, s = η<sub>d</sub>·SOC. The efficiencies then
  drop out of the dynamics and become a scaling on the charging limit.
- Cost: O(T × #segments), about 15 ms per node-year in pure Python. Nothing to install.
- Bonus output: the slope of the value function is the **shadow price of curtailment**,
  meaning what one more MWh of curtailed solar at that hour is worth (`curt_value`).
  That's the LP dual, without calling an LP solver.

### 3.4 Knapsack by dynamic programming

[`siting.py:55`](siting.py#L55). DP over the budget in $100k steps: `best[b]` = max revenue
spending ≤ b. It's exact, takes milliseconds, and costs are rounded *up*, so solutions
are always feasible. It returns the **cheapest** portfolio among all optimal ones (line 85).
That matters because with a revenue-only objective, "investment consumed" is otherwise
arbitrary when there are ties (see §6).

### 3.5 Verification ([`tests/`](tests/))

- The dispatch DP matches an *independent* algorithm on 40 random instances. The other
  algorithm is a polymatroid greedy: serve hours in decreasing price order, each as
  much as max-flow allows.
- 2,000 random feasible dispatch policies never beat the DP.
- Every solution satisfies all constraints (power, source, SOC bounds, energy balance).
- The knapsack matches brute-force enumeration of all 4<sup>6</sup> portfolios.
- The Pyomo MILP matches the decomposition on a 1-week, 8-node instance (needs `pyomo`
  and `highspy` installed).

### 3.6 Why this design is practical

Each scenario type costs a different amount: **budget, capex and objective changes only
re-run the knapsack** (ms), and **efficiency, curtailment and price changes re-run the
123 LPs** (~2 s). A 24-point budget frontier is basically free. With the monolithic
model, each point would be a fresh million-variable MILP.

---

## 4. Results: how to read them

> ⚠️ `results/summary.md` was generated from **synthetic** CAISO-like data (41 nodes,
> 12.5 GW, 3.4 TWh curtailment), because the real CSVs weren't available. Treat the
> patterns as the story and re-run with `--data` before you quote numbers.

Patterns that come from the model's structure (these should hold on real data too):

1. **Diminishing marginal returns.** Each extra $ of capex buys less annual revenue.
   On synthetic data the marginal return falls from about 3.5%/yr at low budgets to
   under 1%/yr past $10B. The best nodes and the best curtailment hours get used up
   first. That's the knapsack filling in value-per-dollar order.
2. **Small tiers first, big tiers later.** At low budgets the optimizer picks many 100 MW
   batteries. Each node's curtailment share fills a small battery, and adding MW at the
   same node runs into the same limited curtailment. As the budget grows it upgrades
   nodes to 200 or 350 MW. The largest solar plant (950 MW, so the most allocated
   curtailment) gets a Large battery. Economies of scale in capex compete with
   diminishing returns in revenue per node.
3. **Siting follows solar size × price spread.** Proportional allocation gives the
   biggest plants the most charging energy. The LMP evening premium (Imperial/Mojave in
   the synthetic data) decides ties.
4. **Dispatch looks like the duck curve:** charge 9am–3pm, discharge 6–9pm, about 150
   full cycles a year at the top node, realizing about $69/MWh.

### Sanity-check the economics (an interviewer will)

Annual revenue / capex on synthetic data is about **3%/yr**, a simple payback of
**about 30 years**. A battery with 15-year life, 7% WACC and 2.5% O&M needs about
13.5%/yr. With the net-value objective (`objective="net"`), the optimizer builds
**nothing** on arbitrage alone. It only builds once you add resource-adequacy
capacity payments (~$10/kW-month → 17 sites). That's the quantitative version of the
report's conclusion: "curtailment arbitrage alone yields margins insufficient to
amortize capex", and it explains why real batteries sit near load centers, where RA
value is.

---

## 5. Sensitivity analysis: what each one teaches

Baseline $6B (synthetic data; `results/sensitivity.csv`):

| scenario | revenue vs base | what it means |
|---|---|---|
| Capex −15% | **+11%** | budget binds, so cheaper batteries = more MW deployed |
| η<sub>c</sub> 0.95 → 0.85 | −5% | only bites when curtailment limits charging |
| η<sub>d</sub> 0.95 → 0.85 | **−10%** | hurts more than η<sub>c</sub>: it also shrinks the energy you can deliver from a full battery (4 h × η<sub>d</sub>) |
| Curtailment over all 24.7 GW CAISO solar | **−33%** | the allocation denominator is a hidden assumption, and the biggest one |
| Curtailment ×0.5 / ×2 | −34% / +33% | revenue is curtailment-limited; it's the dominant driver |
| Charge only when nodal LMP ≤ 0 | **−63%** | most "curtailment" charging happens at hours when the node's price is positive (see §6) |
| Intraday spread −20% | −7% | crude proxy for price cannibalization |
| Net-value objective | build 0 | arbitrage alone isn't investable |
| Net + RA $10/kW-mo | 17 sites | capacity value is what makes projects pencil |

The key message: **the curtailment assumptions dominate everything else.** Efficiency
and cost move revenue by 5–11%. How you allocate curtailment moves it by 30–60%. So the
most valuable next step is node-level curtailment data or a DC-OPF, not a better
battery.

### Reconciling with the report's Section 5

The report found efficiency changes *didn't* move revenue and explained it as
"curtailment is abundant". That's internally consistent: if charging energy never
binds, efficiency only changes how much curtailment you draw. But it implies that
curtailment was much larger relative to battery size than 3–4 TWh/yr allows (see §6).
In this re-implementation, with ~3.4 TWh, curtailment *does* bind and efficiency matters.

---

## 6. Things to fix or be ready for in the report

Fix these before presenting, or have an answer ready:

1. **Revenue magnitude.** Table 3 says $2.6B / $5.8B / $8.6B per year. Upper bound:
   all charging comes from curtailment (~3–4 TWh/yr), so discharge ≤ ~3.4 TWh × 0.90 ≈
   3.1 TWh, and even at $150/MWh that's ≤ $0.46B/yr. $5.8B is >10× above what's physically
   possible. A ~12× error is exactly what you get from **summing 5-minute CAISO
   curtailment intervals instead of averaging them** (see `data.hourly_from_5min`).
   That's a hypothesis to check: compare total discharged MWh to total curtailment MWh.
   It would also explain the "efficiency doesn't matter" result. Section 4.1's text says
   $26.4M, and 4.2 says $8.60B. Pick the one the code supports.
2. **"Marginal revenue 1.22 per $"** compares *annual* revenue with *one-time* capex,
   which implies a payback under one year. That contradicts the conclusion. Express it as
   %/yr (revenue/capex) or use an NPV.
3. **Tier sizes are inconsistent.** Table 2 says 100/150/350 MW, but 150 MW × 4 h ≠ 800 MWh.
   Sections 2 and 3.3 say 100/200/350, and Section 4 and the conclusion say 100/150/300.
   The costs ($228M = 800 MWh × $285) only work for 200 MW. This code uses 100/200/350.
4. **Node count** is 41 or 43, and the **baseline budget** is $2B (§3.6) or $3B (§4.1).
   The horizon is 12 months (§2) or 5 months (§7).
5. **"Investment consumed" in the sensitivities** ($4.86B vs $4.37B with identical revenue).
   The objective has no capex term, so among optimal portfolios the solver's choice of
   spend is arbitrary. These differences are degeneracy, not insight. Fix it with a
   lexicographic second objective (min capex among revenue-optimal portfolios, which is
   what `knapsack` does) or a net-value objective. The text (§5.2: $5.65B) and table
   ($4.86B) also disagree.
6. **The SOC initial condition** in §3.6 is garbled. It should be SOC<sub>i,0</sub> = 0 (or a
   fixed fraction). Mention that there's no end-of-horizon SOC condition.
7. Two tables are numbered "Table 3", and "24.7 GM" should be GW.

---

## 7. Limitations & extensions (in order of impact)

1. **Curtailment allocation and the pass-through artifact.** Allocating *system*
   curtailment to nodes means the battery can "charge from curtailment" at hours when
   its own node's price is positive. Since the model doesn't forbid simultaneous
   charge and discharge, it also sells that curtailed energy in the same hour. In the
   synthetic run that's ~25% of discharged MWh at the top node. Fixes: node-level
   curtailment (OASIS / telemetry), or a DC-OPF where congestion creates the curtailment
   endogenously.
2. **Price-taker.** 5–9 GW of new batteries would flatten the spread they arbitrage
   (cannibalization). Fixes: an equilibrium model (MPEC), iterating the price
   response, or at least a spread-compression sensitivity (included: −20% spread →
   −7% revenue).
3. **Perfect foresight.** The model knows the whole year's prices in advance, so revenue
   is an *upper bound*. Real operators bid with forecasts. Rolling-horizon or
   stochastic dispatch would typically capture 70–90% of it.
4. **Revenue stack.** Energy arbitrage only. Adding RA capacity payments, ancillary
   services (regulation, spinning reserve), and grid charging changes siting toward
   load centers. That's the gap the report's real-world map comparison (Fig. 1 vs 2)
   shows.
5. **Discrete tiers.** Lumpy decisions → SOS2 piecewise-linear cost curve.
6. **Battery details.** Degradation and cycle costs (add a $/MWh throughput cost),
   end-of-horizon SOC, and interconnection cost by node.

---

## 8. Likely questions, with short answers

- **"Why MILP and not a heuristic?"** You get a provably optimal answer and a bound, and
  the problem is small in the integer dimension (123 binaries). Duals and
  sensitivities are also interpretable.
- **"How long does it take to solve?"** Monolithic: about a million variables, so building
  in Pyomo takes minutes, and HiGHS time depends on the gap. Decomposed: about 2 s for
  the year, plus milliseconds per budget scenario.
- **"How do you know the answer is right?"** Two independent algorithms agree, brute force
  agrees on small cases, every constraint is checked, and the monolithic MILP matches.
- **"What's the binding constraint?"** Mostly the charging-source constraint (curtailment)
  and the budget. The marginal value of curtailment (~$66/MWh at the top node) is the
  dual that shows it.
- **"Why doesn't the battery charge from the grid at night?"** It's a design choice: the
  study is about absorbing curtailment. Allowing grid charging (with LMP as the cost)
  is a one-line change to the objective and would raise revenue.
- **"What would you do with more time?"** Node-level curtailment, a DC-OPF with Benders,
  price response, and a full revenue stack with NPV in the objective.
- **"Python vs Julia?"** JuMP builds big models faster. In Python, Pyomo is the standard
  algebraic modeling tool; linopy/cvxpy are faster for vectorized models. In this
  case, exploiting the problem's structure mattered more than the modeling language.
