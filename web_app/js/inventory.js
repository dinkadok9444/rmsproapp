/* Inventory — read-only port of lib/screens/modules/inventory_screen.dart
   Wraps: stock_screen.dart (SPAREPART), accessories_screen.dart (ACCESSORIES),
          phone_stock_screen.dart (TELEFON). */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();

  const $ = id => document.getElementById(id);
  const state = {
    segment: 'SPAREPART',
    filterStatus: 'ALL',
    filterCategory: 'ALL',
    filterModel: 'ALL',
    filterSort: 'DESC',
    search: '',
    sparepart: [],
    accessories: [],
    phone: [],
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
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;');
  }
  function num(v) { return Number(v) || 0; }

  // ---- listeners ----
  // SPAREPART — inventory_$owner (dart stock_screen: tiada filter shopID)
  db.collection('inventory_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      out.push({
        id: doc.id,
        kod: d.kod || '-',
        nama: d.nama || '-',
        category: d.category || '',
        qty: num(d.qty),
        kos: num(d.kos),
        jual: num(d.jual),
        status: String(d.status || 'AVAILABLE').toUpperCase(),
        tarikhMasuk: d.tarikh_masuk || '',
        tkhJual: d.tkh_jual || '',
        siriJual: d.no_siri_jual || '',
        supplier: d.supplier || '',
        timestamp: tsMs(d.timestamp),
      });
    });
    state.sparepart = out;
    if (state.segment === 'SPAREPART') render();
  }, err => console.warn('inventory:', err));

  // ACCESSORIES — accessories_$owner (dart accessories_screen: tiada filter shopID)
  db.collection('accessories_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      out.push({
        id: doc.id,
        kod: d.kod || '-',
        nama: d.nama || '-',
        category: d.category || '',
        qty: num(d.qty),
        kos: num(d.kos),
        jual: num(d.jual),
        status: String(d.status || 'AVAILABLE').toUpperCase(),
        tarikhMasuk: d.tarikh_masuk || '',
        tkhJual: d.tkh_jual || '',
        siriJual: d.no_siri_jual || '',
        supplier: d.supplier || '',
        timestamp: tsMs(d.timestamp),
      });
    });
    state.accessories = out;
    if (state.segment === 'ACCESSORIES') render();
  }, err => console.warn('accessories:', err));

  // TELEFON — phone_stock_$owner, filtered by shopID + not SOLD
  db.collection('phone_stock_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      if (String(d.status || '').toUpperCase() === 'SOLD') return;
      out.push({
        id: doc.id,
        kod: d.kod || '-',
        nama: d.nama || '-',
        imei: d.imei || '-',
        warna: d.warna || '',
        storage: d.storage || '',
        kategori: String(d.kategori || '').toUpperCase(),
        supplier: d.supplier || '',
        kos: num(d.kos),
        jual: num(d.jual),
        status: String(d.status || 'AVAILABLE').toUpperCase(),
        timestamp: tsMs(d.timestamp),
      });
    });
    state.phone = out;
    if (state.segment === 'TELEFON') render();
  }, err => console.warn('phone_stock:', err));

  // ---- filters / render ----
  function currentList() {
    if (state.segment === 'SPAREPART') return state.sparepart;
    if (state.segment === 'ACCESSORIES') return state.accessories;
    return state.phone;
  }

  function rebuildCategoryOptions() {
    const isPhone = state.segment === 'TELEFON';
    const cats = new Set();
    currentList().forEach(d => {
      const c = isPhone ? d.kategori : d.category;
      if (c) cats.add(String(c).toUpperCase());
    });
    const sel = $('fCategory');
    const prev = state.filterCategory;
    const opts = ['<option value="ALL">Semua</option>']
      .concat([...cats].sort().map(c => `<option value="${esc(c)}">${esc(c)}</option>`));
    sel.innerHTML = opts.join('');
    sel.value = [...cats].includes(prev) || prev === 'ALL' ? prev : 'ALL';
    state.filterCategory = sel.value;
  }

  function rebuildModelOptions() {
    if (state.segment !== 'TELEFON') return;
    const models = new Set();
    state.phone.forEach(d => { if (d.nama && d.nama !== '-') models.add(String(d.nama).toUpperCase()); });
    const sel = $('fModel');
    const prev = state.filterModel;
    const opts = ['<option value="ALL">Semua</option>']
      .concat([...models].sort().map(m => `<option value="${esc(m)}">${esc(m)}</option>`));
    sel.innerHTML = opts.join('');
    sel.value = [...models].includes(prev) || prev === 'ALL' ? prev : 'ALL';
    state.filterModel = sel.value;
  }

  function applyFilters(arr) {
    const isPhone = state.segment === 'TELEFON';
    let out = arr.slice();
    if (state.filterStatus !== 'ALL') {
      out = out.filter(r => r.status === state.filterStatus
        || (state.filterStatus === 'AVAILABLE' && !['TERJUAL','RETURNED','USED'].includes(r.status)));
    }
    if (state.filterCategory !== 'ALL') {
      out = out.filter(r => {
        const c = isPhone ? r.kategori : r.category;
        return String(c || '').toUpperCase() === state.filterCategory;
      });
    }
    if (isPhone && state.filterModel !== 'ALL') {
      out = out.filter(r => String(r.nama || '').toUpperCase() === state.filterModel);
    }
    const q = state.search.toLowerCase().trim();
    if (q) {
      out = out.filter(r => {
        const fields = isPhone
          ? [r.kod, r.nama, r.imei, r.warna, r.storage, r.supplier]
          : [r.kod, r.nama, r.siriJual, r.supplier];
        return fields.some(f => String(f || '').toLowerCase().includes(q));
      });
    }
    out.sort((a,b) => state.filterSort === 'DESC'
      ? (b.timestamp||0) - (a.timestamp||0)
      : (a.timestamp||0) - (b.timestamp||0));
    return out;
  }

  function render() {
    rebuildCategoryOptions();
    const phoneRow = document.querySelector('.inv-phone-only');
    if (phoneRow) phoneRow.hidden = state.segment !== 'TELEFON';
    if (state.segment === 'TELEFON') rebuildModelOptions();

    const titleMap = {
      SPAREPART: 'Senarai Sparepart',
      ACCESSORIES: 'Senarai Accessories',
      TELEFON: 'Senarai Telefon',
    };
    $('listTitle').textContent = titleMap[state.segment];

    const arr = applyFilters(currentList());

    // stats
    const items = arr.length;
    const isPhone = state.segment === 'TELEFON';
    const totalQty = isPhone ? items : arr.reduce((s, r) => s + (r.qty || 0), 0);
    const totalValue = isPhone
      ? arr.reduce((s, r) => s + r.jual, 0)
      : arr.reduce((s, r) => s + r.jual * (r.qty || 0), 0);
    const low = isPhone ? 0 : arr.filter(r => (r.qty || 0) <= 2 && r.status === 'AVAILABLE').length;

    $('stItems').textContent = items;
    $('stQty').textContent = totalQty;
    $('stValue').textContent = fmtMoney(totalValue);
    $('stLow').textContent = low;

    $('invEmpty').hidden = arr.length > 0;
    $('invList').innerHTML = arr.map(r => isPhone ? renderPhoneCard(r) : renderStockCard(r)).join('');
  }

  function statusBadge(status) {
    const key = status.toLowerCase();
    const label = status || 'AVAILABLE';
    return `<span class="inv-item__badge inv-item__badge--st-${esc(key)}">${esc(label)}</span>`;
  }

  function renderStockCard(r) {
    const low = r.qty <= 2 && r.status === 'AVAILABLE';
    const catBadge = r.category
      ? `<span class="inv-item__badge inv-item__badge--cat">${esc(r.category)}</span>` : '';
    const metaParts = [];
    if (r.tarikhMasuk) metaParts.push(`<span><i class="fas fa-arrow-down"></i> Masuk: ${esc(r.tarikhMasuk)}</span>`);
    if (r.tkhJual) metaParts.push(`<span><i class="fas fa-arrow-up"></i> Jual: ${esc(r.tkhJual)}</span>`);
    if (r.siriJual) metaParts.push(`<span><i class="fas fa-hashtag"></i> ${esc(r.siriJual)}</span>`);
    if (r.supplier) metaParts.push(`<span><i class="fas fa-truck"></i> ${esc(r.supplier)}</span>`);
    return `
      <div class="inv-item ${low ? 'is-low' : ''}">
        <div class="inv-item__qty">${r.qty}</div>
        <div class="inv-item__main">
          <div class="inv-item__head">
            <span class="inv-item__kod">${esc(r.kod)}</span>
            ${catBadge}
            ${statusBadge(r.status || 'AVAILABLE')}
          </div>
          <div class="inv-item__title">${esc(r.nama)}</div>
          <div class="inv-item__meta">${metaParts.join('')}</div>
        </div>
        <div class="inv-item__price">${fmtMoney(r.jual)}</div>
      </div>`;
  }

  function renderPhoneCard(r) {
    const catBadge = r.kategori
      ? `<span class="inv-item__badge inv-item__badge--cat">${esc(r.kategori)}</span>` : '';
    const specs = [r.warna, r.storage].filter(Boolean).map(esc).join(' • ');
    const metaParts = [];
    metaParts.push(`<span><i class="fas fa-barcode"></i> IMEI: ${esc(r.imei)}</span>`);
    if (r.supplier) metaParts.push(`<span><i class="fas fa-truck"></i> ${esc(r.supplier)}</span>`);
    return `
      <div class="inv-item">
        <div class="inv-item__qty"><i class="fas fa-mobile-screen-button" style="font-size:18px;"></i></div>
        <div class="inv-item__main">
          <div class="inv-item__head">
            <span class="inv-item__kod">${esc(r.kod)}</span>
            ${catBadge}
            ${statusBadge(r.status || 'AVAILABLE')}
          </div>
          <div class="inv-item__title">${esc(r.nama)}${specs ? ' — ' + specs : ''}</div>
          <div class="inv-item__meta">${metaParts.join('')}</div>
        </div>
        <div class="inv-item__price">${fmtMoney(r.jual)}</div>
      </div>`;
  }

  // ---- events ----
  $('invSegment').addEventListener('click', e => {
    const b = e.target.closest('.inv-seg-btn');
    if (!b) return;
    state.segment = b.dataset.seg;
    state.filterCategory = 'ALL';
    state.filterModel = 'ALL';
    document.querySelectorAll('.inv-seg-btn').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('fStatus').addEventListener('change', e => { state.filterStatus = e.target.value; render(); });
  $('fCategory').addEventListener('change', e => { state.filterCategory = e.target.value; render(); });
  $('fModel').addEventListener('change', e => { state.filterModel = e.target.value; render(); });
  $('fSort').addEventListener('change', e => { state.filterSort = e.target.value; render(); });
  $('fSearch').addEventListener('input', e => { state.search = e.target.value; render(); });

  render();
})();
