/* Kewangan — port lib/screens/modules/kewangan_screen.dart (read-only subset) */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();

  const $ = id => document.getElementById(id);
  const state = {
    segment: 0, // 0 kewangan, 1 phone sales
    filterTime: 'TODAY',
    filterSort: 'DESC',
    search: '',
    phoneType: 'CUSTOMER',
    sources: {},          // key => array of records
    phoneSales: [],
  };

  // ---- helpers ----
  const fmtMoney = n => 'RM ' + (Number(n) || 0).toFixed(2);
  function tsMs(v) {
    if (v == null) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') {
      const n = Number(v);
      if (!Number.isNaN(n)) return n;
      const d = Date.parse(v); return Number.isNaN(d) ? 0 : d;
    }
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
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;');
  }
  function num(v) { return Number(v) || 0; }

  function timeRange() {
    const now = new Date();
    const start = new Date(now);
    start.setHours(0,0,0,0);
    switch (state.filterTime) {
      case 'TODAY': return [start.getTime(), Number.MAX_SAFE_INTEGER];
      case 'WEEK': {
        const dow = start.getDay(); // 0 Sun
        const diff = (dow + 6) % 7; // Monday start
        start.setDate(start.getDate() - diff);
        return [start.getTime(), Number.MAX_SAFE_INTEGER];
      }
      case 'MONTH': {
        start.setDate(1); return [start.getTime(), Number.MAX_SAFE_INTEGER];
      }
      case 'YEAR': {
        start.setMonth(0, 1); return [start.getTime(), Number.MAX_SAFE_INTEGER];
      }
      case 'ALL': return [0, Number.MAX_SAFE_INTEGER];
    }
    return [0, Number.MAX_SAFE_INTEGER];
  }

  // ---- data merge ----
  function mergeRecords(key, recs) {
    state.sources[key] = recs;
    render();
  }

  function allRecords() {
    const arr = [];
    for (const k in state.sources) arr.push(...state.sources[k]);
    return arr;
  }

  // ---- listeners ----
  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      if (String(d.payment_status || '').toUpperCase() !== 'PAID') return;
      const nama = String(d.nama || '').toUpperCase();
      const jenis = String(d.jenis_servis || '').toUpperCase();
      if (nama === 'JUALAN PANTAS' || jenis === 'JUALAN') return;
      out.push({
        docId: doc.id, siri: d.siri || doc.id,
        jenis: 'RETAIL', jenisLabel: 'SALES REPAIR',
        nama: d.nama || '-', tel: d.tel || '-',
        item: d.model || d.kerosakan || '-',
        jumlah: num(d.total),
        cara: d.cara_bayaran || 'CASH',
        staff: d.staff_repair || d.staff_terima || '-',
        timestamp: tsMs(d.paid_at || d.timestamp),
        isExpense: false,
      });
    });
    mergeRecords('REPAIR', out);
  }, err => console.warn('repairs:', err));

  const receiverCode = `${ownerID}@${shopID}`.toLowerCase();
  db.collection('collab_global_network')
    .where('receiver', '==', receiverCode)
    .onSnapshot(snap => {
      const out = [];
      snap.forEach(doc => {
        const d = doc.data() || {};
        if (String(d.payment_status || '').toUpperCase() !== 'PAID') return;
        out.push({
          docId: doc.id, siri: d.siri || doc.id,
          jenis: 'PRO_ONLINE', jenisLabel: 'PRO DEALER',
          nama: d.namaCust || d.nama || '-',
          tel: d.telCust || d.tel || '-',
          item: d.model || d.kerosakan || '-',
          jumlah: num(d.total),
          cara: d.cara_bayaran || 'ONLINE',
          staff: d.staff_repair || d.sender || '-',
          timestamp: tsMs(d.timestamp),
          isExpense: false,
        });
      });
      mergeRecords('COLLAB', out);
    }, err => console.warn('collab:', err));

  db.collection('pro_walkin_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      if (String(d.payment_status || '').toUpperCase() !== 'PAID') return;
      out.push({
        docId: doc.id, siri: d.siri || doc.id,
        jenis: 'PRO_OFFLINE', jenisLabel: 'PRO DEALER',
        nama: d.namaCust || d.nama || '-',
        tel: d.telCust || d.tel || '-',
        item: d.model || d.kerosakan || '-',
        jumlah: num(d.total),
        cara: d.cara_bayaran || 'CASH',
        staff: d.staff_repair || d.staff_terima || '-',
        timestamp: tsMs(d.timestamp),
        isExpense: false,
      });
    });
    mergeRecords('PRO_WALKIN', out);
  }, err => console.warn('pro_walkin:', err));

  db.collection('expenses_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      if (d.archived === true) return;
      out.push({
        docId: doc.id, siri: doc.id,
        jenis: 'EXPENSE', jenisLabel: 'DUIT KELUAR',
        nama: d.perkara || '-', tel: '-',
        item: d.perkara || '-',
        jumlah: num(d.jumlah ?? d.amaun),
        cara: '-',
        staff: d.staff || d.staf || '-',
        timestamp: tsMs(d.timestamp),
        isExpense: true,
      });
    });
    mergeRecords('EXPENSE', out);
  }, err => console.warn('expenses:', err));

  db.collection('jualan_pantas_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      if (String(d.payment_status || '').toUpperCase() !== 'PAID') return;
      if (String(d.nama || '').toUpperCase() === 'JUALAN TELEFON') return;
      out.push({
        docId: doc.id, siri: d.siri || doc.id,
        jenis: 'PANTAS', jenisLabel: 'QUICK SALES',
        nama: d.nama || 'QUICK SALES', tel: d.tel || '-',
        item: d.item || d.model || d.perkara || '-',
        jumlah: num(d.total),
        cara: d.cara_bayaran || 'CASH',
        staff: d.staff || d.staff_terima || '-',
        timestamp: tsMs(d.timestamp),
        isExpense: false,
      });
    });
    mergeRecords('PANTAS', out);
  }, err => console.warn('jualan_pantas:', err));

  db.collection('phone_sales_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      out.push({
        docId: doc.id,
        kod: d.kod || '-',
        nama: d.nama || '-',
        imei: d.imei || '-',
        warna: d.warna || '-',
        storage: d.storage || '-',
        jual: num(d.jual),
        siri: d.siri || '-',
        staffJual: d.staffJual || d.staffName || '-',
        timestamp: tsMs(d.timestamp),
        saleType: String(d.saleType || 'CUSTOMER').toUpperCase(),
        custName: d.custName || '-',
        custPhone: d.custPhone || '-',
        dealerName: d.dealerName || '',
        dealerKedai: d.dealerKedai || '',
      });
    });
    out.sort((a,b) => (b.timestamp||0) - (a.timestamp||0));
    state.phoneSales = out;
    render();
  }, err => console.warn('phone_sales:', err));

  // ---- render ----
  function render() {
    const phoneOnlyRow = document.querySelector('.kw-phone-only');
    if (phoneOnlyRow) phoneOnlyRow.hidden = state.segment !== 1;
    $('listTitle').textContent = state.segment === 1 ? 'Senarai Jualan Telefon' : 'Senarai Rekod';

    if (state.segment === 1) return renderPhoneSales();
    renderKewangan();
  }

  function renderKewangan() {
    let arr = allRecords();
    const [tStart, tEnd] = timeRange();
    arr = arr.filter(r => r.timestamp >= tStart && r.timestamp <= tEnd);
    const q = state.search.toLowerCase().trim();
    if (q) {
      arr = arr.filter(r =>
        String(r.nama).toLowerCase().includes(q) ||
        String(r.siri).toLowerCase().includes(q) ||
        String(r.item).toLowerCase().includes(q) ||
        String(r.staff).toLowerCase().includes(q)
      );
    }
    arr.sort((a,b) => state.filterSort === 'DESC'
      ? (b.timestamp||0) - (a.timestamp||0)
      : (a.timestamp||0) - (b.timestamp||0));

    // stats
    let sales = 0, expense = 0;
    arr.forEach(r => { if (r.isExpense) expense += r.jumlah; else sales += r.jumlah; });
    $('stSales').textContent = fmtMoney(sales);
    $('stExpense').textContent = fmtMoney(expense);
    $('stNet').textContent = fmtMoney(sales - expense);
    $('stCount').textContent = arr.length;

    const list = $('kwList');
    $('kwEmpty').hidden = arr.length > 0;
    list.innerHTML = arr.map(r => {
      const cls = r.isExpense ? 'kw-item--expense'
        : (r.jenis === 'PRO_ONLINE' || r.jenis === 'PRO_OFFLINE') ? 'kw-item--pro'
        : r.jenis === 'PANTAS' ? 'kw-item--pantas' : '';
      const icon = r.isExpense ? 'fa-money-bill-transfer'
        : r.jenis === 'PANTAS' ? 'fa-bolt'
        : (r.jenis === 'PRO_ONLINE' || r.jenis === 'PRO_OFFLINE') ? 'fa-handshake'
        : 'fa-screwdriver-wrench';
      const sign = r.isExpense ? '-' : '+';
      return `
        <div class="kw-item ${cls}">
          <div class="kw-item__badge"><i class="fas ${icon}"></i></div>
          <div class="kw-item__main">
            <div class="kw-item__title">${esc(r.nama)} — ${esc(r.item)}</div>
            <div class="kw-item__sub">#${esc(r.siri)} • ${esc(r.jenisLabel)}</div>
            <div class="kw-item__meta">
              <span><i class="fas fa-user"></i> ${esc(r.staff)}</span>
              <span><i class="fas fa-credit-card"></i> ${esc(r.cara)}</span>
              <span><i class="fas fa-clock"></i> ${fmtDate(r.timestamp)}</span>
            </div>
          </div>
          <div class="kw-item__amount">${sign} ${fmtMoney(r.jumlah)}</div>
        </div>`;
    }).join('');
  }

  function renderPhoneSales() {
    let arr = state.phoneSales.filter(d => (d.saleType || 'CUSTOMER') === state.phoneType);
    const [tStart, tEnd] = timeRange();
    arr = arr.filter(r => r.timestamp >= tStart && r.timestamp <= tEnd);
    const q = state.search.toLowerCase().trim();
    if (q) {
      arr = arr.filter(r =>
        String(r.nama).toLowerCase().includes(q) ||
        String(r.imei).toLowerCase().includes(q) ||
        String(r.kod).toLowerCase().includes(q) ||
        String(r.custName).toLowerCase().includes(q) ||
        String(r.dealerName).toLowerCase().includes(q)
      );
    }
    arr.sort((a,b) => state.filterSort === 'DESC'
      ? (b.timestamp||0) - (a.timestamp||0)
      : (a.timestamp||0) - (b.timestamp||0));

    let total = 0;
    arr.forEach(r => total += r.jual);
    $('stSales').textContent = fmtMoney(total);
    $('stExpense').textContent = 'RM 0.00';
    $('stNet').textContent = fmtMoney(total);
    $('stCount').textContent = arr.length;

    const list = $('kwList');
    $('kwEmpty').hidden = arr.length > 0;
    list.innerHTML = arr.map(r => {
      const party = state.phoneType === 'DEALER'
        ? `${esc(r.dealerName || '-')} (${esc(r.dealerKedai || '-')})`
        : `${esc(r.custName || '-')} • ${esc(r.custPhone || '-')}`;
      return `
        <div class="kw-item kw-item--phone">
          <div class="kw-item__badge"><i class="fas fa-mobile-screen"></i></div>
          <div class="kw-item__main">
            <div class="kw-item__title">${esc(r.nama)} — ${esc(r.warna)} ${esc(r.storage)}</div>
            <div class="kw-item__sub">IMEI: ${esc(r.imei)} • Kod: ${esc(r.kod)}</div>
            <div class="kw-item__meta">
              <span><i class="fas fa-user"></i> ${esc(r.staffJual)}</span>
              <span><i class="fas fa-user-tag"></i> ${party}</span>
              <span><i class="fas fa-clock"></i> ${fmtDate(r.timestamp)}</span>
            </div>
          </div>
          <div class="kw-item__amount">+ ${fmtMoney(r.jual)}</div>
        </div>`;
    }).join('');
  }

  // ---- events ----
  $('kwSegment').addEventListener('click', e => {
    const b = e.target.closest('.kw-seg-btn');
    if (!b) return;
    state.segment = Number(b.dataset.seg);
    document.querySelectorAll('.kw-seg-btn').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('fTime').addEventListener('change', e => { state.filterTime = e.target.value; render(); });
  $('fSort').addEventListener('change', e => { state.filterSort = e.target.value; render(); });
  $('fSearch').addEventListener('input', e => { state.search = e.target.value; render(); });
  $('fPhoneType').addEventListener('change', e => { state.phoneType = e.target.value; render(); });

  render();
})();
