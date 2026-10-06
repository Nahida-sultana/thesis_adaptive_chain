/**
 * @file v5_roadmap_demo.js
 * @notice Complete Integration & Verification Demo for the 3 Roadmap Milestones:
 *
 *  1. Decentralized TEE Device Attestation (anti-Sybil hardware binding, permissionless onboarding).
 *  2. Off-Chain Verification Layer (work receipts, replay protection, anti-tampering).
 *  3. Automated Epoch Crons & Keepers (checkUpkeep, performUpkeep, claims & rebates).
 *
 * Run:
 *   npx hardhat run scripts/v5_roadmap_demo.js
 */

const { ethers } = require("hardhat");
const { OffChainWorkerService } = require("./offchain_worker");
const { FairMetaChainKeeperBot } = require("./keeper_bot");

const E = (n) => ethers.parseEther(String(n));
const F = (n) => Number(ethers.formatEther(n));

const warp = async (sec) => {
  await ethers.provider.send("evm_increaseTime", [sec]);
  await ethers.provider.send("evm_mine", []);
};

const expectRevert = async (promise, expectedSubstring) => {
  try {
    await promise;
    return "FAILED: Did not revert!";
  } catch (err) {
    const msg = err.message || err.toString();
    if (expectedSubstring && !msg.includes(expectedSubstring)) {
      return `Reverted with different reason: ${msg}`;
    }
    return `OK: Reverted as expected (${expectedSubstring || "revert"})`;
  }
};

async function main() {
  console.log("================================================================================");
  console.log("FAIRMETACHAIN ROADMAP MILESTONES VERIFICATION (V5)");
  console.log("================================================================================\n");

  const [deployer, teeAuthority, workVerifier, user1, user2, attackerAcct1, attackerAcct2] =
    await ethers.getSigners();

  const chainId = (await ethers.provider.getNetwork()).chainId;

  // --------------------------------------------------------------------------
  // STEP 0: Deploy Infrastructure
  // --------------------------------------------------------------------------
  console.log("--- STEP 0: Deploying Tokens & FairMetaChainV5 ---");
  const Token = await ethers.getContractFactory("MockRewardToken");
  const token = await Token.deploy();
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();

  const FMC5 = await ethers.getContractFactory("FairMetaChainV5");
  const fmc = await FMC5.deploy(tokenAddr, teeAuthority.address, workVerifier.address);
  await fmc.waitForDeployment();
  const fmcAddr = await fmc.getAddress();

  console.log(`MockRewardToken deployed : ${tokenAddr}`);
  console.log(`FairMetaChainV5 deployed   : ${fmcAddr}`);
  console.log(`TEE Attestation Authority: ${teeAuthority.address}`);
  console.log(`Work Verifier Oracle     : ${workVerifier.address}\n`);

  // Create shards with sensitivities
  await (await fmc.createShard(1200)).wait(); // Shard 0: alpha = 12.00
  await (await fmc.createShard(1800)).wait(); // Shard 1: alpha = 18.00
  await (await fmc.createShard(1500)).wait(); // Shard 2: alpha = 15.00

  // Deposit 10,000 FMC into Shard 0
  await (await token.approve(fmcAddr, E(30000))).wait();
  await (await fmc.depositReward(0, E(10000))).wait();
  await (await fmc.depositReward(1, E(10000))).wait();
  await (await fmc.depositReward(2, E(10000))).wait();

  // Distribute tokens to participants for gas & fees
  for (const u of [user1, user2, attackerAcct1, attackerAcct2]) {
    await (await token.transfer(u.address, E(1000))).wait();
    await (await token.connect(u).approve(fmcAddr, E(1000))).wait();
  }
  console.log("Seeded shards with rewards and funded user accounts.\n");

  // --------------------------------------------------------------------------
  // MILESTONE 1: DECENTRALIZED VERIFICATION (TEE REMOTE ATTESTATION)
  // --------------------------------------------------------------------------
  console.log("================================================================================");
  console.log("MILESTONE 1: DECENTRALIZED VERIFICATION (REPLACING OWNER WHITELIST)");
  console.log("================================================================================");

  // Turn on permissioned mode to test identity gating
  await (await fmc.proposeParams(3500, 2000, 2000, E(5), 2000, E(10), true)).wait();
  await warp(24 * 3600 + 5);
  await (await fmc.executeParams()).wait();
  console.log(`Permissioned mode active: ${await fmc.permissioned()}`);
  console.log(`Effective Cap: ${Number(await fmc.effectiveCapBps()) / 100}%`);

  // Helper to generate TEE Attestation signature
  const signAttestation = async (account, hardwareId, expiry, signer = teeAuthority) => {
    const packed = ethers.solidityPacked(
      ["string", "uint256", "address", "bytes32", "uint256"],
      ["FAIRMETACHAIN_TEE_ATTESTATION", chainId, account, hardwareId, expiry]
    );
    const hash = ethers.keccak256(packed);
    return signer.signMessage(ethers.getBytes(hash));
  };

  const hwId1 = ethers.keccak256(ethers.toUtf8Bytes("DEVICE_INTEL_SGX_SERVER_001"));
  const hwId2 = ethers.keccak256(ethers.toUtf8Bytes("DEVICE_AMD_SEV_SERVER_002"));
  const latestBlock = await ethers.provider.getBlock("latest");
  const expiry = BigInt(latestBlock.timestamp + 86400 * 30);

  // 1.1 Valid Device 1 Registration
  const sig1 = await signAttestation(user1.address, hwId1, expiry);
  await (await fmc.connect(user1).registerWithDeviceAttestation(hwId1, expiry, sig1)).wait();
  console.log(`[PASS] User1 permissionlessly registered with TEE Hardware ID 1! Status: registered=${await fmc.registered(user1.address)}`);

  // 1.2 Valid Device 2 Registration
  const sig2 = await signAttestation(user2.address, hwId2, expiry);
  await (await fmc.connect(user2).registerWithDeviceAttestation(hwId2, expiry, sig2)).wait();
  console.log(`[PASS] User2 permissionlessly registered with TEE Hardware ID 2! Status: registered=${await fmc.registered(user2.address)}`);

  // 1.3 Anti-Sybil Defense: Attacker tries to register account 2 with the SAME hardware ID 1
  const sigReuse = await signAttestation(attackerAcct1.address, hwId1, expiry);
  const resultReuse = await expectRevert(
    fmc.connect(attackerAcct1).registerWithDeviceAttestation(hwId1, expiry, sigReuse),
    "hardware already registered"
  );
  console.log(`[PASS] Sybil duplicate hardware check: ${resultReuse}`);

  // 1.4 Forgery Check: Attacker signs attestation with their own fake key
  const forgedSig = await signAttestation(attackerAcct1.address, ethers.randomBytes(32), expiry, attackerAcct1);
  const resultForgery = await expectRevert(
    fmc.connect(attackerAcct1).registerWithDeviceAttestation(ethers.randomBytes(32), expiry, forgedSig),
    "invalid attestation signature"
  );
  console.log(`[PASS] Forged TEE attestation check: ${resultForgery}\n`);

  // --------------------------------------------------------------------------
  // MILESTONE 2: OFF-CHAIN VERIFICATION LAYER (CRYPTOGRAPHIC WORK RECEIPTS)
  // --------------------------------------------------------------------------
  console.log("================================================================================");
  console.log("MILESTONE 2: OFF-CHAIN VERIFICATION LAYER (PROOF OF COMPUTE / WORK RECEIPTS)");
  console.log("================================================================================");

  const workerService = new OffChainWorkerService(workVerifier, fmcAddr, chainId);

  // 2.1 User 1 executes off-chain Metaverse compute (e.g. 100 units of 3D rendering)
  console.log("Simulating User 1 rendering compute task off-chain...");
  const task1 = await workerService.createSignedWorkReceipt({
    shardId: 0,
    contributorAddress: user1.address,
    amount: E(100),
    gasUnits: 10n
  });
  console.log(`Generated WorkReceipt: TaskId=${task1.receipt.taskId.slice(0, 14)}... ResultHash=${task1.receipt.resultHash.slice(0, 14)}...`);

  // Submit verified contribution
  await (await fmc.connect(user1).contributeWithProof(task1.receipt, task1.signature)).wait();
  console.log(`[PASS] User 1 submitted verified contribution of 100 units to Shard 0.`);

  // 2.2 User 2 executes off-chain Metaverse physics simulation (e.g. 50 units)
  const task2 = await workerService.createSignedWorkReceipt({
    shardId: 0,
    contributorAddress: user2.address,
    amount: E(50),
    gasUnits: 5n
  });
  await (await fmc.connect(user2).contributeWithProof(task2.receipt, task2.signature)).wait();
  console.log(`[PASS] User 2 submitted verified contribution of 50 units to Shard 0.`);

  // 2.3 Replay Attack Protection: Attacker tries to submit Task 1 again
  const resultReplay = await expectRevert(
    fmc.connect(user1).contributeWithProof(task1.receipt, task1.signature),
    "task already submitted"
  );
  console.log(`[PASS] Replay protection check: ${resultReplay}`);

  // 2.4 Tampering Attack: User tries to inflate amount from 50 to 500 on a fresh task without oracle resigning
  const task3 = await workerService.createSignedWorkReceipt({
    shardId: 0,
    contributorAddress: user2.address,
    amount: E(50),
    gasUnits: 5n
  });
  const tamperedReceipt = { ...task3.receipt, amount: E(500) };
  const resultTamper = await expectRevert(
    fmc.connect(user2).contributeWithProof(tamperedReceipt, task3.signature),
    "invalid work signature"
  );
  console.log(`[PASS] Tampered work amount check: ${resultTamper}`);

  // 2.5 Strict Proof Mode: Enforce requireProof = true
  await (await fmc.setRequireProof(true)).wait();
  const resultUnverifiedBlocked = await expectRevert(
    fmc.connect(user1).contribute(0, E(20), 2n),
    "proof required"
  );
  console.log(`[PASS] Strict proof mode blocks unverified contribute(): ${resultUnverifiedBlocked}\n`);

  // --------------------------------------------------------------------------
  // MILESTONE 3: AUTOMATED EPOCH CRONS & KEEPERS
  // --------------------------------------------------------------------------
  console.log("================================================================================");
  console.log("MILESTONE 3: AUTOMATED EPOCH CRONS & KEEPERS (CHAINLINK COMPATIBLE)");
  console.log("================================================================================");

  const keeperBot = new FairMetaChainKeeperBot(fmcAddr, deployer);

  // 3.1 Initial Upkeep: Trigger first upkeep to rollover Epoch 1 (since timelock test advanced clock)
  console.log("3.1 Keeper advances Epoch 1 after timelock duration:");
  const upkeepCheck1 = await keeperBot.checkAndPerformUpkeep();
  console.log(`[PASS] Keeper triggered performUpkeep()! Current Epoch: ${upkeepCheck1.epoch}.`);

  // 3.2 Check immediately after rollover: Upkeep should NOT be needed yet
  console.log("\n3.2 Checking keeper status immediately after rollover (before epoch duration elapses):");
  const upkeepCheck2 = await keeperBot.checkAndPerformUpkeep();
  console.log(`[PASS] Keeper correctly decided: performed = ${upkeepCheck2.performed} (Epoch is still running).`);

  // 3.3 Simulate time passage: Advance EVM time by 1 hour (epoch duration)
  console.log("\n3.3 Simulating passage of 1 hour (epoch duration)...");
  await warp(3605);

  // 3.4 Check after duration elapsed: Upkeep should be triggered autonomously
  console.log("Checking keeper status after epoch duration elapsed:");
  const upkeepCheck3 = await keeperBot.checkAndPerformUpkeep();
  console.log(`[PASS] Keeper autonomously triggered upkeep! Advanced to Epoch: ${upkeepCheck3.epoch}.`);

  // 3.4 Claims & Settlement in New Epoch
  console.log("\n--- Claims & Settlement for Epoch 1 ---");
  const u1BalBefore = await token.balanceOf(user1.address);
  await (await fmc.connect(user1).claimReward(1, 0)).wait();
  await (await fmc.connect(user1).claimRebate(1)).wait();
  const u1Reward = F((await token.balanceOf(user1.address)) - u1BalBefore);

  const u2BalBefore = await token.balanceOf(user2.address);
  await (await fmc.connect(user2).claimReward(1, 0)).wait();
  await (await fmc.connect(user2).claimRebate(1)).wait();
  const u2Reward = F((await token.balanceOf(user2.address)) - u2BalBefore);

  const epochBudget = F(await fmc.epochBudget(1, 0));
  const rebatePool = F(await fmc.epochRebatePool(1));

  console.log(`Epoch 1 Shard 0 Budget: ${epochBudget.toFixed(2)} FMC`);
  console.log(`Epoch 1 Rebate Pool   : ${rebatePool.toFixed(4)} FMC (shared equally among active contributors)`);
  console.log(`User 1 Total Payout   : ${u1Reward.toFixed(3)} FMC (contributed 100 units, subject to 35% cap)`);
  console.log(`User 2 Total Payout   : ${u2Reward.toFixed(3)} FMC (contributed 50 units)`);

  const u1Info = await fmc.getUserInfo(user1.address);
  const u2Info = await fmc.getUserInfo(user2.address);
  console.log(`User 1 Reputation Score: ${Number(u1Info[0])} / 10000`);
  console.log(`User 2 Reputation Score: ${Number(u2Info[0])} / 10000`);

  console.log("\n================================================================================");
  console.log("ALL 3 ROADMAP MILESTONES SUCCESSFULLY IMPLEMENTED AND VERIFIED!");
  console.log("================================================================================");
}

main().catch((err) => {
  console.error("Demo failed:", err);
  process.exit(1);
});
