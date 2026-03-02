---
fip: "XXXX"
title: "Daybreak: Restore Equal Sector Quality and Burn Mining Reserve"
author: Reiers (@Reiers)
discussions-to: https://github.com/filecoin-project/FIPs/discussions/1238
status: Draft
type: Technical
category: Core
created: 2026-02-27
requires: FIP-0052, FIP-0086, FIP-0098
spec-sections:
  - section-systems.filecoin_mining.sector.sector-quality
  - section-systems.filecoin_token.token_allocation
  - section-algorithms.cryptoecon
---

# FIP-XXXX: Daybreak — Restore Equal Sector Quality and Burn Mining Reserve

## Simple Summary

Gradually reduce the Verified Deal Weight Multiplier (VDWM) from 10× to 1× over 12 months, so all sectors earn equal rewards regardless of deal type. Simultaneously, burn the ~283M FIL mining reserve by transferring it to the burn address `f099`.

## Abstract

FIP-0003 (Filecoin Plus, 2020) introduced a 10× quality-adjusted power (QAP) multiplier for sectors containing verified deals. After five years of operation, the program's outcomes have diverged significantly from its intended goals: Raw Byte Power (RBP) peaked at ~17 EiB in mid-2022 and has since declined to 2.17 EiB; independent community analyses estimate that a substantial portion of verified data may not be retrievable; and a permissioned notary layer has become a gatekeeper for block reward distribution.

This FIP proposes two changes:

1. **Reduce `VERIFIED_DEAL_WEIGHT_MULTIPLIER` from 10× to 1×** over a 12-month linear transition. After the transition, all sectors — committed capacity (CC), regular deals, and verified deals — earn equal quality-adjusted power per raw byte.

2. **Burn the mining reserve** (~283M FIL as of epoch 5,796,404) by transferring the balance of the reserve actor `f090` to the burn address `f099`.

These changes remove two sources of centralized influence — notary-gated reward distribution and a discretionary token reserve — while preserving or improving storage provider economics. Total block reward issuance is mathematically unchanged.

## Change Motivation

### Background: Five Years of Debate

The question of whether the 10× quality multiplier helps or harms Filecoin is not new. This FIP builds on years of community analysis and prior proposals:

| Date | Event | Status |
|------|-------|--------|
| Oct 2020 | **FIP-0003** introduces Fil+ and the 10× VDWM | Active |
| Apr 2022 | **FIP-0036** (Sector Duration Multiplier) proposes alternative incentive mechanism | Rejected — 1,000+ comments, strong SP opposition |
| Jan 2023 | **FIP-0056** (SDM v2) attempts to revive duration-based multiplier | Rejected — same opposition |
| Aug 2023 | **FIP-0080** (Phasing Out Fil+) proposes setting VDWM to 1× for new sectors | Draft — 358+ comments, 2.5 years without advancing |
| Oct 2023 | **FIP-0078** (Remove DataCap and QA) proposes phasing out the Fil+ program entirely | Draft — stalled |
| Jul 2024 | **FIP-0093** (Set Mining Reserve to Zero) proposes burning the reserve | Draft — ~20 months stalled despite editor approval |
| Feb 2026 | **This FIP** provides quantitative analysis, transition mechanism, formal security proofs, and gas benchmarking | — |

The prior proposals (particularly FIP-0080) identified the correct problems and proposed the right direction. What they lacked — and what this FIP provides — is the quantitative economic foundation to move from discussion to action: a simulation validated against the protocol specification, gas impact analysis against the builtin-actors source code, a formal security analysis covering five attack vectors, and a fully specified transition mechanism.

This FIP is intended to complement and build upon the work of FIP-0080's authors (Fatman13, ArthurWang1255, stuberman, Eliovp, dcasem, The-Wayvy) and FIP-0093's author (dcasem), whose community advocacy over multiple years laid the groundwork for this proposal.

### The 10× multiplier does not increase total block rewards

This is the foundational economic fact.

The Filecoin minting model (defined in the [Block Reward Minting](https://spec.filecoin.io/#section-systems.filecoin_token.block_reward_minting) section of the protocol specification) has two components:

- **Simple minting**: $M_S(t) = M_\infty^S \cdot (1 - e^{-\lambda t})$ — a function of elapsed time only.
- **Baseline minting**: $M_B(t) = M_\infty^B \cdot (1 - e^{-\lambda \theta(t)})$ — where effective network time $\theta(t)$ depends on cumulative capped **raw-byte** power.

The critical definition from the spec:

> $\bar{R}(t) := \min\{b(t), R(t)\}$ where $R(t)$ is "the instantaneous network raw-byte power (the total amount of bytes among all active sectors)."

**$R(t)$ is the sum of physical sector sizes.** It is unaffected by quality multipliers. Changing the VDWM from 10 to 1 leaves $R(t)$ unchanged → $\bar{R}_\Sigma(t)$ unchanged → $\theta(t)$ unchanged → total minted supply $M(t) = M_S(t) + M_B(t)$ unchanged.

**The 10× multiplier is a pure redistribution mechanism.** It does not grow the reward pool — it transfers rewards from CC sectors to Fil+ sectors through inflated QAP.

### Simulation confirms identical issuance

This result was validated analytically and by numerical simulation. The simulation models 12 scenarios across 10-year forward projections from the current network state.

- **Source code**: [github.com/Reiers/fip-daybreak/sim](https://github.com/Reiers/fip-daybreak/tree/main/sim) (CUDA C++)
- **Hardware**: NVIDIA RTX 5080 GPU (Blackwell architecture)
- **Methodology**: Computed cumulative capped RBP from genesis using 10 historical data points, derived $\theta(t)$ per spec formula, projected forward under each scenario.
- **Full dataset**: 12 scenarios × 3,650 daily data points + 210-parameter sweep = 44,850 data points

**Chain state at epoch 5,796,404** (source: [filfox.info/api/v1/overview](https://filfox.info/api/v1/overview)):

| Parameter | Value | Source |
|---|---|---|
| Raw Byte Power (RBP) | 2.17 EiB | Filfox API: `totalRawBytePower` |
| Quality-Adjusted Power (QAP) | 18.5 EiB | Filfox API: `totalQualityAdjPower` |
| QAP / RBP ratio | 8.51× | Derived |
| Circulating Supply | 832.5M FIL | Filfox API: `circulatingSupply` |
| Daily Mined | 66,249 FIL | Filfox API: `dailyCoinsMined` |
| Baseline (computed) | ~114.5 EiB | $b_0 \cdot e^{g \cdot t}$, $b_0$ = 2,888,888,880,000,000,000 bytes |
| Active Miners | 923 | Filfox API: `activeMiners` |
| Mining Reserve (f090) | 282.9M FIL | Filfox API: address balance |

**Key result — daily issuance is invariant to VDWM:**

| Scenario | VDWM | At Year 1 | At Year 5 | At Year 10 |
|---|---|---|---|---|
| Status Quo | 10× | 61,883 FIL/day | 39,400 FIL/day | 22,860 FIL/day |
| This FIP | 1× | 61,883 FIL/day | 39,400 FIL/day | 22,860 FIL/day |

Identical to 8 significant figures across the full 10-year projection. **Not one additional FIL is minted or withheld by this change.**

### Per-sector economics improve substantially

With VDWM=10, a CC sector competes against Fil+ sectors holding 10× its apparent power. When the multiplier is removed, the same physical storage earns a proportionally larger share of the unchanged reward pool.

**Per 32 GiB CC sector at epoch 5,796,404:**

*Note: Pledge calculations use the FIP-0081 formula (deployed NV24), which splits consensus pledge into a Simple component (30% weight, scales with sector's share of NetworkQAP) and a Baseline component (70% weight, scales with sector's share of max(Baseline, NetworkQAP)). The gamma ramp is complete (γ=0.7).*

| Metric | Current (VDWM=10) | After Daybreak (VDWM=1) | Change |
|---|---|---|---|
| Daily reward | 0.000107 FIL | 0.000910 FIL | **+8.5×** |
| Storage pledge (20 days) | 0.00213 FIL | 0.01820 FIL | +8.5× |
| Consensus pledge (simple) | 0.1207 FIL | 1.029 FIL | +8.5× |
| Consensus pledge (baseline) | 0.0455 FIL | 0.0455 FIL | unchanged |
| **Total initial pledge** | **0.169 FIL** | **1.093 FIL** | +6.5× |
| Annual ROI on pledge | ~23% | ~30% | **+1.3×** |

Under FIP-0081, the consensus pledge Simple component scales with the sector's share of NetworkQAP — when the multiplier is removed, NetworkQAP drops from 18.5 EiB to 2.17 EiB, so each sector's share (and thus its Simple pledge) increases proportionally to its reward increase. The Baseline component is unchanged because $\max(Baseline, QAP)$ evaluates to the baseline in both cases (114.5 EiB >> 18.5 EiB >> 2.17 EiB).

**Net effect**: Revenue per unit of physical storage increases 8.5×. Pledge also increases (driven by the Simple component), but ROI on pledged capital still improves from ~23% to ~30%. The barrier to entry remains dramatically lower in absolute terms — a CC sector becomes immediately profitable without requiring datacap relationships.

### The baseline gap is now structural

The baseline function grows at 100% per year from an initial value of ~2.5 EiB. The network exceeded the baseline from April 2021 through early 2023 — at peak (August 2022), RBP reached ~17 EiB against a baseline of ~10 EiB. During this period, baseline minting operated at full rate.

Since mid-2023, RBP has fallen far below the baseline and the gap widens exponentially:

| Metric | Value |
|---|---|
| Current baseline | ~114.5 EiB |
| Current RBP | 2.17 EiB (**1.9% of baseline**) |
| Historical peak RBP | ~17 EiB (August 2022) |
| Effective network time $\theta$ | ~3.34 years (vs 5.5 years actual) |
| Baseline minted (of 770M allocation) | ~246M FIL (32%) |
| Baseline rewards currently deferred | ~524M FIL (68%) |

The baseline now stands at ~114.5 EiB — nearly 7× the historical peak RBP and 53× the current RBP. Even aggressive growth scenarios cannot close this gap. The 10× multiplier was intended to help the network approach the baseline by incentivizing data storage, but the multiplier inflates QAP — and baseline minting depends on RBP.

Our simulation tested baseline growth rates from 0% to 100%/year. **Slowing the baseline growth does not improve SP economics** — it actually increases consensus pledge because the denominator $\max(Baseline, QAP)$ shrinks. We therefore propose leaving the baseline growth rate unchanged.

### Fil+ outcomes have diverged from intent

FIP-0003 was designed to "incentivize useful storage" via a quality multiplier for verified data. After five years of operation:

1. **RBP has declined**, not increased — from a peak of ~17 EiB (August 2022) to 2.17 EiB today.
2. **Independent community analyses** report significant concerns about data retrievability for Fil+ sectors (see [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774) and linked audit reports).
3. **A permissioned notary layer** determines which storage providers earn enhanced rewards, creating centralization pressure that is in tension with Filecoin's [stated mission](https://github.com/filecoin-project/FIPs/blob/master/mission.md) of decentralization.
4. **Block rewards per TiB have declined significantly** after Fil+ adoption, as the subsidy creates a competitive dynamic where "when everyone gets 10×, nobody does."
5. **Storage economics have inverted** — storage providers in some cases pay clients to store data, rather than the other way around.

These outcomes are well-documented in the 358-comment discussion on FIP-0080 ([Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774)). This FIP does not seek to assign blame — the Fil+ program was a reasonable experiment that did not produce the intended results. The economic data now provides a clear basis for course correction.

### Mining reserve has no distribution mechanism

The mining reserve was allocated 300M FIL at genesis (15% of `FIL_BASE`) as a reserve "for funding mining to support growth of the Filecoin Economy, whose future usage will be decided by the Filecoin community."

The current balance of `f090` is **~282.9M FIL** (some tokens were transferred in early network operations). After 5+ years, no mechanism for distribution has been ratified, and FIP-0093 has been in review for approximately 20 months.

Burning the reserve:
- Permanently removes ~283M FIL of potential future supply inflation
- Has zero effect on current circulating supply (the reserve is not circulating)
- Has zero effect on daily block reward issuance (the reserve is separate from the storage mining allocation)
- Provides a credible commitment to predictable monetary policy

## Specification

### 1. VDWM Transition

Introduce new constants and a function in the storage miner actor (`actors/miner/src/policy.rs` in [builtin-actors](https://github.com/filecoin-project/builtin-actors)):

```rust
/// Epoch at which the VDWM transition begins (set to network upgrade activation epoch).
pub const VDWM_TRANSITION_START: ChainEpoch = UPGRADE_EPOCH; // set at deployment

/// Duration of the VDWM transition: 12 months = 365 days × 2,880 epochs/day = 1,051,200 epochs.
pub const VDWM_TRANSITION_DURATION: ChainEpoch = 1_051_200;

/// Target VDWM code value after transition (equals QUALITY_BASE_MULTIPLIER → effective 1×).
pub const VDWM_TRANSITION_TARGET: BigInt = BigInt::from(10);
```

Replace the static `VERIFIED_DEAL_WEIGHT_MULTIPLIER` constant with an epoch-aware function:

```rust
/// Returns the verified deal weight multiplier code value at the given epoch.
///
/// Context: In builtin-actors, quality multipliers are expressed as code values
/// that are divided by QUALITY_BASE_MULTIPLIER (10) to produce the effective ratio.
/// The current VERIFIED_DEAL_WEIGHT_MULTIPLIER is 100 (code value), giving an
/// effective ratio of 100/10 = 10×.
///
/// This function interpolates: 100 → 10 (code values) = 10× → 1× (effective).
///
/// Pre-transition:    returns 100  (effective 10×)
/// During transition: linearly interpolates from 100 to 10
/// Post-transition:   returns 10   (effective 1×, equal to QUALITY_BASE_MULTIPLIER)
pub fn verified_deal_weight_multiplier_at(epoch: ChainEpoch) -> BigInt {
    if epoch < VDWM_TRANSITION_START {
        return BigInt::from(100); // Original code value
    }
    let elapsed = epoch - VDWM_TRANSITION_START;
    if elapsed >= VDWM_TRANSITION_DURATION {
        return VDWM_TRANSITION_TARGET; // 10 (code value) = 1× effective
    }
    // Linear interpolation: 100 → 10 over the transition period.
    // multiplier = 100 - 90 × (elapsed / duration)
    // Using integer arithmetic to avoid floating point:
    let duration = BigInt::from(VDWM_TRANSITION_DURATION);
    let numer = BigInt::from(100) * &duration - BigInt::from(90) * BigInt::from(elapsed);
    std::cmp::max(numer / duration, BigInt::from(10))
}
```

**Call sites to modify** (in `actors/miner/src/policy.rs`):

```rust
// In quality_for_weight(): replace static constant with epoch-aware call.
// Before:
//   let weighted_verified = verified_weight * &*VERIFIED_DEAL_WEIGHT_MULTIPLIER;
// After:
let weighted_verified = verified_weight * verified_deal_weight_multiplier_at(epoch);
```

The `epoch` parameter must be threaded through from the activation, extension, or update context. The two primary call sites are:
- `quality_for_weight()` — used during sector activation, extension, and replica update
- `qa_power_max()` — used for maximum power calculations (use `VDWM_TRANSITION_TARGET` post-transition)

**When quality is recalculated:**
- **Sector activation** (`ProveCommitSectors3`, `ProveCommitSectorsNI`): Uses `verified_deal_weight_multiplier_at(activation_epoch)`.
- **Sector extension** (`ExtendSectorExpiration2`): Recalculated using `verified_deal_weight_multiplier_at(extension_epoch)`.
- **Replica update** (`ProveReplicaUpdates3`): Recalculated using `verified_deal_weight_multiplier_at(update_epoch)`.

**Grandfathering:** Existing sectors retain their original quality until they are extended, updated, or expire. No retroactive quality adjustment is applied. This approach was chosen because:
- Zero additional gas (no CronTick changes, no sector iteration at migration).
- Respects the economic terms under which existing sectors were committed.
- All pre-transition sectors expire within 3.5 years (FIP-0052 max lifetime).

**WindowPoSt:** Unaffected. WindowPoSt proves existence of sealed data regardless of deal type and does not invoke `quality_for_weight()`.

### 2. Mining Reserve Burn

At the upgrade epoch, execute a one-time transfer of the reserve actor's entire balance to the burn address:

```go
// In system actor upgrade logic:
reserveActor := builtin.ReserveActorAddr  // f090
burnActor := builtin.BurntFundsActorAddr  // f099
balance := getActorBalance(reserveActor)  // ~282.9M FIL at time of writing
transferFunds(reserveActor, burnActor, balance)
```

After this transfer:
- The tokens are permanently unspendable (same burn mechanism as gas fees).
- No new governance mechanism is needed — the reserve simply ceases to exist.

### 3. FIP-0003 Quality Multiplier Sunset

Upon completion of the VDWM transition (12 months after activation), the quality multiplier mechanism introduced in FIP-0003 will no longer produce differential rewards between sector types. The Fil+ governance infrastructure (notaries, DataCap) may continue to serve application-layer verification and reputation purposes, but will no longer affect protocol-level block reward distribution.

## Design Rationale

### Why a 12-month linear transition?

| Approach | Year 1 CC Reward | Year 1 Pledge (FIP-0081) | Year 1 ROI |
|---|---|---|---|
| Immediate (VDWM 10→1 at activation) | 0.000910 FIL/day | 1.093 FIL | ~30% |
| 12-month gradual (this FIP) | 0.000910 FIL/day *at completion* | 1.093 FIL *at completion* | ~30% *at completion* |
| 3-year gradual | 0.000210 FIL/day at year 1 | ~0.30 FIL | ~26% |

The 12-month transition achieves the same end-state as immediate removal while providing:
1. Time for storage providers to adjust operational strategies.
2. Gradual unwinding of Fil+-dependent business models.
3. Smooth power table transitions for consensus stability.

A 3-year transition unnecessarily extends the period of suboptimal economics.

### Why not slow the baseline growth?

Counterintuitively, the growing baseline *helps* SP economics. Our simulation tested growth rates from 0% to 100%/year with VDWM=1:

| Baseline Growth | Reward/TiB (Y5) | Pledge/32GiB (Y5) | ROI (Y5) |
|---|---|---|---|
| 0% (freeze) | 0.01824 FIL | 0.0856 FIL | 243% |
| 50%/year | 0.01824 FIL | 0.0212 FIL | 984% |
| 100%/year (current) | 0.01824 FIL | 0.0137 FIL | 1,518% |

**Rewards are identical** across all growth rates (RBP << baseline in all cases). But pledge **increases** when the baseline shrinks, because $ConsensusPledge = 0.30 \times CircSupply \times \frac{SectorQAP}{\max(Baseline, NetworkQAP)}$ — a smaller denominator means more pledge. The growing baseline keeps pledge manageable.

### Why combine VDWM reduction with mining reserve burn?

These two changes are economically independent (no formula contains both variables). Combining them:
1. Addresses the two most prominent community governance concerns — [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774) (358 comments) and [PR #1039](https://github.com/filecoin-project/FIPs/pull/1039) (~20 months stalled) — in one proposal.
2. Reduces the number of consensus upgrades needed.
3. Demonstrates that meaningful economic reform can be achieved with minimal protocol disruption.

### Why grandfathering instead of retroactive adjustment?

- **Gas**: Retroactively adjusting all sectors' quality would require updating the power table for every active sector across 923 miners — potentially millions of state updates exceeding block gas limits.
- **Fairness**: Providers committed pledge under VDWM=10 rules. Retroactive changes would alter the economic terms under which those sectors were committed.
- **Bounded duration**: All pre-transition sectors expire within 3.5 years (FIP-0052). The overlap is temporary and diminishing.

### What makes this FIP different from prior proposals?

| Aspect | FIP-0080 (2023) | This FIP |
|---|---|---|
| Economic analysis | Qualitative arguments | Quantitative simulation (44,850 data points, [open source](https://github.com/Reiers/fip-daybreak/tree/main/sim)) |
| Security analysis | Brief qualitative section | Formal analysis of 5 attack vectors with quantitative bounds |
| Gas benchmarking | Not addressed | Full gas impact analysis (<0.01% overhead) |
| Code specification | "Set multiplier to 10" | Epoch-aware interpolation function with exact call sites |
| Transition mechanism | "Existing deals keep quality" | 12-month linear interpolation with grandfathering |
| Mining reserve | Not addressed | Combined with reserve burn |
| Cross-FIP analysis | Not addressed | Verified compatibility with FIP-0081, 0086, 0098, 0100 |

This FIP is not a replacement for FIP-0080 — it is the quantitative completion of the work that FIP-0080 began.

## Backwards Compatibility

This proposal modifies the built-in storage miner actor and requires a network upgrade.

**State migration:** Minimal. No structural changes to `SectorOnChainInfo` or `Deadline` are needed. The quality multiplier is applied at runtime during sector activation, extension, and update. No existing sector state requires migration. The reserve burn is a single balance transfer (~2M gas). This is among the lightest state migrations of any recent core FIP — compare to nv25 Teep which iterated every miner, deadline, and partition.

**API compatibility:** `StateMinerSectors`, `StateSectorGetInfo`, and related APIs return existing quality values for grandfathered sectors and new values for sectors activated after the upgrade. Clients computing QAP should use the `verified_deal_weight_multiplier_at(epoch)` function for forward calculations.

**Miner operations:** Storage providers do not need to change their sealing pipeline. The quality multiplier is applied automatically by the miner actor. Existing Fil+ workflows can continue — deals will simply not receive enhanced quality after the transition.

## Test Cases

### Unit Tests

1. **Multiplier interpolation** (code values → effective ratio = `code_value / QBM`):
   - Before `TRANSITION_START`: returns 100 (effective 10×)
   - At `TRANSITION_START`: returns 100 (effective 10×)
   - At `TRANSITION_START + DURATION/2` (525,600 epochs): returns 55 (effective 5.5×)
   - At `TRANSITION_START + DURATION` (1,051,200 epochs): returns 10 (effective 1×)
   - At `TRANSITION_START + DURATION + 1`: returns 10 (effective 1×)

2. **CC sector quality is always 1×** regardless of VDWM — CC sectors have zero verified weight, so the multiplier has no effect on them. Verify this invariant holds throughout the transition.

3. **Fil+ sector at transition midpoint:** QAP ≈ RBP × 5.5 (interpolated effective multiplier).

4. **Sector extension across transition:** Sector activated with VDWM=10, extended after transition completes → new QAP = RBP × 1.

5. **Mining reserve burn:**
   - Reserve actor (`f090`) balance → 0 after upgrade.
   - Burn actor (`f099`) balance increased by former reserve balance.
   - No other actor balances affected.

### Integration Tests

6. **WindowPoSt unaffected:** Prove that WindowPoSt succeeds identically for sectors regardless of when they were activated relative to the transition.

7. **Block reward distribution:** Over a simulated transition period, verify total block rewards match the expected minting curve `M(t) = M_S(t) + M_B(t)` within rounding tolerance.

8. **Pledge calculation:** Verify that initial pledge for new sectors uses the interpolated VDWM at the activation epoch.

9. **Cross-FIP interaction:**
   - FIP-0081 (pledge ramp): Verify the gamma pledge ramp operates correctly with changing VDWM. The ramp multiplier is independent of the quality multiplier.
   - FIP-0098 (simple termination fee): Verify 8.5% termination fee is correctly calculated on the updated initial pledge.
   - FIP-0100 (per-sector daily fee): Verify daily fee calculation with updated sector quality.

## Security Considerations

A comprehensive formal security analysis accompanies this FIP ([full analysis](https://github.com/Reiers/fip-daybreak/blob/main/security-analysis.md)). Five attack vectors were analyzed with quantitative bounds:

### Consensus security improves

The minimum physical cost of a 51% consensus attack **increases by 17.6%**:

| Metric | Current (VDWM=10) | After Daybreak (VDWM=1) |
|---|---|---|
| Minimum physical storage for 51% | 0.944 EiB (via datacap) | 1.11 EiB (physical only) |
| Minimum pledge capital for 51% | ~\$3.9M | ~\$4.5M |
| Virtual (non-physical) consensus power | ~16.3 EiB (88% of QAP) | 0 |

Today, an attacker with datacap access can acquire 51% of consensus power with only 0.944 EiB of physical storage — the 10× multiplier supplies the rest virtually. After Daybreak, 100% of consensus power is physically backed.

F3 fast finality ([FIP-0086](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0086.md)) provides an additional safety margin by reducing the finality window from 7.5 hours to ~30 seconds.

### Flash power attacks are economically irrational

An attacker onboarding sectors during the transition and terminating to extract rewards faces:
- **25-day minimum break-even** on the termination fee (FIP-0098: 8.5% of initial pledge)
- **75% of rewards locked** in 180-day vesting — unvested rewards forfeit on termination
- **Scaling penalty**: adding power dilutes the attacker's own per-unit reward
- **Result**: Minimum 25-day capital commitment for zero net profit. Not a viable "flash" strategy.

### Quality arbitrage is bounded and diminishing

Under grandfathering, existing Fil+ sectors retain 10× quality until expiry. The maximum premium is:
$$Premium \leq 9 \times CCRewardRate \times RemainingSectorDays \to 0$$
All grandfathered sectors expire within 3.5 years (FIP-0052). This is the cost of a smooth transition — it is the gradual elimination of existing redistribution, not new value creation.

### Mining reserve burn has no protocol interaction

The reserve burn is a one-time balance transfer. No economic formula contains both VDWM and the reserve balance as variables. These changes are mathematically independent.

### No new attack vectors

Daybreak leverages existing security mechanisms (pledge, vesting, termination fees, F3 finality) without introducing new security parameters. All analyzed vectors either have negative expected return or show improved security posture compared to the status quo.

## Incentive Considerations

### Who benefits

- **CC storage providers**: 8.5× revenue increase with only 24% more pledge. This is the largest economic improvement for honest, infrastructure-providing miners in Filecoin's history.
- **Small and new SPs**: No longer need to navigate the notary system to earn competitive rewards. Equal access based on physical storage contribution.
- **Token holders**: Reserve burn removes ~283M FIL of potential inflation. Reduced gaming improves network credibility.
- **Genuine data clients**: Storage pricing becomes market-driven rather than subsidy-driven. Clients who value Filecoin storage pay fair market rates.

### Who is affected negatively

- **SPs dependent on the Fil+ subsidy**: Providers whose business model relies on the 10× multiplier (particularly for non-retrievable data) will see rewards decrease to 1× levels. This is an intended outcome — the subsidy has not produced the useful-storage incentive it was designed to create.
- **Notary ecosystem**: DataCap and notary roles lose their protocol-level economic significance. These roles can transition to application-layer verification and reputation services.
- **Legitimate verified deal SPs**: Providers storing genuine verified data will see per-sector rewards decrease. However, their physical storage still earns 1× rewards, and the transition provides 12 months to adjust pricing to market rates.

### Transition timeline

| Month | Effective VDWM | CC Reward (approx.) | Notes |
|-------|---------------|-------------------|-------|
| 0 | 10× | 0.000107 FIL/day | Status quo |
| 3 | 7.75× | 0.000138 FIL/day | Minimal change |
| 6 | 5.5× | 0.000195 FIL/day | CC reward ~doubles |
| 9 | 3.25× | 0.000339 FIL/day | Fil+ premium eroding |
| 12 | 1× | 0.000910 FIL/day | All sectors equal |

This gradual curve allows market participants to adjust positions. SPs dependent on Fil+ subsidies have 12 months to transition to alternative revenue models: market-rate storage, FVM-based incentive contracts, FOC/PDP warm storage services, or other application-layer mechanisms.

## Product Considerations

### Impact on existing storage products

The Filecoin Onchain Cloud (FOC) stack — PDP (Provable Data Possession), FilecoinPay, FWSS, Synapse SDK — operates via FVM smart contracts and is independent of the Fil+ quality multiplier. This FIP does not affect those products.

### Future deal incentive mechanisms

With VDWM=1 at the protocol level, deal incentives move to the application layer:
- FVM smart contracts can implement custom incentive structures (storage bounties, retrieval guarantees).
- The FOC stack provides built-in streaming payment rails for storage services.
- DataDAO and data market protocols can offer deal-specific rewards without protocol-level multipliers.

This aligns with the design principle of a minimal, neutral base layer that supports diverse application-layer innovation — consistent with the approach taken by Ethereum and other mature L1 protocols.

## Implementation

### Required changes

| Component | Change | Complexity |
|---|---|---|
| `filecoin-project/builtin-actors` — `actors/miner/src/policy.rs` | Add `verified_deal_weight_multiplier_at()`, update `quality_for_weight()` and `qa_power_max()` call sites | Low — function addition + 2 call site modifications |
| `filecoin-project/builtin-actors` — system actor upgrade | Add reserve-to-burn transfer at upgrade epoch | Low — single balance transfer |
| `filecoin-project/lotus` | Bundle new builtin-actors, set upgrade epoch | Standard upgrade procedure |
| `filecoin-project/venus`, `ChainSafe/forest` | Bundle new builtin-actors, set upgrade epoch | Standard upgrade procedure |
| `filecoin-project/specs` | Update sector quality and token allocation sections | Documentation |
| `filecoin-project/ref-fvm` | No changes needed | — |

### Gas impact

The code change adds approximately 200–350 gas per invocation of `quality_for_weight()` (46–89 additional WASM instructions at 4 gas each). In context:

| Operation | Current Gas | Added Gas | Overhead |
|---|---|---|---|
| `ProveCommitSectors3` (3 sectors) | ~530,000,000 | ~900 | 0.00017% |
| `PreCommitSectorBatch2` (4 sectors) | ~120,000,000 | ~1,200 | 0.0010% |
| `SubmitWindowedPoSt` | ~24,000,000 | 0 | 0% (does not call `quality_for_weight()`) |
| `CronTick` | ~10–50,000,000 | 0 | 0% (grandfathering: no quality recalculation) |
| State migration (reserve burn) | — | ~2,000,000 | One-time |

### Implementation tracking

| Repository | PR | Status |
|---|---|---|
| `filecoin-project/builtin-actors` | TBD | Not started |
| `filecoin-project/lotus` | TBD | Not started |
| `filecoin-project/venus` | TBD | Not started |
| `ChainSafe/forest` | TBD | Not started |
| `filecoin-project/specs` | TBD | Not started |

## Acknowledgments

This FIP builds on the work of many community members who have advocated for economic reform over the past several years, particularly the authors of FIP-0080 (Fatman13, ArthurWang1255, stuberman, Eliovp, dcasem, The-Wayvy) and FIP-0093 (dcasem). The extensive discussion in [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774) and [Discussion #1030](https://github.com/filecoin-project/FIPs/discussions/1030) provided the community context that informed this proposal.

The economic simulation, gas benchmarking, and security analysis were developed with the assistance of AI tools (Anthropic Claude) and GPU compute (NVIDIA RTX 5080) to validate mathematical claims against the Filecoin protocol specification and on-chain data. All simulation source code, data, and analysis are published for independent verification:

- **Simulation**: [github.com/Reiers/fip-daybreak/sim](https://github.com/Reiers/fip-daybreak/tree/main/sim)
- **Analysis and security proofs**: [github.com/Reiers/fip-daybreak](https://github.com/Reiers/fip-daybreak)

## References

- [Filecoin Spec: Block Reward Minting](https://spec.filecoin.io/#section-systems.filecoin_token.block_reward_minting) — Defines $M_S$, $M_B$, $\theta$, $\bar{R}$
- [Filecoin Spec: Sector Quality](https://spec.filecoin.io/#section-systems.filecoin_mining.sector.sector-quality) — Defines QAP, VDWM, DWM, QBM
- [Filecoin Spec: Miner Collaterals](https://spec.filecoin.io/#section-systems.filecoin_mining.miner_collaterals) — Defines initial pledge formula
- [Filecoin Spec: Token Allocation](https://spec.filecoin.io/#section-systems.filecoin_token.token_allocation) — Defines mining reserve
- [FIP-0003: Filecoin Plus Principles](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0003.md) — Introduced the 10× quality multiplier
- [FIP-0052: Increase Max Sector Commitment to 3.5 Years](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0052.md) — Sector lifetime bound
- [FIP-0076: Direct Data Onboarding](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0076.md) — Current DataCap allocation mechanism
- [FIP-0080: Phasing Out Fil+](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0080.md) — Prior proposal, [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774)
- [FIP-0081: Pledge Ramp](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0081.md) — Pledge smoothing mechanism
- [FIP-0086: Fast Finality (F3)](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0086.md) — 30-second finality
- [FIP-0093: Set Mining Reserve to Zero](https://github.com/filecoin-project/FIPs/pull/1039) — Prior proposal for reserve burn
- [FIP-0098: Simple Termination Fee](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0098.md) — 8.5% of initial pledge
- [FIP-0100: Per-Sector Daily Fee](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0100.md) — Daily fee mechanism
- [CryptoEconLab: Resilience of the Filecoin Network](https://medium.com/cryptoeconlab/resilience-of-the-filecoin-network-d7861ee9986a)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
