/* Fungsi Lain — port lib/screens/modules/fungsi_lain_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch') || '';
  let ownerID = 'admin', shopID = 'MAIN';
  if (branch.includes('@')) { ownerID = branch.split('@')[0]; shopID = branch.split('@')[1].toUpperCase(); }
  const staffRole = localStorage.getItem('rms_staff_role') || '';
  const userRole = localStorage.getItem('rms_user_role') || '';
  const senderRole = staffRole || userRole || 'branch';
  const senderName = localStorage.getItem('rms_staff_name') || ownerID;

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const fmtTs = ms => { if (!ms) return '-'; const d = new Date(+ms); const p = n => String(n).padStart(2,'0'); return `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`; };
  function snack(msg, err=false){ const el=document.createElement('div'); el.className='fl-snack'+(err?' err':''); el.textContent=msg; document.body.appendChild(el); setTimeout(()=>el.remove(),2500); }

  // ── Announcement ──
  db.collection('admin_announcements').doc('global').onSnapshot(snap => {
    const m = snap.exists ? String((snap.data() || {}).message || '').trim() : '';
    const box = $('annBox');
    if (!m) { box.className = 'fl-ann-empty'; box.textContent = 'Tiada pengumuman'; }
    else { box.className = 'fl-ann'; box.textContent = 'Berita: ' + m; }
  });

  // ── Feedback ──
  let myFeedbacks = [];
  db.collection('app_feedback').where('ownerID','==',ownerID).where('shopID','==',shopID).onSnapshot(snap => {
    myFeedbacks = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    myFeedbacks.sort((a,b) => (b.createdAt||0) - (a.createdAt||0));
    renderFeedback();
  });

  function renderFeedback(){
    const wrap = $('fbHistWrap'); const host = $('fbHist');
    if (!myFeedbacks.length) { wrap.hidden = true; return; }
    wrap.hidden = false;
    host.innerHTML = myFeedbacks.map(fb => {
      const resolved = fb.status === 'resolved';
      const note = (fb.resolveNote || '').toString().trim();
      return `<div class="fl-fb-item${resolved?' resolved':''}">
        <div class="fl-fb-hdr">
          <span class="fl-badge${resolved?' resolved':''}">${resolved?'SELESAI':'TERBUKA'}</span>
          <span class="fl-fb-time">${fmtTs(fb.createdAt)}</span>
        </div>
        <div class="fl-fb-msg">${esc(fb.message || '')}</div>
        ${resolved && note ? `<div class="fl-resolve-note"><i class="fas fa-reply"></i><span>${esc(note)}</span></div>` : ''}
        ${resolved ? `<div class="fl-resolved-at">Diselesaikan: ${fmtTs(fb.resolvedAt)}</div>` : ''}
      </div>`;
    }).join('');
  }

  let sending = false;
  $('fbSend').addEventListener('click', async () => {
    const msg = $('fbInput').value.trim();
    if (!msg || sending) return;
    sending = true; $('fbSend').disabled = true; $('fbSendLbl').textContent = 'MENGHANTAR...';
    try {
      await db.collection('app_feedback').add({
        ownerID, shopID, senderRole, senderName, message: msg,
        createdAt: Date.now(), status: 'open',
      });
      $('fbInput').value = '';
      snack('Feedback dihantar');
    } catch(e){ snack('Ralat: '+e.message, true); }
    finally { sending = false; $('fbSend').disabled = false; $('fbSendLbl').textContent = 'HANTAR FEEDBACK'; }
  });

  // ── POS / Tracking ──
  let posRecords = [];
  db.collection('trackings_'+ownerID).onSnapshot(snap => {
    posRecords = [];
    snap.forEach(doc => {
      const d = doc.data(); d.id = doc.id;
      if ((d.shopID || '').toString().toUpperCase() === shopID) posRecords.push(d);
    });
    posRecords.sort((a,b) => (b.timestamp||0) - (a.timestamp||0));
    posRecords = posRecords.slice(0, 15);
    renderPos();
  });

  function statusColor(s){ if (s === 'SELESAI') return '#10b981'; if (s === 'DALAM PERJALANAN') return '#2563eb'; return '#eab308'; }

  function renderPos(){
    const host = $('posList');
    if (!posRecords.length) { host.innerHTML = `<div class="fl-empty">Tiada rekod pos</div>`; return; }
    host.innerHTML = posRecords.map(t => {
      const col = statusColor(t.status_track || 'DIPOS');
      return `<div class="fl-pos-row">
        <div style="flex:1;">
          <div class="fl-pos-tarikh">${esc(t.tarikh || '-')}</div>
          <div class="fl-pos-track">${esc(t.trackNo || '-')}</div>
          <div class="fl-pos-kurier">(${esc(t.kurier || '-')})</div>
          <div class="fl-pos-item">${esc(t.item || '')}</div>
          <span class="fl-pos-status" style="color:${col};border-color:${col};">${esc(t.status_track || 'DIPOS')}</span>
        </div>
        <div style="display:flex;flex-direction:column;gap:6px;">
          <button class="fl-icon-btn" data-edit="${esc(t.id)}" style="border-color:#eab308;color:#eab308;background:rgba(234,179,8,.1);"><i class="fas fa-pen-to-square"></i></button>
          <button class="fl-icon-btn" data-del="${esc(t.id)}" style="border-color:#dc2626;color:#dc2626;background:rgba(220,38,38,.1);"><i class="fas fa-trash-can"></i></button>
        </div>
      </div>`;
    }).join('');
    host.querySelectorAll('[data-edit]').forEach(b => b.addEventListener('click', () => {
      const rec = posRecords.find(x => x.id === b.getAttribute('data-edit'));
      if (rec) openPosModal(rec);
    }));
    host.querySelectorAll('[data-del]').forEach(b => b.addEventListener('click', async () => {
      if (!confirm('Padam rekod pos ini?')) return;
      await db.collection('trackings_'+ownerID).doc(b.getAttribute('data-del')).delete();
    }));
  }

  // ── POS Modal ──
  let editingId = null;
  function openPosModal(existing){
    editingId = existing ? existing.id : null;
    $('posModalTitle').innerHTML = `<i class="fas fa-truck-fast"></i> ${existing ? 'KEMASKINI REKOD' : 'TAMBAH REKOD'}`;
    const today = new Date().toISOString().slice(0,10);
    $('posTarikh').value = existing?.tarikh || today;
    $('posItem').value = existing?.item || '';
    $('posKurier').value = existing?.kurier || '';
    $('posTrack').value = existing?.trackNo || '';
    $('posStatus').value = existing?.status_track || 'DIPOS';
    $('posModal').classList.add('is-open');
  }
  $('btnAddPos').addEventListener('click', () => openPosModal(null));
  $('posCancel').addEventListener('click', () => $('posModal').classList.remove('is-open'));
  $('posSave').addEventListener('click', async () => {
    const item = $('posItem').value.trim();
    if (!item) return;
    const data = {
      shopID,
      tarikh: $('posTarikh').value.trim(),
      item: item.toUpperCase(),
      kurier: $('posKurier').value.trim().toUpperCase(),
      trackNo: $('posTrack').value.trim().toUpperCase(),
      status_track: $('posStatus').value,
    };
    if (editingId) {
      await db.collection('trackings_'+ownerID).doc(editingId).update({ ...data, updated: Date.now() });
    } else {
      await db.collection('trackings_'+ownerID).add({ ...data, timestamp: Date.now() });
    }
    $('posModal').classList.remove('is-open');
  });
})();
