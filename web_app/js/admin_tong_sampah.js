/* Admin → Tong Sampah. Mirror tong_sampah_screen.dart.
   Sources: tenants & system_complaints (status='DELETED'). */
(function () {
  'use strict';

  const listEl = document.getElementById('list');
  const metaEl = document.getElementById('meta');
  const countEl = document.getElementById('countMeta');
  let items = [];

  const modal = document.getElementById('confirmModal');
  const confirmInput = document.getElementById('confirmInput');
  let pending = null;

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnReload').addEventListener('click', load);
  document.getElementById('confirmCancel').addEventListener('click', closeModal);
  modal.querySelector('.modal__backdrop').addEventListener('click', closeModal);
  document.getElementById('confirmOk').addEventListener('click', async () => {
    if (!pending) return;
    if (confirmInput.value.trim() !== 'PADAM') return;
    const { error } = await window.sb.from(pending.collection).delete().eq('id', pending.id);
    closeModal();
    if (error) { alert('Ralat: ' + error.message); return; }
    await load();
  });

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    listEl.innerHTML = `<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i> Memuat…</div>`;
    const [tenR, aduR] = await Promise.all([
      window.sb.from('tenants').select('id, nama_kedai, owner_id, config, created_at').eq('status', 'DELETED'),
      window.sb.from('system_complaints').select('id, subject, description, created_at').eq('status', 'DELETED'),
    ]);
    if (tenR.error) { listEl.innerHTML = `<div class="admin-error">${tenR.error.message}</div>`; return; }
    if (aduR.error) { listEl.innerHTML = `<div class="admin-error">${aduR.error.message}</div>`; return; }

    const all = [];
    for (const r of (tenR.data || [])) {
      const c = (r.config && typeof r.config === 'object') ? r.config : {};
      all.push({
        id: r.id,
        collection: 'tenants',
        type: 'AKAUN DEALER',
        label: r.nama_kedai || c.ownerName || r.owner_id || '-',
        sublabel: c.ownerName || '-',
        timestamp: r.created_at,
      });
    }
    for (const r of (aduR.data || [])) {
      all.push({
        id: r.id,
        collection: 'system_complaints',
        type: 'TIKET ADUAN',
        label: r.subject || '-',
        sublabel: r.description || '-',
        timestamp: r.created_at,
      });
    }
    all.sort((a, b) => new Date(b.timestamp || 0).getTime() - new Date(a.timestamp || 0).getTime());
    items = all;
    metaEl.textContent = `Menunjukkan ${items.length} rekod dipadam`;
    countEl.textContent = String(items.length);
    render();
  }

  function render() {
    if (!items.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-trash-can" style="font-size:32px;opacity:0.3;display:block;margin-bottom:10px"></i>Tong sampah kosong</div>`;
      return;
    }
    listEl.innerHTML = items.map(card).join('');
    listEl.querySelectorAll('[data-act="recover"]').forEach(b => b.addEventListener('click', () => recover(b.dataset.col, b.dataset.id)));
    listEl.querySelectorAll('[data-act="kill"]').forEach(b => b.addEventListener('click', () => openKill(b.dataset.col, b.dataset.id)));
  }

  function card(it) {
    const isDealer = it.type === 'AKAUN DEALER';
    return `
      <div class="trash-card">
        <div class="trash-card__head">
          <span class="trash-type ${isDealer ? 'is-dealer' : 'is-aduan'}">${it.type}</span>
          <span class="trash-ts"><i class="fas fa-clock"></i> ${fmtTs(it.timestamp)}</span>
        </div>
        <div class="trash-card__label">${escapeHtml(String(it.label).toUpperCase())}</div>
        <div class="trash-card__sub">${escapeHtml(it.sublabel || '-')}</div>
        <div class="trash-card__actions">
          <button class="chip chip-green" data-act="recover" data-col="${it.collection}" data-id="${it.id}"><i class="fas fa-arrow-rotate-left"></i> PULIH</button>
          <button class="chip chip-red" data-act="kill" data-col="${it.collection}" data-id="${it.id}"><i class="fas fa-xmark"></i> PADAM KEKAL</button>
        </div>
      </div>
    `;
  }

  async function recover(col, id) {
    const newStatus = col === 'tenants' ? 'Pending' : 'BARU';
    const { error } = await window.sb.from(col).update({ status: newStatus }).eq('id', id);
    if (error) { alert('Ralat: ' + error.message); return; }
    await load();
  }

  function openKill(col, id) {
    pending = { collection: col, id };
    confirmInput.value = '';
    modal.classList.remove('hidden');
  }
  function closeModal() { modal.classList.add('hidden'); pending = null; }

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
