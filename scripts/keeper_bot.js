/**
 * @file keeper_bot.js
 * @notice Autonomous Keeper Daemon for FairMetaChain.
 *
 * Implements Roadmap Milestone 3:
 *  - Continuously monitors epoch expiration on-chain via `checkUpkeep()`.
 *  - Automatically triggers `performUpkeep()` / `advanceEpoch()` when epoch duration has elapsed.
 *  - Supports both single-check execution (for cron jobs) and continuous polling loop.
 *
 * Usage:
 *   node scripts/keeper_bot.js [--loop] [--interval=10]
 */

const { ethers } = require("hardhat");

class FairMetaChainKeeperBot {
  constructor(contractAddress, signer, pollIntervalMs = 5000) {
    this.contractAddress = contractAddress;
    this.signer = signer;
    this.pollIntervalMs = pollIntervalMs;
    this.isRunning = false;
  }

  async init() {
    this.fmc = await ethers.getContractAt("FairMetaChainV5", this.contractAddress, this.signer);
  }

  /**
   * Executes a single upkeep check and advances the epoch if needed.
   * @returns {Promise<{performed: boolean, epoch: number}>}
   */
  async checkAndPerformUpkeep() {
    if (!this.fmc) await this.init();

    try {
      const [upkeepNeeded, performData] = await this.fmc.checkUpkeep("0x");
      const currentEpoch = await this.fmc.currentEpoch();
      const lastStart = await this.fmc.lastEpochStart();
      const duration = await this.fmc.epochDuration();
      const latestBlock = await ethers.provider.getBlock("latest");
      const now = latestBlock ? BigInt(latestBlock.timestamp) : BigInt(Math.floor(Date.now() / 1000));
      const nextRoll = lastStart + duration;

      console.log(`[Keeper] Current Epoch: ${currentEpoch} | Block Time: ${now} | Next Roll: ${nextRoll}`);

      if (upkeepNeeded) {
        console.log(`[Keeper] Epoch duration reached! Triggering performUpkeep()...`);
        const tx = await this.fmc.performUpkeep(performData);
        const receipt = await tx.wait();
        const newEpoch = await this.fmc.currentEpoch();
        console.log(`[Keeper] Successfully advanced to Epoch ${newEpoch}! Gas used: ${receipt.gasUsed.toString()}`);
        return { performed: true, epoch: Number(newEpoch) };
      } else {
        const remaining = nextRoll > now ? nextRoll - now : 0n;
        console.log(`[Keeper] Upkeep not needed yet. ~${remaining} seconds remaining in epoch ${currentEpoch}.`);
        return { performed: false, epoch: Number(currentEpoch) };
      }
    } catch (err) {
      console.error(`[Keeper] Error during upkeep check:`, err.message || err);
      return { performed: false, error: err };
    }
  }

  /**
   * Runs the autonomous keeper in a persistent background polling loop.
   */
  async startLoop() {
    this.isRunning = true;
    console.log(`[Keeper] Bot daemon started. Polling every ${this.pollIntervalMs / 1000} seconds...`);
    while (this.isRunning) {
      await this.checkAndPerformUpkeep();
      await new Promise((resolve) => setTimeout(resolve, this.pollIntervalMs));
    }
  }

  stop() {
    this.isRunning = false;
    console.log(`[Keeper] Daemon stopped.`);
  }
}

// Standalone execution if run directly via CLI
if (require.main === module) {
  async function main() {
    const [deployer] = await ethers.getSigners();
    const contractAddress = process.env.FMC_ADDRESS;

    if (!contractAddress) {
      console.error("Please provide FMC_ADDRESS environment variable.");
      process.exit(1);
    }

    const isLoop = process.argv.includes("--loop");
    const keeper = new FairMetaChainKeeperBot(contractAddress, deployer, 5000);

    if (isLoop) {
      await keeper.startLoop();
    } else {
      await keeper.checkAndPerformUpkeep();
    }
  }

  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { FairMetaChainKeeperBot };
