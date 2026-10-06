# FairMetaChain Pilot (Testnet / Local)

Minimal on-chain pilot of the FairMetaChain framework.

## What is included

- `MockRewardToken` – simple ERC-20 used for rewards and gas payments
- `FairMetaChain` – core contract with:
  - Multiple shards
  - Reward pools (MSP deposits)
  - Per-shard gas prices + gas surcharge on contribute
  - Progressive rebate pool
  - Fair-share caps + reputation-weighted claims
  - Basic reputation update

## Quick Start (Local)

```bash
# 1. Install dependencies
npm install

# 2. Compile
npx hardhat compile

# 3. Start a local node (separate terminal)
npx hardhat node

# 4. Deploy (another terminal)
npx hardhat run scripts/deploy.js --network localhost

# 5. Interact (set the addresses printed by deploy)
# PowerShell:
$env:TOKEN_ADDRESS="0x..."
$env:FMC_ADDRESS="0x..."
npx hardhat run scripts/interact.js --network localhost
```

## Deploy to Sepolia (optional)

1. Create a free Alchemy/Infura Sepolia RPC URL
2. Get Sepolia ETH from a faucet
3. Uncomment the `sepolia` network in `hardhat.config.js`
4. Set environment variables:

```bash
export SEPOLIA_RPC_URL="https://..."
export PRIVATE_KEY="your_private_key"
npx hardhat run scripts/deploy.js --network sepolia
```

## Important Notes

- This is a **pilot / research prototype**. It is **not audited**.
- Do **not** put real money on it.
- Epoch advancement, full rebate distribution and reward-pool accounting are simplified for clarity.
- For a production system you would add: proper epoch snapshots, access control roles, pausing, formal verification, and a real contribution verification layer (TEE / zk / optimistic).

## Next engineering steps

1. Add proper epoch snapshots of `totalContributed`
2. Implement a fairer rebate distribution (Merkle claim or on-chain weighted)
3. Add a simple frontend (React + wagmi / viem)
4. Integrate an off-chain worker that reports real resource contributions
5. Move verification to TEEs or zk-SNARKs
