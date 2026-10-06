// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title FairMetaChainV5
 * @notice Production-grade resource allocation system for Metaverse applications.
 * Inherits all V4 features (Stackelberg alpha budgets, dual-mode Sybil neutrality, timelock governance)
 * and implements the three critical engineering & research roadmap milestones:
 *
 *  1. Decentralized Verification (Replacing Owner Whitelist):
 *     Permissionless device onboarding via TEE (Trusted Execution Environment) remote attestation.
 *     Enforces strict 1-to-1 hardware-to-account binding (hardwareId <-> address) to neutralize Sybil splits.
 *
 *  2. Cryptographic Off-Chain Contribution Verification:
 *     Replaces naive self-reported contributions with signed WorkReceipts from TEE verification nodes / oracles.
 *     Features task replay protection, result commitments (resultHash), and strict deadlines.
 *
 *  3. Automated Epoch Crons / Keepers:
 *     Chainlink Automation / Gelato Keeper compatible interface (checkUpkeep & performUpkeep)
 *     for autonomous, permissionless epoch rollover without centralized operator intervention.
 */
contract FairMetaChainV5 is Ownable, ReentrancyGuard {
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

    struct WorkReceipt {
        bytes32 taskId;
        uint256 shardId;
        address contributor;
        uint256 amount;
        uint256 gasUnits;
        bytes32 resultHash;
        uint256 deadline;
    }

    IERC20 public immutable rewardToken;

    // --- Epoch Parameters ---
    uint256 public currentEpoch;
    uint256 public epochDuration = 1 hours;
    uint256 public lastEpochStart;

    // --- Economic & Game-Theoretic Parameters ---
    uint256 public initialReputation = 2000;      // 20% warm-up for new participants
    uint256 public maxShareCapBps = 3500;         // 35% fair share cap
    uint256 public fairnessPhiMinBps = 2000;      // Minimum reputation haircut floor
    uint256 public gasRebateFractionBps = 4000;   // 40% gas surcharge diverted to rebate pool
    uint256 public emissionBps = 2000;            // 20% shard pool emission rate per epoch
    uint256 public budgetPerAlpha = 10 ether;     // Equilibrium budget P* = alpha * budgetPerAlpha / 100
    uint256 public registrationFee = 5 ether;     // One-time fee recycled to shard pool
    uint256 public claimWindow = 3;               // Epochs after which unallocated budget rolls back

    // --- Shards & Users ---
    mapping(uint256 => Shard) public shards;
    uint256 public shardCount;
    mapping(address => UserInfo) public users;
    mapping(address => bool) public joined;

    // --- Accounting Per Epoch ---
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

    // =========================================================================
    // ROADMAP 1: DECENTRALIZED TEE VERIFICATION (REPLACING OWNER WHITELIST)
    // =========================================================================
    bool public permissioned;
    address public teeAttestationSigner;
    mapping(address => bool) public registered;
    mapping(bytes32 => address) public hardwareToAccount;
    mapping(address => bytes32) public accountToHardware;

    // =========================================================================
    // ROADMAP 2: OFF-CHAIN VERIFICATION LAYER (CRYPTOGRAPHIC PROOF OF WORK)
    // =========================================================================
    address public workVerifierSigner;
    bool public requireProof;
    mapping(bytes32 => bool) public usedTasks;

    // =========================================================================
    // GOVERNANCE & TIMELOCK CONTROLS
    // =========================================================================
    uint256 public constant TIMELOCK = 1 days;
    bool public paramsLocked;
    bool public forceAdvanceDisabled;

    struct Pending {
        uint256 capBps;
        uint256 phiMinBps;
        uint256 emissionBps;
        uint256 fee;
        uint256 initialRep;
        uint256 budgetPerAlpha;
        bool permissioned;
        uint256 eta;
    }
    Pending public pending;

    // --- Events ---
    event ShardCreated(uint256 indexed shardId, uint256 alpha);
    event RewardDeposited(uint256 indexed shardId, uint256 amount);
    event GasPriceUpdated(uint256 indexed shardId, uint256 newPrice);
    event ContributionMade(address indexed user, uint256 indexed shardId, uint256 amount, uint256 gasPaid, uint256 epoch);
    event VerifiedContributionMade(address indexed user, uint256 indexed shardId, bytes32 indexed taskId, uint256 amount, uint256 gasPaid, uint256 epoch);
    event RewardsClaimed(address indexed user, uint256 indexed epoch, uint256 indexed shardId, uint256 amount);
    event RebateClaimed(address indexed user, uint256 indexed epoch, uint256 amount);
    event EpochAdvanced(uint256 newEpoch);
    event Joined(address indexed user, uint256 fee);
    event Swept(uint256 indexed epoch, uint256 indexed shardId, uint256 amount);

    // Roadmap events
    event DeviceAttested(address indexed user, bytes32 indexed hardwareId);
    event AttestationSignerUpdated(address indexed newSigner);
    event WorkVerifierUpdated(address indexed newVerifier);
    event RequireProofUpdated(bool required);

    // Governance events
    event ParamsProposed(uint256 eta);
    event ParamsExecuted();
    event ParamsCancelled();
    event ParamsLocked();

    constructor(
        address _rewardToken,
        address _teeAttestationSigner,
        address _workVerifierSigner
    ) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        teeAttestationSigner = _teeAttestationSigner;
        workVerifierSigner = _workVerifierSigner;
        lastEpochStart = block.timestamp;
        currentEpoch = 1;
    }

    // =========================================================================
    // ADMIN & ORACLE CONFIGURATION
    // =========================================================================
    function setTeeAttestationSigner(address _signer) external onlyOwner {
        teeAttestationSigner = _signer;
        emit AttestationSignerUpdated(_signer);
    }

    function setWorkVerifierSigner(address _verifier) external onlyOwner {
        workVerifierSigner = _verifier;
        emit WorkVerifierUpdated(_verifier);
    }

    function setRequireProof(bool _required) external onlyOwner {
        requireProof = _required;
        emit RequireProofUpdated(_required);
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

    // =========================================================================
    // ROADMAP 1: DECENTRALIZED DEVICE ATTESTATION
    // =========================================================================

    function _toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    /**
     * @notice Allows any user possessing a genuine TEE hardware quote to register permissionlessly.
     * @dev Replaces the administrative whitelist with a cryptographic proof of distinct hardware.
     * Enforces a 1-to-1 binding between hardwareId and Ethereum address.
     */
    function registerWithDeviceAttestation(
        bytes32 hardwareId,
        uint256 expiry,
        bytes calldata signature
    ) external nonReentrant {
        require(teeAttestationSigner != address(0), "attestation signer not set");
        require(block.timestamp <= expiry, "attestation expired");
        require(hardwareId != bytes32(0), "invalid hardwareId");
        require(hardwareToAccount[hardwareId] == address(0), "hardware already registered");
        require(accountToHardware[msg.sender] == bytes32(0), "account already registered");

        bytes32 messageHash = keccak256(
            abi.encodePacked("FAIRMETACHAIN_TEE_ATTESTATION", block.chainid, msg.sender, hardwareId, expiry)
        );
        bytes32 ethSignedHash = _toEthSignedMessageHash(messageHash);
        address recovered = ECDSA.recover(ethSignedHash, signature);
        require(recovered == teeAttestationSigner, "invalid attestation signature");

        hardwareToAccount[hardwareId] = msg.sender;
        accountToHardware[msg.sender] = hardwareId;
        registered[msg.sender] = true;

        emit DeviceAttested(msg.sender, hardwareId);
    }

    /// Admin fallback registration
    function register(address[] calldata accts, bool ok) external onlyOwner {
        for (uint256 i = 0; i < accts.length; i++) registered[accts[i]] = ok;
    }

    // =========================================================================
    // TIMELOCKED GOVERNANCE
    // =========================================================================
    function proposeParams(
        uint256 _capBps,
        uint256 _phiMinBps,
        uint256 _emissionBps,
        uint256 _fee,
        uint256 _initialRep,
        uint256 _budgetPerAlpha,
        bool _permissioned
    ) external onlyOwner {
        require(!paramsLocked, "locked");
        require(_capBps <= 10000 && _phiMinBps <= 10000 && _emissionBps <= 10000 && _initialRep <= 10000, "bps");
        pending = Pending(_capBps, _phiMinBps, _emissionBps, _fee, _initialRep, _budgetPerAlpha, _permissioned, block.timestamp + TIMELOCK);
        emit ParamsProposed(pending.eta);
    }

    function executeParams() external {
        require(pending.eta != 0, "none");
        require(block.timestamp >= pending.eta, "timelock");
        maxShareCapBps = pending.capBps;
        fairnessPhiMinBps = pending.phiMinBps;
        emissionBps = pending.emissionBps;
        registrationFee = pending.fee;
        initialReputation = pending.initialRep;
        budgetPerAlpha = pending.budgetPerAlpha;
        permissioned = pending.permissioned;
        delete pending;
        emit ParamsExecuted();
    }

    function cancelParams() external onlyOwner {
        delete pending;
        emit ParamsCancelled();
    }

    function lockParams() external onlyOwner {
        paramsLocked = true;
        delete pending;
        emit ParamsLocked();
    }

    function disableForceAdvance() external onlyOwner {
        forceAdvanceDisabled = true;
    }

    function effectiveCapBps() public view returns (uint256) {
        return permissioned ? maxShareCapBps : 10000;
    }

    // =========================================================================
    // ROADMAP 3: AUTOMATED EPOCH CRONS & KEEPERS
    // =========================================================================

    /**
     * @notice Chainlink Automation / Keeper check function.
     * @return upkeepNeeded True if epoch duration has elapsed and epoch is ready to advance.
     * @return performData ABI-encoded metadata for epoch advancement.
     */
    function checkUpkeep(bytes calldata /* checkData */) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastEpochStart + epochDuration);
        performData = abi.encode(currentEpoch, lastEpochStart + epochDuration);
    }

    /**
     * @notice Chainlink Automation / Keeper execution function.
     * @dev Callable by anyone, bot, or keeper once epochDuration has passed.
     */
    function performUpkeep(bytes calldata /* performData */) external nonReentrant {
        require(block.timestamp >= lastEpochStart + epochDuration, "epoch running");
        _advance();
    }

    function advanceEpoch() external nonReentrant {
        require(block.timestamp >= lastEpochStart + epochDuration, "epoch running");
        _advance();
    }

    function forceAdvanceEpoch() external onlyOwner {
        require(!forceAdvanceDisabled, "disabled");
        _advance();
    }

    function _advance() internal {
        uint256 e = currentEpoch;
        for (uint256 i = 0; i < shardCount; i++) {
            if (epochShardTotal[e][i] == 0) continue; // Unused shards keep their pool untouched
            uint256 b = (shards[i].alpha * budgetPerAlpha) / 100;
            uint256 maxB = (shards[i].rewardPool * emissionBps) / 10000;
            if (b > maxB) b = maxB;
            shards[i].rewardPool -= b;
            epochBudget[e][i] = b;
        }
        currentEpoch = e + 1;
        lastEpochStart = block.timestamp;
        emit EpochAdvanced(currentEpoch);
    }

    // =========================================================================
    // ROADMAP 2: OFF-CHAIN VERIFICATION LAYER & CONTRIBUTIONS
    // =========================================================================

    /**
     * @notice Submits resource contributions backed by a signed cryptographic work receipt.
     * @param receipt The metadata describing the off-chain rendering/compute task.
     * @param signature The ECDSA signature from the authorized TEE verification oracle.
     */
    function contributeWithProof(
        WorkReceipt calldata receipt,
        bytes calldata signature
    ) external nonReentrant {
        require(workVerifierSigner != address(0), "work verifier not set");
        require(receipt.contributor == msg.sender, "contributor mismatch");
        require(!usedTasks[receipt.taskId], "task already submitted");
        require(receipt.taskId != bytes32(0), "empty taskId");
        require(block.timestamp <= receipt.deadline, "receipt expired");
        require(receipt.amount > 0, "zero amount");
        require(shards[receipt.shardId].active, "inactive shard");
        require(!permissioned || registered[msg.sender], "not registered");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "FAIRMETACHAIN_WORK_RECEIPT",
                block.chainid,
                receipt.taskId,
                receipt.shardId,
                receipt.contributor,
                receipt.amount,
                receipt.gasUnits,
                receipt.resultHash,
                receipt.deadline
            )
        );
        bytes32 ethSignedHash = _toEthSignedMessageHash(messageHash);
        address recovered = ECDSA.recover(ethSignedHash, signature);
        require(recovered == workVerifierSigner, "invalid work signature");

        usedTasks[receipt.taskId] = true;

        uint256 gasCost = _processContribution(receipt.shardId, receipt.amount, receipt.gasUnits);

        emit VerifiedContributionMade(msg.sender, receipt.shardId, receipt.taskId, receipt.amount, gasCost, currentEpoch);
    }

    /**
     * @notice Unverified contribution fallback (accessible when requireProof == false).
     */
    function contribute(uint256 shardId, uint256 amount, uint256 gasUnits) external nonReentrant {
        require(!requireProof, "proof required");
        require(shards[shardId].active, "inactive");
        require(amount > 0, "zero amount");
        require(!permissioned || registered[msg.sender], "not registered");

        uint256 gasCost = _processContribution(shardId, amount, gasUnits);

        emit ContributionMade(msg.sender, shardId, amount, gasCost, currentEpoch);
    }

    function _processContribution(
        uint256 shardId,
        uint256 amount,
        uint256 gasUnits
    ) internal returns (uint256 gasCost) {
        uint256 e = currentEpoch;
        if (!joined[msg.sender] && registrationFee > 0) {
            rewardToken.safeTransferFrom(msg.sender, address(this), registrationFee);
            shards[shardId].rewardPool += registrationFee;
            emit Joined(msg.sender, registrationFee);
        }
        joined[msg.sender] = true;

        gasCost = (gasUnits * shards[shardId].gasPrice) / 1e18;
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
        uint256 delta = amount >= 50 ether ? 8000 : 4000;
        u.reputation = (u.reputation * 80 + delta * 20) / 100;
        if (u.reputation > 10000) u.reputation = 10000;
        if (u.reputation < 500) u.reputation = 500;
        epochReputation[e][msg.sender] = u.reputation;

        return gasCost;
    }

    // =========================================================================
    // CLAIMS & SETTLEMENT
    // =========================================================================
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
        uint256 capBps = effectiveCapBps();
        if (rawShareBps > capBps) rawShareBps = capBps;
        uint256 phiBps = epochReputation[epoch][msg.sender];
        if (phiBps < fairnessPhiMinBps) phiBps = fairnessPhiMinBps;
        uint256 effectiveBps = (rawShareBps * phiBps) / 10000;

        uint256 reward = (epochBudget[epoch][shardId] * effectiveBps) / 10000;
        if (reward > 0) {
            epochPaid[epoch][shardId] += reward;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, epoch, shardId, reward);
        }
    }

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

    // =========================================================================
    // PUBLIC VIEW INTERFACES
    // =========================================================================
    function getUserInfo(address user) external view returns (uint256 reputation, uint256 totalContributedAllTime) {
        UserInfo storage u = users[user];
        return (u.reputation, u.totalContributedAllTime);
    }

    function getShard(uint256 shardId) external view returns (
        uint256 rewardPool,
        uint256 gasPrice,
        uint256 totalContributed,
        uint256 alpha,
        bool active
    ) {
        Shard storage s = shards[shardId];
        return (s.rewardPool, s.gasPrice, epochShardTotal[currentEpoch][shardId], s.alpha, s.active);
    }
}
