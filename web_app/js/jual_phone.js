/* Jualan Telefon — port lib/screens/modules/jual_telefon_screen.dart (read-only) */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();

  const $ = id => document.getElementById(id);
  const state = {
    segment: 'CUSTOMER',   // CUSTOMER | DEALER
    tab: 'ACTIVE',         // ACTIVE | ARCHIVED | DELETED
    filterTime: 'SEMUA',
    search: '',
    all: [],               // all phone_receipts
  };

  const fmtMoney = n => 'RM ' + (Number(n) || 0).toFixed(2);
  const num = v => Number(v) || 0;
  function tsMs(v) {
    if (v == null) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') { const n = Number(v); return Number.isNaN(n) ? 0 : n; }
    if (v && typeof v.toMillis === 'function') return v.toMillis();
    if (v && v.seconds != null) return v.seconds * 1000;
    return 0;
  }
  function fmtDate(ms) {
    if (!ms) return '-';
    const d = new Date(ms);
    const pad = n => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function timeStart() {
    const now = new Date();
    const start = new Date(now); start.setHours(0,0,0,0);
    switch (state.filterTime) {
      case 'HARI INI': return start.getTime();
      case 'MINGGU INI': {
        const dow = start.getDay(); const diff = (dow + 6) % 7;
        start.setDate(start.getDate() - diff); return start.getTime();
      }
      case 'BULAN INI': start.setDate(1); return start.getTime();
      case 'TAHUN INI': start.setMonth(0, 1); return start.getTime();
      default: return 0;
    }
  }

  function itemsContainQuery(items, q) {
    if (!Array.isArray(items)) return false;
    for (const it of items) {
      if (it && typeof it === 'object') {
        if (String(it.imei || '').toLowerCase().includes(q)) return true;
        if (String(it.nama || '').toLowerCase().includes(q)) return true;
      }
    }
    return false;
  }

  // ---- listener ----
  db.collection('phone_receipts_' + ownerID)
    .orderBy('timestamp', 'desc')
    .onSnapshot(snap => {
      const all = [];
      snap.forEach(doc => {
        const d = doc.data() || {};
        if (String(d.shopID || '').toUpperCase() !== shopID) return;
        all.push({ _id: doc.id, ...d, timestamp: tsMs(d.timestamp) });
      });
      state.all = all;
      render();
    }, err => console.warn('phone_receipts:', err));

  function filtered() {
    const tStart = timeStart();
    const q = state.search.toLowerCase().trim();
    return state.all.filter(d => {
      const status = String(d.billStatus || 'ACTIVE').toUpperCase();
      if (status !== state.tab) return false;
      const type = String(d.saleType || 'CUSTOMER').toUpperCase();
      if (type !== state.segment) return false;
      if (d.timestamp < tStart) return false;
      if (q) {
        const hit =
          String(d.phoneName || '').toLowerCase().includes(q) ||
          String(d.custName || '').toLowerCase().includes(q) ||
          String(d.custPhone || '').toLowerCase().includes(q) ||
          String(d.siri || '').toLowerCase().includes(q) ||
          String(d.dealerName || '').toLowerCase().includes(q) ||
          itemsContainQuery(d.items, q);
        if (!hit) return false;
      }
      return true;
    });
  }

  function render() {
    const arr = filtered();
    $('listTitle').textContent = state.tab === 'ACTIVE' ? 'Senarai Bil Aktif'
      : state.tab === 'ARCHIVED' ? 'Senarai Bil Arkib' : 'Senarai Bil Padam';

    const list = $('jpList');
    $('jpEmpty').hidden = arr.length > 0;
    list.innerHTML = arr.map(r => {
      const isDealer = String(r.saleType || 'CUSTOMER').toUpperCase() === 'DEALER';
      const cls = [
        isDealer ? 'jp-item--dealer' : '',
        state.tab === 'ARCHIVED' ? 'jp-item--archived' : '',
        state.tab === 'DELETED' ? 'jp-item--deleted' : '',
      ].filter(Boolean).join(' ');
      const party = isDealer
        ? `${esc(r.dealerName || '-')}${r.dealerKedai ? ' (' + esc(r.dealerKedai) + ')' : ''}`
        : `${esc(r.custName || '-')} • ${esc(r.custPhone || '-')}`;
      const pill = state.tab === 'ARCHIVED' ? '<span class="jp-pill jp-pill--archived">Arkib</span>'
        : state.tab === 'DELETED' ? '<span class="jp-pill jp-pill--deleted">Padam</span>'
        : `<span class="jp-pill">${isDealer ? 'Dealer' : 'Customer'}</span>`;
      const warranty = r.warranty ? ` • Waranti: ${esc(r.warranty)}` : '';
      const term = r.paymentTerm ? ` • Terma: ${esc(r.paymentTerm)}` : '';
      return `
        <div class="jp-item ${cls}">
          <div class="jp-item__badge"><i class="fas fa-mobile-screen"></i></div>
          <div class="jp-item__main">
            <div class="jp-item__title">${esc(r.phoneName || '-')} ${pill}</div>
            <div class="jp-item__sub">#${esc(r.siri || r._id)} • ${party}${warranty}${term}</div>
            <div class="jp-item__meta">
              <span><i class="fas fa-user"></i> ${esc(r.staffName || '-')}</span>
              <span><i class="fas fa-credit-card"></i> ${esc(r.paymentMethod || '-')}</span>
              <span><i class="fas fa-clock"></i> ${fmtDate(r.timestamp)}</span>
            </div>
          </div>
          <div class="jp-item__amount">${fmtMoney(r.sellPrice)}</div>
        </div>`;
    }).join('');
  }

  // ---- events ----
  $('jpSegment').addEventListener('click', e => {
    const b = e.target.closest('.jp-seg-btn'); if (!b) return;
    state.segment = b.dataset.seg;
    document.querySelectorAll('.jp-seg-btn').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('jpTabs').addEventListener('click', e => {
    const b = e.target.closest('.jp-tab-btn'); if (!b) return;
    state.tab = b.dataset.tab;
    document.querySelectorAll('.jp-tab-btn').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('fTime').addEventListener('change', e => { state.filterTime = e.target.value; render(); });
  $('fSearch').addEventListener('input', e => { state.search = e.target.value; render(); });

  render();
})();
