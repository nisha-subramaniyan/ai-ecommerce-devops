// Data layer. Uses PostgreSQL when DATABASE_URL is set, otherwise an in-memory
// store so unit tests and quick local runs need no database.
const SEED = [
  { id: 1, name: 'Wireless Headphones', price: 59.99, stock: 25 },
  { id: 2, name: 'Mechanical Keyboard', price: 89.5, stock: 15 },
  { id: 3, name: 'USB-C Hub', price: 34.0, stock: 40 },
  { id: 4, name: 'Laptop Stand', price: 27.25, stock: 30 },
  { id: 5, name: '4K Webcam', price: 79.0, stock: 12 }
];

function memoryStore() {
  const orders = [];
  return {
    kind: 'memory',
    async init() {},
    async listProducts() { return SEED; },
    async getProduct(id) { return SEED.find((p) => p.id === id) || null; },
    async createOrder(items, total) {
      const order = { id: orders.length + 1, items, total, created_at: new Date().toISOString() };
      orders.push(order);
      return order;
    },
    async ping() { return true; }
  };
}

function pgStore(connectionString) {
  const { Pool } = require('pg');
  const pool = new Pool({ connectionString });
  return {
    kind: 'postgres',
    async init() {
      await pool.query(`CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY, name TEXT NOT NULL, price NUMERIC(10,2) NOT NULL, stock INT NOT NULL)`);
      await pool.query(`CREATE TABLE IF NOT EXISTS orders (
        id SERIAL PRIMARY KEY, items JSONB NOT NULL, total NUMERIC(10,2) NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now())`);
      const { rows } = await pool.query('SELECT COUNT(*)::int AS n FROM products');
      if (rows[0].n === 0) {
        for (const p of SEED) {
          await pool.query('INSERT INTO products(name, price, stock) VALUES ($1,$2,$3)', [p.name, p.price, p.stock]);
        }
      }
    },
    async listProducts() {
      const { rows } = await pool.query('SELECT id, name, price::float AS price, stock FROM products ORDER BY id');
      return rows;
    },
    async getProduct(id) {
      const { rows } = await pool.query('SELECT id, name, price::float AS price, stock FROM products WHERE id=$1', [id]);
      return rows[0] || null;
    },
    async createOrder(items, total) {
      const { rows } = await pool.query(
        'INSERT INTO orders(items, total) VALUES ($1,$2) RETURNING id, items, total::float AS total, created_at',
        [JSON.stringify(items), total]);
      return rows[0];
    },
    async ping() { await pool.query('SELECT 1'); return true; }
  };
}

function createStore() {
  return process.env.DATABASE_URL ? pgStore(process.env.DATABASE_URL) : memoryStore();
}

module.exports = { createStore, memoryStore };
