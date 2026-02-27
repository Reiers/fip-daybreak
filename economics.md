# Super FIP — Economic Analysis

## CUDA Simulation Results (RTX 5080, Blackwell)

**Simulation:** 12 named scenarios × 3,650 days + 210 parameter sweep × 5 checkpoints = 44,850 data points
**Source code:** `sim/filecoin_econ_sim.cu` — validated against Filecoin spec math
**Run date:** 2026-02-27

---

## 1. The Core Finding: Fil+ Does NOT Increase Total Minting

**This is the most important economic fact in this FIP.**

The Filecoin spec defines baseline minting using **Raw Byte Power (RBP)**, not Quality-Adjusted Power (QAP):

$$\bar{R}(t) = \min\bigl(\text{baseline}(t),\; \text{RBP}(t)\bigr)$$

$$\theta(t) = \frac{1}{g} \cdot \ln\!\left(\frac{g \cdot \int_0^t \bar{R}(x)\,dx}{b_0} + 1\right)$$

$$M_B(t) = M_{\infty B} \cdot \left(1 - e^{-\lambda\,\theta(t)}\right)$$

**Consequence:** The 10x Fil+ multiplier inflates QAP from 2.17 EiB to 18.5 EiB, but has **zero effect** on the minting trajectory. Total daily issuance is identical (66,249 FIL/day) regardless of VDWM value.

The multiplier ONLY redistributes existing rewards from CC sectors to Fil+ sectors. It is a zero-sum redistribution mechanism, not a productivity incentive.

### Verified by simulation:

| Scenario | Daily Issuance (Year 1) | Daily Issuance (Year 5) | Daily Issuance (Year 10) |
|---|---|---|---|
| Status Quo (VDWM=10) | 61,883 FIL | 39,400 FIL | 22,860 FIL |
| Fil+ Removed (VDWM=1) | 61,883 FIL | 39,400 FIL | 22,860 FIL |

**Identical.** The multiplier doesn't increase the pie — it just changes who gets which slice.

---

## 2. Per-Sector Economics: CC Miners Get 8.5x Revenue Boost

### Current state (With Fil+, VDWM=10):

| Metric | CC Sector (32 GiB) | Fil+ Sector (32 GiB) |
|---|---|---|
| QAP | 32 GiB | 320 GiB |
| Daily reward | 0.000107 FIL ($0.00016) | 0.001067 FIL ($0.0016) |
| Storage pledge | 0.002134 FIL | 0.021340 FIL |
| Consensus pledge | 0.065173 FIL | 0.065173 FIL |
| **Total pledge** | **0.067 FIL** | **0.086 FIL** |
| Annual ROI on pledge | 57.9% | 452.5% |

### After reform (Without Fil+, VDWM=1):

| Metric | All Sectors (32 GiB) |
|---|---|
| QAP | 32 GiB |
| Daily reward | 0.000910 FIL ($0.00137) |
| Storage pledge | 0.018197 FIL |
| Consensus pledge | 0.065173 FIL |
| **Total pledge** | **0.083 FIL** |
| Annual ROI on pledge | 398.6% |

**Impact:**
- CC sector reward: **+8.5x** (from $0.00016 to $0.00137 per day)
- Pledge: +24% (from 0.067 to 0.083 FIL — storage pledge increases because daily reward is higher)
- ROI: +589% (from 57.9% to 398.6% annual)
- Consensus pledge: **UNCHANGED** (because baseline 114 EiB >> QAP in both cases)

---

## 3. The Baseline Gap: 98% of Rewards are Unreachable

| Parameter | Value |
|---|---|
| Current RBP | 2.17 EiB |
| Current baseline | 114.21 EiB |
| RBP as % of baseline | **1.9%** |
| Baseline in 5 years | 3,656 EiB |
| Baseline in 10 years | 116,954 EiB |

The baseline was designed to start at 2.5 EiB and grow 100%/year. After 5.5 years, it's at 114 EiB while actual RBP peaked at ~19 EiB (in 2022) and has since declined to 2.17 EiB. **The network has never exceeded the baseline.**

This means:
- **Effective network time θ = 3.34 years** (vs actual age 5.5 years)
- Of the 770M FIL baseline allocation, only ~246M has been minted (32%)
- ~524M FIL of baseline rewards are effectively locked by the unreachable baseline
- The gap widens exponentially: baseline doubles yearly, RBP declines

### Baseline growth rate sensitivity (Year 5, VDWM=1, RBP stable):

| Baseline Growth | Reward/TiB | Pledge/32GiB | ROI |
|---|---|---|---|
| 0% (freeze) | 0.018244 | 0.085593 | 243% |
| 25%/year | 0.018244 | 0.035713 | 583% |
| 50%/year | 0.018244 | 0.021172 | 984% |
| 75%/year | 0.018244 | 0.015923 | 1,308% |
| 100%/year (status quo) | 0.018244 | 0.013721 | 1,518% |

**Key insight:** Slowing baseline growth doesn't change rewards (same RBP, same minting), but it significantly INCREASES the consensus pledge because `max(baseline, QAP)` in the denominator decreases when baseline is smaller.

**Recommendation:** Keep baseline growth at 100%/year. The growing baseline reduces pledge per sector over time, improving SP economics. Slowing it counterproductively increases pledge.

---

## 4. Scenario Comparison (Year 1 — Actionable Timeframe)

| Scenario | Reward/TiB/day | Pledge/32GiB | ROI% | Description |
|---|---|---|---|---|
| **Status Quo** | 0.003369 | 0.036 | 106% | Current system |
| **Fil+ Removed** | 0.028628 | 0.052 | 626% | VDWM 10→1, same trends |
| **Gradual 3yr** | 0.004773 | 0.037 | 146% | 10→1 over 3 years |
| **Gradual 1yr** | 0.028628 | 0.052 | 626% | 10→1 over 1 year |
| **Conservative** | 0.010561 | 0.041 | 295% | VDWM 10→3 + reserve burn |
| **Full Reform** | 0.027480 | 0.063 | 499% | VDWM→1, baseline 50%, burn |
| **Full Reform Optimistic** | 0.025494 | 0.062 | 472% | Same + RBP grows 10%/yr |

**Recommended: Gradual 1-year transition (10→1)** — achieves same end-state as immediate removal, but gives SPs time to adjust. By month 12, all sectors are equal.

---

## 5. Mining Reserve Burn Impact

The mining reserve is 300M FIL (15% of FIL_BASE) allocated for "future mining types." It has never been used.

| Metric | With Reserve | Reserve Burned |
|---|---|---|
| Daily issuance | Unchanged | Unchanged |
| Per-sector reward | Unchanged | Unchanged |
| Circulating supply | Unchanged* | Unchanged* |
| Potential future inflation | 300M FIL risk | 0 risk |

*The mining reserve is not currently circulating. Burning it doesn't change current economics but **permanently removes 300M FIL of inflation risk**, which is a significant positive signal.

Combined with Fil+ removal, it addresses two community complaints simultaneously:
1. Permissioned block reward distribution (Fil+)
2. Unaccountable token reserves (mining reserve)

---

## 6. Sensitivity Analysis (Parameter Sweep — 210 Combinations)

### Most important finding:

**VDWM is the dominant parameter.** Across all 210 combinations:

| VDWM | Avg Reward/TiB (Y5) | Avg ROI (Y5) |
|---|---|---|
| 1 | 0.026x | 987% |
| 2 | 0.013x | 676% |
| 3 | 0.009x | 523% |
| 5 | 0.005x | 367% |
| 7 | 0.004x | 294% |
| 10 | 0.003x | 225% |
| 15 | 0.002x | 170% |

(x = baseline normalization factor)

Reducing VDWM has the single largest impact on SP economics — much larger than changing baseline growth or even RBP trajectory.

### VDWM=10 vs VDWM=1 (controlled comparison, RBP=-5%/yr, BL=100%):

| | VDWM=10 | VDWM=1 | Change |
|---|---|---|---|
| Reward/TiB | 0.002634 | 0.022378 | **+8.5x** |
| Pledge/32G | 0.003959 | 0.016299 | +4.1x |
| ROI | 759% | 1,567% | **+2.1x** |

---

## 7. Cross-Validation Against Chain State

| Metric | Spec Math | Chain Data | Error |
|---|---|---|---|
| Simple minted | 155.46M FIL | ~155M* | <1% |
| Effective time θ | 3.34 years | N/A (internal) | — |
| Daily issuance | 57,762-66,249† | 66,249 FIL | <15%‡ |
| Baseline level | 114.21 EiB | ~114 EiB | <1% |

*Estimated from total supply minus vesting/baseline
†Range from day 1 (sim) vs actual (day 0 = current)
‡Discrepancy from daily averaging vs epoch-precise calculation

The simulation's math tracks the spec within acceptable bounds.

---

## 8. What This FIP Proposes (Economics Summary)

### Phase 1: VDWM Reduction (10→1 over 12 months)
- Linear reduction of verified deal weight multiplier
- Month 0: VDWM = 10 (status quo)
- Month 6: VDWM = 5.5
- Month 12: VDWM = 1 (all sectors equal)
- **Impact:** CC sector revenue increases ~8.5x over 12 months
- **Total issuance:** UNCHANGED (proven by simulation)
- **Pledge:** +24% per CC sector (storage pledge increases with reward)
- **Consensus pledge:** Unchanged (baseline dominates denominator)

### Phase 2: Mining Reserve Burn
- Set `FIL_MiningReserveAlloc` to 0 (burn/send to f099)
- **Impact:** Removes 300M FIL inflation risk permanently
- **No effect on current economics** — reserve was never circulating

### What we are NOT proposing (and why):
- **Baseline growth change:** Simulation shows slowing baseline INCREASES pledge. Keep at 100%.
- **Reward vesting change:** 180-day vesting provides appropriate security buffer
- **Consensus pledge target change:** 30% is well-calibrated for current network

---

## Appendix: Mathematical Proof

### Theorem: VDWM does not affect total block reward issuance

**Proof:**

The total minted supply $M(t) = M_S(t) + M_B(t)$, where:

$$M_S(t) = M_{\infty S} \cdot \left(1 - e^{-\lambda t}\right) \quad \text{(independent of any network state)}$$

$$M_B(t) = M_{\infty B} \cdot \left(1 - e^{-\lambda\,\theta(t)}\right) \quad \text{where } \theta \text{ depends on cumulative capped RBP}$$

The effective network time $\theta(t)$ is defined by:

$$\int_0^{\theta} b(x)\,dx = \int_0^{t} \min\bigl(b(x),\, R(x)\bigr)\,dx$$

$R(x)$ is the **raw byte power** — the sum of sector sizes in bytes, regardless of quality multiplier. VDWM affects only QAP (quality-adjusted power), not RBP.

Therefore: changing VDWM leaves $R(x)$ unchanged $\Rightarrow$ cumulative sum unchanged $\Rightarrow$ $\theta(t)$ unchanged $\Rightarrow$ $M_B(t)$ unchanged $\Rightarrow$ $M(t)$ unchanged. $\blacksquare$

**Corollary:** The 10x multiplier is a pure redistribution mechanism. It taxes CC sectors to subsidize Fil+ sectors, with no net benefit to the network's minting trajectory.
