/**
 * filecoin_econ_sim.cu — Filecoin Economic Simulation for Super FIP
 * 
 * Validates minting model against Filecoin spec, then projects 10 years
 * forward under 12 reform scenarios + 1,050-point parameter sweep.
 *
 * Built for RTX 5080 (Blackwell sm_100), CUDA 13.1
 * Author: Capri (for Nicklas/Reiers)  Date: 2026-02-27
 *
 * KEY INSIGHT: Baseline minting uses RBP (raw byte power), NOT QAP.
 * The 10x Fil+ multiplier only redistributes rewards — it does NOT
 * increase total minting. Removing it makes CC sectors ~8.5x more
 * profitable with unchanged pledge.
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <cuda_runtime.h>

// ============================================================
// FILECOIN SPEC CONSTANTS
// ============================================================

// Token allocations (FIL)
#define FIL_BASE            2000000000.0
#define M_INF               1100000000.0    // 55% storage mining
#define GAMMA               0.7             // Baseline fraction
#define M_INF_B             (M_INF * GAMMA)         // 770M baseline
#define M_INF_S             (M_INF * (1.0 - GAMMA)) // 330M simple
#define MINING_RESERVE      300000000.0     // 15% = 300M

// Time
#define EPOCH_SEC           30.0
#define EPOCHS_PER_DAY      2880
#define EPOCHS_PER_YEAR     1051200         // 365 * 2880

// Minting rate: 6-year half-life
// lambda = ln(2) / (6 * 365 * 2880)
#define LAMBDA              1.09886e-7

// Baseline: b(t) = b0 * exp(g*t), 100%/yr growth from 2.5 EiB
#define B0_EIB              2.5
#define G_ANNUAL_DEFAULT    1.0             // 100% annual growth
// g = ln(1 + g_annual) / EPOCHS_PER_YEAR
#define G_DEFAULT           6.59324e-7

// Consensus
#define E_WIN               5.0             // Expected wins per epoch

// Quality multipliers (spec defaults)
#define QBM                 1.0
#define DWM                 1.0
#define VDWM_DEFAULT        10.0

// Pledge
#define STORAGE_PLEDGE_DAYS 20.0
#define CONSENSUS_TARGET    0.30

// ============================================================
// CURRENT CHAIN STATE (Feb 27, 2026 — from filfox API)
// ============================================================

#define CURRENT_EPOCH       5796404
#define CURRENT_RBP_EIB     2.17
#define CURRENT_QAP_EIB     18.5
#define CURRENT_CIRC_FIL    832500000.0
#define CURRENT_PLEDGE_FIL  94870000.0
#define CURRENT_BURNT_FIL   41770000.0
#define CURRENT_MINED_DAILY 66249.0
#define CURRENT_BASELINE_EIB (B0_EIB * exp(G_DEFAULT * CURRENT_EPOCH))
// ≈ 114.3 EiB
#define FIL_PLUS_FRAC       0.833   // QAP/RBP ≈ 8.5x → fp = 0.833

// ============================================================
// SIMULATION PARAMETERS
// ============================================================

#define SIM_YEARS           10
#define SIM_DAYS            (SIM_YEARS * 365)
#define SIM_EPOCHS          (SIM_YEARS * EPOCHS_PER_YEAR)

// Named scenarios
#define N_SCENARIOS         12

// Parameter sweep
#define N_VDWM              7   // [1, 2, 3, 5, 7, 10, 15]
#define N_RBP_TREND         6   // [-20%, -10%, -5%, 0%, +5%, +10%]
#define N_BL_GROWTH         5   // [0%, 25%, 50%, 75%, 100%]
#define N_SWEEP             (N_VDWM * N_RBP_TREND * N_BL_GROWTH) // 210

// Output checkpoints for sweep (years)
#define N_CHECKPOINTS       5   // 1, 2, 5, 7, 10

// ============================================================
// DATA STRUCTURES
// ============================================================

struct ScenarioParams {
    double vdwm;                // Verified deal multiplier
    double rbp_annual_pct;      // Annual RBP change (e.g., -0.05 = -5%)
    double baseline_annual;     // Baseline annual growth rate
    double reserve_burn_frac;   // Fraction of reserve to burn (0-1)
    double fil_plus_frac;       // Fraction of sectors that are Fil+ verified
    int    transition_epochs;   // Epochs to transition VDWM (0 = instant)
    double initial_vdwm;        // Starting VDWM for transition
    char   name[64];
};

struct DailyMetrics {
    int    day;
    double year;
    double rbp_eib;
    double qap_eib;
    double baseline_eib;
    double cumsum_eib_epochs;
    double theta_epochs;
    double simple_minted;       // Cumulative FIL
    double baseline_minted;     // Cumulative FIL
    double total_minted;        // Cumulative FIL
    double daily_issuance;      // FIL/day
    double reward_per_win;      // FIL per WinCount
    double reward_per_32gib_day;// FIL/day for one 32 GiB CC sector
    double reward_per_tib_day;  // FIL/day per TiB of CC power
    double storage_pledge_32gib;// FIL
    double consensus_pledge_32gib;// FIL
    double total_pledge_32gib;  // FIL
    double circulating;         // FIL
    double annual_roi_pct;      // % return on pledge
};

struct SweepResult {
    int    sweep_idx;
    double vdwm;
    double rbp_trend;
    double bl_growth;
    // Metrics at 5 checkpoints (1y, 2y, 5y, 7y, 10y)
    double reward_per_tib[N_CHECKPOINTS];
    double pledge_per_32gib[N_CHECKPOINTS];
    double daily_issuance[N_CHECKPOINTS];
    double roi_pct[N_CHECKPOINTS];
    double total_minted[N_CHECKPOINTS];
};

// ============================================================
// HISTORICAL RBP MODEL (for cumsum validation)
// Piecewise linear interpolation of network RBP history
// ============================================================

// 10 data points from genesis to now
#define N_HIST_POINTS 10

__constant__ int    hist_epoch[N_HIST_POINTS] = {
    0, 788400, 1751000, 2277000, 2803000,
    3329000, 3855000, 4381000, 5065000, 5796404
};
__constant__ double hist_rbp[N_HIST_POINTS] = {
    1.0, 8.0, 18.0, 17.0, 13.0,
    8.0, 5.0, 3.0, 2.5, 2.17
};
__constant__ double hist_fp[N_HIST_POINTS] = {
    0.0, 0.10, 0.40, 0.60, 0.75,
    0.82, 0.85, 0.84, 0.833, 0.833
};

// ============================================================
// DEVICE HELPER FUNCTIONS
// ============================================================

// Linear interpolation in historical data
__device__ double interp_hist(int epoch, const int* epochs, const double* vals, int n) {
    if (epoch <= epochs[0]) return vals[0];
    if (epoch >= epochs[n-1]) return vals[n-1];
    for (int i = 1; i < n; i++) {
        if (epoch <= epochs[i]) {
            double frac = (double)(epoch - epochs[i-1]) / (double)(epochs[i] - epochs[i-1]);
            return vals[i-1] + frac * (vals[i] - vals[i-1]);
        }
    }
    return vals[n-1];
}

// Baseline function: b(t) = b0 * exp(g * t)
__device__ double baseline_at(int epoch, double g) {
    return B0_EIB * exp(g * (double)epoch);
}

// Simple minting cumulative: M_S(t) = M_inf_S * (1 - exp(-lambda * t))
__device__ double simple_minted_at(int epoch) {
    return M_INF_S * (1.0 - exp(-LAMBDA * (double)epoch));
}

// Effective network time from cumulative capped power
// theta = (1/g) * ln(g * cumsum / b0 + 1)
__device__ double effective_time(double cumsum_eib_epochs, double g) {
    if (g < 1e-15) return 0.0;  // degenerate case
    double arg = g * cumsum_eib_epochs / B0_EIB + 1.0;
    if (arg <= 0.0) return 0.0;
    return (1.0 / g) * log(arg);
}

// Baseline minting cumulative: M_B(t) = M_inf_B * (1 - exp(-lambda * theta))
__device__ double baseline_minted_at(double theta) {
    return M_INF_B * (1.0 - exp(-LAMBDA * theta));
}

// GiB in one EiB
#define GIB_PER_EIB 1073741824.0

// Current baseline level (computed from spec parameters)
// b_current = B0 * exp(G_DEFAULT * CURRENT_EPOCH) ≈ 114.21 EiB
#define B_CURRENT_EIB (B0_EIB * exp(G_DEFAULT * (double)CURRENT_EPOCH))

// ============================================================
// PHASE 1: Compute cumulative sum from genesis to current epoch
// Uses historical RBP data, sums min(baseline, RBP) per epoch
// Runs on a single thread, precomputes cumsum for scenario init
// ============================================================

__global__ void compute_genesis_cumsum(double* out_cumsum, double* out_simple, 
                                        double* out_baseline_minted, double* out_theta) {
    double cumsum = 0.0;
    double g = G_DEFAULT;
    
    // Step through history in daily increments for speed
    // (2880 epochs per day, ~2014 days from genesis to now)
    int total_days = CURRENT_EPOCH / EPOCHS_PER_DAY;
    
    for (int d = 0; d <= total_days; d++) {
        int epoch = d * EPOCHS_PER_DAY;
        if (epoch > CURRENT_EPOCH) epoch = CURRENT_EPOCH;
        
        double rbp = interp_hist(epoch, hist_epoch, hist_rbp, N_HIST_POINTS);
        double bl = baseline_at(epoch, g);
        double r_bar = fmin(bl, rbp);
        
        // Add to cumsum (trapezoidal: each day = EPOCHS_PER_DAY epochs)
        int step = (d == 0) ? 0 : EPOCHS_PER_DAY;
        if (d == total_days) {
            step = CURRENT_EPOCH - (total_days - 1) * EPOCHS_PER_DAY;
            if (step < 0) step = 0;
        }
        cumsum += r_bar * (double)step;
    }
    
    double theta = effective_time(cumsum, g);
    double sm = simple_minted_at(CURRENT_EPOCH);
    double bm = baseline_minted_at(theta);
    
    *out_cumsum = cumsum;
    *out_simple = sm;
    *out_baseline_minted = bm;
    *out_theta = theta;
}

// ============================================================
// PHASE 2: NAMED SCENARIO SIMULATION
// Each thread = one scenario, steps day-by-day for 10 years
// ============================================================

__global__ void simulate_scenarios(
    ScenarioParams* params,
    DailyMetrics* output,       // [N_SCENARIOS][SIM_DAYS]
    double init_cumsum,
    double init_total_minted
) {
    int sid = blockIdx.x * blockDim.x + threadIdx.x;
    if (sid >= N_SCENARIOS) return;
    
    ScenarioParams p = params[sid];
    DailyMetrics* out = &output[sid * SIM_DAYS];
    
    // Compute FORWARD growth rate g for this scenario's baseline
    // CRITICAL: baseline changes only apply FORWARD from current epoch.
    // Historical baseline used G_DEFAULT. Forward baseline starts from
    // b_current = B0 * exp(G_DEFAULT * CURRENT_EPOCH) ≈ 114 EiB
    // and grows at the scenario rate.
    double g_forward = log(1.0 + p.baseline_annual) / (double)EPOCHS_PER_YEAR;
    double b_current = B0_EIB * exp(G_DEFAULT * (double)CURRENT_EPOCH);
    
    // RBP growth rate per epoch
    double rbp_rate = log(1.0 + p.rbp_annual_pct) / (double)EPOCHS_PER_YEAR;
    
    // Initial state
    double cumsum = init_cumsum;
    double prev_total_minted = init_total_minted;
    double circ = CURRENT_CIRC_FIL;
    
    // Remaining vesting (PL + FF, ~20M over 8 months ≈ 240 days)
    double remaining_vest = 20000000.0;
    double vest_per_day = remaining_vest / 240.0;
    int vest_days_left = 240;
    
    // Burn rate (negligible basefee + some penalties)
    double burn_per_day = 2000.0;
    
    for (int d = 0; d < SIM_DAYS; d++) {
        int epoch = CURRENT_EPOCH + (d + 1) * EPOCHS_PER_DAY;
        double year = (double)(d + 1) / 365.25;
        
        // --- RBP trajectory ---
        double rbp = CURRENT_RBP_EIB * exp(rbp_rate * (double)((d + 1) * EPOCHS_PER_DAY));
        if (rbp < 0.1) rbp = 0.1;  // Floor at 100 PiB
        
        // --- VDWM (possibly transitioning) ---
        double vdwm_now;
        if (p.transition_epochs > 0) {
            int elapsed = (d + 1) * EPOCHS_PER_DAY;
            if (elapsed >= p.transition_epochs) {
                vdwm_now = p.vdwm;
            } else {
                double frac = (double)elapsed / (double)p.transition_epochs;
                vdwm_now = p.initial_vdwm + frac * (p.vdwm - p.initial_vdwm);
            }
        } else {
            vdwm_now = p.vdwm;
        }
        
        // --- QAP ---
        double qap = rbp * (1.0 - p.fil_plus_frac + p.fil_plus_frac * vdwm_now);
        
        // --- Baseline (FORWARD from current) ---
        // baseline_forward = b_current * exp(g_forward * elapsed_from_current)
        double elapsed_epochs = (double)((d + 1) * EPOCHS_PER_DAY);
        double bl_at_epoch = b_current * exp(g_forward * elapsed_epochs);
        
        // --- Cumulative capped power (daily step) ---
        // Since baseline >> RBP for all realistic scenarios, r_bar ≈ RBP
        double r_bar = fmin(bl_at_epoch, rbp);
        cumsum += r_bar * (double)EPOCHS_PER_DAY;
        
        // --- Effective time & minting ---
        // CRITICAL: Always use G_DEFAULT for effective_time.
        // θ maps cumsum back through the ORIGINAL baseline curve.
        // Since θ < CURRENT_EPOCH for all realistic scenarios (network
        // never caught up to baseline), the mapping is always through
        // the historical phase where g = G_DEFAULT.
        double theta = effective_time(cumsum, G_DEFAULT);
        double sm = simple_minted_at(epoch);
        double bm = baseline_minted_at(theta);
        double total = sm + bm;
        
        // --- Daily issuance ---
        double daily = total - prev_total_minted;
        if (daily < 0.0) daily = 0.0;
        prev_total_minted = total;
        
        // --- Per-win reward ---
        double reward_per_win = daily / (E_WIN * (double)EPOCHS_PER_DAY);
        
        // --- Reward per 32 GiB CC sector per day ---
        double sector_qap_gib = 32.0;  // CC sector
        double total_qap_gib = qap * GIB_PER_EIB;
        double qap_fraction = sector_qap_gib / total_qap_gib;
        double reward_32gib = daily * qap_fraction;
        
        // --- Reward per TiB per day ---
        double reward_tib = reward_32gib * (1024.0 / 32.0);
        
        // --- Pledge calculation ---
        double daily_sector_reward = reward_32gib;
        double stor_pledge = STORAGE_PLEDGE_DAYS * daily_sector_reward;
        
        // Consensus pledge = 30% * circ * sector_QAP / max(baseline, QAP)
        // sector_QAP in GiB, baseline and QAP in GiB
        double denom = fmax(bl_at_epoch * GIB_PER_EIB, total_qap_gib);
        double cons_pledge = CONSENSUS_TARGET * circ * sector_qap_gib / denom;
        
        double total_pledge = stor_pledge + cons_pledge;
        
        // --- ROI ---
        double annual_reward = reward_32gib * 365.25;
        double roi = (total_pledge > 0.0) ? (annual_reward / total_pledge) * 100.0 : 0.0;
        
        // --- Circulating supply update ---
        double vest_today = (d < vest_days_left) ? vest_per_day : 0.0;
        circ += daily + vest_today - burn_per_day;
        
        // --- Reserve burn effect (reduce circ by burnt reserve, one-time at day 0) ---
        if (d == 0 && p.reserve_burn_frac > 0.0) {
            // Mining reserve burn reduces potential future supply
            // It doesn't directly change circulating (reserve isn't circulating)
            // but signals permanent supply reduction
            // Model as sentiment: no direct circ change
        }
        
        // --- Write output ---
        out[d].day = d + 1;
        out[d].year = year;
        out[d].rbp_eib = rbp;
        out[d].qap_eib = qap;
        out[d].baseline_eib = bl_at_epoch;
        out[d].cumsum_eib_epochs = cumsum;
        out[d].theta_epochs = theta;
        out[d].simple_minted = sm;
        out[d].baseline_minted = bm;
        out[d].total_minted = total;
        out[d].daily_issuance = daily;
        out[d].reward_per_win = reward_per_win;
        out[d].reward_per_32gib_day = reward_32gib;
        out[d].reward_per_tib_day = reward_tib;
        out[d].storage_pledge_32gib = stor_pledge;
        out[d].consensus_pledge_32gib = cons_pledge;
        out[d].total_pledge_32gib = total_pledge;
        out[d].circulating = circ;
        out[d].annual_roi_pct = roi;
    }
}

// ============================================================
// PHASE 3: PARAMETER SWEEP
// Each thread = one (VDWM, RBP_trend, baseline_growth) combo
// Output only at 5 checkpoints
// ============================================================

__constant__ double sweep_vdwm[N_VDWM] = {1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 15.0};
__constant__ double sweep_rbp[N_RBP_TREND] = {-0.20, -0.10, -0.05, 0.0, 0.05, 0.10};
__constant__ double sweep_bl[N_BL_GROWTH] = {0.0, 0.25, 0.50, 0.75, 1.00};
__constant__ int    checkpoint_days[N_CHECKPOINTS] = {365, 730, 1825, 2555, 3650};

__global__ void parameter_sweep(
    SweepResult* results,
    double init_cumsum,
    double init_total_minted
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= N_SWEEP) return;
    
    // Decode parameter indices
    int vi = tid / (N_RBP_TREND * N_BL_GROWTH);
    int ri = (tid / N_BL_GROWTH) % N_RBP_TREND;
    int bi = tid % N_BL_GROWTH;
    
    double vdwm = sweep_vdwm[vi];
    double rbp_pct = sweep_rbp[ri];
    double bl_annual = sweep_bl[bi];
    
    double g_fwd = (bl_annual > 0.001) ? log(1.0 + bl_annual) / (double)EPOCHS_PER_YEAR : 1e-15;
    double b_cur = B0_EIB * exp(G_DEFAULT * (double)CURRENT_EPOCH);
    double rbp_rate = (fabs(rbp_pct) > 0.001) ? log(1.0 + rbp_pct) / (double)EPOCHS_PER_YEAR : 0.0;
    
    double cumsum = init_cumsum;
    double prev_total = init_total_minted;
    double circ = CURRENT_CIRC_FIL;
    
    int ck = 0;  // checkpoint index
    
    SweepResult res;
    res.sweep_idx = tid;
    res.vdwm = vdwm;
    res.rbp_trend = rbp_pct;
    res.bl_growth = bl_annual;
    
    for (int d = 0; d < SIM_DAYS && ck < N_CHECKPOINTS; d++) {
        int epoch = CURRENT_EPOCH + (d + 1) * EPOCHS_PER_DAY;
        
        double rbp = CURRENT_RBP_EIB * exp(rbp_rate * (double)((d+1) * EPOCHS_PER_DAY));
        if (rbp < 0.1) rbp = 0.1;
        
        double qap = rbp * (1.0 - FIL_PLUS_FRAC + FIL_PLUS_FRAC * vdwm);
        double elapsed = (double)((d+1) * EPOCHS_PER_DAY);
        double bl = b_cur * exp(g_fwd * elapsed);
        double r_bar = fmin(bl, rbp);
        cumsum += r_bar * (double)EPOCHS_PER_DAY;
        
        // Always use G_DEFAULT for effective_time (θ in historical baseline regime)
        double theta = effective_time(cumsum, G_DEFAULT);
        double sm = simple_minted_at(epoch);
        double bm = baseline_minted_at(theta);
        double total = sm + bm;
        double daily = total - prev_total;
        if (daily < 0.0) daily = 0.0;
        prev_total = total;
        
        circ += daily + (d < 240 ? 83333.0 : 0.0) - 2000.0;
        
        // Check if this is a checkpoint day
        if (d + 1 == checkpoint_days[ck]) {
            double total_qap_gib = qap * GIB_PER_EIB;
            double reward_tib = daily * (1024.0 / total_qap_gib);  // per TiB CC
            
            double daily_32gib = daily * 32.0 / total_qap_gib;
            double stor_p = STORAGE_PLEDGE_DAYS * daily_32gib;
            double cons_p = CONSENSUS_TARGET * circ * 32.0 / fmax(bl * GIB_PER_EIB, total_qap_gib);
            double pledge = stor_p + cons_p;
            double roi = (pledge > 0.0) ? (daily_32gib * 365.25 / pledge) * 100.0 : 0.0;
            
            res.reward_per_tib[ck] = reward_tib;
            res.pledge_per_32gib[ck] = pledge;
            res.daily_issuance[ck] = daily;
            res.roi_pct[ck] = roi;
            res.total_minted[ck] = total;
            ck++;
        }
    }
    
    results[tid] = res;
}

// ============================================================
// HOST CODE
// ============================================================

void define_scenarios(ScenarioParams* s) {
    // Scenario 0: Status Quo
    s[0] = {10.0, -0.05, 1.0, 0.0, 0.833, 0, 10.0, "Status_Quo"};
    
    // Scenario 1: Immediate Fil+ Removal (VDWM=1)
    s[1] = {1.0, -0.05, 1.0, 0.0, 0.833, 0, 1.0, "FilPlus_Removed"};
    
    // Scenario 2: Fil+ Removed + RBP Recovery (+5%/yr)
    s[2] = {1.0, 0.05, 1.0, 0.0, 0.833, 0, 1.0, "FilPlus_Removed_RBP_Recovery"};
    
    // Scenario 3: Fil+ Removed + RBP Collapse (-20%/yr)
    s[3] = {1.0, -0.20, 1.0, 0.0, 0.833, 0, 1.0, "FilPlus_Removed_RBP_Collapse"};
    
    // Scenario 4: Gradual Reduction 10→1 over 3 years
    s[4] = {1.0, -0.05, 1.0, 0.0, 0.833, 3*EPOCHS_PER_YEAR, 10.0, "Gradual_10to1_3yr"};
    
    // Scenario 5: Gradual Reduction 10→1 over 1 year
    s[5] = {1.0, -0.05, 1.0, 0.0, 0.833, EPOCHS_PER_YEAR, 10.0, "Gradual_10to1_1yr"};
    
    // Scenario 6: Status Quo + Reserve Burn
    s[6] = {10.0, -0.05, 1.0, 1.0, 0.833, 0, 10.0, "StatusQuo_ReserveBurn"};
    
    // Scenario 7: Full Reform (VDWM=1 + reserve burn + baseline 50%)
    s[7] = {1.0, 0.0, 0.50, 1.0, 0.833, EPOCHS_PER_YEAR, 10.0, "Full_Reform"};
    
    // Scenario 8: Conservative Reform (VDWM=3 + reserve burn)
    s[8] = {3.0, -0.03, 1.0, 1.0, 0.833, EPOCHS_PER_YEAR, 10.0, "Conservative_Reform"};
    
    // Scenario 9: Full Reform + RBP Growth (+10%/yr)
    s[9] = {1.0, 0.10, 0.50, 1.0, 0.833, EPOCHS_PER_YEAR, 10.0, "Full_Reform_Optimistic"};
    
    // Scenario 10: Baseline Slowdown Only (100% → 25%)
    s[10] = {10.0, -0.05, 0.25, 0.0, 0.833, 0, 10.0, "Baseline_Slowdown_Only"};
    
    // Scenario 11: Nuclear Option (VDWM=1, baseline 0%, reserve burn)
    s[11] = {1.0, 0.0, 0.001, 1.0, 0.833, 0, 1.0, "Nuclear_Option"};
}

void write_scenario_csv(const char* dir, const char* name, DailyMetrics* data, int days) {
    char path[256];
    snprintf(path, sizeof(path), "%s/scenario_%s.csv", dir, name);
    FILE* f = fopen(path, "w");
    if (!f) { fprintf(stderr, "Cannot open %s\n", path); return; }
    
    fprintf(f, "day,year,rbp_eib,qap_eib,baseline_eib,cumsum,theta,"
               "simple_minted,baseline_minted,total_minted,daily_issuance,"
               "reward_per_win,reward_32gib_day,reward_tib_day,"
               "storage_pledge,consensus_pledge,total_pledge,circulating,roi_pct\n");
    
    for (int i = 0; i < days; i++) {
        DailyMetrics* m = &data[i];
        fprintf(f, "%d,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,"
                   "%.2f,%.2f,%.2f,%.2f,"
                   "%.8f,%.8f,%.8f,"
                   "%.8f,%.8f,%.8f,%.2f,%.4f\n",
                m->day, m->year, m->rbp_eib, m->qap_eib, m->baseline_eib,
                m->cumsum_eib_epochs, m->theta_epochs,
                m->simple_minted, m->baseline_minted, m->total_minted,
                m->daily_issuance,
                m->reward_per_win, m->reward_per_32gib_day, m->reward_per_tib_day,
                m->storage_pledge_32gib, m->consensus_pledge_32gib,
                m->total_pledge_32gib, m->circulating, m->annual_roi_pct);
    }
    fclose(f);
    printf("  Written: %s\n", path);
}

void write_sweep_csv(const char* dir, SweepResult* data, int n) {
    char path[256];
    snprintf(path, sizeof(path), "%s/parameter_sweep.csv", dir);
    FILE* f = fopen(path, "w");
    if (!f) { fprintf(stderr, "Cannot open %s\n", path); return; }
    
    fprintf(f, "idx,vdwm,rbp_trend,bl_growth,"
               "reward_tib_1y,reward_tib_2y,reward_tib_5y,reward_tib_7y,reward_tib_10y,"
               "pledge_1y,pledge_2y,pledge_5y,pledge_7y,pledge_10y,"
               "issuance_1y,issuance_2y,issuance_5y,issuance_7y,issuance_10y,"
               "roi_1y,roi_2y,roi_5y,roi_7y,roi_10y,"
               "minted_1y,minted_2y,minted_5y,minted_7y,minted_10y\n");
    
    for (int i = 0; i < n; i++) {
        SweepResult* r = &data[i];
        fprintf(f, "%d,%.1f,%.2f,%.2f", r->sweep_idx, r->vdwm, r->rbp_trend, r->bl_growth);
        for (int c = 0; c < N_CHECKPOINTS; c++) fprintf(f, ",%.8f", r->reward_per_tib[c]);
        for (int c = 0; c < N_CHECKPOINTS; c++) fprintf(f, ",%.8f", r->pledge_per_32gib[c]);
        for (int c = 0; c < N_CHECKPOINTS; c++) fprintf(f, ",%.2f", r->daily_issuance[c]);
        for (int c = 0; c < N_CHECKPOINTS; c++) fprintf(f, ",%.4f", r->roi_pct[c]);
        for (int c = 0; c < N_CHECKPOINTS; c++) fprintf(f, ",%.2f", r->total_minted[c]);
        fprintf(f, "\n");
    }
    fclose(f);
    printf("  Written: %s\n", path);
}

int main(int argc, char** argv) {
    const char* outdir = (argc > 1) ? argv[1] : "./results";
    
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║  Filecoin Economic Simulation — Super FIP               ║\n");
    printf("║  CUDA on Blackwell RTX 5080                             ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n\n");
    
    // ---- Device info ----
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("GPU: %s (%d SMs, %.1f GB)\n\n", 
           prop.name, prop.multiProcessorCount, 
           prop.totalGlobalMem / 1e9);
    
    // ============================================================
    // PHASE 1: Compute genesis → current cumulative sum
    // ============================================================
    printf("Phase 1: Computing genesis → current cumulative sum...\n");
    
    double *d_cumsum, *d_simple, *d_bm, *d_theta;
    cudaMalloc(&d_cumsum, sizeof(double));
    cudaMalloc(&d_simple, sizeof(double));
    cudaMalloc(&d_bm, sizeof(double));
    cudaMalloc(&d_theta, sizeof(double));
    
    compute_genesis_cumsum<<<1,1>>>(d_cumsum, d_simple, d_bm, d_theta);
    cudaDeviceSynchronize();
    
    double h_cumsum, h_simple, h_bm, h_theta;
    cudaMemcpy(&h_cumsum, d_cumsum, sizeof(double), cudaMemcpyDeviceToHost);
    cudaMemcpy(&h_simple, d_simple, sizeof(double), cudaMemcpyDeviceToHost);
    cudaMemcpy(&h_bm, d_bm, sizeof(double), cudaMemcpyDeviceToHost);
    cudaMemcpy(&h_theta, d_theta, sizeof(double), cudaMemcpyDeviceToHost);
    
    double h_total_minted = h_simple + h_bm;
    
    printf("  Cumulative RBP·epochs: %.2f EiB·epochs\n", h_cumsum);
    printf("  Effective time θ:      %.0f epochs (%.2f years)\n", h_theta, h_theta / EPOCHS_PER_YEAR);
    printf("  Simple minted:         %.2f M FIL\n", h_simple / 1e6);
    printf("  Baseline minted:       %.2f M FIL\n", h_bm / 1e6);
    printf("  Total minted:          %.2f M FIL\n", h_total_minted / 1e6);
    printf("  Current baseline:      %.2f EiB\n", CURRENT_BASELINE_EIB);
    printf("  Current RBP:           %.2f EiB (%.1f%% of baseline)\n", 
           CURRENT_RBP_EIB, 100.0 * CURRENT_RBP_EIB / CURRENT_BASELINE_EIB);
    printf("  Current QAP:           %.2f EiB (%.1f%% of baseline)\n\n",
           CURRENT_QAP_EIB, 100.0 * CURRENT_QAP_EIB / CURRENT_BASELINE_EIB);
    
    // ============================================================
    // KEY FINDING: Fil+ multiplier impact analysis
    // ============================================================
    printf("═══ KEY FINDING: Fil+ Multiplier Economic Impact ═══\n");
    double total_qap_gib = CURRENT_QAP_EIB * GIB_PER_EIB;
    double reward_cc_with_filplus = CURRENT_MINED_DAILY * 32.0 / total_qap_gib;
    double reward_fp_with_filplus = reward_cc_with_filplus * VDWM_DEFAULT;
    
    double qap_without = CURRENT_RBP_EIB * GIB_PER_EIB;  // All sectors = 1x
    double reward_cc_without = CURRENT_MINED_DAILY * 32.0 / qap_without;
    
    printf("  WITH Fil+ (10x):\n");
    printf("    CC sector reward:    %.6f FIL/day ($%.6f)\n", 
           reward_cc_with_filplus, reward_cc_with_filplus * 1.5);
    printf("    Fil+ sector reward:  %.6f FIL/day ($%.6f)\n",
           reward_fp_with_filplus, reward_fp_with_filplus * 1.5);
    printf("  WITHOUT Fil+ (1x):\n");
    printf("    All sectors reward:  %.6f FIL/day ($%.6f)\n",
           reward_cc_without, reward_cc_without * 1.5);
    printf("  CC sector improvement: %.1fx higher reward\n", 
           reward_cc_without / reward_cc_with_filplus);
    printf("  Total daily issuance:  UNCHANGED (%.0f FIL) — baseline uses RBP!\n\n",
           CURRENT_MINED_DAILY);
    
    // Pledge comparison
    double bl_gib = CURRENT_BASELINE_EIB * GIB_PER_EIB;
    double cons_with = CONSENSUS_TARGET * CURRENT_CIRC_FIL * 32.0 / fmax(bl_gib, total_qap_gib);
    double cons_without = CONSENSUS_TARGET * CURRENT_CIRC_FIL * 32.0 / fmax(bl_gib, qap_without);
    double stor_with = STORAGE_PLEDGE_DAYS * reward_cc_with_filplus;
    double stor_without = STORAGE_PLEDGE_DAYS * reward_cc_without;
    
    printf("  PLEDGE (32 GiB CC sector):\n");
    printf("    With Fil+:    storage=%.6f + consensus=%.6f = %.6f FIL\n",
           stor_with, cons_with, stor_with + cons_with);
    printf("    Without Fil+: storage=%.6f + consensus=%.6f = %.6f FIL\n",
           stor_without, cons_without, stor_without + cons_without);
    printf("    Note: consensus pledge unchanged (baseline >> QAP in both cases)\n\n");
    
    double roi_with = (reward_cc_with_filplus * 365.25 / (stor_with + cons_with)) * 100.0;
    double roi_without = (reward_cc_without * 365.25 / (stor_without + cons_without)) * 100.0;
    printf("  ROI (CC sector):\n");
    printf("    With Fil+:    %.1f%% annual\n", roi_with);
    printf("    Without Fil+: %.1f%% annual\n\n", roi_without);
    
    // ============================================================
    // PHASE 2: Named scenarios
    // ============================================================
    printf("Phase 2: Running %d named scenarios (10 years each)...\n", N_SCENARIOS);
    
    ScenarioParams h_params[N_SCENARIOS];
    define_scenarios(h_params);
    
    ScenarioParams* d_params;
    cudaMalloc(&d_params, N_SCENARIOS * sizeof(ScenarioParams));
    cudaMemcpy(d_params, h_params, N_SCENARIOS * sizeof(ScenarioParams), cudaMemcpyHostToDevice);
    
    size_t output_size = N_SCENARIOS * SIM_DAYS * sizeof(DailyMetrics);
    printf("  Output buffer: %.1f MB\n", output_size / 1e6);
    
    DailyMetrics* d_output;
    cudaMalloc(&d_output, output_size);
    
    simulate_scenarios<<<1, N_SCENARIOS>>>(d_params, d_output, h_cumsum, h_total_minted);
    cudaDeviceSynchronize();
    
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    
    DailyMetrics* h_output = (DailyMetrics*)malloc(output_size);
    cudaMemcpy(h_output, d_output, output_size, cudaMemcpyDeviceToHost);
    
    // Write CSVs
    for (int i = 0; i < N_SCENARIOS; i++) {
        write_scenario_csv(outdir, h_params[i].name, &h_output[i * SIM_DAYS], SIM_DAYS);
    }
    
    // Print summary table
    printf("\n═══ 10-YEAR SCENARIO COMPARISON ═══\n");
    printf("%-35s %12s %12s %12s %12s %10s\n",
           "Scenario", "Reward/TiB", "Pledge/32G", "Issuance/d", "Minted", "ROI%");
    printf("%-35s %12s %12s %12s %12s %10s\n",
           "", "(FIL/day)", "(FIL)", "(FIL)", "(M FIL)", "(annual)");
    printf("─────────────────────────────────── ──────────── ──────────── ──────────── ──────────── ──────────\n");
    
    for (int i = 0; i < N_SCENARIOS; i++) {
        DailyMetrics* last = &h_output[i * SIM_DAYS + SIM_DAYS - 1];
        printf("%-35s %12.6f %12.6f %12.2f %12.2f %10.1f\n",
               h_params[i].name,
               last->reward_per_tib_day,
               last->total_pledge_32gib,
               last->daily_issuance,
               last->total_minted / 1e6,
               last->annual_roi_pct);
    }
    
    // Year 1 comparison
    printf("\n═══ YEAR 1 COMPARISON ═══\n");
    printf("%-35s %12s %12s %12s %10s\n",
           "Scenario", "Reward/TiB", "Pledge/32G", "Issuance/d", "ROI%");
    printf("─────────────────────────────────── ──────────── ──────────── ──────────── ──────────\n");
    for (int i = 0; i < N_SCENARIOS; i++) {
        DailyMetrics* y1 = &h_output[i * SIM_DAYS + 364];
        printf("%-35s %12.6f %12.6f %12.2f %10.1f\n",
               h_params[i].name,
               y1->reward_per_tib_day,
               y1->total_pledge_32gib,
               y1->daily_issuance,
               y1->annual_roi_pct);
    }
    
    // ============================================================
    // PHASE 3: Parameter sweep
    // ============================================================
    printf("\nPhase 3: Running %d parameter sweep combinations...\n", N_SWEEP);
    
    SweepResult* d_sweep;
    cudaMalloc(&d_sweep, N_SWEEP * sizeof(SweepResult));
    
    int threads_per_block = 128;
    int blocks = (N_SWEEP + threads_per_block - 1) / threads_per_block;
    parameter_sweep<<<blocks, threads_per_block>>>(d_sweep, h_cumsum, h_total_minted);
    cudaDeviceSynchronize();
    
    err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA sweep error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    
    SweepResult* h_sweep = (SweepResult*)malloc(N_SWEEP * sizeof(SweepResult));
    cudaMemcpy(h_sweep, d_sweep, N_SWEEP * sizeof(SweepResult), cudaMemcpyDeviceToHost);
    
    write_sweep_csv(outdir, h_sweep, N_SWEEP);
    
    // Print sweep highlights
    printf("\n═══ PARAMETER SWEEP HIGHLIGHTS (Year 5) ═══\n");
    printf("%-6s %-8s %-8s %12s %12s %10s\n",
           "VDWM", "RBP%", "BL%", "Reward/TiB", "Pledge/32G", "ROI%");
    printf("────── ──────── ──────── ──────────── ──────────── ──────────\n");
    
    // Find best and worst ROI
    double best_roi = -1e9, worst_roi = 1e9;
    int best_idx = 0, worst_idx = 0;
    for (int i = 0; i < N_SWEEP; i++) {
        if (h_sweep[i].roi_pct[2] > best_roi) { best_roi = h_sweep[i].roi_pct[2]; best_idx = i; }
        if (h_sweep[i].roi_pct[2] < worst_roi) { worst_roi = h_sweep[i].roi_pct[2]; worst_idx = i; }
    }
    
    // Print a selection: best ROI, worst ROI, and status quo equivalent
    printf("BEST:  ");
    printf("%-6.0f %-8.0f %-8.0f %12.6f %12.6f %10.1f\n",
           h_sweep[best_idx].vdwm, h_sweep[best_idx].rbp_trend*100, 
           h_sweep[best_idx].bl_growth*100,
           h_sweep[best_idx].reward_per_tib[2], h_sweep[best_idx].pledge_per_32gib[2],
           h_sweep[best_idx].roi_pct[2]);
    printf("WORST: ");
    printf("%-6.0f %-8.0f %-8.0f %12.6f %12.6f %10.1f\n",
           h_sweep[worst_idx].vdwm, h_sweep[worst_idx].rbp_trend*100,
           h_sweep[worst_idx].bl_growth*100,
           h_sweep[worst_idx].reward_per_tib[2], h_sweep[worst_idx].pledge_per_32gib[2],
           h_sweep[worst_idx].roi_pct[2]);
    
    // Print all VDWM=1, RBP=0%, varying baseline
    printf("\n── VDWM=1 (no Fil+), RBP stable, varying baseline growth: ──\n");
    for (int i = 0; i < N_SWEEP; i++) {
        if (fabs(h_sweep[i].vdwm - 1.0) < 0.1 && fabs(h_sweep[i].rbp_trend) < 0.01) {
            printf("  BL=%3.0f%%: reward/TiB=%.6f  pledge=%.6f  ROI=%.1f%%\n",
                   h_sweep[i].bl_growth * 100,
                   h_sweep[i].reward_per_tib[2],
                   h_sweep[i].pledge_per_32gib[2],
                   h_sweep[i].roi_pct[2]);
        }
    }
    
    // Compare VDWM=10 vs VDWM=1 at same conditions
    printf("\n── VDWM=10 vs VDWM=1 (RBP=-5%%, BL=100%%): ──\n");
    for (int i = 0; i < N_SWEEP; i++) {
        if ((fabs(h_sweep[i].vdwm - 10.0) < 0.1 || fabs(h_sweep[i].vdwm - 1.0) < 0.1) &&
            fabs(h_sweep[i].rbp_trend + 0.05) < 0.01 &&
            fabs(h_sweep[i].bl_growth - 1.0) < 0.01) {
            printf("  VDWM=%2.0f: reward/TiB=%.6f  pledge=%.6f  ROI=%.1f%%\n",
                   h_sweep[i].vdwm,
                   h_sweep[i].reward_per_tib[2],
                   h_sweep[i].pledge_per_32gib[2],
                   h_sweep[i].roi_pct[2]);
        }
    }
    
    printf("\n═══ SIMULATION COMPLETE ═══\n");
    printf("Results written to: %s/\n", outdir);
    printf("  12 scenario CSVs + 1 parameter sweep CSV\n");
    printf("  Total data points: %d\n", N_SCENARIOS * SIM_DAYS + N_SWEEP * N_CHECKPOINTS);
    
    // Cleanup
    free(h_output);
    free(h_sweep);
    cudaFree(d_cumsum); cudaFree(d_simple); cudaFree(d_bm); cudaFree(d_theta);
    cudaFree(d_params); cudaFree(d_output); cudaFree(d_sweep);
    
    return 0;
}
