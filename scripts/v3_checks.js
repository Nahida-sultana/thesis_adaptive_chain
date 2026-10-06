// V3 checks: (1) alpha-driven budget, (2) Sybil net gain under different configs.
// Run: npx hardhat run scripts/v3_checks.js
const { ethers } = require("hardhat");
const E = (n) => ethers.parseEther(String(n));
const F = (n) => Number(ethers.formatEther(n));

async function deploy(name, alphas = [1200]) {
  const signers = await ethers.getSigners();
  const token = await (await ethers.getContractFactory("MockRewardToken")).deploy();
  const fmc = await (await ethers.getContractFactory(name)).deploy(await token.getAddress());
  const addr = await fmc.getAddress();
  for (const a of alphas) await (await fmc.createShard(a)).wait();
  await (await token.approve(addr, E(10000 * alphas.length))).wait();
  for (let i = 0; i < alphas.length; i++) await (await fmc.depositReward(i, E(10000))).wait();
  for (const u of signers.slice(1, 12)) await (await token.transfer(u.address, E(1000))).wait();
  return { signers, token, fmc, addr };
}

async function alphaBudget() {
  const { signers, token, fmc, addr } = await deploy("FairMetaChainV3", [1200, 1800, 1500]);
  const u = signers[1];
  await (await token.connect(u).approve(addr, E(100))).wait();
  for (let s = 0; s < 3; s++) await (await fmc.connect(u).contribute(s, E(50), E(5))).wait();
  await (await fmc.forceAdvanceEpoch()).wait();
  console.log("=== 1. alpha-driven epoch budget (budget = alpha * 10 / 100) ===");
  for (let s = 0; s < 3; s++) console.log(`shard ${s}: alpha ${(await fmc.shards(s)).alpha}  budget ${F(await fmc.epochBudget(1, s))}`);
}

// attacker joins at epoch `joinAt`, runs through epoch 4. split = 1 account (single) or 4 accounts.
async function run(name, { cap, fee, joinAt, split }) {
  const { signers, token, fmc, addr } = await deploy(name);
  if (cap !== undefined) await (await fmc.setParams(cap, name === "FairMetaChainV3" ? 2000 : 4500, 2000)).wait();
  if (fee !== undefined && name === "FairMetaChainV3") await (await fmc.setSybilParams(E(fee), 2000, E(10))).wait();
  const honest = signers[1];
  const atk = signers.slice(2, 2 + split);
  const per = 1000 / split;
  const contrib = async (u, amt) => {
    await (await token.connect(u).approve(addr, E(200))).wait();
    await (await fmc.connect(u).contribute(0, E(amt), E(5))).wait();
  };
  let nContrib = 0;
  for (let ep = 1; ep <= 4; ep++) {
    await contrib(honest, 1000);
    if (ep >= joinAt) for (const a of atk) { await contrib(a, per); nContrib++; }
    await (await fmc.forceAdvanceEpoch()).wait();
  }
  let reward = 0;
  for (const a of atk) for (let ep = joinAt; ep <= 4; ep++) {
    const b = await token.balanceOf(a.address);
    await (await fmc.connect(a).claimReward(ep, 0)).wait();
    reward += F((await token.balanceOf(a.address)) - b);
  }
  const feePaid = name === "FairMetaChainV3" ? atk.length * (fee ?? 5) : 0;
  const gasPaid = nContrib * 0.1;
  return reward - feePaid - gasPaid;
}

async function sybil() {
  console.log("\n=== 2. Sybil: net profit of splitting into 4 accounts minus net profit with 1 account (tokens, 4 epochs) ===");
  const rows = [];
  const cfgs = [
    ["V2 (cap 35%)",                   "FairMetaChainV2", {}],
    ["V3 (cap 35%, fee 5, warm-up)",   "FairMetaChainV3", { fee: 5 }],
    ["V3 (cap 35%, fee 40, warm-up)",  "FairMetaChainV3", { fee: 40 }],
    ["V3 (cap 100% = pay-per-share)",  "FairMetaChainV3", { cap: 10000, fee: 0 }],
  ];
  for (const [label, name, o] of cfgs) for (const joinAt of [4, 1]) {
    const one = await run(name, { ...o, joinAt, split: 1 });
    const four = await run(name, { ...o, joinAt, split: 4 });
    rows.push({ config: label, attackerJoins: `epoch ${joinAt}`, net1acct: +one.toFixed(2), net4acct: +four.toFixed(2), splitProfit: +(four - one).toFixed(2), sybilProfitable: four > one ? 'YES' : 'no' });
  }
  console.table(rows);
}

(async () => { await alphaBudget(); await sybil(); })().catch((e) => { console.error(e); process.exitCode = 1; });
