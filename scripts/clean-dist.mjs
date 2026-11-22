import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const workspace = process.argv[2];
if (!['shared', 'server'].includes(workspace)) {
  throw new Error('Expected shared or server workspace.');
}

// Remove stale compiler output when a source module is deleted or renamed.
const directory = fileURLToPath(new URL(`../packages/${workspace}/dist/`, import.meta.url));
rmSync(directory, { recursive: true, force: true });
// Composite workspaces otherwise consider deleted output up to date.
rmSync(fileURLToPath(new URL(`../packages/${workspace}/tsconfig.tsbuildinfo`, import.meta.url)), { force: true });
