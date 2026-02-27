---
fip: "XXXX"
title: Restore Equal Sector Quality and Burn Mining Reserve
author: Reiers (@Reiers)
discussions-to: https://github.com/filecoin-project/FIPs/discussions/XXXX
status: Draft
type: Technical
category: Core
created: 2026-02-27
spec-sections:
  - section-systems.filecoin_mining.sector.sector-quality
  - section-systems.filecoin_token.token_allocation
  - section-algorithms.cryptoecon
---

# FIP-XXXX: Restore Equal Sector Quality and Burn Mining Reserve

## Simple Summary

Set the Verified Deal Weight Multiplier (VDWM) to 1x over a 12-month linear transition, making all sectors equal regardless of deal type, and permanently burn the 300M FIL mining reserve by sending it to `f099`.

## Abstract

The Filecoin Plus (Fil+) program introduced a 10x quality-adjusted power (QAP) multiplier for sectors containing verified deals (FIP-0003). After 5+ years of operation, the program has not achieved its intended goals: Raw Byte Power (RBP) peaked at ~19 EiB and has declined to 2.17 EiB, ~90% of verified data is estimated to be non-retrievable, and a permissioned notary layer controls block reward distribution.

This FIP proposes two changes:

1. **Reduce the `VERIFIED_DEAL_WEIGHT_MULTIPLIER` from 10 to 1** over a 12-month linear transition (approximately one change of −0.75 per month). After the transition, all sectors — committed capacity, regular deals, and verified deals — earn equal quality-adjusted power per raw byte.

2. **Set the mining reserve allocation to zero**, permanently removing 300M FIL of potential future inflation from the token supply by sending the reserve balance to the burn address `f099`.

Together, these changes remove two sources of centralized control (notary-gated rewards and discretionary token reserves) while preserving or improving storage provider economics.

## Change Motivation

### The 10x multiplier does not increase total block rewards

This is the foundational economic fact motivating this FIP.

The Filecoin minting model (specified in the [Block Reward Minting](https://spec.filecoin.io/#section-systems.filecoin_token.block_reward_minting) section of the protocol specification) defines two components of block reward issuance:

- **Simple minting:** $M_S(t) = M_{\infty S} \cdot (1 - e^{-\lambda t})$ — a function of elapsed time only.
- **Baseline minting:** $M_B(t) = M_{\infty B} \cdot (1 - e^{-\lambda\theta(t)})$ — where the effective network time $\theta(t)$ depends on the cumulative capped raw-byte power $\bar{R}_\Sigma(t)$.

Critically, the baseline function uses **Raw Byte Power (RBP)**, not Quality-Adjusted Power (QAP):

$$\bar{R}(t) := \min\bigl\{b(t),\; R(t)\bigr\}$$

where $R(t)$ is defined as "the instantaneous network raw-byte power (the total amount of bytes among all active sectors)" (spec §5.2.2). This is the sum of physical sector sizes, unaffected by quality multipliers.

**Therefore:** Changing the VDWM from 10 to 1 leaves $R(t)$ unchanged, $\bar{R}_\Sigma(t)$ unchanged, $\theta(t)$ unchanged, and total minted supply $M(t) = M_S(t) + M_B(t)$ unchanged.

The 10x multiplier is a **pure redistribution mechanism**. It does not increase the reward pool — it transfers rewards from CC sectors to Fil+ sectors through inflated QAP.

### Simulation confirms: identical issuance across all VDWM values

We validated this analytically and by numerical simulation. The simulation was implemented as a CUDA program ([source code](https://github.com/Reiers/super-fip-sim)) and executed on an NVIDIA RTX 5080 GPU, modeling 12 scenarios across 10-year forward projections from the current network state (epoch 5,796,404).

**Methodology:**

1. Computed cumulative capped raw-byte power `R̄_Σ` from genesis to the current epoch using 10 historical RBP data points interpolated linearly, stepping in daily (2,880-epoch) increments.
2. Derived effective network time `θ = (1/g) · ln(g · R̄_Σ / b_0 + 1)` per the spec formula.
3. Validated simple minting at the current epoch: `M_S = 155.46M FIL` (matches chain state within 1%).
4. Projected forward under each scenario, tracking daily issuance, per-sector rewards, pledge, and circulating supply.
5. Confirmed that changing VDWM does not alter the minting trajectory in any scenario.

**Current chain state used as simulation input** (source: [filfox.info API](https://filfox.info/api/v1/overview), epoch 5,796,404):

| Parameter | Value | Source |
|---|---|---|
| Raw Byte Power | 2.17 EiB | `totalRawBytePower` |
| Quality-Adjusted Power | 18.50 EiB | `totalQualityAdjPower` |
| Circulating Supply | 832.5M FIL | `circulatingSupply` |
| Daily Mined | 66,249 FIL | `dailyCoinsMined` |
| Active Miners | 923 | `activeMiners` |
| Baseline (computed) | 114.21 EiB | `b_0 · e^{g · t}` |

**Key result — daily issuance is invariant to VDWM:**

| Scenario | VDWM | Year 1 Issuance | Year 5 Issuance | Year 10 Issuance |
|---|---|---|---|---|
| Status Quo | 10 | 61,883 FIL/day | 39,400 FIL/day | 22,860 FIL/day |
| This FIP | 1 | 61,883 FIL/day | 39,400 FIL/day | 22,860 FIL/day |

The values are identical to 8 significant figures across the full 10-year projection.

### Per-sector economics improve substantially for honest miners

With VDWM=10, a 32 GiB CC sector competes against Fil+ sectors that hold 10x its apparent power. When the multiplier is removed, the same physical storage earns a proportionally larger share of the unchanged reward pool.

**Per 32 GiB CC sector, current epoch:**

| Metric | With Fil+ (VDWM=10) | Without Fil+ (VDWM=1) | Change |
|---|---|---|---|
| Daily reward | 0.000107 FIL | 0.000910 FIL | **+8.5×** |
| Storage pledge (20 days) | 0.00213 FIL | 0.01820 FIL | +8.5× |
| Consensus pledge | 0.06517 FIL | 0.06517 FIL | **unchanged** |
| **Total initial pledge** | **0.0673 FIL** | **0.0834 FIL** | +24% |
| Annual ROI on pledge | 58% | 399% | **+6.9×** |

The consensus pledge is unchanged because the denominator $\max\bigl(b(t),\, \text{QAP}(t)\bigr)$ evaluates to the baseline in both cases ($114.21 \text{ EiB} \gg 18.5 \text{ EiB} \gg 2.17 \text{ EiB}$). The storage pledge increases proportionally to the higher per-sector reward, but this is a direct function of the sector earning more.

**Net effect:** For every storage provider running committed capacity, revenue per unit of storage increases 8.5× while total pledge increases only 24%. ROI on pledge capital improves from 58% to 399%.

### The baseline gap is a structural problem

The baseline function was designed to grow at 100% per year from an initial value of 2.5 EiB. After 5.5 years:

| Metric | Value |
|---|---|
| Current baseline | 114.21 EiB |
| Current RBP | 2.17 EiB (**1.9% of baseline**) |
| Effective network time θ | 3.34 years (vs 5.5 years actual) |
| Baseline minted (of 770M allocation) | 246M FIL (32%) |
| Baseline rewards effectively unreachable | ~524M FIL (68%) |

The network has never exceeded the baseline. Peak RBP was ~19 EiB in mid-2022; the baseline at that time was already ~35 EiB. The 10x multiplier was intended to help the network approach the baseline by incentivizing data storage, but QAP (not RBP) is what the multiplier inflates, and baseline minting depends on RBP.

The baseline continues to grow at 100%/year. In 5 more years it will reach ~3,656 EiB. In 10 years: ~116,954 EiB. The gap between actual storage and the baseline is widening exponentially.

Our simulation confirmed that **slowing the baseline growth rate does not improve SP economics** — it actually *increases* the consensus pledge because the denominator $\max(\text{baseline},\, \text{QAP})$ decreases. We therefore propose leaving the baseline growth rate unchanged.

### Fil+ has failed its stated goals

The Fil+ program (FIP-0003) was designed to "incentivize useful storage" via a quality multiplier for verified data. The program's outcomes:

1. **RBP declined**, not increased: from 19 EiB peak to 2.17 EiB current.
2. **~90% of Fil+ data is non-retrievable** (per community audit reports cited in [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774)).
3. **DataCap is traded on black markets** at ~$14,300/PiB.
4. **A permissioned notary layer** controls which storage providers earn enhanced rewards, contradicting Filecoin's decentralization mission.
5. **Block rewards per TiB declined 3× faster** after Fil+ adoption than before (from −11.7% to −42.2% over comparable 6-month periods).
6. **Storage providers pay clients** to store data (negative storage pricing) — an inverted economic signal.

This FIP is not the first to identify these issues. FIP-0080 (Phasing Out Fil+, Discussion #774, 358 comments) has been in Draft status since August 2023 — over 2.5 years — with broad community support but no path to ratification. This FIP provides the quantitative economic analysis and transition mechanism that FIP-0080's authors and supporters have called for.

### Mining reserve is unused and unnecessary

The 300M FIL mining reserve (15% of `FIL_BASE`) was allocated "for funding mining to support growth of the Filecoin Economy, whose future usage will be decided by the Filecoin community." After 5+ years, no mechanism for distribution has been ratified, no tokens have been released, and FIP-0093 (Set Mining Reserve to Zero) has been stalled in review since July 2024 despite editor approval.

The reserve represents unrealized inflation potential. Burning it:
- Permanently removes 300M FIL of potential future supply
- Has zero effect on current circulating supply (the reserve is not circulating)
- Has zero effect on daily issuance (the reserve is separate from storage mining allocation)
- Signals credible commitment to predictable monetary policy

## Specification

### 1. VDWM Transition

Introduce a new constant and modify an existing one in the storage miner actor:

```rust
/// Epoch at which the VDWM transition begins (set to upgrade activation epoch)
pub const VDWM_TRANSITION_START: ChainEpoch = UPGRADE_EPOCH; // set at deployment

/// Duration of the VDWM transition in epochs (12 months = 365 * 2880 = 1,051,200 epochs)
pub const VDWM_TRANSITION_DURATION: ChainEpoch = 1_051_200;

/// Target VDWM after transition completes
pub const VDWM_TRANSITION_TARGET: BigInt = BigInt::from(10); // == QBM == DWM
```

Modify the quality multiplier calculation to interpolate during the transition:

```rust
/// Returns the verified deal weight multiplier code value at the given epoch.
/// This replaces the static `VERIFIED_DEAL_WEIGHT_MULTIPLIER` constant (100).
/// The effective quality ratio is this value divided by QUALITY_BASE_MULTIPLIER (10).
///
/// Pre-transition: returns 100  (effective 10×)
/// Post-transition: returns 10  (effective 1×, equal to QUALITY_BASE_MULTIPLIER)
/// During transition: linearly interpolates from 100 to 10
pub fn verified_deal_weight_multiplier_at(epoch: ChainEpoch) -> BigInt {
    if epoch < VDWM_TRANSITION_START {
        return BigInt::from(100); // Pre-transition: original code value
    }
    let elapsed = epoch - VDWM_TRANSITION_START;
    if elapsed >= VDWM_TRANSITION_DURATION {
        return VDWM_TRANSITION_TARGET; // Post-transition: equals QBM (10)
    }
    // Linear interpolation: 100 → 10 over transition period
    // multiplier = 100 - 90 * (elapsed / duration)
    // Using integer math: multiplier = (100 * duration - 90 * elapsed) / duration
    let duration = BigInt::from(VDWM_TRANSITION_DURATION);
    let numer = BigInt::from(100) * &duration - BigInt::from(90) * BigInt::from(elapsed);
    // Floor division, minimum 10 (= QUALITY_BASE_MULTIPLIER)
    std::cmp::max(numer / duration, BigInt::from(10))
}
```

The quality multiplier is applied at:
- **Sector activation** (`ProveCommitSectors3`, `ProveCommitSectorsNI`): Quality calculated using `verified_deal_weight_multiplier_at(activation_epoch)`.
- **Sector extension** (`ExtendSectorExpiration2`): Quality recalculated using `verified_deal_weight_multiplier_at(extension_epoch)`.
- **Replica update** (`ProveReplicaUpdates3`): Quality recalculated using `verified_deal_weight_multiplier_at(update_epoch)`.

**Existing sectors** retain their original quality until they are extended, updated, or expire. No retroactive quality adjustment is applied. This is the **grandfathering approach**, chosen because:
- Zero additional gas cost (no CronTick changes).
- Existing sectors' pledge calculations were made under VDWM=10; retroactive changes would alter the economic contract under which those sectors were committed.
- Old sectors will naturally cycle out as they reach maximum lifetime (3.5 years per FIP-0052).

**WindowPoSt and power table updates:**
The power table tracks QAP per miner. When a sector's quality changes (via extension or update), the power table is updated accordingly. WindowPoSt itself does not depend on the quality multiplier — it proves existence of sealed data regardless of deal type.

### 2. Mining Reserve Burn

At the upgrade epoch, execute a one-time transfer of the mining reserve balance to the burn address:

```go
// In the system actor upgrade logic:
reserveActor := builtin.ReserveActorAddr  // f090
burnActor := builtin.BurntFundsActorAddr  // f099
balance := getActorBalance(reserveActor)
transferFunds(reserveActor, burnActor, balance)
```

After this transfer:
- `FIL_MiningReserveAlloc` effectively becomes 0.
- The tokens are permanently unspendable (same burn mechanism as gas fees).
- No new governance mechanism is needed — the reserve simply ceases to exist.

### 3. FIP-0003 Status Update

FIP-0003 (Filecoin Plus Principles) currently has status `Active`. Upon completion of the VDWM transition (12 months after activation), FIP-0003 should be updated to status `Superseded` by this FIP, as the quality multiplier it introduced will no longer have differential effect.

## Design Rationale

### Why a 12-month linear transition?

Simulation of both immediate (VDWM=10→1 at activation) and gradual (10→1 over 12 months) transitions shows:

| | Year 1 Reward/TiB | Year 1 Pledge/32G | Year 1 ROI |
|---|---|---|---|
| Immediate removal | 0.0286 FIL/day | 0.052 FIL | 626% |
| 12-month gradual | 0.0286 FIL/day (at completion) | 0.052 FIL (at completion) | 626% (at completion) |
| 3-year gradual | 0.0048 FIL/day (at year 1) | 0.037 FIL | 146% |

The 12-month transition achieves the same end-state as immediate removal while providing:
1. Time for SPs to adjust operational strategies.
2. Gradual unwinding of Fil+ data positions.
3. Smoother power table transitions for consensus stability.

A 3-year transition extends the period of suboptimal economics unnecessarily.

### Why not slow the baseline growth?

Our simulation tested baseline growth rates from 0% to 100%/year, with VDWM=1 and stable RBP:

| Baseline Growth | Reward/TiB (Y5) | Pledge/32GiB (Y5) | ROI (Y5) |
|---|---|---|---|
| 0% (freeze) | 0.01824 | 0.0856 | 243% |
| 25%/year | 0.01824 | 0.0357 | 583% |
| 50%/year | 0.01824 | 0.0212 | 984% |
| 100%/year (current) | 0.01824 | 0.0137 | 1,518% |

**Rewards are identical** across all growth rates (because $\text{RBP} \ll \text{baseline}$ in all cases, so $\bar{R} = \text{RBP}$ regardless). But pledge **increases** when baseline growth slows, because the consensus pledge formula:

$$\text{AdditionalIP} = 0.30 \times C(t) \times \frac{\text{SectorQAP}}{\max\bigl(\text{Baseline}(t),\; \text{NetworkQAP}(t)\bigr)}$$

produces a larger result when the baseline is smaller.

Counterintuitively, the growing baseline *helps* SP economics by keeping the denominator large and pledge low. We therefore leave the baseline growth rate unchanged.

### Why combine VDWM reduction with mining reserve burn?

These two changes are economically independent:
- VDWM reduction: changes reward redistribution, not total issuance.
- Reserve burn: changes potential future supply, not current issuance.

Combining them in a single FIP:
1. Addresses the two most prominent community governance concerns (Discussion #774 with 358 comments, and PR #1039 with 14+ months of stalled review) in one coherent proposal.
2. Demonstrates that fundamental economic reform can be achieved with minimal protocol disruption.
3. Reduces the number of separate consensus upgrades needed.

### Why grandfathering instead of retroactive quality adjustment?

**Gas analysis (Phase 2):** Retroactively adjusting all existing sectors' quality would require updating the power table for every active sector at the transition step. With ~2.17 EiB across 923 miners, this involves potentially millions of state updates, which would exceed the block gas limit of $10^{10}$ gas.

**Economic fairness:** Storage providers committed pledge under VDWM=10 rules. Retroactively reducing their quality without reducing their pledge would change the economic contract they entered.

**Natural cycle-out:** With maximum sector lifetime of 3.5 years (FIP-0052), all pre-transition sectors will expire within 3.5 years of activation. The overlap period where old 10x sectors coexist with new 1x sectors is bounded and diminishing.

## Backwards Compatibility

This proposal changes the behavior of the built-in storage miner actor and requires a network upgrade.

**State migration:** Minimal. No structural changes to `SectorOnChainInfo` or `Deadline` are needed. The quality multiplier is a runtime parameter used during sector activation, extension, and update — it does not require migration of existing sector state.

**API compatibility:** The `StateMinerSectors`, `StateSectorGetInfo`, and related APIs will return the existing quality values for grandfathered sectors and new quality values for sectors activated/extended after the upgrade. Clients that compute QAP should use the `verified_deal_weight_multiplier(epoch)` function for forward calculations.

**Miner operations:** Storage providers do not need to change their sealing pipeline. The quality multiplier is applied automatically by the miner actor. SPs with existing Fil+ workflows can continue making verified deals — the deals will simply not receive enhanced quality.

## Test Cases

### Unit Tests

1. **Multiplier interpolation** (code values, effective ratio = code_value / QBM):
   - At `TRANSITION_START`: returns 100 (effective 10×)
   - At `TRANSITION_START + DURATION/2`: returns 55 (effective 5.5×, ±0.5 from integer math)
   - At `TRANSITION_START + DURATION`: returns 10 (effective 1×)
   - At `TRANSITION_START + DURATION + 1`: returns 10 (effective 1×)
   - Before `TRANSITION_START`: returns 100 (effective 10×)

2. **Sector activation during transition:**
   - CC sector at any epoch: QAP = RBP (always 1×, unaffected by VDWM)
   - Fil+ sector at transition midpoint: QAP = RBP × 5.5 (interpolated ~5.5×)
   - Fil+ sector after transition: QAP = RBP (effective 1×)

3. **Sector extension across transition:**
   - Sector originally activated with VDWM=10, extended after transition completes: new QAP = RBP × 1

4. **Mining reserve burn:**
   - Reserve actor balance → 0 after upgrade
   - Burn actor balance increased by former reserve balance
   - Total supply decreased by former reserve balance

### Integration Tests

5. **WindowPoSt unaffected:** Prove that WindowPoSt succeeds identically for sectors regardless of when they were activated relative to the transition.

6. **Block reward distribution:** Over a simulated transition period, verify that total block rewards match the expected minting curve (M_S + M_B) within rounding tolerance.

7. **Pledge calculation:** Verify that initial pledge for new sectors uses the interpolated VDWM at activation epoch.

## Security Considerations

A comprehensive formal security analysis accompanies this FIP (see `security-analysis.md`). Five attack vectors were analyzed with quantitative bounds. Summary:

### Consensus security improves

The minimum physical cost of a 51% consensus attack **increases by 17.6%** after Daybreak:

| Metric | Current (VDWM=10) | Post-Daybreak (VDWM=1) |
|---|---|---|
| Minimum physical storage for 51% | 0.944 EiB (via datacap) | 1.107 EiB |
| Minimum pledge capital for 51% | ~$3.9M | ~$4.5M |
| Virtual (non-physical) power | 8.5 EiB (56% of QAP) | 0 |

Today, an attacker with access to datacap can acquire 51% of consensus power with only 0.944 EiB of physical storage (the 10× multiplier supplies the rest virtually). After Daybreak, 100% of consensus power is physically backed, requiring 1.107 EiB — a strictly higher barrier.

F3 fast finality (FIP-0086) provides an additional ~900× safety margin by reducing the finality window from 7.5 hours to ~30 seconds, making QAP-based consensus attacks impractical regardless of VDWM.

### Flash power attacks are economically irrational

An attacker onboarding CC sectors during the transition and terminating to extract rewards faces:

- **25-day minimum break-even** on the termination fee alone (FIP-0098: 8.5% of initial pledge)
- **75% of rewards locked** in 180-day vesting (unvested rewards forfeit on termination)
- **Scaling penalty**: adding power dilutes the attacker's own per-unit reward (reward ∝ 1/(P+A))
- **Pledge lock**: 20 days of expected reward locked as storage pledge, plus consensus pledge

A flash power attack requires a minimum 25-day capital commitment for zero net profit (excluding opportunity cost). This is not a viable attack strategy.

### Quality arbitrage is bounded and diminishing

Under the grandfathering approach, existing Fil+ sectors retain their 10× quality until expiry. The maximum "grandfathered premium" is bounded by:
```
Premium ≤ 9 × CC_reward_rate × remaining_sector_days → 0 as sectors expire
```

All grandfathered sectors expire within 3.5 years (FIP-0052 max lifetime). The premium represents the cost of a smooth transition — it is the gradual elimination of existing redistribution, not new value creation. Total network issuance is unchanged.

### Mining reserve burn security

The reserve burn is a one-time state transfer with no ongoing protocol implications. The tokens are transferred to the burn address `f099`, which is the same mechanism used for gas fee burns — well-tested and irreversible. The reserve burn and VDWM change are mathematically independent: no economic formula contains both variables.

### No new attack vectors introduced

Daybreak leverages existing security mechanisms (pledge, vesting, termination fees, F3 finality) without requiring new security parameters. All five analyzed attack vectors (flash power, quality arbitrage, notary front-running, reserve interaction, consensus security) either have negative expected return or show improved security posture compared to the status quo.

## Incentive Considerations

### Who benefits

- **CC storage providers:** 8.5× increase in per-sector revenue with only 24% increase in pledge. This is the largest economic improvement for honest miners in Filecoin's history.
- **Small and new SPs:** No longer need to navigate the notary system to be competitive. Equal access to rewards based on physical storage contribution.
- **Token holders:** Mining reserve burn removes 300M FIL of potential inflation. Reduced gaming activity improves network legitimacy.
- **Real data clients:** Storage pricing becomes market-driven rather than subsidy-driven. Clients who genuinely value Filecoin storage will pay fair market rates.

### Who is affected negatively

- **Fil+ gaming operations:** SPs whose economic model depends on 10x multiplier from non-retrievable data will see rewards decrease to 1× levels. This is intentional — these operations extract network value without providing storage utility.
- **Notary ecosystem:** DataCap and notary roles become economically irrelevant. Existing notary infrastructure can transition to verification/reputation services on the FVM.
- **Large verified deal SPs (legitimate):** SPs storing genuine verified data will see per-sector rewards decrease from 10× to 1× multiplied levels. However, their physical storage still earns 1× rewards, and they can charge clients market rates for storage services.

### Transition economics

During the 12-month transition:
- Month 1: VDWM ≈ 9.25 — minimal change from status quo
- Month 6: VDWM ≈ 5.5 — CC sector reward approximately doubles
- Month 12: VDWM = 1.0 — CC sector reward reaches 8.5× of pre-transition level

This gradual change allows market participants to adjust positions. SPs dependent on Fil+ subsidies have 12 months to transition to alternative business models (market-rate storage, FVM-based incentive contracts, FOC/PDP warm storage services).

## Product Considerations

### Impact on Filecoin storage products

The Filecoin Onchain Cloud (FOC) ecosystem — including PDP (Provable Data Possession), FilecoinPay, FWSS (Filecoin Warm Storage Service), and Synapse SDK — operates independently of the Fil+ quality multiplier. These services provide storage verification and payment rails via FVM smart contracts. This FIP does not affect their operation.

### Future deal incentive mechanisms

With VDWM=1 at the protocol level, deal incentive mechanisms move to the application layer:
- FVM smart contracts can implement custom incentive structures (e.g., storage bounties, retrieval guarantees).
- The FOC product stack provides built-in streaming payment rails for storage services.
- DataDAO and data market protocols can offer deal-specific rewards without requiring protocol-level quality multipliers.

This aligns with the principle of a minimal, neutral base layer supporting diverse application-layer innovation.

## Implementation

### builtin-actors changes

1. Modify `actors/miner/src/policy.rs`:
   - Add `VDWM_TRANSITION_START`, `VDWM_TRANSITION_DURATION`, `VDWM_TRANSITION_TARGET` constants.
   - Add `verified_deal_weight_multiplier_at(epoch)` function (interpolates code value 100→10).
   - Update `quality_for_weight()`: replace `&*VERIFIED_DEAL_WEIGHT_MULTIPLIER` with `verified_deal_weight_multiplier_at(epoch)` (requires adding `epoch` parameter).
   - Update `qa_power_max()`: use `VDWM_TRANSITION_TARGET` (post-transition max).
   - Gas impact: < 0.01% per affected operation (see Phase 2 gas benchmarking).

2. Modify system actor upgrade logic:
   - Add reserve-to-burn transfer at upgrade epoch.

### Implementation tracking

| Repository | PR | Status |
|---|---|---|
| `filecoin-project/builtin-actors` | TBD | Not started |
| `filecoin-project/ref-fvm` | N/A | No changes needed |
| `filecoin-project/lotus` | TBD | Not started |
| `filecoin-project/venus` | TBD | Not started |
| `ChainSafe/forest` | TBD | Not started |
| `filecoin-project/specs` | TBD | Not started |

### Simulation code

The economic simulation used to generate the data in this FIP is publicly available:
- **Repository:** [github.com/Reiers/super-fip-sim](https://github.com/Reiers/super-fip-sim)
- **Language:** CUDA C++ (validated on NVIDIA RTX 5080, Blackwell architecture)
- **Data:** 12 scenario CSVs (3,650 daily data points each) + 210-point parameter sweep
- **Reproducibility:** Build with `make` (requires CUDA toolkit 13.0+), run with `make run`

All economic claims in this FIP can be independently verified by running the simulation or by direct computation from the Filecoin spec formulas cited above.

## References

- [Filecoin Spec: Block Reward Minting](https://spec.filecoin.io/#section-systems.filecoin_token.block_reward_minting) — Defines M_S, M_B, θ, R̄
- [Filecoin Spec: Sector Quality](https://spec.filecoin.io/#section-systems.filecoin_mining.sector.sector-quality) — Defines QAP, VDWM, DWM, QBM
- [Filecoin Spec: Miner Collaterals](https://spec.filecoin.io/#section-systems.filecoin_mining.miner_collaterals) — Defines initial pledge formula
- [Filecoin Spec: Token Allocation](https://spec.filecoin.io/#section-systems.filecoin_token.token_allocation) — Defines mining reserve
- [FIP-0003: Filecoin Plus Principles](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0003.md) — Introduced the 10x quality multiplier
- [FIP-0080: Phasing Out Fil+ (Discussion #774)](https://github.com/filecoin-project/FIPs/discussions/774) — 358 comments, 2.5 years in Draft
- [FIP-0093: Set Mining Reserve to Zero (PR #1039)](https://github.com/filecoin-project/FIPs/pull/1039) — 14+ months stalled
- [FIP-0052: Increase Max Sector Commitment to 3.5 Years](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0052.md) — Sector lifetime bound
- [FIP-0086: Fast Finality (F3)](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0086.md) — 30-second finality
- [FIP-0098: Simple Termination Fee](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0098.md) — 8.5% of initial pledge
- [FIP-0100: Per-Sector Fee](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0100.md) — Daily fee mechanism
- [CryptoEconLab: Resilience of the Filecoin Network](https://medium.com/cryptoeconlab/resilience-of-the-filecoin-network-d7861ee9986a)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
