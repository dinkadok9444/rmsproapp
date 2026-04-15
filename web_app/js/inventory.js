/* inventory.js — Supabase. Combined inventory viewer: spareparts + accessories + phones. Read-only. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  let segment = 'SPAREPART';
  let DATA = { SPAREPART: [], FAST_SERVICE: [], ACCESSORIES: [], TELEFON: [] };
  const FS_CAT = 'FAST SERVICE';
  let showHistory = false;
  let histFilter = { status: 'ALL', from: '', to: '', q: '' };
  let filters = { status: 'ALL', category: 'ALL', model: 'ALL', sort: 'DESC', search: '' };

  async function fetchAll() {
    const [sp, ac, ph] = await Promise.all([
      window.sb.from('stock_parts').select('*').eq('branch_id', branchId).limit(2000),
      window.sb.from('accessories').select('*').eq('branch_id', branchId).limit(2000),
      window.sb.from('phone_stock').select('*').eq('branch_id', branchId).limit(2000),
    ]);
    const allParts = sp.data || [];
    DATA.FAST_SERVICE = allParts.filter((r) => (r.category || '').toUpperCase() === FS_CAT);
    DATA.SPAREPART = allParts.filter((r) => (r.category || '').toUpperCase() !== FS_CAT);
    DATA.ACCESSORIES = ac.data || [];
    DATA.TELEFON = ph.data || [];
  }

  function isHistoryRow(r) {
    // FAST SERVICE is unlimited — never moves to history
    if ((r.category || '').toUpperCase() === FS_CAT) return false;
    const st = (r.status || 'AVAILABLE').toUpperCase();
    const qty = Number(r.qty) || 0;
    return st !== 'AVAILABLE' || qty <= 0;
  }

  function currentRows() {
    let rows = (DATA[segment] || []).slice();
    rows = rows.filter((r) => showHistory ? isHistoryRow(r) : !isHistoryRow(r));
    if (showHistory) {
      if (histFilter.status !== 'ALL') rows = rows.filter((r) => (r.status || '').toUpperCase() === histFilter.status);
      if (histFilter.from) rows = rows.filter((r) => (r.updated_at || r.created_at || '') >= histFilter.from);
      if (histFilter.to) rows = rows.filter((r) => (r.updated_at || r.created_at || '').slice(0,10) <= histFilter.to);
      const hq = histFilter.q.toLowerCase();
      if (hq) rows = rows.filter((r) => [r.sku, r.part_name, r.item_name, r.device_name, r.no_siri_jual, r.siri].filter(Boolean).join(' ').toLowerCase().includes(hq));
      return rows;
    }
    const q = (filters.search || '').toLowerCase();
    rows = rows.filter((r) => {
      if (filters.status !== 'ALL' && (r.status || 'AVAILABLE').toUpperCase() !== filters.status) return false;
      if (filters.category !== 'ALL' && (r.category || '').toUpperCase() !== filters.category) return false;
      if (segment === 'TELEFON' && filters.model !== 'ALL' && (r.model || r.device_name || '') !== filters.model) return false;
      if (segment === 'FAST_SERVICE' && filters.model !== 'ALL' && (r.model || '') !== filters.model) return false;
      if (q) {
        const hay = [(r.sku||''),(r.part_name||''),(r.item_name||''),(r.device_name||''),(r.model||''),(r.imei||''),(r.siri||'')].join(' ').toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
    rows.sort((a, b) => {
      const ta = a.created_at || '';
      const tb = b.created_at || '';
      return filters.sort === 'ASC' ? ta.localeCompare(tb) : tb.localeCompare(ta);
    });
    return rows;
  }

  function renderStats(rows) {
    const items = rows.length;
    const isPhone = segment === 'TELEFON';
    const qty = rows.reduce((s, r) => s + (Number(r.qty) || (isPhone ? 1 : 0)), 0);
    const value = rows.reduce((s, r) => s + ((Number(r.price) || 0) * (Number(r.qty) || (isPhone ? 1 : 0))), 0);
    const low = rows.filter((r) => !isPhone && (Number(r.qty) || 0) <= 2).length;
    $('stItems').textContent = items;
    $('stQty').textContent = qty;
    $('stValue').textContent = fmtRM(value);
    $('stLow').textContent = low;
  }

  function populateCategoryFilter() {
    const src = DATA[segment] || [];
    const cats = Array.from(new Set(src.map((r) => (r.category || '').toUpperCase()).filter(Boolean)));
    $('fCategory').innerHTML = '<option value="ALL">Semua</option>' + cats.map((c) => `<option value="${c}">${c}</option>`).join('');
    if (segment === 'TELEFON') {
      const models = Array.from(new Set(src.map((r) => r.model || r.device_name || '').filter(Boolean)));
      $('fModel').innerHTML = '<option value="ALL">Semua</option>' + models.map((m) => `<option value="${m}">${m}</option>`).join('');
    }
    document.querySelectorAll('.inv-phone-only').forEach((el) => { el.hidden = segment !== 'TELEFON'; });
  }

  function refresh() {
    const rows = currentRows();
    renderStats(rows);
    const list = $('invList');
    $('invEmpty').hidden = rows.length > 0;
    list.innerHTML = rows.map((r) => {
      const name = r.part_name || r.item_name || r.device_name || r.model || '—';
      const sub = r.sku || r.imei || r.siri || '';
      const qty = segment === 'TELEFON' ? 1 : (Number(r.qty) || 0);
      const isFS = segment === 'FAST_SERVICE';
      const status = (r.status || 'AVAILABLE').toUpperCase();
      const stClass = `inv-item__badge--st-${status.toLowerCase()}`;
      const lowClass = (segment !== 'TELEFON' && qty > 0 && qty <= 3) ? ' is-low' : '';
      const cat = r.category ? `<span class="inv-item__badge inv-item__badge--cat">${r.category}</span>` : '';
      const meta = [];
      if (r.model && segment !== 'TELEFON') meta.push(`<span><i class="fas fa-mobile-screen-button"></i> ${r.model}</span>`);
      if (r.color) meta.push(`<span><i class="fas fa-palette"></i> ${r.color}</span>`);
      return `<div class="inv-item${lowClass}${showHistory ? ' is-history' : ''}${isFS ? ' is-fs' : ''}" data-id="${r.id}" data-seg="${segment}" title="${showHistory ? 'Klik untuk RESTORE ke stok aktif' : 'Klik untuk edit'}">
        <div class="inv-item__qty" title="${isFS ? 'Kali digunakan' : 'Quantity'}">${isFS ? (qty + '×') : qty}</div>
        <div class="inv-item__main">
          <div class="inv-item__head">
            ${sub ? `<span class="inv-item__kod">${sub}</span>` : ''}
            ${cat}
            ${isFS ? '<span class="inv-item__badge inv-item__badge--fs">UNLIMITED</span>' : `<span class="inv-item__badge ${stClass}">${status}</span>`}
          </div>
          <div class="inv-item__title">${name}</div>
          ${meta.length ? `<div class="inv-item__meta">${meta.join('')}</div>` : ''}
        </div>
        <div class="inv-item__price">${fmtRM(r.price)}</div>
      </div>`;
    }).join('');
    list.querySelectorAll('.inv-item').forEach((el) => {
      el.addEventListener('click', async () => {
        const id = el.dataset.id;
        const row = (DATA[segment] || []).find((x) => String(x.id) === String(id));
        if (!row) return;
        if (showHistory) {
          if (!confirm('Restore item ini ke stok aktif?')) return;
          const table = SEG_TABLE[segment];
          const { error } = await window.sb.from(table).update({ qty: 1, status: 'AVAILABLE' }).eq('id', row.id);
          if (error) { snack('Gagal restore: ' + error.message, true); return; }
          snack('Item di-restore ke stok aktif');
          await fetchAll(); populateCategoryFilter(); refresh();
        } else {
          openEditModal(row, segment);
        }
      });
    });
    const title = { SPAREPART: 'Sparepart', FAST_SERVICE: 'Fast Service', ACCESSORIES: 'Aksesori', TELEFON: 'Telefon' }[segment] || '';
    $('listTitle').textContent = (showHistory ? 'History ' : 'Senarai ') + title;
  }

  document.querySelectorAll('.inv-seg-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.inv-seg-btn').forEach((b) => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      segment = btn.dataset.seg;
      filters.category = 'ALL'; filters.model = 'ALL';
      if (segment === 'FAST_SERVICE' && showHistory) { showHistory = false; applyHistoryMode(); return; }
      populateCategoryFilter();
      refresh();
    });
  });

  $('fStatus').addEventListener('change', (e) => { filters.status = e.target.value; refresh(); });
  $('fCategory').addEventListener('change', (e) => { filters.category = e.target.value; refresh(); });
  $('fModel').addEventListener('change', (e) => { filters.model = e.target.value; refresh(); });
  $('fSort').addEventListener('change', (e) => { filters.sort = e.target.value; refresh(); });
  $('fSearch').addEventListener('input', (e) => { filters.search = e.target.value; refresh(); });

  $('btnAdd').addEventListener('click', () => openAddModal(segment));
  function applyHistoryMode() {
    $('btnHistory').classList.toggle('is-on', showHistory);
    $('btnAdd').style.display = showHistory ? 'none' : '';
    $('btnHistory').style.display = showHistory ? 'none' : '';
    // Hide main summary/filter in history mode; show dedicated history filter
    $('secSummary').hidden = showHistory;
    $('secFilter').hidden = showHistory;
    $('secHistFilter').hidden = !showHistory;
    refresh();
  }
  $('btnHistory').addEventListener('click', () => {
    if (segment === 'FAST_SERVICE') { snack('Fast Service tak ada history (unlimited)'); return; }
    showHistory = true;
    histFilter = { status: 'ALL', from: '', to: '', q: '' };
    ['hStatus','hFrom','hTo','hSearch'].forEach((id) => { if ($(id)) $(id).value = id === 'hStatus' ? 'ALL' : ''; });
    applyHistoryMode();
  });
  $('btnHistBack').addEventListener('click', () => {
    showHistory = false;
    applyHistoryMode();
  });
  $('hStatus').addEventListener('change', (e) => { histFilter.status = e.target.value; refresh(); });
  $('hFrom').addEventListener('change', (e) => { histFilter.from = e.target.value; refresh(); });
  $('hTo').addEventListener('change', (e) => { histFilter.to = e.target.value; refresh(); });
  $('hSearch').addEventListener('input', (e) => { histFilter.q = e.target.value; refresh(); });
  $('hReset').addEventListener('click', () => {
    histFilter = { status: 'ALL', from: '', to: '', q: '' };
    $('hStatus').value = 'ALL'; $('hFrom').value = ''; $('hTo').value = ''; $('hSearch').value = '';
    refresh();
  });

  function genKod(prefix) {
    const d = new Date();
    return prefix + d.getFullYear().toString().slice(2) + String(d.getMonth()+1).padStart(2,'0') + String(d.getDate()).padStart(2,'0') + '-' + String(d.getHours()).padStart(2,'0') + String(d.getMinutes()).padStart(2,'0') + String(d.getSeconds()).padStart(2,'0');
  }

  function openAddModal(seg) {
    const title = { SPAREPART: 'Tambah Sparepart', FAST_SERVICE: 'Tambah Fast Service', ACCESSORIES: 'Tambah Aksesori', TELEFON: 'Tambah Telefon' }[seg];
    const prefix = { SPAREPART: 'SP-', FAST_SERVICE: 'FS-', ACCESSORIES: 'AC-', TELEFON: 'PH-' }[seg];
    const isPhone = seg === 'TELEFON';
    const back = document.createElement('div');
    back.className = 'inv-modal-back';
    back.innerHTML = `
      <div class="inv-modal" role="dialog" aria-modal="true">
        <div class="inv-modal__hd">
          <div class="inv-modal__title"><i class="fas fa-box-open"></i> ${title}</div>
          <button type="button" class="inv-modal__close"><i class="fas fa-xmark"></i></button>
        </div>
        <label class="inv-modal__lbl">Kod Item</label>
        <input class="inv-modal__inp" id="adKod" value="${genKod(prefix)}">
        <label class="inv-modal__lbl">Nama Item</label>
        <input class="inv-modal__inp" id="adNama" placeholder="Cth: LCD iPhone 13">
        ${isPhone ? `
          <label class="inv-modal__lbl">IMEI</label>
          <input class="inv-modal__inp" id="adImei" placeholder="IMEI">
          <label class="inv-modal__lbl">Warna</label>
          <input class="inv-modal__inp" id="adWarna" placeholder="BLACK">
          <label class="inv-modal__lbl">Storage</label>
          <input class="inv-modal__inp" id="adStorage" placeholder="128GB">
          <label class="inv-modal__lbl">Condition</label>
          <select class="inv-modal__inp" id="adCond"><option>NEW</option><option>USED</option></select>
        ` : ''}
        <label class="inv-modal__lbl">Kategori</label>
        <input class="inv-modal__inp" id="adCat" value="${seg==='FAST_SERVICE'?'FAST SERVICE':seg==='SPAREPART'?'SPAREPART':seg==='ACCESSORIES'?'ACCESSORIES':''}" ${seg!=='ACCESSORIES'?'readonly':''}>
        <label class="inv-modal__lbl">Harga Jual (RM)</label>
        <input class="inv-modal__inp" id="adPrice" type="number" step="0.01" value="0">
        <div class="inv-modal__btns">
          <button type="button" class="inv-modal__btn inv-modal__btn--primary" id="adSave"><i class="fas fa-floppy-disk"></i> SIMPAN</button>
          <button type="button" class="inv-modal__btn inv-modal__btn--red" id="adCancel"><i class="fas fa-xmark"></i> BATAL</button>
        </div>
      </div>`;
    document.body.appendChild(back);
    requestAnimationFrame(() => back.classList.add('is-show'));
    const close = () => { back.classList.remove('is-show'); setTimeout(() => back.remove(), 200); };
    back.addEventListener('click', (e) => { if (e.target === back) close(); });
    back.querySelector('.inv-modal__close').addEventListener('click', close);
    back.querySelector('#adCancel').addEventListener('click', close);

    back.querySelector('#adSave').addEventListener('click', async () => {
      const kod = back.querySelector('#adKod').value.trim().toUpperCase();
      const nama = back.querySelector('#adNama').value.trim().toUpperCase();
      const cat = back.querySelector('#adCat').value.trim().toUpperCase();
      const price = parseFloat(back.querySelector('#adPrice').value) || 0;
      if (!kod) { snack('Sila isi Kod Item', true); return; }
      if (!nama) { snack('Sila isi Nama Item', true); return; }

      const base = { tenant_id: ctx.tenant_id, branch_id: branchId, cost: 0, price, status: 'AVAILABLE' };
      let row, table;
      if (seg === 'SPAREPART') {
        table = 'stock_parts';
        row = { ...base, sku: kod, part_name: nama, category: cat, qty: 1 };
      } else if (seg === 'FAST_SERVICE') {
        table = 'stock_parts';
        row = { ...base, sku: kod, part_name: nama, category: cat, qty: 0 };
      } else if (seg === 'ACCESSORIES') {
        table = 'accessories';
        row = { ...base, sku: kod, item_name: nama, category: cat, qty: 1 };
      } else {
        table = 'phone_stock';
        const imei = back.querySelector('#adImei').value.trim();
        const warna = back.querySelector('#adWarna').value.trim().toUpperCase();
        const storage = back.querySelector('#adStorage').value.trim().toUpperCase();
        const cond = back.querySelector('#adCond').value;
        row = { ...base, device_name: nama, qty: 1, condition: cond, notes: JSON.stringify({ kod, imei, warna, storage }) };
      }
      const { error } = await window.sb.from(table).insert(row);
      if (error) { snack('Gagal: ' + error.message, true); return; }
      close();
      snack('Stok berjaya ditambah');
      await fetchAll(); populateCategoryFilter(); refresh();
    });

    setTimeout(() => back.querySelector('#adNama').focus(), 100);
  }

  function subscribe(table) {
    window.sb.channel(table + '-inv-' + branchId)
      .on('postgres_changes', { event: '*', schema: 'public', table, filter: `branch_id=eq.${branchId}` }, async () => {
        await fetchAll(); populateCategoryFilter(); refresh();
      }).subscribe();
  }
  ['stock_parts','accessories','phone_stock'].forEach(subscribe);

  // ═══════════════════════════════════════
  // EDIT MODAL — mirror Flutter _showEditModal
  // ═══════════════════════════════════════
  const SEG_TABLE = { SPAREPART: 'stock_parts', FAST_SERVICE: 'stock_parts', ACCESSORIES: 'accessories', TELEFON: 'phone_stock' };
  const SEG_NAME_FIELD = { SPAREPART: 'part_name', FAST_SERVICE: 'part_name', ACCESSORIES: 'item_name', TELEFON: 'device_name' };

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'inv-snack' + (err ? ' is-err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => { el.classList.add('is-show'); }, 10);
    setTimeout(() => { el.classList.remove('is-show'); setTimeout(() => el.remove(), 300); }, 2200);
  }

  function openEditModal(item, seg) {
    const table = SEG_TABLE[seg];
    const nameField = SEG_NAME_FIELD[seg];
    const id = item.id;
    const kod = item.sku || item.imei || item.siri || '-';
    const qty = seg === 'TELEFON' ? 1 : (Number(item.qty) || 0);
    const status = (item.status || 'AVAILABLE').toUpperCase();
    const isSold = status === 'TERJUAL';
    const siriJual = item.no_siri_jual || '';
    const curName = item[nameField] || item.part_name || item.item_name || item.device_name || '';
    const curPrice = Number(item.price) || 0;

    const back = document.createElement('div');
    back.className = 'inv-modal-back';
    back.innerHTML = `
      <div class="inv-modal" role="dialog" aria-modal="true">
        <div class="inv-modal__hd">
          <div class="inv-modal__title"><i class="fas fa-pen-to-square"></i> Edit: <span>${kod}</span></div>
          <button type="button" class="inv-modal__close" aria-label="Close"><i class="fas fa-xmark"></i></button>
        </div>

        <div class="inv-modal__row">
          <span class="inv-pill ${isSold ? 'is-sold' : 'is-avail'}">${status}</span>
          <span class="inv-modal__qty${qty <= 2 ? ' is-low' : ''}">QTY: ${qty}</span>
          ${siriJual ? `<span class="inv-modal__siri">Siri Jual: ${siriJual}</span>` : ''}
        </div>

        <label class="inv-modal__lbl">Nama Item</label>
        <input class="inv-modal__inp" id="emName" value="${(curName + '').replace(/"/g, '&quot;')}" placeholder="Nama">

        <label class="inv-modal__lbl">Harga Jual (RM)</label>
        <input class="inv-modal__inp" id="emPrice" type="number" step="0.01" value="${curPrice}" placeholder="0.00">

        <div class="inv-modal__btns">
          <button type="button" class="inv-modal__btn inv-modal__btn--primary" id="emSave"><i class="fas fa-floppy-disk"></i> KEMASKINI</button>
          <button type="button" class="inv-modal__btn inv-modal__btn--blue" id="emPrint"><i class="fas fa-print"></i> CETAK LABEL</button>
        </div>

        <div class="inv-modal__sect">
          <div class="inv-modal__sect-hd"><i class="fas fa-clock-rotate-left"></i> Reverse Stock</div>
          <div class="inv-modal__reverse">
            <input class="inv-modal__inp" id="emSiri" placeholder="Cth: RMS-00001">
            <button type="button" class="inv-modal__btn inv-modal__btn--red" id="emReverse"><i class="fas fa-arrows-rotate"></i> REVERSE</button>
          </div>
        </div>

        <button type="button" class="inv-modal__btn inv-modal__btn--red inv-modal__btn--full" id="emDelete"><i class="fas fa-trash-can"></i> PADAM ITEM</button>
      </div>`;
    document.body.appendChild(back);
    requestAnimationFrame(() => back.classList.add('is-show'));

    const close = () => { back.classList.remove('is-show'); setTimeout(() => back.remove(), 200); };
    back.addEventListener('click', (e) => { if (e.target === back) close(); });
    back.querySelector('.inv-modal__close').addEventListener('click', close);

    back.querySelector('#emSave').addEventListener('click', async () => {
      const name = back.querySelector('#emName').value.trim().toUpperCase();
      const price = parseFloat(back.querySelector('#emPrice').value) || 0;
      if (!name) { snack('Nama item tidak boleh kosong', true); return; }
      const upd = { price };
      upd[nameField] = name;
      const { error } = await window.sb.from(table).update(upd).eq('id', id);
      if (error) { snack('Gagal kemaskini: ' + error.message, true); return; }
      close();
      snack('Stok berjaya dikemaskini');
    });

    back.querySelector('#emPrint').addEventListener('click', () => {
      const printable = `LABEL STOK\n================================\n${kod}\n${curName}\nRM ${curPrice.toFixed(2)}\n================================\n~ RMS Pro ~`;
      const w = window.open('', '_blank', 'width=320,height=240');
      if (!w) { snack('Browser block popup. Allow popup untuk cetak.', true); return; }
      w.document.write(`<pre style="font:bold 14px monospace;text-align:center;white-space:pre-wrap;margin:0;padding:8px">${printable}</pre><script>window.print();<\/script>`);
      w.document.close();
    });

    back.querySelector('#emReverse').addEventListener('click', async () => {
      const siri = back.querySelector('#emSiri').value.trim().toUpperCase();
      if (!siri) { snack('Sila isi No. Siri', true); return; }
      if ((siriJual + '').toUpperCase() !== siri) { snack('No. Siri tidak sepadan dengan item ini', true); return; }
      const { error } = await window.sb.from(table).update({ qty: qty + 1, status: 'AVAILABLE' }).eq('id', id);
      if (error) { snack('Gagal reverse: ' + error.message, true); return; }
      close();
      snack('Stok berjaya di-reverse dari job ' + siri);
    });

    back.querySelector('#emDelete').addEventListener('click', async () => {
      if (!confirm(`Padam item "${kod}"?`)) return;
      const { error } = await window.sb.from(table).delete().eq('id', id);
      if (error) { snack('Gagal padam: ' + error.message, true); return; }
      close();
      snack('Item berjaya dipadam');
    });

    setTimeout(() => back.querySelector('#emName').focus(), 100);
  }

  await fetchAll();
  populateCategoryFilter();
  refresh();
})();
