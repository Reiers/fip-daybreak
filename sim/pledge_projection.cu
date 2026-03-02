/**
 * pledge_projection.cu — FIP-Daybreak Pledge & Locked FIL Projection
 * 
 * Compares 1x-for-all vs 10x-for-all convergence paths.
 * Uses FIP-0081 pledge formula (simple + baseline components with gamma).
 * Tracks total network locked FIL over the transition period.
 *
 * Target: RTX 6000 (sm_75, Turing), CUDA 12.x
 * Author: Capri (for Nicklas/Reiers)  Date: 2026-03-02
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cuda_runtime.h>

// ============================================================
// FILECOIN SPEC CONSTANTS
// ============================================================

#define FIL_BASE            2000000000.0
#define M_INF               1100000000.0
#define MINTING_GAMMA       0.7             // Minting baseline fraction
#define M_INF_B             (M_INF * MINTING_GAMMA)
#define M_INF_S             (M_INF * (1.0 - MINTING_GAMMA))
#define LAMBDA              1.09886e-7      // ln(2)/(6*EPOCHS_PER_YEAR)

#define EPOCHS_PER_DAY      2880
#define EPOCHS_PER_YEAR     1051200

#define B0_EIB              2.5
#define G_DEFAULT           6.59324e-7      // ln(2)/EPOCHS_PER_YEAR

#define E_WIN               5.0
#define STORAGE_PLEDGE_DAYS 20.0
#define CONSENSUS_TARGET    0.30
#define GIB_PER_EIB         1073741824.0

// FIP-0081: Pledge gamma (controls simple vs baseline weight)
// Ramp completed Nov 2025 → gamma = 0.7
#define PLEDGE_GAMMA        0.7

// ============================================================
// CURRENT CHAIN STATE (Mar 2, 2026)
// ============================================================

#define CURRENT_EPOCH       5802000
#define CURRENT_RBP_EIB     2.17
#define CURRENT_QAP_EIB     18.5
#define CURRENT_CIRC_FIL    832500000.0
#define CURRENT_LOCKED_FIL  93000000.0      // Approximate total locked
#define CURRENT_MINED_DAILY 66249.0
#define FIL_PLUS_FRAC       0.833           // ~83% of sectors have DC

// Sector lifecycle
#define AVG_SECTOR_LIFE_DAYS 540            // ~18 months average
#define TOTAL_SECTORS       72000000.0      // ~2.17 EiB / 32 GiB ≈ 72M sectors

// ============================================================
// SIMULATION PARAMETERS
// ============================================================

#define SIM_YEARS           5
#define SIM_DAYS            (SIM_YEARS * 365)

// Convergence scenarios
#define N_SCENARIOS         6

// ============================================================
// DATA STRUCTURES
// ============================================================

struct PledgeScenario {
    double target_vdwm;         // Final VDWM (1.0 or 10.0)
    double all_sector_mult;     // Multiplier for ALL sectors (1.0 or 10.0)
    double rbp_annual_pct;      // Annual RBP change
    int    transition_days;     // Days to complete transition
    char   name[64];
};

struct PledgeDailyOutput {
    int    day;
    double year;
    // Per-sector (new 32 GiB CC sector)
    double simple_pledge;       // FIP-0081 simple component
    double baseline_pledge;     // FIP-0081 baseline component
    double consensus_pledge;    // Weighted combo
    double storage_pledge;
    double total_pledge;
    double daily_reward;
    double annual_roi_pct;
    // Network totals
    double network_qap_eib;
    double baseline_eib;
    double network_consensus_pledge;  // Total across all sectors
    double network_storage_pledge;
    double network_total_locked;
    double circulating_supply;
    // Components
    double network_simple_total;
    double network_baseline_total;
};

// ============================================================
// HISTORICAL DATA (for cumsum)
// ============================================================

#define N_HIST 10
__constant__ int    hist_epoch[N_HIST] = {
    0, 788400, 1751000, 2277000, 2803000,
    3329000, 3855000, 4381000, 5065000, 5802000
};
__constant__ double hist_rbp[N_HIST] = {
    1.0, 8.0, 18.0, 17.0, 13.0,
    8.0, 5.0, 3.0, 2.5, 2.17
};

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

__device__ double baseline_at(int epoch) {
    return B0_EIB * exp(G_DEFAULT * (double)epoch);
}

// ============================================================
// PHASE 1: Genesis cumsum (single thread)
// ============================================================

__global__ void compute_cumsum(double* out_cumsum, double* out_total_minted) {
    double cumsum = 0.0;
    int total_days = CURRENT_EPOCH / EPOCHS_PER_DAY;
    
    for (int d = 0; d <= total_days; d++) {
        int epoch = d * EPOCHS_PER_DAY;
        if (epoch > CURRENT_EPOCH) epoch = CURRENT_EPOCH;
        
        double rbp = interp_hist(epoch, hist_epoch, hist_rbp, N_HIST);
        double bl = baseline_at(epoch);
        double r_bar = fmin(bl, rbp);
        
        int step = (d == 0) ? 0 : EPOCHS_PER_DAY;
        if (d == total_days) {
            step = CURRENT_EPOCH - (total_days - 1) * EPOCHS_PER_DAY;
            if (step < 0) step = 0;
        }
        cumsum += r_bar * (double)step;
    }
    
    // Minting
    double theta = (1.0 / G_DEFAULT) * log(G_DEFAULT * cumsum / B0_EIB + 1.0);
    double sm = M_INF_S * (1.0 - exp(-LAMBDA * (double)CURRENT_EPOCH));
    double bm = M_INF_B * (1.0 - exp(-LAMBDA * theta));
    
    *out_cumsum = cumsum;
    *out_total_minted = sm + bm;
}

// ============================================================
// PHASE 2: Pledge projection scenarios
// ============================================================

__global__ void simulate_pledge(
    PledgeScenario* params,
    PledgeDailyOutput* output,
    double init_cumsum,
    double init_total_minted
) {
    int sid = blockIdx.x * blockDim.x + threadIdx.x;
    if (sid >= N_SCENARIOS) return;
    
    PledgeScenario p = params[sid];
    PledgeDailyOutput* out = &output[sid * SIM_DAYS];
    
    double cumsum = init_cumsum;
    double prev_minted = init_total_minted;
    double circ = CURRENT_CIRC_FIL;
    
    double rbp_rate = log(1.0 + p.rbp_annual_pct) / (double)EPOCHS_PER_YEAR;
    double b_current = baseline_at(CURRENT_EPOCH);
    
    // Track sector turnover for network pledge
    // Simplified model: sectors expire linearly over avg lifetime
    // Old sectors (pre-Daybreak) have mixed pledge, new sectors use new formula
    double old_sector_frac = 1.0;  // Fraction of sectors from pre-Daybreak era
    double decay_per_day = 1.0 / (double)AVG_SECTOR_LIFE_DAYS;
    
    for (int d = 0; d < SIM_DAYS; d++) {
        int epoch = CURRENT_EPOCH + (d + 1) * EPOCHS_PER_DAY;
        double year = (double)(d + 1) / 365.25;
        double elapsed_epochs = (double)((d + 1) * EPOCHS_PER_DAY);
        
        // RBP trajectory
        double rbp = CURRENT_RBP_EIB * exp(rbp_rate * elapsed_epochs);
        if (rbp < 0.1) rbp = 0.1;
        
        // Baseline (continues at 100%/yr)
        double bl = b_current * exp(G_DEFAULT * elapsed_epochs);
        
        // Effective VDWM during transition
        double vdwm_now;
        if (d >= p.transition_days || p.transition_days == 0) {
            vdwm_now = p.target_vdwm;
        } else {
            double frac = (double)d / (double)p.transition_days;
            vdwm_now = 10.0 + frac * (p.target_vdwm - 10.0);
        }
        
        // Network QAP depends on scenario
        // For "all sectors get X" scenarios, we use all_sector_mult
        // For transition scenarios, old sectors keep old QAP, new sectors use new
        double network_qap;
        if (p.all_sector_mult > 0) {
            // All sectors get this multiplier (1x or 10x for all)
            network_qap = rbp * p.all_sector_mult;
        } else {
            // Transition: blend old (10x DC, 1x CC) and new (vdwm_now)
            // Old sectors: QAP = RBP * (0.167 + 0.833 * 10) = 8.5 * RBP
            old_sector_frac = fmax(0.0, 1.0 - (double)(d + 1) * decay_per_day);
            double old_qap_mult = (1.0 - FIL_PLUS_FRAC) + FIL_PLUS_FRAC * 10.0;  // 8.5
            double new_qap_mult = (1.0 - FIL_PLUS_FRAC) + FIL_PLUS_FRAC * vdwm_now;
            double blended_mult = old_sector_frac * old_qap_mult + (1.0 - old_sector_frac) * new_qap_mult;
            network_qap = rbp * blended_mult;
        }
        
        // Minting (RBP-based, unchanged by VDWM)
        double r_bar = fmin(bl, rbp);
        cumsum += r_bar * (double)EPOCHS_PER_DAY;
        double theta = (1.0 / G_DEFAULT) * log(G_DEFAULT * cumsum / B0_EIB + 1.0);
        double sm = M_INF_S * (1.0 - exp(-LAMBDA * (double)epoch));
        double bm = M_INF_B * (1.0 - exp(-LAMBDA * theta));
        double total_minted = sm + bm;
        double daily = total_minted - prev_minted;
        if (daily < 0.0) daily = 0.0;
        prev_minted = total_minted;
        
        // Per-sector reward (32 GiB CC sector, gets 1x QAP in all scenarios)
        double sector_qap_gib = 32.0;
        if (p.all_sector_mult > 0) sector_qap_gib = 32.0 * p.all_sector_mult;
        double total_qap_gib = network_qap * GIB_PER_EIB;
        double daily_reward = daily * sector_qap_gib / total_qap_gib;
        
        // === FIP-0081 PLEDGE FORMULA ===
        double bl_gib = bl * GIB_PER_EIB;
        double denom_baseline = fmax(bl_gib, total_qap_gib);
        
        // Simple component: independent of baseline
        double simple_p = CONSENSUS_TARGET * circ * sector_qap_gib / total_qap_gib;
        
        // Baseline component: depends on baseline
        double baseline_p = CONSENSUS_TARGET * circ * sector_qap_gib / denom_baseline;
        
        // Weighted combination (gamma = 0.7)
        double consensus_p = (1.0 - PLEDGE_GAMMA) * simple_p + PLEDGE_GAMMA * baseline_p;
        
        // Storage pledge
        double storage_p = STORAGE_PLEDGE_DAYS * daily_reward;
        
        double total_pledge = consensus_p + storage_p;
        
        // ROI
        double roi = (total_pledge > 0.0) ? (daily_reward * 365.25 / total_pledge) * 100.0 : 0.0;
        
        // === NETWORK TOTALS ===
        // Total simple consensus pledge (sum across all sectors = 0.3 * 0.3 * circ)
        double net_simple = (1.0 - PLEDGE_GAMMA) * CONSENSUS_TARGET * circ;  // = 0.09 * circ
        
        // Total baseline consensus pledge
        double net_baseline = PLEDGE_GAMMA * CONSENSUS_TARGET * circ * network_qap * GIB_PER_EIB / denom_baseline;
        // Simplify: = 0.21 * circ * NetworkQAP / max(Baseline, NetworkQAP)
        
        double net_consensus = net_simple + net_baseline;
        
        // Total storage pledge ≈ 20 * daily_issuance
        double net_storage = STORAGE_PLEDGE_DAYS * daily;
        
        // Total locked (simplified: new pledge from current sectors)
        // In reality, locked FIL also includes vesting rewards from older sectors
        // We track the steady-state pledge level the network converges toward
        double net_locked = net_consensus + net_storage;
        
        // Circulating supply update
        circ += daily - 2000.0;  // daily minted minus burns
        if (d < 240) circ += 83333.0;  // remaining vesting
        
        // Write output
        out[d].day = d + 1;
        out[d].year = year;
        out[d].simple_pledge = simple_p;
        out[d].baseline_pledge = baseline_p;
        out[d].consensus_pledge = consensus_p;
        out[d].storage_pledge = storage_p;
        out[d].total_pledge = total_pledge;
        out[d].daily_reward = daily_reward;
        out[d].annual_roi_pct = roi;
        out[d].network_qap_eib = network_qap;
        out[d].baseline_eib = bl;
        out[d].network_consensus_pledge = net_consensus;
        out[d].network_storage_pledge = net_storage;
        out[d].network_total_locked = net_locked;
        out[d].circulating_supply = circ;
        out[d].network_simple_total = net_simple;
        out[d].network_baseline_total = net_baseline;
    }
}

// ============================================================
// HOST CODE
// ============================================================

void define_scenarios(PledgeScenario* s) {
    // Scenario 0: Status Quo (VDWM=10, mixed DC/CC)
    s[0] = {10.0, 0.0, -0.05, 0, "StatusQuo_VDWM10"};
    
    // Scenario 1: 1x-for-all (Daybreak target)
    s[1] = {1.0, 1.0, -0.05, 0, "AllSectors_1x"};
    
    // Scenario 2: 10x-for-all (irenegia's alternative)
    s[2] = {10.0, 10.0, -0.05, 0, "AllSectors_10x"};
    
    // Scenario 3: Daybreak transition (10→1 over 12 months, sector turnover)
    s[3] = {1.0, 0.0, -0.05, 365, "Daybreak_12mo_Transition"};
    
    // Scenario 4: 1x-for-all with RBP recovery (+5%/yr)
    s[4] = {1.0, 1.0, 0.05, 0, "AllSectors_1x_RBP_Recovery"};
    
    // Scenario 5: 10x-for-all with RBP recovery (+5%/yr)  
    s[5] = {10.0, 10.0, 0.05, 0, "AllSectors_10x_RBP_Recovery"};
}

void write_csv(const char* dir, const char* name, PledgeDailyOutput* data, int days) {
    char path[256];
    snprintf(path, sizeof(path), "%s/pledge_%s.csv", dir, name);
    FILE* f = fopen(path, "w");
    if (!f) { fprintf(stderr, "Cannot open %s\n", path); return; }
    
    fprintf(f, "day,year,"
               "simple_pledge,baseline_pledge,consensus_pledge,storage_pledge,total_pledge,"
               "daily_reward,annual_roi_pct,"
               "network_qap_eib,baseline_eib,"
               "net_consensus_pledge,net_storage_pledge,net_total_locked,"
               "circulating_supply,net_simple_total,net_baseline_total\n");
    
    for (int i = 0; i < days; i++) {
        PledgeDailyOutput* m = &data[i];
        fprintf(f, "%d,%.4f,"
                   "%.6f,%.6f,%.6f,%.6f,%.6f,"
                   "%.8f,%.4f,"
                   "%.4f,%.2f,"
                   "%.2f,%.2f,%.2f,"
                   "%.2f,%.2f,%.2f\n",
                m->day, m->year,
                m->simple_pledge, m->baseline_pledge, m->consensus_pledge,
                m->storage_pledge, m->total_pledge,
                m->daily_reward, m->annual_roi_pct,
                m->network_qap_eib, m->baseline_eib,
                m->network_consensus_pledge, m->network_storage_pledge,
                m->network_total_locked, m->circulating_supply,
                m->network_simple_total, m->network_baseline_total);
    }
    fclose(f);
    printf("  Written: %s\n", path);
}

int main(int argc, char** argv) {
    const char* outdir = (argc > 1) ? argv[1] : "./pledge_results";
    
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║  FIP-Daybreak: Pledge & Locked FIL Projection               ║\n");
    printf("║  FIP-0081 Formula · 1x vs 10x Convergence Analysis          ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n\n");
    
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("GPU: %s (%d SMs, %.1f GB)\n\n", prop.name, prop.multiProcessorCount, 
           prop.totalGlobalMem / 1e9);
    
    // Phase 1: Genesis cumsum
    printf("Phase 1: Computing genesis cumulative sum...\n");
    double *d_cumsum, *d_minted;
    cudaMalloc(&d_cumsum, sizeof(double));
    cudaMalloc(&d_minted, sizeof(double));
    
    compute_cumsum<<<1,1>>>(d_cumsum, d_minted);
    cudaDeviceSynchronize();
    
    double h_cumsum, h_minted;
    cudaMemcpy(&h_cumsum, d_cumsum, sizeof(double), cudaMemcpyDeviceToHost);
    cudaMemcpy(&h_minted, d_minted, sizeof(double), cudaMemcpyDeviceToHost);
    printf("  Cumsum: %.2f EiB·epochs, Total minted: %.2f M FIL\n\n", h_cumsum, h_minted/1e6);
    
    // Phase 2: Pledge scenarios
    printf("Phase 2: Running %d pledge scenarios (%d years each)...\n", N_SCENARIOS, SIM_YEARS);
    
    PledgeScenario h_params[N_SCENARIOS];
    define_scenarios(h_params);
    
    PledgeScenario* d_params;
    cudaMalloc(&d_params, N_SCENARIOS * sizeof(PledgeScenario));
    cudaMemcpy(d_params, h_params, N_SCENARIOS * sizeof(PledgeScenario), cudaMemcpyHostToDevice);
    
    size_t out_size = N_SCENARIOS * SIM_DAYS * sizeof(PledgeDailyOutput);
    PledgeDailyOutput* d_output;
    cudaMalloc(&d_output, out_size);
    
    simulate_pledge<<<1, N_SCENARIOS>>>(d_params, d_output, h_cumsum, h_minted);
    cudaDeviceSynchronize();
    
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    
    PledgeDailyOutput* h_output = (PledgeDailyOutput*)malloc(out_size);
    cudaMemcpy(h_output, d_output, out_size, cudaMemcpyDeviceToHost);
    
    // Create output dir
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "mkdir -p %s", outdir);
    system(cmd);
    
    // Write CSVs
    for (int i = 0; i < N_SCENARIOS; i++) {
        write_csv(outdir, h_params[i].name, &h_output[i * SIM_DAYS], SIM_DAYS);
    }
    
    // ============================================================
    // SUMMARY TABLE: 1x vs 10x Key Comparison
    // ============================================================
    printf("\n");
    printf("═══════════════════════════════════════════════════════════════════════════\n");
    printf("  1x-FOR-ALL vs 10x-FOR-ALL: PLEDGE & LOCKED FIL COMPARISON\n");
    printf("  (FIP-0081 formula, gamma=0.7)\n");
    printf("═══════════════════════════════════════════════════════════════════════════\n\n");
    
    // Compare scenarios 1 (1x) and 2 (10x) at key timepoints
    int checkpoints[] = {0, 30, 90, 180, 365, 730, 1095, 1460, 1825};
    int n_ck = 9;
    
    printf("  PER-SECTOR (32 GiB CC) PLEDGE:\n");
    printf("  %-8s  %-12s %-12s %-12s %-12s %-10s %-10s\n",
           "Day", "1x Simple", "1x Baseline", "1x Total", "10x Total", "1x ROI%", "10x ROI%");
    printf("  ──────── ──────────── ──────────── ──────────── ──────────── ────────── ──────────\n");
    
    for (int c = 0; c < n_ck; c++) {
        int d = checkpoints[c];
        if (d >= SIM_DAYS) break;
        PledgeDailyOutput* m1 = &h_output[1 * SIM_DAYS + d];  // 1x
        PledgeDailyOutput* m10 = &h_output[2 * SIM_DAYS + d]; // 10x
        printf("  %-8d  %10.4f   %10.4f   %10.4f   %10.4f   %8.1f   %8.1f\n",
               d + 1, m1->simple_pledge, m1->baseline_pledge,
               m1->total_pledge, m10->total_pledge,
               m1->annual_roi_pct, m10->annual_roi_pct);
    }
    
    printf("\n  NETWORK TOTAL LOCKED FIL (M FIL):\n");
    printf("  %-8s  %-14s %-14s %-14s %-14s %-12s\n",
           "Day", "1x Consensus", "10x Consensus", "1x Simple", "1x Baseline");
    printf("  ──────── ────────────── ────────────── ────────────── ────────────── ────────────\n");
    
    for (int c = 0; c < n_ck; c++) {
        int d = checkpoints[c];
        if (d >= SIM_DAYS) break;
        PledgeDailyOutput* m1 = &h_output[1 * SIM_DAYS + d];
        PledgeDailyOutput* m10 = &h_output[2 * SIM_DAYS + d];
        printf("  %-8d  %12.2f   %12.2f   %12.2f   %12.2f\n",
               d + 1,
               m1->network_consensus_pledge / 1e6,
               m10->network_consensus_pledge / 1e6,
               m1->network_simple_total / 1e6,
               m1->network_baseline_total / 1e6);
    }
    
    // Key finding summary
    PledgeDailyOutput* final_1x = &h_output[1 * SIM_DAYS + SIM_DAYS - 1];
    PledgeDailyOutput* final_10x = &h_output[2 * SIM_DAYS + SIM_DAYS - 1];
    PledgeDailyOutput* day1_1x = &h_output[1 * SIM_DAYS + 0];
    PledgeDailyOutput* day1_10x = &h_output[2 * SIM_DAYS + 0];
    
    printf("\n═══ KEY FINDINGS ═══\n\n");
    printf("  Day 1:\n");
    printf("    1x per-sector pledge:  %.4f FIL (simple=%.4f + baseline=%.4f)\n",
           day1_1x->total_pledge, day1_1x->simple_pledge, day1_1x->baseline_pledge);
    printf("    10x per-sector pledge: %.4f FIL (simple=%.4f + baseline=%.4f)\n",
           day1_10x->total_pledge, day1_10x->simple_pledge, day1_10x->baseline_pledge);
    printf("    Difference: %.4f FIL/sector (%.1f%%)\n",
           day1_10x->total_pledge - day1_1x->total_pledge,
           100.0 * (day1_10x->total_pledge - day1_1x->total_pledge) / day1_1x->total_pledge);
    printf("    1x ROI: %.1f%%  vs  10x ROI: %.1f%%\n",
           day1_1x->annual_roi_pct, day1_10x->annual_roi_pct);
    
    printf("\n  Network locking (Day 1):\n");
    printf("    1x total consensus pledge: %.2f M FIL\n", day1_1x->network_consensus_pledge / 1e6);
    printf("    10x total consensus pledge: %.2f M FIL\n", day1_10x->network_consensus_pledge / 1e6);
    printf("    Difference: %.2f M FIL (%.1f%% of circulating)\n",
           (day1_10x->network_consensus_pledge - day1_1x->network_consensus_pledge) / 1e6,
           100.0 * (day1_10x->network_consensus_pledge - day1_1x->network_consensus_pledge) / CURRENT_CIRC_FIL);
    printf("    Simple component (IDENTICAL): %.2f M FIL\n", day1_1x->network_simple_total / 1e6);
    printf("    Baseline diff: %.2f M FIL (shrinks as baseline grows)\n",
           (day1_10x->network_baseline_total - day1_1x->network_baseline_total) / 1e6);
    
    printf("\n  Year %d:\n", SIM_YEARS);
    printf("    1x network consensus pledge: %.2f M FIL\n", final_1x->network_consensus_pledge / 1e6);
    printf("    10x network consensus pledge: %.2f M FIL\n", final_10x->network_consensus_pledge / 1e6);
    printf("    Baseline component gap narrowed to: %.2f M FIL\n",
           (final_10x->network_baseline_total - final_1x->network_baseline_total) / 1e6);
    printf("    Baseline at year %d: %.0f EiB (dwarfs any QAP scenario)\n",
           SIM_YEARS, final_1x->baseline_eib);
    
    printf("\n═══ CONCLUSION ═══\n");
    printf("  FIP-0081's simple pledge floor is IDENTICAL under 1x and 10x.\n");
    printf("  The difference is ONLY in the baseline component, which shrinks\n");
    printf("  to irrelevance as the baseline grows at 100%%/year.\n");
    printf("  1x gives better ROI (lower pledge per sector, same rewards).\n");
    printf("  The ~%.0f M FIL locking difference is temporary.\n\n",
           (day1_10x->network_consensus_pledge - day1_1x->network_consensus_pledge) / 1e6);
    
    printf("Results written to: %s/\n", outdir);
    
    // Cleanup
    free(h_output);
    cudaFree(d_cumsum); cudaFree(d_minted);
    cudaFree(d_params); cudaFree(d_output);
    
    return 0;
}
