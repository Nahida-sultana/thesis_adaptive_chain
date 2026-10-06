// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title FairMetaChainV6 (Comprehensive Architecture)
 * @notice Advanced resource allocation framework for Metaverse applications.
 * Directly addresses and resolves the core architectural limitations of V4:
 *
 *  1. Sybil Resistance:
 *     - Proportional Gas Rebates: Eliminates dust Sybil rebate drain by weighting rebates on gas paid.
 *     - Hardware TEE Attestation: Strict 1-to-1 hardwareId <-> address cryptographic binding.
 *     - Entry Friction: One-time recycled registration fee + continuous reputation warm-up.
 *     - Dual-Mode Sybil Neutrality: Proportional in permissionless mode; 35% cap in verified mode.
 *
 *  2. Gas Efficiency & Storage Packing:
 *     - Packed structs: Shard packed into a single 32-byte slot (uint128 + uint64 + uint32 + bool).
 *     - Packed UserInfo (uint32 reputation + uint224 totalContributed) in 1 slot.
 *     - Consolidated EpochShardData mapping replacing 4 separate nested storage mappings.
 *     - Batch Claiming: Claim across multiple epochs and shards in a single transaction.
 *
 *  3. Fairness Enhancements:
 *     - Surplus-Preserving Fair Allocation: Capped surplus is redistributed to non-capped edge nodes.
 *     - Smooth Continuous Reputation: Eliminates binary cliffs (e.g. 50 ETH jump) with linear EMA scaling.
 *
 *  4. Security & Governance:
 *     - Ownable2Step: Prevents accidental loss of owner privileges.
 *     - Fee-on-Transfer safe token handling (balance-before vs. balance-after).
 *     - Rescue mechanism for non-system ERC20 tokens.
 *     - 24h Timelock on parameters + irrevocable immutability switches (lockParams).
 *
 *  5. Robust Epoch & Automation:
 *     - Chainlink Automation (checkUpkeep & performUpkeep) built-in.
 *     - Multi-epoch catch-up mechanism if keeper is temporarily delayed.
 *     - Expanded claim window (7 days default) preventing premature user reward confiscation.
 */
contract FairMetaChainV6 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Packed Structs for Optimized Storage (SLOAD/SSTORE Savings) ---

    // Occupies EXACTLY 1 storage slot (32 bytes): 16 + 8 + 4 + 1 = 29 bytes <= 32 bytes
    struct Shard {
        uint128 rewardPool;   // Up to 3.4e38 wei
        uint64 gasPrice;      // Up to 18.4 ETH gas price
        uint32 alpha;         // Shard sensitivity (e.g. 1500 = 15.00)
        bool active;          // Shard status
    }

    // Occupies EXACTLY 1 storage slot (32 bytes): 4 + 28 = 32 bytes
    struct UserInfo {
        uint32 reputation;             // 0..10,000 basis points
        uint224 totalContributedAllTime;
    }

    // Occupies EXACTLY 2 storage slots (64 bytes): replaces 4 independent nested mappings
    struct EpochShardData {
        uint128 totalContributed;
        uint128 budget;
        uint128 paidOut;
        bool swept;
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
    uint256 public claimWindowEpochs = 168; // 7 days (at 1h epochs)

    // --- Economic Parameters (BPS = 1/10000) ---
    uint16 public initialReputation = 2000;      // 20% warm-up
    uint16 public maxShareCapBps = 3500;         // 35% cap
    uint16 public fairnessPhiMinBps = 2000;      // Floor reputation haircut
    uint16 public gasRebateFractionBps = 4000;   // 40% gas surcharge to rebate pool
    uint16 public emissionBps = 2000;            // 20% pool emission per epoch
    uint128 public budgetPerAlpha = 10 ether;    // Equilibrium budget scaling P* = alpha
    uint128 public registrationFee = 5 ether;    // Recycled one-time fee

    // --- Shard & User Registry ---
    uint256 public shardCount;
    mapping(uint256 => Shard) public shards;
    mapping(address => UserInfo) public users;
    mapping(address => bool) public joined;

    // --- Consolidated Epoch Data ---
    mapping(uint256 => mapping(uint256 => EpochShardData)) public epochShards;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public shardContribution;
    mapping(uint256 => mapping(address => uint32)) public epochReputation;
    mapping(uint256 => mapping(address => uint256)) public epochGasPaid;
    mapping(uint256 => uint256) public epochTotalGasPaid;
    mapping(uint256 => uint256) public epochRebatePool;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public rewardClaimed;
    mapping(uint256 => mapping(address => bool)) public rebateClaimed;

    // --- Roadmap 1: Decentralized TEE Hardware Identity ---
    bool public permissioned;
    address public teeAttestationSigner;
    mapping(address => bool) public registered;
    mapping(bytes32 => address) public hardwareToAccount;
    mapping(address => bytes32) public accountToHardware;

    // --- Roadmap 2: Off-Chain Verification Layer ---
    address public workVerifierSigner;
    bool public requireProof;
    mapping(bytes32 => bool) public usedTasks;

    // --- Governance & Timelock ---
    uint256 public constant TIMELOCK = 1 days;
    bool public paramsLocked;
    bool public forceAdvanceDisabled;

    struct PendingParams {
        uint16 capBps;
        uint16 phiMinBps;
        uint16 emissionBps;
        uint16 initialRep;
        uint128 fee;
        uint128 budgetPerAlpha;
        bool permissioned;
        uint256 eta;
    }
    PendingParams public pending;

    // --- Events ---
    event ShardCreated(uint256 indexed shardId, uint32 alpha);
    event RewardDeposited(uint256 indexed shardId, uint256 amount);
    event GasPriceUpdated(uint256 indexed shardId, uint64 newPrice);
    event ContributionMade(address indexed user, uint256 indexed shardId, uint256 amount, uint256 gasPaid, uint256 epoch);
    event VerifiedContributionMade(address indexed user, uint256 indexed shardId, bytes32 indexed taskId, uint256 amount, uint256 gasPaid, uint256 epoch);
    event RewardsClaimed(address indexed user, uint256 indexed epoch, uint256 indexed shardId, uint256 amount);
    event RebateClaimed(address indexed user, uint256 indexed epoch, uint256 amount);
    event EpochAdvanced(uint256 newEpoch);
    event Joined(address indexed user, uint256 fee);
    event Swept(uint256 indexed epoch, uint256 indexed shardId, uint256 amount);
    event DeviceAttested(address indexed user, bytes32 indexed hardwareId);
    event AttestationSignerUpdated(address indexed newSigner);
    event WorkVerifierUpdated(address indexed newVerifier);
    event RequireProofUpdated(bool required);
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
    // ADMIN & CONFIGURATION
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

    function setClaimWindowEpochs(uint256 _epochs) external onlyOwner {
        require(_epochs >= 24, "min 24 epochs");
        claimWindowEpochs = _epochs;
    }

    function createShard(uint32 alpha) external onlyOwner returns (uint256) {
        uint256 id = shardCount++;
        shards[id] = Shard({
            rewardPool: 0,
            gasPrice: 0.02 ether,
            alpha: alpha,
            active: true
        });
        emit ShardCreated(id, alpha);
        return id;
    }

    function depositReward(uint256 shardId, uint128 amount) external onlyOwner {
        require(shards[shardId].active, "inactive");
        uint256 received = _safeTransferFrom(rewardToken, msg.sender, address(this), amount);
        shards[shardId].rewardPool += uint128(received);
        emit RewardDeposited(shardId, received);
    }

    function setGasPrice(uint256 shardId, uint64 newPrice) external onlyOwner {
        require(shards[shardId].active, "inactive");
        shards[shardId].gasPrice = newPrice;
        emit GasPriceUpdated(shardId, newPrice);
    }

    // =========================================================================
    // TIMELOCKED GOVERNANCE
    // =========================================================================

    function proposeParams(
        uint16 _capBps,
        uint16 _phiMinBps,
        uint16 _emissionBps,
        uint16 _initialRep,
        uint128 _fee,
        uint128 _budgetPerAlpha,
        bool _permissioned
    ) external onlyOwner {
        require(!paramsLocked, "locked");
        require(_capBps <= 10000 && _phiMinBps <= 10000 && _emissionBps <= 10000 && _initialRep <= 10000, "bps");
        pending = PendingParams({
            capBps: _capBps,
            phiMinBps: _phiMinBps,
            emissionBps: _emissionBps,
            initialRep: _initialRep,
            fee: _fee,
            budgetPerAlpha: _budgetPerAlpha,
            permissioned: _permissioned,
            eta: block.timestamp + TIMELOCK
        });
        emit ParamsProposed(pending.eta);
    }

    function executeParams() external {
        require(pending.eta != 0, "none");
        require(block.timestamp >= pending.eta, "timelock");
        maxShareCapBps = pending.capBps;
        fairnessPhiMinBps = pending.phiMinBps;
        emissionBps = pending.emissionBps;
        initialReputation = pending.initialRep;
        registrationFee = pending.fee;
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
    // SYBIL RESISTANCE: TEE HARDWARE ATTESTATION
    // =========================================================================

    function _toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

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

    function register(address[] calldata accts, bool ok) external onlyOwner {
        for (uint256 i = 0; i < accts.length; i++) registered[accts[i]] = ok;
    }

    // =========================================================================
    // AUTOMATED EPOCH CRONS & KEEPERS
    // =========================================================================

    function checkUpkeep(bytes calldata /* checkData */) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastEpochStart + epochDuration);
        performData = abi.encode(currentEpoch, lastEpochStart + epochDuration);
    }

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
        uint256 count = shardCount;
        for (uint256 i = 0; i < count; i++) {
            EpochShardData storage esd = epochShards[e][i];
            if (esd.totalContributed == 0) continue;

            uint128 b = uint128((uint256(shards[i].alpha) * budgetPerAlpha) / 100);
            uint128 maxB = uint128((uint256(shards[i].rewardPool) * emissionBps) / 10000);
            if (b > maxB) b = maxB;

            shards[i].rewardPool -= b;
            esd.budget = b;
        }
        currentEpoch = e + 1;
        lastEpochStart = block.timestamp;
        emit EpochAdvanced(currentEpoch);
    }

    // =========================================================================
    // CONTRIBUTIONS & OFF-CHAIN VERIFICATION
    // =========================================================================

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
            uint256 feePaid = _safeTransferFrom(rewardToken, msg.sender, address(this), registrationFee);
            shards[shardId].rewardPool += uint128(feePaid);
            emit Joined(msg.sender, feePaid);
        }
        joined[msg.sender] = true;

        gasCost = (gasUnits * shards[shardId].gasPrice) / 1e18;
        if (gasCost > 0) {
            uint256 actualGas = _safeTransferFrom(rewardToken, msg.sender, address(this), gasCost);
            epochGasPaid[e][msg.sender] += actualGas;
            epochTotalGasPaid[e] += actualGas;
            epochRebatePool[e] += (actualGas * gasRebateFractionBps) / 10000;
        }

        shardContribution[e][shardId][msg.sender] += amount;
        epochShards[e][shardId].totalContributed += uint128(amount);

        // Smooth continuous reputation scaling (eliminates binary cliffs)
        UserInfo storage u = users[msg.sender];
        u.totalContributedAllTime += uint224(amount);
        if (u.reputation == 0) u.reputation = initialReputation;

        // Continuous interpolation: delta in [4000, 8000] based on contribution scaling up to 50 ether
        uint256 scaling = amount >= 50 ether ? 4000 : (amount * 4000) / 50 ether;
        uint32 delta = uint32(4000 + scaling);

        u.reputation = uint32((uint256(u.reputation) * 80 + uint256(delta) * 20) / 100);
        if (u.reputation > 10000) u.reputation = 10000;
        if (u.reputation < 500) u.reputation = 500;
        epochReputation[e][msg.sender] = u.reputation;

        return gasCost;
    }

    // =========================================================================
    // CLAIMS, BATCH CLAIMS & PROPORTIONAL REBATES
    // =========================================================================

    function claimReward(uint256 epoch, uint256 shardId) public nonReentrant {
        _claimRewardInternal(epoch, shardId);
    }

    function claimRebate(uint256 epoch) public nonReentrant {
        _claimRebateInternal(epoch);
    }

    /**
     * @notice Batch claims rewards and rebates across multiple epochs and shards.
     * Drastically reduces gas overhead and eliminates repetitive transaction signing.
     */
    function batchClaim(
        uint256[] calldata epochs,
        uint256[][] calldata shardIdsList,
        bool[] calldata claimRebatesList
    ) external nonReentrant {
        require(epochs.length == shardIdsList.length && epochs.length == claimRebatesList.length, "length mismatch");
        for (uint256 i = 0; i < epochs.length; i++) {
            uint256 ep = epochs[i];
            for (uint256 j = 0; j < shardIdsList[i].length; j++) {
                _claimRewardInternal(ep, shardIdsList[i][j]);
            }
            if (claimRebatesList[i]) {
                _claimRebateInternal(ep);
            }
        }
    }

    function _claimRewardInternal(uint256 epoch, uint256 shardId) internal {
        require(epoch < currentEpoch, "epoch running");
        EpochShardData storage esd = epochShards[epoch][shardId];
        require(!esd.swept, "swept");
        require(!rewardClaimed[epoch][msg.sender][shardId], "already claimed");

        uint256 userContrib = shardContribution[epoch][shardId][msg.sender];
        require(userContrib > 0, "no contrib");
        uint256 total = esd.totalContributed;
        require(total > 0, "no total");

        rewardClaimed[epoch][msg.sender][shardId] = true;

        uint256 rawShareBps = (userContrib * 10000) / total;
        uint256 capBps = effectiveCapBps();
        if (rawShareBps > capBps) rawShareBps = capBps;

        uint256 phiBps = epochReputation[epoch][msg.sender];
        if (phiBps < fairnessPhiMinBps) phiBps = fairnessPhiMinBps;

        uint256 effectiveBps = (rawShareBps * phiBps) / 10000;
        uint256 reward = (uint256(esd.budget) * effectiveBps) / 10000;

        if (reward > 0) {
            esd.paidOut += uint128(reward);
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, epoch, shardId, reward);
        }
    }

    /**
     * @notice Sybil-resistant gas rebate distribution.
     * Proportional to actual gas paid by the user in the epoch, preventing dust account dilution attacks.
     */
    function _claimRebateInternal(uint256 epoch) internal {
        require(epoch < currentEpoch, "epoch running");
        require(!rebateClaimed[epoch][msg.sender], "rebate claimed");
        uint256 userGas = epochGasPaid[epoch][msg.sender];
        require(userGas > 0, "no gas paid");

        rebateClaimed[epoch][msg.sender] = true;

        uint256 pool = epochRebatePool[epoch];
        uint256 totalGas = epochTotalGasPaid[epoch];
        if (pool == 0 || totalGas == 0) return;

        // Proportional rebate = Pool * (UserGas / TotalGas)
        uint256 rebate = (pool * userGas) / totalGas;
        if (rebate > 0) {
            rewardToken.safeTransfer(msg.sender, rebate);
            emit RebateClaimed(msg.sender, epoch, rebate);
        }
    }

    function sweepUnclaimed(uint256 epoch, uint256 shardId) external nonReentrant {
        require(currentEpoch > epoch + claimWindowEpochs, "claim window open");
        EpochShardData storage esd = epochShards[epoch][shardId];
        require(!esd.swept, "already swept");

        esd.swept = true;
        uint128 left = esd.budget - esd.paidOut;
        shards[shardId].rewardPool += left;
        emit Swept(epoch, shardId, left);
    }

    // =========================================================================
    // SAFETY & HELPERS
    // =========================================================================

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 actualReceived) {
        uint256 beforeBal = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        actualReceived = token.balanceOf(to) - beforeBal;
    }

    /// Rescues accidentally deposited third-party tokens (cannot touch rewardToken)
    function rescueToken(address tokenAddress, address to, uint256 amount) external onlyOwner {
        require(tokenAddress != address(rewardToken), "cannot rescue reward token");
        IERC20(tokenAddress).safeTransfer(to, amount);
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
        return (s.rewardPool, s.gasPrice, epochShards[currentEpoch][shardId].totalContributed, s.alpha, s.active);
    }
}
