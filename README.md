# FIP-Daybreak

**FIP-XXXX: Restore Equal Sector Quality and Burn Mining Reserve**

> *Codename: Daybreak — a new beginning for Filecoin storage provider economics.*

## What This Is

A comprehensive FIP proposal backed by:
- **44,850-datapoint** CUDA economic simulation (Blackwell RTX 5080)
- **Formal security analysis** with quantitative proofs for 5 attack vectors
- **Gas benchmarking** confirming < 0.01% overhead
- **Deep FIP process knowledge** from analyzing all 108 existing proposals

## Two Coordinated Changes

1. **Restore Equal Sector Quality** — Reduce the Verified Deal Weight Multiplier (VDWM) from 10× to 1× over a 12-month linear transition. All sectors earn equal quality-adjusted power per raw byte.

2. **Burn Mining Reserve** — Permanently remove 300M FIL of potential future inflation by transferring the mining reserve balance to the burn address `f099`.

## The Core Discovery

The 10× Fil+ multiplier **does not increase total block rewards**. The Filecoin minting model uses Raw Byte Power (RBP), not Quality-Adjusted Power (QAP), for baseline minting. The multiplier is a pure zero-sum redistribution mechanism that taxes CC sectors to subsidize Fil+ sectors — with no net benefit to the network's minting trajectory.

**Total daily issuance is identical regardless of VDWM value.** Proven mathematically and by simulation.

## Key Numbers

| Metric | Current (VDWM=10) | Post-Daybreak (VDWM=1) | Change |
|---|---|---|---|
| Daily network issuance | 66,019 FIL | 66,019 FIL | **unchanged** |
| CC sector reward (32 GiB) | 0.000107 FIL/day | 0.000910 FIL/day | **+8.5×** |
| Initial pledge per CC sector | 0.0673 FIL | 0.0834 FIL | +24% |
| Annual ROI on pledge | 58% | 399% | **+6.9×** |
| Min physical cost of 51% attack | 0.944 EiB | 1.107 EiB | **+17.6% more secure** |

## Status

| Phase | Status |
|---|---|
| 1. Economic Modeling (CUDA simulation) | ✅ Complete |
| 2. Gas Benchmarking (on-chain + FVM analysis) | ✅ Complete |
| 3. Formal Security Analysis (5 attack vectors) | ✅ Complete |
| 4. Community Pre-Review + FIP Submission | 🔜 Next |

🔒 **Private** — Working draft. Not yet submitted to filecoin-project/FIPs.

## Files

| File | Description |
|---|---|
| `fip-draft.md` | The complete FIP document (all 12 required sections per FIP-0001) |
| `economics.md` | Economic analysis with simulation results |
| `security-analysis.md` | Formal security analysis — 5 attack vectors with proofs |
| `gas-benchmarking.md` | Gas impact analysis from on-chain data + FVM price list |
| `phases.md` | Phase breakdown and community engagement plan |
| `sim/` | CUDA simulation source code |
| `results/` | Simulation output CSVs (12 scenarios + parameter sweep) |

## Supersedes / References

- **FIP-0080** (Phasing Out Fil+) — stalled 2.5 years, 358 comments. Daybreak provides the quantitative analysis and transition mechanism FIP-0080 called for.
- **FIP-0093** (Set Mining Reserve to Zero) — stalled 14 months. Subsumed by Daybreak's reserve burn.
- **FIP-0003** (Filecoin Plus) — effectively superseded when VDWM reaches 1×.

## Reproducibility

```bash
# Build and run the simulation (requires CUDA toolkit 13.0+)
cd sim && make && make run

# Results in results/ directory
ls results/scenario_*.csv results/parameter_sweep.csv
```

## License

[CC0](https://creativecommons.org/publicdomain/zero/1.0/) — Copyright and related rights waived.
