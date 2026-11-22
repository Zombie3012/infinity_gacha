// Isolated child-process host used by the real-clock PvE soak test.
process.env.NODE_ENV = 'test';
const { pathToFileURL } = await import('node:url');
const { resolve } = await import('node:path');
// A frozen build allows independent development builds during a long run.
const runtime = process.env.PVE_TEST_USE_CURRENT_BUILD !== '1' && process.env.PVE_SOAK_RUNTIME_DIR
  ? pathToFileURL(resolve(process.env.PVE_SOAK_RUNTIME_DIR) + '/').href : '../packages/server/dist/';
const { createApp } = await import(runtime + 'server.js');
const { pool } = await import(runtime + 'database/db.js');
const server = createApp().listen(0, '127.0.0.1', () => process.send?.({ port: server.address().port }));
process.on('message', message => {
  if (message === 'stop') server.close(async () => { await pool.end(); process.exit(0); });
});
