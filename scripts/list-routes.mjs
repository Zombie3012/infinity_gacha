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
  'All business errors use `{ "error": "ERR_CODE" }`. Detailed request/response schemas for Combat v2 live in `openapi.combat-v2.yaml`; this inventory is the source list for the remaining OpenAPI coverage.',
  '',
  '| Method | Path | Auth | Feature |',
  '|---|---|---|---|',
  ...rows.map(row => `| ${row.method} | \`${row.path}\` | ${row.auth} | ${row.feature || '—'} |`),
  '',
];
writeFileSync('API_Routes.md', `${lines.join('\n')}\n`, 'utf8');
console.log(`[docs:routes] wrote ${rows.length} routes to API_Routes.md`);
