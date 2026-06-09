#!/usr/bin/env node
// sync-addresses.mjs — propagate the canonical 0G-mainnet contract addresses
// from deployments/16661*.json to every place they are duplicated (FE
// contracts.ts, all .env files, READMEs, docs). Turns a redeploy into a
// ONE-COMMAND propagation instead of a ~15-file manual edit. See ../../ENV.md.
//
// Usage (run from the contracts repo root, with the sibling repos checked out
// next to it in the umbrella folder):
//   node scripts/sync-addresses.mjs            # DRY-RUN: show what would change
//   node scripts/sync-addresses.mjs --write    # apply changes + update lockfile
//
// How it works:
//   • NEW addresses  ← deployments/16661.json (Cert/Oracle/iNFT) +
//                       deployments/16661-paper-engine.json (Live/Season).
//   • OLD addresses  ← deployments/.synced-addresses.json (the lockfile this
//                       script maintains).
//   For each contract whose address changed (old != new) it string-replaces
//   old→new across the target files — format-agnostic, and replaceAll handles
//   markdown links that print the address twice. Idempotent.
//   First run (no lockfile) just records the current deployments as the
//   baseline (assumes the repo is in sync), so the NEXT redeploy can diff
//   against it.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const CONTRACTS_ROOT = resolve(SCRIPT_DIR, '..'); // .../contracts
const PROJECT_ROOT = resolve(CONTRACTS_ROOT, '..'); // umbrella folder holding all repos
const CHAIN_ID = 16661;

const DEPLOY_QUALIFIER = resolve(CONTRACTS_ROOT, 'deployments', `${CHAIN_ID}.json`);
const DEPLOY_PAPER = resolve(CONTRACTS_ROOT, 'deployments', `${CHAIN_ID}-paper-engine.json`);
const LOCKFILE = resolve(CONTRACTS_ROOT, 'deployments', '.synced-addresses.json');

const WRITE = process.argv.includes('--write');

const rel = (p) => relative(PROJECT_ROOT, p);
function readJson(p) {
  if (!existsSync(p)) {
    console.error(`✗ missing source file: ${rel(p)}`);
    process.exit(1);
  }
  return JSON.parse(readFileSync(p, 'utf8'));
}

// ── 1) canonical NEW addresses from the deployment records (source of truth) ──
const q = readJson(DEPLOY_QUALIFIER).addresses ?? {};
const pe = readJson(DEPLOY_PAPER).paperEngine ?? {};
const NEW = {
  AgentCertificate: q.AgentCertificate,
  ReencryptionOracle: q.ReencryptionOracle,
  ZeroArenaINFT: q.ZeroArenaINFT,
  LiveCertificate: pe.LiveCertificate,
  Season: pe.Season,
};
for (const [k, v] of Object.entries(NEW)) {
  if (!/^0x[0-9a-fA-F]{40}$/.test(v ?? '')) {
    console.error(`✗ ${k}: invalid/missing address in deployments json: ${v}`);
    process.exit(1);
  }
}

// ── 2) target files (relative to PROJECT_ROOT). Missing files are skipped, so
//        the script is safe on a standalone contracts clone. ──
const TARGETS = [
  // functional (breaks the product if stale)
  'zero-arena-fe/lib/chain/contracts.ts',
  'zero-arena-fe/.env.local',
  'zero-arena-fe/.env.example',
  'zero-arena-bacend/.env',
  'zero-arena-bacend/.env.onboard.example',
  'zero-arena-bacend/.env.paper.example',
  'examples/.env',
  'examples/.env.example',
  // docs of record
  'ENV.md',
  'CLAUDE.md',
  'README.md',
  'contracts/README.md',
  'sdk/README.md',
  'examples/README.md',
  'zero-arena-fe/README.md',
  'zero-arena-bacend/README.md',
  'zero-arena-fe/INTEGRATION.md',
  'zero-arena-bacend/INTEGRATION.md',
  'docs/03-timeline-roadmap.md',
  'docs/07-smart-contracts.md',
];

// ── 3) OLD addresses from the lockfile ──
const OLD = existsSync(LOCKFILE) ? readJson(LOCKFILE) : null;

if (!OLD) {
  console.log('No lockfile yet — recording the current deployments as the sync baseline.');
  console.log('(Assumes the repo is currently in sync. Re-run with --write after your next');
  console.log(' redeploy and it will propagate the changed addresses everywhere.)\n');
  for (const [k, v] of Object.entries(NEW)) console.log(`  ${k}: ${v}`);
  if (WRITE) {
    writeFileSync(LOCKFILE, JSON.stringify(NEW, null, 2) + '\n');
    console.log(`\n✓ wrote baseline ${rel(LOCKFILE)}`);
  } else {
    console.log('\ndry-run: pass --write to record the baseline lockfile.');
  }
  process.exit(0);
}

// ── 4) what changed ──
const changes = Object.keys(NEW)
  .filter((k) => OLD[k] && OLD[k] !== NEW[k])
  .map((k) => ({ k, old: OLD[k], neu: NEW[k] }));

if (changes.length === 0) {
  console.log('✓ All addresses already match the lockfile — nothing to propagate.');
  // still surface network drift below before exiting
} else {
  console.log(`${WRITE ? 'Applying' : 'DRY-RUN — would apply'} ${changes.length} address change(s):`);
  for (const c of changes) console.log(`  ${c.k}: ${c.old} → ${c.neu}`);
  console.log('');

  let totalEdits = 0;
  for (const t of TARGETS) {
    const p = resolve(PROJECT_ROOT, t);
    if (!existsSync(p)) {
      console.log(`  – skip (absent): ${t}`);
      continue;
    }
    let content = readFileSync(p, 'utf8');
    let edits = 0;
    for (const c of changes) {
      const n = content.split(c.old).length - 1;
      if (n > 0) {
        content = content.split(c.old).join(c.neu);
        edits += n;
      }
    }
    if (edits > 0) {
      totalEdits += edits;
      console.log(`  ${WRITE ? '✓' : '·'} ${t}  (${edits} occurrence(s))`);
      if (WRITE) writeFileSync(p, content);
    }
  }
  console.log(`\n${WRITE ? 'Applied' : 'Would apply'} ${totalEdits} edit(s).`);

  if (WRITE) {
    writeFileSync(LOCKFILE, JSON.stringify(NEW, null, 2) + '\n');
    console.log(`✓ updated lockfile ${rel(LOCKFILE)}`);
  } else {
    console.log('Pass --write to apply the edits and update the lockfile.');
  }
}

// ── 5) bonus: warn on testnet/Galileo drift in the target .env files (the class
//        of bug that left zero-arena-bacend/.env on Galileo). Read-only. ──
const NET_BAD = /evmrpc-testnet|testnet-turbo|chainscan-galileo/;
const envTargets = TARGETS.filter((t) => /\.env(\.|$)/.test(t));
let warned = false;
for (const t of envTargets) {
  const p = resolve(PROJECT_ROOT, t);
  if (!existsSync(p)) continue;
  const bad = readFileSync(p, 'utf8')
    .split('\n')
    .filter((l) => NET_BAD.test(l) && !l.trim().startsWith('#'));
  if (bad.length) {
    if (!warned) {
      console.log('\n⚠ testnet/Galileo URLs found (mainnet expected — see ENV.md §1):');
      warned = true;
    }
    console.log(`  ${t}: ${bad.length} line(s)`);
  }
}
