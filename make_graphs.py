"""
FairMetaChain: V1 vs V2 graphs (2D + 3D).
Run from the project folder (where the CSV files are):
    pip install pandas matplotlib numpy
    python make_graphs.py
Output: ./graphs/*.png
"""
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

OUT = "graphs"
os.makedirs(OUT, exist_ok=True)
C1, C2 = "#e4572e", "#2e86ab"   # V1, V2 colours
BUDGET = {"V1": 10000.0, "V2": 2000.0}  # reward budget per epoch (V2 opens 20% of pool)

f1 = pd.read_csv("fairness_results_FairMetaChain.csv")
f2 = pd.read_csv("fairness_results_FairMetaChainV2.csv")
g1 = pd.read_csv("gas_results_FairMetaChain.csv")
g2 = pd.read_csv("gas_results_FairMetaChainV2.csv")
f1["payoutPct"] = f1["reward"] / BUDGET["V1"] * 100   # normalised so V1 and V2 are comparable
f2["payoutPct"] = f2["reward"] / BUDGET["V2"] * 100

def save(name):
    plt.tight_layout()
    plt.savefig(f"{OUT}/{name}", dpi=200)
    plt.close()
    print("saved", f"{OUT}/{name}")

# ---------- 2D ----------
# 1. Scenario 1: payout % per user
s1a, s1b = f1[f1.scenario.str.startswith("S1")], f2[f2.scenario.str.startswith("S1")]
x = np.arange(len(s1a)); w = 0.38
plt.figure(figsize=(7, 4.5))
plt.bar(x - w/2, s1a.payoutPct, w, label="V1", color=C1)
plt.bar(x + w/2, s1b.payoutPct, w, label="V2", color=C2)
plt.xticks(x, [f"{u}\n({c})" for u, c in zip(s1a.user, s1a.contributed)])
plt.axhline(35 * 0.45, ls="--", c="gray", lw=1, label="V1 cap ceiling (15.75%)")
plt.ylabel("Payout (% of epoch budget)"); plt.title("Scenario 1: payout vs contribution size")
plt.legend(); save("01_payout_by_user.png")

# 2. Raw share vs payout (cap visible)
plt.figure(figsize=(6.5, 4.5))
plt.plot(s1a.rawSharePct, s1a.payoutPct, "o-", c=C1, label="V1")
plt.plot(s1b.rawSharePct, s1b.payoutPct, "s-", c=C2, label="V2")
plt.xlabel("Raw contribution share (%)"); plt.ylabel("Payout (% of epoch budget)")
plt.title("Share vs payout (35% cap flattens the top)"); plt.legend(); plt.grid(alpha=.3)
save("02_share_vs_payout.png")

# 3. Sybil: honest single account vs attacker (4 accounts), same total contribution
def sybil(df):
    s = df[df.scenario.str.startswith("S2")]
    return s[s.user.str.startswith("Honest")].payoutPct.sum(), s[s.user.str.startswith("Atk")].payoutPct.sum()
h1, a1 = sybil(f1); h2, a2 = sybil(f2)
plt.figure(figsize=(6.5, 4.5))
x = np.arange(2)
plt.bar(x - w/2, [h1, h2], w, label="Honest (1 account)", color="#5b8e7d")
plt.bar(x + w/2, [a1, a2], w, label="Attacker (4 accounts)", color="#bc4b51")
plt.xticks(x, ["V1", "V2 (permissionless)"]); plt.ylabel("Payout (% of epoch budget)")
plt.title(f"Sybil test: attacker gain x{a1/h1:.2f} (V1), x{a2/h2:.2f} (V2)"); plt.legend()
save("03_sybil_test.png")

# 4. Gas comparison
m = g1.merge(g2, on="function", suffixes=("_v1", "_v2"))
x = np.arange(len(m))
plt.figure(figsize=(7.5, 4.5))
plt.bar(x - w/2, m.avgGas_v1, w, label="V1", color=C1)
plt.bar(x + w/2, m.avgGas_v2, w, label="V2", color=C2)
for i, (a, b) in enumerate(zip(m.avgGas_v1, m.avgGas_v2)):
    plt.text(i + w/2, b, f"{(b-a)/a*100:+.0f}%", ha="center", va="bottom", fontsize=8)
plt.xticks(x, m.function, rotation=15); plt.ylabel("Average gas used")
plt.title("Gas cost per function"); plt.legend(); save("04_gas_comparison.png")

# ---------- 3D ----------
CAP, PHI_MIN = 0.35, 0.45

# 5. Reward surface: raw share x reputation -> payout (% of budget)
share = np.linspace(0, 1, 60)
rep = np.linspace(0, 1, 60)           # reputation / 10000
S, R = np.meshgrid(share, rep)
v1_rep = np.minimum(R, 0.08)          # V1: reputation can never exceed ~800/10000
Z1 = np.minimum(S, CAP) * np.maximum(v1_rep, PHI_MIN) * 100
Z2 = np.minimum(S, CAP) * np.maximum(R, PHI_MIN) * 100
fig = plt.figure(figsize=(12, 5))
for i, (Z, t, cm) in enumerate([(Z1, "V1: reputation has no effect", "Reds"), (Z2, "V2: reputation changes payout", "Blues")]):
    ax = fig.add_subplot(1, 2, i + 1, projection="3d")
    ax.plot_surface(S * 100, R * 10000, Z, cmap=cm, edgecolor="none", alpha=.9)
    ax.set_xlabel("Raw share (%)"); ax.set_ylabel("Reputation"); ax.set_zlabel("Payout (% of budget)")
    ax.set_zlim(0, 35); ax.set_title(t); ax.view_init(25, -125)
save("05_3d_reward_surface.png")

# 6. Sybil gain surface: number of fake accounts x total share -> gain ratio
n = np.arange(1, 11)
tot = np.linspace(0.05, 1.0, 40)
N, T = np.meshgrid(n, tot)
gain = (N * np.minimum(T / N, CAP)) / np.minimum(T, CAP)
fig = plt.figure(figsize=(7.5, 5.5))
ax = fig.add_subplot(111, projection="3d")
ax.plot_surface(N, T * 100, gain, cmap="inferno", edgecolor="none", alpha=.9)
ax.plot_surface(N, T * 100, np.ones_like(gain), color="#2e86ab", alpha=.35)   # permissioned mode = 1.0
ax.set_xlabel("Fake accounts (splits)"); ax.set_ylabel("Attacker total share (%)"); ax.set_zlabel("Gain vs 1 account")
ax.set_title("Sybil gain (surface) vs permissioned registry (blue plane = 1.0x)"); ax.view_init(25, -60)
save("06_3d_sybil_gain.png")

# 7. 3D bars: user x version -> payout
users = list(s1a.user)
fig = plt.figure(figsize=(8, 5.5))
ax = fig.add_subplot(111, projection="3d")
for k, (df, col) in enumerate([(s1a, C1), (s1b, C2)]):
    ax.bar3d(np.arange(len(users)), np.full(len(users), k), np.zeros(len(users)), 0.5, 0.5, df.payoutPct.values, color=col, alpha=.85)
ax.set_xticks(np.arange(len(users)) + .25); ax.set_xticklabels(users)
ax.set_yticks([.25, 1.25]); ax.set_yticklabels(["V1", "V2"])
ax.set_zlabel("Payout (% of budget)"); ax.set_title("Scenario 1 payouts, V1 vs V2"); ax.view_init(28, -55)
save("07_3d_bars_users.png")

# 8. 3D bars: gas function x version
fig = plt.figure(figsize=(8, 5.5))
ax = fig.add_subplot(111, projection="3d")
for k, (col, vals) in enumerate([(C1, m.avgGas_v1), (C2, m.avgGas_v2)]):
    ax.bar3d(np.arange(len(m)), np.full(len(m), k), np.zeros(len(m)), 0.5, 0.5, vals.values, color=col, alpha=.85)
ax.set_xticks(np.arange(len(m)) + .25); ax.set_xticklabels(m.function, fontsize=7, rotation=15)
ax.set_yticks([.25, 1.25]); ax.set_yticklabels(["V1", "V2"])
ax.set_zlabel("Avg gas"); ax.set_title("Gas per function, V1 vs V2"); ax.view_init(28, -55)
save("08_3d_bars_gas.png")
print("done")
