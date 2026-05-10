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

## Deploy (Galileo testnet)

```bash
cp .env.example .env
# fill in GALILEO_RPC_URL, DEPLOYER_PRIVATE_KEY, DEPLOYER_ADDRESS, ORACLE_SIGNER_ADDRESS

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --verify
```

The script writes addresses to `deployments/galileo-testnet.json`, which is checked into git and consumed by the SDK at publish time.

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
