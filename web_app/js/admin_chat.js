/* admin_chat.js — Dealer Support console (platform admin, Supabase).
   Sidebar: list all sv_ticket_meta rows (all branches) sorted by last_ts desc.
   Click branch → open thread, realtime subscribe to sv_tickets filtered by branch_id. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  if (ctx.role !== 'admin') { window.location.href = 'index.html'; return; }
  const sb = window.sb;

  const ADMIN_NAME = 'DEALER SUPPORT';
  const ADMIN_SENDER_ID = 'DEALER_SUPPORT';

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtTime = (iso) => {
    if (!iso) return ''; const d = new Date(iso); if (isNaN(d)) return '';
    const p = (n) => String(n).padStart(2, '0');
    const now = new Date();
    if (d.toDateString() === now.toDateString()) return `${p(d.getHours())}:${p(d.getMinutes())}`;
    return `${p(d.getDate())}/${p(d.getMonth()+1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  };

  // State
  let metaList = [];          // from sv_ticket_meta
  let activeBranch = null;
  let msgs = [];
  let msgsChan = null;
  let search = '';

  async function loadMeta() {
    const { data, error } = await sb.from('sv_ticket_meta')
      .select('*').order('last_ts', { ascending: false, nullsFirst: false });
    if (error) { console.error('meta load:', error); return; }
    metaList = data || [];
    renderList();
  }
  sb.channel('admin-meta')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'sv_ticket_meta' }, loadMeta)
    .subscribe();

  function renderList() {
    const q = search.trim().toUpperCase();
    const list = metaList.filter(u => !q ||
      (u.name || '').toUpperCase().includes(q) ||
      (u.shop_code || '').toUpperCase().includes(q) ||
      (u.branch_id || '').toUpperCase().includes(q)
    );
    $('acCount').textContent = String(list.length);
    const el = $('acList');
    if (!list.length) { el.innerHTML = `<div style="padding:20px;text-align:center;color:#94A3B8;font-size:11px">Tiada tiket</div>`; return; }
    el.innerHTML = list.map(u => {
      const unread = u.last_from === 'user';
      const name = u.name || u.branch_id;
      const initial = (name || '?').charAt(0).toUpperCase();
      return `<button class="ac__user${u.branch_id===activeBranch?' is-active':''}" data-bid="${esc(u.branch_id)}">
        <div class="ac__user-avatar">${esc(initial)}</div>
        <div class="ac__user-info">
          <div class="ac__user-name">${esc(name)}</div>
          <div class="ac__user-last">${esc(u.last_msg || u.shop_code || '—')}</div>
        </div>
        ${unread ? '<span class="ac__user-unread"></span>' : ''}
      </button>`;
    }).join('');
  }

  async function openRoom(branchId) {
    activeBranch = branchId;
    renderList();
    if (msgsChan) { await sb.removeChannel(msgsChan); msgsChan = null; }

    const meta = metaList.find(m => m.branch_id === branchId) || {};
    const room = $('acRoom');
    room.innerHTML = `
      <div class="ac__room-head">
        <div class="ac__user-avatar">${esc((meta.name || branchId).charAt(0).toUpperCase())}</div>
        <div>
          <div class="ac__room-name">${esc(meta.name || branchId)}</div>
          <div class="ac__room-sub">${esc(meta.shop_code || branchId)}</div>
        </div>
      </div>
      <div class="ac__body" id="acBody"><div class="ac__empty">Memuat...</div></div>
      <div class="ac__compose"><input type="text" id="acInput" placeholder="Balas sebagai Dealer Support..."><button id="acSend"><i class="fas fa-paper-plane"></i></button></div>
    `;
    $('acSend').addEventListener('click', send);
    $('acInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); send(); } });
    $('acInput').focus();

    // Load thread
    const { data, error } = await sb.from('sv_tickets')
      .select('*').eq('branch_id', branchId).order('created_at', { ascending: true });
    if (error) { console.error('thread load:', error); return; }
    msgs = data || [];
    renderMsgs();

    // Subscribe new inserts
    msgsChan = sb.channel(`admin-thread-${branchId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'sv_tickets', filter: `branch_id=eq.${branchId}` }, (payload) => {
        if (!msgs.some(m => m.id === payload.new.id)) { msgs.push(payload.new); renderMsgs(); }
      })
      .subscribe((status) => { if (status !== 'SUBSCRIBED') console.log('admin_chat realtime:', status); });
  }

  function renderMsgs() {
    const body = $('acBody'); if (!body) return;
    if (!msgs.length) { body.innerHTML = `<div class="ac__empty">Belum ada mesej</div>`; return; }
    body.innerHTML = msgs.map(m => {
      const isAdmin = m.role === 'admin';
      return `<div class="ac__msg${isAdmin?' is-admin':''}">
        ${!isAdmin ? `<div class="ac__msg-sender">${esc(m.sender_name || m.sender_id || '-')}</div>` : ''}
        <div class="ac__msg-bubble">${esc(m.text || '')}</div>
        <div class="ac__msg-time">${esc(fmtTime(m.created_at))}</div>
      </div>`;
    }).join('');
    body.scrollTop = body.scrollHeight;
  }

  let sending = false;
  async function send() {
    if (!activeBranch || sending) return;
    const inp = $('acInput');
    const btn = $('acSend');
    const text = inp.value.trim();
    if (!text) return;
    const original = inp.value;
    inp.value = '';
    sending = true; if (btn) btn.disabled = true;
    const meta = metaList.find(m => m.branch_id === activeBranch) || {};
    const tenantId = meta.tenant_id;
    if (!tenantId) { alert('Tenant ID missing for this ticket'); return; }
    try {
      const { data: inserted, error: e1 } = await sb.from('sv_tickets').insert({
        tenant_id: tenantId, branch_id: activeBranch,
        sender_id: ADMIN_SENDER_ID, sender_name: ADMIN_NAME, role: 'admin', text,
      }).select().single();
      if (e1) throw e1;
      // Optimistic: append locally (avoid waiting for realtime echo)
      if (inserted && !msgs.some(m => m.id === inserted.id)) {
        msgs.push(inserted);
        renderMsgs();
      }
      const { error: e2 } = await sb.from('sv_ticket_meta').upsert({
        branch_id: activeBranch, tenant_id: tenantId,
        last_msg: text, last_ts: new Date().toISOString(), last_from: 'admin', updated_at: new Date().toISOString(),
      }, { onConflict: 'branch_id' });
      if (e2) console.warn('meta upsert:', e2);
    } catch (e) {
      console.error('admin send:', e);
      alert('Gagal hantar: ' + (e.message || e.code || e));
      inp.value = original;
    } finally {
      sending = false; if (btn) btn.disabled = false;
    }
  }

  $('acList').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-bid]'); if (!b) return;
    openRoom(b.dataset.bid);
  });
  $('acSearch').addEventListener('input', (e) => { search = e.target.value; renderList(); });

  await loadMeta();
})();
