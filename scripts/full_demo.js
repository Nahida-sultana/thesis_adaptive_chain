const hre = require("hardhat");

async function main() {
  const [msp, user1, user2, user3, user4] = await hre.ethers.getSigners();

  const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS;
  const FMC_ADDRESS   = process.env.FMC_ADDRESS;
  if (!TOKEN_ADDRESS || !FMC_ADDRESS) {
    console.log("Set TOKEN_ADDRESS and FMC_ADDRESS first");
    return;
  }

  const token = await hre.ethers.getContractAt("MockRewardToken", TOKEN_ADDRESS);
  const fmc   = await hre.ethers.getContractAt("FairMetaChain", FMC_ADDRESS);

  console.log("=== FairMetaChain Full Demo ===\n");

  // Fund users
  for (const u of [user1, user2, user3, user4]) {
    await (await token.connect(msp).transfer(u.address, hre.ethers.parseEther("1000"))).wait();
    await (await token.connect(u).approve(FMC_ADDRESS, hre.ethers.parseEther("1000"))).wait();
  }
  console.log("1. Funded 4 users");

  // More contributions
  console.log("2. Users contributing...");
  await (await fmc.connect(user1).contribute(0, hre.ethers.parseEther("120"), hre.ethers.parseEther("12"))).wait();
  await (await fmc.connect(user2).contribute(0, hre.ethers.parseEther("80"),  hre.ethers.parseEther("6"))).wait();
  await (await fmc.connect(user3).contribute(1, hre.ethers.parseEther("100"), hre.ethers.parseEther("9"))).wait();
  await (await fmc.connect(user4).contribute(1, hre.ethers.parseEther("50"),  hre.ethers.parseEther("4"))).wait();
  await (await fmc.connect(user1).contribute(2, hre.ethers.parseEther("60"),  hre.ethers.parseEther("5"))).wait();
  await (await fmc.connect(user2).contribute(2, hre.ethers.parseEther("40"),  hre.ethers.parseEther("3"))).wait();
  console.log("   Contributions done");

  // Show state
  for (let i = 0; i < 3; i++) {
    const s = await fmc.getShard(i);
    console.log(`   Shard ${i}: contributed=${hre.ethers.formatEther(s.totalContributed)}, gasPrice=${hre.ethers.formatEther(s.gasPrice)}`);
  }

  // Advance epoch
  console.log("\n3. Advancing epoch...");
  await (await fmc.connect(msp).forceAdvanceEpoch()).wait();
  console.log("   Current epoch:", (await fmc.currentEpoch()).toString());

  // Claim rewards
  console.log("\n4. Claiming rewards...");
  for (const [user, name] of [[user1,"U1"],[user2,"U2"],[user3,"U3"],[user4,"U4"]]) {
    for (let shard = 0; shard < 3; shard++) {
      try {
        const tx = await fmc.connect(user).claimReward(1, shard);
        await tx.wait();
        console.log(`   ${name} claimed reward from shard ${shard}`);
      } catch (e) {
        // silent if nothing to claim
      }
    }
  }

  // Claim rebates
  console.log("\n5. Claiming rebates...");
  for (const [user, name] of [[user1,"U1"],[user2,"U2"],[user3,"U3"],[user4,"U4"]]) {
    try {
      const tx = await fmc.connect(user).claimRebate(1);
      await tx.wait();
      console.log(`   ${name} claimed rebate`);
    } catch (e) {}
  }

  // Final balances
  console.log("\n6. Final token balances:");
  for (const [user, name] of [[user1,"U1"],[user2,"U2"],[user3,"U3"],[user4,"U4"]]) {
    const bal = await token.balanceOf(user.address);
    const info = await fmc.getUserInfo(user.address);
    console.log(`   ${name}: balance=${hre.ethers.formatEther(bal)}, rep=${info.reputation}`);
  }

  console.log("\n=== Demo finished successfully ===");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
