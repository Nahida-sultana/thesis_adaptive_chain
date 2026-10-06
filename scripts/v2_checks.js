// V2 behaviour checks. Run: npx hardhat run scripts/v2_checks.js
const { ethers } = require("hardhat");
const E = (n) => ethers.parseEther(String(n));
const F = (n) => Number(ethers.formatEther(n));
async function main() {
  const [owner, a, b, c] = await ethers.getSigners();
  const token = await (await ethers.getContractFactory("MockRewardToken")).deploy();
  const fmc = await (await ethers.getContractFactory("FairMetaChainV2")).deploy(await token.getAddress());
  const addr = await fmc.getAddress();
  await (await fmc.createShard(1200)).wait();
  await (await token.approve(addr, E(10000))).wait();
  await (await fmc.depositReward(0, E(10000))).wait();
  for (const u of [a, b, c]) await (await token.transfer(u.address, E(1000))).wait();
  const contribute = async (u, amt) => {
    await (await token.connect(u).approve(addr, E(amt + 10))).wait();
    return (await fmc.connect(u).contribute(0, E(amt), E(5))).wait();
  };

  // 1. Reputation moves payout (a: 3 contributions of 50, b: 3 of 5 -> different reputation, same share later)
  for (let i = 0; i < 3; i++) { await contribute(a, 50); await contribute(b, 5); }
  console.log("rep a (big contribs):", Number((await fmc.getUserInfo(a.address))[0]), "| rep b (small):", Number((await fmc.getUserInfo(b.address))[0]));

  // 2. Order-independence + pool decrement + rollover
  const poolBefore = F((await fmc.getShard(0))[0]);
  await (await fmc.forceAdvanceEpoch()).wait();
  const poolAfter = F((await fmc.getShard(0))[0]);
  console.log(`pool ${poolBefore} -> ${poolAfter}, epoch1 budget ${F(await fmc.epochBudget(1, 0))}`);
  const bal = async (u) => F(await token.balanceOf(u.address));
  let x = await bal(b); await (await fmc.connect(b).claimReward(1, 0)).wait(); const rb = (await bal(b)) - x;
  x = await bal(a); await (await fmc.connect(a).claimReward(1, 0)).wait(); const ra = (await bal(a)) - x;
  console.log(`b claimed first: ${rb.toFixed(3)} | a claimed second: ${ra.toFixed(3)} (a has 150 vs b 15 contributed)`);
  try { await fmc.connect(a).claimReward(1, 0); } catch (e) { console.log("double claim blocked:", e.shortMessage); }
  for (let i = 0; i < 3; i++) await (await fmc.forceAdvanceEpoch()).wait();
  await (await fmc.sweepUnclaimed(1, 0)).wait();
  console.log("pool after sweep (unallocated rolls back):", F((await fmc.getShard(0))[0]));

  // 3. Permissioned mode blocks Sybil accounts
  await (await fmc.setPermissioned(true)).wait();
  await (await fmc.register([a.address], true)).wait();
  await contribute(a, 100).then(() => console.log("registered account a: OK"));
  try { await contribute(c, 100); } catch (e) { console.log("unregistered account c:", e.shortMessage || e.message); }
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
