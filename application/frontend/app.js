const cart = {};
const $ = (id) => document.getElementById(id);

function renderCart() {
  const n = Object.values(cart).reduce((a, b) => a + b, 0);
  $('cart').textContent = `Cart: ${n} item${n === 1 ? '' : 's'}`;
}

async function load() {
  const products = await (await fetch('/api/products')).json();
  $('grid').innerHTML = '';
  products.forEach((p) => {
    const d = document.createElement('div');
    d.className = 'card';
    d.innerHTML = `<h3>${p.name}</h3><p>$${Number(p.price).toFixed(2)} &middot; ${p.stock} in stock</p>`;
    const b = document.createElement('button');
    b.textContent = 'Add to cart';
    b.onclick = () => { cart[p.id] = (cart[p.id] || 0) + 1; renderCart(); };
    d.appendChild(b);
    $('grid').appendChild(d);
  });
  try { $('ver').textContent = 'version: ' + (await (await fetch('/api/version')).json()).version; } catch (e) {}
}

$('checkout').onclick = async () => {
  const items = Object.entries(cart).map(([productId, quantity]) => ({ productId: Number(productId), quantity }));
  const r = await fetch('/api/orders', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ items }) });
  const body = await r.json();
  $('msg').textContent = r.ok ? `Order #${body.id} placed. Total $${body.total}` : `Error: ${body.error}`;
  if (r.ok) { Object.keys(cart).forEach((k) => delete cart[k]); renderCart(); }
};

load();
