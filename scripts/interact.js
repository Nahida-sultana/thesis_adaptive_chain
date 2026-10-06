/**
 * Simple interaction script for the FairMetaChain pilot.
 * Usage examples:
 *   npx hardhat run scripts/interact.js --network localhost
 */
const hre = require("hardhat");

async function main() {
  const [msp, user1, user2, user3] = await hre.ethers.getSigners();

  // Replace these with the addresses printed by deploy.js
  const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS;
  const FMC_ADDRESS   = process.env.FMC_ADDRESS;

  if (!TOKEN_ADDRESS || !FMC_ADDRESS) {
    console.log("Please set TOKEN_ADDRESS and FMC_ADDRESS environment variables");
    console.log("Example:");
    console.log('  $env:TOKEN_ADDRESS="0x..."');
    console.log('  $env:FMC_ADDRESS="0x..."');
    console.log("  npx hardhat run scripts/interact.js --network localhost");
    return;
  }

  const token = await hre.ethers.getContractAt("MockRewardToken", TOKEN_ADDRESS);
  const fmc   = await hre.ethers.getContractAt("FairMetaChain", FMC_ADDRESS);

  console.log("=== FairMetaChain Pilot Interaction ===\n");

  // Give some tokens to users so they can pay gas
  for (const u of [user1, user2, user3]) {
    await (await token.connect(msp).transfer(u.address, hre.ethers.parseEther("500"))).wait();
    await (await token.connect(u).approve(FMC_ADDRESS, hre.ethers.parseEther("500"))).wait();
  }
  console.log("Distributed tokens and approvals to 3 users");

  // Users contribute
  console.log("\nUsers contributing...");
  await (await fmc.connect(user1).contribute(0, hre.ethers.parseEther("100"), hre.ethers.parseEther("10"))).wait();
  await (await fmc.connect(user2).contribute(0, hre.ethers.parseEther("60"),  hre.ethers.parseEther("5"))).wait();
  await (await fmc.connect(user3).contribute(1, hre.ethers.parseEther("80"),  hre.ethers.parseEther("8"))).wait();
  await (await fmc.connect(user1).contribute(1, hre.ethers.parseEther("40"),  hre.ethers.parseEther("4"))).wait();
  console.log("Contributions recorded");

  // Show state
  for (let i = 0; i < 3; i++) {
    const s = await fmc.getShard(i);
    console.log(`Shard ${i}: rewardPool=${hre.ethers.formatEther(s.rewardPool)}, totalContributed=${hre.ethers.formatEther(s.totalContributed)}, gasPrice=${hre.ethers.formatEther(s.gasPrice)}`);
  }

  for (const u of [user1, user2, user3]) {
    const info = await fmc.getUserInfo(u.address);
    console.log(`User ${u.address.slice(0,8)}... rep=${info.reputation}, totalContrib=${hre.ethers.formatEther(info.totalContributedAllTime)}`);
  }

  console.log("\nPilot interaction finished successfully.");
  console.log("Next steps: advance epoch, claim rewards, claim rebates.");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
