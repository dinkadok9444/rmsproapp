/* maklum-balas.js — Supabase. Customer feedback + rating. Table: customer_feedback. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtDate = (iso) => { if (!iso) return ''; const d = new Date(iso); return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()}`; };

  let ALL = [];
  let USERS = [];
  let searchQ = '';
  let filter = 'Semua_Terbaru';

  async function fetchAll() {
    const { data } = await window.sb.from('customer_feedback').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    return data || [];
  }
  async function fetchUsers() {
    const { data } = await window.sb.from('users').select('id,nama').eq('tenant_id', ctx.tenant_id);
    return data || [];
  }
  const userName = (id) => { const u = USERS.find((x) => x.id === id); return u ? u.nama : '-'; };

  function payloadOf(r) { try { return typeof r.payload === 'string' ? JSON.parse(r.payload) : (r.payload || {}); } catch (e) { return {}; } }

  function starBar(n) {
    let out = '';
    for (let i = 1; i <= 5; i++) out += `<i class="fas fa-star" style="color:${i<=n?'#f59e0b':'#e2e8f0'};"></i>`;
    return out;
  }

  function refresh() {
    let rows = ALL.slice();
    const q = searchQ.toLowerCase();
    if (q) rows = rows.filter((r) => (r.siri||'').toLowerCase().includes(q) || (r.nama||'').toLowerCase().includes(q) || (r.tel||'').toLowerCase().includes(q));

    if (filter.startsWith('Semua')) {
      rows.sort((a, b) => filter === 'Semua_Terbaru' ? (b.created_at||'').localeCompare(a.created_at||'') : (a.created_at||'').localeCompare(b.created_at||''));
    } else {
      const r = Number(filter);
      rows = rows.filter((x) => Number(x.rating) === r).sort((a, b) => (b.created_at||'').localeCompare(a.created_at||''));
    }

    const total = ALL.length;
    const avg = total ? (ALL.reduce((s, r) => s + (Number(r.rating) || 0), 0) / total) : 0;
    $('mbAvg').textContent = avg.toFixed(1);
    $('mbCount').textContent = total + ' Maklum Balas';
    $('mbShowing').textContent = 'Menunjukkan ' + rows.length + ' rekod';
    $('mbEmpty').classList.toggle('hidden', rows.length > 0);

    $('mbList').innerHTML = rows.map((r) => {
      const p = payloadOf(r);
      return `<div class="mb-card" data-id="${r.id}">
        <div class="mb-card__hd">
          <div><b>${r.siri || '—'}</b> · ${r.nama || ''}</div>
          <div>${starBar(Number(r.rating) || 0)}</div>
        </div>
        <div class="mb-card__body">
          <div>${p.komen || p.comment || ''}</div>
          <div class="mb-card__meta"><span>${r.tel || ''}</span><span>${fmtDate(r.created_at)}</span></div>
        </div>
        <div class="mb-card__staff">
          <button type="button" class="mb-staff-btn" data-t="${p.staff_terima||''}" data-r="${p.staff_repair||''}" data-s="${p.staff_serah||''}">
            <i class="fas fa-id-badge"></i> STAF
          </button>
        </div>
      </div>`;
    }).join('');

    $('mbList').querySelectorAll('.mb-staff-btn').forEach((b) => b.addEventListener('click', (e) => {
      e.stopPropagation();
      $('mbStaffTerima').textContent = userName(b.dataset.t);
      $('mbStaffRepair').textContent = userName(b.dataset.r);
      $('mbStaffSerah').textContent = userName(b.dataset.s);
      $('mbStaffModal').classList.add('is-open');
    }));
  }

  $('mbFilter').addEventListener('change', (e) => { filter = e.target.value; refresh(); });
  $('mbSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('mbSearchToggle').addEventListener('click', () => $('mbSearchWrap').classList.toggle('hidden'));
  $('mbStaffClose').addEventListener('click', () => $('mbStaffModal').classList.remove('is-open'));

  window.sb.channel('mb-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'customer_feedback', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchAll(); refresh(); }).subscribe();

  [ALL, USERS] = await Promise.all([fetchAll(), fetchUsers()]);
  refresh();
})();
