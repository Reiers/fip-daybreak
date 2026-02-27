# FIP-Daybreak — Gas Benchmarking

## Summary

FIP-Daybreak adds **< 0.01% gas overhead** to any affected operation. WindowPoSt and CronTick have **zero** gas change. The state migration is the lightest of any recent core FIP.

---

## On-Chain Gas Measurements

Source: Filfox API, epoch ~5,796,499.

| Method | Batch Size | Gas Used | Calls `quality_for_weight()` |
|---|---|---|---|
| `SubmitWindowedPoSt` | 1 partition | 24,057,352 | **No** — proves sector existence only |
| `PreCommitSectorBatch2` | 4 sectors | ~120,000,000 | Yes — for deposit calculation |
| `ProveCommitSectors3` | 3 sectors | ~530,000,000 | Yes — for pledge calculation |
| `ExtendSectorExpiration2` | varies | ~15–50,000,000 | Yes — for quality re-evaluation |
| `ProveReplicaUpdates3` | varies | ~200–600,000,000 | Yes — for updated quality |
| `CronTick` | per-deadline | ~10–50,000,000 | **No** — grandfathering approach |

## Code Change

The only change is replacing a static constant with an epoch-aware function in `actors/miner/src/policy.rs`:

**Before:**
```rust
lazy_static! {
    pub static ref VERIFIED_DEAL_WEIGHT_MULTIPLIER: BigInt = BigInt::from(100);
}
```

**After:**
```rust
pub fn verified_deal_weight_multiplier_at(epoch: ChainEpoch) -> BigInt {
    if epoch < VDWM_TRANSITION_START { return BigInt::from(100); }
    let elapsed = epoch - VDWM_TRANSITION_START;
    if elapsed >= VDWM_TRANSITION_DURATION { return BigInt::from(10); }
    let duration = BigInt::from(VDWM_TRANSITION_DURATION);
    let numer = BigInt::from(100) * &duration - BigInt::from(90) * BigInt::from(elapsed);
    std::cmp::max(numer / duration, BigInt::from(10))
}
```

## Additional Operations Per Call

| Operation | WASM Instructions | Gas (@ 4 gas/inst) |
|---|---|---|
| Epoch comparison | 1 | 4 |
| Subtraction | 1 | 4 |
| Comparison | 1 | 4 |
| BigInt multiply (100 × duration) | 12–25 | 48–100 |
| BigInt multiply (90 × elapsed) | 12–25 | 48–100 |
| BigInt subtraction | 3–5 | 12–20 |
| BigInt division | 15–30 | 60–120 |
| BigInt max | 1 | 4 |
| **Total** | **46–89** | **~180–350 gas** |

Post-transition (early return path): **~4–8 gas total**.

## Gas Delta

| Method | Current Gas | Added Gas | Overhead |
|---|---|---|---|
| `SubmitWindowedPoSt` | 24,057,352 | **0** | 0% |
| `PreCommitSectorBatch2` (4) | ~120,000,000 | ~1,200 | 0.0010% |
| `ProveCommitSectors3` (3) | ~530,000,000 | ~900 | 0.00017% |
| `ExtendSectorExpiration2` (10) | ~50,000,000 | ~3,000 | 0.006% |
| `CronTick` | ~10–50,000,000 | **0** | 0% |

## State Migration

**Zero sector iteration** — the lightest migration of any recent core FIP:

| Daybreak Migration | nv25 Teep Migration (FIP-0098/0100) |
|---|---|
| No miner actor iteration | Iterated **every** miner |
| No deadline traversal | Loaded **every** deadline (48/miner) |
| No partition traversal | Loaded **every** partition |
| One balance transfer: $f_{090} \to f_{099}$ | Summed LivePower, added DailyFee field |
| Estimated: < 1 second | Estimated: minutes |

Reserve burn gas: ~1,956,000 gas (system actor operation during migration).

## Comparison to Recent FIPs

| FIP | Gas Impact |
|---|---|
| FIP-0098 (Simple Termination Fee) | Slight reduction — simplified formula |
| FIP-0100 (Daily Proof Fee) | **New cost added** — ~500–1,000 gas/sector |
| FIP-0081 (Pledge Ramp) | **Increased** — added gamma interpolation to pledge calc |
| FIP-0092 (NI-PoRep) | **New proof type** — 4.5M–5.7M gas per NI proof |
| **FIP-Daybreak** | **~200–350 gas/sector** — two orders of magnitude smaller |

## Code Value Clarification

| Concept | Spec Language | Code Value (`policy.rs`) |
|---|---|---|
| Quality Base Multiplier (QBM) | $1\times$ | `BigInt::from(10)` |
| Verified Deal Weight Multiplier | $10\times$ | `BigInt::from(100)` |
| Our transition target | $1\times$ (equal to QBM) | `BigInt::from(10)` |

The `quality_for_weight()` function divides by QBM at the end:

$$\text{Quality} = \frac{\text{WeightedSum} \ll 20}{\text{SectorSpaceTime} \times \text{QBM}}$$

So effective multiplier $= \frac{\text{CodeValue}}{\text{QBM}} = \frac{100}{10} = 10\times$. The interpolation transitions the code value $100 \to 10$, yielding effective $10\times \to 1\times$.
