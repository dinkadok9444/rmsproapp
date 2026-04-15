/* Admin → SaaS Feedback. Mirror saas_feedback_screen.dart.
   Table: app_feedback (id, sender_name, sender_role, message, status, created_at, resolved_at, resolve_note). */
(function () {
  'use strict';

  const listEl = document.getElementById('fbList');
  const tabs = document.querySelectorAll('.admin-tab');
  const cntOpen = document.getElementById('cntOpen');
  const cntResolved = document.getElementById('cntResolved');

  const modal = document.getElementById('resolveModal');
  const noteEl = document.getElementById('resolveNote');
  let currentFb = null;

  let currentStatus = 'open';
  let cache = { open: [], resolved: [] };

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });

  tabs.forEach(t => t.addEventListener('click', () => {
    tabs.forEach(x => x.classList.remove('is-active'));
    t.classList.add('is-active');
    currentStatus = t.dataset.status;
    render();
  }));

  document.getElementById('resolveCancel').addEventListener('click', () => closeModal());
  document.getElementById('resolveOk').addEventListener('click', async () => {
    if (!currentFb) return;
    const note = noteEl.value.trim();
    const { error } = await window.sb.from('app_feedback').update({
      status: 'resolved',
      resolved_at: new Date().toISOString(),
      resolve_note: note,
    }).eq('id', currentFb.id);
    closeModal();
    if (error) { alert('Gagal: ' + error.message); return; }
    await loadBoth();
  });
  modal.querySelector('.modal__backdrop').addEventListener('click', closeModal);

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await loadBoth();
  })();

  async function loadBoth() {
    const [o, r] = await Promise.all([
      window.sb.from('app_feedback').select('*').eq('status', 'open').order('created_at', { ascending: false }),
      window.sb.from('app_feedback').select('*').eq('status', 'resolved').order('resolved_at', { ascending: false }),
    ]);
    cache.open = o.data || [];
    cache.resolved = r.data || [];
    cntOpen.textContent = cache.open.length;
    cntResolved.textContent = cache.resolved.length;
    render();
  }

  function render() {
    const rows = cache[currentStatus] || [];
    if (!rows.length) {
      listEl.innerHTML = `<div class="admin-empty">${currentStatus === 'open' ? 'Tiada feedback terbuka' : 'Tiada sejarah selesai'}</div>`;
      return;
    }
    listEl.innerHTML = rows.map(fbCard).join('');
    listEl.querySelectorAll('[data-act="resolve"]').forEach(b => b.addEventListener('click', () => openResolve(b.dataset.id)));
    listEl.querySelectorAll('[data-act="reopen"]').forEach(b => b.addEventListener('click', () => reopen(b.dataset.id)));
  }

  function fbCard(fb) {
    const resolved = fb.status === 'resolved';
    const role = (fb.sender_role || '-').toUpperCase();
    const name = fb.sender_name || '-';
    const msg = escapeHtml(fb.message || '');
    const created = fmtTs(fb.created_at);
    const resolvedAt = fmtTs(fb.resolved_at);
    const note = (fb.resolve_note || '').trim();
    return `
      <div class="fb-card ${resolved ? 'is-resolved' : 'is-open'}">
        <div class="fb-card__head">
          <span class="fb-card__role">${escapeHtml(role)}</span>
          <span class="fb-card__name">${escapeHtml(name)}</span>
          <span class="fb-card__time">${created}</span>
        </div>
        <div class="fb-card__msg">${msg}</div>
        ${resolved ? `
          <div class="fb-card__resolve">
            <div class="fb-card__resolve-head"><i class="fas fa-circle-check"></i> SELESAI · ${resolvedAt}</div>
            ${note ? `<div class="fb-card__resolve-note">${escapeHtml(note)}</div>` : ''}
          </div>` : ''}
        <div class="fb-card__actions">
          ${resolved
            ? `<button class="btn btn-muted btn-sm" data-act="reopen" data-id="${fb.id}"><i class="fas fa-rotate-left"></i> BUKA SEMULA</button>`
            : `<button class="btn btn-green btn-sm" data-act="resolve" data-id="${fb.id}"><i class="fas fa-check"></i> TANDA SELESAI</button>`}
        </div>
      </div>
    `;
  }

  function openResolve(id) {
    currentFb = cache.open.find(x => String(x.id) === String(id));
    if (!currentFb) return;
    noteEl.value = '';
    modal.classList.remove('hidden');
  }
  function closeModal() { modal.classList.add('hidden'); currentFb = null; }

  async function reopen(id) {
    const { error } = await window.sb.from('app_feedback').update({
      status: 'open', resolved_at: null, resolve_note: null,
    }).eq('id', id);
    if (error) { alert('Gagal: ' + error.message); return; }
    await loadBoth();
  }

  function fmtTs(v) {
    if (!v) return '-';
    const d = new Date(v);
    if (isNaN(d.getTime())) return '-';
    const pad = n => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }
})();
