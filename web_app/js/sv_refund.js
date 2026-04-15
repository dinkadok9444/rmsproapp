/* sv_refund.js — Supervisor Refund/Claim tab. Mirror sv_refund_tab.dart + sv_claim_tab.dart.
   Tables: refunds (refund_status PENDING|APPROVED|REJECTED|COMPLETED), claims (claim_status
   CLAIM WAITING APPROVAL|CLAIM APPROVE|CLAIM REJECTED). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const sb = window.sb;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const $ = (id) => document.getElementById(id);
  const t = (k, p) => (window.svI18n ? window.svI18n.t(k, p) : k);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtDate = (iso) => {
    if (!iso) return '-'; const d = new Date(iso); if (isNaN(d)) return '-';
    const p = (n) => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)}`;
  };
  function toast(msg, err) {
    const x = document.createElement('div');
    x.className = 'admin-toast'; if (err) x.style.background = 'var(--red, #EF4444)';
    x.innerHTML = `<i class="fas fa-${err ? 'circle-exclamation' : 'circle-check'}"></i> ${esc(msg)}`;
    document.body.appendChild(x); setTimeout(() => x.remove(), 2600);
  }
  const parseJson = (v) => { try { return typeof v === 'string' && v ? JSON.parse(v) : (v && typeof v === 'object' ? v : {}); } catch { return {}; } };

  // ── State
  let segment = 'REFUND';
  let search = '';
  let filterStatus = 'ALL';
  let refunds = [], claims = [];

  // ── Status maps per segment
  const REFUND_STATUSES = ['ALL','PENDING','APPROVED','REJECTED','COMPLETED'];
  const CLAIM_STATUSES  = ['ALL','CLAIM WAITING APPROVAL','CLAIM APPROVE','CLAIM REJECTED'];
  const CLAIM_LABEL = { 'CLAIM WAITING APPROVAL': 'PENDING', 'CLAIM APPROVE': 'APPROVED', 'CLAIM REJECTED': 'REJECTED' };
  const statusColor = (s) => {
    const u = String(s || '').toUpperCase();
    if (u === 'APPROVED' || u === 'COMPLETED' || u === 'CLAIM APPROVE') return '#10B981';
    if (u === 'REJECTED' || u === 'CLAIM REJECTED') return '#EF4444';
    return '#F59E0B';
  };

  // ── Data load
  async function loadRefunds() {
    const { data, error } = await sb.from('refunds').select('*').eq('branch_id', branchId).order('created_at', { ascending: false });
    if (error) { toast(t('c.errLoad'), true); return; }
    refunds = (data || []).map(r => {
      const extra = parseJson(r.processed_by);
      return { id: r.id, siri: r.siri || '', nama: r.nama || extra.namaCust || '', model: r.model || extra.model || '', amount: Number(r.refund_amount) || 0,
        reason: r.reason || '', status: r.refund_status || 'PENDING', ts: r.created_at, rejectReason: extra.rejectReason || '' };
    });
    if (segment === 'REFUND') render();
  }
  async function loadClaims() {
    const { data, error } = await sb.from('claims').select('*').eq('branch_id', branchId).order('created_at', { ascending: false });
    if (error) { toast(t('c.errLoad'), true); return; }
    claims = (data || []).map(r => {
      const extra = parseJson(r.catatan);
      return { id: r.id, claimID: r.claim_code || '', siri: r.siri || '', nama: r.nama || extra.nama || '', model: r.model || extra.model || '',
        status: r.claim_status || 'CLAIM WAITING APPROVAL', rejectReason: r.reject_reason || extra.rejectReason || '', ts: r.created_at };
    });
    if (segment === 'CLAIM') render();
  }
  sb.channel(`sv-refunds-${branchId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'refunds', filter: `branch_id=eq.${branchId}` }, loadRefunds).subscribe();
  sb.channel(`sv-claims-${branchId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'claims', filter: `branch_id=eq.${branchId}` }, loadClaims).subscribe();

  // ── Filter
  function getList() { return segment === 'REFUND' ? refunds : claims; }
  function filtered() {
    let list = getList().slice();
    const q = search.trim().toUpperCase();
    if (q) list = list.filter(r =>
      String(r.siri).toUpperCase().includes(q) ||
      String(r.nama).toUpperCase().includes(q) ||
      String(r.claimID || '').toUpperCase().includes(q)
    );
    if (filterStatus !== 'ALL') list = list.filter(r => String(r.status).toUpperCase() === filterStatus.toUpperCase());
    return list;
  }
  function pendingCount() {
    if (segment === 'REFUND') return refunds.filter(r => String(r.status).toUpperCase() === 'PENDING').length;
    return claims.filter(r => String(r.status).toUpperCase() === 'CLAIM WAITING APPROVAL').length;
  }

  // ── Render
  function render() {
    const isR = segment === 'REFUND';
    // Title + badge
    const titleEl = $('svRcTitle');
    titleEl.innerHTML = `<i class="fas fa-${isR ? 'money-bill-transfer' : 'file-shield'}"></i><span>${esc(t(isR ? 'rc.titleRefund' : 'rc.titleClaim'))}</span><span class="sv-rc__badge${pendingCount()>0?'':' hidden'}" id="svRcPending">${t('rc.pending', { n: pendingCount() })}</span>`;

    // Chips
    const chips = $('svRcChips');
    const statuses = isR ? REFUND_STATUSES : CLAIM_STATUSES;
    chips.innerHTML = statuses.map(s => {
      const lbl = s === 'ALL' ? t('c.all').toUpperCase() : (CLAIM_LABEL[s] || s);
      return `<button data-s="${esc(s)}" class="${filterStatus===s?'is-active':''}">${esc(lbl)}</button>`;
    }).join('');

    // Body
    const list = filtered();
    const body = $('svRcBody');
    if (!list.length) {
      body.innerHTML = `<div class="sv-rc__empty"><i class="fas fa-receipt"></i><div>${esc(t(isR ? 'rc.emptyR' : 'rc.emptyC'))}</div></div>`;
      return;
    }
    body.innerHTML = list.map(r => {
      const status = String(r.status || '').toUpperCase();
      const displayStatus = CLAIM_LABEL[status] || status;
      const col = statusColor(status);
      const isPending = status === 'PENDING' || status === 'CLAIM WAITING APPROVAL';
      const isRejected = status === 'REJECTED' || status === 'CLAIM REJECTED';
      const amtBlock = isR ? `<div class="sv-rc__card-amt">RM ${(Number(r.amount)||0).toFixed(2)}</div>` : `<div class="sv-rc__card-claimid">${esc(r.claimID || '-')}</div>`;
      const actions = isPending ? `<div class="sv-rc__card-actions">
        <button class="sv-rc__btn-approve" data-act="approve" data-id="${esc(r.id)}"><i class="fas fa-check"></i> ${esc(t('rc.approve'))}</button>
        <button class="sv-rc__btn-reject" data-act="reject" data-id="${esc(r.id)}"><i class="fas fa-xmark"></i> ${esc(t('rc.reject'))}</button>
      </div>` : '';
      const rejBlock = (isRejected && r.rejectReason) ? `<div class="sv-rc__card-reject"><i class="fas fa-circle-info"></i> ${esc(t('rc.reason'))}: ${esc(r.rejectReason)}</div>` : '';
      return `<div class="sv-rc__card">
        <div class="sv-rc__card-head">
          <div class="sv-rc__card-siri">#${esc(r.siri || '-')}</div>
          <div class="sv-rc__card-status" style="color:${col};background:${col}26;border-color:${col}">${esc(displayStatus)}</div>
        </div>
        <div class="sv-rc__card-nama">${esc(r.nama || '-')}</div>
        <div class="sv-rc__card-sub">${esc(r.model || '-')}${isR ? `  |  ${esc(r.reason || '-')}` : ''}</div>
        <div class="sv-rc__card-foot">
          <div class="sv-rc__card-ts">${fmtDate(r.ts)}</div>
          ${amtBlock}
        </div>
        ${actions}
        ${rejBlock}
      </div>`;
    }).join('');
  }

  // ── Actions
  async function approve(id) {
    const isR = segment === 'REFUND';
    if (!confirm(t(isR ? 'rc.approveRQ' : 'rc.approveCQ'))) return;
    const nowIso = new Date().toISOString();
    const nowMs = Date.now();
    if (isR) {
      await sb.from('refunds').update({ refund_status: 'APPROVED', processed_at: nowIso }).eq('id', id);
      await mergeJson('refunds', 'processed_by', id, { approvedBy: 'SUPERVISOR', approvedAt: nowMs });
      toast(t('rc.approvedR'));
      loadRefunds();
    } else {
      await sb.from('claims').update({ claim_status: 'CLAIM APPROVE', approved_at: nowIso, approved_by: 'SUPERVISOR' }).eq('id', id);
      await mergeJson('claims', 'catatan', id, { approvedBy: 'SUPERVISOR', approvedAt: nowMs });
      toast(t('rc.approvedC'));
      loadClaims();
    }
  }
  async function reject(id) {
    const isR = segment === 'REFUND';
    const reason = prompt(t('rc.rejectQ')) || '';
    if (reason === null) return;
    const nowMs = Date.now();
    if (isR) {
      await sb.from('refunds').update({ refund_status: 'REJECTED' }).eq('id', id);
      await mergeJson('refunds', 'processed_by', id, { rejectedBy: 'SUPERVISOR', rejectReason: reason.trim(), rejectedAt: nowMs });
      toast(t('rc.rejectedR'));
      loadRefunds();
    } else {
      await sb.from('claims').update({ claim_status: 'CLAIM REJECTED', reject_reason: reason.trim() }).eq('id', id);
      await mergeJson('claims', 'catatan', id, { rejectedBy: 'SUPERVISOR', rejectReason: reason.trim(), rejectedAt: nowMs });
      toast(t('rc.rejectedC'));
      loadClaims();
    }
  }
  async function mergeJson(table, field, id, patch) {
    const { data } = await sb.from(table).select(field).eq('id', id).maybeSingle();
    const cur = parseJson(data && data[field]);
    const next = { ...cur, ...patch };
    await sb.from(table).update({ [field]: JSON.stringify(next) }).eq('id', id);
  }

  // ── Events
  $('svRcSegs').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-seg]'); if (!b) return;
    segment = b.dataset.seg;
    $('svRcSegs').querySelectorAll('button').forEach(x => x.classList.toggle('is-active', x === b));
    filterStatus = 'ALL';
    render();
  });
  $('svRcSearch').addEventListener('input', (e) => { search = e.target.value; render(); });
  $('svRcChips').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-s]'); if (!b) return;
    filterStatus = b.dataset.s; render();
  });
  $('svRcBody').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-act]'); if (!b) return;
    if (b.dataset.act === 'approve') approve(b.dataset.id);
    else if (b.dataset.act === 'reject') reject(b.dataset.id);
  });
  window.addEventListener('sv:lang:changed', render);

  await Promise.all([loadRefunds(), loadClaims()]);
  render();
})();
