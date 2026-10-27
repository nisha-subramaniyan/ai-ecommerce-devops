const test = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');
const { memoryStore } = require('../src/store');

let server, base;
test.before(async () => {
  server = createApp(memoryStore()).listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => server.close());

test('GET /health returns ok', async () => {
  const r = await fetch(`${base}/health`);
  assert.strictEqual(r.status, 200);
  assert.deepStrictEqual(await r.json(), { status: 'ok' });
});

test('GET /api/products lists seeded products', async () => {
  const items = await (await fetch(`${base}/api/products`)).json();
  assert.ok(items.length >= 5);
});

test('GET unknown product returns 404', async () => {
  assert.strictEqual((await fetch(`${base}/api/products/999`)).status, 404);
});

test('POST /api/orders computes the total', async () => {
  const r = await fetch(`${base}/api/orders`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ items: [{ productId: 1, quantity: 2 }, { productId: 3, quantity: 1 }] })
  });
  assert.strictEqual(r.status, 201);
  assert.strictEqual((await r.json()).total, 153.98);
});

test('POST /api/orders rejects invalid payload', async () => {
  const r = await fetch(`${base}/api/orders`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ items: [] }) });
  assert.strictEqual(r.status, 400);
});

test('GET /metrics exposes Prometheus metrics', async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_request_duration_seconds/);
});
