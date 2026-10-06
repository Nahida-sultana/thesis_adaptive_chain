/**
 * @file offchain_worker.js
 * @notice Off-Chain Worker & Verification Service for FairMetaChain.
 *
 * Implements Roadmap Milestone 2:
 *  - Generates synthetic Metaverse compute tasks (e.g. 3D spatial audio, ray-traced chunk rendering).
 *  - Simulates off-chain compute benchmark execution and calculates cryptographic resultHash (SHA-256).
 *  - TEE Verification Authority signs an EIP-191 formatted WorkReceipt with an authorized enclave key.
 *  - Formats receipts for on-chain submission via `contributeWithProof()`.
 */

const { ethers } = require("hardhat");
const crypto = require("crypto");

class OffChainWorkerService {
  /**
   * @param {ethers.Signer|ethers.Wallet} verifierWallet Authorized TEE verifier key
   * @param {string} contractAddress Deployed FairMetaChainV5 address
   * @param {bigint} chainId EVM Chain ID
   */
  constructor(verifierWallet, contractAddress, chainId = 31337n) {
    this.verifierWallet = verifierWallet;
    this.contractAddress = contractAddress;
    this.chainId = BigInt(chainId);
  }

  /**
   * Simulates Metaverse rendering or physics computation.
   * @param {number} complexity Number of simulated floating point operations (FLOPS)
   */
  executeComputeTask(complexity = 1000) {
    // Generate simulated 3D spatial points
    const buffer = Buffer.alloc(complexity * 4);
    for (let i = 0; i < complexity; i++) {
      buffer.writeFloatLE(Math.sin(i) * Math.cos(i), i * 4);
    }
    // Calculate hash of the computed Metaverse rendering chunk
    const resultHash = "0x" + crypto.createHash("sha256").update(buffer).digest("hex");
    return resultHash;
  }

  /**
   * Creates and cryptographically signs a WorkReceipt.
   *
   * @param {object} params
   * @param {number} params.shardId
   * @param {string} params.contributorAddress
   * @param {bigint} params.amount Resource units (in wei/ether scale)
   * @param {bigint} params.gasUnits Gas units consumed
   * @param {number} params.validitySeconds How long the receipt remains valid
   */
  async createSignedWorkReceipt({
    shardId,
    contributorAddress,
    amount,
    gasUnits = 5n,
    validitySeconds = 600
  }) {
    const taskId = ethers.hexlify(ethers.randomBytes(32));
    const resultHash = this.executeComputeTask(500);

    const latestBlock = await ethers.provider.getBlock("latest");
    const currentBlockTime = latestBlock ? BigInt(latestBlock.timestamp) : BigInt(Math.floor(Date.now() / 1000));
    const deadline = currentBlockTime + BigInt(validitySeconds);

    const receipt = {
      taskId,
      shardId: BigInt(shardId),
      contributor: contributorAddress,
      amount: BigInt(amount),
      gasUnits: BigInt(gasUnits),
      resultHash,
      deadline
    };

    // Pack message exactly matching FairMetaChainV5.sol:
    // abi.encodePacked("FAIRMETACHAIN_WORK_RECEIPT", block.chainid, taskId, shardId, contributor, amount, gasUnits, resultHash, deadline)
    const packed = ethers.solidityPacked(
      ["string", "uint256", "bytes32", "uint256", "address", "uint256", "uint256", "bytes32", "uint256"],
      [
        "FAIRMETACHAIN_WORK_RECEIPT",
        this.chainId,
        receipt.taskId,
        receipt.shardId,
        receipt.contributor,
        receipt.amount,
        receipt.gasUnits,
        receipt.resultHash,
        receipt.deadline
      ]
    );

    const messageHash = ethers.keccak256(packed);
    // Sign with Ethereum Signed Message prefix (matching MessageHashUtils.toEthSignedMessageHash)
    const signature = await this.verifierWallet.signMessage(ethers.getBytes(messageHash));

    return { receipt, signature };
  }
}

module.exports = { OffChainWorkerService };
