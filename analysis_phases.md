# Super FIP — Phase Breakdown

## Phase 1: Economic Modeling ✅ COMPLETE

**Deliverable:** CUDA simulation validated against spec, 12 scenarios + 210 parameter sweep

### What we proved:
1. **VDWM doesn't affect total minting** — baseline uses RBP, not QAP. Mathematical proof + simulation.
2. **CC sector revenue increases 8.5x** when VDWM goes from 10 to 1 (same total issuance, fewer QAP competing).
3. **Consensus pledge unchanged** — baseline (114 EiB) >> QAP in all scenarios, so max(baseline, QAP) = baseline.
4. **Storage pledge increases 24%** — because daily reward per sector is higher, and storage pledge = 20 days of reward.
5. **Net ROI improvement: 58% → 399% annual** on pledge for CC sectors.
6. **Baseline growth should stay at 100%** — slowing it counterproductively increases pledge.
7. **Mining reserve burn is economically neutral** but removes 300M FIL inflation risk.
8. **1-year linear transition is optimal** — matches immediate removal at completion, smooth for SPs.

### Files:
- `sim/filecoin_econ_sim.cu` — CUDA source (Blackwell RTX 5080)
- `results/scenario_*.csv` — 12 scenario trajectories (3,650 days each)
- `results/parameter_sweep.csv` — 210 parameter combinations × 5 checkpoints
- `economics.md` — Full analysis and mathematical proof

---

## Phase 2: Gas Benchmarking for Pledge Lockup Queue

**Status:** NOT STARTED
**Estimated effort:** 2-3 days
**Prerequisites:** Phase 1 (complete), Calibration testnet access

### Objective
Benchmark gas costs for the proposed pledge adjustment mechanism during the 12-month VDWM transition.

### What needs benchmarking:
1. **PreCommitSector with modified quality calculation** — Sectors committed during transition use interpolated VDWM. Need to measure gas delta vs current PreCommit.
2. **ProveCommitSector pledge calculation** — Pledge formula unchanged, but storage pledge component changes with reward. Gas impact should be zero (same computation).
3. **WindowPoSt** — Unchanged by proposal (power table tracking is separate from quality calculation).
4. **CronTick for quality re-evaluation** — IF we retroactively adjust existing sectors' quality (option A), the CronTick cost per deadline increases. IF we grandfather existing sectors (option B), no CronTick change.

### Design decision needed:
**Option A: Retroactive** — All sectors' quality adjusted at each transition step. High gas cost (batch update all power entries). Fairer but expensive.
**Option B: Grandfathered** — Existing sectors keep original quality until expiry/renewal. New sectors use interpolated VDWM. Zero gas overhead but creates two classes of sectors.
**Option C: Hybrid** — Existing sectors' quality updated only at their next WindowPoSt deadline. Distributes gas cost over 48 deadlines (24 hours). Best tradeoff.

### Approach:
1. Fork builtin-actors, implement quality interpolation in `miner_actor.rs`
2. Deploy to local devnet
3. Measure gas for PreCommit, ProveCommit, WindowPoSt with N sectors at various transition points
4. Extrapolate to mainnet scale (923 active miners, ~2.17 EiB)

### Key gas constraints:
- Block gas limit: 10B gas
- Single message limit: ~1.5B gas (practical)
- Current WindowPoSt: ~200-400M gas per partition
- CronTick budget: must not exceed block limit across all miners in one epoch

### Use Blackwell for:
- Running calibration node (lotus-miner) in docker
- Automating gas measurements across transition parameters
- Statistical analysis of gas distribution

---

## Phase 3: Formal Security Analysis of 7-Day Lockup

**Status:** NOT STARTED
**Estimated effort:** 3-5 days
**Prerequisites:** Phase 2 (gas benchmarks inform lockup design)

### Objective
Prove that the 7-day pledge lockup period (between VDWM transition steps) is sufficient to prevent economic attacks.

### Attack vectors to analyze:

#### 3.1 Flash power attack
**Threat:** Attacker rapidly onboards CC sectors during transition to capture outsized reward share, then terminates.
**Mitigation:** Existing initial pledge + termination fee. 
**Analysis needed:** Calculate maximum extractable value vs pledge cost at each transition step. Prove pledge always exceeds potential exploit.

#### 3.2 Quality arbitrage
**Threat:** Actors game transition timing — convert Fil+ sectors to CC right before multiplier drops (to lock in higher reward at lower quality cost).
**Mitigation:** Quality change only takes effect at next proving deadline (Option C).
**Analysis needed:** Model optimal arbitrage strategy, prove net gain is bounded.

#### 3.3 Notary front-running
**Threat:** Notaries issue datacap right before transition step to maximize Fil+ benefit in remaining window.
**Mitigation:** VDWM reduction is gradual (linear), so each step reduces benefit marginally.
**Analysis needed:** Model notary incentive at each transition point.

#### 3.4 Mining reserve interaction
**Threat:** If reserve burn and VDWM change happen simultaneously, compound effects could create unexpected economic shocks.
**Mitigation:** Reserve burn is supply-neutral (reserve not circulating). VDWM change is issuance-neutral (proven in Phase 1).
**Analysis needed:** Prove independence of the two changes.

### Formal methods:
- Model the transition as a Markov chain over (epoch, VDWM, RBP, pledge_locked) states
- Prove: for all states reachable during transition, no actor can extract value > their pledge
- Prove: 7-day lockup provides sufficient settlement finality for pledge adjustments
- Use F3 fast finality (30s) to argue that 7 days = ~20,160 epochs provides ~20,000x safety margin

### Deliverable:
Security analysis document (LaTeX or Markdown) with:
- Threat model (Byzantine SP, malicious notary, colluding cartel)
- Formal proofs for bounded extractable value
- 7-day lockup justification with quantitative bounds
- Comparison to existing Filecoin security parameters (42-day fault termination, 180-day vesting)

---

## Phase 4: Calibration Net Testing

**Status:** NOT STARTED  
**Estimated effort:** 1-2 weeks
**Prerequisites:** Phase 2 (gas benchmarks), Phase 3 (security analysis)

### Objective
Deploy and test the full proposal on Filecoin Calibration testnet before mainnet.

### Test plan:

#### 4.1 Environment setup
- Deploy modified lotus + builtin-actors to calibration
- Setup 3+ test SPs with varied configurations:
  - SP-A: 100% CC sectors
  - SP-B: 100% Fil+ sectors
  - SP-C: Mixed 50/50

#### 4.2 Transition testing (7 days compressed)
- Deploy FIP activation at epoch N
- Verify VDWM interpolation at each step
- Measure: block rewards per SP, pledge changes, gas costs
- Verify: total issuance matches expected (unchanged)

#### 4.3 Edge case testing
- Sector committed mid-transition step
- Sector extension during transition
- Sector termination during transition
- Snap deal (CC → data) during transition
- WindowPoSt across transition boundary
- Multiple miners hitting deadline simultaneously

#### 4.4 Regression testing
- Full lotus test suite passes
- builtin-actors test suite passes
- F3 finality unaffected
- Message pool behavior unchanged
- Chain sync unaffected

#### 4.5 Performance metrics
- Block production time (must stay <30s)
- CronTick gas budget
- State tree size impact
- Tipset weight calculation (uses QAP)

### Deliverable:
Test report with pass/fail for all test cases, gas measurements, performance benchmarks.

---

## Phase 5: Community Pre-Review

**Status:** NOT STARTED
**Estimated effort:** 2-4 weeks
**Prerequisites:** Phases 1-4 complete

### Objective
Build consensus BEFORE submitting the FIP. This is the #1 reason community FIPs fail (see governance analysis).

### Strategy:

#### 5.1 Pre-FIP discussion (Week 1-2)
- Post in FIPs GitHub Discussions with:
  - Economic simulation results (with reproducible code)
  - Security analysis summary
  - Calibration test results
  - Clear problem statement: "The 10x multiplier doesn't increase total rewards"
- Cross-post summary to:
  - `#fil-fips` Slack channel
  - `#fil-foc` Slack channel (FOC team affected)
  - Filecoin governance forum
  
#### 5.2 Target audience engagement (Week 2-3)
- **Pro-reform faction:** Fatman13, dcasem, The-Wayvy, Eliovp, ArthurWang1255 — they'll support immediately. Get their explicit endorsement.
- **Technical gatekeepers:** anorth, rvagg, jennijuju — engage with data, not emotion. Our simulation code speaks louder than arguments.
- **CryptoEconLab:** tmellan — challenge them to dispute the math (they can't, it's from their own spec).
- **Chinese community:** via Fatman13 — ensure Chinese SPs understand the benefit.

#### 5.3 Address predictable objections (Week 3-4)
| Objection | Response |
|---|---|
| "Fil+ incentivizes useful storage" | Data shows 90%+ gaming. Multiplier doesn't increase total rewards. Real demand pays via markets. |
| "CC sectors don't contribute value" | CC sectors contribute storage capacity and security. The multiplier doesn't change total capacity. |
| "SPs will leave if rewards change" | CC sector rewards INCREASE 8.5x. Only Fil+ gaming operations are harmed. |
| "This changes network economics" | Total issuance is UNCHANGED. Only redistribution changes. Mathematically proven. |
| "Need CryptoEconLab analysis" | Our simulation IS the analysis. Code is public. Challenge them to find errors. |
| "Need voting tool first" | This FIP addresses a pure technical parameter change. No novel governance needed. |

#### 5.4 FIP submission
- Format per FIP-0001 template (all 12 required sections)
- Include: simulation code, results CSV, security analysis, test report
- Open as PR to `filecoin-project/FIPs`
- Request FIP number from editors

### Key principle:
**Never submit without pre-consensus.** The governance analysis shows that community FIPs without prior coalition-building get stuck in limbo. We build the coalition first, then submit when support is clear.

---

## Timeline

| Phase | Duration | Dependencies | Deliverable |
|---|---|---|---|
| 1. Economic Modeling | ✅ Done | — | Simulation + analysis |
| 2. Gas Benchmarking | 2-3 days | Phase 1 | Gas measurements |
| 3. Security Analysis | 3-5 days | Phase 2 | Formal proofs |
| 4. Calibration Testing | 1-2 weeks | Phase 2, 3 | Test report |
| 5. Community Pre-Review | 2-4 weeks | Phase 1-4 | Coalition + FIP PR |

**Total estimated: 5-9 weeks to FIP submission**

Phases 2-3 can partially overlap. Phase 4 requires modified lotus (implementation work).
Phase 5 can begin soft outreach during Phase 4.
