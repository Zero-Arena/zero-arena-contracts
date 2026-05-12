# Zero Arena — contracts

> Solidity contracts on 0G Chain. Consumed by the [`zeroarena`](https://github.com/Zero-Arena/zero-arena-sdk) SDK via the `@zero-arena/contracts` npm package.

> **Building an agent? Wrong directory.**
> The Galileo deployment is live. Agent devs use the SDK and never need `DEPLOYER_PRIVATE_KEY` or `ORACLE_SIGNER_ADDRESS`. Head to [the SDK](https://github.com/Zero-Arena/zero-arena-sdk).

## Contracts

| Contract | Purpose |
| - | - |
| [`AgentCertificate.sol`](src/AgentCertificate.sol) | Append-only registry of backtest results. Anchors `runHash`, storage / dataset hashes, metrics, `trustTier`, and the `attestationHash` slot reserved for v0.2. |
| [`ZeroArenaINFT.sol`](src/ZeroArenaINFT.sol) | ERC-7857 iNFT. Mints require a certificate clearing configurable thresholds. Vanilla ERC-721 transfers are disabled — ownership moves only through the oracle re-encryption flow. |
| [`oracle/ReencryptionOracle.sol`](src/oracle/ReencryptionOracle.sol) | v0.1 trusted-signer stub for off-chain sealed-key proofs. v0.2 swaps in TEE-attested verification against 0G Compute Sealed Inference quotes. |

## Live deployment — Galileo testnet (chain ID 16602)

| Contract | Address |
| - | - |
| `AgentCertificate` | [`0x21a5DEA59cfA07B261d389A9554477e137805c2f`](https://chainscan-galileo.0g.ai/address/0x21a5dea59cfa07b261d389a9554477e137805c2f) ✓ |
| `ReencryptionOracle` | [`0x63909dA30b0d65ad72b32b3C8C82515f7BFA6Fd6`](https://chainscan-galileo.0g.ai/address/0x63909da30b0d65ad72b32b3c8c82515f7bfa6fd6) ✓ |
| `ZeroArenaINFT` | [`0x4Bd4d45f206861aa7cD4421785a316A1dD06036f`](https://chainscan-galileo.0g.ai/address/0x4bd4d45f206861aa7cd4421785a316a1dd06036f) ✓ |

- Deployer / admin: [`0xB1a5402E…3f50DbD`](https://chainscan-galileo.0g.ai/address/0xb1a5402e46d5360d46a9fe0807d3c927b3f50dbd)
- Oracle signer: [`0xDEf4B61E…2d600D1`](https://chainscan-galileo.0g.ai/address/0xdef4b61eaf80eed763c2d5c443e2b56cb2d600d1)
- Deploy block: 32563974 (2026-05-10)

Pinned in [`deployments/galileo-testnet.json`](deployments/galileo-testnet.json) and shipped in `@zero-arena/contracts/dist/addresses.json`.

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
# fill GALILEO_RPC_URL, DEPLOYER_PRIVATE_KEY, DEPLOYER_ADDRESS, ORACLE_SIGNER_ADDRESS

forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $GALILEO_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --legacy --with-gas-price 3000000000
```

Galileo enforces a tip > 2 gwei — the `--legacy --with-gas-price 3000000000` is mandatory.

## Source verification

```bash
forge verify-contract \
  --chain-id 16602 --num-of-optimizations 200 \
  --compiler-version "v0.8.24+commit.e11b9ed9" \
  --verifier custom --verifier-url https://chainscan-galileo.0g.ai/open/api \
  --verifier-api-key PLACEHOLDER \
  <addr> src/<Path>.sol:<Contract>
```

Add `--constructor-args $(cast abi-encode "constructor(address,address)" $DEPLOYER_ADDRESS $ORACLE_SIGNER_ADDRESS)` for `ReencryptionOracle`, and `"constructor(address,address,address)"` with admin/oracle/cert for `ZeroArenaINFT`.

`forge verify-check` currently mishandles the GUID — poll status with:

```bash
curl -s "https://chainscan-galileo.0g.ai/open/api?module=contract&action=checkverifystatus&guid=<GUID>"
```

## Release flow

After every redeploy:

1. Tag this repo `vX.Y.Z`.
2. CI publishes `@zero-arena/contracts@X.Y.Z` (ABIs + addresses).
3. SDK bumps the dep and cuts a matching SDK release.

Full runbook: [`sdk/RELEASE.md`](https://github.com/Zero-Arena/zero-arena-sdk/blob/main/RELEASE.md).

## Notes

- `Certificate` packs into 5 storage slots.
- `AgentCertificate` has no admin role and no upgrade path — submissions are immutable.
- `ZeroArenaINFT` overrides `transferFrom`/`safeTransferFrom` to revert; the oracle proof provides authorization for `transfer`/`clone`.
- `ReencryptionOracle` trusts a single ECDSA signer in v0.1 (mutable via `setSigner`). **Do not deploy v0.1 oracle to mainnet** — v0.2 replaces `verifyProof()` with 0G Compute TEE quote verification.

## License

MIT.
