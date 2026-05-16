# Mainnet deploy runbook

Step-by-step deploy of all 5 Zero Arena contracts to **0G mainnet (chainId 16661)**. Read end-to-end before running anything. Every `forge script … --broadcast` line spends real 0G.

> **Trust caveat — read this before deploying.** v0.1 oracle is a trusted-ECDSA stub. The wallet holding `ORACLE_PRIVATE_KEY` can forge any ERC-7857 transfer and steal any minted iNFT. v0.4 swaps it for 0G Compute TEE attestation. Until then, treat the mainnet oracle key like a custody root: hardware wallet, never on a dev laptop, rotate via `setSigner()` on any suspicion of compromise.

---

## 0. Network specs (reference)

| | Mainnet | Galileo (deprecated) |
| - | - | - |
| Chain name | 0G Mainnet | 0G Galileo |
| chainId | **16661** | 16602 |
| RPC | `https://evmrpc.0g.ai` | `https://evmrpc-testnet.0g.ai` |
| Storage indexer | `https://indexer-storage-turbo.0g.ai` | `https://indexer-storage-testnet-turbo.0g.ai` |
| Explorer | `https://chainscan.0g.ai` | `https://chainscan-galileo.0g.ai` |
| Faucet | — (real 0G needed) | `https://faucet.0g.ai` |
| Gas tip | (try default; fallback `--legacy --with-gas-price <wei>` if rejected) | `>2 gwei` required (use `--legacy --with-gas-price 3000000000`) |

## 1. Wallets you need

Three separate addresses. **Do NOT reuse Galileo deployer key.**

| Wallet | Role | Funding needed |
| - | - | - |
| DEPLOYER | Admin (Ownable2Step) on every contract | enough 0G for ~5 deploys + future admin tx |
| ORACLE_SIGNER | Address written into `ReencryptionOracle` at construction; signs transfer proofs off-chain | zero on-chain gas (signs off-chain). **Hardware wallet recommended.** |
| OPERATOR | Authorized updater in `LiveCertificate`; gas-payer for paper daemon + season-keeper | ongoing — every `EpochCommitted` + `Season.settle` |

Generate with `cast wallet new` if you don't have them yet:

```bash
cast wallet new       # repeat 3×, record address + private key per wallet
```

Fund the DEPLOYER wallet via whichever 0G mainnet on-ramp you have access to before broadcasting.

## 2. Fill `contracts/.env`

```bash
cp .env.example .env
```

Set in `.env`:

```ini
DEPLOYER_PRIVATE_KEY=0x<deployer-key>
DEPLOYER_ADDRESS=0x<deployer-address>     # must == `cast wallet address $DEPLOYER_PRIVATE_KEY`
ORACLE_SIGNER_ADDRESS=0x<oracle-address>
OPERATOR_ADDRESS=0x<operator-address>
# ZA_ADDR_INFT will be filled AFTER step 4
```

Sanity check:

```bash
cast wallet address $(grep '^DEPLOYER_PRIVATE_KEY=' .env | cut -d= -f2)
# → must match DEPLOYER_ADDRESS in the .env

cast balance --rpc-url https://evmrpc.0g.ai $DEPLOYER_ADDRESS
# → must be > 0
```

## 3. Build + test

```bash
forge build
forge test                          # full suite
FOUNDRY_PROFILE=ci forge test       # heavy fuzz, optional
```

All tests must pass before you broadcast anything.

## 4. Deploy qualifier layer (AgentCertificate + ReencryptionOracle + ZeroArenaINFT)

```bash
source .env

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast
```

Notes:

- **No `--legacy --with-gas-price`** by default — try without first. Mainnet should accept EIP-1559 envelopes. If you see `intrinsic gas too low` or `tip too low`, retry with `--legacy --with-gas-price <higher-wei>` (start at `100000000` = 0.1 gwei and bump).
- Script writes `deployments/16661.json` on success.
- Console output prints each address; capture them.

After this step:

```bash
cat deployments/16661.json
# → { "chainId": 16661, "addresses": { "AgentCertificate": "0x…", "ReencryptionOracle": "0x…", "ZeroArenaINFT": "0x…" }, "deployBlock": <n> }
```

Append `ZA_ADDR_INFT=0x<ZeroArenaINFT-from-above>` to `.env`.

## 5. Deploy arena layer (LiveCertificate + Season + authorize operator)

```bash
source .env

forge script script/DeployPaperEngine.s.sol:DeployPaperEngine \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast
```

Script:

1. Deploys `LiveCertificate(admin, ZA_ADDR_INFT)`.
2. Calls `live.setUpdater(OPERATOR_ADDRESS, true)` — authorizes the operator wallet globally.
3. Deploys `Season(admin, address(live), ZA_ADDR_INFT)`.
4. Writes `deployments/16661-paper-engine.json`.

## 6. Rebuild + republish `@zero-arena/contracts`

```bash
npm run build:abi
# → dist/addresses.json now has both "galileo" and "mainnet" entries
cat dist/addresses.json
```

When ready to publish:

```bash
npm version patch                   # 0.2.0 → 0.2.1 (or minor for the network add)
npm publish --access public
```

SDK and FE will pick up the new mainnet entry on their next package bump.

## 7. Verify contracts on chainscan.0g.ai

For each contract, in sequence:

```bash
# AgentCertificate(address admin)
forge verify-contract \
  --chain-id 16661 --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom \
  --verifier-url https://chainscan.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address)" $DEPLOYER_ADDRESS) \
  <AgentCertificate-addr> src/AgentCertificate.sol:AgentCertificate

# ReencryptionOracle(address admin, address signer)
forge verify-contract \
  --chain-id 16661 --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom --verifier-url https://chainscan.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS $ORACLE_SIGNER_ADDRESS) \
  <ReencryptionOracle-addr> src/oracle/ReencryptionOracle.sol:ReencryptionOracle

# ZeroArenaINFT(address admin, address oracle, address cert)
forge verify-contract \
  --chain-id 16661 --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom --verifier-url https://chainscan.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $DEPLOYER_ADDRESS <oracle-addr> <cert-addr>) \
  <ZeroArenaINFT-addr> src/ZeroArenaINFT.sol:ZeroArenaINFT

# LiveCertificate(address admin, address inft)
forge verify-contract \
  --chain-id 16661 --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom --verifier-url https://chainscan.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS <inft-addr>) \
  <LiveCertificate-addr> src/LiveCertificate.sol:LiveCertificate

# Season(address admin, address live, address inft)
forge verify-contract \
  --chain-id 16661 --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom --verifier-url https://chainscan.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $DEPLOYER_ADDRESS <live-addr> <inft-addr>) \
  <Season-addr> src/Season.sol:Season
```

Poll status (`forge verify-check` is flaky on 0G explorers):

```bash
curl -s "https://chainscan.0g.ai/open/api?module=contract&action=checkverifystatus&guid=<GUID>"
```

## 8. Sanity checks (read-only)

```bash
source .env

# AgentCertificate: nextCertId should be 1 (no certs yet)
cast call <AgentCertificate-addr> "nextCertId()(uint256)" --rpc-url $MAINNET_RPC_URL

# ZeroArenaINFT: thresholds match defaults (0 return, 1000 = 1.0 Sharpe)
cast call <ZeroArenaINFT-addr> "minTotalReturnBps()(int128)" --rpc-url $MAINNET_RPC_URL
cast call <ZeroArenaINFT-addr> "minSharpeX1000()(uint128)" --rpc-url $MAINNET_RPC_URL

# ReencryptionOracle: signer matches what you set
cast call <ReencryptionOracle-addr> "signer()(address)" --rpc-url $MAINNET_RPC_URL
# → must equal $ORACLE_SIGNER_ADDRESS

# LiveCertificate: operator is authorized
cast call <LiveCertificate-addr> "authorizedUpdaters(address)(bool)" $OPERATOR_ADDRESS --rpc-url $MAINNET_RPC_URL
# → true

# Season: nextSeasonId is 1, no seasons yet
cast call <Season-addr> "nextSeasonId()(uint256)" --rpc-url $MAINNET_RPC_URL
```

## 9. Out-of-scope for this runbook

The session that runs this runbook stops after step 8. The following come in follow-up sessions:

- Update SDK env defaults + init-wizard constants + dataset re-upload
- Update backend default RPC + drop Galileo gas-price override + rotate Railway env vars
- Update FE chain config + addresses + explorer URLs + redeploy Vercel
- Update examples + per-repo READMEs + `docs/*.md` + root `CLAUDE.md` + `README.md`
- Re-upload canonical OHLCV dataset to mainnet 0G Storage (`npx zeroarena dataset upload`)
- Create first mainnet Season (`forge script script/CreatePaperSeason.s.sol` with funded `SEASON_PRIZE_WEI`)
- Re-mint canonical agents on mainnet (`npm run multi:mint`)

---

## Rollback / recovery notes

| Failure mode | Recovery |
| - | - |
| Deploy tx reverts | Inspect `cast tx <hash>` output; fix env / constructor args; re-run script (deploy script is idempotent only in the sense that re-running deploys NEW contracts at NEW addresses — old failed deploys cost gas but produce no contract) |
| Wrong `ORACLE_SIGNER_ADDRESS` written into `ReencryptionOracle` | Admin calls `setSigner(newSigner)` from DEPLOYER wallet — same tx works on any chain |
| Wrong `OPERATOR_ADDRESS` authorized in `LiveCertificate` | Admin calls `setUpdater(oldOp, false)` then `setUpdater(newOp, true)` |
| Thresholds too tight (mint reverts with `ThresholdNotMet`) | Admin calls `ZeroArenaINFT.setThresholds(minReturn, minSharpe)` |
| Discovered bug post-deploy | Contracts are non-upgradeable. Redeploy fresh set, point SDK + FE + BE at the new addresses, communicate the migration. Existing iNFTs at the old addresses are orphaned (their cert points to the old `AgentCertificate`). |

## Trust posture (mainnet preview disclosure)

Until v0.4 ships:

- ERC-7857 transfers go through the trusted-ECDSA `ReencryptionOracle`. Audit the off-chain oracle service host and rotate the signer if anything looks off.
- Paper daemons in `LiveCertificate.update` are operator-attested or owner-attested. Neither is cheat-proof. Communicate this caveat on the dashboard and in marketing copy.
- Season prize pools hold real 0G. The admin (you) funds the pool; settlement is permissionless. Anyone can call `Season.settle` once `endTime` passes.
