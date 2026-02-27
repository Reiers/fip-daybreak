# FIP Discussion: Daybreak — Restore Equal Sector Quality and Burn Mining Reserve

**Full proposal:** [Reiers/fip-daybreak](https://github.com/Reiers/fip-daybreak) — FIP draft, economic simulation, security analysis, gas benchmarking

---

## TL;DR

Two coordinated changes:

1. **Reduce the Verified Deal Weight Multiplier (VDWM) from 10× to 1×** over a 12-month linear transition
2. **Burn the mining reserve (~283M FIL)** by transferring `f090` to `f099`

## The Core Discovery

The 10× Fil+ multiplier **does not increase total block rewards**. Filecoin's minting model uses Raw Byte Power (RBP), not Quality-Adjusted Power (QAP), for baseline minting. The multiplier is a pure zero-sum redistribution — it taxes CC sectors to subsidize Fil+ sectors with no net benefit to minting.

Total daily issuance is identical regardless of VDWM value. Confirmed to 8 significant figures across a 10-year CUDA simulation (44,850 data points).

## Key Numbers

| Metric | Current (VDWM=10) | Post-Daybreak (VDWM=1) | Change |
|---|---|---|---|
| Daily network issuance | 66,249 FIL | 66,249 FIL | **unchanged** |
| CC sector reward (32 GiB) | 0.000107 FIL/day | 0.000910 FIL/day | **+8.5×** |
| Initial pledge per CC sector | 0.0673 FIL | 0.0834 FIL | +24% |
| Annual ROI on pledge | 58% | 399% | **+6.9×** |
| Min physical cost of 51% attack | 0.944 EiB | 1.11 EiB | **+17.6% more secure** |
| Virtual (non-physical) consensus power | ~16.3 EiB (88% of QAP) | 0 | **eliminated** |

## What's Different From FIP-0080

This proposal builds on the work started by FIP-0080 (Fatman13, ArthurWang1255, stuberman, Eliovp, dcasem, The-Wayvy) and FIP-0093 (dcasem). What's new:

| | FIP-0080 | FIP-Daybreak |
|---|---|---|
| Economic analysis | Qualitative arguments | Quantitative CUDA simulation (44,850 data points, [open source](https://github.com/Reiers/fip-daybreak/tree/main/sim)) |
| Security analysis | Not provided | [Formal analysis](https://github.com/Reiers/fip-daybreak/blob/main/security-analysis.md) — 5 attack vectors with quantitative bounds |
| Gas impact | Not analyzed | <0.01% overhead — [benchmarked against on-chain data](https://github.com/Reiers/fip-daybreak/blob/main/gas-benchmarking.md) |
| Transition mechanism | Unspecified | 12-month linear interpolation with specified epoch constants |
| Migration cost | Unspecified | Lightest of any recent core FIP (zero sector iteration, one balance transfer) |

## Baseline Context

The network exceeded the baseline from April 2021 through early 2023. At peak (August 2022), RBP reached ~17 EiB against a baseline of ~10 EiB. Since February 2023, RBP has been below the baseline and declining — now at 2.17 EiB against a baseline of ~114.5 EiB (1.9%). The gap is structural and widening exponentially.

The mining reserve holds ~283M FIL allocated for "future incentives" with no defined mechanism or timeline. Burning it removes a permanent overhang of potential inflation.

## Security

Consensus security **improves** by 17.6%. Currently, ~16.3 EiB of QAP (88%) is virtual — it doesn't correspond to physical storage. Removing virtual power means every unit of consensus power requires real hardware. The minimum physical cost of a 51% attack rises from 0.944 EiB to 1.11 EiB.

Full formal security analysis covering 5 attack vectors: [security-analysis.md](https://github.com/Reiers/fip-daybreak/blob/main/security-analysis.md)

## Implementation

The core change is ~15 lines in `actors/miner/src/policy.rs` (builtin-actors) — a linear interpolation of `VERIFIED_DEAL_WEIGHT_MULTIPLIER` from 100 to 10 (code values) over 1,051,200 epochs. Plus a one-time `Send` from `f090` to `f099` in the migration actor.

Existing sectors keep their original quality until expiry or renewal. No sector iteration at migration. No CronTick changes. No WindowPoSt changes.

## Transparency

This proposal was developed with AI assistance (Claude) for economic modeling, code analysis, and drafting. All numbers are independently verifiable against on-chain data and the [Filecoin spec](https://spec.filecoin.io/). The CUDA simulation source code is [open](https://github.com/Reiers/fip-daybreak/tree/main/sim).

---

**Full FIP draft (all 12 sections per FIP-0001):** [fip-draft.md](https://github.com/Reiers/fip-daybreak/blob/main/fip-draft.md)

I'm looking for feedback on the economic model, security analysis, and transition design. If there are attack vectors I haven't considered or numbers that don't match your understanding of the protocol, I want to hear about them.
