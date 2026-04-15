/* phone_stock.js — Supabase. Mirror phone_stock_screen.dart (list + add + edit + sell). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'ps-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  let ALL = [];
  let searchQ = '';
  let filterModel = 'SEMUA';
  let filterKat = 'SEMUA';
  const ownerID = (ctx.email || '').split('@')[0] || 'unknown';

  async function fetchStock() {
    const { data, error } = await window.sb
      .from('phone_stock').select('*')
      .eq('branch_id', branchId)
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .limit(2000);
    if (error) { console.error(error); return []; }
    return data || [];
  }

  function parseNotes(s) { try { return JSON.parse(s || '{}'); } catch (e) { return {}; } }

  function refresh() {
    const q = searchQ.toLowerCase();
    const rows = ALL.filter((r) => {
      const notes = parseNotes(r.notes);
      if (filterModel !== 'SEMUA' && r.device_name !== filterModel) return false;
      if (filterKat !== 'SEMUA' && (r.condition || '') !== filterKat) return false;
      if (q) {
        const hay = `${r.device_name || ''} ${notes.imei || ''} ${notes.kod || ''} ${notes.warna || ''}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });

    // Filter options
    const models = ['SEMUA', ...new Set(ALL.map((r) => r.device_name).filter(Boolean))];
    const kats = ['SEMUA', ...new Set(ALL.map((r) => r.condition).filter(Boolean))];
    $('filterModel').innerHTML = models.map((m) => `<option value="${m}"${m===filterModel?' selected':''}>${m}</option>`).join('');
    $('filterKategori').innerHTML = kats.map((m) => `<option value="${m}"${m===filterKat?' selected':''}>${m}</option>`).join('');

    $('psEmpty').hidden = rows.length > 0;
    $('psGrid').innerHTML = rows.map((r) => {
      const notes = parseNotes(r.notes);
      const stCol = r.status === 'AVAILABLE' ? '#10b981' : (r.status === 'SOLD' ? '#64748b' : '#f59e0b');
      const img = notes.image_url ? `<img src="${notes.image_url}" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;">` : '';
      return `<div class="ps-card" data-id="${r.id}">
        <div class="ps-card__img" style="position:relative;overflow:hidden;">
          ${img}
          <i class="fas fa-mobile-screen-button"></i>
          <span class="ps-badge status-right" style="background:${stCol}">${r.status || ''}</span>
          ${r.condition ? `<span class="ps-badge kat-left" style="background:#2563eb">${r.condition}</span>` : ''}
        </div>
        <div style="padding:8px;">
          <div style="font-weight:900;font-size:12px;">${r.device_name || '—'}</div>
          <div style="font-size:10px;color:#64748b;">${notes.kod || ''} ${notes.warna || ''} ${notes.storage || ''}</div>
          <div style="font-weight:900;color:#2563eb;margin-top:4px;">${fmtRM(r.price)}</div>
        </div>
        <div class="ps-card__actions">
          <button data-act="edit" style="color:#2563eb;border-color:#2563eb55;"><i class="fas fa-pen"></i></button>
          ${r.status === 'AVAILABLE' ? '<button data-act="sell" style="color:#10b981;border-color:#10b98155;"><i class="fas fa-cash-register"></i></button>' : ''}
          <button data-act="del" style="color:#dc2626;border-color:#dc262655;"><i class="fas fa-trash"></i></button>
        </div>
      </div>`;
    }).join('');

    $('psGrid').querySelectorAll('.ps-card').forEach((el) => {
      const id = el.dataset.id;
      el.querySelectorAll('[data-act]').forEach((b) => {
        b.addEventListener('click', (e) => {
          e.stopPropagation();
          const row = ALL.find((r) => r.id === id);
          if (!row) return;
          if (b.dataset.act === 'edit') openForm(row);
          else if (b.dataset.act === 'sell') openSell(row);
          else if (b.dataset.act === 'del') delRow(row);
        });
      });
      el.addEventListener('click', () => {
        const row = ALL.find((r) => r.id === id);
        if (row) openDetail(row);
      });
    });

    const available = ALL.filter((r) => r.status === 'AVAILABLE').length;
    const sold = ALL.filter((r) => r.status === 'SOLD').length;
    $('psFooter').innerHTML = `<span class="ps-foot-badge" style="background:#10b98133;color:#059669;">AVAILABLE: ${available}</span>
      <span class="ps-foot-badge" style="background:#64748b33;color:#475569;">SOLD: ${sold}</span>
      <span class="ps-foot-badge" style="background:#2563eb33;color:#1e40af;">TOTAL: ${ALL.length}</span>`;
  }

  function openModal(html) {
    const bg = $('modalBg');
    $('modalBox').innerHTML = html;
    bg.classList.add('is-open');
    $('modalBox').querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => bg.classList.remove('is-open')));
    bg.onclick = (e) => { if (e.target === bg) bg.classList.remove('is-open'); };
  }
  function closeModal() { $('modalBg').classList.remove('is-open'); }

  function openForm(row) {
    const r = row || {};
    const notes = parseNotes(r.notes);
    let curImgUrl = notes.image_url || null;
    openModal(`
      <button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-mobile-screen-button"></i> ${row ? 'EDIT' : 'TAMBAH'} PHONE</h3>
      <div class="ps-field"><label>Gambar</label>
        <div style="display:flex;align-items:center;gap:10px;">
          <img id="fImgPrev" src="${curImgUrl || ''}" style="width:60px;height:60px;object-fit:cover;border-radius:8px;background:#f1f5f9;${curImgUrl ? '' : 'display:none;'}">
          <button type="button" id="fImgBtn" style="padding:8px 12px;border:1px solid #2563eb55;color:#2563eb;background:#fff;border-radius:8px;cursor:pointer;"><i class="fas fa-camera"></i> Upload</button>
          <button type="button" id="fImgDel" style="padding:8px 12px;border:1px solid #dc262655;color:#dc2626;background:#fff;border-radius:8px;cursor:pointer;${curImgUrl ? '' : 'display:none;'}"><i class="fas fa-trash"></i></button>
        </div>
      </div>
      <div class="ps-field"><label>Nama Model</label><input id="fName" value="${r.device_name || ''}"></div>
      <div class="ps-row2">
        <div class="ps-field"><label>Harga Jual</label><input id="fPrice" type="number" step="0.01" value="${r.price || 0}"></div>
        <div class="ps-field"><label>Kos (Modal)</label><input id="fCost" type="number" step="0.01" value="${r.cost || 0}"></div>
      </div>
      <div class="ps-row2">
        <div class="ps-field"><label>Qty</label><input id="fQty" type="number" value="${r.qty || 1}"></div>
        <div class="ps-field"><label>Condition</label>
          <select id="fCond">
            <option${(r.condition||'BARU')==='BARU'?' selected':''}>BARU</option>
            <option${r.condition==='H/USED'?' selected':''}>H/USED</option>
            <option${r.condition==='SECOND'?' selected':''}>SECOND</option>
          </select>
        </div>
      </div>
      <div class="ps-row2">
        <div class="ps-field"><label>IMEI</label><input id="fImei" value="${notes.imei || ''}"></div>
        <div class="ps-field"><label>Kod</label><input id="fKod" value="${notes.kod || ''}"></div>
      </div>
      <div class="ps-row2">
        <div class="ps-field"><label>Warna</label><input id="fWarna" value="${notes.warna || ''}"></div>
        <div class="ps-field"><label>Storage</label><input id="fStor" value="${notes.storage || ''}"></div>
      </div>
      <div class="ps-actions">
        <button class="btn-save" id="fSave"><i class="fas fa-save"></i> SIMPAN</button>
      </div>`);
    // Image upload button
    $('fImgBtn').addEventListener('click', async () => {
      if (!window.SupabaseStorage) { snack('Storage helper missing', true); return; }
      const btn = $('fImgBtn');
      const orig = btn.innerHTML;
      btn.innerHTML = 'UPLOADING...'; btn.disabled = true;
      try {
        const kod = ($('fKod').value.trim() || 'phone') + '_' + (ctx.id || 'x');
        const url = await window.SupabaseStorage.pickAndUpload({
          bucket: 'phone_stock',
          pathFn: () => `${ownerID}/${kod}_${Date.now()}.jpg`,
          maxDim: 1280, quality: 0.8,
        });
        if (url) {
          curImgUrl = url;
          $('fImgPrev').src = url; $('fImgPrev').style.display = '';
          $('fImgDel').style.display = '';
        }
      } catch (e) {
        snack('Upload gagal: ' + e.message, true);
      } finally {
        btn.innerHTML = orig; btn.disabled = false;
      }
    });
    $('fImgDel').addEventListener('click', () => {
      curImgUrl = null;
      $('fImgPrev').style.display = 'none'; $('fImgDel').style.display = 'none';
    });

    $('fSave').addEventListener('click', async () => {
      const patch = {
        device_name: $('fName').value.trim(),
        price: Number($('fPrice').value) || 0,
        cost: Number($('fCost').value) || 0,
        qty: Number($('fQty').value) || 1,
        condition: $('fCond').value,
        notes: JSON.stringify({
          imei: $('fImei').value.trim(),
          kod: $('fKod').value.trim(),
          warna: $('fWarna').value.trim(),
          storage: $('fStor').value.trim(),
          image_url: curImgUrl || null,
        }),
      };
      if (!patch.device_name) { snack('Nama wajib', true); return; }
      let err;
      if (row) {
        ({ error: err } = await window.sb.from('phone_stock').update(patch).eq('id', row.id));
      } else {
        ({ error: err } = await window.sb.from('phone_stock').insert({
          ...patch,
          tenant_id: ctx.tenant_id,
          branch_id: branchId,
          status: 'AVAILABLE',
          added_by: ctx.nama || ctx.id,
        }));
      }
      if (err) { snack('Gagal: ' + err.message, true); return; }
      snack('Disimpan');
      closeModal();
      ALL = await fetchStock();
      refresh();
    });
  }

  function openSell(row) {
    const notes = parseNotes(row.notes);
    openModal(`
      <button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-cash-register"></i> JUAL — ${row.device_name}</h3>
      <div class="ps-row2">
        <div class="ps-field"><label>Nama Pelanggan</label><input id="sName"></div>
        <div class="ps-field"><label>No Telefon</label><input id="sTel"></div>
      </div>
      <div class="ps-row2">
        <div class="ps-field"><label>Harga Jual</label><input id="sPrice" type="number" step="0.01" value="${row.price || 0}"></div>
        <div class="ps-field"><label>Qty</label><input id="sQty" type="number" value="1" max="${row.qty}"></div>
      </div>
      <div class="ps-field"><label>Catatan</label><textarea id="sNote" rows="2"></textarea></div>
      <div class="ps-actions">
        <button class="btn-save" id="sSave"><i class="fas fa-check"></i> SAHKAN JUAL</button>
      </div>`);
    $('sSave').addEventListener('click', async () => {
      const qty = Number($('sQty').value) || 1;
      const price = Number($('sPrice').value) || 0;
      const sellNotes = {
        imei: notes.imei, kod: notes.kod, warna: notes.warna, storage: notes.storage,
        note: $('sNote').value.trim(),
      };
      const { error } = await window.sb.from('phone_sales').insert({
        tenant_id: ctx.tenant_id,
        branch_id: branchId,
        device_name: row.device_name,
        customer_name: $('sName').value.trim(),
        customer_phone: $('sTel').value.trim(),
        price_per_unit: price,
        total_price: Number((price * qty).toFixed(2)),
        sold_at: new Date().toISOString(),
        notes: JSON.stringify(sellNotes),
      });
      if (error) { snack('Gagal: ' + error.message, true); return; }
      const remain = Math.max(0, (row.qty || 1) - qty);
      await window.sb.from('phone_stock').update({
        qty: remain,
        status: remain === 0 ? 'SOLD' : 'AVAILABLE',
      }).eq('id', row.id);
      snack('Jualan direkod');
      closeModal();
      ALL = await fetchStock();
      refresh();
    });
  }

  async function delRow(row) {
    if (!confirm(`Padam ${row.device_name}?`)) return;
    const { error } = await window.sb.from('phone_stock').update({ deleted_at: new Date().toISOString() }).eq('id', row.id);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Dipadam');
    ALL = await fetchStock();
    refresh();
  }

  function openDetail(row) {
    const notes = parseNotes(row.notes);
    openModal(`
      <button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-mobile-screen-button"></i> ${row.device_name}</h3>
      <div class="ps-detail-row"><b>Status</b><span>${row.status}</span></div>
      <div class="ps-detail-row"><b>Condition</b><span>${row.condition || '—'}</span></div>
      <div class="ps-detail-row"><b>Qty</b><span>${row.qty}</span></div>
      <div class="ps-detail-row"><b>Harga</b><span>${fmtRM(row.price)}</span></div>
      <div class="ps-detail-row"><b>Kos</b><span>${fmtRM(row.cost)}</span></div>
      <div class="ps-detail-row"><b>IMEI</b><span>${notes.imei || '—'}</span></div>
      <div class="ps-detail-row"><b>Kod</b><span>${notes.kod || '—'}</span></div>
      <div class="ps-detail-row"><b>Warna</b><span>${notes.warna || '—'}</span></div>
      <div class="ps-detail-row"><b>Storage</b><span>${notes.storage || '—'}</span></div>`);
  }

  // --- Handlers
  $('btnAdd').addEventListener('click', () => openForm(null));
  $('searchInput').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('clearSearch').addEventListener('click', () => { $('searchInput').value = ''; searchQ = ''; refresh(); });
  $('filterModel').addEventListener('change', (e) => { filterModel = e.target.value; refresh(); });
  $('filterKategori').addEventListener('change', (e) => { filterKat = e.target.value; refresh(); });
  // Pick an AVAILABLE phone from current branch
  function pickPhoneItems() {
    return ALL.filter((r) => r.status === 'AVAILABLE' && !r.deleted_at);
  }

  function renderPickList(rows, onPick) {
    if (rows.length === 0) return '<p style="color:#64748b;padding:10px;">Tiada stok AVAILABLE.</p>';
    return `<div style="display:flex;flex-direction:column;gap:6px;max-height:360px;overflow-y:auto;">
      ${rows.map((r) => {
        const notes = parseNotes(r.notes);
        return `<div class="ps-hist-item" data-pick="${r.id}" style="cursor:pointer;display:flex;justify-content:space-between;align-items:center;">
          <div>
            <b>${r.device_name || '-'}</b> — ${fmtRM(r.price)}
            <br><small style="color:#64748b;">IMEI: ${notes.imei || '—'} · ${notes.kod || ''} ${notes.warna || ''}</small>
          </div>
          <i class="fas fa-chevron-right" style="color:#94a3b8;"></i>
        </div>`;
      }).join('')}
    </div>`;
  }

  // ── RETURN ──────────────────────────────────────────
  $('btnReturnList').addEventListener('click', () => {
    const rows = pickPhoneItems();
    openModal(`<button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-truck-ramp-box" style="color:#dc2626"></i> RETURN SUPPLIER — Pilih Stok</h3>
      ${renderPickList(rows)}`);
    $('modalBox').querySelectorAll('[data-pick]').forEach((el) => {
      el.addEventListener('click', () => {
        const row = ALL.find((r) => r.id === el.dataset.pick);
        if (row) openReturnForm(row);
      });
    });
  });

  function openReturnForm(row) {
    const notes = parseNotes(row.notes);
    openModal(`<button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-truck-ramp-box" style="color:#dc2626"></i> RETURN — ${row.device_name}</h3>
      <div class="ps-field"><label>Jenis Return</label>
        <select id="rType">
          <option value="PERMANENT">PERMANENT — return kekal ke supplier</option>
          <option value="CLAIM">CLAIM — hantar untuk claim warranty</option>
        </select>
      </div>
      <div class="ps-field"><label>Catatan (pilihan)</label><textarea id="rNote" rows="2"></textarea></div>
      <div class="ps-actions">
        <button class="btn-del" id="rSave"><i class="fas fa-check"></i> SAHKAN RETURN</button>
      </div>`);
    $('rSave').addEventListener('click', async () => {
      const type = $('rType').value;
      const note = $('rNote').value.trim();
      const reason = note ? `${type} — ${note}` : type;
      const { error: e1 } = await window.sb.from('phone_returns').insert({
        tenant_id: ctx.tenant_id,
        branch_id: branchId,
        phone_stock_id: row.id,
        device_name: row.device_name || '-',
        imei: notes.imei || '',
        kos: row.cost || 0,
        jual: row.price || 0,
        reason,
        returned_by: ctx.nama || ctx.id || null,
      });
      if (e1) { snack('Gagal: ' + e1.message, true); return; }
      const { error: e2 } = await window.sb.from('phone_stock').update({
        status: 'RETURNED',
        deleted_at: new Date().toISOString(),
      }).eq('id', row.id);
      if (e2) { snack('Gagal update stock: ' + e2.message, true); return; }
      snack(type === 'PERMANENT' ? 'Di-return permanent ke supplier' : 'Dihantar untuk claim');
      closeModal();
      ALL = await fetchStock();
      refresh();
    });
  }

  // ── TRANSFER ────────────────────────────────────────
  $('btnTransferList').addEventListener('click', () => {
    const rows = pickPhoneItems();
    openModal(`<button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-right-left" style="color:#3b82f6"></i> TRANSFER CAWANGAN — Pilih Stok</h3>
      ${renderPickList(rows)}`);
    $('modalBox').querySelectorAll('[data-pick]').forEach((el) => {
      el.addEventListener('click', () => {
        const row = ALL.find((r) => r.id === el.dataset.pick);
        if (row) openTransferForm(row);
      });
    });
  });

  async function openTransferForm(row) {
    const notes = parseNotes(row.notes);
    // Load other branches under the tenant
    const { data: branches, error: berr } = await window.sb
      .from('branches')
      .select('id,name,shop_code')
      .eq('tenant_id', ctx.tenant_id)
      .order('name', { ascending: true });
    if (berr) { snack('Gagal load cawangan: ' + berr.message, true); return; }
    const others = (branches || []).filter((b) => b.id !== branchId);
    if (others.length === 0) { snack('Tiada cawangan lain untuk transfer', true); return; }

    openModal(`<button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-right-left" style="color:#3b82f6"></i> TRANSFER — ${row.device_name}</h3>
      <div class="ps-detail-row"><b>IMEI</b><span>${notes.imei || '—'}</span></div>
      <div class="ps-detail-row"><b>Harga</b><span>${fmtRM(row.price)}</span></div>
      <div class="ps-field"><label>Cawangan Destinasi</label>
        <select id="tBranch">
          ${others.map((b) => `<option value="${b.id}" data-code="${b.shop_code || ''}" data-name="${b.name || ''}">${b.name || '(no name)'} ${b.shop_code ? '— ' + b.shop_code : ''}</option>`).join('')}
        </select>
      </div>
      <div class="ps-field"><label>Catatan (pilihan)</label><textarea id="tNote" rows="2"></textarea></div>
      <div class="ps-actions">
        <button class="btn-save" id="tSave" style="background:#3b82f6"><i class="fas fa-paper-plane"></i> HANTAR TRANSFER</button>
      </div>`);
    $('tSave').addEventListener('click', async () => {
      const sel = $('tBranch');
      const opt = sel.options[sel.selectedIndex];
      const toBranchId = sel.value;
      const toName = opt.dataset.code || opt.dataset.name || '';
      const note = $('tNote').value.trim();
      const { error: e1 } = await window.sb.from('phone_transfers').insert({
        tenant_id: ctx.tenant_id,
        from_branch_id: branchId,
        to_branch_id: toBranchId,
        to_branch_name: toName,
        phone_stock_id: row.id,
        device_name: row.device_name || '-',
        imei: notes.imei || '',
        kos: row.cost || 0,
        jual: row.price || 0,
        status: 'PENDING',
        notes: note || null,
      });
      if (e1) { snack('Gagal: ' + e1.message, true); return; }
      const { error: e2 } = await window.sb.from('phone_stock').update({
        deleted_at: new Date().toISOString(),
      }).eq('id', row.id);
      if (e2) { snack('Gagal update stock: ' + e2.message, true); return; }
      snack('Stok ditransfer ke ' + (toName || 'cawangan'));
      closeModal();
      ALL = await fetchStock();
      refresh();
    });
  }
  $('btnHistory').addEventListener('click', async () => {
    const { data } = await window.sb.from('phone_sales').select('*').eq('branch_id', branchId).is('deleted_at', null).order('sold_at', { ascending: false }).limit(200);
    const rows = data || [];
    openModal(`<button class="ps-close" data-close><i class="fas fa-xmark"></i></button>
      <h3><i class="fas fa-clock-rotate-left"></i> HISTORY JUALAN</h3>
      ${rows.length === 0 ? '<p style="color:#64748b;">Tiada rekod.</p>' :
        rows.map((r) => `<div class="ps-hist-item"><b>${r.device_name}</b> — ${fmtRM(r.total_price)}<br><small>${r.customer_name || '—'} · ${new Date(r.sold_at).toLocaleString('en-MY')}</small></div>`).join('')}`);
  });

  window.sb.channel('phone_stock-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'phone_stock', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchStock(); refresh(); })
    .subscribe();

  ALL = await fetchStock();
  refresh();
})();
