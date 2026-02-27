---
fip: "<to be assigned>"
title: "Daybreak: Sector Parity, Reserve Cleanup, and Economic Simplification"
author: Reiers (@Reiers)
discussions-to: <to be created>
status: Draft
type: Technical
category: Core
created: 2026-02-27
spec-sections:
  - section-systems.filecoin_token.token_allocation
  - section-systems.filecoin_mining.sector.sector-quality
  - section-algorithms.cryptoecon
  - section-systems.filecoin_token.minting_model
  - section-systems.filecoin_mining.miner_collaterals
requires: "0098"
---

# FIP-XXXX: Daybreak — Sector Parity, Reserve Cleanup, and Economic Simplification

## Simple Summary

This FIP introduces four coordinated economic changes to Filecoin:

1. **Sector Parity**: Gradually reduce the Verified Deal quality multiplier from 10x to 1x over 12 months, making all sectors equal in consensus power per raw byte.
2. **Reserve Cleanup**: Set the mining reserve (f090, ~282.9M FIL) to zero by transferring its balance to f099 (the burn address).
3. **CC Sector Offboarding**: Reduce termination fees for Committed Capacity sectors to zero, subject to a 7-day pledge lockup.
4. **Baseline Recalibration**: Reduce the baseline annual growth rate from 100% to 50% to better reflect actual network growth and unlock deferred baseline minting rewards.

Together, these changes restore economic neutrality to the protocol, remove unused token overhang, lower barriers to entry, and align the minting schedule with network reality.

## Abstract

Filecoin's economic model was designed to incentivize useful storage through a quality-adjusted power mechanism where verified deals receive 10x the consensus power of committed capacity sectors. After five years of operation, this mechanism has produced significant unintended consequences: a permissioned layer controlled by human notaries, widespread gaming (~90% of verified data estimated non-genuine), declining raw byte power, community fragmentation, and a fundamental departure from Filecoin's stated mission of decentralized storage.

This FIP addresses these issues through four complementary protocol changes. The multiplier reduction follows a predictable schedule (10x → 5x → 2.5x → 1x) applied only to new sectors, grandfathering existing commitments. The mining reserve burn removes 282.9M FIL of latent supply that has never been utilized. CC sector termination reform eliminates penalties for provably-empty sectors while maintaining a lockup period for consensus security. Baseline recalibration adjusts the growth rate to unlock rewards that are currently deferred because the network operates well below the original baseline.

Each change is independently valuable, but together they form a coherent economic reset that aligns protocol incentives with its original design goals while enabling the next phase of Filecoin's growth — including Filecoin Onchain Cloud (FOC), PDP-based warm storage, and permissionless data markets on FVM.

## Change Motivation

### The Current State

Filecoin's original specification ([spec.filecoin.io](https://spec.filecoin.io)) established a permissionless storage network where miners earn block rewards proportional to their contributed storage. The Verified Client mechanism (FIP-0003) was introduced as a social-trust layer to incentivize "useful" data by granting 10x quality-adjusted power to sectors storing verified data.

Five years later, the empirical evidence is clear:

**1. The multiplier has created a permissioned consensus layer.**

As of epoch 5,796,404 (February 2026, sourced from [filfox.info API](https://filfox.info/api/v1/overview)):

| Parameter | Value |
|---|---|
| Raw Byte Power (RBP) | 2.17 EiB |
| Quality-Adjusted Power (QAP) | 18.50 EiB |
| Circulating Supply | 832.5M FIL |
| Daily Mined | 66,249 FIL |
| Active Miners | 923 |
| Network Baseline | 114.21 EiB |

Using the standard decomposition:

```
Fil+ consensus share = 10 × (QAP - RBP) / (9 × QAP) = 10 × (18.50 - 2.17) / (9 × 18.50) ≈ 98.1%
Fil+ physical storage share = (QAP/RBP - 1) / 9 = (18.50/2.17 - 1) / 9 ≈ 83.6%
```

83.6% of physical storage, boosted by human-granted DataCap, controls **98.1% of consensus power**. The remaining 16.4% of storage (CC sectors) shares just 1.9% of block rewards. This directly contradicts Filecoin's [mission statement](https://github.com/filecoin-project/FIPs/blob/master/mission.md): *"No centralized parties can control, stop, or censor the network, its operation, or its participants."*

**1a. The 10x multiplier does not increase total block rewards — it is a pure redistribution.**

This is the foundational economic fact motivating this FIP. The Filecoin minting model ([Block Reward Minting](https://spec.filecoin.io/#section-systems.filecoin_token.block_reward_minting)) defines:

- **Simple minting**: `M_S(t) = M_∞S · (1 − e^{−λt})` — a function of elapsed time only.
- **Baseline minting**: `M_B(t) = M_∞B · (1 − e^{−λθ(t)})` — where the effective network time θ(t) depends on cumulative *raw-byte* power.

Critically, the effective network time θ is derived from:

```
R̄(t) := min{b(t), R(t)}
```

where `R(t)` is defined as *"the instantaneous network raw-byte power (the total amount of bytes among all active sectors)"* (spec §5.2.2). This is the sum of physical sector sizes — **unaffected by quality multipliers**.

**Therefore:** Changing VDWM leaves `R(t)` unchanged → `R̄_Σ(t)` unchanged → `θ(t)` unchanged → `M(t) = M_S(t) + M_B(t)` unchanged. The multiplier is a zero-sum redistribution: it taxes CC sectors to subsidize Fil+ sectors, with no net increase to the reward pool.

We validated this by numerical simulation (CUDA, NVIDIA RTX 5080 GPU — [source code](https://github.com/Reiers/super-fip-sim)). Starting from the current chain state, we projected 12 scenarios across 10 years:

| Scenario | VDWM | Year 1 Issuance | Year 5 Issuance | Year 10 Issuance |
|---|---|---|---|---|
| Status Quo | 10 | 61,883 FIL/day | 39,400 FIL/day | 22,860 FIL/day |
| Sector Parity | 1 | 61,883 FIL/day | 39,400 FIL/day | 22,860 FIL/day |

Values are identical to 8 significant figures across the full projection. **Removing the multiplier does not reduce network rewards by a single FIL.**

The impact on per-sector economics is dramatic. For a 32 GiB CC sector at the current epoch:

| Metric | With Fil+ (VDWM=10) | Without Fil+ (VDWM=1) | Change |
|---|---|---|---|
| Daily reward | 0.000107 FIL | 0.000910 FIL | **+8.5×** |
| Storage pledge (20 days) | 0.00213 FIL | 0.01820 FIL | +8.5× |
| Consensus pledge | 0.06517 FIL | 0.06517 FIL | **unchanged** |
| Total initial pledge | 0.0673 FIL | 0.0834 FIL | +24% |
| Annual ROI on pledge | 58% | 399% | **+6.9×** |

The consensus pledge is unchanged because `max(baseline, QAP)` evaluates to the baseline (114.21 EiB) in both cases — the network is far below baseline regardless of VDWM.

**2. The subsidy mechanism has been extensively gamed.**

Community analyses ([notary-governance#940](https://github.com/filecoin-project/notary-governance/issues/940), [notary-governance#941](https://github.com/filecoin-project/notary-governance/issues/941), [quality.datacapstats.io](https://quality.datacapstats.io/)) consistently estimate that the vast majority of verified data is non-genuine — including data replication with minor modifications, non-retrievable sectors, and various forms of system gaming. DataCap has been observed trading on secondary markets. The verification process has not achieved the "decentralized, globally distributed network of entities" envisioned by the original specification.

**3. Raw byte power is in sustained decline.**

RBP peaked at ~19 EiB in mid-2022 and has declined to 2.17 EiB — an **89% decline**. The network is losing physical storage capacity at ~25% per year. The cost structure of CC mining has become deeply unfavorable: a CC sector earns just 0.000107 FIL/day ($0.00016) while a Fil+ sector earns 0.001067 FIL/day ($0.0016) — a 10× gap for identical physical hardware. Storage providers who cannot access DataCap face an effective ~90% tax on their block rewards. This drives rational providers out of the network, reducing both its security (less physical storage) and its capacity to serve future demand.

The network's RBP now represents just **1.9% of the baseline** (2.17 EiB vs 114.21 EiB). The effective network time θ is 3.34 years — lagging 2.2 years behind real time. This means 68% of the baseline minting allocation (~524M FIL) remains effectively unreachable under current conditions.

**4. The community has been requesting reform for over two years.**

[Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774) (FIP-0080, Aug 2023) is the most-engaged FIP discussion in Filecoin's history with 57 substantive comments. [Discussion #844](https://github.com/filecoin-project/FIPs/discussions/844) (FIP-0078, Oct 2023) has 22 comments. Both proposals have remained in Draft status for over two years. [Discussion #972](https://github.com/filecoin-project/FIPs/discussions/972) (Zero CC Termination, Mar 2024) received constructive engagement from core developers but was never formalized. [PR #1039](https://github.com/filecoin-project/FIPs/pull/1039) (FIP-0093, Mining Reserve, Jul 2024) received editor approval but was abandoned by its author.

This FIP consolidates these efforts into a single, comprehensive, implementation-ready proposal.

**5. The mining reserve is unused overhead.**

The [token allocation specification](https://spec.filecoin.io/#section-systems.filecoin_token.token_allocation) allocated 15% of FIL_BASE (300M FIL, now ~282.9M FIL at f090) for "future types of mining." After five years, these tokens have never been distributed. The specification itself acknowledges: *"It will be up to the community to determine in the future how to distribute those tokens."* The community's determination, as expressed through [FIP-0093](https://github.com/filecoin-project/FIPs/pull/1039) and broad Slack/governance forum support, is to remove this supply overhang.

**6. The baseline is disconnected from reality.**

The minting model specifies a baseline starting at 2.5 EiB growing at 100% annually. By 2026, this baseline far exceeds actual network RBP (~11 EiB), meaning a significant portion of baseline minting rewards remain deferred. Adjusting the growth rate to 50% — still above the global storage market's ~40% annual growth — would unlock additional block rewards for current participants without changing the total FIL supply.

### What This FIP Is NOT

- **Not anti-Fil+**: This FIP does not question the value of incentivizing useful data storage. It questions the specific mechanism (a 10x consensus multiplier gated by human notaries) and proposes a transition to permissionless alternatives (FVM-based markets, PDP verification, payment-backed storage demand).
- **Not a fork threat**: This FIP works entirely within the existing FIP governance process and targets inclusion in a future network upgrade.
- **Not a reversal**: Existing sector commitments are grandfathered. No storage provider loses power on sectors they have already committed.

## Specification

### Change 1: Verified Deal Quality Multiplier Reduction

#### Parameters

| Parameter | Current Value | Proposed Value |
|-----------|--------------|----------------|
| `VerifiedDealWeightMultiplier` (VDWM) | 10 | Scheduled reduction (see below) |
| `QualityBaseMultiplier` (QBM) | 1 | 1 (unchanged) |
| `DealWeightMultiplier` (DWM) | 1 | 1 (unchanged) |

#### Schedule

Starting from the activation epoch of this FIP:

| Phase | Duration | VDWM | Effective Date (approximate) |
|-------|----------|------|------------------------------|
| Phase 0 (current) | — | 10x | Before activation |
| Phase 1 | 0–4 months | 5x | Activation |
| Phase 2 | 4–8 months | 2.5x | Activation + 345,600 epochs |
| Phase 3 | 8–12 months | 1.25x | Activation + 691,200 epochs |
| Phase 4 | 12+ months | 1x | Activation + 1,036,800 epochs |

Epoch calculations assume 30-second epochs, 2,880 epochs/day, ~86,400 epochs/month.

#### Grandfathering

Sectors committed **before** the activation epoch retain their original quality multiplier for their full committed duration. The multiplier reduction applies only to **new** sector commitments (PreCommitSector and ProveCommitSector calls) after the activation epoch.

Upon sector **extension** (ExtendSectorExpiration) after the activation epoch, the sector's quality multiplier is recalculated using the VDWM in effect at the time of extension, applied to any remaining verified deal weight.

#### Implementation

In `builtin-actors` (`actors/miner/src/`):

1. Add a new network-version-gated function `current_verified_deal_weight_multiplier(epoch)` that returns the VDWM based on the schedule above, relative to the activation epoch stored as a network parameter.

2. Modify `quality_adj_power_for_weight` ([ref](https://github.com/filecoin-project/builtin-actors/blob/master/actors/miner/src/sectors.rs)) to use `current_verified_deal_weight_multiplier(current_epoch)` for new sector activations instead of the hardcoded value.

3. Modify `extend_sector_expiration` to recalculate quality using the multiplier in effect at the time of extension.

4. In the power actor, no changes are needed — power accounting already flows from sector quality.

### Change 2: Mining Reserve Cleanup

#### Specification

1. Transfer the entire balance of `f090` (the mining reserve actor, approximately 282,966,003 FIL) to `f099` (the burn address).

2. Update the `TotalFilecoin` constant used in invariant checks from `2,000,000,000 × 10^18` attoFIL to the new value: `TotalFilecoin - BalanceOf(f090)`, which is approximately `1,717,066,618,961,773,405,230,063,046` attoFIL (the exact value to be computed at migration time).

3. Update `DealProviderCollateralBounds` (which uses `TotalFilecoin` as a maximum) to use the adjusted total.

#### Implementation

This is a state migration executed during the network upgrade:

1. Read balance of f090.
2. Transfer entire balance from f090 to f099.
3. Update the `TOTAL_FILECOIN` constant in the runtime.
4. Update invariant checks in `go-state-types` ([ref](https://github.com/filecoin-project/go-state-types/blob/master/builtin/v15/check.go)).

This is a one-time migration. The f090 actor remains but with a zero balance.

### Change 3: CC Sector Offboarding Reform

#### Parameters

| Parameter | Current Value | Proposed Value |
|-----------|--------------|----------------|
| CC Sector Termination Fee | 8.5% of initial pledge (per FIP-0098) | 0 |
| CC Sector Pledge Lockup | 0 (immediate return) | 7 days (201,600 epochs) |

#### Definition of CC Sector

A CC sector is defined as a sector where the unsealed CID (CommD) equals the "zero piece" CID — that is, the sector is provably empty of user data. This is consistent with the definition in [FIP-0098](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0098.md) and [Discussion #972](https://github.com/filecoin-project/FIPs/discussions/972).

After FIP-0076 (DDO), CC is not the same as "sector without deals" or "sector whose Fil+ allocation expired." The on-chain test is the data commitment being equal to the zero-data commitment.

#### Mechanism

When a miner terminates a CC sector (via `TerminateSectors`):

1. **No termination fee is charged.** The sector's termination penalty is zero.
2. **Pledge lockup**: The initial pledge associated with the sector is not released immediately. Instead, it enters a 7-day lockup period (201,600 epochs), after which it is returned to the miner's available balance.
3. **Faulty CC sectors**: If a CC sector is in a faulty state at the time of termination, the standard fault fee applies (2.14 days of block reward per day in fault), but no additional termination fee is charged. The lockup still applies.

#### Security Rationale

The 7-day lockup addresses the consensus security concern raised by @anorth and @irenegia in [Discussion #972](https://github.com/filecoin-project/FIPs/discussions/972): complete freedom to add/remove power at any rate ("flash power") makes incentive alignment difficult. The lockup ensures a minimum commitment period for consensus pledge, analogous to unstaking delays in proof-of-stake networks (Ethereum: ~27 hours via exit queue; Cosmos: 21 days).

The lockup is financially similar to a ~1.23% termination fee (7 days × ~15% annual interest on locked capital / 365 × pledge), far less than the current 8.5%, while providing stronger security guarantees than a fee alone since the pledge remains at risk for the full lockup period.

#### Implementation

In `builtin-actors` (`actors/miner/src/monies.rs`):

1. Modify `pledge_penalty_for_termination` to check if the terminated sector is CC (zero data commitment). If so, return zero penalty.

2. Add a new `PledgeLockupQueue` data structure to `MinerState` that tracks pledge amounts and their unlock epochs.

3. Modify `TerminateSectors` to enqueue CC sector pledge into the lockup queue instead of releasing it immediately.

4. Add a `ProcessPledgeLockups` method (called by cron or on any state-changing miner invocation) that releases pledges whose lockup period has elapsed.

### Change 4: Baseline Recalibration

#### Parameters

| Parameter | Current Value | Proposed Value |
|-----------|--------------|----------------|
| Baseline annual growth rate (g_a) | 100% | 50% |

All other minting parameters remain unchanged:
- Simple/baseline split (γ): 30%/70%
- Half-life (λ): 6 years
- Initial baseline (b₀): 2.5 EiB

#### Mathematical Impact

The baseline function changes from:

```
b(t) = b₀ × e^(g₁ × t)     where g₁ = ln(1 + 1.0) / 1yr = ln(2) / 1yr
```

to:

```
b(t) = b₀ × e^(g₂ × t)     where g₂ = ln(1 + 0.5) / 1yr = ln(1.5) / 1yr
```

This means the baseline at any given time t is lower, so the network's "effective network time" θ(t) increases:

```
θ(t) = (1/g) × ln(g × R̄_Σ(t) / b₀ + 1)
```

A lower g means a larger θ(t) for the same cumulative network power, which unlocks more baseline minting rewards:

```
M_B(t) = M_∞B × (1 - e^(-λ × θ(t)))
```

**Concrete effect**: At current 2.17 EiB RBP, the 100% growth baseline (114.21 EiB) is far ahead of the network. Reducing to 50% changes the effective network time calculation, partially unlocking deferred baseline minting and increasing daily issuance by approximately 8% — without changing the total FIL supply or the long-term minting schedule.

**Simulation results** — baseline growth rate sensitivity at Year 5 (VDWM=1, RBP stable):

| Baseline Growth | Daily Issuance | Reward/TiB | Pledge/32GiB | ROI |
|---|---|---|---|---|
| 0% (freeze) | +24%* | 0.01824 | 0.0856 | 243% |
| 25%/year | +16%* | 0.01824 | 0.0357 | 583% |
| 50%/year (proposed) | +8%* | 0.01824 | 0.0212 | 984% |
| 100%/year (current) | baseline | 0.01824 | 0.0137 | 1,518% |

*Percentage increase in daily issuance vs 100% baseline growth.

Note: rewards per TiB are approximately equal across all growth rates (because RBP << baseline in all scenarios, so `R̄ = RBP` regardless). The primary effect of slower baseline growth is on the consensus pledge denominator: `max(baseline, QAP)` yields a smaller baseline, which *increases* the consensus pledge per sector. The net ROI is therefore lower with slower growth.

This presents a deliberate trade-off: **the 50% rate unlocks more total minting** (benefiting the network's token economics and current participants collectively) **while modestly increasing per-sector pledge** (a stronger per-sector commitment). The 50% rate still exceeds global storage market growth (~40% annually per IDC estimates) and remains aspirational. Since consensus pledge provides security guarantees, the increased pledge under 50% growth can be viewed as a feature rather than a cost — it raises the economic barrier for flash-power attacks during the multiplier transition.

#### Implementation

In `builtin-actors` (reward actor):

1. At the activation epoch, update the baseline growth rate constant from `g₁` to `g₂`.
2. The baseline function `b(t)` transitions to the new growth rate at activation. For continuity, the new baseline at activation epoch equals the old baseline at that epoch:

```
b_new(t) = b_old(t_activation) × e^(g₂ × (t - t_activation))    for t ≥ t_activation
```

This ensures no discontinuity in the baseline function.

## Design Rationale

### Why a Scheduled Multiplier Reduction (Not Immediate)?

Immediate removal of the 10x multiplier would render all new onboarding unprofitable at current reward levels (as analyzed by @anorth in [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774#discussioncomment-6660099)). A 12-month schedule allows:

1. **Market adaptation**: SPs can adjust business models incrementally.
2. **Orderly transition**: No sudden shock to QAP, pledge requirements, or circulating supply.
3. **Evaluation checkpoints**: The community can assess effects at each phase boundary.

The "free multiplier" approach (proposed by @anorth in [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774#discussioncomment-6770113)), where any SP can choose a 1-10x multiplier with proportional pledge, was considered as an alternative. While it achieves the same long-run equilibrium, it does not provide certainty about the timeline to sector parity, which is a primary community demand ([Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774), [Discussion #844](https://github.com/filecoin-project/FIPs/discussions/844)). A definite schedule provides the "much-needed certainty to network participants" called for in FIP-0080.

### Why Grandfathering?

All authors of FIP-0078/0080 explicitly committed to grandfathering existing sectors. Retroactive changes would: (a) breach the implicit contract with SPs who committed based on existing rules, (b) potentially trigger legal liability for SPs with investor obligations, and (c) set a precedent that undermines confidence in future protocol commitments. Sectors committed before activation retain their original QAP until natural expiration.

### Why Burn the Mining Reserve (Not Repurpose It)?

The mining reserve was created for "future types of mining." After five years:

1. **No concrete proposal** has been made to use these tokens for a new mining type.
2. **FOC/PDP** (the closest analogy to "new mining") was designed without requiring the mining reserve.
3. The reserve creates **perceived supply overhang** — 282.9M FIL that could theoretically be released at any time, depressing investor confidence.
4. If a future use case requires new token issuance, it can be proposed via FIP at that time with full community deliberation — a stronger governance guarantee than a pre-minted reserve controlled by no one.

This aligns with FIP-0093's rationale and the broad support it received from FIP editors @rvagg and @jsoares.

### Why Zero CC Termination + Lockup (Not Just Reduced Fee)?

Per @anorth's analysis in [Discussion #972](https://github.com/filecoin-project/FIPs/discussions/972#discussioncomment-9078432):

> "I tend to agree that further stability (of CC sectors) is probably not something the protocol should sacrifice much for."

And per @irenegia's security analysis:

> "24h is okay for WindowPoSt, but even higher values are fine (i.e., 24h is the minimum). So we can set it to whatever is needed for lockup, maybe setting to 1 week is okay."

A lockup is superior to a fee because:
- It provides **stronger security** (the full pledge is at risk for the entire period, not just a fraction burned on exit)
- It is **cheaper for honest SPs** (they get all their pledge back)
- It **prevents flash power attacks** (can't rapidly cycle power in/out)
- It aligns with standard PoS network design (Ethereum, Cosmos, Polkadot all use lockups)

### Why Recalibrate the Baseline?

The 100% annual growth rate was set assuming aggressive adoption. After 5.5 years, the network has never exceeded the baseline — RBP peaked at 19 EiB while the baseline was already 35 EiB at that time. Today RBP is just 1.9% of the 114 EiB baseline, and the gap widens exponentially (baseline in 5 years: 3,656 EiB; in 10 years: 116,954 EiB).

Our simulation reveals a nuanced trade-off:

- **More total minting**: Reducing g increases the effective network time θ (because `θ = (1/g) · ln(g · R̄_Σ / b₀ + 1)` grows when g shrinks). At the transition, θ jumps from ~3.51M to ~4.78M epochs, unlocking ~69M additional FIL of baseline minting and increasing ongoing daily issuance by ~8%.

- **Higher consensus pledge**: The consensus pledge formula `0.30 × CircSupply × SectorQAP / max(Baseline, QAP)` produces a larger pledge when the forward baseline is smaller. At Year 5 with 50% growth, consensus pledge is ~1.5× higher than with 100% growth.

We recommend 50% for two reasons:

1. **The spec anticipated adjustment**: The minting model specification explicitly states *"The community can come together to slow down the rate of growth when the network is providing 1-10% of the world's storage."* The network currently provides well under 0.01% of world storage yet the baseline assumes 100% growth in perpetuity.

2. **Higher pledge strengthens the multiplier transition**: During the 12-month VDWM reduction, the slightly higher pledge from a slower baseline provides additional economic security against flash-power attacks. This is a deliberate design complement to the CC offboarding reform (Change 3).

If the community prefers to maximize per-sector ROI, the baseline growth rate can remain at 100% without affecting the other three changes. The four changes in this FIP are independently valuable.

## Backwards Compatibility

### Multiplier Reduction

- **New sectors**: Subject to the current VDWM at their activation epoch. This is a parameter change, not a structural change to the sector quality calculation.
- **Existing sectors**: Unchanged until extension. On extension, the multiplier at time of extension applies.
- **Power table**: QAP decreases gradually as new sectors activate with lower multipliers. No sudden drop.
- **Pledge requirements**: Consensus pledge per sector decreases with lower QAP, reducing barriers to entry.
- **API compatibility**: `StateMinerPower`, `StateReadState`, and related APIs continue to work. QAP values change but data types remain the same.

### Mining Reserve

- **Total supply accounting**: Tools and explorers that reference `TotalFilecoin = 2B` must update to the new constant. The `StateCirculatingSupply` API already computes circulating supply dynamically and is unaffected.
- **f090 actor**: Remains on-chain with zero balance. No actor removal needed.

### CC Termination

- **Existing termination flows**: The `TerminateSectors` message interface does not change. Only the penalty calculation and pledge release timing change for CC sectors.
- **DeFi/lending protocols**: Protocols that use miner termination fees as collateral assumptions benefit from the simplification (consistent with FIP-0098's motivation). The lockup period is predictable and can be accounted for.
- **Curio/Lotus implementation**: The `TerminateSectors` method in the miner actor already handles sector termination. The change adds a conditional branch for CC sectors and a new queue for delayed pledge release.

### Baseline Recalibration

- **Reward calculation**: The reward actor already computes the baseline function per-epoch. Changing the growth rate is a constant update. No API changes.
- **Historical data**: All historical minting remains valid. The new rate applies only from the activation epoch forward.

## Test Cases

1. **Multiplier Phase Transition**: Verify that a sector committed at activation+1 receives VDWM=5x, a sector committed at activation+345,601 receives VDWM=2.5x, etc.
2. **Grandfathering**: Verify that a sector committed before activation retains VDWM=10x at any epoch.
3. **Extension Re-pricing**: Verify that extending a pre-activation 10x sector after activation applies the current VDWM.
4. **Reserve Burn**: Verify that f090 balance is zero post-migration and f099 balance increased by the same amount.
5. **Invariant Check**: Verify the new TotalFilecoin constant passes all invariant checks post-migration.
6. **CC Termination (Zero Fee)**: Verify that terminating a CC sector incurs no penalty.
7. **CC Termination (Lockup)**: Verify that pledge from a terminated CC sector is unavailable for 201,600 epochs, then released.
8. **CC Termination (Faulty)**: Verify that a faulty CC sector still pays fault fees but no additional termination fee.
9. **Non-CC Termination**: Verify that sectors with non-zero data commitments still pay the FIP-0098 termination fee.
10. **Baseline Continuity**: Verify that the baseline function is continuous at the activation epoch (no step change).
11. **Baseline Rewards**: Verify that per-epoch block rewards increase after recalibration (due to higher θ(t)).
12. **Poisson Sortition**: Verify that leader election remains correct as QAP shifts from multiplier reduction.

## Security Considerations

### Consensus Security

**Multiplier reduction**: As VDWM decreases, the relative power of physical storage increases. This strengthens consensus security because consensus power becomes more tightly coupled to actual hardware commitment. An attacker must acquire physical storage, not just DataCap approvals, to gain power.

**CC termination reform**: The 7-day lockup prevents rapid power cycling. The total pledge at risk during the lockup is higher than the current termination fee (100% of pledge vs 8.5%), providing stronger disincentive for adversarial behavior. @irenegia's formal analysis ([linked in #972](https://drive.google.com/file/d/1notObdkPT1BCztgspIpzSUAzWSrM8h81/view)) confirms that termination fees must be ≥ fault fees for WindowPoSt security; the lockup satisfies this constraint because the full pledge is withheld.

**Baseline recalibration**: Increasing baseline minting rewards does not change total supply. It accelerates the release of rewards that would eventually be released anyway, which increases the incentive for current participants to maintain storage commitments.

### Attack Vectors

1. **Flash loan power**: An adversary could theoretically acquire FIL, commit CC sectors with high multiplier, win blocks, and terminate. The 7-day lockup makes this economically infeasible (capital locked for 7 days for a probabilistic block reward).

2. **Multiplier front-running**: Before Phase 1 takes effect, SPs might rush to commit sectors at 10x. This is expected and harmless — these sectors are grandfathered and will naturally expire.

3. **Supply shock from reserve burn**: The reserve tokens are not in circulation and their removal does not change FIL_CirculatingSupply. There is no supply shock.

## Incentive Considerations

### For Storage Providers

- **CC miners**: Immediately benefit from zero termination fees (can exit unprofitable sectors) and higher baseline minting (more reward per TiB). The multiplier reduction gradually increases their share of block rewards as QAP from verified deals shrinks.
- **Deal-based SPs**: Short-term reduction in QAP advantage, but gains from lower pledge requirements (as total QAP decreases) and increased ability to charge market rates for storage (no longer competing against subsidized self-dealing).
- **New entrants**: Dramatically lower barriers — no need to navigate the DataCap bureaucracy, lower collateral requirements, clearer economics.

### For the Token

- **Circulating supply**: Reserve burn removes ~282.9M FIL from total supply. Baseline recalibration modestly increases near-term minting but within the same total cap.
- **Pledge dynamics**: As VDWM decreases, total locked pledge decreases (lower QAP = lower consensus pledge per sector). This releases FIL to circulation but at a gradual, predictable rate.
- **Deflationary pressure**: Gas burning continues. The reserve burn is a one-time deflationary event.

### For Data Clients

- **No disruption to existing deals**: Grandfathering protects all current storage commitments.
- **Long-term benefit**: As the multiplier reaches 1x, SPs are incentivized to seek paying clients rather than gaming DataCap. This creates a real market for storage services.
- **FOC/PDP compatibility**: Filecoin Onchain Cloud services (PDP, warm storage, Filecoin Pay) do not depend on the 10x multiplier and will function identically under sector parity.

## Product Considerations

### Enabling Permissionless Storage Markets

With sector parity (VDWM=1x), the protocol no longer prescribes which data is "valuable." This opens the door for:

- **FVM-based markets**: Smart contracts can define their own quality criteria, multipliers, and incentive structures without protocol-level permission.
- **PDP-based warm storage**: The FOC stack (PDP, FWSS, Filecoin Pay) provides cryptographic proof of data possession without relying on the 10x multiplier for economic viability.
- **Application-layer incentives**: Programs like Slingshot, AI dataset curation, or public goods storage can be funded through grants or FVM contracts, rather than by taxing CC miners through the power table.

### Simplifying the SP Experience

The current experience of operating a Filecoin storage provider is burdened by DataCap acquisition, notary relationships, and the complexity of deal-dependent power calculations. This FIP simplifies the economics to: commit storage → earn rewards proportional to storage → optionally serve paying clients for additional revenue.

### Alignment with FOC

The Filecoin Onchain Cloud (FOC) architecture — comprising PDP verification, Filecoin Pay streaming payments, and the FWSS warm storage service — was designed independently of the 10x multiplier. This FIP's changes are fully compatible with and complementary to FOC:

- PDP provides trustless proof of data possession (replacing the social trust of DataCap)
- Filecoin Pay enables direct client-to-provider payments (replacing the subsidy of the multiplier)
- Both systems benefit from the simplified, predictable economics of sector parity

## Implementation

### Repositories Requiring Changes

| Repository | Changes | Scope |
|-----------|---------|-------|
| `filecoin-project/builtin-actors` | Multiplier schedule, CC termination, pledge lockup, baseline rate | Core actor changes |
| `filecoin-project/go-state-types` | New constants, state types for lockup queue, invariant check update | State migration |
| `filecoin-project/ref-fvm` | No changes expected | — |
| `filecoin-project/lotus` | Node upgrade, migration code, API exposure of lockup state | Node implementation |
| `filecoin-project/curio` | Node upgrade | Node implementation |
| `ChainSafe/forest` | Node upgrade, migration code | Node implementation |

### Migration Plan

The state migration at upgrade epoch must:

1. Read f090 balance and transfer to f099.
2. Update TotalFilecoin constant.
3. Set new baseline growth rate in reward actor state.
4. Initialize the multiplier schedule with activation epoch.
5. Add empty PledgeLockupQueue to all miner states.

This is comparable in scope to previous network upgrade migrations (e.g., nv22 Dragon, nv23 Waffle).

### Tracking

- [ ] `builtin-actors` PR: Multiplier schedule in miner actor
- [ ] `builtin-actors` PR: CC termination reform in miner actor  
- [ ] `builtin-actors` PR: Baseline recalibration in reward actor
- [ ] `go-state-types` PR: State migration for f090 burn and new types
- [ ] `lotus` PR: Migration integration and API updates
- [ ] `curio` PR: Migration integration
- [ ] Calibration net deployment and testing
- [ ] Community review period

## TODO

- [ ] Precise computation of new TotalFilecoin constant at the migration epoch
- [ ] Gas benchmarking for the PledgeLockupQueue operations
- [x] Economic modeling: simulate multiplier reduction impact on QAP, pledge, and minting rate across all phases — **COMPLETE** (CUDA simulation, 12 scenarios × 3,650 days + 210-point parameter sweep = 44,850 data points. [Source](https://github.com/Reiers/super-fip-sim))
- [ ] Formal security analysis: validate the 7-day lockup against flash power attack models
- [ ] Calibration network testing of all four changes
- [ ] Coordinate with FIP editors for number assignment
- [ ] Open GitHub Discussion for community review

## Simulation Methodology

The economic claims in this FIP are supported by a numerical simulation validated against the Filecoin protocol specification.

**Implementation:** CUDA C++ executed on an NVIDIA RTX 5080 GPU (Blackwell architecture, 84 SMs). Source code: [github.com/Reiers/super-fip-sim](https://github.com/Reiers/super-fip-sim).

**Calibration (genesis → current epoch):**
1. Computed cumulative capped raw-byte power `R̄_Σ` from genesis (epoch 0) to the current epoch (5,796,404) using 10 historical RBP data points interpolated linearly, stepping in daily (2,880-epoch) increments.
2. Derived effective network time `θ = (1/g) · ln(g · R̄_Σ / b₀ + 1)` per the spec formula.
3. Cross-validated: simple minting at current epoch = 155.46M FIL (within 1% of chain state); baseline minted = 246.31M FIL; total = 401.78M FIL.

**Forward projection:**
4. From current state, projected 10 years forward under 12 named scenarios and 210 parameter sweep combinations (VDWM × RBP trend × baseline growth).
5. Each scenario steps day-by-day, tracking: daily issuance, per-sector rewards, pledge components, circulating supply, and ROI.
6. For baseline recalibration scenarios: the effective_time formula uses `G_DEFAULT` (since θ remains in the historical baseline regime where g was unchanged), while the forward baseline for pledge uses `b_current × exp(g_new × elapsed_epochs)`.

**Key validation:** Daily issuance is identical (to 8 significant figures) across all VDWM values at every time step — confirming analytically and numerically that the multiplier does not affect total minting.

**Data:** 12 scenario CSVs (3,650 daily data points each) + 210-point parameter sweep × 5 checkpoints. Total: 44,850 data points. All results are reproducible from the published source code.

## References

| Reference | Description |
|-----------|-------------|
| [FIP-0003](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0003.md) | Filecoin Plus (original verified client mechanism) |
| [FIP-0076](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0076.md) | Direct Data Onboarding |
| [FIP-0098](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0098.md) | Simplified termination fees |
| [FIP-0080](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0080.md) | Scheduled reduction of Fil+ multiplier (Draft) |
| [FIP-0078](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0078.md) | Unrestricted datacap minting (Draft) |
| [FIP-0093](https://github.com/filecoin-project/FIPs/pull/1039) | Set mining reserve to zero (Draft) |
| [Discussion #774](https://github.com/filecoin-project/FIPs/discussions/774) | FIP-0080 community discussion (57 comments) |
| [Discussion #844](https://github.com/filecoin-project/FIPs/discussions/844) | FIP-0078 community discussion (22 comments) |
| [Discussion #972](https://github.com/filecoin-project/FIPs/discussions/972) | Zero CC termination discussion |
| [Discussion #1237](https://github.com/filecoin-project/FIPs/discussions/1237) | Community call for urgent reform |
| [Filecoin Spec](https://spec.filecoin.io) | Protocol specification |
| [Filecoin Mission](https://github.com/filecoin-project/FIPs/blob/master/mission.md) | Network mission statement |
| [Token Allocation](https://spec.filecoin.io/#section-systems.filecoin_token.token_allocation) | Mining reserve specification |
| [Minting Model](https://spec.filecoin.io/#section-systems.filecoin_token.minting_model) | Baseline and simple minting |
| [Sector Quality](https://spec.filecoin.io/#section-systems.filecoin_mining.sector.sector-quality) | Quality-adjusted power specification |
| [CryptoEconomics](https://spec.filecoin.io/#section-algorithms.cryptoecon) | Economic parameters |
| [@irenegia WindowPoSt analysis](https://drive.google.com/file/d/1notObdkPT1BCztgspIpzSUAzWSrM8h81/view) | Formal security analysis of termination fees |
| [Economic Simulation](https://github.com/Reiers/super-fip-sim) | CUDA simulation: 12 scenarios, 44,850 data points (RTX 5080) |
| [FIP-0100](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0100.md) | Per-sector daily fee (batch balancer removal) |

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
