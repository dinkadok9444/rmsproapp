/* refund.js — Supabase. Mirror refund_screen.dart. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function toast(msg) { const t = $('rdToast'); if (!t) return; t.textContent = msg; t.hidden = false; setTimeout(() => { t.hidden = true; }, 1800); }

  let ALL = [];
  let searchQ = '';
  let sort = 'ZA';
  let foundJob = null;
  let approveTargetId = null;

  async function fetchAll() {
    const { data, error } = await window.sb.from('refunds').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    if (error) { console.error(error); return []; }
    return data || [];
  }

  function refresh() {
    const q = searchQ.toLowerCase();
    let rows = ALL.filter((r) => {
      if (!q) return true;
      return (r.siri||'').toLowerCase().includes(q) || (r.nama||'').toLowerCase().includes(q) || (r.reason||'').toLowerCase().includes(q);
    });
    rows.sort((a, b) => sort === 'AZ' ? (a.created_at||'').localeCompare(b.created_at||'') : (b.created_at||'').localeCompare(a.created_at||''));
    $('rdEmpty').classList.toggle('hidden', rows.length > 0);
    $('rdList').innerHTML = rows.map((r) => {
      const st = (r.refund_status || 'PENDING').toUpperCase();
      const stColor = st === 'APPROVED' ? '#10b981' : st === 'REJECTED' ? '#dc2626' : '#eab308';
      return `<div class="lost-item" data-id="${r.id}">
        <div class="lost-item__top">
          <span class="lost-item__siri">${r.siri || '—'}</span>
          <span class="lost-item__status" style="color:${stColor};">${st}</span>
        </div>
        <div class="lost-item__body">
          <div><i class="fas fa-user"></i> ${r.nama || '—'}</div>
          <div><i class="fas fa-money-bill"></i> ${fmtRM(r.refund_amount)}</div>
          <div><i class="fas fa-comment"></i> ${r.reason || '-'}</div>
        </div>
        <div class="lost-item__actions" style="display:flex;gap:6px;margin-top:8px;">
          ${st === 'PENDING' ? `<button class="btn-submit rd-approve" data-id="${r.id}" style="margin:0;padding:6px 10px;background:#10b981;">APPROVE</button>
            <button class="btn-danger rd-reject" data-id="${r.id}" style="padding:6px 10px;">REJECT</button>` : ''}
          <button class="btn-ghost rd-del" data-id="${r.id}" style="padding:6px 10px;">PADAM</button>
        </div>
      </div>`;
    }).join('');
    $('rdList').querySelectorAll('.rd-approve').forEach((el) => el.addEventListener('click', (e) => { e.stopPropagation(); approveTargetId = el.dataset.id; $('rdPass').value = ''; $('rdPassErr').classList.add('hidden'); $('rdApproveModal').classList.add('is-open'); }));
    $('rdList').querySelectorAll('.rd-reject').forEach((el) => el.addEventListener('click', async (e) => { e.stopPropagation(); const reason = prompt('Sebab reject?'); if (!reason) return; await window.sb.from('refunds').update({ refund_status: 'REJECTED', reject_reason: reason }).eq('id', el.dataset.id); toast('Ditolak'); ALL = await fetchAll(); refresh(); }));
    $('rdList').querySelectorAll('.rd-del').forEach((el) => el.addEventListener('click', async (e) => { e.stopPropagation(); if (!confirm('Padam?')) return; await window.sb.from('refunds').delete().eq('id', el.dataset.id); toast('Dipadam'); ALL = await fetchAll(); refresh(); }));
  }

  $('rdNewBtn').addEventListener('click', () => {
    foundJob = null;
    ['rdSiri','rdAmount','rdReason','rdAccName','rdBankName','rdAccNo'].forEach((k) => { if ($(k)) $(k).value = ''; });
    $('rdFound').classList.add('hidden');
    $('rdFormModal').classList.add('is-open');
  });
  $('rdFormClose').addEventListener('click', () => $('rdFormModal').classList.remove('is-open'));

  $('rdSearchBtn').addEventListener('click', async () => {
    const siri = $('rdSiri').value.trim();
    if (!siri) return;
    const { data } = await window.sb.from('jobs').select('*').eq('branch_id', branchId).eq('siri', siri).limit(1);
    if (!data || !data.length) { toast('Tidak jumpa'); $('rdFound').classList.add('hidden'); return; }
    foundJob = data[0];
    $('rdFoundNama').textContent = foundJob.nama || '-';
    $('rdFoundHarga').textContent = fmtRM(foundJob.total);
    $('rdFoundModel').textContent = foundJob.model || '-';
    $('rdFoundKero').textContent = foundJob.kerosakan || '-';
    $('rdFound').classList.remove('hidden');
    $('rdAmount').value = foundJob.total || '';
  });

  $('rdSubmit').addEventListener('click', async () => {
    if (!foundJob) { toast('Cari siri dulu'); return; }
    const amt = Number($('rdAmount').value);
    if (!amt) { toast('Amaun wajib'); return; }
    const payload = {
      tenant_id: tenantId, branch_id: branchId,
      siri: foundJob.siri, nama: foundJob.nama, job_id: foundJob.id,
      refund_amount: amt,
      refund_status: 'PENDING',
      reason: $('rdReason').value.trim(),
      payment_method: $('rdMethod').value,
      speed: $('rdSpeed').value,
      bank_name: $('rdBankName').value.trim(),
      account_name: $('rdAccName').value.trim(),
      account_no: $('rdAccNo').value.trim(),
    };
    const { error } = await window.sb.from('refunds').insert(payload);
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Dihantar');
    $('rdFormModal').classList.remove('is-open');
    ALL = await fetchAll(); refresh();
  });

  $('rdApproveCancel').addEventListener('click', () => $('rdApproveModal').classList.remove('is-open'));
  $('rdApproveOk').addEventListener('click', async () => {
    const pass = $('rdPass').value;
    if (pass !== '1234') { $('rdPassErr').classList.remove('hidden'); return; }
    if (!approveTargetId) return;
    const { error } = await window.sb.from('refunds').update({
      refund_status: 'APPROVED',
      processed_by: ctx.nama || ctx.email,
      processed_at: new Date().toISOString(),
    }).eq('id', approveTargetId);
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Diluluskan');
    $('rdApproveModal').classList.remove('is-open');
    ALL = await fetchAll(); refresh();
  });

  $('rdSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('rdSort').addEventListener('change', (e) => { sort = e.target.value; refresh(); });

  window.sb.channel('refunds-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'refunds', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchAll(); refresh(); })
    .subscribe();

  ALL = await fetchAll();
  refresh();
})();
