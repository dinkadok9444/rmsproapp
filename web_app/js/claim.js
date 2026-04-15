/* claim.js — Supabase. Mirror claim_warranty_screen.dart. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  function toast(msg) { const t = $('cwToast'); if (!t) return; t.textContent = msg; t.hidden = false; setTimeout(() => { t.hidden = true; }, 1800); }

  let ALL = [];
  let JOBS = [];
  let STAFF = [];
  let searchQ = '';
  let filter = 'ALL';
  let editingId = null;

  async function fetchClaims() {
    const { data, error } = await window.sb.from('claims').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    if (error) { console.error(error); return []; }
    return data || [];
  }
  async function fetchJobs() {
    const { data } = await window.sb.from('jobs').select('id,siri,nama,tel,model,kerosakan,total,status').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    return data || [];
  }
  async function fetchStaff() {
    const { data } = await window.sb.from('users').select('id,nama').eq('tenant_id', tenantId);
    return data || [];
  }

  function refresh() {
    const q = searchQ.toLowerCase();
    let rows = ALL.filter((r) => {
      if (filter === 'ALL') {
        const st = (r.claim_status || '').trim();
        if (st === 'Claim Approve' || st === 'Claim Complete') return false;
      } else if ((r.claim_status || '') !== filter) return false;
      if (!q) return true;
      return (r.siri||'').toLowerCase().includes(q) || (r.nama||'').toLowerCase().includes(q) || (r.tel||'').toLowerCase().includes(q) || (r.model||'').toLowerCase().includes(q) || (r.claim_code||'').toLowerCase().includes(q);
    });
    $('cwCount').textContent = rows.length;
    $('cwEmpty').classList.toggle('hidden', rows.length > 0);
    $('cwList').innerHTML = rows.map((r) => `
      <div class="lost-item" data-id="${r.id}">
        <div class="lost-item__top">
          <span class="lost-item__siri">${r.siri || '—'}</span>
          <span class="lost-item__status">${r.claim_status || 'Claim Waiting Approval'}</span>
        </div>
        <div class="lost-item__body">
          <div><i class="fas fa-user"></i> ${r.nama || '—'}</div>
          <div><i class="fas fa-mobile-screen"></i> ${r.model || '—'}</div>
          <div><i class="fas fa-hashtag"></i> ${r.claim_code || '—'}</div>
        </div>
      </div>`).join('');
    $('cwList').querySelectorAll('.lost-item').forEach((el) => {
      el.addEventListener('click', () => openUpdate(ALL.find((r) => r.id === el.dataset.id)));
    });
  }

  function staffOptions(sel) {
    return '<option value="">-</option>' + STAFF.map((s) => `<option value="${s.id}"${sel===s.id?' selected':''}>${s.nama}</option>`).join('');
  }

  function openUpdate(row) {
    if (!row) return;
    editingId = row.id;
    $('cwUpId').textContent = row.siri || '';
    $('cwUpInfo').innerHTML = `<div><b>${row.nama || '-'}</b> · ${row.model || '-'}</div><div style="font-size:11px;color:#64748b;">${row.claim_code || ''}</div>`;
    $('cwUpStatus').value = row.claim_status || 'Claim Waiting Approval';
    $('cwUpHantar').value = row.hantar_at ? row.hantar_at.slice(0,16) : '';
    $('cwUpSiap').value = row.siap_at ? row.siap_at.slice(0,16) : '';
    $('cwUpPickup').value = row.pickup_at ? row.pickup_at.slice(0,16) : '';
    $('cwUpStaffT').innerHTML = staffOptions(row.staff_terima);
    $('cwUpStaffR').innerHTML = staffOptions(row.staff_repair);
    $('cwUpStaffS').innerHTML = staffOptions(row.staff_serah);
    $('cwUpWType').value = row.warranty_type || 'TIADA';
    $('cwUpWTempoh').value = String(row.warranty_days || 7);
    $('cwUpNota').value = row.catatan || '';
    updateTempohVis();
    $('cwUpdateModal').classList.add('is-open');
  }
  function updateTempohVis() {
    const show = $('cwUpWType').value !== 'TIADA';
    $('cwUpWTempohWrap').classList.toggle('hidden', !show);
  }
  $('cwUpWType').addEventListener('change', updateTempohVis);

  $('cwUpSave').addEventListener('click', async () => {
    if (!editingId) return;
    const patch = {
      claim_status: $('cwUpStatus').value,
      hantar_at: $('cwUpHantar').value || null,
      siap_at: $('cwUpSiap').value || null,
      pickup_at: $('cwUpPickup').value || null,
      staff_terima: $('cwUpStaffT').value || null,
      staff_repair: $('cwUpStaffR').value || null,
      staff_serah: $('cwUpStaffS').value || null,
      warranty_type: $('cwUpWType').value,
      warranty_days: $('cwUpWType').value === 'TIADA' ? null : Number($('cwUpWTempoh').value),
      catatan: $('cwUpNota').value,
    };
    const { error } = await window.sb.from('claims').update(patch).eq('id', editingId);
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Disimpan');
    $('cwUpdateModal').classList.remove('is-open');
    ALL = await fetchClaims(); refresh();
  });

  $('cwUpDelete').addEventListener('click', () => { $('cwDelModal').classList.add('is-open'); });
  $('cwDelCancel').addEventListener('click', () => { $('cwDelModal').classList.remove('is-open'); });
  $('cwDelOk').addEventListener('click', async () => {
    if (!editingId) return;
    const { error } = await window.sb.from('claims').delete().eq('id', editingId);
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Dipadam');
    $('cwDelModal').classList.remove('is-open');
    $('cwUpdateModal').classList.remove('is-open');
    ALL = await fetchClaims(); refresh();
  });

  // Daftar claim (cari repair)
  $('cwNewBtn').addEventListener('click', () => {
    $('cwSearchModal').classList.add('is-open');
    $('cwRepairSearch').value = '';
    renderRepairHits('');
  });
  $('cwSearchClose').addEventListener('click', () => $('cwSearchModal').classList.remove('is-open'));
  $('cwUpClose').addEventListener('click', () => $('cwUpdateModal').classList.remove('is-open'));

  $('cwRepairSearch').addEventListener('input', (e) => renderRepairHits(e.target.value));
  function renderRepairHits(q) {
    q = (q || '').toLowerCase().trim();
    const hits = !q ? [] : JOBS.filter((j) => (j.siri||'').toLowerCase().includes(q) || (j.tel||'').toLowerCase().includes(q)).slice(0, 20);
    $('cwRepairCount').textContent = hits.length + ' keputusan';
    $('cwRepairResults').innerHTML = hits.map((j) => `
      <div class="cw-hit" data-id="${j.id}" style="padding:10px;border:1px solid #e2e8f0;border-radius:8px;margin-bottom:6px;cursor:pointer;">
        <div><b>${j.siri||''}</b> — ${j.nama||''}</div>
        <div style="font-size:11px;color:#64748b;">${j.tel||''} · ${j.model||''}</div>
      </div>`).join('');
    $('cwRepairResults').querySelectorAll('.cw-hit').forEach((el) => el.addEventListener('click', () => createClaim(JOBS.find((j) => j.id === el.dataset.id))));
  }

  async function createClaim(job) {
    if (!job) return;
    const code = 'CW' + Date.now().toString(36).toUpperCase().slice(-6);
    const { error } = await window.sb.from('claims').insert({
      tenant_id: tenantId, branch_id: branchId,
      siri: job.siri, nama: job.nama, tel: job.tel, model: job.model,
      claim_code: code, claim_status: 'Claim Waiting Approval',
      kerosakan: job.kerosakan, harga: job.total, job_id: job.id,
    });
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Claim dijana');
    $('cwSearchModal').classList.remove('is-open');
    ALL = await fetchClaims(); refresh();
  }

  $('cwSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('cwFilter').addEventListener('change', (e) => { filter = e.target.value; refresh(); });

  window.sb.channel('claims-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'claims', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchClaims(); refresh(); })
    .subscribe();

  [ALL, JOBS, STAFF] = await Promise.all([fetchClaims(), fetchJobs(), fetchStaff()]);
  refresh();
})();
