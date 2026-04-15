/* stock.js — Supabase. Mirror stock_parts_screen.dart (inventory parts CRUD). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'st-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  let ALL = [];
  let searchQ = '';

  async function fetchStock() {
    const { data, error } = await window.sb
      .from('stock_parts').select('*')
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
      return (r.sku || '').toLowerCase().includes(q) || (r.part_name || '').toLowerCase().includes(q);
    });
    $('stEmpty').hidden = rows.length > 0;
    $('stList').innerHTML = rows.map((r) => {
      const qty = Number(r.qty) || 0;
      const reorder = Number(r.reorder_level) || 0;
      const low = reorder > 0 && qty <= reorder;
      return `<div class="st-card${low?' low':''}" data-id="${r.id}">
        <div class="st-qty${low?' low':''}">${qty}</div>
        <div class="st-body">
          <div class="st-row1">
            <span class="st-kod">${r.sku || '—'}</span>
            <span class="st-mini" style="background:${low?'#ef444422':'#10b98122'};color:${low?'#ef4444':'#059669'};">${r.status || 'AVAILABLE'}</span>
          </div>
          <div class="st-nama">${r.part_name || '—'}</div>
          <div class="st-meta">
            <span>${r.category || 'SPAREPART'}</span>
            <span class="st-jual">${fmtRM(r.price)}</span>
            <span>Kos: ${fmtRM(r.cost)}</span>
          </div>
        </div>
      </div>`;
    }).join('');
    $('stList').querySelectorAll('.st-card').forEach((el) => {
      el.addEventListener('click', () => openEdit(ALL.find((r) => r.id === el.dataset.id)));
    });
    const total = ALL.length;
    const lowCount = ALL.filter((r) => (Number(r.reorder_level) || 0) > 0 && (Number(r.qty) || 0) <= Number(r.reorder_level)).length;
    $('stFooter').innerHTML = `<span class="st-foot-chip" style="background:#2563eb22;color:#1e40af;">TOTAL: ${total}</span>
      <span class="st-foot-chip" style="background:#ef444422;color:#dc2626;">LOW: ${lowCount}</span>`;
  }

  // Add modal
  function openAdd() {
    ['addKod','addNama','addJual'].forEach((k) => { if ($(k)) $(k).value = ''; });
    const today = new Date();
    $('addTarikh').value = today.toISOString().slice(0, 10);
    $('mAdd').classList.add('show');
  }
  function closeMod(id) { $(id).classList.remove('show'); }
  $('btnAdd').addEventListener('click', openAdd);
  document.querySelectorAll('[data-close]').forEach((el) => el.addEventListener('click', () => {
    el.closest('.st-modal-bg').classList.remove('show');
  }));

  $('addAuto').addEventListener('click', () => {
    $('addKod').value = 'SP' + Date.now().toString(36).toUpperCase().slice(-6);
  });
  $('addCopy').addEventListener('click', () => {
    if ($('addKod').value) navigator.clipboard.writeText($('addKod').value);
  });
  $('addScan').addEventListener('click', () => {
    const v = prompt('Masuk barcode:'); if (v) $('addKod').value = v;
  });

  $('addSave').addEventListener('click', async () => {
    const sku = $('addKod').value.trim();
    const name = $('addNama').value.trim();
    if (!sku || !name) { snack('Kod & nama wajib', true); return; }
    const { error } = await window.sb.from('stock_parts').insert({
      tenant_id: ctx.tenant_id,
      branch_id: branchId,
      sku,
      part_name: name,
      qty: 0,
      price: Number($('addJual').value) || 0,
      cost: 0,
      category: $('addCategory').value,
      status: 'AVAILABLE',
    });
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Ditambah');
    closeMod('mAdd');
    ALL = await fetchStock();
    refresh();
  });

  // Edit modal
  function openEdit(row) {
    if (!row) return;
    $('editTitle').textContent = 'EDIT ' + (row.sku || '');
    $('editBody').innerHTML = `
      <div class="st-field"><label>Kod Item</label><input class="input" id="eSku" value="${row.sku || ''}"></div>
      <div class="st-field"><label>Nama</label><input class="input" id="eName" value="${row.part_name || ''}"></div>
      <div style="display:flex;gap:6px;">
        <div class="st-field" style="flex:1;"><label>Qty</label><input class="input" id="eQty" type="number" value="${row.qty || 0}"></div>
        <div class="st-field" style="flex:1;"><label>Reorder</label><input class="input" id="eReorder" type="number" value="${row.reorder_level || 0}"></div>
      </div>
      <div style="display:flex;gap:6px;">
        <div class="st-field" style="flex:1;"><label>Harga Jual</label><input class="input" id="ePrice" type="number" step="0.01" value="${row.price || 0}"></div>
        <div class="st-field" style="flex:1;"><label>Kos</label><input class="input" id="eCost" type="number" step="0.01" value="${row.cost || 0}"></div>
      </div>
      <div class="st-field"><label>Kategori</label>
        <select class="set-select" id="eCat">
          <option${(row.category||'SPAREPART')==='SPAREPART'?' selected':''}>SPAREPART</option>
          <option${row.category==='FAST SERVICE'?' selected':''}>FAST SERVICE</option>
          <option${row.category==='ACCESSORIES'?' selected':''}>ACCESSORIES</option>
        </select>
      </div>
      <div style="display:flex;gap:8px;">
        <button class="st-btn blue" id="eSave"><i class="fas fa-save"></i> SIMPAN</button>
        <button class="st-btn red" id="eDel"><i class="fas fa-trash"></i> PADAM</button>
      </div>`;
    $('mEdit').classList.add('show');
    $('eSave').addEventListener('click', async () => {
      const patch = {
        sku: $('eSku').value.trim(),
        part_name: $('eName').value.trim(),
        qty: Number($('eQty').value) || 0,
        reorder_level: Number($('eReorder').value) || 0,
        price: Number($('ePrice').value) || 0,
        cost: Number($('eCost').value) || 0,
        category: $('eCat').value,
      };
      const { error } = await window.sb.from('stock_parts').update(patch).eq('id', row.id);
      if (error) { snack('Gagal: ' + error.message, true); return; }
      snack('Disimpan'); closeMod('mEdit');
      ALL = await fetchStock(); refresh();
    });
    $('eDel').addEventListener('click', async () => {
      if (!confirm('Padam ' + row.sku + '?')) return;
      const { error } = await window.sb.from('stock_parts').delete().eq('id', row.id);
      if (error) { snack('Gagal: ' + error.message, true); return; }
      snack('Dipadam'); closeMod('mEdit');
      ALL = await fetchStock(); refresh();
    });
  }

  // History (used/return)
  function fmtDate(iso) {
    if (!iso) return '—';
    try { return new Date(iso).toLocaleString('en-MY', { dateStyle: 'short', timeStyle: 'short' }); } catch (_) { return iso; }
  }
  function esc(s) { return (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

  async function loadUsedHistory() {
    $('usedBody').innerHTML = '<p style="color:#64748b;padding:20px;">Memuatkan…</p>';
    // Build part list for filter
    const partOptions = ALL.map((p) => `<option value="${p.id}">${esc(p.sku || '')} — ${esc(p.part_name || '')}</option>`).join('');
    // Query stock_usage joined with jobs
    const { data: usage, error } = await window.sb
      .from('stock_usage')
      .select('id, stock_part_id, qty, used_at, used_by, reason, part_name, job_id, jobs(siri, nama, tel, created_at)')
      .eq('branch_id', branchId)
      .order('used_at', { ascending: false })
      .limit(500);
    if (error) {
      $('usedBody').innerHTML = `<p style="color:#ef4444;padding:20px;">Ralat: ${esc(error.message)}</p>`;
      return;
    }
    const rows = usage || [];
    const renderList = (filterId) => {
      const filtered = filterId ? rows.filter((r) => r.stock_part_id === filterId) : rows;
      if (!filtered.length) return '<div class="st-empty"><i class="fas fa-inbox"></i><p>Tiada rekod used.</p></div>';
      return filtered.map((r) => {
        const part = ALL.find((p) => p.id === r.stock_part_id);
        const partLbl = part ? `${part.sku || ''} — ${part.part_name || ''}` : (r.part_name || '—');
        const j = r.jobs || {};
        return `<div class="st-hist-row">
          <div style="width:36px;height:36px;border-radius:8px;background:#f9731622;color:#f97316;display:flex;align-items:center;justify-content:center;font-weight:900;">${r.qty || 1}</div>
          <div style="flex:1;min-width:0;">
            <div style="font-weight:900;font-size:12px;color:#0f172a;">${esc(partLbl)}</div>
            <div style="font-size:10px;color:#64748b;margin-top:2px;">
              <i class="fas fa-hashtag"></i> ${esc(j.siri || '—')} ·
              <i class="fas fa-user"></i> ${esc(j.nama || '—')} ·
              <i class="fas fa-phone"></i> ${esc(j.tel || '—')}
            </div>
            <div style="font-size:10px;color:#94a3b8;margin-top:2px;">
              <i class="fas fa-clock"></i> ${esc(fmtDate(r.used_at))}${r.used_by ? ' · ' + esc(r.used_by) : ''}
            </div>
          </div>
        </div>`;
      }).join('');
    };
    $('usedBody').innerHTML = `
      <div class="st-field">
        <label>FILTER PART</label>
        <select class="set-select" id="usedFilter">
          <option value="">— SEMUA —</option>
          ${partOptions}
        </select>
      </div>
      <div id="usedList">${renderList('')}</div>`;
    $('usedFilter').addEventListener('change', (e) => {
      $('usedList').innerHTML = renderList(e.target.value);
    });
  }

  async function loadReturnHistory() {
    $('returnBody').innerHTML = '<p style="color:#64748b;padding:20px;">Memuatkan…</p>';
    const partIds = ALL.map((p) => p.id);
    if (!partIds.length) {
      $('returnBody').innerHTML = '<div class="st-empty"><i class="fas fa-inbox"></i><p>Tiada stok.</p></div>';
      return;
    }
    const { data: rets, error } = await window.sb
      .from('stock_returns')
      .select('*')
      .in('stock_part_id', partIds)
      .order('returned_at', { ascending: false })
      .limit(500);
    if (error) {
      $('returnBody').innerHTML = `<p style="color:#ef4444;padding:20px;">Ralat: ${esc(error.message)}</p>`;
      return;
    }
    const rows = rets || [];
    if (!rows.length) {
      $('returnBody').innerHTML = '<div class="st-empty"><i class="fas fa-inbox"></i><p>Tiada rekod return.</p></div>';
      return;
    }
    $('returnBody').innerHTML = rows.map((r) => {
      const part = ALL.find((p) => p.id === r.stock_part_id);
      const partLbl = part ? `${part.sku || ''} — ${part.part_name || ''}` : '—';
      return `<div class="st-hist-row">
        <div style="width:36px;height:36px;border-radius:8px;background:#ef444422;color:#ef4444;display:flex;align-items:center;justify-content:center;font-weight:900;">${r.qty || 1}</div>
        <div style="flex:1;min-width:0;">
          <div style="font-weight:900;font-size:12px;color:#0f172a;">${esc(partLbl)}</div>
          <div style="font-size:10px;color:#64748b;margin-top:2px;">
            <i class="fas fa-comment"></i> ${esc(r.reason || '—')}${r.staff ? ' · <i class="fas fa-user"></i> ' + esc(r.staff) : ''}
          </div>
          <div style="font-size:10px;color:#94a3b8;margin-top:2px;">
            <i class="fas fa-clock"></i> ${esc(fmtDate(r.returned_at))}
          </div>
        </div>
      </div>`;
    }).join('');
  }

  $('btnUsed').addEventListener('click', () => {
    $('mUsed').classList.add('show');
    loadUsedHistory();
  });
  $('btnReturn').addEventListener('click', () => {
    $('mReturn').classList.add('show');
    loadReturnHistory();
  });

  $('stSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('btnScan') && $('btnScan').addEventListener('click', () => {
    const v = prompt('Masuk barcode:'); if (v) { $('stSearch').value = v; searchQ = v; refresh(); }
  });

  window.sb.channel('stock_parts-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'stock_parts', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchStock(); refresh(); })
    .subscribe();

  ALL = await fetchStock();
  refresh();
})();
