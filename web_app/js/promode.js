/* promode.js — Supabase. Mirror profesional_screen.dart. Tables: pro_walkin, pro_dealers, branches. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  function payloadOf(r) { try { return typeof r.payload === 'string' ? JSON.parse(r.payload) : (r.payload || {}); } catch (e) { return {}; } }
  const fmtDT = (iso) => { if (!iso) return ''; const d = new Date(iso); return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`; };

  let WALKIN = [];
  let DEALERS = [];
  let branch = null;
  let activeTab = 'online';
  let searchQ = '';
  let showArchived = false;

  async function fetchBranch() {
    const { data } = await window.sb.from('branches').select('*').eq('id', branchId).single();
    return data;
  }
  async function fetchWalkin() {
    const { data } = await window.sb.from('pro_walkin').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    return data || [];
  }
  async function fetchDealers() {
    const { data } = await window.sb.from('pro_dealers').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(2000);
    return data || [];
  }

  function renderStatus() {
    const on = branch && branch.pro_mode === true;
    $('pmBadge').innerHTML = on ? '<i class="fas fa-crown" style="color:#eab308;"></i>' : '<i class="fas fa-power-off"></i>';
    $('pmTitle').textContent = on ? 'Pro Mode AKTIF' : 'Pro Mode TIDAK AKTIF';
    $('pmSub').innerHTML = `${branch?.name || '—'} · <a href="#" id="pmToggleLink" style="color:#2563eb;">${on ? 'Nyahaktif' : 'Aktifkan'}</a>`;
    const tlink = document.getElementById('pmToggleLink');
    if (tlink) tlink.addEventListener('click', async (e) => {
      e.preventDefault();
      const { error } = await window.sb.from('branches').update({ pro_mode: !on }).eq('id', branchId);
      if (error) { alert('Gagal: ' + error.message); return; }
      branch = await fetchBranch();
      renderStatus();
    });
  }

  function filterTasks() {
    const q = searchQ.toLowerCase();
    return WALKIN.filter((r) => {
      const p = payloadOf(r);
      const isOnline = p.source === 'ONLINE' || p.source === 'online' || p.channel === 'online';
      if (activeTab === 'online' && !isOnline) return false;
      if (activeTab === 'offline' && isOnline) return false;
      const st = (r.status || 'PENDING').toUpperCase();
      if (!showArchived && (st === 'DONE' || st === 'ARCHIVED')) return false;
      if (q) {
        const hay = [(p.siri||''),(p.nama||''),(p.model||''),(p.sender||'')].join(' ').toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }

  function refresh() {
    const tasks = filterTasks();
    $('pmCount').textContent = tasks.length;
    $('listTitle').textContent = activeTab === 'online' ? 'Task Online' : 'Task Offline';
    $('pmEmpty').hidden = tasks.length > 0;
    $('pmList').innerHTML = tasks.map((r) => {
      const p = payloadOf(r);
      const st = r.status || 'PENDING';
      return `<div class="pm-task" data-id="${r.id}">
        <div class="pm-task__hd">
          <span class="pm-task__title">${p.nama || p.sender || '—'}</span>
          <span class="pm-task__status" data-st="${st}">${st}</span>
        </div>
        <div class="pm-task__body">
          <div>${p.model || ''} · ${p.siri || ''}</div>
          <div class="pm-task__meta">${fmtDT(r.created_at)}</div>
        </div>
        <div class="pm-task__actions">
          ${st !== 'DONE' ? '<button class="pm-btn pm-done">TANDA SIAP</button>' : ''}
          <button class="pm-btn pm-del">PADAM</button>
        </div>
      </div>`;
    }).join('');
    $('pmList').querySelectorAll('.pm-task').forEach((el) => {
      const id = el.dataset.id;
      el.querySelector('.pm-done') && el.querySelector('.pm-done').addEventListener('click', async (e) => {
        e.stopPropagation();
        const { error } = await window.sb.from('pro_walkin').update({ status: 'DONE' }).eq('id', id);
        if (error) alert('Gagal: ' + error.message);
      });
      el.querySelector('.pm-del') && el.querySelector('.pm-del').addEventListener('click', async (e) => {
        e.stopPropagation();
        if (!confirm('Padam?')) return;
        await window.sb.from('pro_walkin').delete().eq('id', id);
      });
    });

    $('pmDealerCount').textContent = DEALERS.length;
    $('pmDealerEmpty').hidden = DEALERS.length > 0;
    $('pmDealers').innerHTML = DEALERS.map((d) => `<div class="pm-dealer">
      <div class="pm-dealer__nm">${d.nama || '—'}</div>
      <div class="pm-dealer__tel">${d.tel || ''}</div>
    </div>`).join('');
  }

  document.querySelectorAll('.pm-tab').forEach((b) => b.addEventListener('click', () => {
    document.querySelectorAll('.pm-tab').forEach((x) => x.classList.remove('is-active'));
    b.classList.add('is-active');
    activeTab = b.dataset.tab;
    refresh();
  }));
  $('pmSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('pmArchived').addEventListener('change', (e) => { showArchived = e.target.checked; refresh(); });

  function toast(id, msg) {
    const t = document.getElementById(id); if (!t) { alert(msg); return; }
    t.textContent = msg; t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 1800);
  }

  // ── Tambah Dealer modal ───────────────────────────────────
  const pmAddDealerBtn = $('pmAddDealerBtn');
  if (pmAddDealerBtn) pmAddDealerBtn.addEventListener('click', () => {
    ['pmDlNama', 'pmDlKod', 'pmDlTel', 'pmDlAlamat', 'pmDlKom'].forEach((k) => { const el = $(k); if (el) el.value = ''; });
    $('pmDealerModal').classList.add('is-open');
  });
  const pmDealerClose = $('pmDealerClose');
  if (pmDealerClose) pmDealerClose.addEventListener('click', () => $('pmDealerModal').classList.remove('is-open'));
  const pmDlSubmit = $('pmDlSubmit');
  if (pmDlSubmit) pmDlSubmit.addEventListener('click', async () => {
    const nama = $('pmDlNama').value.trim();
    const kod = $('pmDlKod').value.trim();
    const tel = $('pmDlTel').value.trim();
    const alamat = $('pmDlAlamat').value.trim();
    const kom = parseFloat($('pmDlKom').value || '0') || 0;
    if (!nama) return toast('pmDlToast', 'Nama kedai wajib');
    if (!tel) return toast('pmDlToast', 'Tel wajib');
    const { error } = await window.sb.from('pro_dealers').insert({
      tenant_id: tenantId,
      branch_id: branchId,
      nama_kedai: nama,
      phone: tel,
      alamat,
      payload: { kod_dealer: kod, komisen: kom },
    });
    if (error) return toast('pmDlToast', 'Gagal: ' + error.message);
    toast('pmDlToast', 'Dealer disimpan');
    setTimeout(() => $('pmDealerModal').classList.remove('is-open'), 700);
    DEALERS = await fetchDealers(); refresh();
  });

  // ── Tambah Walk-in modal ──────────────────────────────────
  const pmAddWalkinBtn = $('pmAddWalkinBtn');
  if (pmAddWalkinBtn) pmAddWalkinBtn.addEventListener('click', () => {
    ['pmWkNama', 'pmWkTel', 'pmWkItem', 'pmWkHarga', 'pmWkTarikh'].forEach((k) => { const el = $(k); if (el) el.value = ''; });
    const d = new Date(); const iso = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
    $('pmWkTarikh').value = iso;
    $('pmWalkinModal').classList.add('is-open');
  });
  const pmWalkinClose = $('pmWalkinClose');
  if (pmWalkinClose) pmWalkinClose.addEventListener('click', () => $('pmWalkinModal').classList.remove('is-open'));
  const pmWkSubmit = $('pmWkSubmit');
  if (pmWkSubmit) pmWkSubmit.addEventListener('click', async () => {
    const nama = $('pmWkNama').value.trim();
    const tel = $('pmWkTel').value.trim();
    const item = $('pmWkItem').value.trim();
    const harga = parseFloat($('pmWkHarga').value || '0') || 0;
    const tarikh = $('pmWkTarikh').value;
    if (!nama) return toast('pmWkToast', 'Nama wajib');
    if (!tel) return toast('pmWkToast', 'Tel wajib');
    if (!item) return toast('pmWkToast', 'Item wajib');
    const row = {
      tenant_id: tenantId,
      branch_id: branchId,
      nama, tel,
      model: item,
      harga,
      status: 'PENDING',
      archived: false,
      payload: { source: 'OFFLINE', channel: 'offline', tarikh },
    };
    if (tarikh) row.created_at = new Date(tarikh + 'T00:00:00').toISOString();
    const { error } = await window.sb.from('pro_walkin').insert(row);
    if (error) return toast('pmWkToast', 'Gagal: ' + error.message);
    toast('pmWkToast', 'Walk-in disimpan');
    setTimeout(() => $('pmWalkinModal').classList.remove('is-open'), 700);
    WALKIN = await fetchWalkin(); refresh();
  });

  window.sb.channel('pm-walkin-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pro_walkin', filter: `branch_id=eq.${branchId}` }, async () => { WALKIN = await fetchWalkin(); refresh(); }).subscribe();
  window.sb.channel('pm-dealers-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pro_dealers', filter: `branch_id=eq.${branchId}` }, async () => { DEALERS = await fetchDealers(); refresh(); }).subscribe();

  [branch, WALKIN, DEALERS] = await Promise.all([fetchBranch(), fetchWalkin(), fetchDealers()]);
  renderStatus();
  refresh();
})();
