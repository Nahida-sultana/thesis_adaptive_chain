// V4 checks. Run: npx hardhat run scripts/v4_checks.js
const { ethers } = require("hardhat");
const E = (n) => ethers.parseEther(String(n));
const F = (n) => Number(ethers.formatEther(n));
const NAME = "FairMetaChainV4";

async function deploy() {
  const signers = await ethers.getSigners();
  const token = await (await ethers.getContractFactory("MockRewardToken")).deploy();
  const fmc = await (await ethers.getContractFactory(NAME)).deploy(await token.getAddress());
  const addr = await fmc.getAddress();
  await (await fmc.createShard(1200)).wait();
  await (await token.approve(addr, E(10000))).wait();
  await (await fmc.depositReward(0, E(10000))).wait();
  for (const u of signers.slice(1, 12)) await (await token.transfer(u.address, E(1000))).wait();
  return { signers, token, fmc, addr };
}
const warp = async (sec) => { await ethers.provider.send("evm_increaseTime", [sec]); await ethers.provider.send("evm_mine", []); };
const reverts = async (p) => { try { await p; return "NO (did not revert)"; } catch (e) { const m = /reason string '([^']+)'/.exec(e.message || ""); return "reverted: " + (m ? m[1] : (e.reason || e.shortMessage || "error")); } };

// ---- 1. Sybil in default (permissionless) mode ----
async function sybilRun(joinAt, split) {
  const { signers, token, fmc, addr } = await deploy();
  const honest = signers[1], atk = signers.slice(2, 2 + split), per = 1000 / split;
  const contrib = async (u, amt) => { await (await token.connect(u).approve(addr, E(200))).wait(); await (await fmc.connect(u).contribute(0, E(amt), E(5))).wait(); };
  let nC = 0;
  for (let ep = 1; ep <= 4; ep++) {
    await contrib(honest, 1000);
    if (ep >= joinAt) for (const a of atk) { await contrib(a, per); nC++; }
    await (await fmc.forceAdvanceEpoch()).wait();
  }
  let reward = 0;
  for (const a of atk) for (let ep = joinAt; ep <= 4; ep++) {
    const b = await token.balanceOf(a.address);
    await (await fmc.connect(a).claimReward(ep, 0)).wait();
    reward += F((await token.balanceOf(a.address)) - b);
  }
  return reward - atk.length * 5 - nC * 0.1;
}

async function main() {
  console.log("=== 1. Permissionless mode (default): cap forced to 100% ===");
  const rows = [];
  for (const joinAt of [4, 1]) {
    const one = await sybilRun(joinAt, 1), four = await sybilRun(joinAt, 4);
    rows.push({ attackerJoins: `epoch ${joinAt}`, net1acct: +one.toFixed(2), net4acct: +four.toFixed(2), splitProfit: +(four - one).toFixed(2), sybilProfitable: four > one ? "YES" : "no" });
  }
  console.table(rows);

  console.log("\n=== 2. Permissioned mode (timelocked switch): cap 35% active, registry gates accounts ===");
  {
    const { signers, token, fmc, addr } = await deploy();
    console.log("cap before switch (effective bps):", Number(await fmc.effectiveCapBps()));
    await (await fmc.proposeParams(3500, 2000, 2000, E(5), 2000, E(10), true)).wait();
    console.log("execute too early      :", await reverts(fmc.executeParams()));
    await warp(24 * 3600 + 5);
    await (await fmc.executeParams()).wait();
    console.log("cap after timelock (bps):", Number(await fmc.effectiveCapBps()));
    const us = signers.slice(1, 5), amts = [50, 200, 500, 1000];
    await (await fmc.register(us.map((u) => u.address), true)).wait();
    for (let i = 0; i < 4; i++) {
      await (await token.connect(us[i]).approve(addr, E(200))).wait();
      await (await fmc.connect(us[i]).contribute(0, E(amts[i]), E(5))).wait();
    }
    await (await token.connect(signers[6]).approve(addr, E(200))).wait();
    console.log("unregistered account   :", await reverts(fmc.connect(signers[6]).contribute(0, E(100), E(5))));
    await (await fmc.forceAdvanceEpoch()).wait();
    const budget = F(await fmc.epochBudget(1, 0)); const out = [];
    for (let i = 0; i < 4; i++) {
      const b = await token.balanceOf(us[i].address);
      await (await fmc.connect(us[i]).claimReward(1, 0)).wait();
      out.push(F((await token.balanceOf(us[i].address)) - b));
    }
    const paid = out.reduce((a, b) => a + b, 0);
    console.table(us.map((_, i) => ({ user: "U" + (i + 1), contributed: amts[i], reward: +out[i].toFixed(3), pctOfBudget: +(out[i] / budget * 100).toFixed(2), shareOfPaid: +(out[i] / paid * 100).toFixed(1) })));
  }

  console.log("\n=== 3. Governance / centralization controls ===");
  {
    const { signers, fmc } = await deploy();
    console.log("advanceEpoch too early (anyone):", await reverts(fmc.connect(signers[5]).advanceEpoch()));
    await warp(3600 + 5);
    await (await fmc.connect(signers[5]).advanceEpoch()).wait();
    console.log("advanceEpoch after 1h (non-owner): OK, epoch =", Number(await fmc.currentEpoch()));
    await (await fmc.disableForceAdvance()).wait();
    console.log("forceAdvanceEpoch after disable:", await reverts(fmc.forceAdvanceEpoch()));
    await (await fmc.lockParams()).wait();
    console.log("propose after lockParams       :", await reverts(fmc.proposeParams(3500, 2000, 2000, E(5), 2000, E(10), true)));
    console.log("non-owner propose              :", await reverts(fmc.connect(signers[5]).proposeParams(10000, 0, 0, 0, 0, 0, false)));
  }
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
