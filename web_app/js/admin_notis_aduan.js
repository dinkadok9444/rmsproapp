/* Admin → Notis Aduan. Mirror notis_aduan_screen.dart.
   Table: system_complaints (id, subject, description, assigned_to, status, created_at). */
(function () {
  'use strict';

  const listEl = document.getElementById('aduanList');
  const metaEl = document.getElementById('meta');
  let rows = [];

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnReload').addEventListener('click', load);

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    listEl.innerHTML = `<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i> Memuat…</div>`;
    const { data, error } = await window.sb
      .from('system_complaints')
      .select('*')
      .neq('status', 'DELETED')
      .order('created_at', { ascending: false });
    if (error) { listEl.innerHTML = `<div class="admin-error">${error.message}</div>`; metaEl.textContent = ''; return; }
    rows = data || [];
    metaEl.textContent = `Menunjukkan ${rows.length} aduan aktif`;
    render();
  }

  function render() {
    if (!rows.length) { listEl.innerHTML = `<div class="admin-empty">Tiada aduan</div>`; return; }
    listEl.innerHTML = rows.map(card).join('');
    listEl.querySelectorAll('[data-act="done"]').forEach(b => b.addEventListener('click', () => markSelesai(b.dataset.id)));
    listEl.querySelectorAll('[data-act="del"]').forEach(b => b.addEventListener('click', () => softDelete(b.dataset.id)));
  }

  function card(a) {
    const status = (a.status || 'BARU').toUpperCase();
    const isBaru = status === 'BARU';
    return `
      <div class="aduan-card">
        <div class="aduan-card__head">
          <div class="aduan-card__sender"><i class="fas fa-user"></i> ${escapeHtml((a.assigned_to || '-').toUpperCase())}</div>
          <span class="aduan-badge ${isBaru ? 'is-baru' : 'is-done'}">${escapeHtml(status)}</span>
        </div>
        <div class="aduan-card__meta">
          <span><i class="fas fa-clock"></i> ${fmtTs(a.created_at)}</span>
        </div>
        <div class="aduan-card__title">${escapeHtml(a.subject || '-')}</div>
        <div class="aduan-card__desc">${escapeHtml(a.description || '-')}</div>
        <div class="aduan-card__actions">
          ${isBaru ? `<button class="chip chip-green" data-act="done" data-id="${a.id}"><i class="fas fa-check"></i> SELESAI</button>` : ''}
          <button class="chip chip-red" data-act="del" data-id="${a.id}"><i class="fas fa-trash"></i> PADAM</button>
        </div>
      </div>
    `;
  }

  async function markSelesai(id) {
    const { error } = await window.sb.from('system_complaints').update({ status: 'SELESAI' }).eq('id', id);
    if (error) { alert('Ralat: ' + error.message); return; }
    await load();
  }

  async function softDelete(id) {
    if (!confirm('Aduan ini akan dipindahkan ke Tong Sampah. Teruskan?')) return;
    const { error } = await window.sb.from('system_complaints').update({ status: 'DELETED' }).eq('id', id);
    if (error) { alert('Ralat: ' + error.message); return; }
    await load();
  }

  function fmtTs(v) {
    if (!v) return '-';
    const d = new Date(v); if (isNaN(d.getTime())) return '-';
    const p = n => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }
})();
