// Fairness + gas test. Runs on in-process Hardhat network (does NOT touch your localhost node).
// Run: npx hardhat run scripts/fairness_test.js
const hre = require("hardhat");
const fs = require("fs");
const { ethers } = hre;
const NAME = process.env.CONTRACT || "FairMetaChain";
const E = (n) => ethers.parseEther(String(n));
const F = (n) => Number(ethers.formatEther(n));

async function main() {
  const signers = await ethers.getSigners();
  const owner = signers[0];
  const users = signers.slice(1, 10);

  const token = await (await ethers.getContractFactory("MockRewardToken")).deploy();
  const fmc = await (await ethers.getContractFactory(NAME)).deploy(await token.getAddress());
  const fmcAddr = await fmc.getAddress();

  await (await fmc.createShard(1200)).wait();
  await (await token.approve(fmcAddr, E(10000))).wait();
  await (await fmc.depositReward(0, E(10000))).wait();

  for (const u of users) await (await token.transfer(u.address, E(1000))).wait();

  const gas = {};
  const rec = (name, r) => (gas[name] = (gas[name] || []).concat(Number(r.gasUsed)));
  const rows = [];

  async function contribute(u, amt, gasUnits = 5) {
    await (await token.connect(u).approve(fmcAddr, E(amt + gasUnits * 2))).wait();
    const r = await (await fmc.connect(u).contribute(0, E(amt), E(gasUnits))).wait();
    rec("contribute", r);
  }
  async function claim(u, epoch, label, amt, group) {
    const before = await token.balanceOf(u.address);
    const r1 = await (await fmc.connect(u).claimReward(epoch, 0)).wait();
    rec("claimReward", r1);
    const afterReward = await token.balanceOf(u.address);
    const r2 = await (await fmc.connect(u).claimRebate(epoch)).wait();
    rec("claimRebate", r2);
    const total = F(await fmc.epochShardTotal(epoch, 0));
    rows.push({ scenario: group, epoch, user: label, contributed: amt,
      rawSharePct: +(amt / total * 100).toFixed(2),
      reward: F(afterReward - before) });
  }

  // Scenario 1: different contribution sizes (epoch 1)
  const s1 = [[users[0], "U1", 50], [users[1], "U2", 200], [users[2], "U3", 500], [users[3], "U4", 1000]];
  for (const [u, , a] of s1) await contribute(u, a);
  let r = await (await fmc.forceAdvanceEpoch()).wait(); rec("forceAdvanceEpoch", r);
  for (const [u, l, a] of s1) await claim(u, 1, l, a, "S1-different-sizes");

  // Scenario 2: Sybil. Honest 1 account x 1000 vs attacker 4 accounts x 250 (epoch 2)
  const honest = users[4], atk = users.slice(5, 9);
  await contribute(honest, 1000);
  for (const a of atk) await contribute(a, 250);
  r = await (await fmc.forceAdvanceEpoch()).wait(); rec("forceAdvanceEpoch", r);
  await claim(honest, 2, "Honest(1 acct)", 1000, "S2-sybil");
  for (let i = 0; i < atk.length; i++) await claim(atk[i], 2, `Atk${i + 1}`, 250, "S2-sybil");

  console.log("\n=== Reward distribution ===");
  console.table(rows);

  const atkTotal = rows.filter(x => x.user.startsWith("Atk")).reduce((s, x) => s + x.reward, 0);
  const hon = rows.find(x => x.user.startsWith("Honest")).reward;
  console.log(`\nSybil check: honest got ${hon}, attacker (4 accts, same 1000 total) got ${atkTotal}  -> x${(atkTotal / hon).toFixed(2)}`);

  const gasRows = Object.entries(gas).map(([fn, a]) => ({
    function: fn, calls: a.length,
    avgGas: Math.round(a.reduce((x, y) => x + y, 0) / a.length), maxGas: Math.max(...a) }));
  console.log("\n=== Gas usage ===");
  console.table(gasRows);

  fs.writeFileSync(`fairness_results_${NAME}.csv`,
    "scenario,epoch,user,contributed,rawSharePct,reward\n" +
    rows.map(x => Object.values(x).join(",")).join("\n"));
  fs.writeFileSync(`gas_results_${NAME}.csv`,
    "function,calls,avgGas,maxGas\n" + gasRows.map(x => Object.values(x).join(",")).join("\n"));
  console.log(`\nSaved: fairness_results_${NAME}.csv, gas_results_${NAME}.csv`);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
