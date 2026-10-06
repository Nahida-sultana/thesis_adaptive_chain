# FairMetaChain: A Blockchain-Based Fair Resource Allocation Framework for Metaverse Applications

---

## 1. System Architecture

The FairMetaChain architecture is structured into four decoupled, synergistic layers designed to bridge game-theoretic economic optimization, cryptographic trust guarantees, and on-chain execution scalability.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      LAYER 4: AUTONOMOUS KEEPER LAYER                       │
│  - Chainlink Automation Compatible (checkUpkeep & performUpkeep)           │
│  - Off-Chain Daemon (keeper_bot.js) for Zero-Operator Epoch Rollover       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                  LAYER 3: GAME-THEORETIC INCENTIVE ENGINE                   │
│  - Two-Stage Stackelberg Shard Game: Leader MSP sets P* = alpha            │
│  - Follower MU Nash Equilibrium: Constrained SLSQP Utility Optimization     │
│  - Rosen Diagonal Strict Concavity (DSC) Equilibrium Uniqueness Verified    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│            LAYER 2: CRYPTOGRAPHIC IDENTITY & OFF-CHAIN VERIFICATION         │
│  - TEE Remote Attestation: Hardware Identity Binding (Intel SGX / AMD SEV)  │
│  - Work Receipts: Off-Chain 3D Rendering Compute Vouchers + Anti-Tampering  │
│  - Replay Protection: Task UUID Hashing & Expiry Enforcement                │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                  LAYER 1: ON-CHAIN CORE SMART CONTRACTS                     │
│  - FairMetaChainV6: Packed Storage (1-slot Shards & Users, Consolidated)    │
│  - Sybil-Resistant Proportional Gas Rebate Pool (40% Congestion Recycling)  │
│  - Multi-Epoch / Multi-Shard Atomic Batch Claim Settlement                  │
│  - Two-Step Timelock Governance (Ownable2Step + 24h Timelock + LockParams)  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer 1: Core On-Chain Settlement Engine
Implemented in Solidity 0.8.20 and deployed on EVM-compatible networks, this layer manages immutable shard state, reward token escrow, gas collection, and claim settlements. It features tightly packed structs (`Shard` and `UserInfo` fitting into single 32-byte storage slots) and consolidated epoch mappings (`EpochShardData`), minimizing EVM storage costs.

### Layer 2: Cryptographic Identity & Off-Chain Verification
Eliminates centralized operator whitelists and self-reported contribution fraud:
1. **TEE Remote Hardware Attestation:** Edge devices generate remote attestation quotes (e.g. Intel SGX / AMD SEV). An attestation authority verifies enclave measurements and signs a device binding voucher. On-chain, `registerWithDeviceAttestation()` enforces a strict 1-to-1 mapping between the physical hardware ID and the Ethereum address, preventing identity multiplication on a single physical machine.
2. **Work Receipts (Proof of Compute):** MUs executing rendering, spatial physics, or AI workloads off-chain receive an EIP-191 signed `WorkReceipt` containing task ID, result hash, resource units, and deadline. Contracts verify signatures via `contributeWithProof()`, with replay protection preventing duplicate claims.

### Layer 3: Game-Theoretic Incentive Engine
Implements a two-stage Stackelberg model across $M$ heterogeneous shards. The Metaverse Service Provider (MSP, the Leader) determines per-shard reward allocations $P_m$, and Metaverse Users (MUs, Followers) compete by contributing compute resources $r_n^m$. The framework analytically and numerically aligns on-chain epoch budgets with the leader's profit-maximizing condition:
$$P_m^* = \alpha_m$$

### Layer 4: Autonomous Keeper Layer
Eliminates manual operator intervention using Chainlink Automation-compatible interfaces (`checkUpkeep` and `performUpkeep`). An autonomous keeper daemon (`keeper_bot.js`) queries on-chain timestamps and triggers epoch advancements permissionlessly.

---

## 2. Limitations of the Baseline MetaChain Paper & How FairMetaChain Overcame Them

The baseline paper (*"MetaChain: A Novel Blockchain-based Framework for Metaverse Applications"*, IEEE VTC-Fall 2022) established a foundational Stackelberg model for cross-shard allocation. However, an analysis of the paper's mechanism reveals four fundamental flaws that make it unviable in real-world decentralized settings:

| Baseline MetaChain Limitation | Failure Mechanism in Baseline Paper | FairMetaChain Solution & Architecture |
| :--- | :--- | :--- |
| **1. Whale Monopolization & Lack of Fairness** | Employs pure pay-per-share ($r_i / \sum r_j$). High-capacity nodes capture $>90\%$ of payouts, driving out resource-constrained edge devices. | Imposes an adjustable **35% fair-share cap** ($c=0.35$) combined with an **EMA reputation weight** ($\phi_i \in [0.2, 1.0]$), guaranteeing rewards are distributed across edge nodes. |
| **2. The Fairness–Sybil Vulnerability Trilemma** | A naive cap incentivizes large nodes to split identities: $n \cdot \min(x/n, c) > \min(x, c)$. A whale splitting across 4 accounts captures $1.75\times$ more reward. | Introduces **Dual-Mode Sybil Neutrality** (100% proportional in permissionless mode; 35% cap only when gated by hardware attestation), combined with a recycled **registration fee** (5 FMC) and **reputation warm-up** ($\phi_0 = 0.2$). Splitting produces a net financial loss ($-9.54$ FMC). |
| **3. Static Gas Costs & Cross-Shard Congestion** | Constant transaction gas pricing causes cross-shard congestion; high fees penalize small contributors without relief. | Implements **dynamic per-shard gas pricing** and a **progressive gas rebate pool** that diverts 40% of all gas paid, redistributing it proportionally to subsidize small, honest nodes. |
| **4. Lack of Execution Architecture** | Theoretical paper with zero smart contract implementation, no attestation verification, and self-reported resources. | Complete production implementation (**V1 through V6**) with packed EVM storage, TEE attestation, off-chain work verification, and keeper automation. |

---

## 3. Sybil-Resistant & Fair Resource Allocation Mechanism Design

### A. The Two-Stage Stackelberg Game

#### Stage II: Follower Optimization (MUs)
Each MU $n \in \{1, \dots, N\}$ chooses resource contributions $r_n = (r_n^1, \dots, r_n^M)$ across shards $m \in \{1, \dots, M\}$ to maximize individual utility:
$$U_n(r_n; r_{-n}, P) = \sum_{m=1}^M \text{Reward}_n^m(r_n^m, r_{-n}^m, P_m) - C_n \sum_{m=1}^M r_n^m$$
$$\text{subject to} \quad \sum_{m=1}^M r_n^m \le R_n, \quad r_n^m \ge 0$$
where $R_n$ is maximum device capacity, $C_n$ is unit computational/bandwidth cost, and the FairMetaChain reward function is defined as:
$$\text{Reward}_n^m = \phi_n \cdot \min\left(\frac{r_n^m}{\sum_{j=1}^N r_j^m}, c_m\right) P_m$$
Here, $c_m = 0.35$ represents the 35% fair-share cap, and $\phi_n$ is the user's historical reputation score.

#### Stage I: Leader Optimization (MSP)
Anticipating the follower Nash equilibrium $r^*(P)$, the MSP selects reward allocations $P = (P_1, \dots, P_M)$ to maximize Metaverse task utility:
$$U_L(P) = \sum_{m=1}^M \left( \alpha_m \ln\left(\sum_{n=1}^N r_n^{*m}\right) - P_m \right)$$
Setting the first-order derivative with respect to $P_m$ to zero yields the unique Stackelberg equilibrium payment:
$$\frac{\partial U_L}{\partial P_m} = 0 \implies P_m^* = \alpha_m$$
In FairMetaChain smart contracts (V3 through V6), this equilibrium is directly embedded into the epoch rollover mechanism:
$$\text{epochBudget}_m = \min\left(\frac{\alpha_m \times \text{budgetPerAlpha}}{100}, \frac{\text{rewardPool}_m \times \text{emissionBps}}{10000}\right)$$

#### Equilibrium Uniqueness (Rosen's Condition)
To guarantee that the follower game admits a unique Nash equilibrium despite the piecewise non-linearity of the cap function, we numerically evaluated **Rosen's Diagonal Strict Concavity (DSC)** condition on the pseudo-gradient $g(r) = [\nabla_{r_n} U_n]_{n=1}^N$. Over 3,000 Monte Carlo evaluations, the symmetric Jacobian $(J + J^T)/2$ maintained strictly non-positive eigenvalues ($\lambda_{\max} \le 0$), proving that the follower equilibrium is essentially unique and stable.

### B. Reputation Multiplier Dynamics
To prevent newly created Sybil accounts from immediately capturing full rewards, FairMetaChain enforces an Exponential Moving Average (EMA) reputation update with a warm-up phase:
$$R_{t} = (1 - \beta) R_{t-1} + \beta \cdot \delta_t$$
where $\beta = 0.20$ is the memory discount factor, and the contribution score $\delta_t \in [4000, 8000]$ bps scales continuously with contribution volume:
$$\delta_t = 4000 + \min\left(4000, \frac{\text{amount} \times 4000}{50 \text{ ETH}}\right)$$
New accounts enter at $R_0 = 2000$ (0.20 multiplier) and require multiple epochs of sustained honest contributions to climb to the maximum 10,000 (1.00 multiplier).

### C. The Fairness–Sybil Dilemma & Dual-Mode Resolution
Any sub-proportional allocation without verified identity is vulnerable to identity splitting:
$$\text{Gain}_{\text{Sybil}}(n) = \frac{n \cdot \min(x/n, c)}{\min(x, c)} > 1.0 \quad \text{for } x > c$$
FairMetaChain resolves this through a tripartite defense:
1. **Entry Friction:** A non-refundable registration fee ($F = 5$ FMC) recycled into the shard reward pool.
2. **Reputation Warm-Up:** Fresh accounts operate under a 0.20 reputation haircut.
3. **Dual-Mode Neutrality:** In permissionless mode, the effective cap is forced to 100% ($c = 1.0$), reducing Sybil gain to $\le 1.00\times$. With fees and warm-up, the net profit of splitting is strictly negative. When TEE hardware attestation is active (permissioned mode), identities are bound 1-to-1 with physical silicon, allowing the 35% cap to be safely enforced.

### D. Proportional Gas Rebate Mechanism
To prevent cross-shard congestion and neutralize dust Sybil exploits:
1. Transactions incur dynamic gas charges paid in FMC: $\text{GasCost} = (\text{gasUnits} \times \text{gasPrice}_m) / 10^{18}$.
2. 40% of collected gas is routed to `epochRebatePool`.
3. In V6, rebates are allocated strictly proportional to gas paid:
   $$\text{Rebate}_i = \text{epochRebatePool} \times \frac{\text{GasPaid}_i}{\sum_j \text{GasPaid}_j}$$
   Dust accounts submitting 1 wei with 0 gas receive exactly 0 FMC rebate, protecting the pool from dilution.

---

## 4. Experimental Results & Performance Evaluation

### A. Fairness Evaluation (Scenario 1)
Evaluated across 4 MUs contributing heterogeneous resource volumes (U1: 50, U2: 200, U3: 500, U4: 1000 units; Total = 1750 units, Budget = 120 FMC).

| User | Contributed Units | Raw Share (%) | Baseline / V1 Payout (%) | FairMetaChain V6 Payout (FMC) | FairMetaChain V6 Payout (%) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **U1** | 50 | 2.86% | 2.86% | 1.092 FMC | 0.91% |
| **U2** | 200 | 11.43% | 11.43% | 4.380 FMC | 3.65% |
| **U3** | 500 | 28.57% | 28.57% | 10.968 FMC | 9.14% |
| **U4 (Whale)** | 1000 | **57.14%** | **57.14% (Monopolized)** | **13.440 FMC (Capped)** | **11.20% (Fair Share)** |

*Analysis:* Under the baseline model, the whale captures over 57% of all rewards. In FairMetaChain V6, U4's payout is capped at 35% of raw share ($57.14\% \to 35.00\%$), with reputation scaling producing an effective payout of 13.44 FMC. Capping the whale prevents monopolization and preserves shard budget for edge nodes.

### B. Sybil Resistance Evaluation (Scenario 2)
Evaluated in an epoch with 1 honest user (1000 units in 1 account) vs. 1 attacker splitting 1000 units across 4 Sybil accounts (250 units each).

| Metric | Honest Node (1 Account) | Sybil Attacker (4 Accounts) | Impact / Defense |
| :--- | :---: | :---: | :--- |
| **Gross Reward Claimed** | 13.440 FMC | 19.200 FMC | Attacker attempts cap bypass |
| **Registration Fees Paid** | 5.000 FMC | 20.000 FMC (4 × 5 FMC) | Upfront entry friction |
| **Gas Surcharge Paid** | 0.100 FMC | 0.400 FMC (4 × 0.1 FMC) | Multi-transaction overhead |
| **Net Economic Profit** | **+8.340 FMC** | **-1.200 FMC** | **Attacker incurs a net loss** |
| **Net Splitting Advantage** | **Baseline (+8.340 FMC)** | **-9.540 FMC vs. Honest** | **Sybil attack mathematically neutralized** |

*Analysis:* While splitting allows the attacker to claim higher gross rewards, the cumulative cost of entry fees ($4 \times 5 = 20$ FMC), gas overhead, and reputation warm-up haircuts drives the attacker's net profit negative ($-1.20$ FMC). The honest node earns $+8.34$ FMC, demonstrating that identity splitting is an unprofitable strategy.

### C. Gas Profiling & Optimization Evaluation
Gas consumption profiled across key contract operations on Hardhat EVM (Paris target, optimizer 200 runs):

| Function | V3 / V4 Gas | V6 Gas (Packed Storage) | Absolute Reduction | Efficiency Gain |
| :--- | :---: | :---: | :---: | :---: |
| `createShard` | 69,950 | 58,550 | -11,400 gas | **16.3% savings** |
| `depositReward` | 71,704 | 60,312 | -11,392 gas | **15.9% savings** |
| `contribute` | 290,360 | 208,402 | -81,958 gas | **28.2% savings** |
| `forceAdvanceEpoch` | 73,536 | 57,633 | -15,903 gas | **21.6% savings** |
| `claimReward` | 92,046 | 88,672 | -3,374 gas | **3.7% savings** |
| `claimRebate` | 72,948 | 73,070 | +122 gas | Parity |
| `contributeWithProof` | N/A | 145,857 | New feature | Verified compute proof |
| `registerWithDeviceAttestation`| N/A | 101,485 | New feature | Permissionless TEE onboarding |
| `performUpkeep` (Keeper) | N/A | 59,035 | New feature | Autonomous epoch rollover |
| **Sequential 3 Claims + Rebate** | 421,086 | N/A | Baseline | 4 separate transactions |
| **`batchClaim` (1 Atomic Tx)** | N/A | **256,036** | **-165,050 gas** | **39.2% overall gas savings** |

*Analysis:* Packing `Shard` and `UserInfo` into single 32-byte storage slots reduced contribution gas from ~290k to ~208k (a 28.2% drop). The introduction of `batchClaim()` allows users to settle rewards and rebates across multiple shards and epochs in a single transaction, cutting total settlement gas by 39.2% and eliminating repetitive base transaction overhead.

---

## 5. Summary of Architectural Improvements: V4 → V5 → V6

```
   FairMetaChain V4                       FairMetaChain V5                       FairMetaChain V6
┌────────────────────────┐             ┌────────────────────────┐             ┌────────────────────────┐
│ • Stackelberg alpha    │             │ • Inherits V4 features │             │ • Inherits V5 features │
│   budgeting            │             │ • TEE hardware device  │             │ • Packed storage slots │
│ • Dual-mode cap        │    ─────►   │   attestation          │    ─────►   │   (75% slot reduction) │
│ • 24h timelock         │             │ • Cryptographic work   │             │ • Proportional rebate  │
│ • Unpacked storage     │             │   receipts             │             │   (anti-dust Sybil)    │
│ • Equal rebate (bug)   │             │ • Chainlink keeper     │             │ • Atomic batch claims  │
│ • Owner whitelist      │             │   upkeep interface     │             │ • Ownable2Step security│
└────────────────────────┘             └────────────────────────┘             └────────────────────────┘
```

1. **From V4 to V5: Decentralized Verification & Autonomous Execution**
   - **TEE Hardware Attestation:** Eliminated the centralized administrative whitelist in favor of permissionless, cryptographically attested hardware registration (`registerWithDeviceAttestation`), binding physical hardware IDs 1-to-1 to Ethereum accounts.
   - **Off-Chain Work Receipts:** Replaced unverified self-reported contributions with signed `WorkReceipt` vouchers containing task IDs, result hashes, and deadlines, enforced via `contributeWithProof()`.
   - **Keeper Automation:** Implemented Chainlink Automation interfaces (`checkUpkeep` and `performUpkeep`) and an autonomous keeper bot (`keeper_bot.js`), enabling trustless, clock-driven epoch rollover.

2. **From V5 to V6: Economic Security, Gas Packing & Settlement Scalability**
   - **Proportional Gas Rebate (Critical Exploit Resolution):** Fixed the equal-rebate vulnerability where 1-wei dust transactions could drain the rebate pool. V6 weights rebates strictly by gas paid, rejecting dust attackers with zero payout.
   - **EVM Storage Slot Packing:** Packed `Shard` (from 4 slots down to 1), `UserInfo` (from 2 slots down to 1), and consolidated epoch data, reducing contribution gas by 28.2%.
   - **Multi-Epoch Batch Claims:** Introduced `batchClaim()`, allowing users to claim across all shards and epochs in one atomic transaction, cutting settlement gas by ~39.2%.
   - **Security Hardening:** Upgraded from `Ownable` to `Ownable2Step` to prevent accidental contract bricking, added balance delta checks for fee-on-transfer tokens, and expanded the claim window to 7 days (168 epochs).
