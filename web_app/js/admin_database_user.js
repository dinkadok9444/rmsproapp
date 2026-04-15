/* Admin → Database User. Mirror database_user_screen.dart.
   Source: tenants table (nama_kedai, config.ownerName, config.ownerContact, config.negeri, created_at). */
(function () {
  'use strict';

  const listEl = document.getElementById('userList');
  const searchEl = document.getElementById('searchInput');
  const countEl = document.getElementById('countMeta');
  let users = [], filtered = [], sortMode = 'newest';

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnReload').addEventListener('click', load);
  searchEl.addEventListener('input', applyFilter);
  document.querySelectorAll('.sort-chip').forEach(c => c.addEventListener('click', () => {
    document.querySelectorAll('.sort-chip').forEach(x => x.classList.remove('is-active'));
    c.classList.add('is-active');
    sortMode = c.dataset.sort;
    applyFilter();
  }));

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    listEl.innerHTML = `<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i> Memuat…</div>`;
    const { data, error } = await window.sb
      .from('tenants')
      .select('id, nama_kedai, config, created_at')
      .order('created_at', { ascending: false })
      .limit(500);
    if (error) { listEl.innerHTML = `<div class="admin-error">${error.message}</div>`; return; }
    users = (data || []).map(r => {
      const c = (r.config && typeof r.config === 'object') ? r.config : {};
      return {
        id: r.id,
        namaKedai: r.nama_kedai || '-',
        ownerName: c.ownerName || '-',
        phone: String(c.ownerContact || ''),
        negeri: c.negeri || '',
        createdAt: r.created_at ? new Date(r.created_at).getTime() : 0,
      };
    });
    applyFilter();
  }

  function applyFilter() {
    const q = searchEl.value.trim().toLowerCase();
    filtered = users.filter(u =>
      !q ||
      u.namaKedai.toLowerCase().includes(q) ||
      u.ownerName.toLowerCase().includes(q) ||
      u.phone.toLowerCase().includes(q)
    );
    filtered.sort((a, b) => sortMode === 'newest' ? b.createdAt - a.createdAt : a.createdAt - b.createdAt);
    countEl.textContent = `${filtered.length} / ${users.length}`;
    render();
  }

  function render() {
    if (!filtered.length) { listEl.innerHTML = `<div class="admin-empty">Tiada data</div>`; return; }
    listEl.innerHTML = filtered.map(card).join('');
    listEl.querySelectorAll('[data-act="wa"]').forEach(b => b.addEventListener('click', () => openWa(b.dataset.phone)));
  }

  function card(u) {
    const hasPhone = u.phone.trim() !== '';
    return `
      <div class="user-card">
        <div class="user-card__name">${escapeHtml(u.namaKedai)}</div>
        <div class="user-card__owner">${escapeHtml(u.ownerName)}</div>
        ${u.negeri ? `<div class="user-card__negeri">${escapeHtml(u.negeri)}</div>` : ''}
        <button class="wa-btn ${hasPhone ? '' : 'is-disabled'}" data-act="wa" data-phone="${escapeHtml(u.phone)}" ${hasPhone ? '' : 'disabled'}>
          <i class="fab fa-whatsapp"></i>
          <span>${hasPhone ? escapeHtml(u.phone) : 'Tiada no telefon'}</span>
          ${hasPhone ? '<i class="fas fa-arrow-up-right-from-square"></i>' : ''}
        </button>
      </div>
    `;
  }

  function openWa(raw) {
    let p = String(raw).replace(/[^0-9]/g, '');
    if (!p) { alert('No telefon tidak sah'); return; }
    if (p.startsWith('0')) p = '6' + p;
    else if (!p.startsWith('6') && p.length >= 9) p = '6' + p;
    window.open(`https://wa.me/${p}`, '_blank');
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }
})();
