"""Numerical check of Rosen's diagonal-strict-concavity condition (paper Appendix A) for the V3 payoff.
Pseudo-gradient g(r) = dU_n/dr_n^m. Condition: symmetric part of its Jacobian is negative definite."""
import numpy as np
import stackelberg_core as sc
P = np.array([100., 200.]); CAP, PHI = 0.35, 0.8
N, M = 4, 2
def grad(r, cap):
    g = np.zeros((N, M))
    for n in range(N):
        for m in range(M):
            S = r[:, m].sum() - r[n, m]; x = r[n, m]
            share = x / (x + S + 1e-12)
            d = PHI * P[m] * S / (x + S + 1e-12) ** 2 if (cap is None or share < cap) else 0.0
            g[n, m] = d - sc.C[n]
    return g
def jac(r, cap, h=1e-5):
    J = np.zeros((N*M, N*M)); base = grad(r, cap).ravel()
    for k in range(N*M):
        rp = r.copy().ravel(); rp[k] += h
        J[:, k] = (grad(rp.reshape(N, M), cap).ravel() - base) / h
    return J
rng = np.random.default_rng(1)
for label, cap in [("paper payoff (no cap)", None), ("V3 payoff (cap 35%)", CAP)]:
    nd = nsd = tot = 0; capped_players = []
    for _ in range(3000):
        r = rng.uniform(1, 150, (N, M)); J = jac(r, cap); w = np.linalg.eigvalsh((J + J.T) / 2)
        tot += 1; nd += w.max() < -1e-9; nsd += w.max() < 1e-7
        sh = r / r.sum(axis=0); capped_players.append((sh >= CAP).sum())
    print(f"{label:24s}: negative definite {nd/tot*100:5.1f}% | negative semidefinite {nsd/tot*100:5.1f}% | avg capped (player,shard) cells {np.mean(capped_players):.2f}")

# at the actual V3 equilibrium
r_eq = sc.follower_equilibrium(P, cap=CAP, phi=np.full(4, PHI))
J = jac(r_eq, CAP); w = np.linalg.eigvalsh((J + J.T) / 2)
sh = r_eq / r_eq.sum(axis=0)
print("V3 equilibrium shares per MU (rows) x shard:\n", sh.round(3))
print("max eigenvalue of sym(J) at V3 equilibrium:", round(w.max(), 5))
