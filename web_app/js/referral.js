/* Referral — port lib/screens/modules/referral_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch') || '';
  if (!branch.includes('@')) { window.location.replace('index.html'); return; }
  const ownerID = branch.split('@')[0].toLowerCase();
  const shopID = branch.split('@')[1].toUpperCase();

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const fmtTs = ms => { if (!ms) return '-'; const d = new Date(+ms); const p = n => String(n).padStart(2,'0'); return `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`; };
  function snack(msg, err=false){ const el=document.createElement('div'); el.className='rf-snack'+(err?' err':''); el.textContent=msg; document.body.appendChild(el); setTimeout(()=>el.remove(),2500); }
  function closeAll(){ document.querySelectorAll('.rf-modal-bg').forEach(m => m.classList.remove('is-open')); }
  document.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', () => $(b.getAttribute('data-close')).classList.remove('is-open')));

  let svPass = '';
  let referrals = [], filtered = [], rawDataArr = [], currentRef = null, currentClaims = [];

  db.collection('shops_'+ownerID).doc(shopID).get().then(s => {
    if (s.exists) { const d = s.data() || {}; svPass = (d.svPass || d.branchAdminPass || '').toString(); }
  });

  db.collection('referrals_'+ownerID).orderBy('timestamp','desc').onSnapshot(snap => {
    referrals = [];
    snap.forEach(doc => {
      const d = doc.data(); d.id = doc.id;
      if ((d.shopID || '').toString().toUpperCase() === shopID) referrals.push(d);
    });
    filterAndRender();
  });
  db.collection('repairs_'+ownerID).onSnapshot(snap => {
    rawDataArr = [];
    snap.forEach(doc => {
      const d = doc.data(); d.id = doc.id;
      if ((d.shopID || '').toString().toUpperCase() === shopID) rawDataArr.push(d);
    });
  });

  $('rfSearch').addEventListener('input', filterAndRender);

  function filterAndRender(){
    const q = ($('rfSearch').value || '').toLowerCase().trim();
    filtered = !q ? referrals.slice() : referrals.filter(d =>
      (d.nama||'').toString().toLowerCase().includes(q) ||
      (d.tel||'').toString().toLowerCase().includes(q) ||
      (d.refCode||'').toString().toLowerCase().includes(q));
    $('rfCount').textContent = filtered.length + ' rekod';
    renderList();
  }

  function renderList(){
    const host = $('rfList');
    if (!referrals.length) {
      host.innerHTML = `<div class="rf-empty"><i class="fas fa-user-group"></i><div class="rf-empty-t">Tiada rekod referral</div><div class="rf-empty-s">Tekan "JANA KOD" untuk menambah<br>referral baru dari rekod pembaikan</div></div>`;
      return;
    }
    if (!filtered.length) { host.innerHTML = `<div class="rf-empty"><div class="rf-empty-t">Tiada padanan</div></div>`; return; }
    host.innerHTML = filtered.map((r, i) => {
      const isActive = (r.status||'').toString().toUpperCase() === 'ACTIVE';
      const comm = Number(r.commission || 0);
      const bank = (r.bank || '').toString();
      return `<div class="rf-card${isActive?'':' suspended'}" data-idx="${i}">
        <div class="rf-row1">
          <div class="rf-nama">${esc(r.nama || '-')}</div>
          <span class="rf-badge ${isActive?'active':'susp'}">${isActive?'ACTIVE':'SUSPENDED'}</span>
        </div>
        <div class="rf-tel">${esc(r.tel || '-')}</div>
        <div class="rf-row3">
          <span class="rf-code">${esc(r.refCode || '-')}</span>
          <a class="rf-wa" data-wa="${i}"><i class="fab fa-whatsapp"></i> HANTAR</a>
          ${(bank || comm>0) ? `<div class="rf-bank">${bank ? `<div class="rf-bank-name">${esc(bank)}</div>` : ''}${comm>0 ? `<div class="rf-comm">RM${comm.toFixed(2)}</div>` : ''}</div>` : ''}
        </div>
      </div>`;
    }).join('');
    host.querySelectorAll('.rf-card').forEach(c => c.addEventListener('click', e => {
      if (e.target.closest('[data-wa]')) return;
      openEdit(filtered[+c.getAttribute('data-idx')]);
    }));
    host.querySelectorAll('[data-wa]').forEach(b => b.addEventListener('click', e => {
      e.stopPropagation();
      const r = filtered[+b.getAttribute('data-wa')];
      sendWa(r.tel || '', r.refCode || '', r.nama || '');
    }));
  }

  function sendWa(tel, code, nama){
    const phone = (tel || '').replace(/[^0-9]/g, '');
    const formatted = phone.startsWith('0') ? '6'+phone : phone;
    const msg = encodeURIComponent(`Salam ${nama}! Kod referral anda: *${code}*\n\nKongsikan kod ini kepada rakan/keluarga anda. Setiap pembaikan menggunakan kod ini, anda layak menerima komisyen!\n\nTerima kasih.`);
    window.open(`https://wa.me/${formatted}?text=${msg}`, '_blank');
  }

  // ── Jana Kod (search customer) ──
  function genCode(){ return 'REF-' + (Math.floor(Math.random()*900000)+100000); }

  $('btnJana').addEventListener('click', () => {
    $('custSearchInp').value = ''; $('custResults').innerHTML = '';
    $('modalSearch').classList.add('is-open');
  });

  function doCustSearch(){
    const q = ($('custSearchInp').value || '').toLowerCase().trim();
    if (!q) return;
    const results = rawDataArr.filter(d =>
      (d.siri||'').toString().toLowerCase().includes(q) ||
      (d.tel||'').toString().toLowerCase().includes(q));
    renderCustResults(results);
  }
  $('custSearchBtn').addEventListener('click', doCustSearch);
  $('custSearchInp').addEventListener('keydown', e => { if (e.key === 'Enter') doCustSearch(); });

  function renderCustResults(results){
    const host = $('custResults');
    if (!results.length) { host.innerHTML = `<div class="rf-empty"><div class="rf-empty-s">Tiada hasil</div></div>`; return; }
    host.innerHTML = results.map((c, i) => {
      const already = referrals.some(r => (r.tel||'') === (c.tel||'') && (r.tel||'') !== '');
      return `<div class="rf-cust-hit">
        <div style="flex:1;"><strong>${esc(c.nama || '-')}</strong><small>${esc(c.tel || '-')} | #${esc(c.siri || '-')}</small></div>
        ${already ? `<span class="exists">SUDAH ADA</span>` : `<button class="addbtn" data-add="${i}"><i class="fas fa-plus"></i> JANA KOD</button>`}
      </div>`;
    }).join('');
    host.querySelectorAll('[data-add]').forEach(b => b.addEventListener('click', async () => {
      const c = results[+b.getAttribute('data-add')];
      let code = genCode();
      try { const ex = await db.collection('referrals_'+ownerID).doc(code).get(); if (ex.exists) code = genCode(); } catch(_){}
      await db.collection('referrals_'+ownerID).doc(code).set({
        refCode: code,
        nama: (c.nama || '').toString().toUpperCase(),
        tel: c.tel || '',
        siriAsal: c.siri || '',
        shopID, ownerID,
        status: 'ACTIVE',
        bank: '', accNo: '', commission: 0,
        timestamp: Date.now(),
      });
      closeAll();
      snack('Referral '+code+' dijana');
    }));
  }

  // ── Edit referral ──
  function openEdit(ref){
    currentRef = ref;
    const st = (ref.status||'ACTIVE').toString().toUpperCase();
    $('editInfo').innerHTML = `
      <div class="rf-info-row"><div class="lbl">Kod</div><div class="val">${esc(ref.refCode||'-')}</div></div>
      <div class="rf-info-row"><div class="lbl">Nama</div><div class="val">${esc(ref.nama||'-')}</div></div>
      <div class="rf-info-row"><div class="lbl">Tel</div><div class="val">${esc(ref.tel||'-')}</div></div>
      <div class="rf-info-row"><div class="lbl">Status</div><div class="val">${esc(st)}</div></div>`;
    $('editBank').value = ref.bank || '';
    $('editAcc').value = ref.accNo || '';
    $('editComm').value = ref.commission != null ? ref.commission : '';
    const tog = $('editToggle');
    if (st === 'ACTIVE') { tog.className = 'rf-toggle'; tog.innerHTML = '<i class="fas fa-pause"></i> GANTUNG'; }
    else { tog.className = 'rf-toggle active'; tog.innerHTML = '<i class="fas fa-play"></i> AKTIF'; }
    $('claimList').innerHTML = '<div class="rf-empty"><div class="rf-empty-s">Memuatkan...</div></div>';
    $('claimHdrTxt').textContent = 'SEJARAH TUNTUTAN (0)';
    loadClaims(ref);
    $('modalEdit').classList.add('is-open');
  }

  async function loadClaims(ref){
    try {
      const snap = await db.collection('referral_claims_'+ownerID)
        .where('refCode','==', ref.refCode).orderBy('timestamp','desc').get();
      currentClaims = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    } catch(_){ currentClaims = []; }
    renderClaims();
  }

  function renderClaims(){
    $('claimHdrTxt').textContent = `SEJARAH TUNTUTAN (${currentClaims.length})`;
    if (!currentClaims.length) { $('claimList').innerHTML = `<div class="rf-empty"><div class="rf-empty-s">Tiada sejarah tuntutan</div></div>`; return; }
    $('claimList').innerHTML = currentClaims.map((cl, i) => {
      const isPaid = (cl.paymentStatus||'').toString().toUpperCase() === 'PAID';
      const col = isPaid ? '#10b981' : '#eab308';
      return `<div class="rf-claim ${isPaid?'paid':''}">
        <div class="rf-claim-info">
          <div class="rf-claim-nm">${esc(cl.redeemerName||'-')}</div>
          <div class="rf-claim-pk">${esc(cl.perkara||'-')}</div>
          <div class="rf-claim-ts">${fmtTs(cl.timestamp)}</div>
        </div>
        <div class="rf-claim-right">
          <div class="rf-claim-amt" style="color:${col};">RM${Number(cl.amount||0).toFixed(2)}</div>
          <button class="rf-claim-pay" data-pay="${i}" style="color:${col};border-color:${col};background:${col}22;">${isPaid?'PAID':'UNPAID'}</button>
        </div>
      </div>`;
    }).join('');
    $('claimList').querySelectorAll('[data-pay]').forEach(b => b.addEventListener('click', async () => {
      const cl = currentClaims[+b.getAttribute('data-pay')];
      const isPaid = (cl.paymentStatus||'').toString().toUpperCase() === 'PAID';
      const newPay = isPaid ? 'UNPAID' : 'PAID';
      await db.collection('referral_claims_'+ownerID).doc(cl.id).update({
        paymentStatus: newPay,
        paidAt: newPay === 'PAID' ? Date.now() : null,
      });
      await loadClaims(currentRef);
    }));
  }

  $('editSave').addEventListener('click', async () => {
    await db.collection('referrals_'+ownerID).doc(currentRef.id).update({
      bank: ($('editBank').value || '').trim().toUpperCase(),
      accNo: ($('editAcc').value || '').trim(),
      commission: parseFloat($('editComm').value) || 0,
      lastUpdated: Date.now(),
    });
    closeAll();
    snack('Referral dikemaskini');
  });

  $('editToggle').addEventListener('click', async () => {
    const st = (currentRef.status||'ACTIVE').toString().toUpperCase();
    const newSt = st === 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE';
    await db.collection('referrals_'+ownerID).doc(currentRef.id).update({
      status: newSt, lastUpdated: Date.now(),
    });
    currentRef.status = newSt;
    const tog = $('editToggle');
    if (newSt === 'ACTIVE') { tog.className = 'rf-toggle active'; tog.innerHTML = '<i class="fas fa-pause"></i> GANTUNG'; }
    else { tog.className = 'rf-toggle'; tog.innerHTML = '<i class="fas fa-play"></i> AKTIF'; }
    snack(newSt === 'ACTIVE' ? 'Referral diaktifkan' : 'Referral digantung');
  });

  $('editDel').addEventListener('click', () => {
    $('pinMsg').textContent = `Adakah anda pasti mahu memadam referral ${currentRef.refCode}?`;
    $('pinInp').value = '';
    $('modalPin').classList.add('is-open');
  });

  $('pinOk').addEventListener('click', async () => {
    const pin = ($('pinInp').value || '').trim();
    if (!pin) { snack('Sila masukkan PIN', true); return; }
    if (pin !== svPass) { snack('PIN tidak sah!', true); return; }
    await db.collection('referrals_'+ownerID).doc(currentRef.id).delete();
    closeAll();
    snack('Referral dipadam');
  });
})();
