"""Stackelberg core (paper eq. 3-6). Followers = MUs, leader = MSP."""
import numpy as np
from scipy.optimize import minimize

R = np.array([100., 200., 300., 500.])     # MU capacities (paper Sec. IV)
C = np.array([0.2, 0.1, 0.3, 0.2])          # unit costs
EPS = 1e-9

def payoff_share(r_n, others, P, cap=None, phi=1.0):
    """Per-shard payoff. cap=None -> paper's pure pay-per-share. cap given -> V3 capped share * reputation phi."""
    share = r_n / (r_n + others + EPS)
    if cap is not None:
        share = np.minimum(share, cap)
    return phi * share * P

def best_response(n, r, P, cap=None, phi=None, ftol=1e-6):
    M = len(P)
    phi = np.ones(len(R)) if phi is None else phi
    others = r.sum(axis=0) - r[n]
    def neg_u(x):
        return -sum(payoff_share(x[m], others[m], P[m], cap, phi[n]) - C[n] * x[m] for m in range(M))
    cons = [{"type": "ineq", "fun": lambda x: R[n] - x.sum()}]
    res = minimize(neg_u, r[n], bounds=[(0, R[n])] * M, constraints=cons, method="SLSQP", options={"ftol": ftol, "maxiter": 500})
    return np.clip(res.x, 0, R[n])

def follower_equilibrium(P, cap=None, phi=None, iters=60, tol=1e-3, history=False):
    N, M = len(R), len(P)
    r = np.full((N, M), 1.0)
    hist = [r.copy()]
    for _ in range(iters):
        old = r.copy()
        for n in range(N):
            r[n] = best_response(n, r, P, cap, phi)
        hist.append(r.copy())
        if np.abs(r - old).max() < tol:
            break
    return (r, hist) if history else r

def leader_utility(alpha, P, r):
    tot = r.sum(axis=0)
    return float(sum(a * np.log(max(t, 1e-9)) - p for a, t, p in zip(alpha, tot, P)))

def solve_leader(alpha, grid, cap=None, phi=None):
    """Grid search like Algorithm 1 (P step = 1)."""
    best = (-1e18, None, None)
    for p1 in grid[0]:
        for p2 in grid[1]:
            P = np.array([p1, p2], float)
            r = follower_equilibrium(P, cap, phi)
            u = leader_utility(alpha, P, r)
            if u > best[0]:
                best = (u, P, r)
    return best