// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * FairMetaChain V3 = V2 + three additions (see below). V2 fixes vs V1:
 *  1. Reputation scale fixed (0..10000 bps) so it actually moves the payout; snapshotted per epoch.
 *  2. Per-epoch reward budget is fixed at epoch end -> claim order no longer matters.
 *  3. rewardPool is decremented; unallocated/unclaimed budget rolls back via sweepUnclaimed().
 *  4. Optional permissioned mode (registry) as a stand-in for identity / TEE / zk verification (Sybil guard).
 *  5. epochDuration is now used (advanceEpoch()).
 *
 * V3 additions:
 *  A. alpha-driven epoch budget. Paper (MetaChain, VTC-2022) MSP utility U_L = sum(alpha*ln(R) - P). With pay-per-share
 *     followers the equilibrium gives P* = alpha (verified numerically, python/stackelberg_sim.py), so
 *     budget_m = alpha_m * budgetPerAlpha / 100  (alpha stored x100), bounded by pool*emissionBps.
 *  B. Sybil cost: one-time registrationFee (recycled to the shard pool) + reputation warm-up (fresh accounts start low).
 *  C. Setting maxShareCapBps = 10000 makes payouts exactly proportional (Sybil gain = 1.00x, same as the paper).
 * Public getters used by the dashboard (getShard, getUserInfo, ...) keep the same signatures as V1.
 */
contract FairMetaChainV3 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Shard { uint256 rewardPool; uint256 gasPrice; uint256 alpha; bool active; }
    struct UserInfo { uint256 reputation; uint256 totalContributedAllTime; }

    uint256 public initialReputation = 2000;   // warm-up: new accounts start low

    IERC20 public immutable rewardToken;

    uint256 public currentEpoch;
    uint256 public epochDuration = 1 hours;
    uint256 public lastEpochStart;

    uint256 public maxShareCapBps = 3500;
    uint256 public fairnessPhiMinBps = 2000;
    uint256 public gasRebateFractionBps = 4000;
    uint256 public emissionBps = 2000;   // share of a shard's pool opened as budget each epoch
    uint256 public budgetPerAlpha = 10 ether; // epoch budget = alpha(x100) * budgetPerAlpha / 100
    uint256 public registrationFee = 5 ether; // one-time, per account, recycled into the shard pool
    mapping(address => bool) public joined;
    uint256 public claimWindow = 3;      // epochs after which unclaimed budget can be swept back

    bool public permissioned;
    mapping(address => bool) public registered;

    mapping(uint256 => Shard) public shards;
    uint256 public shardCount;
    mapping(address => UserInfo) public users;

    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public shardContribution;
    mapping(uint256 => mapping(uint256 => uint256)) public epochShardTotal;
    mapping(uint256 => mapping(uint256 => uint256)) public epochBudget;
    mapping(uint256 => mapping(uint256 => uint256)) public epochPaid;
    mapping(uint256 => mapping(uint256 => bool)) public epochSwept;
    mapping(uint256 => mapping(address => uint256)) public epochReputation;
    mapping(uint256 => mapping(address => uint256)) public epochGasUsed;
    mapping(uint256 => uint256) public epochGasRevenue;
    mapping(uint256 => uint256) public epochRebatePool;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public rewardClaimed;
    mapping(uint256 => mapping(address => bool)) public rebateClaimed;
    mapping(uint256 => address[]) public epochContributors;
    mapping(uint256 => mapping(address => bool)) public isEpochContributor;

    event ShardCreated(uint256 indexed shardId, uint256 alpha);
    event RewardDeposited(uint256 indexed shardId, uint256 amount);
    event GasPriceUpdated(uint256 indexed shardId, uint256 newPrice);
    event ContributionMade(address indexed user, uint256 indexed shardId, uint256 amount, uint256 gasPaid, uint256 epoch);
    event RewardsClaimed(address indexed user, uint256 indexed epoch, uint256 indexed shardId, uint256 amount);
    event RebateClaimed(address indexed user, uint256 indexed epoch, uint256 amount);
    event EpochAdvanced(uint256 newEpoch);
    event Joined(address indexed user, uint256 fee);
    event Swept(uint256 indexed epoch, uint256 indexed shardId, uint256 amount);

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        lastEpochStart = block.timestamp;
        currentEpoch = 1;
    }

    // ---------- admin ----------
    function createShard(uint256 alpha) external onlyOwner returns (uint256) {
        uint256 id = shardCount++;
        shards[id] = Shard({rewardPool: 0, gasPrice: 0.02 ether, alpha: alpha, active: true});
        emit ShardCreated(id, alpha);
        return id;
    }

    function depositReward(uint256 shardId, uint256 amount) external onlyOwner {
        require(shards[shardId].active, "inactive");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        shards[shardId].rewardPool += amount;
        emit RewardDeposited(shardId, amount);
    }

    function setGasPrice(uint256 shardId, uint256 newPrice) external onlyOwner {
        require(shards[shardId].active, "inactive");
        shards[shardId].gasPrice = newPrice;
        emit GasPriceUpdated(shardId, newPrice);
    }

    function setParams(uint256 _capBps, uint256 _phiMinBps, uint256 _emissionBps) external onlyOwner {
        require(_capBps <= 10000 && _phiMinBps <= 10000 && _emissionBps <= 10000, "bps");
        maxShareCapBps = _capBps;
        fairnessPhiMinBps = _phiMinBps;
        emissionBps = _emissionBps;
    }

    function setSybilParams(uint256 _fee, uint256 _initialRep, uint256 _budgetPerAlpha) external onlyOwner {
        require(_initialRep <= 10000, "bps");
        registrationFee = _fee;
        initialReputation = _initialRep;
        budgetPerAlpha = _budgetPerAlpha;
    }

    function setPermissioned(bool on) external onlyOwner { permissioned = on; }

    function register(address[] calldata accts, bool ok) external onlyOwner {
        for (uint256 i = 0; i < accts.length; i++) registered[accts[i]] = ok;
    }

    // ---------- epochs ----------
    function forceAdvanceEpoch() external onlyOwner { _advance(); }

    function advanceEpoch() external {
        require(block.timestamp >= lastEpochStart + epochDuration, "epoch running");
        _advance();
    }

    function _advance() internal {
        uint256 e = currentEpoch;
        for (uint256 i = 0; i < shardCount; i++) {
            if (epochShardTotal[e][i] == 0) continue; // nobody contributed: pool stays untouched
            uint256 b = (shards[i].alpha * budgetPerAlpha) / 100;      // alpha-driven (paper: P* = alpha)
            uint256 maxB = (shards[i].rewardPool * emissionBps) / 10000;
            if (b > maxB) b = maxB;
            shards[i].rewardPool -= b;
            epochBudget[e][i] = b;
        }
        currentEpoch = e + 1;
        lastEpochStart = block.timestamp;
        emit EpochAdvanced(currentEpoch);
    }

    // ---------- user actions ----------
    function contribute(uint256 shardId, uint256 amount, uint256 gasUnits) external nonReentrant {
        require(shards[shardId].active, "inactive");
        require(amount > 0, "zero");
        require(!permissioned || registered[msg.sender], "not registered");

        uint256 e = currentEpoch;
        if (!joined[msg.sender] && registrationFee > 0) {
            rewardToken.safeTransferFrom(msg.sender, address(this), registrationFee);
            shards[shardId].rewardPool += registrationFee;
            emit Joined(msg.sender, registrationFee);
        }
        joined[msg.sender] = true;
        uint256 gasCost = (gasUnits * shards[shardId].gasPrice) / 1e18;
        if (gasCost > 0) {
            rewardToken.safeTransferFrom(msg.sender, address(this), gasCost);
            epochGasRevenue[e] += gasCost;
            epochRebatePool[e] += (gasCost * gasRebateFractionBps) / 10000;
        }

        shardContribution[e][shardId][msg.sender] += amount;
        epochShardTotal[e][shardId] += amount;
        epochGasUsed[e][msg.sender] += gasUnits;

        if (!isEpochContributor[e][msg.sender]) {
            epochContributors[e].push(msg.sender);
            isEpochContributor[e][msg.sender] = true;
        }

        UserInfo storage u = users[msg.sender];
        u.totalContributedAllTime += amount;
        if (u.reputation == 0) u.reputation = initialReputation;
        uint256 delta = amount >= 50 ether ? 8000 : 4000;     // same 2:1 ratio as V1, on the 0..10000 scale
        u.reputation = (u.reputation * 80 + delta * 20) / 100; // EMA, alpha = 0.2
        if (u.reputation > 10000) u.reputation = 10000;
        if (u.reputation < 500) u.reputation = 500;
        epochReputation[e][msg.sender] = u.reputation;         // snapshot used at claim time

        emit ContributionMade(msg.sender, shardId, amount, gasCost, e);
    }

    function claimReward(uint256 epoch, uint256 shardId) external nonReentrant {
        require(epoch < currentEpoch, "epoch not finished");
        require(!epochSwept[epoch][shardId], "swept");
        require(!rewardClaimed[epoch][msg.sender][shardId], "already claimed");
        uint256 userContrib = shardContribution[epoch][shardId][msg.sender];
        require(userContrib > 0, "nothing");
        uint256 total = epochShardTotal[epoch][shardId];
        require(total > 0, "no total");

        rewardClaimed[epoch][msg.sender][shardId] = true;

        uint256 rawShareBps = (userContrib * 10000) / total;
        if (rawShareBps > maxShareCapBps) rawShareBps = maxShareCapBps;
        uint256 phiBps = epochReputation[epoch][msg.sender];
        if (phiBps < fairnessPhiMinBps) phiBps = fairnessPhiMinBps;
        uint256 effectiveBps = (rawShareBps * phiBps) / 10000;
        // sum(effectiveBps) <= sum(rawShareBps) <= 10000, so payouts can never exceed the epoch budget
        uint256 reward = (epochBudget[epoch][shardId] * effectiveBps) / 10000;

        if (reward > 0) {
            epochPaid[epoch][shardId] += reward;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, epoch, shardId, reward);
        }
    }

    /// Unallocated (cap / reputation haircut) and unclaimed budget returns to the shard pool after claimWindow.
    function sweepUnclaimed(uint256 epoch, uint256 shardId) external {
        require(currentEpoch > epoch + claimWindow, "window open");
        require(!epochSwept[epoch][shardId], "swept");
        epochSwept[epoch][shardId] = true;
        uint256 left = epochBudget[epoch][shardId] - epochPaid[epoch][shardId];
        shards[shardId].rewardPool += left;
        emit Swept(epoch, shardId, left);
    }

    function claimRebate(uint256 epoch) external nonReentrant {
        require(epoch < currentEpoch, "epoch not finished");
        require(!rebateClaimed[epoch][msg.sender], "already claimed");
        require(isEpochContributor[epoch][msg.sender], "not contributor");
        rebateClaimed[epoch][msg.sender] = true;

        uint256 pool = epochRebatePool[epoch];
        uint256 num = epochContributors[epoch].length;
        if (pool == 0 || num == 0) return;
        uint256 rebate = pool / num;
        if (rebate > 0) {
            rewardToken.safeTransfer(msg.sender, rebate);
            emit RebateClaimed(msg.sender, epoch, rebate);
        }
    }

    // ---------- views (same signatures as V1) ----------
    function getUserInfo(address user) external view returns (uint256 reputation, uint256 totalContributedAllTime) {
        UserInfo storage u = users[user];
        return (u.reputation, u.totalContributedAllTime);
    }

    function getShard(uint256 shardId) external view returns (uint256 rewardPool, uint256 gasPrice, uint256 totalContributed, uint256 alpha, bool active) {
        Shard storage s = shards[shardId];
        return (s.rewardPool, s.gasPrice, epochShardTotal[currentEpoch][shardId], s.alpha, s.active);
    }
}
