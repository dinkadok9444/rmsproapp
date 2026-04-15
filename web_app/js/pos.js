/* pos.js — Supabase. Mirror quick_sales_screen.dart (products grid → cart → checkout + history). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const toast = (msg) => {
    const t = $('posToast'); if (!t) return;
    t.textContent = msg; t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 2000);
  };

  let PRODUCTS = []; // {id, source, sku, name, price, qty, category}
  let cart = {}; // id -> { prod, qty }
  let activeCat = 'SEMUA';
  let searchQ = '';
  let payMethod = 'CASH';
  let custType = 'WALK-IN';

  async function fetchProducts() {
    const [{ data: parts }, { data: acc }] = await Promise.all([
      window.sb.from('stock_parts').select('*').eq('branch_id', branchId).eq('status', 'AVAILABLE').limit(2000),
      window.sb.from('accessories').select('*').eq('branch_id', branchId).limit(2000),
    ]);
    const out = [];
    (parts || []).forEach((r) => out.push({
      id: 'P:' + r.id, _id: r.id, source: 'stock_parts',
      sku: r.sku || '', name: r.part_name || r.sku || '—',
      price: Number(r.price) || 0, qty: Number(r.qty) || 0,
      category: r.category || 'PART',
    }));
    (acc || []).forEach((r) => out.push({
      id: 'A:' + r.id, _id: r.id, source: 'accessories',
      sku: r.sku || '', name: r.item_name || r.sku || '—',
      price: Number(r.price) || 0, qty: Number(r.qty) || 0,
      category: 'ACCESSORIES',
    }));
    PRODUCTS = out;
  }

  function renderCats() {
    const cats = ['SEMUA', ...new Set(PRODUCTS.map((p) => p.category).filter(Boolean))];
    $('posCats').innerHTML = cats.map((c) => `<button class="pos-cat${c === activeCat ? ' is-active' : ''}" data-c="${c}">${c}</button>`).join('');
    $('posCats').querySelectorAll('.pos-cat').forEach((b) => {
      b.addEventListener('click', () => { activeCat = b.dataset.c; renderCats(); renderProducts(); });
    });
  }

  function renderProducts() {
    const q = searchQ.toLowerCase();
    const rows = PRODUCTS.filter((p) => {
      if (activeCat !== 'SEMUA' && p.category !== activeCat) return false;
      if (q && !(p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q))) return false;
      return true;
    });
    if (!rows.length) { $('posProducts').innerHTML = ''; $('posProductsEmpty').classList.remove('hidden'); return; }
    $('posProductsEmpty').classList.add('hidden');
    $('posProducts').innerHTML = rows.map((p) => `
      <div class="pos-product" data-id="${p.id}">
        <div class="pos-product__name">${p.name}</div>
        <div class="pos-product__sku">${p.sku}</div>
        <div class="pos-product__meta">
          <span class="pos-product__price">${fmtRM(p.price)}</span>
          <span class="pos-product__qty">Stok: ${p.qty}</span>
        </div>
      </div>`).join('');
    $('posProducts').querySelectorAll('.pos-product').forEach((el) => {
      el.addEventListener('click', () => addToCart(el.dataset.id));
    });
  }

  function addToCart(id) {
    const p = PRODUCTS.find((x) => x.id === id);
    if (!p) return;
    if (!cart[id]) cart[id] = { prod: p, qty: 0 };
    if (cart[id].qty + 1 > p.qty) { toast('Stok tak cukup'); return; }
    cart[id].qty++;
    renderCart();
  }

  function renderCart() {
    const list = Object.values(cart);
    $('posCartCount').textContent = list.reduce((s, x) => s + x.qty, 0);
    const total = list.reduce((s, x) => s + x.qty * x.prod.price, 0);
    $('posCartTotal').textContent = fmtRM(total);
    $('posPayTotal').textContent = fmtRM(total);
    $('posPayBtn').disabled = !list.length;
    $('posCartEmpty').classList.toggle('hidden', list.length > 0);
    $('posCartList').innerHTML = list.map((x) => `
      <div class="pos-cart__item" data-id="${x.prod.id}">
        <div class="pos-cart__name">${x.prod.name}</div>
        <div class="pos-cart__row">
          <button class="pos-cart__btn" data-act="-">−</button>
          <span class="pos-cart__q">${x.qty}</span>
          <button class="pos-cart__btn" data-act="+">+</button>
          <span class="pos-cart__amt">${fmtRM(x.qty * x.prod.price)}</span>
          <button class="pos-cart__btn pos-cart__del" data-act="x"><i class="fas fa-trash"></i></button>
        </div>
      </div>`).join('');
    $('posCartList').querySelectorAll('[data-act]').forEach((b) => {
      b.addEventListener('click', () => {
        const id = b.closest('[data-id]').dataset.id;
        const c = cart[id]; if (!c) return;
        if (b.dataset.act === '+') {
          if (c.qty + 1 > c.prod.qty) { toast('Stok tak cukup'); return; }
          c.qty++;
        } else if (b.dataset.act === '-') {
          c.qty--; if (c.qty <= 0) delete cart[id];
        } else {
          delete cart[id];
        }
        renderCart();
      });
    });
  }

  $('posCartClear').addEventListener('click', () => { cart = {}; renderCart(); });
  $('posSearch').addEventListener('input', (e) => { searchQ = e.target.value; renderProducts(); });

  // --- Payment modal
  const PAY_METHODS = [
    { k: 'CASH', i: 'fa-money-bill' },
    { k: 'QR', i: 'fa-qrcode' },
    { k: 'ONLINE', i: 'fa-globe' },
    { k: 'CARD', i: 'fa-credit-card' },
  ];
  function renderPayGrid() {
    $('posPayGrid').innerHTML = PAY_METHODS.map((m) => `<button type="button" class="pos-pay-btn${m.k === payMethod ? ' is-active' : ''}" data-k="${m.k}"><i class="fas ${m.i}"></i> ${m.k}</button>`).join('');
    $('posPayGrid').querySelectorAll('[data-k]').forEach((b) => {
      b.addEventListener('click', () => { payMethod = b.dataset.k; renderPayGrid(); });
    });
  }
  renderPayGrid();

  document.querySelectorAll('#posCustType .pos-seg__item').forEach((b) => {
    b.addEventListener('click', () => {
      document.querySelectorAll('#posCustType .pos-seg__item').forEach((x) => x.classList.remove('is-active'));
      b.classList.add('is-active');
      custType = b.dataset.type;
    });
  });

  $('posPayBtn').addEventListener('click', () => { $('posPayModal').classList.add('is-open'); });
  $('posPayClose').addEventListener('click', () => { $('posPayModal').classList.remove('is-open'); });

  let lastSale = null;
  $('posPayConfirm').addEventListener('click', async () => {
    const list = Object.values(cart);
    if (!list.length) return;
    const total = list.reduce((s, x) => s + x.qty * x.prod.price, 0);
    const siri = 'S' + Date.now().toString(36).toUpperCase();

    const desc = {
      siri,
      cust_type: custType,
      customer_name: $('posCustName').value.trim() || null,
      customer_tel: $('posCustTel').value.trim() || null,
      customer_alamat: $('posCustAlamat').value.trim() || null,
      items: list.map((x) => ({ id: x.prod._id, source: x.prod.source, name: x.prod.name, sku: x.prod.sku, qty: x.qty, price: x.prod.price })),
    };

    const { data, error } = await window.sb.from('quick_sales').insert({
      tenant_id: ctx.tenant_id,
      branch_id: branchId,
      kind: 'SALE',
      description: JSON.stringify(desc),
      amount: Number(total.toFixed(2)),
      sold_by: $('posStaff').value || ctx.nama,
      sold_at: new Date().toISOString(),
      payment_method: payMethod,
    }).select().single();
    if (error) { toast('Gagal: ' + error.message); return; }

    // Decrement stock
    for (const x of list) {
      const newQty = Math.max(0, x.prod.qty - x.qty);
      const newStatus = (x.prod.source === 'stock_parts' && newQty === 0) ? 'OUT_OF_STOCK' : undefined;
      const patch = { qty: newQty };
      if (newStatus) patch.status = newStatus;
      await window.sb.from(x.prod.source).update(patch).eq('id', x.prod._id);
    }

    lastSale = { siri, total, method: payMethod, row: data };
    $('posDoneSiri').textContent = '#' + siri;
    $('posDoneAmt').textContent = fmtRM(total);
    $('posDoneMethod').textContent = payMethod;
    $('posDoneStatus').textContent = 'Rekod #' + (data && data.id ? data.id.slice(0, 8) : '');
    $('posPayModal').classList.remove('is-open');
    $('posDoneModal').classList.add('is-open');

    // Auto-print + drawer
    const P = window.RmsPrinter;
    if ($('posAutoPrint').checked && P && P.isConnected && P.isConnected()) {
      doPrint(lastSale).catch(() => {});
    }
    if ($('posAutoDrawer').checked && payMethod === 'CASH' && P && P.isConnected && P.isConnected()) {
      P.kickCashDrawer().catch(() => {});
    }

    cart = {};
    renderCart();
    await fetchProducts();
    renderCats();
    renderProducts();
    loadCustomerList().catch(() => {});
  });

  $('posDoneOk').addEventListener('click', () => { $('posDoneModal').classList.remove('is-open'); });

  async function doPrint(sale) {
    if (!sale) return;
    const P = window.RmsPrinter;
    if (!P || !P.isConnected || !P.isConnected()) { toast('Printer tidak disambung'); return; }
    const shop = { shopName: $('posShop').textContent || 'RMS PRO' };
    const job = {
      siri: sale.siri,
      nama: (sale.row && JSON.parse(sale.row.description || '{}').customer_name) || 'Walk-in',
      tel: (sale.row && JSON.parse(sale.row.description || '{}').customer_tel) || '-',
      model: '-',
      tarikh: sale.row && sale.row.sold_at,
      items_array: (JSON.parse(sale.row.description || '{}').items || []).map((x) => ({ nama: x.name, qty: x.qty, harga: x.price })),
    };
    try { await P.printReceipt(job, shop); } catch (e) { toast('Gagal cetak: ' + e.message); }
  }

  $('posDoneReprint').addEventListener('click', () => doPrint(lastSale));

  // Printer connect button + label
  function updatePrinterLbl() {
    const P = window.RmsPrinter;
    const lbl = $('posPrinterLbl');
    if (!lbl) return;
    lbl.textContent = (P && P.isConnected && P.isConnected()) ? (P.getName() || 'CONNECTED') : 'PRINTER';
  }
  if (window.RmsPrinter) {
    window.RmsPrinter.onChange(updatePrinterLbl);
  }
  $('posPrinterBtn').addEventListener('click', async () => {
    const P = window.RmsPrinter; if (!P) { toast('Printer module tiada'); return; }
    if (P.isConnected()) { await P.disconnect(); await P.disconnectUSB(); return; }
    try {
      if (P.bleSupported()) await P.connect();
      else if (P.usbSupported()) await P.connectUSB();
      else toast('Browser tak support printer');
    } catch (e) { toast(e.message); }
  });

  // --- Customer datalist (from pos_trackings + past quick_sales customer_name)
  async function loadCustomerList() {
    const out = new Map();
    const { data: pt } = await window.sb.from('pos_trackings').select('customer_name,customer_tel').eq('tenant_id', ctx.tenant_id).limit(500);
    (pt || []).forEach((r) => { if (r.customer_name) out.set(r.customer_name, r.customer_tel || ''); });
    const { data: qs } = await window.sb.from('quick_sales').select('description').eq('branch_id', branchId).eq('kind', 'SALE').order('sold_at', { ascending: false }).limit(300);
    (qs || []).forEach((r) => { try { const d = JSON.parse(r.description || '{}'); if (d.customer_name) out.set(d.customer_name, d.customer_tel || out.get(d.customer_name) || ''); } catch (_) {} });
    $('posCustList').innerHTML = [...out.entries()].map(([n, t]) => `<option value="${n}">${t}</option>`).join('');
  }
  $('posCustName').addEventListener('change', () => {
    const v = $('posCustName').value;
    const opt = $('posCustList').querySelector(`option[value="${v.replace(/"/g,'\\"')}"]`);
    if (opt && opt.textContent && !$('posCustTel').value) $('posCustTel').value = opt.textContent;
  });

  // --- Staff dropdown
  async function loadStaff() {
    const { data } = await window.sb.from('users').select('id,nama').eq('tenant_id', ctx.tenant_id).limit(100);
    const list = (data && data.length) ? data : [{ id: ctx.id, nama: ctx.nama }];
    $('posStaff').innerHTML = list.map((u) => `<option value="${u.nama || u.id}">${u.nama || u.id}</option>`).join('');
    if (ctx.nama) $('posStaff').value = ctx.nama;
  }

  // --- History modal
  let HIST = [];
  async function fetchHistory() {
    const { data } = await window.sb
      .from('quick_sales').select('*')
      .eq('branch_id', branchId).eq('kind', 'SALE')
      .order('sold_at', { ascending: false }).limit(500);
    HIST = data || [];
    renderHist();
  }
  function renderHist() {
    const range = $('posHistRange').value;
    const q = ($('posHistSearch').value || '').toLowerCase();
    const now = Date.now();
    const cutoff = range === 'today' ? (new Date().setHours(0,0,0,0))
      : range === 'week' ? now - 7*864e5
      : range === 'month' ? now - 30*864e5
      : 0;
    const rows = HIST.filter((r) => {
      const t = r.sold_at ? new Date(r.sold_at).getTime() : 0;
      if (cutoff && t < cutoff) return false;
      if (q) {
        const desc = (r.description || '').toLowerCase();
        if (!desc.includes(q)) return false;
      }
      return true;
    });
    $('posHistCount').textContent = rows.length;
    $('posHistTotal').textContent = fmtRM(rows.reduce((s, r) => s + Number(r.amount || 0), 0));
    $('posHistEmpty').classList.toggle('hidden', rows.length > 0);
    $('posHistList').innerHTML = rows.map((r) => {
      let d = {}; try { d = JSON.parse(r.description || '{}'); } catch (e) {}
      const dt = r.sold_at ? new Date(r.sold_at) : null;
      const dtStr = dt ? `${String(dt.getDate()).padStart(2,'0')}/${String(dt.getMonth()+1).padStart(2,'0')} ${String(dt.getHours()).padStart(2,'0')}:${String(dt.getMinutes()).padStart(2,'0')}` : '';
      return `<div class="pos-hist-item">
        <div><b>${d.siri || r.id.slice(0,8)}</b> · ${r.payment_method || ''} · ${dtStr}</div>
        <div>${d.customer_name || 'Walk-in'} · ${fmtRM(r.amount)}</div>
      </div>`;
    }).join('');
  }
  $('posHistoryBtn').addEventListener('click', async () => { await fetchHistory(); $('posHistModal').classList.add('is-open'); });
  $('posHistClose').addEventListener('click', () => $('posHistModal').classList.remove('is-open'));
  $('posHistRange').addEventListener('change', renderHist);
  $('posHistSearch').addEventListener('input', renderHist);

  // --- Branch name
  (async () => {
    const { data } = await window.sb.from('branches').select('name').eq('id', branchId).single();
    $('posShop').textContent = (data && data.name) || '';
  })();

  // Realtime
  window.sb.channel('pos-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'stock_parts', filter: `branch_id=eq.${branchId}` }, async () => { await fetchProducts(); renderProducts(); })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'accessories', filter: `branch_id=eq.${branchId}` }, async () => { await fetchProducts(); renderProducts(); })
    .subscribe();

  await loadStaff();
  await fetchProducts();
  renderCats();
  renderProducts();
  renderCart();
  loadCustomerList().catch(() => {});
  updatePrinterLbl();
})();
