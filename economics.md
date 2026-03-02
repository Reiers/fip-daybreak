# Super FIP — Economic Analysis

## CUDA Simulation Results (RTX 5080, Blackwell)

**Simulation:** 12 named scenarios × 3,650 days + 210 parameter sweep × 5 checkpoints = 44,850 data points
**Source code:** `sim/filecoin_econ_sim.cu` — validated against Filecoin spec math
**Chain state:** Epoch ~5,796,404 (Filfox API)

---

## 1. The Core Finding: Fil+ Does NOT Increase Total Minting

**This is the most important economic fact in this FIP.**

The Filecoin spec defines baseline minting using **Raw Byte Power (RBP)**, not Quality-Adjusted Power (QAP):

$$\bar{R}(t) = \min(\text{baseline}(t),\; \text{RBP}(t))$$

$$\theta(t) = \frac{1}{g} \cdot \ln\left(\frac{g \cdot \int_0^t \bar{R}(x)\,dx}{b_0} + 1\right)$$

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

*Pledge uses FIP-0081 formula (NV24): ConsensusPledge = (1-γ)×Simple + γ×Baseline, γ=0.7*

| Metric | CC Sector (32 GiB) | Fil+ Sector (32 GiB) |
|---|---|---|
| QAP | 32 GiB | 320 GiB |
| Daily reward | 0.000107 FIL ($0.00016) | 0.001067 FIL ($0.0016) |
| Storage pledge | 0.002134 FIL | 0.021340 FIL |
| Consensus pledge (simple, 30%) | 0.1207 FIL | 1.207 FIL |
| Consensus pledge (baseline, 70%) | 0.0455 FIL | 0.455 FIL |
| **Total pledge** | **0.169 FIL** | **1.683 FIL** |
| Annual ROI on pledge | ~23% | ~23% |

### After reform (Without Fil+, VDWM=1):

| Metric | All Sectors (32 GiB) |
|---|---|
| QAP | 32 GiB |
| Daily reward | 0.000910 FIL ($0.00137) |
| Storage pledge | 0.018197 FIL |
| Consensus pledge (simple, 30%) | 1.029 FIL |
| Consensus pledge (baseline, 70%) | 0.0455 FIL |
| **Total pledge** | **1.093 FIL** |
| Annual ROI on pledge | ~30% |

**Impact:**
- CC sector reward: **+8.5x** (from $0.00016 to $0.00137 per day)
- Pledge: +6.5× (from 0.169 to 1.093 FIL — Simple consensus pledge scales with share of NetworkQAP)
- ROI: +30% (from ~23% to ~30% annual)
- Consensus pledge (baseline component): **UNCHANGED** (because baseline 114 EiB >> QAP in both cases)
- Consensus pledge (simple component): scales proportionally with rewards (8.5×), as designed by FIP-0081

---

## 3. The Baseline Gap: 98% of Rewards are Unreachable

| Parameter | Value |
|---|---|
| Current RBP | 2.17 EiB |
| Current baseline | 114.21 EiB |
| RBP as % of baseline | **1.9%** |
| Baseline in 5 years | 3,656 EiB |
| Baseline in 10 years | 116,954 EiB |

The baseline was designed to start at 2.5 EiB and grow 100%/year. The network exceeded the baseline from April 2021 through early 2023, with RBP peaking at ~17 EiB against a baseline of ~10 EiB (August 2022). Since then, RBP has declined to 2.17 EiB while the baseline has grown to ~114.5 EiB. **The gap is now structural and widening exponentially.**

This means:
- **Effective network time θ = 3.34 years** (vs actual age 5.5 years)
- Of the 770M FIL baseline allocation, only ~246M has been minted (32%)
- ~524M FIL of baseline rewards are effectively locked by the unreachable baseline
- The gap widens exponentially: baseline doubles yearly, RBP declines

### Baseline growth rate sensitivity (Year 5, VDWM=1, RBP stable, FIP-0081):

| Baseline Growth | Reward/TiB | Pledge/32GiB | ROI |
|---|---|---|---|
| 0% (freeze) | 0.018244 | 1.234710 | 16.9% |
| 25%/year | 0.018244 | 1.199794 | 17.4% |
| 50%/year | 0.018244 | 1.189616 | 17.5% |
| 75%/year | 0.018244 | 1.185941 | 17.6% |
| 100%/year (status quo) | 0.018244 | 1.184400 | 17.6% |

**Key insight:** Reward is identical across all growth rates (same RBP, same minting). Pledge varies only slightly because the FIP-0081 Simple component dominates (≈97% of consensus pledge). The Baseline component is the only part affected by baseline growth, and it's small when baseline >> QAP.

**Recommendation:** Keep baseline growth at 100%/year. While it has minimal impact on pledge under current conditions, a growing baseline provides future headroom and reduces the Baseline pledge component.

---

## 4. Scenario Comparison (Year 1 — FIP-0081 corrected)

| Scenario | Reward/TiB/day | Pledge/32GiB | ROI% | Description |
|---|---|---|---|---|
| **Status Quo** | 0.003369 | 0.160 | 24.0% | Current system |
| **Fil+ Removed** | 0.028628 | 1.181 | 27.7% | VDWM 10→1, same trends |
| **Gradual 3yr** | 0.004773 | 0.217 | 25.1% | 10→1 over 3 years |
| **Gradual 1yr** | 0.028628 | 1.181 | 27.7% | 10→1 over 1 year |
| **Conservative** | 0.010561 | 0.449 | 26.8% | VDWM 10→3 + reserve burn |
| **Full Reform** | 0.027480 | 1.132 | 27.7% | VDWM→1, baseline 50%, burn |
| **Full Reform Optimistic** | 0.025494 | 1.032 | 28.2% | Same + RBP grows 10%/yr |

**Recommended: Gradual 1-year transition (10→1)** — achieves same end-state as immediate removal, but gives SPs time to adjust. By month 12, all sectors are equal.

*Note: ROI improvement is modest (~24% → ~28%) because FIP-0081's Simple pledge component scales with the sector's share of NetworkQAP — rewards and pledge increase together. The primary benefit is 8.5× higher absolute revenue per sector, making CC mining economically viable without datacap.*

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

## 6. Sensitivity Analysis (Parameter Sweep — 210 Combinations, FIP-0081)

### Most important finding:

**VDWM controls absolute revenue; ROI converges.** Under FIP-0081, the Simple pledge component ensures that pledge scales with share of NetworkQAP — so changing VDWM affects absolute reward per sector (8.5× for 10→1) but has limited impact on ROI (pledge moves proportionally).

### Best vs Worst at Year 5:

| | VDWM | RBP trend | BL growth | Reward/TiB | Pledge/32G | ROI |
|---|---|---|---|---|---|---|
| **Best ROI** | 1 | +10%/yr | 100% | 0.012754 | 0.741 | 19.6% |
| **Worst ROI** | 15 | +10%/yr | 0% | 0.001007 | 0.111 | 10.4% |

### VDWM=10 vs VDWM=1 (controlled comparison, RBP=-5%/yr, BL=100%):

| | VDWM=10 | VDWM=1 | Change |
|---|---|---|---|
| Reward/TiB | 0.002634 | 0.022378 | **+8.5x** |
| Pledge/32G | 0.181 | 1.526 | +8.4x |
| ROI | 16.6% | 16.7% | ~0% |

*At Year 5 with declining RBP, reward and pledge scale nearly identically — ROI converges regardless of VDWM. The difference is in absolute economics: each VDWM=1 sector earns 8.5× more FIL, making CC mining viable without datacap.*

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
- **Pledge per CC sector:** +6.5× (0.169 → 1.093 FIL) — FIP-0081 Simple component drives most of the increase
- **ROI:** ~23% → ~30% (modest improvement — reward and pledge scale together)

### Phase 2: Mining Reserve Burn
- Set `FIL_MiningReserveAlloc` to 0 (burn/send to f099)
- **Impact:** Removes 300M FIL inflation risk permanently
- **No effect on current economics** — reserve was never circulating

### What I am NOT proposing (and why):
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

$$\int_0^{\theta} b(x)\,dx = \int_0^{t} \min(b(x),\, R(x))\,dx$$

$R(x)$ is the **raw byte power** — the sum of sector sizes in bytes, regardless of quality multiplier. VDWM affects only QAP (quality-adjusted power), not RBP.

Therefore: changing VDWM leaves $R(x)$ unchanged $\Rightarrow$ cumulative sum unchanged $\Rightarrow$ $\theta(t)$ unchanged $\Rightarrow$ $M_B(t)$ unchanged $\Rightarrow$ $M(t)$ unchanged. $\blacksquare$

**Corollary:** The 10x multiplier is a pure redistribution mechanism. It taxes CC sectors to subsidize Fil+ sectors, with no net benefit to the network's minting trajectory.
