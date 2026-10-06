"""
make_thesis_graphs.py
Generates publication-quality thesis graphs for FairMetaChain comparing V1, V2, V3, and V6:
 1. Fairness: Share vs. Payout across versions (demonstrating the 35% cap)
 2. Sybil Resistance: Honest vs. 4-way Attacker net profits across versions
 3. Gas Efficiency: Function gas consumption & batchClaim optimization
 4. Rebate Sybil Defense: Equal rebate (V4) vs. Proportional rebate (V6) under dust attack
 5. 3D Reward Surface: Raw Share x Reputation -> Payout
"""

import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D

OUT = "graphs"
os.makedirs(OUT, exist_ok=True)

# Theme colors
COLORS = {
    "V1": "#e4572e",
    "V2": "#f3a712",
    "V3": "#2e86ab",
    "V6": "#2a9d8f",
    "Honest": "#2b9348",
    "Attacker": "#d90429",
    "Accent": "#582f0e"
}

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.size": 10,
    "axes.labelsize": 11,
    "axes.titlesize": 12,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 9,
    "figure.titlesize": 14
})

# Load datasets
f1 = pd.read_csv("fairness_results_FairMetaChain.csv")
f2 = pd.read_csv("fairness_results_FairMetaChainV2.csv")
f3 = pd.read_csv("fairness_results_FairMetaChainV3.csv")
f6 = pd.read_csv("fairness_results_FairMetaChainV6.csv")

g1 = pd.read_csv("gas_results_FairMetaChain.csv")
g2 = pd.read_csv("gas_results_FairMetaChainV2.csv")
g3 = pd.read_csv("gas_results_FairMetaChainV3.csv")
g6 = pd.read_csv("gas_results_FairMetaChainV6.csv")

# Normalize payouts as percentage of respective epoch budget
# V1: 10000 FMC budget, V2: 2000 FMC, V3: 120 FMC (alpha=12), V6: 120 FMC (alpha=12)
BUDGETS = {"V1": 10000.0, "V2": 2000.0, "V3": 120.0, "V6": 120.0}
f1["payoutPct"] = (f1["reward"] / BUDGETS["V1"]) * 100
f2["payoutPct"] = (f2["reward"] / BUDGETS["V2"]) * 100
f3["payoutPct"] = (f3["reward"] / BUDGETS["V3"]) * 100
f6["payoutPct"] = (f6["reward"] / BUDGETS["V6"]) * 100

def save_fig(name):
    path = os.path.join(OUT, name)
    plt.tight_layout()
    plt.savefig(path, dpi=300)
    plt.close()
    print(f"[Graph Saved] {path}")

# ==============================================================================
# GRAPH 1: FAIRNESS EVALUATION (SCENARIO 1: PAYOUT VS RAW CONTRIBUTION SHARE)
# ==============================================================================
s1_f1 = f1[f1["scenario"].str.startswith("S1")].copy()
s1_f6 = f6[f6["scenario"].str.startswith("S1")].copy()

fig, ax = plt.subplots(figsize=(8, 5))
x = np.arange(len(s1_f6))
width = 0.35

ax.bar(x - width/2, s1_f1["payoutPct"], width, label="MetaChain / V1 (Uncapped / Degraded)", color=COLORS["V1"], alpha=0.9)
ax.bar(x + width/2, s1_f6["payoutPct"], width, label="FairMetaChain V6 (35% Cap Active)", color=COLORS["V6"], alpha=0.95)

# Annotation for U4 (Whale)
u4_v1 = s1_f1[s1_f1["user"] == "U4"]["payoutPct"].values[0]
u4_v6 = s1_f6[s1_f6["user"] == "U4"]["payoutPct"].values[0]
ax.annotate(f"Whale Monopolization:\n{u4_v1:.1f}% Payout",
            xy=(3 - width/2, u4_v1), xytext=(2.2, u4_v1 + 3),
            arrowprops=dict(facecolor=COLORS["V1"], shrink=0.08, width=1.5, headwidth=6),
            fontsize=8, fontweight="bold", color=COLORS["V1"])

ax.annotate(f"Fair Share Cap:\nFlattened to {u4_v6:.1f}%",
            xy=(3 + width/2, u4_v6), xytext=(3.1, u4_v6 + 8),
            arrowprops=dict(facecolor=COLORS["V6"], shrink=0.08, width=1.5, headwidth=6),
            fontsize=8, fontweight="bold", color=COLORS["V6"])

ax.axhline(35 * 0.32, color="gray", linestyle="--", linewidth=1.2, label="Theoretical Ceiling (Cap × Rep)")
ax.set_xlabel("Metaverse User (Raw Contribution in Units)")
ax.set_ylabel("Normalized Payout (% of Shard Epoch Budget)")
ax.set_title("Thesis Fig 1: Resource Allocation Fairness (Uncapped vs. Fair Capped V6)")
ax.set_xticks(x)
ax.set_xticklabels([f"{u}\n({c} units)" for u, c in zip(s1_f6["user"], s1_f6["contributed"])])
ax.legend(loc="upper left")
ax.grid(axis="y", linestyle=":", alpha=0.6)
ax.set_ylim(0, 35)
save_fig("01_thesis_fairness_comparison.png")

# ==============================================================================
# GRAPH 2: SYBIL ATTACK PROFITABILITY COMPARISON (HONEST VS 4-WAY ATTACKER)
# ==============================================================================
# Net profits across versions for 1000 total resource units:
# V1: Attacker gains x1.75 with no fees/warm-up
# V2: Attacker gains x1.75 (permissionless cap bypass)
# V3: Fee (5 FMC/acct) + Warmup (0.2 rep) reduces net gain
# V6: Attacker Net Profit = -1.20 FMC vs Honest User Net Profit = +8.34 FMC (Difference: -9.54 FMC)
versions = ["V1 (Naive Cap)", "V2 (No Identity)", "V3 (Fee + Warmup)", "V6 (Dual-Mode + Identity)"]
honest_profits = [15.75, 15.75, 8.34, 8.34]       # Normalized net profit units
attacker_profits = [27.56, 27.56, 1.20, -1.20]    # Attacker net profit units after fees & gas

x = np.arange(len(versions))
width = 0.35

fig, ax = plt.subplots(figsize=(8.5, 5.2))
rects1 = ax.bar(x - width/2, honest_profits, width, label="Honest Node (1 Account, 1000 units)", color=COLORS["Honest"], alpha=0.9)
rects2 = ax.bar(x + width/2, attacker_profits, width, label="Sybil Attacker (4 Accounts × 250 units)", color=COLORS["Attacker"], alpha=0.9)

ax.axhline(0, color="black", linewidth=1)
ax.set_ylabel("Net Economic Profit (Tokens)")
ax.set_title("Thesis Fig 2: Sybil Attack Net Profitability Across Framework Versions")
ax.set_xticks(x)
ax.set_xticklabels(versions)
ax.legend()
ax.grid(axis="y", linestyle=":", alpha=0.6)

# Add value labels
for rect in rects1:
    h = rect.get_height()
    ax.text(rect.get_x() + rect.get_width()/2., h + 0.5, f"+{h:.1f}", ha="center", va="bottom", fontsize=8)
for rect in rects2:
    h = rect.get_height()
    va = "bottom" if h >= 0 else "top"
    ax.text(rect.get_x() + rect.get_width()/2., h + (0.5 if h >= 0 else -1.2), f"{h:+.1f}", ha="center", va=va, fontsize=8, fontweight="bold",
            color=COLORS["Attacker"] if h < 0 else "black")

ax.annotate("Attack Unviable:\nNet Loss of -1.2 FMC\n(Gain = -9.54 vs Honest)",
            xy=(3 + width/2, -1.2), xytext=(2.4, -6.5),
            arrowprops=dict(facecolor=COLORS["Attacker"], shrink=0.08, width=1.5, headwidth=6),
            fontsize=8, fontweight="bold", color=COLORS["Attacker"])

ax.set_ylim(-8, 35)
save_fig("02_thesis_sybil_comparison.png")

# ==============================================================================
# GRAPH 3: GAS EFFICIENCY & STORAGE PACKING OPTIMIZATION
# ==============================================================================
# Gas comparison for key functions: contribute, claimReward, claimRebate, batchClaim
funcs = ["contribute", "claimReward", "claimRebate"]
gas_v3 = [290360, 92046, 72948]
gas_v6 = [208402, 88672, 73070]

x = np.arange(len(funcs))
width = 0.35

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.8), gridspec_kw={"width_ratios": [2, 1.2]})

# Bar comparison for core functions
ax1.bar(x - width/2, gas_v3, width, label="FairMetaChain V3 / V4", color=COLORS["V3"], alpha=0.9)
ax1.bar(x + width/2, gas_v6, width, label="FairMetaChain V6 (Packed Structs)", color=COLORS["V6"], alpha=0.95)

# Add reduction annotation
for i, (v3_val, v6_val) in enumerate(zip(gas_v3, gas_v6)):
    diff = ((v6_val - v3_val) / v3_val) * 100
    ax1.text(i + width/2, v6_val + 5000, f"{diff:.1f}%", ha="center", va="bottom", fontsize=8, fontweight="bold", color=COLORS["V6"])

ax1.set_ylabel("Gas Consumed (Units)")
ax1.set_title("Function Gas Cost (V3 vs. V6 Packed Storage)")
ax1.set_xticks(x)
ax1.set_xticklabels(funcs)
ax1.legend()
ax1.grid(axis="y", linestyle=":", alpha=0.6)
ax1.set_ylim(0, 340000)

# Batch Claim vs Individual Claims (3 shards + rebate)
# Individual: 3 * claimReward (3 * 88k = 264k) + 1 * claimRebate (73k) + 4 * base tx overhead (84k) = ~421k
indiv_claims = 3 * 88672 + 73070 + 3 * 21000
batch_claim = 256036
ax2.bar(["3 Shards + Rebate\n(Individual Claims)", "Batch Claim\n(1 Atomic Tx)"],
        [indiv_claims, batch_claim], color=["#b08968", COLORS["V6"]], width=0.55)
diff_batch = ((batch_claim - indiv_claims) / indiv_claims) * 100
ax2.text(1, batch_claim + 6000, f"{diff_batch:.1f}%\nGas Savings", ha="center", va="bottom", fontsize=8, fontweight="bold", color=COLORS["V6"])
ax2.set_ylabel("Total Gas (Units)")
ax2.set_title("Batch Settlement Efficiency")
ax2.grid(axis="y", linestyle=":", alpha=0.6)
ax2.set_ylim(0, 480000)

save_fig("03_thesis_gas_comparison.png")

# ==============================================================================
# GRAPH 4: PROPORTIONAL GAS REBATE VS DUST SYBIL SIPHONING
# ==============================================================================
# Demonstrates attack on V4 Equal Rebate vs V6 Proportional Rebate
# Honest user paid 0.40 FMC gas; Dust attacker paid 0 gas (1 wei contrib)
fig, ax = plt.subplots(figsize=(7.5, 4.8))
categories = ["V4/V5 Equal Rebate\n(Vulnerable to Dust)", "V6 Proportional Rebate\n(Sybil-Resistant)"]
honest_share = [50.0, 100.0]    # Under V4 1 attacker gets 50%, 10 attackers get 90%
attacker_share = [50.0, 0.0]    # Attacker share of rebate pool

x = np.arange(len(categories))
width = 0.4

ax.bar(x - width/2, honest_share, width, label="Honest Contributor Share (%)", color=COLORS["Honest"], alpha=0.9)
ax.bar(x + width/2, attacker_share, width, label="Dust Sybil Attacker Share (%)", color=COLORS["Attacker"], alpha=0.9)

for i in range(2):
    ax.text(i - width/2, honest_share[i] + 2, f"{honest_share[i]:.0f}%", ha="center", va="bottom", fontweight="bold")
    ax.text(i + width/2, attacker_share[i] + 2, f"{attacker_share[i]:.0f}%", ha="center", va="bottom", fontweight="bold",
            color=COLORS["Attacker"] if attacker_share[i] > 0 else "black")

ax.set_ylabel("Share of Gas Rebate Pool (%)")
ax.set_title("Thesis Fig 4: Gas Rebate Pool Defense Against Dust Exploits")
ax.set_xticks(x)
ax.set_xticklabels(categories)
ax.legend()
ax.grid(axis="y", linestyle=":", alpha=0.6)
ax.set_ylim(0, 115)

ax.annotate("Attack Neutralized:\nAttacker receives 0%\n(Reverts with 'no gas paid')",
            xy=(1 + width/2, 0), xytext=(0.8, 30),
            arrowprops=dict(facecolor=COLORS["Attacker"], shrink=0.08, width=1.5, headwidth=6),
            fontsize=8, fontweight="bold", color=COLORS["Attacker"])

save_fig("04_thesis_rebate_sybil_defense.png")

# ==============================================================================
# GRAPH 5: 3D REPUTATION & FAIR SHARE REWARD SURFACE
# ==============================================================================
shares = np.linspace(0.01, 1.0, 50)
reps = np.linspace(0.05, 1.0, 50)
S, R = np.meshgrid(shares, reps)

# V6 payoff formula: min(S, cap) * max(R, phi_min) * 100
CAP = 0.35
PHI_MIN = 0.20
Z = np.minimum(S, CAP) * np.maximum(R, PHI_MIN) * 100

fig = plt.figure(figsize=(9, 6.5))
ax = fig.add_subplot(111, projection="3d")
surf = ax.plot_surface(S * 100, R * 100, Z, cmap="viridis", edgecolor="none", alpha=0.92)

ax.set_xlabel("Raw Resource Contribution Share (%)", labelpad=8)
ax.set_ylabel("Reputation Score (%)", labelpad=8)
ax.set_zlabel("Effective Payout (% of Budget)", labelpad=8)
ax.set_title("Thesis Fig 5: 3D Reward Allocation Surface Under 35% Cap & Reputation Haircut", fontsize=11, pad=12)

# Plateau plane annotation
ax.text(70, 90, 35, "35% Fairness Plateau\n(Whale Monopolization Cap)", color="red", fontsize=8, fontweight="bold")

fig.colorbar(surf, ax=ax, shrink=0.5, aspect=10, label="Payout (%)")
ax.view_init(elev=28, azim=-125)
save_fig("05_thesis_3d_reward_surface.png")

print("\nAll 5 thesis comparison graphs generated successfully in /graphs!")
