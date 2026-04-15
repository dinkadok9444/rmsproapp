/* Admin → Marketplace. Mirror rmsproapp/lib/screens/admin_modules/marketplace_admin_screen.dart.
   Data: Firestore `marketplace_orders` + `marketplace_global` (marketplace kekal Firebase).
   Fields guna camelCase mengikut dart source. */
(function () {
  'use strict';

  const FILTERS = ['Semua', 'pending_payment', 'paid', 'shipped', 'completed', 'cancelled'];

  const listEl = document.getElementById('orderList');
  const filterRow = document.getElementById('filterRow');
  let orders = [];
  let filterStatus = 'Semua';
  let activeListings = 0;

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });

  document.querySelectorAll('.admin-tab').forEach(t => t.addEventListener('click', () => {
    document.querySelectorAll('.admin-tab').forEach(x => x.classList.remove('is-active'));
    t.classList.add('is-active');
    const tab = t.dataset.tab;
    document.getElementById('tabTrx').classList.toggle('hidden', tab !== 'trx');
    document.getElementById('tabAna').classList.toggle('hidden', tab !== 'ana');
    if (tab === 'ana') renderAnalytics();
  }));

  const FB_CONFIG = {
    apiKey: 'AIzaSyCiCmpmEFnaZKx1OE84a2OgRDEn8E9Ulfk',
    appId: '1:94407896005:web:42a2ab858a0b24280379ac',
    messagingSenderId: '94407896005',
    projectId: 'rmspro-2f454',
    authDomain: 'rmspro-2f454.firebaseapp.com',
    storageBucket: 'rmspro-2f454.firebasestorage.app',
    databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
  };
  let fs;

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    if (!window.firebase) { listEl.innerHTML = '<div class="admin-error">Firebase SDK tak dimuatkan</div>'; return; }
    if (!firebase.apps.length) firebase.initializeApp(FB_CONFIG);
    fs = firebase.firestore();
    renderFilters();
    await Promise.all([loadOrders(), loadStats()]);
  })();

  function renderFilters() {
    filterRow.innerHTML = FILTERS.map(f => `
      <button class="mp-filter ${filterStatus === f ? 'is-active' : ''}" data-f="${escapeAttr(f)}">
        ${f === 'Semua' ? 'Semua' : statusLabel(f)}
      </button>
    `).join('');
    filterRow.querySelectorAll('.mp-filter').forEach(b => b.addEventListener('click', () => {
      filterStatus = b.dataset.f;
      renderFilters();
      renderOrders();
    }));
  }

  async function loadOrders() {
    try {
      const snap = await fs.collection('marketplace_orders').orderBy('createdAt', 'desc').get();
      orders = snap.docs.map(d => {
        const x = d.data() || {};
        // Map camelCase Firestore → snake_case yang render code guna
        return {
          id: d.id,
          status: x.status,
          item_name: x.itemName,
          category: x.category,
          quantity: x.quantity,
          total_price: x.totalPrice,
          commission: x.commission,
          seller_payout: x.sellerPayout,
          buyer_shop_name: x.buyerShopName,
          seller_shop_name: x.sellerShopName,
          tracking_number: x.trackingNumber,
          courier_name: x.courierName,
          created_at: x.createdAt && x.createdAt.toDate ? x.createdAt.toDate().toISOString() : null,
        };
      });
      updateStats();
      renderOrders();
    } catch (err) {
      listEl.innerHTML = `<div class="admin-error">${escapeHtml(err.message || err)}</div>`;
    }
  }

  async function loadStats() {
    try {
      const snap = await fs.collection('marketplace_global').where('isActive', '==', true).get();
      activeListings = snap.size;
    } catch (_) { activeListings = 0; }
  }

  function updateStats() {
    let gmv = 0, comm = 0, completed = 0, active = 0;
    for (const o of orders) {
      const total = num(o.total_price);
      const c = num(o.commission);
      const s = o.status || '';
      if (s === 'completed') { gmv += total; comm += c; completed++; }
      if (s === 'paid' || s === 'shipped') active++;
    }
    document.getElementById('statGmv').textContent = 'RM ' + gmv.toFixed(2);
    document.getElementById('statComm').textContent = 'RM ' + comm.toFixed(2);
    document.getElementById('statActive').textContent = String(active);
    document.getElementById('statDone').textContent = String(completed);
    window.__mpStats = { gmv, comm, completed, active };
  }

  function renderOrders() {
    const rows = filterStatus === 'Semua' ? orders : orders.filter(o => o.status === filterStatus);
    if (!rows.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-inbox"></i> Tiada transaksi</div>`;
      return;
    }
    listEl.innerHTML = rows.map(orderCard).join('');
  }

  function orderCard(o) {
    const status = o.status || '';
    const col = statusColor(status);
    const total = num(o.total_price);
    const comm = num(o.commission);
    const payout = num(o.seller_payout);
    const qty = parseInt(o.quantity, 10) || 0;
    const tracking = (o.tracking_number || '').toString().trim();
    return `
      <div class="mp-order" style="border-color:${col}33">
        <div class="mp-order__head">
          <span class="mp-status" style="background:${col}1A;color:${col}">${escapeHtml(statusLabel(status))}</span>
          <span class="mp-order__date">${escapeHtml(fmtDate(o.created_at))}</span>
        </div>
        <div class="mp-order__item">${escapeHtml((o.item_name || '-').toUpperCase())}</div>
        <div class="mp-order__route">
          <i class="fas fa-shop"></i>
          <span>${escapeHtml((o.buyer_shop_name || '-').toUpperCase())} &rarr; ${escapeHtml((o.seller_shop_name || '-').toUpperCase())}</span>
        </div>
        <div class="mp-chips">
          <span class="mp-chip" style="background:rgba(148,163,184,0.15);color:var(--text-dim)">${qty} unit</span>
          <span class="mp-chip" style="background:rgba(59,130,246,0.1);color:var(--blue)">RM ${total.toFixed(2)}</span>
          <span class="mp-chip" style="background:rgba(139,92,246,0.1);color:#8B5CF6">Kom: RM ${comm.toFixed(2)}</span>
          <span class="mp-chip" style="background:rgba(16,185,129,0.1);color:var(--green)">Seller: RM ${payout.toFixed(2)}</span>
        </div>
        ${tracking ? `
          <div class="mp-tracking">
            <i class="fas fa-truck"></i>
            <span>${escapeHtml(o.courier_name || '')} ${escapeHtml(tracking)}</span>
          </div>
        ` : ''}
      </div>
    `;
  }

  function renderAnalytics() {
    const s = window.__mpStats || { gmv: 0, comm: 0 };
    document.getElementById('anaGmv').textContent = 'RM ' + s.gmv.toFixed(2);
    document.getElementById('anaComm').textContent = 'RM ' + s.comm.toFixed(2);
    document.getElementById('anaListing').textContent = String(activeListings);
    document.getElementById('anaTotal').textContent = String(orders.length);

    const catCount = {}, catRev = {};
    for (const o of orders) {
      if (o.status !== 'completed') continue;
      const cat = (o.category || 'Lain-lain').toString();
      catCount[cat] = (catCount[cat] || 0) + 1;
      catRev[cat] = (catRev[cat] || 0) + num(o.total_price);
    }
    const catEl = document.getElementById('catList');
    const catKeys = Object.keys(catCount);
    if (!catKeys.length) {
      catEl.innerHTML = `<div class="admin-empty" style="padding:12px;text-align:left">Tiada data</div>`;
    } else {
      catEl.innerHTML = catKeys.map(k => `
        <div class="mp-row">
          <div class="mp-row__name" style="flex:1">${escapeHtml(k)}</div>
          <div style="font-size:10px;color:var(--text-muted);margin-right:12px">${catCount[k]} unit</div>
          <div class="mp-row__val">RM ${(catRev[k] || 0).toFixed(2)}</div>
        </div>
      `).join('');
    }

    const sellerSales = {};
    for (const o of orders) {
      if (o.status !== 'completed') continue;
      const name = (o.seller_shop_name || '-').toString();
      sellerSales[name] = (sellerSales[name] || 0) + num(o.total_price);
    }
    const sorted = Object.entries(sellerSales).sort((a, b) => b[1] - a[1]).slice(0, 10);
    const sellerEl = document.getElementById('sellerList');
    if (!sorted.length) {
      sellerEl.innerHTML = `<div class="admin-empty" style="padding:12px;text-align:left">Tiada data</div>`;
    } else {
      sellerEl.innerHTML = sorted.map(([name, val], idx) => {
        const rank = idx + 1;
        return `
          <div class="mp-row">
            <div class="mp-row__rank ${rank <= 3 ? 'is-top' : 'is-rest'}">${rank}</div>
            <div class="mp-row__name">${escapeHtml(name.toUpperCase())}</div>
            <div class="mp-row__val">RM ${val.toFixed(2)}</div>
          </div>
        `;
      }).join('');
    }
  }

  function statusLabel(s) {
    switch (s) {
      case 'pending_payment': return 'BELUM BAYAR';
      case 'paid': return 'DIBAYAR';
      case 'shipped': return 'DIHANTAR';
      case 'completed': return 'SELESAI';
      case 'cancelled': return 'DIBATALKAN';
      default: return (s || '').toUpperCase();
    }
  }
  function statusColor(s) {
    switch (s) {
      case 'pending_payment': return '#F59E0B';
      case 'paid': return '#3B82F6';
      case 'shipped': return '#8B5CF6';
      case 'completed': return '#10B981';
      case 'cancelled': return '#EF4444';
      default: return '#64748B';
    }
  }
  function num(v) { return (typeof v === 'number') ? v : (parseFloat(v) || 0); }
  function fmtDate(v) {
    if (!v) return '-';
    const d = new Date(v);
    if (isNaN(d.getTime())) return '-';
    const pad = n => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function escapeHtml(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }
  function escapeAttr(s) { return escapeHtml(s); }
})();
