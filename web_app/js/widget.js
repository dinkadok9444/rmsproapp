/* Port dari lib/screens/modules/dashboard_widget_screen.dart (tanpa Quick Sales) */
(function () {
  'use strict';
  if (!document.getElementById('wgQuote')) return;

  let ownerID = 'admin', shopID = 'MAIN';
  let filterStats = 'TODAY', filterKew = 'TODAY';
  let repairs = [], jualanPantas = [], expenses = [];
  let bateriResults = [], lcdResults = [];
  let activeTab = 'bateri';

  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0]; shopID = (p[1] || '').toUpperCase();
  }

  const $ = id => document.getElementById(id);

  // ─── Range ───
  function getRange(period) {
    const now = new Date();
    let start;
    switch (period) {
      case 'TODAY': start = new Date(now.getFullYear(), now.getMonth(), now.getDate()); break;
      case 'WEEK': {
        const d = new Date(now); d.setDate(now.getDate() - (now.getDay() % 7));
        start = new Date(d.getFullYear(), d.getMonth(), d.getDate()); break;
      }
      case 'MONTH': start = new Date(now.getFullYear(), now.getMonth(), 1); break;
      case 'YEAR':  start = new Date(now.getFullYear(), 0, 1); break;
      default:      start = new Date(2020, 0, 1);
    }
    return [start.getTime(), now.getTime()];
  }

  // ─── Listeners ───
  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.id = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    repairs = arr;
    updateStats(); updateKewangan();
  }, e => console.warn('repairs:', e));

  db.collection('jualan_pantas_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.id = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    jualanPantas = arr;
    updateKewangan();
  }, e => console.warn('jualan_pantas:', e));

  db.collection('expenses_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.id = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    expenses = arr;
    updateKewangan();
  }, e => console.warn('expenses:', e));

  // Quote
  db.collection('system_settings').doc('pengumuman').get().then(doc => {
    if (doc.exists) {
      const m = (doc.data() || {}).motivasi || 'Konsisten adalah kunci kejayaan.';
      $('wgQuote').textContent = '"' + m + '"';
    }
  }).catch(() => {});

  // ─── Stats ───
  function updateStats() {
    const [s, e] = getRange(filterStats);
    const arr = repairs.filter(d => {
      const ts = Number(d.timestamp || 0);
      const nama = String(d.nama || '').toUpperCase();
      const jenis = String(d.jenis_servis || '').toUpperCase();
      return ts >= s && ts <= e && nama !== 'JUALAN PANTAS' && nama !== 'QUICK SALES' && jenis !== 'JUALAN';
    });
    $('wgStTotal').textContent = arr.length;
    $('wgStProg').textContent  = arr.filter(d => up(d.status) === 'IN PROGRESS').length;
    $('wgStWait').textContent  = arr.filter(d => up(d.status) === 'WAITING PART').length;
    $('wgStReady').textContent = arr.filter(d => up(d.status) === 'READY TO PICKUP').length;
    $('wgStComp').textContent  = arr.filter(d => up(d.status) === 'COMPLETED').length;
    $('wgStCancel').textContent = arr.filter(d => { const u = up(d.status); return u === 'CANCEL' || u === 'CANCELLED'; }).length;
  }

  // ─── Kewangan ───
  function updateKewangan() {
    const [s, e] = getRange(filterKew);
    let sales = 0, refund = 0, exp = 0;

    for (const d of repairs) {
      const ts = Number(d.timestamp || 0);
      if (ts < s || ts > e) continue;
      if (up(d.payment_status) !== 'PAID') continue;
      const total = parseFloat(d.total) || 0;
      const st = up(d.status);
      if (st === 'CANCEL' || st === 'CANCELLED' || st === 'REFUND') refund += total;
      else sales += total;
    }
    for (const d of jualanPantas) {
      const ts = Number(d.timestamp || 0);
      if (ts < s || ts > e) continue;
      if (up(d.payment_status) !== 'PAID') continue;
      const total = parseFloat(d.total) || 0;
      const siri = String(d.siri || '');
      const dup = repairs.some(r => String(r.siri || '') === siri);
      if (!dup) sales += total;
    }
    for (const d of expenses) {
      const ts = Number(d.timestamp || 0);
      if (ts < s || ts > e) continue;
      exp += parseFloat(d.amount) || 0;
    }

    $('wgKwSales').textContent  = 'RM ' + sales.toFixed(2);
    $('wgKwRefund').textContent = 'RM ' + refund.toFixed(2);
    $('wgKwExp').textContent    = 'RM ' + exp.toFixed(2);
    $('wgKwNet').textContent    = 'RM ' + (sales - refund - exp).toFixed(2);
  }

  $('wgStatsFilter').addEventListener('change', e => { filterStats = e.target.value; updateStats(); });
  $('wgKewFilter').addEventListener('change', e => { filterKew = e.target.value; updateKewangan(); });

  // ─── Komponen search ───
  $('wgKompBtn').addEventListener('click', searchKomponen);
  $('wgKompInput').addEventListener('keydown', e => { if (e.key === 'Enter') searchKomponen(); });
  document.querySelectorAll('.wg-komp-tab').forEach(b => b.addEventListener('click', () => {
    activeTab = b.dataset.tab;
    document.querySelectorAll('.wg-komp-tab').forEach(x => x.classList.toggle('is-active', x === b));
    renderKomponen();
  }));

  async function searchKomponen() {
    const q = $('wgKompInput').value.trim().toLowerCase();
    if (!q) return;
    const box = $('wgKompResults');
    box.innerHTML = '<div class="wg-komp-empty"><i class="fas fa-spinner fa-spin"></i><div>Mencari…</div></div>';
    try {
      const [snapBat, snapLcd] = await Promise.all([
        db.collection('database_bateri_admin').get(),
        db.collection('database_lcd_admin').get(),
      ]);
      const matches = (d) => {
        const m = String(d.model || '').toLowerCase();
        const k = String(d.kod || '').toLowerCase();
        const i = String(d.info || '').toLowerCase();
        return m.includes(q) || k.includes(q) || i.includes(q);
      };
      bateriResults = []; lcdResults = [];
      snapBat.forEach(doc => { const d = doc.data(); if (matches(d)) bateriResults.push(d); });
      snapLcd.forEach(doc => { const d = doc.data(); if (matches(d)) lcdResults.push(d); });
      $('wgBatCount').textContent = bateriResults.length;
      $('wgLcdCount').textContent = lcdResults.length;
      renderKomponen();
    } catch (err) {
      box.innerHTML = `<div class="wg-komp-empty"><i class="fas fa-triangle-exclamation"></i><div>Ralat: ${escHtml(err.message)}</div></div>`;
    }
  }

  function renderKomponen() {
    const box = $('wgKompResults');
    const arr = activeTab === 'bateri' ? bateriResults : lcdResults;
    if (!arr.length) {
      box.innerHTML = '<div class="wg-komp-empty"><i class="fas fa-circle-info"></i><div>Tiada keputusan. Tekan Cari.</div></div>';
      return;
    }
    box.innerHTML = arr.map(d => `
      <div class="wg-komp-row">
        <div class="wg-komp-row__model">${escHtml(d.model || '-')}</div>
        <div class="wg-komp-row__meta">
          <span class="wg-komp-row__kod">${escHtml(d.kod || '-')}</span>
          ${d.info ? `<span class="wg-komp-row__info">${escHtml(d.info)}</span>` : ''}
        </div>
      </div>
    `).join('');
  }

  // Helpers
  function up(s) { return String(s || '').toUpperCase(); }
  function escHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  updateStats();
  updateKewangan();

  // ─── Navigate to other modules (sambung ke Kewangan & Senarai Job) ───
  function gotoModule(id, hint) {
    try {
      if (hint) localStorage.setItem('_pending_' + id, JSON.stringify(hint));
      const parentDoc = window.parent && window.parent.document;
      if (!parentDoc) return;
      const tile = parentDoc.querySelector(`.branch-tile[data-module="${id}"]`);
      if (tile) tile.click();
    } catch (e) { console.warn('gotoModule:', e); }
  }

  // Stat cards → Senarai Job dengan filter status
  const statMap = {
    wgStTotal:  'ALL',
    wgStProg:   'IN PROGRESS',
    wgStWait:   'WAITING PART',
    wgStReady:  'READY TO PICKUP',
    wgStComp:   'COMPLETED',
    wgStCancel: 'CANCEL',
  };
  Object.keys(statMap).forEach(id => {
    const el = $(id);
    if (!el) return;
    const card = el.closest('.wg-stat');
    if (!card) return;
    card.classList.add('is-clickable');
    card.addEventListener('click', () => gotoModule('Senarai_job', { status: statMap[id] }));
  });

  // Kewangan cards → Kewangan module
  document.querySelectorAll('.wg-kew__card').forEach(card => {
    card.classList.add('is-clickable');
    card.addEventListener('click', () => gotoModule('Kewangan', { range: filterKew }));
  });
})();
