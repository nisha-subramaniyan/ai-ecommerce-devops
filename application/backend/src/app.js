const express = require('express');
const client = require('prom-client');

// Structured JSON logs: one object per line. Filebeat/ELK and the AI analyser
// both depend on this format, so keep the field names stable.
function log(level, message, extra = {}) {
  process.stdout.write(JSON.stringify({
    '@timestamp': new Date().toISOString(), level, service: 'shop-backend', message, ...extra
  }) + '\n');
}

function createApp(store) {
  const app = express();
  app.use(express.json());

  // ---- Prometheus metrics ----
  const register = new client.Registry();
  client.collectDefaultMetrics({ register });
  const httpDuration = new client.Histogram({
    name: 'http_request_duration_seconds', help: 'HTTP request latency',
    labelNames: ['method', 'route', 'status'], buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
    registers: [register]
  });
  const ordersTotal = new client.Counter({
    name: 'shop_orders_total', help: 'Orders placed', registers: [register] });

  app.use((req, res, next) => {
    const end = httpDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
      end({ method: req.method, route, status: res.statusCode });
      log(res.statusCode >= 500 ? 'error' : 'info', 'request', {
        method: req.method, path: req.originalUrl, status: res.statusCode });
    });
    next();
  });

  // ---- Operational endpoints ----
  app.get('/health', (req, res) => res.json({ status: 'ok' }));           // liveness
  app.get('/ready', async (req, res) => {                                  // readiness
    try { await store.ping(); res.json({ status: 'ready', store: store.kind }); }
    catch (e) { log('error', 'database unreachable', { error: e.message }); res.status(503).json({ status: 'not-ready' }); }
  });
  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });
  app.get('/api/version', (req, res) => res.json({ version: process.env.APP_VERSION || 'dev' }));

  // ---- Business API ----
  app.get('/api/products', async (req, res, next) => {
    try { res.json(await store.listProducts()); } catch (e) { next(e); }
  });

  app.get('/api/products/:id', async (req, res, next) => {
    try {
      const p = await store.getProduct(Number(req.params.id));
      if (!p) return res.status(404).json({ error: 'product not found' });
      res.json(p);
    } catch (e) { next(e); }
  });

  app.post('/api/orders', async (req, res, next) => {
    try {
      const items = req.body && req.body.items;
      if (!Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ error: 'items must be a non-empty array' });
      }
      let total = 0;
      for (const it of items) {
        const p = await store.getProduct(Number(it.productId));
        const qty = Number(it.quantity);
        if (!p || !Number.isInteger(qty) || qty < 1) {
          return res.status(400).json({ error: 'invalid item', item: it });
        }
        total += p.price * qty;
      }
      const order = await store.createOrder(items, Math.round(total * 100) / 100);
      ordersTotal.inc();
      log('info', 'order created', { orderId: order.id, total: order.total });
      res.status(201).json(order);
    } catch (e) { next(e); }
  });

  // Deliberate failure endpoint used to demo monitoring + AI incident analysis.
  // Disabled unless ENABLE_CHAOS=true so it never exists in a real deployment.
  if (process.env.ENABLE_CHAOS === 'true') {
    app.get('/api/chaos/error', (req, res, next) => next(new Error('Simulated failure: database connection timeout (ETIMEDOUT)')));
  }

  app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
    log('error', err.message, { stack: err.stack, path: req.originalUrl });
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}

module.exports = { createApp, log };
