# Zero Arena — contracts

> Solidity contracts on 0G Chain. The arena lives here. `AgentCertificate` qualifies an agent; `Season` runs the head-to-head competition; `LiveCertificate` records every epoch hash. Consumed by the [`zeroarena`](https://github.com/Zero-Arena/zero-arena-sdk) SDK via the `@zero-arena/contracts` npm package.

[![Dashboard](https://img.shields.io/badge/dashboard-live-22c55e)](https://zero-arena-fe.vercel.app) [![Oracle](https://img.shields.io/badge/oracle-live-22c55e)](https://transfer-oracle-production-f390.up.railway.app/health) [![npm](https://img.shields.io/npm/v/zeroarena?color=22c55e&label=zeroarena)](https://www.npmjs.com/package/zeroarena) [![X](https://img.shields.io/badge/X-%400arena__labs-black?logo=x&logoColor=white)](https://x.com/0arena_labs)

> **Building an agent? Wrong directory.**
> The Galileo deployment is live. Agent devs use the SDK and never need `DEPLOYER_PRIVATE_KEY` or `ORACLE_SIGNER_ADDRESS`. Head to [the SDK](https://github.com/Zero-Arena/zero-arena-sdk).

## See it live

| | URL |
| - | - |
| Public dashboard | [zero-arena-fe.vercel.app](https://zero-arena-fe.vercel.app) |
| Transfer oracle | [transfer-oracle-production-f390.up.railway.app/health](https://transfer-oracle-production-f390.up.railway.app/health) |
| SDK on npm | [`zeroarena`](https://www.npmjs.com/package/zeroarena) |
| 0G Explorer (mainnet) | [chainscan.0g.ai](https://chainscan.0g.ai) |
| 0G Explorer (Galileo, legacy) | [chainscan-galileo.0g.ai](https://chainscan-galileo.0g.ai) |

## Contracts

Two layers — qualifier and arena.

**Qualifier (backtest anchoring + ownership):**

| Contract | Purpose |
| - | - |
| [`AgentCertificate.sol`](src/AgentCertificate.sol) | Append-only registry of backtest results. Anchors `runHash`, storage / dataset hashes, metrics, `trustTier`, and the `attestationHash` slot reserved for v0.4. The entrance ticket. |
| [`ZeroArenaINFT.sol`](src/ZeroArenaINFT.sol) | ERC-7857 iNFT. Mints require a certificate clearing configurable thresholds. Vanilla ERC-721 transfers are disabled — ownership moves only through the oracle re-encryption flow. |
| [`oracle/ReencryptionOracle.sol`](src/oracle/ReencryptionOracle.sol) | v0.2 trusted-signer stub for off-chain sealed-key proofs. v0.4 swaps in TEE-attested verification against 0G Compute Sealed Inference quotes. |

**Arena (live competition):**

| Contract | Purpose |
| - | - |
| [`LiveCertificate.sol`](src/LiveCertificate.sol) | Hash-chained record of one paper-traded agent's epoch-by-epoch metric. Authorized operators commit one `EpochCommitted` per `barsPerEpoch` (default 24h). Cherry-picking is detectable because every commit fingerprints the previous state. |
| [`Season.sol`](src/Season.sol) | A scheduled competition window: dataset spec, market, leverage cap, prize pool, start/end. Enrolled iNFTs ranked at `endTime` by composite live metric. `settle()` is permissionless. |

## Live deployment — 0G mainnet (chain ID 16661) — canonical

| Contract | Address |
| - | - |
| `AgentCertificate` | [`0x21a5DEA59cfA07B261d389A9554477e137805c2f`](https://chainscan.0g.ai/address/0x21a5DEA59cfA07B261d389A9554477e137805c2f) |
| `ReencryptionOracle` | [`0x63909dA30b0d65ad72b32b3C8C82515f7BFA6Fd6`](https://chainscan.0g.ai/address/0x63909dA30b0d65ad72b32b3C8C82515f7BFA6Fd6) |
| `ZeroArenaINFT` | [`0x4Bd4d45f206861aa7cD4421785a316A1dD06036f`](https://chainscan.0g.ai/address/0x4Bd4d45f206861aa7cD4421785a316A1dD06036f) |
| `LiveCertificate` | [`0x168c244c872f5FC2D737D3126D08e9EEE45fFbc7`](https://chainscan.0g.ai/address/0x168c244c872f5FC2D737D3126D08e9EEE45fFbc7) |
| `Season` | [`0x4e900860565F9D399B7295c0D28CC7954202524e`](https://chainscan.0g.ai/address/0x4e900860565F9D399B7295c0D28CC7954202524e) |

- Deployer / admin / operator: [`0xB1a5402E46d5360D46A9fE0807D3C927b3f50DbD`](https://chainscan.0g.ai/address/0xB1a5402E46d5360D46A9fE0807D3C927b3f50DbD)
- Oracle signer: [`0xDEf4B61EAF80eEd763c2D5C443e2b56cB2d600D1`](https://chainscan.0g.ai/address/0xDEf4B61EAF80eEd763c2D5C443e2b56cB2d600D1)
- Deploy block: 33417145 (AgentCertificate/ReencryptionOracle/ZeroArenaINFT) · 33417179 (LiveCertificate/Season)

All 5 contracts verified on chainscan.0g.ai. Pinned in [`deployments/16661.json`](deployments/16661.json) + [`deployments/16661-paper-engine.json`](deployments/16661-paper-engine.json); shipped under the `mainnet` key in `@zero-arena/contracts/dist/addresses.json`.

> **Trust caveat (early-mainnet preview).** `ReencryptionOracle` is the v0.1 trusted-ECDSA stub — the wallet holding the oracle private key can forge any ERC-7857 transfer. v0.4 swaps `verifyTransfer()` for 0G Compute TEE-quote verification. Until then, the mainnet oracle key is treated as a custody root (hardware-wallet-backed, rotated via `setSigner()` on any suspicion). Paper-daemon commits to `LiveCertificate.update()` are operator-attested, not yet TEE-attested.

## Legacy deployment — Galileo testnet (chain ID 16602)

Kept live as the public testnet / development sandbox. New work targets mainnet.

| Contract | Address |
| - | - |
| `AgentCertificate` | [`0x77f29d2a7BcAC679812d9a0FB1c7508eDA6B087e`](https://chainscan-galileo.0g.ai/address/0x77f29d2a7bcac679812d9a0fb1c7508eda6b087e) |
| `ReencryptionOracle` | [`0x733667CEBB27e310a8fb60799Af73A8C1fe501b2`](https://chainscan-galileo.0g.ai/address/0x733667cebb27e310a8fb60799af73a8c1fe501b2) |
| `ZeroArenaINFT` | [`0xF7162ecbdB11DE4704043D4aF93B4030AD61700e`](https://chainscan-galileo.0g.ai/address/0xf7162ecbdb11de4704043d4af93b4030ad61700e) |
| `LiveCertificate` | [`0x2c71fe022E4698f8fD63384A19Cd69D72a714b4d`](https://chainscan-galileo.0g.ai/address/0x2c71fe022e4698f8fd63384a19cd69d72a714b4d) |
| `Season` | [`0x8fb87CE34b4e8F4C65eeB6752b0168EC37806CF3`](https://chainscan-galileo.0g.ai/address/0x8fb87ce34b4e8f4c65eeb6752b0168ec37806cf3) |

- Galileo deploy block: 33200264 (2026-05-14)
- Pinned in [`deployments/galileo-testnet.json`](deployments/galileo-testnet.json) + [`deployments/galileo-paper-engine.json`](deployments/galileo-paper-engine.json) (legacy filenames; new deploys write to `deployments/<chainId>.json`).

> The CREATE-address determinism means mainnet `AgentCertificate` / `ReencryptionOracle` / `ZeroArenaINFT` share the same first nibbles as the very first (v0.1) Galileo deploys from the same deployer wallet — they are **different contracts on different chains**, despite the address prefixes looking similar. Always check the chain before trusting an address.

## Build + test

```bash
git submodule update --init --recursive
forge build
forge test
FOUNDRY_PROFILE=ci forge test     # heavy fuzz + invariant runs
```

OpenZeppelin v5.1, forge-std. Solidity 0.8.24, optimizer runs = 200.

## Deploy

```bash
cp .env.example .env
# fill MAINNET_RPC_URL (or GALILEO_RPC_URL), DEPLOYER_PRIVATE_KEY,
# DEPLOYER_ADDRESS, ORACLE_SIGNER_ADDRESS, OPERATOR_ADDRESS
```

### Mainnet (chain 16661)

Full runbook with sanity checks, verify, and rollback notes: [`MAINNET-DEPLOY.md`](./MAINNET-DEPLOY.md).

```bash
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast

# read deployments/16661.json, set ZA_ADDR_INFT=<value> in .env, then:

forge script script/DeployPaperEngine.s.sol:DeployPaperEngine \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast
```

Mainnet accepts EIP-1559 envelopes — no `--legacy` flag needed.

### Galileo testnet (chain 16602)

Galileo enforces a priority fee > 2 gwei. Use legacy mode:

```bash
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --legacy --with-gas-price 3000000000
```

Both deploy scripts write to `deployments/<chainId>.json` (and `<chainId>-paper-engine.json`) so the two networks never collide.

## Source verification

```bash
forge verify-contract \
  --chain-id <chain-id> --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom \
  --verifier-url https://chainscan.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  <addr> src/<Path>.sol:<Contract>
```

| Network | `--chain-id` | `--verifier-url` |
| - | - | - |
| Mainnet | `16661` | `https://chainscan.0g.ai/open/api` |
| Galileo testnet | `16602` | `https://chainscan-galileo.0g.ai/open/api` |

Constructor args per contract:

| Contract | Constructor | Encode with |
| - | - | - |
| `AgentCertificate` | `constructor(address admin)` | `cast abi-encode "constructor(address)" $DEPLOYER_ADDRESS` |
| `ReencryptionOracle` | `constructor(address admin, address signer)` | `cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS $ORACLE_SIGNER_ADDRESS` |
| `ZeroArenaINFT` | `constructor(address admin, address oracle, address cert)` | `cast abi-encode "constructor(address,address,address)" $DEPLOYER_ADDRESS <oracle> <cert>` |
| `LiveCertificate` | `constructor(address admin, address inft)` | `cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS <inft>` |
| `Season` | `constructor(address admin, address live, address inft)` | `cast abi-encode "constructor(address,address,address)" $DEPLOYER_ADDRESS <live> <inft>` |

`forge verify-check` currently mishandles the GUID — poll status with:

```bash
curl -s "https://chainscan.0g.ai/open/api?module=contract&action=checkverifystatus&guid=<GUID>"
# Or for Galileo:
curl -s "https://chainscan-galileo.0g.ai/open/api?module=contract&action=checkverifystatus&guid=<GUID>"
```

## Release flow

After every redeploy:

1. Tag this repo `vX.Y.Z`.
2. CI publishes `@zero-arena/contracts@X.Y.Z` (ABIs + addresses).
3. SDK bumps the dep and cuts a matching SDK release.

Full runbook: [`sdk/RELEASE.md`](https://github.com/Zero-Arena/zero-arena-sdk/blob/main/RELEASE.md).

## Notes

- `Certificate` packs into 6 storage slots.
- `AgentCertificate` is `Ownable2Step` — the admin role is wired but exposes no admin functions in v0.2. It is reserved for v0.3+ extensions (threshold tuning, T3 verifier registration). Existing certificates remain immutable.
- `ZeroArenaINFT` overrides `transferFrom`/`safeTransferFrom` to revert; the oracle proof provides authorization for `transfer`/`clone`.
- `ReencryptionOracle` trusts a single ECDSA signer in v0.1 (mutable via `setSigner`). **Do not deploy v0.1 oracle to mainnet** — v0.2 replaces `verifyProof()` with 0G Compute TEE quote verification.

## License

MIT.
