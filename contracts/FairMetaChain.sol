// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * FairMetaChain - Improved Pilot Contracts
 * Improvements: proper epoch snapshots, better claim logic, forceAdvanceEpoch for testing
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FairMetaChain is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Shard {
        uint256 rewardPool;
        uint256 gasPrice;
        uint256 alpha;
        bool active;
    }

    struct UserInfo {
        uint256 reputation;
        uint256 totalContributedAllTime;
    }

    IERC20 public immutable rewardToken;

    uint256 public currentEpoch;
    uint256 public epochDuration = 1 hours;
    uint256 public lastEpochStart;

    uint256 public maxShareCapBps = 3500;
    uint256 public fairnessPhiMinBps = 4500;
    uint256 public gasRebateFractionBps = 4000;

    mapping(uint256 => Shard) public shards;
    uint256 public shardCount;

    mapping(address => UserInfo) public users;

    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public shardContribution;
    mapping(uint256 => mapping(uint256 => uint256)) public epochShardTotal;
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

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        lastEpochStart = block.timestamp;
        currentEpoch = 1;
    }

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

    function forceAdvanceEpoch() external onlyOwner {
        currentEpoch += 1;
        lastEpochStart = block.timestamp;
        emit EpochAdvanced(currentEpoch);
    }

    function contribute(uint256 shardId, uint256 amount, uint256 gasUnits) external nonReentrant {
        require(shards[shardId].active, "inactive");
        require(amount > 0, "zero");

        uint256 gasCost = (gasUnits * shards[shardId].gasPrice) / 1e18;
        if (gasCost > 0) {
            rewardToken.safeTransferFrom(msg.sender, address(this), gasCost);
            epochGasRevenue[currentEpoch] += gasCost;
            epochRebatePool[currentEpoch] += (gasCost * gasRebateFractionBps) / 10000;
        }

        shardContribution[currentEpoch][shardId][msg.sender] += amount;
        epochShardTotal[currentEpoch][shardId] += amount;
        epochGasUsed[currentEpoch][msg.sender] += gasUnits;

        if (!isEpochContributor[currentEpoch][msg.sender]) {
            epochContributors[currentEpoch].push(msg.sender);
            isEpochContributor[currentEpoch][msg.sender] = true;
        }

        UserInfo storage u = users[msg.sender];
        u.totalContributedAllTime += amount;
        uint256 delta = amount >= 50 ether ? 800 : 400;
        u.reputation = (u.reputation * 80 + delta * 20) / 100;
        if (u.reputation > 10000) u.reputation = 10000;
        if (u.reputation < 500) u.reputation = 500;

        emit ContributionMade(msg.sender, shardId, amount, gasCost, currentEpoch);
    }

    function claimReward(uint256 epoch, uint256 shardId) external nonReentrant {
        require(epoch < currentEpoch, "epoch not finished");
        require(!rewardClaimed[epoch][msg.sender][shardId], "already claimed");
        uint256 userContrib = shardContribution[epoch][shardId][msg.sender];
        require(userContrib > 0, "nothing");
        uint256 total = epochShardTotal[epoch][shardId];
        require(total > 0, "no total");

        rewardClaimed[epoch][msg.sender][shardId] = true;

        uint256 rawShareBps = (userContrib * 10000) / total;
        if (rawShareBps > maxShareCapBps) rawShareBps = maxShareCapBps;
        uint256 phiBps = users[msg.sender].reputation;
        if (phiBps < fairnessPhiMinBps) phiBps = fairnessPhiMinBps;
        uint256 effectiveBps = (rawShareBps * phiBps) / 10000;
        uint256 reward = (shards[shardId].rewardPool * effectiveBps) / 10000;

        if (reward > 0) {
            uint256 bal = rewardToken.balanceOf(address(this));
            if (reward > bal) reward = bal;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, epoch, shardId, reward);
        }
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
            uint256 bal = rewardToken.balanceOf(address(this));
            if (rebate > bal) rebate = bal;
            rewardToken.safeTransfer(msg.sender, rebate);
            emit RebateClaimed(msg.sender, epoch, rebate);
        }
    }

    function getUserInfo(address user) external view returns (uint256 reputation, uint256 totalContributedAllTime) {
        UserInfo storage u = users[user];
        return (u.reputation, u.totalContributedAllTime);
    }

    function getShard(uint256 shardId) external view returns (uint256 rewardPool, uint256 gasPrice, uint256 totalContributed, uint256 alpha, bool active) {
        Shard storage s = shards[shardId];
        return (s.rewardPool, s.gasPrice, epochShardTotal[currentEpoch][shardId], s.alpha, s.active);
    }
}
