# FIP-Daybreak

**FIP-XXXX: Restore Equal Sector Quality and Burn Mining Reserve**

> *Codename: Daybreak — a new beginning for Filecoin storage provider economics.*

## What This Is

A comprehensive FIP proposal backed by:
- **44,850-datapoint** CUDA economic simulation (Blackwell RTX 5080)
- **Formal security analysis** with quantitative proofs for 5 attack vectors
- **Gas benchmarking** confirming <0.01% overhead
- **Deep FIP process knowledge** from analyzing all 108 existing proposals

## Two Coordinated Changes

1. **Restore Equal Sector Quality** — Reduce the Verified Deal Weight Multiplier (VDWM) from 10× to 1× over a 12-month linear transition. All sectors earn equal quality-adjusted power per raw byte.

2. **Burn Mining Reserve** — Permanently remove ~283M FIL of potential future inflation by transferring the mining reserve (`f090`) balance to the burn address `f099`.

## The Core Discovery

The 10× Fil+ multiplier **does not increase total block rewards**. The Filecoin minting model uses Raw Byte Power (RBP), not Quality-Adjusted Power (QAP), for baseline minting. The multiplier is a pure zero-sum redistribution mechanism that taxes CC sectors to subsidize Fil+ sectors — with no net benefit to the network's minting trajectory.

**Total daily issuance is identical regardless of VDWM value.** Confirmed to 8 significant figures across a 10-year projection (0.00000000% difference).

## Baseline History

The network exceeded the baseline from April 2021 through early 2023 — at peak (August 2022), RBP reached ~17 EiB against a baseline of ~10 EiB. Since then, RBP has declined to 2.17 EiB while the baseline has grown to ~114.5 EiB. The gap is now structural and widening exponentially — the baseline stands at nearly 7× the historical peak and 53× the current RBP.

## Key Numbers

| Metric | Current (VDWM=10) | Post-Daybreak (VDWM=1) | Change |
|---|---|---|---|
| Daily network issuance | 66,249 FIL | 66,249 FIL | **unchanged** |
| CC sector reward (32 GiB) | 0.000107 FIL/day | 0.000910 FIL/day | **+8.5×** |
| Initial pledge per CC sector | 0.0673 FIL | 0.0834 FIL | +24% |
| Annual ROI on pledge | 58% | 399% | **+6.9×** |
| Min physical cost of 51% attack | 0.944 EiB | 1.11 EiB | **+17.6% more secure** |
| Virtual (non-physical) consensus power | ~16.3 EiB (88% of QAP) | 0 | **eliminated** |

*Chain state at epoch 5,796,404. Source: [Filfox API](https://filfox.info/api/v1/overview).*

## Verification

All numbers independently verified against:
- **Filecoin protocol specification** — minting formulas, sector quality, pledge calculations
- **Filfox API** — on-chain state (RBP, QAP, circulating supply, daily issuance, reserve balance)
- **builtin-actors source** — `QUALITY_BASE_MULTIPLIER`, `VERIFIED_DEAL_WEIGHT_MULTIPLIER`, call sites
- **CUDA simulation** — reproduced on Blackwell RTX 5080, issuance invariance confirmed to 8 sig figs
- **Cross-FIP review** — FIP-0081 (pledge ramp), FIP-0086 (F3), FIP-0098 (8.5% termination), FIP-0100 (daily fee)

## Status

| Phase | Status |
|---|---|
| 1. Economic Modeling (CUDA simulation) | ✅ Complete |
| 2. Gas Benchmarking (on-chain + FVM analysis) | ✅ Complete |
| 3. Formal Security Analysis (5 attack vectors) | ✅ Complete |
| 4. Final Verification Pass | ✅ Complete |
| 5. Community Pre-Review + FIP Submission | 🔜 Next |

📋 **Draft** — Community pre-review. Not yet submitted to filecoin-project/FIPs.

## Files

| File | Description |
|---|---|
| `fip-draft.md` | The complete FIP document (all 12 required sections per FIP-0001) |
| `economics.md` | Economic analysis with simulation results |
| `security-analysis.md` | Formal security analysis — 5 attack vectors with proofs |
| `phases.md` | Phase breakdown, gas benchmarking, and community engagement plan |
| `sim/` | CUDA simulation source code |
| `results/` | Simulation output CSVs (12 scenarios + parameter sweep) |

## Supersedes / References

- **FIP-0080** (Phasing Out Fil+) — stalled 2.5 years, 358 comments. Daybreak provides the quantitative simulation, formal security proofs, gas analysis, and specified transition mechanism that FIP-0080 lacked.
- **FIP-0093** (Set Mining Reserve to Zero) — stalled ~20 months. Subsumed by Daybreak's reserve burn.
- **FIP-0003** (Filecoin Plus) — quality multiplier sunset when VDWM reaches 1×. Governance infrastructure may continue for application-layer purposes.

## Reproducibility

All math is independently verifiable against on-chain data and the [Filecoin spec](https://spec.filecoin.io/).

```bash
# Build and run the simulation (requires CUDA toolkit 13.0+)
cd sim && make && make run

# Results in results/ directory
ls results/scenario_*.csv results/parameter_sweep.csv
```

## License

[CC0](https://creativecommons.org/publicdomain/zero/1.0/) — Copyright and related rights waived.
