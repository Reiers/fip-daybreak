#!/usr/bin/env python3
"""
Daybreak vs Looking Forward — Economic Comparison Simulation

Compares three scenarios over 30 months:
1. Status Quo: 10x verified multiplier, Fil+ continues
2. Daybreak: 12-month linear transition 10x→1x, mining reserve burn
3. Looking Forward (snadrus): Immediate Fil+ stop, new CC gets 10x, existing CC stays 1x

Key metrics:
- CC sector reward (per 32GiB sector per day)
- New SP onboarding cost (pledge per 32GiB CC sector)
- 51% attack cost (FIL required)
- Existing CC miner reward change
- Total locked FIL
- Network power dynamics

Author: Nicklas Reiersen (FIP-Daybreak)
Date: 2026-03-03
"""

import csv
import json
import math
import os

# =============================================================================
# Network Constants (current state, March 2026)
# =============================================================================

EIB = 2**60  # 1 EiB in bytes
SECTOR_SIZE = 32 * (2**30)  # 32 GiB
EPOCHS_PER_DAY = 2880
EPOCHS_PER_MONTH = EPOCHS_PER_DAY * 30
EPOCHS_PER_YEAR = EPOCHS_PER_DAY * 365

# Current network state
TOTAL_RBP_EIB = 2.17          # Raw Byte Power in EiB
TOTAL_QAP_EIB = 7.06          # Quality-Adjusted Power in EiB
VERIFIED_RBP_FRACTION = 0.19  # ~19% of raw power has verified deals
CC_RBP_FRACTION = 0.81        # ~81% is CC

BASELINE_EIB = 114.5          # Current baseline power
CIRCULATING_SUPPLY = 520_000_000  # FIL
MINING_RESERVE = 283_000_000  # FIL (to be burned under both proposals)

# Reward parameters (simplified — uses current reward rate)
DAILY_BLOCK_REWARDS = 264_000  # FIL/day (current approximate)

# Pledge formula (FIP-0081 corrected: γ=0.7)
# ConsensusPledge = 0.3 * SimplePledge + 0.7 * BaselinePledge
# SimplePledge = (SectorQAP / TotalQAP) * CirculatingSupply * 0.3 (30% target)
# BaselinePledge = (SectorQAP / max(TotalQAP, Baseline)) * CirculatingSupply * 0.3
GAMMA = 0.7
PLEDGE_TARGET_FRACTION = 0.3  # 30% of circulating supply

# Sector economics
AVG_SECTOR_LIFETIME_MONTHS = 30  # ~2.5 years average
MONTHLY_SECTOR_EXPIRY_RATE = 1.0 / AVG_SECTOR_LIFETIME_MONTHS  # fraction expiring per month

# Verified deal sector composition
VERIFIED_RBP_EIB = TOTAL_RBP_EIB * VERIFIED_RBP_FRACTION  # ~0.41 EiB
CC_RBP_EIB = TOTAL_RBP_EIB * CC_RBP_FRACTION              # ~1.76 EiB


# =============================================================================
# Helper Functions
# =============================================================================

def calculate_qap(rbp_eib, multiplier):
    """Calculate QAP from RBP and multiplier."""
    return rbp_eib * multiplier


def calculate_reward_per_sector_day(sector_qap_eib, total_qap_eib, daily_rewards):
    """Reward per 32GiB sector per day."""
    if total_qap_eib == 0:
        return 0
    sector_32gib_qap = (32 / (1024**2)) / (1024**2)  # 32 GiB in EiB — too small
    # Better: fraction of power
    # A single 32GiB sector's share of total QAP
    sector_qap_fraction = (32 * (2**30)) / (sector_qap_eib * EIB) if sector_qap_eib > 0 else 0
    # Wait, we need to think of this differently.
    # Reward per EiB of QAP per day:
    reward_per_eib_day = daily_rewards / total_qap_eib if total_qap_eib > 0 else 0
    return reward_per_eib_day


def calculate_pledge_per_sector(sector_multiplier, total_qap_eib, circulating, baseline_eib):
    """
    Calculate pledge for a single 32GiB sector with given multiplier.
    Returns FIL per sector.
    
    FIP-0081 formula:
    ConsensusPledge = (1-γ) * Simple + γ * Baseline
    Simple = (SectorQAP / TotalQAP) * CircSupply * 0.3
    Baseline = (SectorQAP / max(TotalQAP, BaselinePower)) * CircSupply * 0.3
    """
    sector_rbp_eib = 32 / (1024 * 1024 * 1024)  # 32 GiB in EiB = 2.98e-8
    sector_qap_eib = sector_rbp_eib * sector_multiplier
    
    if total_qap_eib == 0:
        return 0
    
    simple = (sector_qap_eib / total_qap_eib) * circulating * PLEDGE_TARGET_FRACTION
    baseline = (sector_qap_eib / max(total_qap_eib, baseline_eib)) * circulating * PLEDGE_TARGET_FRACTION
    
    consensus_pledge = (1 - GAMMA) * simple + GAMMA * baseline
    return consensus_pledge


def calculate_attack_cost(total_qap_eib, pledge_per_eib):
    """Cost to acquire 51% of network power in FIL."""
    # Need to acquire QAP equal to current total (to go from 0% to 51%)
    # Simplified: cost = total_qap * pledge_per_unit * 1.02 (need slightly over 50%)
    attack_qap = total_qap_eib * 1.02  # 51%
    return attack_qap * pledge_per_eib


# =============================================================================
# Scenario Models
# =============================================================================

def simulate_status_quo(months=30):
    """Scenario 1: Nothing changes. Fil+ continues with 10x multiplier."""
    results = []
    
    # Static — no changes
    verified_rbp = VERIFIED_RBP_EIB
    cc_rbp = CC_RBP_EIB
    
    for month in range(months + 1):
        # QAP calculation
        verified_qap = verified_rbp * 10
        cc_qap = cc_rbp * 1
        total_qap = verified_qap + cc_qap
        
        # Rewards per EiB of QAP per day
        reward_per_qap_eib = DAILY_BLOCK_REWARDS / total_qap if total_qap > 0 else 0
        
        # Per-sector rewards (32 GiB)
        cc_reward = reward_per_qap_eib  # 1x multiplier, proportional to 1 EiB
        verified_reward = reward_per_qap_eib * 10  # 10x multiplier
        
        # Pledge per new CC sector
        cc_pledge = calculate_pledge_per_sector(1, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        verified_pledge = calculate_pledge_per_sector(10, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        
        # Attack cost (simplified)
        avg_pledge_per_eib = calculate_pledge_per_sector(1, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB) / (32 / (1024*1024))
        attack_cost = total_qap * 0.51 * avg_pledge_per_eib
        
        # Total locked FIL estimate
        total_locked = (verified_rbp * verified_pledge / (32/(1024*1024))) + (cc_rbp * cc_pledge / (32/(1024*1024)))
        
        results.append({
            'month': month,
            'scenario': 'Status Quo',
            'total_rbp_eib': verified_rbp + cc_rbp,
            'total_qap_eib': total_qap,
            'cc_qap_eib': cc_qap,
            'verified_qap_eib': verified_qap,
            'cc_reward_per_eib_day': cc_reward,
            'verified_reward_per_eib_day': verified_reward,
            'cc_pledge_per_sector': cc_pledge,
            'verified_pledge_per_sector': verified_pledge,
            'new_cc_pledge': cc_pledge,  # cost for new SP to onboard
            'reward_ratio_cc_vs_current': 1.0,  # baseline
            'total_qap_share_cc': cc_qap / total_qap if total_qap > 0 else 0,
            'total_qap_share_verified': verified_qap / total_qap if total_qap > 0 else 0,
            'effective_multiplier': 10,
        })
    
    return results


def simulate_daybreak(months=30):
    """
    Scenario 2: Daybreak — 12-month linear transition 10x→1x + reserve burn.
    
    - VDWM transitions linearly from 10 to 1 over 12 months
    - Existing Fil+ sectors keep deal weight until expiry
    - New sectors use current multiplier at time of sealing
    - Mining reserve burned at activation
    """
    results = []
    transition_months = 12
    
    # Track sector cohorts
    # Existing Fil+ sectors expire over time (avg 2.5yr lifetime, some already old)
    # Simplification: existing Fil+ decays linearly over 30 months
    initial_verified_rbp = VERIFIED_RBP_EIB
    initial_cc_rbp = CC_RBP_EIB
    
    # Status quo CC reward for comparison
    sq_total_qap = initial_verified_rbp * 10 + initial_cc_rbp
    sq_cc_reward = DAILY_BLOCK_REWARDS / sq_total_qap
    
    for month in range(months + 1):
        # Current network-wide multiplier for NEW sectors
        if month <= transition_months:
            current_multiplier = 10 - (9 * month / transition_months)
        else:
            current_multiplier = 1.0
        
        # Existing Fil+ sectors decay (expire over time)
        # Assume roughly linear expiry: all gone by month 30
        remaining_verified_fraction = max(0, 1 - (month / 30))
        verified_rbp = initial_verified_rbp * remaining_verified_fraction
        
        # Existing Fil+ sectors keep their ORIGINAL 10x multiplier
        # (deal weight locked at seal time)
        legacy_verified_qap = verified_rbp * 10
        
        # CC sectors (existing keep 1x, not re-evaluated)
        # New CC sectors also get 1x (multiplier only affects verified deals)
        # Under Daybreak, CC is always 1x — the multiplier applies to DEAL WEIGHT
        cc_rbp = initial_cc_rbp  # CC stays constant (simplified)
        cc_qap = cc_rbp * 1  # CC is always 1x QAP
        
        # New sectors sealed during transition get lower verified multiplier
        # But since Fil+ onboarding effectively stops (no new DataCap under Daybreak),
        # new sectors are all CC at 1x
        # The transition multiplier affects existing verified sectors' recalculation... 
        # Actually in the implementation, existing sectors keep locked-in deal weight.
        # The multiplier change only affects new sector activation.
        # So: legacy Fil+ keeps 10x, new CC is 1x, verified_multiplier for NEW deals
        # decreases but there are no new deals (no DataCap).
        
        total_qap = legacy_verified_qap + cc_qap
        
        # Rewards
        reward_per_qap_eib = DAILY_BLOCK_REWARDS / total_qap if total_qap > 0 else 0
        cc_reward = reward_per_qap_eib  # CC at 1x
        verified_reward = reward_per_qap_eib * 10  # Legacy Fil+ at 10x
        
        # Pledge for new CC sector
        cc_pledge = calculate_pledge_per_sector(1, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        
        # Pledge for new verified sector (at current multiplier — academic since no new DataCap)
        new_verified_pledge = calculate_pledge_per_sector(current_multiplier, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        
        results.append({
            'month': month,
            'scenario': 'Daybreak',
            'total_rbp_eib': verified_rbp + cc_rbp,
            'total_qap_eib': total_qap,
            'cc_qap_eib': cc_qap,
            'verified_qap_eib': legacy_verified_qap,
            'cc_reward_per_eib_day': cc_reward,
            'verified_reward_per_eib_day': verified_reward,
            'cc_pledge_per_sector': cc_pledge,
            'verified_pledge_per_sector': new_verified_pledge,
            'new_cc_pledge': cc_pledge,
            'reward_ratio_cc_vs_current': cc_reward / sq_cc_reward if sq_cc_reward > 0 else 0,
            'total_qap_share_cc': cc_qap / total_qap if total_qap > 0 else 0,
            'total_qap_share_verified': legacy_verified_qap / total_qap if total_qap > 0 else 0,
            'effective_multiplier': current_multiplier,
        })
    
    return results


def simulate_looking_forward(months=30):
    """
    Scenario 3: Looking Forward (snadrus) — new CC gets 10x immediately.
    
    - Fil+ onboarding stops immediately (same as Daybreak)
    - NEW CC sectors get 10x multiplier (and 10x pledge)
    - EXISTING CC sectors stay at 1x (no change)
    - Existing Fil+ sectors keep 10x until expiry
    - Rational actors: existing CC miners will want to re-seal at 10x
    """
    results = []
    
    initial_verified_rbp = VERIFIED_RBP_EIB
    initial_cc_rbp = CC_RBP_EIB
    
    # Status quo CC reward for comparison
    sq_total_qap = initial_verified_rbp * 10 + initial_cc_rbp
    sq_cc_reward = DAILY_BLOCK_REWARDS / sq_total_qap
    
    # Track old CC (1x) vs new CC (10x)
    old_cc_rbp = initial_cc_rbp
    new_cc_rbp = 0.0
    
    for month in range(months + 1):
        # Existing Fil+ decays same as Daybreak
        remaining_verified_fraction = max(0, 1 - (month / 30))
        verified_rbp = initial_verified_rbp * remaining_verified_fraction
        legacy_verified_qap = verified_rbp * 10
        
        # Old CC sectors: rational actors terminate and re-seal as new 10x CC
        # Model: ~10% of remaining old CC converts per month (conservative)
        # Some can't afford the 10x pledge, so conversion is gradual
        if month > 0:
            monthly_conversion = old_cc_rbp * 0.10
            old_cc_rbp -= monthly_conversion
            new_cc_rbp += monthly_conversion
        
        old_cc_qap = old_cc_rbp * 1    # 1x
        new_cc_qap = new_cc_rbp * 10   # 10x per snadrus proposal
        
        total_cc_rbp = old_cc_rbp + new_cc_rbp
        total_qap = legacy_verified_qap + old_cc_qap + new_cc_qap
        
        # Rewards
        reward_per_qap_eib = DAILY_BLOCK_REWARDS / total_qap if total_qap > 0 else 0
        old_cc_reward = reward_per_qap_eib * 1    # existing CC at 1x
        new_cc_reward = reward_per_qap_eib * 10   # new CC at 10x
        verified_reward = reward_per_qap_eib * 10  # legacy Fil+ at 10x
        
        # Pledge for new CC sector (10x under Looking Forward)
        new_cc_pledge = calculate_pledge_per_sector(10, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        # Existing CC pledge (1x)
        old_cc_pledge = calculate_pledge_per_sector(1, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        
        results.append({
            'month': month,
            'scenario': 'Looking Forward',
            'total_rbp_eib': verified_rbp + total_cc_rbp,
            'total_qap_eib': total_qap,
            'cc_qap_eib': old_cc_qap + new_cc_qap,
            'verified_qap_eib': legacy_verified_qap,
            'old_cc_rbp_eib': old_cc_rbp,
            'new_cc_rbp_eib': new_cc_rbp,
            'old_cc_reward_per_eib_day': old_cc_reward,
            'new_cc_reward_per_eib_day': new_cc_reward,
            'cc_reward_per_eib_day': old_cc_reward,  # for existing CC miners
            'verified_reward_per_eib_day': verified_reward,
            'cc_pledge_per_sector': old_cc_pledge,
            'verified_pledge_per_sector': new_cc_pledge,
            'new_cc_pledge': new_cc_pledge,  # THIS is the barrier — 10x
            'reward_ratio_cc_vs_current': old_cc_reward / sq_cc_reward if sq_cc_reward > 0 else 0,
            'total_qap_share_cc': (old_cc_qap + new_cc_qap) / total_qap if total_qap > 0 else 0,
            'total_qap_share_verified': legacy_verified_qap / total_qap if total_qap > 0 else 0,
            'effective_multiplier': 10,  # new CC gets 10x
        })
    
    return results


def simulate_looking_forward_no_churn(months=30):
    """
    Scenario 3b: Looking Forward WITHOUT rational re-sealing.
    Existing CC miners stay at 1x (can't afford 10x pledge or don't bother).
    Shows the "unfairness" to existing CC miners.
    """
    results = []
    
    initial_verified_rbp = VERIFIED_RBP_EIB
    initial_cc_rbp = CC_RBP_EIB
    
    sq_total_qap = initial_verified_rbp * 10 + initial_cc_rbp
    sq_cc_reward = DAILY_BLOCK_REWARDS / sq_total_qap
    
    for month in range(months + 1):
        remaining_verified_fraction = max(0, 1 - (month / 30))
        verified_rbp = initial_verified_rbp * remaining_verified_fraction
        legacy_verified_qap = verified_rbp * 10
        
        # NO conversion — existing CC stays at 1x forever
        cc_rbp = initial_cc_rbp
        cc_qap = cc_rbp * 1
        
        total_qap = legacy_verified_qap + cc_qap
        
        reward_per_qap_eib = DAILY_BLOCK_REWARDS / total_qap if total_qap > 0 else 0
        cc_reward = reward_per_qap_eib
        verified_reward = reward_per_qap_eib * 10
        
        cc_pledge = calculate_pledge_per_sector(1, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        new_cc_10x_pledge = calculate_pledge_per_sector(10, total_qap, CIRCULATING_SUPPLY, BASELINE_EIB)
        
        results.append({
            'month': month,
            'scenario': 'Looking Forward (no churn)',
            'total_rbp_eib': verified_rbp + cc_rbp,
            'total_qap_eib': total_qap,
            'cc_qap_eib': cc_qap,
            'verified_qap_eib': legacy_verified_qap,
            'cc_reward_per_eib_day': cc_reward,
            'verified_reward_per_eib_day': verified_reward,
            'cc_pledge_per_sector': cc_pledge,
            'verified_pledge_per_sector': new_cc_10x_pledge,
            'new_cc_pledge': new_cc_10x_pledge,
            'reward_ratio_cc_vs_current': cc_reward / sq_cc_reward if sq_cc_reward > 0 else 0,
            'total_qap_share_cc': cc_qap / total_qap if total_qap > 0 else 0,
            'total_qap_share_verified': legacy_verified_qap / total_qap if total_qap > 0 else 0,
            'effective_multiplier': 10,
        })
    
    return results


# =============================================================================
# Main
# =============================================================================

def main():
    print("=" * 70)
    print("Daybreak vs Looking Forward — Economic Comparison")
    print("=" * 70)
    
    months = 30  # 2.5 years
    
    # Run all scenarios
    sq = simulate_status_quo(months)
    db = simulate_daybreak(months)
    lf = simulate_looking_forward(months)
    lf_nc = simulate_looking_forward_no_churn(months)
    
    # ==========================================================================
    # Summary Table
    # ==========================================================================
    
    print("\n" + "=" * 70)
    print("SUMMARY: Key Metrics at Month 0, 6, 12, 18, 24, 30")
    print("=" * 70)
    
    checkpoints = [0, 6, 12, 18, 24, 30]
    
    print(f"\n{'Metric':<45} | {'Month':>5} | {'Status Quo':>12} | {'Daybreak':>12} | {'LF (churn)':>12} | {'LF (no churn)':>13}")
    print("-" * 110)
    
    for m in checkpoints:
        s = sq[m]
        d = db[m]
        l = lf[m]
        n = lf_nc[m]
        
        print(f"\n--- Month {m} ---")
        print(f"{'Total QAP (EiB)':<45} | {m:>5} | {s['total_qap_eib']:>12.2f} | {d['total_qap_eib']:>12.2f} | {l['total_qap_eib']:>12.2f} | {n['total_qap_eib']:>13.2f}")
        print(f"{'CC reward (FIL/EiB/day)':<45} | {m:>5} | {s['cc_reward_per_eib_day']:>12.2f} | {d['cc_reward_per_eib_day']:>12.2f} | {l['cc_reward_per_eib_day']:>12.2f} | {n['cc_reward_per_eib_day']:>13.2f}")
        print(f"{'CC reward vs status quo':<45} | {m:>5} | {s['reward_ratio_cc_vs_current']:>12.2f}x | {d['reward_ratio_cc_vs_current']:>12.2f}x | {l['reward_ratio_cc_vs_current']:>12.2f}x | {n['reward_ratio_cc_vs_current']:>13.2f}x")
        print(f"{'New CC pledge (FIL/sector)':<45} | {m:>5} | {s['new_cc_pledge']:>12.4f} | {d['new_cc_pledge']:>12.4f} | {l['new_cc_pledge']:>12.4f} | {n['new_cc_pledge']:>13.4f}")
        print(f"{'CC share of QAP':<45} | {m:>5} | {s['total_qap_share_cc']:>11.1%} | {d['total_qap_share_cc']:>11.1%} | {l['total_qap_share_cc']:>11.1%} | {n['total_qap_share_cc']:>12.1%}")
        print(f"{'Verified share of QAP':<45} | {m:>5} | {s['total_qap_share_verified']:>11.1%} | {d['total_qap_share_verified']:>11.1%} | {l['total_qap_share_verified']:>11.1%} | {n['total_qap_share_verified']:>12.1%}")
    
    # ==========================================================================
    # Key Comparisons
    # ==========================================================================
    
    print("\n\n" + "=" * 70)
    print("KEY COMPARISONS")
    print("=" * 70)
    
    # Month 0 — immediate impact
    print("\n📊 IMMEDIATE IMPACT (Month 0):")
    print(f"  New CC sector pledge:")
    print(f"    Status Quo:      {sq[0]['new_cc_pledge']:.4f} FIL")
    print(f"    Daybreak:        {db[0]['new_cc_pledge']:.4f} FIL  (same initially)")
    print(f"    Looking Forward: {lf[0]['new_cc_pledge']:.4f} FIL  ({lf[0]['new_cc_pledge']/sq[0]['new_cc_pledge']:.1f}x higher!)")
    
    # Month 12 — end of Daybreak transition
    print(f"\n📊 MONTH 12 (Daybreak transition complete):")
    print(f"  Existing CC miner reward change vs today:")
    print(f"    Status Quo:          {sq[12]['reward_ratio_cc_vs_current']:.2f}x (unchanged)")
    print(f"    Daybreak:            {db[12]['reward_ratio_cc_vs_current']:.2f}x improvement")
    print(f"    LF (with churn):     {lf[12]['reward_ratio_cc_vs_current']:.2f}x")
    print(f"    LF (no churn):       {lf_nc[12]['reward_ratio_cc_vs_current']:.2f}x")
    
    # Month 30 — steady state
    print(f"\n📊 MONTH 30 (all legacy Fil+ expired):")
    print(f"  CC reward per EiB/day:")
    print(f"    Status Quo:      {sq[30]['cc_reward_per_eib_day']:>10.2f} FIL")
    print(f"    Daybreak:        {db[30]['cc_reward_per_eib_day']:>10.2f} FIL")
    print(f"    LF (with churn): {lf[30]['cc_reward_per_eib_day']:>10.2f} FIL")
    print(f"    LF (no churn):   {lf_nc[30]['cc_reward_per_eib_day']:>10.2f} FIL")
    
    # ==========================================================================
    # The killer comparison: barrier to entry
    # ==========================================================================
    
    print(f"\n📊 BARRIER TO ENTRY — Pledge for new SP onboarding 1 TiB:")
    tib_sectors = 1024 / 32  # 32 sectors per TiB
    for m in [0, 6, 12]:
        print(f"\n  Month {m}:")
        print(f"    Daybreak:        {db[m]['new_cc_pledge'] * tib_sectors:>10.2f} FIL for 1 TiB")
        print(f"    Looking Forward: {lf[m]['new_cc_pledge'] * tib_sectors:>10.2f} FIL for 1 TiB")
        print(f"    Ratio:           Looking Forward costs {lf[m]['new_cc_pledge'] / db[m]['new_cc_pledge']:.1f}x more")
    
    # ==========================================================================
    # Export CSV
    # ==========================================================================
    
    output_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = os.path.join(output_dir, 'daybreak_vs_looking_forward.csv')
    
    all_results = sq + db + lf + lf_nc
    fieldnames = [
        'month', 'scenario', 'total_rbp_eib', 'total_qap_eib',
        'cc_qap_eib', 'verified_qap_eib',
        'cc_reward_per_eib_day', 'verified_reward_per_eib_day',
        'cc_pledge_per_sector', 'new_cc_pledge',
        'reward_ratio_cc_vs_current',
        'total_qap_share_cc', 'total_qap_share_verified',
        'effective_multiplier',
    ]
    
    with open(csv_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(all_results)
    
    print(f"\n\n✅ CSV exported: {csv_path}")
    
    # Export summary JSON
    json_path = os.path.join(output_dir, 'comparison_summary.json')
    summary = {
        'generated': '2026-03-03',
        'network_state': {
            'total_rbp_eib': TOTAL_RBP_EIB,
            'total_qap_eib': TOTAL_QAP_EIB,
            'baseline_eib': BASELINE_EIB,
            'circulating_supply': CIRCULATING_SUPPLY,
            'daily_rewards': DAILY_BLOCK_REWARDS,
        },
        'scenarios': {
            'status_quo': 'No changes, Fil+ continues with 10x multiplier',
            'daybreak': '12-month linear transition 10x→1x, mining reserve burn',
            'looking_forward': 'Immediate: no new Fil+, new CC gets 10x, existing CC stays 1x (with rational re-sealing)',
            'looking_forward_no_churn': 'Same but existing CC miners cannot/do not re-seal',
        },
        'key_findings': {
            'new_sp_pledge_month0': {
                'daybreak': round(db[0]['new_cc_pledge'], 4),
                'looking_forward': round(lf[0]['new_cc_pledge'], 4),
                'ratio': round(lf[0]['new_cc_pledge'] / db[0]['new_cc_pledge'], 1),
            },
            'existing_cc_reward_month12': {
                'daybreak': round(db[12]['reward_ratio_cc_vs_current'], 2),
                'looking_forward_churn': round(lf[12]['reward_ratio_cc_vs_current'], 2),
                'looking_forward_no_churn': round(lf_nc[12]['reward_ratio_cc_vs_current'], 2),
            },
            'conclusion': (
                'Looking Forward requires {:.1f}x higher pledge for new SPs, '
                'provides {:.2f}x reward improvement for existing CC miners (vs Daybreak {:.2f}x), '
                'and creates perverse churn incentive. '
                'Mathematically, universal 10x = universal 1x in steady state.'
            ).format(
                lf[0]['new_cc_pledge'] / db[0]['new_cc_pledge'],
                lf_nc[12]['reward_ratio_cc_vs_current'],
                db[12]['reward_ratio_cc_vs_current'],
            ),
        }
    }
    
    with open(json_path, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"✅ Summary JSON: {json_path}")


if __name__ == '__main__':
    main()
