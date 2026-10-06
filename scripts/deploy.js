const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying FairMetaChain pilot with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // 1. Deploy Mock Reward Token
  const Token = await hre.ethers.getContractFactory("MockRewardToken");
  const token = await Token.deploy();
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log("MockRewardToken deployed to:", tokenAddress);

  // 2. Deploy FairMetaChain
  const FMC = await hre.ethers.getContractFactory("FairMetaChain");
  const fmc = await FMC.deploy(tokenAddress);
  await fmc.waitForDeployment();
  const fmcAddress = await fmc.getAddress();
  console.log("FairMetaChain deployed to:", fmcAddress);

  // 3. Create a few shards
  let tx = await fmc.createShard(1200); // alpha = 12.00 (scaled)
  await tx.wait();
  tx = await fmc.createShard(1800);
  await tx.wait();
  tx = await fmc.createShard(1500);
  await tx.wait();
  console.log("Created 3 shards");

  // 4. Approve and deposit initial rewards
  const depositAmount = hre.ethers.parseEther("10000");
  tx = await token.approve(fmcAddress, depositAmount * 3n);
  await tx.wait();

  for (let i = 0; i < 3; i++) {
    tx = await fmc.depositReward(i, depositAmount);
    await tx.wait();
    console.log(`Deposited 10000 tokens to shard ${i}`);
  }

  // 5. Set initial gas prices
  await (await fmc.setGasPrice(0, hre.ethers.parseEther("0.02"))).wait();
  await (await fmc.setGasPrice(1, hre.ethers.parseEther("0.03"))).wait();
  await (await fmc.setGasPrice(2, hre.ethers.parseEther("0.025"))).wait();
  console.log("Gas prices set");

  console.log("\n=== Deployment Summary ===");
  console.log("Reward Token :", tokenAddress);
  console.log("FairMetaChain:", fmcAddress);
  console.log("Deployer     :", deployer.address);
  console.log("==========================\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
