# Zero Arena — contracts

> Solidity contracts for the Zero Arena verifiable-trading-agent infrastructure on 0G Chain.

This repo holds the on-chain logic. The TypeScript SDK that consumes these contracts lives at [`Zero-Arena/zero-arena-sdk`](https://github.com/Zero-Arena/zero-arena-sdk).

## Contracts

| Contract | Purpose |
| - | - |
| [`AgentCertificate.sol`](src/AgentCertificate.sol) | Append-only registry of deterministic backtest results. Anchors `runHash`, `storageRootHash`, `datasetHash`, headline metrics, `trustTier` (T1/T2/T3) and the reserved `attestationHash` slot for v0.2 TEE attestation reports. |
| [`ZeroArenaINFT.sol`](src/ZeroArenaINFT.sol) | ERC-7857 Intelligent NFT for trading agents. Mints require a certificate that clears configurable thresholds. Vanilla ERC-721 transfers are disabled — ownership moves only through the oracle re-encryption flow. |
| [`oracle/ReencryptionOracle.sol`](src/oracle/ReencryptionOracle.sol) | v0.1 trusted-signer stub that verifies sealed-key proofs produced off-chain. v0.2 replaces this with TEE-attested verification against 0G Compute Sealed Inference quotes. |

## Trust model on-chain

Each `Certificate` carries a `trustTier` byte (`1=T1`, `2=T2`, `3=T3`) and an `attestationHash` field. v0.1 contracts accept submissions tagged T1 or T2 with `attestationHash = 0x0`. v0.2 contracts (no ABI break) will additionally accept T3 submissions whose `attestationHash` decodes to a valid 0G Compute Sealed Inference quote. The full tier table is in the [org README](https://github.com/Zero-Arena).

The ERC-7857 interface implemented here follows the [0G iNFT specification](https://docs.0g.ai/developer-hub/building-on-0g/inft/erc7857): `transfer`, `clone`, `authorizeUsage`, plus the `MetadataUpdated` / `UsageAuthorized` / `OracleUpdated` events.

## Toolchain

- **Foundry** — `forge` for build/test, `cast` for chain queries, `anvil` for local fork.
- **OpenZeppelin Contracts v5.1** — base `ERC721`, `Ownable2Step`, `ECDSA`. Pulled as a git submodule.
- **forge-std** — testing utilities.

No Hardhat, no JS test framework. The `package.json` at the repo root exists only to publish ABIs + addresses as `@zero-arena/contracts` to npm.

## Quick start

```bash
git submodule update --init --recursive
forge build
forge test
```

To run tests with the heavy fuzz/invariant profile:

```bash
FOUNDRY_PROFILE=ci forge test
```

## Live deployment — Galileo testnet (chain ID 16602)

| Contract | Address | Source |
| - | - | - |
| `AgentCertificate` | [`0x21a5DEA59cfA07B261d389A9554477e137805c2f`](https://chainscan-galileo.0g.ai/address/0x21a5dea59cfa07b261d389a9554477e137805c2f) | Verified ✓ |
| `ReencryptionOracle` | [`0x63909dA30b0d65ad72b32b3C8C82515f7BFA6Fd6`](https://chainscan-galileo.0g.ai/address/0x63909da30b0d65ad72b32b3c8c82515f7bfa6fd6) | Verified ✓ |
| `ZeroArenaINFT` | [`0x4Bd4d45f206861aa7cD4421785a316A1dD06036f`](https://chainscan-galileo.0g.ai/address/0x4bd4d45f206861aa7cd4421785a316a1dd06036f) | Verified ✓ |

- **Deployer / admin (Wallet A):** [`0xB1a5402E46d5360D46A9fE0807D3C927b3f50DbD`](https://chainscan-galileo.0g.ai/address/0xb1a5402e46d5360d46a9fe0807d3c927b3f50dbd) — `Ownable2Step` admin on `ReencryptionOracle` and `ZeroArenaINFT`.
- **Oracle signer (Wallet B):** [`0xDEf4B61EAF80eEd763c2D5C443e2b56cB2d600D1`](https://chainscan-galileo.0g.ai/address/0xdef4b61eaf80eed763c2d5c443e2b56cb2d600d1) — signs ERC-7857 re-encryption proofs off-chain. Read back from `ReencryptionOracle.signer()`.
- **Deploy block:** 32563974 / 32563975 (deploy date 2026-05-10).

These addresses are the canonical v0.1 testnet deployment. They're also written to [`deployments/galileo-testnet.json`](deployments/galileo-testnet.json) and shipped in `@zero-arena/contracts/dist/addresses.json`.

## Deploying your own copy

```bash
cp .env.example .env
# fill in GALILEO_RPC_URL, DEPLOYER_PRIVATE_KEY, DEPLOYER_ADDRESS, ORACLE_SIGNER_ADDRESS

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --legacy --with-gas-price 3000000000
```

Galileo enforces a strict-greater-than-2-gwei priority fee — Foundry's default tip cap is far below this, so `--legacy --with-gas-price 3000000000` (3 gwei) is required to avoid `transaction gas price below minimum`. The script writes addresses to `deployments/galileo-testnet.json`.

### Source verification

Galileo's explorer (chainscan) is a SPA — its public `/api` path returns 405 for `POST`. The actual Etherscan-compatible verifier endpoint sits at `/open/api`, with verifier type `custom` (NOT `blockscout`). The flow is per-contract:

```bash
# AgentCertificate — no constructor args
forge verify-contract \
  --chain-id 16602 \
  --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom \
  --verifier-url https://chainscan-galileo.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  0x21a5DEA59cfA07B261d389A9554477e137805c2f \
  src/AgentCertificate.sol:AgentCertificate

# ReencryptionOracle — (admin, signer)
forge verify-contract \
  --chain-id 16602 \
  --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom \
  --verifier-url https://chainscan-galileo.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS $ORACLE_SIGNER_ADDRESS) \
  <oracleAddress> \
  src/oracle/ReencryptionOracle.sol:ReencryptionOracle

# ZeroArenaINFT — (admin, oracleAddress, certificate)
forge verify-contract \
  --chain-id 16602 \
  --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom \
  --verifier-url https://chainscan-galileo.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $DEPLOYER_ADDRESS <oracleAddress> <certAddress>) \
  <inftAddress> \
  src/ZeroArenaINFT.sol:ZeroArenaINFT
```

Status check (avoid `forge verify-check` — it currently mis-handles the GUID; curl directly instead):

```bash
curl -s "https://chainscan-galileo.0g.ai/open/api?module=contract&action=checkverifystatus&guid=<GUID>"
# → {"status":"1","message":"OK","result":"Pass - Verified"}
```

## Cross-repo coupling

After every redeploy:

1. Tag this repo `vX.Y.Z`.
2. CI publishes `@zero-arena/contracts@X.Y.Z` to npm with ABIs + addresses.
3. SDK bumps the dep and cuts a matching SDK release.

The SDK never imports Solidity source — only ABIs and addresses. Contract refactors that don't change the public ABI don't require an SDK release.

## Gas + audit notes

- `Certificate` is packed into 5 storage slots (saves 3 SSTOREs vs. naive layout).
- `AgentCertificate` has no admin role and no upgrade path — submissions are immutable.
- `ZeroArenaINFT` overrides `transferFrom` and `safeTransferFrom` to revert. The `Approval` machinery is left in place so approved operators can call `transfer` / `clone` on behalf of the owner.
- `_update(to, tokenId, address(0))` is used inside `transfer` to bypass the standard ERC-721 auth check; authorization is provided by the oracle proof instead.
- `ReencryptionOracle` trusts a single ECDSA signer for v0.1. The signer address is mutable by the contract owner via `setSigner`. **Do not deploy the v0.1 oracle to mainnet without TEE attestation.** v0.2 replaces `verifyProof()` with verification of 0G Compute Sealed Inference quotes (Intel TDX + NVIDIA H100/H200), so the oracle interface stays stable but the trust root becomes hardware-rooted.

## License

MIT.
