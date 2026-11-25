#!/usr/bin/env node
/**
 * Generates API_Routes.md from the Express route table.
 * Usage: npm run docs:routes
 */
import { readFileSync, writeFileSync } from 'node:fs';

const source = readFileSync('packages/server/src/server.ts', 'utf8');
const routePattern = /app\.(get|post|patch|put|delete)\('([^']+)'([^\n]*)/g;
const rows = [];
for (const match of source.matchAll(routePattern)) {
  const [, method, path, rest] = match;
  const feature = /requireFeature\('([^']+)'\)/.exec(rest)?.[1] ?? '';
  const auth = rest.includes('requireAdminApiKey') ? 'admin key'
    : rest.includes('requireAccount') ? 'Bearer'
      : 'public';
  rows.push({ method: method.toUpperCase(), path, auth, feature });
}
rows.sort((a, b) => a.path.localeCompare(b.path) || a.method.localeCompare(b.method));

const lines = [
  '# API route inventory',
  '',
  `Generated from \`packages/server/src/server.ts\` (${rows.length} routes).`,
  'Errors use `{ "error": string }`; the string may be an error code or a readable message. Detailed schemas: [private PvE map](openapi.pve.yaml) and [Combat v2](openapi.combat-v2.yaml). PvE mutations require `Idempotency-Key`; map reads settle due arrivals. This inventory lists the remaining API coverage.',
  'This is a static inventory of literal route declarations, not a guarantee of access or an exhaustive list of dynamically generated routes. Prefix middleware can enforce additional conditions: `/api/dungeon/*` is unavailable, `/api/shop/*` requires clearing Tower floor 5, `/api/alchemy/*` requires floor 10, and `/api/alliance/*` and protected World routes require floor 25. See [Tower progression](docs/TOWER_PROGRESSION.md) and the server implementation.',
  '',
  '| Method | Path | Auth | Feature |',
  '|---|---|---|---|',
  ...rows.map(row => `| ${row.method} | \`${row.path}\` | ${row.auth} | ${row.feature || '—'} |`),
  '',
];
writeFileSync('API_Routes.md', `${lines.join('\n')}\n`, 'utf8');
console.log(`[docs:routes] wrote ${rows.length} routes to API_Routes.md`);
