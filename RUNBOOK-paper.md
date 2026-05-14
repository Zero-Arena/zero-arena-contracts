# Runbook — bring the paper trading arena online

Step-by-step to flip RFC-001 from "compiled, tested" to "real agents
trading on Galileo and committing on chain." Run from
`zero-arena-contracts/` unless noted.

Prerequisites:

- `foundry` installed (`brew install foundry` on macOS)
- Two funded Galileo wallets:
  - **Wallet A (admin/deployer)** — deploys contracts, creates seasons.
    Holds `DEPLOYER_PRIVATE_KEY`.
  - **Operator wallet** — the backend daemon's wallet. Authorized in
    `LiveCertificate.authorizedUpdaters`. Needs Galileo gas. May be the
    same address as Wallet A (default v0.2 deployment uses Wallet A).
- v0.2 deployment already lives in `deployments/galileo-testnet.json`
  and `deployments/galileo-paper-engine.json`.

---

## 1. Deploy LiveCertificate + Season

```bash
export GALILEO_RPC_URL=https://evmrpc-testnet.0g.ai
export DEPLOYER_PRIVATE_KEY=0x...        # Wallet A
export DEPLOYER_ADDRESS=0x...
export OPERATOR_ADDRESS=0x...            # paper-engine updater wallet
export ZA_ADDR_INFT=0xF7162ecbdB11DE4704043D4aF93B4030AD61700e

forge script script/DeployPaperEngine.s.sol:DeployPaperEngine \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast --legacy --with-gas-price 3000000000
```

Output: `deployments/galileo-paper-engine.json` with
`LiveCertificate` + `Season` addresses. Note them — you'll set them as
env vars in the BE + FE.

(Optional) Verify the source:

```bash
forge verify-contract \
  --chain-id 16602 \
  --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom \
  --verifier-url https://chainscan-galileo.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS $ZA_ADDR_INFT) \
  <LiveCertificateAddress> \
  src/LiveCertificate.sol:LiveCertificate
```

Same pattern for Season (constructor takes `(address admin, address liveAddr, address inftAddr)`).

---

## 2. Create the first season

```bash
export ZA_ADDR_SEASON=0x...                   # from step 1 output
export SEASON_PRIZE_WEI=100000000000000000    # 0.1 0G
export SEASON_START_OFFSET=600                # enrollment closes in 10 min
export SEASON_DURATION=2592000                # 30 days
export SEASON_MARKET=0                        # 0=spot, 1=perp

forge script script/CreatePaperSeason.s.sol:CreatePaperSeason \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast --legacy --with-gas-price 3000000000
```

Output prints the `Season id` — note it for step 3.

---

## 3. Enroll an iNFT and start its paper run

Run this as the iNFT **owner** (not the deployer, unless they're the same wallet).

```bash
export ZA_ADDR_CERT=0x77f29d2a7BcAC679812d9a0FB1c7508eDA6B087e
export ZA_ADDR_LIVE_CERT=0x2c71fe022E4698f8fD63384A19Cd69D72a714b4d
export ZA_ADDR_SEASON=0x8fb87CE34b4e8F4C65eeB6752b0168EC37806CF3
export PAPER_TOKEN_ID=1                       # iNFT to compete with
export PAPER_CERT_ID=1                        # its underlying cert
export PAPER_SEASON_ID=1                      # season from step 2
export OWNER_PRIVATE_KEY=0x...

forge script script/StartPaperRun.s.sol:StartPaperRun \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $OWNER_PRIVATE_KEY \
  --broadcast --legacy --with-gas-price 3000000000
```

This does two writes in one broadcast: `Season.enroll(seasonId, tokenId)` then `LiveCertificate.start(tokenId, runHash)`. Repeat for every iNFT you want competing.

---

## 4. Wire the BE env + start the daemon

In `zero-arena-bacend/.env`:

```ini
# v0.2 dataset + oracle (existing)
ZA_RPC=https://evmrpc-testnet.0g.ai
ZA_INDEXER=https://indexer-storage-testnet-turbo.0g.ai
OPERATOR_PRIVATE_KEY=0x...                    # paper-engine updater wallet
ZA_ADDR_CERT=0x77f29d2a7BcAC679812d9a0FB1c7508eDA6B087e
ZA_ADDR_INFT=0xF7162ecbdB11DE4704043D4aF93B4030AD61700e
ZA_ADDR_ORACLE=0x733667CEBB27e310a8fb60799Af73A8C1fe501b2

# v0.3 paper engine
ZA_ADDR_LIVE_CERT=0x2c71fe022E4698f8fD63384A19Cd69D72a714b4d
PAPER_TOKEN_ID=1                              # which iNFT this daemon drives
PAPER_AGENT_MODULE=/abs/path/to/agent.ts      # default-exports your Agent
PAPER_GENESIS_HASH=0x...                      # this iNFT's static-cert runHash
PAPER_SYMBOL=btcusdt
PAPER_INTERVAL=15m
PAPER_MARKET=spot
PAPER_BARS_PER_EPOCH=96                       # 96 = 24h at 15m
                                              # use 4 for a faster demo cadence
PAPER_DRY_RUN=false                           # commit on-chain
```

Then from `zero-arena-bacend/`:

### 4a. Demo path — backfill last 7 days, fast

```bash
PAPER_BACKFILL_DAYS=7 PAPER_BARS_PER_EPOCH=4 \
  npm run paper -- backfill   # commits ~4 epochs per simulated day = ~28 epochs in seconds
```

Each epoch fires a real `LiveCertificate.update()` transaction on
Galileo. The FE leaderboard refreshes once a minute and picks up the
new state automatically.

### 4b. Live path — subscribe to Binance WS, run 24/7

```bash
npm run paper -- start
```

Process keeps running. One epoch per `barsPerEpoch * intervalMinutes`
(default = 24 hours). Manage with systemd / pm2 / tmux for survivability.

`npm run paper` is shorthand for `tsx src/index.ts paper`. Add it as a
real script in `zero-arena-bacend/package.json` if you haven't yet.

---

## 5. Update the FE env

In `zero-arena-fe/.env.local`:

```ini
NEXT_PUBLIC_LIVE_CERTIFICATE_ADDRESS=0x...    # from step 1
NEXT_PUBLIC_SEASON_ADDRESS=0x...              # from step 1
```

Restart `pnpm dev`. The amber **Demo data** pills go away; the
**Galileo live** badges turn on. `/season`, `/season/1`, and
`/agent/<slug>/live` now read directly from chain.

---

## 6. Watch it tick

- `https://chainscan-galileo.0g.ai/address/<LiveCertificateAddress>` — see
  every `EpochCommitted` event land.
- `localhost:3000/season/1` — leaderboard reorders each time the FE
  refreshes its 60-second cache.
- `localhost:3000/agent/cert-1/live` — per-agent dashboard updates the
  cumulative hash + live metrics.

If anything is wrong:

- **`EpochOutOfOrder(expected: 0, got: 5)`** — operator is committing
  with a stale `epochIndex`. The runner expects the on-chain
  `epochCount` and the local snapshot to agree. Delete the snapshot file
  and resume from the genesis state if state drift is suspected.
- **`UnauthorizedUpdater`** — Wallet B is not in `setUpdater`. Re-run
  step 1's setUpdater call from admin: `live.setUpdater(operator, true)`.
- **`NotStarted`** — operator is committing for a tokenId that hasn't
  called `LiveCertificate.start()` yet. Re-run step 3.

---

## v0.4 swap-in

The interfaces above stay stable when v0.4 introduces TEE-attested
updates: `submitEpochOnChain` keeps the same shape, but the
`OPERATOR_PRIVATE_KEY` is replaced by a 0G Compute Sealed Inference
quote that LiveCertificate validates on-chain. No FE / runbook changes.
