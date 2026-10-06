"""
Stackelberg simulation for MetaChain (paper) vs FairMetaChain V3.
Run:  pip install numpy scipy matplotlib   then   python stackelberg_sim.py
Output: ./graphs_sim/*.png  + printed results
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401
from scipy.optimize import minimize
import stackelberg_core as sc

OUT = "graphs_sim"; os.makedirs(OUT, exist_ok=True)
def save(n):
    plt.tight_layout(); plt.savefig(f"{OUT}/{n}", dpi=200); plt.close(); print("saved", n)

CAP, PHI = 0.35, 0.8   # V3 payoff: capped share x reputation factor

# ---------- 1. Paper Fig 2: one MU's utility surface ----------
P_, T_, Cn, Rn = np.array([1000., 2000.]), np.array([100., 300.]), 5.0, 100.0
def u_mu(r1, r2): return r1/(r1+T_[0])*P_[0] + r2/(r2+T_[1])*P_[1] - Cn*(r1+r2)
res = minimize(lambda x: -u_mu(*x), [10, 10], bounds=[(0, Rn)]*2, constraints=[{"type": "ineq", "fun": lambda x: Rn-x.sum()}])
print(f"[Fig2] MU optimum r=({res.x[0]:.2f},{res.x[1]:.2f}) U*={-res.fun:.2f}   (paper: 41.42, 46.41, 121.68)")
a, b = np.meshgrid(np.linspace(0, 100, 80), np.linspace(0, 100, 80))
Z = np.where(a+b <= Rn, u_mu(a, b), np.nan)
fig = plt.figure(figsize=(7, 5)); ax = fig.add_subplot(111, projection="3d")
ax.plot_surface(a, b, Z, cmap="viridis", edgecolor="none", alpha=.9)
ax.scatter(*res.x, -res.fun, c="r", s=50, label=f"optimum U*={-res.fun:.1f}")
ax.set_xlabel("r1 (shard 1)"); ax.set_ylabel("r2 (shard 2)"); ax.set_zlabel("MU utility"); ax.legend()
ax.set_title("MU utility surface (reproduces paper Fig. 2)"); save("01_mu_utility_3d.png")

# ---------- 2. Paper Fig 3 vs V3: convergence of MU strategies ----------
P = np.array([100., 200.])
fig, axs = plt.subplots(2, 2, figsize=(10, 6.5))
for row, (label, kw) in enumerate([("Paper (pay-per-share)", {}), ("V3 (cap 35% x phi 0.8)", {"cap": CAP, "phi": np.full(4, PHI)})]):
    r, hist = sc.follower_equilibrium(P, history=True, **kw)
    H = np.array(hist)
    for m in range(2):
        for n in range(4): axs[row, m].plot(H[:, n, m], marker="o", ms=3, label=f"MU{n+1}")
        axs[row, m].set_title(f"{label}: shard {m+1}"); axs[row, m].set_xlabel("iteration"); axs[row, m].set_ylabel("resources")
    print(f"[Fig3] {label}: equilibrium contributions per MU (rows) x shard:\n{r.round(1)}  converged in {len(hist)-1} iterations")
axs[0, 0].legend(fontsize=7); save("02_convergence.png")

# ---------- 3. Paper Fig 4/5 + V3: MSP utility, leader optimum ----------
g = np.arange(1, 21)
def eq_grid(**kw):
    return {(p1, p2): sc.follower_equilibrium(np.array([p1, p2], float), **kw) for p1 in g for p2 in g}
EQ_paper = eq_grid()
EQ_v3 = eq_grid(cap=CAP, phi=np.full(4, PHI))
def leader_surface(EQ, alpha):
    Zs = np.array([[sc.leader_utility(alpha, [p1, p2], EQ[(p1, p2)]) for p1 in g] for p2 in g])
    i = np.unravel_index(np.argmax(Zs), Zs.shape)
    return Zs, (g[i[1]], g[i[0]], Zs[i])
fig = plt.figure(figsize=(13, 9))
k = 1
for name, EQ in [("Paper payoff", EQ_paper), ("V3 payoff (cap 35%, phi 0.8)", EQ_v3)]:
    for alpha in [(4, 6), (10, 15)]:
        Zs, (p1, p2, u) = leader_surface(EQ, alpha)
        tot = EQ[(p1, p2)].sum(axis=0)
        print(f"[MSP] {name:30s} alpha={alpha} -> P*=({p1},{p2}) UL*={u:.2f} total resources/shard={tot.round(1)}")
        ax = fig.add_subplot(2, 2, k, projection="3d"); k += 1
        X, Y = np.meshgrid(g, g)
        ax.plot_surface(X, Y, Zs, cmap="plasma", edgecolor="none", alpha=.9)
        ax.scatter(p1, p2, u, c="k", s=40)
        ax.set_xlabel("P1"); ax.set_ylabel("P2"); ax.set_zlabel("MSP utility")
        ax.set_title(f"{name}\nalpha={alpha}: P*=({p1},{p2})", fontsize=9)
save("03_msp_utility_3d.png")

# ---------- 4. Sybil economics (matches contract: cap, warm-up, one-time fee) ----------
def phi_traj(T, init=0.2, big=0.8):
    p, out = init, []
    for _ in range(T):
        p = p*0.8 + big*0.2; out.append(p)
    return np.array(out)
def split_profit(n, fee, T=4, P=120., H=1000., s=1000., cap=CAP, gas=0.1):
    ph = phi_traj(T)
    Rn = sum(n*ph_k*P*min((s/n)/(s+H), cap) for ph_k in ph)
    R1 = sum(ph_k*P*min(s/(s+H), cap) for ph_k in ph)
    return (Rn - R1) - (n-1)*fee - (n-1)*gas*T
nn, ff = np.meshgrid(np.arange(1, 11), np.linspace(0, 60, 40))
Zp = np.vectorize(split_profit)(nn, ff)
fig = plt.figure(figsize=(8, 5.8)); ax = fig.add_subplot(111, projection="3d")
ax.plot_surface(nn, ff, Zp, cmap="coolwarm", edgecolor="none", alpha=.9)
ax.plot_surface(nn, ff, np.zeros_like(Zp), color="k", alpha=.25)
ax.set_xlabel("Fake accounts n"); ax.set_ylabel("Registration fee (tokens)"); ax.set_zlabel("Profit from splitting (tokens)")
ax.set_title("Sybil profit over 4 epochs: above plane = attack pays"); ax.view_init(25, -120); save("04_sybil_fee_3d.png")
be = [next((f for f in np.linspace(0, 60, 601) if split_profit(n, f) <= 0), None) for n in (2, 4, 8)]
print(f"[Sybil] break-even fee (profit<=0, 4 epochs): n=2:{be[0]:.1f}  n=4:{be[1]:.1f}  n=8:{be[2]:.1f} tokens")

# ---------- 5. Fairness vs Sybil trade-off by cap (3D + Pareto) ----------
contrib = np.array([50, 200, 500, 1000.]); share = contrib/contrib.sum()
caps = np.linspace(0.30, 1.0, 36)
top1 = [min(share.max(), c)/np.minimum(share, c).sum()*100 for c in caps]
x_att = 0.5
def gain(c, n): return n*min(x_att/n, c)/min(x_att, c)
gain4 = [gain(c, 4) for c in caps]
fig, ax1 = plt.subplots(figsize=(7, 4.5))
ax1.plot(caps*100, top1, c="#2e86ab", label="Top contributor's share of payout (%)"); ax1.set_xlabel("Share cap (%)"); ax1.set_ylabel("Top-1 payout share (%)", color="#2e86ab")
ax2 = ax1.twinx(); ax2.plot(caps*100, gain4, c="#e4572e", label="Sybil gain (4 accounts)"); ax2.set_ylabel("Sybil gain factor", color="#e4572e")
ax1.set_title("Fairness vs Sybil-resistance trade-off (cap 100% = paper's pay-per-share)"); save("05_cap_tradeoff.png")
cc, nn2 = np.meshgrid(caps, np.arange(1, 11))
G = np.vectorize(gain)(cc, nn2)
fig = plt.figure(figsize=(7.5, 5.5)); ax = fig.add_subplot(111, projection="3d")
ax.plot_surface(cc*100, nn2, G, cmap="inferno", edgecolor="none", alpha=.9)
ax.set_xlabel("Share cap (%)"); ax.set_ylabel("Fake accounts n"); ax.set_zlabel("Sybil gain factor")
ax.set_title("Sybil gain vs cap and number of splits (no fee)"); ax.view_init(25, -55); save("06_sybil_gain_vs_cap_3d.png")

# ---------- 6. Numerical uniqueness check (random starts reach same equilibrium) ----------
# strict solver tolerance: a loose tolerance (ftol 1e-6) leaves ~0.5-2 resource units of solver noise
rng = np.random.default_rng(0); eqs = []
for _ in range(8):
    r = rng.uniform(1, 50, (4, 2))
    for _ in range(500):
        old = r.copy()
        for n in range(4): r[n] = sc.best_response(n, r, np.array([100., 200.]), CAP, np.full(4, PHI), ftol=1e-12)
        if np.abs(r-old).max() < 1e-6: break
    eqs.append(r.copy())
print(f"[Uniqueness] V3 payoff, 8 random starts, strict tolerance: max deviation between equilibria = {max(np.abs(e-eqs[0]).max() for e in eqs):.6f}")
print("done")