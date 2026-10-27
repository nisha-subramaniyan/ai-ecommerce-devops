const { createApp, log } = require('./app');
const { createStore } = require('./store');

const port = Number(process.env.PORT || 3000);

async function main() {
  const store = createStore();
  // Retry DB init: in Compose/Kubernetes the DB may start after the app.
  for (let attempt = 1; ; attempt++) {
    try { await store.init(); break; }
    catch (e) {
      log('error', 'database init failed', { attempt, error: e.message });
      if (attempt >= 30) process.exit(1);
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  const server = createApp(store).listen(port, () =>
    log('info', 'server started', { port, store: store.kind }));

  process.on('SIGTERM', () => { // graceful shutdown for rolling updates
    log('info', 'SIGTERM received, shutting down');
    server.close(() => process.exit(0));
  });
}

main();
