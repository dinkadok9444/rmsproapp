/* fungsi_lain.js — Notifikasi admin, feedback, rekod pos. Mirror fungsi_lain_screen.dart. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtDate = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()}`;
  };

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'fl-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  // ── ANNOUNCEMENTS ─────────────────────────────────────────
  async function loadAnnouncements() {
    const box = $('annBox'); if (!box) return;
    const nowIso = new Date().toISOString();
    const results = await Promise.all([
      window.sb.from('admin_announcements').select('*').order('posted_at', { ascending: false }).limit(5),
      window.sb.from('system_settings').select('*').eq('id', 'pengumuman').maybeSingle(),
    ]);
    const anns = results[0].data || [];
    const sys = results[1].data;
    let html = '';
    if (sys && sys.enabled && sys.message) {
      const inWindow = (!sys.start_date || sys.start_date <= nowIso) && (!sys.end_date || sys.end_date >= nowIso);
      if (inWindow) {
        const sev = (sys.severity || 'info').toLowerCase();
        const color = sev === 'warn' ? '#f59e0b' : sev === 'error' ? '#dc2626' : '#2563eb';
        html += `<div class="fl-ann" style="border-left-color:${color};color:${color};">
          <strong>${sys.title || 'PENGUMUMAN'}</strong><br>${sys.message}</div>`;
      }
    }
    if (anns.length) {
      html += anns.map((a) => `<div class="fl-ann">
        <strong>${a.title || '—'}</strong><br>${a.body || ''}
        <div style="font-size:9px;color:#94a3b8;margin-top:4px;">${fmtDate(a.posted_at)}</div>
      </div>`).join('');
    }
    if (!html) {
      box.className = 'fl-ann-empty';
      box.textContent = 'Tiada pengumuman';
    } else {
      box.className = '';
      box.innerHTML = html;
    }
  }

  // ── FEEDBACK ──────────────────────────────────────────────
  async function loadFeedback() {
    const { data } = await window.sb.from('feedback')
      .select('*').eq('branch_id', branchId)
      .order('created_at', { ascending: false }).limit(20);
    const rows = data || [];
    if (rows.length) {
      $('fbHistWrap').hidden = false;
      $('fbHist').innerHTML = rows.map((r) => {
        const resolved = !!r.resolved;
        return `<div class="fl-fb-item${resolved ? ' resolved' : ''}">
          <div class="fl-fb-hdr">
            <span class="fl-badge${resolved ? ' resolved' : ''}">${resolved ? 'SELESAI' : 'BARU'}</span>
            <span class="fl-fb-time">${fmtDate(r.created_at)}</span>
          </div>
          <div class="fl-fb-msg">${(r.message || '').replace(/</g, '&lt;')}</div>
          ${r.resolved_note ? `<div class="fl-resolve-note"><i class="fas fa-reply"></i> ${r.resolved_note}</div>` : ''}
          ${resolved && r.resolved_at ? `<div class="fl-resolved-at">${fmtDate(r.resolved_at)}</div>` : ''}
        </div>`;
      }).join('');
    } else {
      $('fbHistWrap').hidden = true;
    }
  }

  $('fbSend').addEventListener('click', async () => {
    const msg = $('fbInput').value.trim();
    if (!msg) { snack('Isi feedback dulu', true); return; }
    $('fbSend').disabled = true;
    $('fbSendLbl').textContent = 'MENGHANTAR...';
    const { error } = await window.sb.from('feedback').insert({
      tenant_id: tenantId,
      branch_id: branchId,
      message: msg,
      resolved: false,
      sender_id: ctx.id,
      sender_name: ctx.nama || ctx.email,
    });
    $('fbSend').disabled = false;
    $('fbSendLbl').textContent = 'HANTAR FEEDBACK';
    if (error) { snack('Gagal: ' + error.message, true); return; }
    $('fbInput').value = '';
    snack('Feedback dihantar');
    loadFeedback();
  });

  // ── POS TRACKING ──────────────────────────────────────────
  let EDIT_ID = null;

  async function loadPos() {
    const { data } = await window.sb.from('pos_tracking')
      .select('*').eq('branch_id', branchId)
      .order('tarikh', { ascending: false }).limit(100);
    const rows = data || [];
    if (!rows.length) {
      $('posList').innerHTML = '<div class="fl-empty">Tiada rekod pos.</div>';
      return;
    }
    $('posList').innerHTML = rows.map((r) => {
      const st = (r.status || 'DIPOS').toUpperCase();
      const col = st === 'SELESAI' ? '#10b981' : st === 'DALAM PERJALANAN' ? '#2563eb' : '#f59e0b';
      return `<div class="fl-pos-row">
        <div style="flex:1;">
          <div class="fl-pos-tarikh">${fmtDate(r.tarikh)}</div>
          <div class="fl-pos-track">${r.tracking_no || '—'}</div>
          <div class="fl-pos-kurier">${r.kurier || ''}</div>
          <div class="fl-pos-item">${r.item || ''}</div>
          <span class="fl-pos-status" style="color:${col};border-color:${col};">${st}</span>
        </div>
        <div style="display:flex;flex-direction:column;gap:4px;">
          <button class="fl-icon-btn" style="border-color:#2563eb;color:#2563eb;" data-edit="${r.id}"><i class="fas fa-pen"></i></button>
          <button class="fl-icon-btn" style="border-color:#dc2626;color:#dc2626;" data-del="${r.id}"><i class="fas fa-trash"></i></button>
        </div>
      </div>`;
    }).join('');

    $('posList').querySelectorAll('[data-edit]').forEach((b) => {
      b.addEventListener('click', () => {
        const r = rows.find((x) => x.id === b.dataset.edit); if (!r) return;
        EDIT_ID = r.id;
        $('posModalTitle').innerHTML = '<i class="fas fa-truck-fast"></i> EDIT REKOD';
        $('posTarikh').value = (r.tarikh || '').slice(0, 10);
        $('posItem').value = r.item || '';
        $('posKurier').value = r.kurier || '';
        $('posTrack').value = r.tracking_no || '';
        $('posStatus').value = r.status || 'DIPOS';
        $('posModal').classList.add('is-open');
      });
    });
    $('posList').querySelectorAll('[data-del]').forEach((b) => {
      b.addEventListener('click', async () => {
        if (!confirm('Padam rekod ini?')) return;
        const { error } = await window.sb.from('pos_tracking').delete().eq('id', b.dataset.del);
        if (error) { snack('Gagal: ' + error.message, true); return; }
        snack('Dipadam'); loadPos();
      });
    });
  }

  $('btnAddPos').addEventListener('click', () => {
    EDIT_ID = null;
    $('posModalTitle').innerHTML = '<i class="fas fa-truck-fast"></i> TAMBAH REKOD';
    const today = new Date().toISOString().slice(0, 10);
    $('posTarikh').value = today;
    $('posItem').value = '';
    $('posKurier').value = '';
    $('posTrack').value = '';
    $('posStatus').value = 'DIPOS';
    $('posModal').classList.add('is-open');
  });

  $('posCancel').addEventListener('click', () => $('posModal').classList.remove('is-open'));

  $('posSave').addEventListener('click', async () => {
    const payload = {
      tarikh: $('posTarikh').value || null,
      item: $('posItem').value.trim(),
      kurier: $('posKurier').value.trim(),
      tracking_no: $('posTrack').value.trim().toUpperCase(),
      status: $('posStatus').value,
    };
    if (!payload.item || !payload.tracking_no) { snack('Item & tracking wajib', true); return; }
    let error;
    if (EDIT_ID) {
      ({ error } = await window.sb.from('pos_tracking').update(payload).eq('id', EDIT_ID));
    } else {
      ({ error } = await window.sb.from('pos_tracking').insert({
        ...payload, tenant_id: tenantId, branch_id: branchId,
      }));
    }
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Disimpan');
    $('posModal').classList.remove('is-open');
    loadPos();
  });

  // ── Realtime ──────────────────────────────────────────────
  window.sb.channel('fl-feedback-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'feedback', filter: `branch_id=eq.${branchId}` }, loadFeedback)
    .subscribe();
  window.sb.channel('fl-pos-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pos_tracking', filter: `branch_id=eq.${branchId}` }, loadPos)
    .subscribe();

  await Promise.all([loadAnnouncements(), loadFeedback(), loadPos()]);
})();
