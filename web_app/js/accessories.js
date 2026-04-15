/* accessories.js — Supabase. Mirror accessories_screen.dart (CRUD stock accessories). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'ac-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  let ALL = [];
  let searchQ = '';
  let editingId = null;

  async function fetchAll() {
    const { data, error } = await window.sb
      .from('accessories').select('*')
      .eq('branch_id', branchId)
      .order('created_at', { ascending: false })
      .limit(2000);
    if (error) { console.error(error); return []; }
    return data || [];
  }

  function refresh() {
    const q = searchQ.toLowerCase();
    const rows = ALL.filter((r) => {
      if (!q) return true;
      return (r.sku || '').toLowerCase().includes(q) ||
             (r.item_name || '').toLowerCase().includes(q);
    });
    const list = $('acList');
    if (!rows.length) {
      list.innerHTML = '<div class="ac-empty"><i class="fas fa-box-open"></i><div>Tiada aksesori.</div></div>';
    } else {
      list.innerHTML = rows.map((r) => {
        const qty = Number(r.qty) || 0;
        const low = qty <= 2;
        return `<div class="ac-card${low ? ' low' : ''}" data-id="${r.id}">
          <div class="ac-qty">${qty}</div>
          <div class="ac-content">
            <div class="ac-row1">
              <span class="ac-kod">${r.sku || '—'}</span>
              <span class="ac-cat">${r.category || 'ACCESSORIES'}</span>
            </div>
            <div class="ac-nama">${r.item_name || '—'}</div>
            <div class="ac-info"><span class="jual">${fmtRM(r.price)}</span><span class="supp">Kos ${fmtRM(r.cost)}</span></div>
          </div>
          <i class="fas fa-chevron-right ac-chev"></i>
        </div>`;
      }).join('');
      list.querySelectorAll('.ac-card').forEach((el) => {
        el.addEventListener('click', () => openEdit(ALL.find((r) => r.id === el.dataset.id)));
      });
    }
    const foot = $('acFoot');
    const total = ALL.length;
    const qtySum = ALL.reduce((s, r) => s + (Number(r.qty) || 0), 0);
    foot.hidden = total === 0;
    foot.innerHTML = `<span class="ac-chip" style="background:#f59e0b22;color:#f59e0b;">ITEM: ${total}</span>
      <span class="ac-chip" style="background:#10b98122;color:#10b981;">QTY: ${qtySum}</span>`;
  }

  function openAdd() {
    editingId = null;
    $('addTitle').textContent = 'TAMBAH STOK';
    $('saveLbl').textContent = 'SIMPAN STOK';
    ['fKod','fNama','fJual'].forEach((k) => { if ($(k)) $(k).value = ''; });
    $('fTarikh').value = new Date().toISOString().slice(0, 10);
    $('fCat').value = 'ACCESSORIES';
    $('modalAdd').classList.add('is-open');
  }

  function openEdit(row) {
    if (!row) return;
    editingId = row.id;
    $('editTitle').textContent = 'EDIT ' + (row.sku || '');
    $('editStatusRow').innerHTML =
      `<div class="ac-badge" style="color:#f59e0b;border-color:#f59e0b55;background:#f59e0b15;">${row.sku || ''}</div>
       <div class="ac-badge" style="color:#06b6d4;border-color:#06b6d455;background:#06b6d415;">${row.category || 'ACCESSORIES'}</div>
       <div class="ac-badge" style="color:#10b981;border-color:#10b98155;background:#10b98115;">QTY ${row.qty || 0}</div>`;
    $('eNama').value = row.item_name || '';
    $('eJual').value = row.price || 0;
    $('modalEdit').classList.add('is-open');
  }

  function closeMod(id) { $(id).classList.remove('is-open'); }
  document.querySelectorAll('[data-close]').forEach((el) => {
    el.addEventListener('click', () => closeMod(el.dataset.close));
  });

  $('btnAdd').addEventListener('click', openAdd);
  $('kodAuto').addEventListener('click', () => { $('fKod').value = 'AC' + Date.now().toString(36).toUpperCase().slice(-6); });
  $('kodCopy').addEventListener('click', () => { if ($('fKod').value) navigator.clipboard.writeText($('fKod').value); });
  $('kodScan').addEventListener('click', () => { const v = prompt('Masuk barcode:'); if (v) $('fKod').value = v; });

  $('saveStock').addEventListener('click', async () => {
    const sku = $('fKod').value.trim();
    const name = $('fNama').value.trim();
    if (!sku || !name) { snack('Kod & nama wajib', true); return; }
    const payload = {
      tenant_id: tenantId,
      branch_id: branchId,
      sku,
      item_name: name,
      qty: 1,
      price: Number($('fJual').value) || 0,
      cost: 0,
      category: $('fCat').value,
    };
    const { error } = await window.sb.from('accessories').insert(payload);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Ditambah');
    closeMod('modalAdd');
    ALL = await fetchAll(); refresh();
  });

  $('eUpdate').addEventListener('click', async () => {
    if (!editingId) return;
    const patch = {
      item_name: $('eNama').value.trim(),
      price: Number($('eJual').value) || 0,
    };
    const { error } = await window.sb.from('accessories').update(patch).eq('id', editingId);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Dikemaskini'); closeMod('modalEdit');
    ALL = await fetchAll(); refresh();
  });

  $('eDelete').addEventListener('click', async () => {
    if (!editingId) return;
    if (!confirm('Padam item ini?')) return;
    const { error } = await window.sb.from('accessories').delete().eq('id', editingId);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Dipadam'); closeMod('modalEdit');
    ALL = await fetchAll(); refresh();
  });

  $('eReverse').addEventListener('click', async () => {
    if (!editingId) return;
    const row = ALL.find((r) => r.id === editingId);
    if (!row) return;
    const { error } = await window.sb.from('accessories').update({ qty: (Number(row.qty) || 0) + 1 }).eq('id', editingId);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Reverse +1'); closeMod('modalEdit');
    ALL = await fetchAll(); refresh();
  });

  $('ePrint').addEventListener('click', () => snack('Cetak label — TODO'));
  $('btnHistUsed').addEventListener('click', () => {
    $('usedList').innerHTML = '<p style="color:#94a3b8;padding:20px;text-align:center;">History used — belum dilaksanakan.</p>';
    $('modalUsed').classList.add('is-open');
  });
  $('btnHistReturn').addEventListener('click', () => {
    $('returnList').innerHTML = '<p style="color:#94a3b8;padding:20px;text-align:center;">History return — belum dilaksanakan.</p>';
    $('modalReturn').classList.add('is-open');
  });

  $('acSearch').addEventListener('input', (e) => {
    searchQ = e.target.value;
    $('acClear').hidden = !searchQ;
    refresh();
  });
  $('acClear').addEventListener('click', () => { $('acSearch').value = ''; searchQ = ''; $('acClear').hidden = true; refresh(); });
  $('acScan').addEventListener('click', () => { const v = prompt('Masuk barcode:'); if (v) { $('acSearch').value = v; searchQ = v; refresh(); } });

  window.sb.channel('accessories-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'accessories', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchAll(); refresh(); })
    .subscribe();

  ALL = await fetchAll();
  refresh();
})();
