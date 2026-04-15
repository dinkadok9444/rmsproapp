/* kerugian.js — Supabase. Mirror lost_screen.dart. Table: losses. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function toast(msg) { const t = $('lsToast'); if (!t) return; t.textContent = msg; t.hidden = false; setTimeout(() => { t.hidden = true; }, 1800); }

  let ALL = [];
  let searchQ = '';
  let sort = 'ZA';
  let chipFilter = 'ALL';
  let editingId = null;
  let delTargetId = null;

  async function fetchAll() {
    const { data, error } = await window.sb.from('losses').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    if (error) { console.error(error); return []; }
    return data || [];
  }

  function jenisOf(r) { return r.item_type || 'Lain-lain'; }

  function refresh() {
    const q = searchQ.toLowerCase();
    let rows = ALL.filter((r) => {
      if (chipFilter !== 'ALL' && jenisOf(r) !== chipFilter) return false;
      if (!q) return true;
      return (r.item_name||'').toLowerCase().includes(q) || (r.reason||'').toLowerCase().includes(q) || (r.siri||'').toLowerCase().includes(q) || jenisOf(r).toLowerCase().includes(q);
    });
    rows.sort((a, b) => sort === 'AZ' ? (a.created_at||'').localeCompare(b.created_at||'') : (b.created_at||'').localeCompare(a.created_at||''));

    const total = ALL.reduce((s, r) => s + (Number(r.estimated_value) || 0), 0);
    $('lsTotal').textContent = fmtRM(total);
    $('lsCount').textContent = ALL.length + ' rekod';

    // chips
    const jenisSet = Array.from(new Set(ALL.map(jenisOf)));
    $('lsChips').innerHTML = ['ALL', ...jenisSet].map((j) => `<button class="lost-chip${chipFilter===j?' is-active':''}" data-j="${j}">${j==='ALL'?'SEMUA':j}</button>`).join('');
    $('lsChips').querySelectorAll('.lost-chip').forEach((el) => el.addEventListener('click', () => { chipFilter = el.dataset.j; refresh(); }));

    $('lsEmpty').classList.toggle('hidden', rows.length > 0);
    $('lsList').innerHTML = rows.map((r) => `
      <div class="lost-item" data-id="${r.id}">
        <div class="lost-item__top">
          <span class="lost-item__siri">${jenisOf(r)}</span>
          <span class="lost-item__status" style="color:#dc2626;">${fmtRM(r.estimated_value)}</span>
        </div>
        <div class="lost-item__body">
          <div><i class="fas fa-box"></i> ${r.item_name || '—'}</div>
          ${r.siri ? `<div><i class="fas fa-hashtag"></i> ${r.siri}</div>` : ''}
          <div><i class="fas fa-comment"></i> ${r.reason || '-'}</div>
        </div>
      </div>`).join('');
    $('lsList').querySelectorAll('.lost-item').forEach((el) => el.addEventListener('click', () => openEdit(ALL.find((r) => r.id === el.dataset.id))));
  }

  function openNew() {
    editingId = null;
    $('lsFormTitle').textContent = 'REKOD KERUGIAN';
    $('lsSubmitLbl').textContent = 'SIMPAN';
    $('lsJenis').value = 'Lain-lain';
    ['lsSiri','lsJumlah','lsKeterangan'].forEach((k) => $(k).value = '');
    $('lsFormModal').classList.add('is-open');
  }
  function openEdit(row) {
    if (!row) return;
    editingId = row.id;
    $('lsFormTitle').textContent = 'EDIT KERUGIAN';
    $('lsSubmitLbl').textContent = 'KEMASKINI';
    $('lsJenis').value = row.item_type || 'Lain-lain';
    $('lsSiri').value = row.siri || '';
    $('lsJumlah').value = row.estimated_value || '';
    $('lsKeterangan').value = row.reason || '';
    $('lsFormModal').classList.add('is-open');
  }

  $('lsNewBtn').addEventListener('click', openNew);
  $('lsFormClose').addEventListener('click', () => $('lsFormModal').classList.remove('is-open'));

  $('lsSubmit').addEventListener('click', async () => {
    const jenis = $('lsJenis').value;
    const amount = Number($('lsJumlah').value);
    const reason = $('lsKeterangan').value.trim();
    if (!amount) { toast('Jumlah wajib'); return; }
    const payload = {
      item_type: jenis,
      item_name: jenis,
      quantity: 1,
      estimated_value: amount,
      reason,
      siri: $('lsSiri').value.trim() || null,
      status: 'REPORTED',
    };
    if (editingId) {
      const { error } = await window.sb.from('losses').update(payload).eq('id', editingId);
      if (error) { toast('Gagal: ' + error.message); return; }
      toast('Dikemaskini');
    } else {
      payload.tenant_id = tenantId; payload.branch_id = branchId;
      payload.reported_by = ctx.nama || ctx.email;
      const { error } = await window.sb.from('losses').insert(payload);
      if (error) { toast('Gagal: ' + error.message); return; }
      toast('Direkod');
    }
    $('lsFormModal').classList.remove('is-open');
    ALL = await fetchAll(); refresh();
  });

  // Long-press / right-click delete (simple: add delete btn via double-click)
  $('lsList').addEventListener('dblclick', (e) => {
    const item = e.target.closest('.lost-item');
    if (!item) return;
    delTargetId = item.dataset.id;
    $('lsDeleteModal').classList.add('is-open');
  });
  $('lsDelCancel').addEventListener('click', () => $('lsDeleteModal').classList.remove('is-open'));
  $('lsDelOk').addEventListener('click', async () => {
    if (!delTargetId) return;
    const { error } = await window.sb.from('losses').delete().eq('id', delTargetId);
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Dipadam'); $('lsDeleteModal').classList.remove('is-open');
    ALL = await fetchAll(); refresh();
  });

  $('lsSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('lsSort').addEventListener('change', (e) => { sort = e.target.value; refresh(); });

  window.sb.channel('losses-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'losses', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchAll(); refresh(); })
    .subscribe();

  ALL = await fetchAll();
  refresh();
})();
