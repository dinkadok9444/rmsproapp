/* sv_chat.js — Supervisor Dealer Support chat (Supabase).
   Table: sv_tickets (branch_id PK thread), sv_ticket_meta (sidebar + unread).
   User inserts with role='user'. Dealer Support replies with role='admin'. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const sb = window.sb;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtTime = (iso) => {
    if (!iso) return ''; const d = new Date(iso); if (isNaN(d)) return '';
    const p = (n) => String(n).padStart(2, '0');
    const now = new Date();
    if (d.toDateString() === now.toDateString()) return `${p(d.getHours())}:${p(d.getMinutes())}`;
    return `${p(d.getDate())}/${p(d.getMonth()+1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  };

  // Identity
  let me = (ctx.nama || 'USER').toUpperCase();
  let shopCode = '';
  try {
    const { data } = await sb.from('branches').select('nama_kedai, shop_code').eq('id', branchId).maybeSingle();
    if (data) {
      me = String(data.nama_kedai || me).toUpperCase();
      shopCode = String(data.shop_code || '').toUpperCase();
    }
  } catch {}

  let msgs = [];

  async function reload() {
    const { data, error } = await sb.from('sv_tickets')
      .select('*').eq('branch_id', branchId).order('created_at', { ascending: true });
    if (error) { console.error('chat load:', error); return; }
    msgs = data || [];
    render();
  }
  sb.channel(`sv-chat-${branchId}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'sv_tickets', filter: `branch_id=eq.${branchId}` }, (payload) => {
      if (!msgs.some(m => m.id === payload.new.id)) { msgs.push(payload.new); render(); }
    })
    .subscribe((status) => { if (status !== 'SUBSCRIBED') console.log('sv_chat realtime:', status); });

  // Fallback polling every 12s in case realtime stalls
  setInterval(async () => {
    try {
      const lastTs = msgs.length ? msgs[msgs.length - 1].created_at : '1970-01-01';
      const { data } = await sb.from('sv_tickets').select('*')
        .eq('branch_id', branchId).gt('created_at', lastTs).order('created_at', { ascending: true });
      if (data && data.length) {
        for (const r of data) if (!msgs.some(m => m.id === r.id)) msgs.push(r);
        render();
      }
    } catch {}
  }, 12000);

  // ── Red dot on CHAT tile when admin replied (last_from='admin')
  const chatTile = document.querySelector('#supTabs .sup-tile[data-tab="CHAT"]');
  function setDot(show) {
    if (!chatTile) return;
    let dot = chatTile.querySelector('.sup-tile__dot');
    if (show) {
      if (!dot) { dot = document.createElement('span'); dot.className = 'sup-tile__dot'; chatTile.appendChild(dot); }
    } else if (dot) dot.remove();
  }
  async function checkMeta() {
    const { data } = await sb.from('sv_ticket_meta').select('last_from').eq('branch_id', branchId).maybeSingle();
    setDot(data && data.last_from === 'admin');
  }
  sb.channel(`sv-chat-meta-${branchId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'sv_ticket_meta', filter: `branch_id=eq.${branchId}` }, checkMeta)
    .subscribe();
  checkMeta();
  // Clear dot when user clicks the CHAT tab
  if (chatTile) chatTile.addEventListener('click', async () => {
    setDot(false);
    try {
      await sb.from('sv_ticket_meta').update({ last_from: 'user_seen' }).eq('branch_id', branchId).eq('last_from', 'admin');
    } catch {}
  });

  function render() {
    const body = $('svChBody');
    if (!msgs.length) {
      body.innerHTML = `<div class="sv-ch__empty">Belum ada mesej. Hantar mesej pertama untuk hubungi support.</div>`;
      return;
    }
    body.innerHTML = msgs.map(m => {
      const mine = m.role !== 'admin';
      return `<div class="sv-ch__msg${mine?' is-mine':''}">
        ${!mine ? `<div class="sv-ch__msg-sender"><i class="fas fa-user-shield"></i> ${esc(m.sender_name || 'DEALER SUPPORT')}</div>` : ''}
        <div class="sv-ch__msg-bubble">${esc(m.text || '')}</div>
        <div class="sv-ch__msg-time">${esc(fmtTime(m.created_at))}</div>
      </div>`;
    }).join('');
    body.scrollTop = body.scrollHeight;
  }

  let sending = false;
  async function send() {
    if (sending) return;
    const inp = $('svChInput');
    const btn = $('svChSend');
    const text = inp.value.trim();
    if (!text) return;
    const original = inp.value;
    inp.value = '';
    sending = true; if (btn) btn.disabled = true;
    try {
      const { data: inserted, error: e1 } = await sb.from('sv_tickets').insert({
        tenant_id: tenantId, branch_id: branchId,
        sender_id: branchId, sender_name: me, role: 'user', text,
      }).select().single();
      if (e1) throw e1;
      // Optimistic append
      if (inserted && !msgs.some(m => m.id === inserted.id)) {
        msgs.push(inserted); render();
      }
      const { error: e2 } = await sb.from('sv_ticket_meta').upsert({
        branch_id: branchId, tenant_id: tenantId, name: me, shop_code: shopCode,
        last_msg: text, last_ts: new Date().toISOString(), last_from: 'user', updated_at: new Date().toISOString(),
      }, { onConflict: 'branch_id' });
      if (e2) console.warn('meta upsert:', e2);
    } catch (e) {
      console.error('chat send:', e);
      alert('Gagal hantar mesej: ' + (e.message || e.code || e));
      inp.value = original;
    }
  }

  $('svChSend').addEventListener('click', send);
  $('svChInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); send(); } });

  await reload();
})();
