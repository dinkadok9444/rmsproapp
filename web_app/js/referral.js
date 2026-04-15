/* referral.js — Supabase. Mirror referral_screen.dart. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'rf-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }
  function parseCB(r) { try { return typeof r.created_by === 'string' ? JSON.parse(r.created_by) : (r.created_by || {}); } catch (e) { return {}; } }

  let ALL = [];
  let CLAIMS = [];
  let searchQ = '';
  let editing = null;
  let delId = null;

  async function fetchAll() {
    const { data } = await window.sb.from('referrals').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false }).limit(2000);
    return data || [];
  }
  async function fetchClaims() {
    const { data } = await window.sb.from('referral_claims').select('*').order('created_at', { ascending: false }).limit(5000);
    return data || [];
  }

  function refresh() {
    const q = searchQ.toLowerCase();
    const rows = ALL.filter((r) => {
      const cb = parseCB(r);
      if (!q) return true;
      return (cb.nama||'').toLowerCase().includes(q) || (cb.tel||'').toLowerCase().includes(q) || (r.code||'').toLowerCase().includes(q);
    });
    $('rfCount').textContent = ALL.length + ' rekod';
    $('rfList').innerHTML = rows.length ? rows.map((r) => {
      const cb = parseCB(r);
      const suspended = r.suspended === true;
      return `<div class="rf-card${suspended?' suspended':''}" data-id="${r.id}">
        <div class="rf-row1">
          <span class="rf-nama">${cb.nama || '—'}</span>
          <span class="rf-badge ${suspended?'susp':'active'}">${suspended?'GANTUNG':'ACTIVE'}</span>
        </div>
        <div class="rf-tel">${cb.tel || ''}</div>
        <div class="rf-row3">
          <span class="rf-code">${r.code || ''}</span>
          <button type="button" class="rf-wa-btn" data-wa="1" data-tel="${cb.tel || ''}" data-code="${r.code || ''}" data-nama="${(cb.nama || '').replace(/"/g,'&quot;')}" style="background:rgba(37,211,102,0.15);border:1px solid rgba(37,211,102,0.3);color:#25D366;border-radius:6px;padding:4px 8px;font-size:10px;font-weight:900;cursor:pointer;display:inline-flex;align-items:center;gap:4px;"><i class="fab fa-whatsapp"></i> HANTAR</button>
          <span class="rf-bank">
            <div class="rf-bank-name">${cb.bank || ''} ${cb.acc_no || ''}</div>
            <div class="rf-comm">${fmtRM(cb.commission)}</div>
          </span>
        </div>
        <div style="font-size:10px;color:#94a3b8;margin-top:6px;">Used: ${r.used_count || 0}x</div>
      </div>`;
    }).join('') : '<div class="rf-empty"><i class="fas fa-user-slash"></i><div class="rf-empty-t">Tiada referral</div><div class="rf-empty-s">Tekan "JANA KOD"</div></div>';
    $('rfList').querySelectorAll('.rf-card').forEach((el) => el.addEventListener('click', (ev) => {
      if (ev.target.closest('[data-wa="1"]')) return;
      openEdit(ALL.find((r) => r.id === el.dataset.id));
    }));
    $('rfList').querySelectorAll('[data-wa="1"]').forEach((btn) => btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      const tel = btn.dataset.tel || '';
      const code = btn.dataset.code || '';
      const nama = btn.dataset.nama || '';
      let phone = tel.replace(/\D/g, '');
      if (!phone) { snack('Tiada nombor telefon', true); return; }
      if (phone.startsWith('0')) phone = '6' + phone;
      const msg = encodeURIComponent(
        `Salam ${nama}! Kod referral anda: *${code}*\n\nKongsikan kod ini kepada rakan/keluarga anda. Setiap pembaikan menggunakan kod ini, anda layak menerima komisyen!\n\nTerima kasih.`
      );
      window.open(`https://wa.me/${phone}?text=${msg}`, '_blank');
    }));
  }

  function closeAll() { document.querySelectorAll('.rf-modal-bg').forEach((el) => el.classList.remove('is-open')); }
  document.querySelectorAll('[data-close]').forEach((el) => el.addEventListener('click', () => $(el.dataset.close).classList.remove('is-open')));

  $('btnJana').addEventListener('click', () => {
    $('custSearchInp').value = '';
    $('custResults').innerHTML = '';
    $('modalSearch').classList.add('is-open');
  });

  $('custSearchBtn').addEventListener('click', doSearchCust);
  $('custSearchInp').addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearchCust(); });

  async function doSearchCust() {
    const q = $('custSearchInp').value.trim();
    if (!q) return;
    const { data: jobs } = await window.sb.from('jobs').select('siri,nama,tel').eq('branch_id', branchId).or(`siri.ilike.%${q}%,tel.ilike.%${q}%,nama.ilike.%${q}%`).limit(20);
    const uniq = new Map();
    (jobs || []).forEach((j) => { const key = (j.tel||'').replace(/\D/g, ''); if (key && !uniq.has(key)) uniq.set(key, j); });
    const hits = Array.from(uniq.values());
    $('custResults').innerHTML = hits.length ? hits.map((h) => {
      const exists = ALL.some((r) => { const cb = parseCB(r); return (cb.tel||'').replace(/\D/g, '') === (h.tel||'').replace(/\D/g, ''); });
      return `<div class="rf-cust-hit">
        <div style="flex:1;"><strong>${h.nama||''}</strong><small>${h.tel||''}</small></div>
        ${exists ? '<span class="exists">ADA</span>' : `<button class="addbtn" data-nama="${h.nama||''}" data-tel="${h.tel||''}"><i class="fas fa-plus"></i> JANA</button>`}
      </div>`;
    }).join('') : '<div style="padding:12px;color:#94a3b8;">Tiada jumpa.</div>';
    $('custResults').querySelectorAll('.addbtn').forEach((b) => b.addEventListener('click', () => createReferral(b.dataset.nama, b.dataset.tel)));
  }

  async function createReferral(nama, tel) {
    const code = 'RF' + Date.now().toString(36).toUpperCase().slice(-6);
    const cb = { nama, tel, commission: 0, bank: '', acc_no: '' };
    const { error } = await window.sb.from('referrals').insert({
      tenant_id: tenantId,
      code,
      used_count: 0,
      created_by: JSON.stringify(cb),
    });
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Kod dijana: ' + code);
    closeAll();
    ALL = await fetchAll(); refresh();
  }

  function openEdit(row) {
    if (!row) return;
    editing = row;
    const cb = parseCB(row);
    $('editInfo').innerHTML = `
      <div class="rf-info-row"><span class="lbl">NAMA</span><span class="val">${cb.nama || '-'}</span></div>
      <div class="rf-info-row"><span class="lbl">TELEFON</span><span class="val">${cb.tel || '-'}</span></div>
      <div class="rf-info-row"><span class="lbl">KOD</span><span class="val">${row.code || '-'}</span></div>
      <div class="rf-info-row"><span class="lbl">USED</span><span class="val">${row.used_count || 0}x</span></div>`;
    $('editBank').value = cb.bank || '';
    $('editAcc').value = cb.acc_no || '';
    $('editComm').value = cb.commission || 0;
    const tgl = $('editToggle');
    tgl.classList.toggle('active', !row.suspended);
    tgl.innerHTML = row.suspended ? '<i class="fas fa-play"></i> AKTIF' : '<i class="fas fa-pause"></i> GANTUNG';
    const myClaims = CLAIMS.filter((c) => c.referral_id === row.id);
    $('claimHdrTxt').textContent = `SEJARAH TUNTUTAN (${myClaims.length})`;
    $('claimList').innerHTML = myClaims.map((c) => `<div class="rf-claim${c.status==='APPROVED'?' paid':''}">
      <div class="rf-claim-info">
        <div class="rf-claim-nm">${c.claimed_by || '-'}</div>
        <div class="rf-claim-pk">${c.siri || ''}</div>
      </div>
      <div class="rf-claim-right">
        <div class="rf-claim-amt" style="color:${c.status==='APPROVED'?'#10b981':'#eab308'};">${fmtRM(c.amount)}</div>
        <div class="rf-claim-pay" style="color:${c.status==='APPROVED'?'#10b981':'#eab308'};border-color:currentColor;">${c.status || 'PENDING'}</div>
      </div>
    </div>`).join('');
    $('modalEdit').classList.add('is-open');
  }

  $('editSave').addEventListener('click', async () => {
    if (!editing) return;
    const cb = parseCB(editing);
    cb.bank = $('editBank').value.trim();
    cb.acc_no = $('editAcc').value.trim();
    cb.commission = Number($('editComm').value) || 0;
    const { error } = await window.sb.from('referrals').update({ created_by: JSON.stringify(cb) }).eq('id', editing.id);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Disimpan'); closeAll();
    ALL = await fetchAll(); refresh();
  });

  $('editToggle').addEventListener('click', async () => {
    if (!editing) return;
    const { error } = await window.sb.from('referrals').update({ suspended: !editing.suspended }).eq('id', editing.id);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack(editing.suspended ? 'Diaktifkan' : 'Digantung');
    closeAll();
    ALL = await fetchAll(); refresh();
  });

  $('editDel').addEventListener('click', () => {
    if (!editing) return;
    delId = editing.id;
    $('pinMsg').textContent = 'Referral "' + editing.code + '" akan dipadam.';
    $('pinInp').value = '';
    $('modalPin').classList.add('is-open');
  });

  $('pinOk').addEventListener('click', async () => {
    if ($('pinInp').value !== '1234') { snack('PIN salah', true); return; }
    if (!delId) return;
    const { error } = await window.sb.from('referrals').delete().eq('id', delId);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    snack('Dipadam'); closeAll();
    ALL = await fetchAll(); refresh();
  });

  $('rfSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });

  window.sb.channel('referrals-' + tenantId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'referrals', filter: `tenant_id=eq.${tenantId}` }, async () => { ALL = await fetchAll(); refresh(); }).subscribe();
  window.sb.channel('ref-claims-' + tenantId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'referral_claims' }, async () => { CLAIMS = await fetchClaims(); }).subscribe();

  [ALL, CLAIMS] = await Promise.all([fetchAll(), fetchClaims()]);
  refresh();
})();
