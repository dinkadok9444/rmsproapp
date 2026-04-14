/* DB Customer — 1:1 port of lib/screens/modules/db_cust_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID  = (shopRaw  || '').toUpperCase();

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const num = v => Number(v) || 0;

  const state = {
    segment: 0,                 // 0=REPAIR 1=JUALAN
    sort: 'TERBARU',
    time: 'SEMUA',
    aff:  'SEMUA',
    exactDate: null,            // Date or null
    search: '',
    allRepairs: [],
    allSales: [],
    filtered: [],
    phoneFrequency: {},
    referrals: {},              // telClean -> ref doc
    referralClaims: {},         // refCode -> [claims]
    page: 1,
    rowsPerPage: 25,
    svPass: '',
    hasGalleryAddon: false,
    loading: true,
  };

  const fmt = ts => (typeof ts === 'number' && ts > 0)
    ? (new Date(ts)).toLocaleDateString('en-GB',{day:'2-digit',month:'2-digit',year:'2-digit'})
    : '-';
  const fmtFull = ts => (typeof ts === 'number' && ts > 0)
    ? (new Date(ts)).toLocaleString('en-GB',{day:'2-digit',month:'2-digit',year:'2-digit',hour:'2-digit',minute:'2-digit'})
    : '-';
  const cleanTel = t => String(t || '').replace(/\D/g,'');
  const isRegular = d => {
    const tel = cleanTel(d.tel);
    return tel && (state.phoneFrequency[tel] || 0) > 1;
  };
  const generateCode = prefix => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let s = '';
    for (let i = 0; i < 6; i++) s += chars[Math.floor(Math.random() * chars.length)];
    return prefix + s;
  };
  const formatWaTel = t => {
    let n = String(t || '').replace(/\D/g,'');
    if (n.startsWith('0')) n = '6' + n;
    if (!n.startsWith('6')) n = '60' + n;
    return n;
  };

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'dc-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2500);
  }

  // ── LOAD BRANCH / ADDON ──
  (async function loadPrefs() {
    try {
      const shop = await db.collection('shops_' + ownerID).doc(shopID).get();
      if (shop.exists) state.svPass = (shop.data().svPass || '').toString();
    } catch(_) {}
    try {
      const dealer = await db.collection('saas_dealers').doc(ownerID).get();
      if (dealer.exists) {
        const d = dealer.data();
        let has = d.addonGallery === true;
        if (has && d.galleryExpire != null && Date.now() > Number(d.galleryExpire)) has = false;
        if (!has) {
          try {
            const shop = await db.collection('shops_' + ownerID).doc(shopID).get();
            if (shop.exists) has = shop.data().hasGalleryAddon === true;
          } catch(_) {}
        }
        state.hasGalleryAddon = has;
      }
    } catch(_) {}
  })();

  // ── LISTENERS ──
  db.collection('repairs_' + ownerID).where('shopID', '==', shopID).onSnapshot(snap => {
    const list = [], freq = {};
    snap.forEach(doc => {
      const d = Object.assign({ _docId: doc.id }, doc.data());
      const nama = String(d.nama || '').toUpperCase();
      const jenis = String(d.jenis_servis || '').toUpperCase();
      if (nama === 'JUALAN PANTAS' || jenis === 'JUALAN') return;
      list.push(d);
      const tel = cleanTel(d.tel);
      if (tel) freq[tel] = (freq[tel] || 0) + 1;
    });
    list.sort((a,b) => num(b.timestamp) - num(a.timestamp));
    state.allRepairs = list;
    state.phoneFrequency = freq;
    state.loading = false;
    applyFilter(); render();
  });

  db.collection('phone_sales_' + ownerID).where('shopID', '==', shopID).onSnapshot(snap => {
    const list = [];
    snap.forEach(doc => list.push(Object.assign({ _docId: doc.id }, doc.data())));
    list.sort((a,b) => num(b.timestamp) - num(a.timestamp));
    state.allSales = list;
    if (state.segment === 1) { applyFilter(); render(); } else { render(); }
  });

  db.collection('referrals_' + ownerID).onSnapshot(snap => {
    const refs = {};
    snap.forEach(doc => {
      const d = Object.assign({ _docId: doc.id }, doc.data());
      const tel = cleanTel(d.tel);
      if (tel) refs[tel] = d;
    });
    state.referrals = refs;
    applyFilter(); render();
  });

  db.collection('referral_claims_' + ownerID).onSnapshot(snap => {
    const claims = {};
    snap.forEach(doc => {
      const d = Object.assign({ _docId: doc.id }, doc.data());
      const code = String(d.referral_code || '');
      if (!code) return;
      (claims[code] = claims[code] || []).push(d);
    });
    state.referralClaims = claims;
  });

  // ── FILTER ──
  function applyFilter() {
    let data = (state.segment === 0 ? state.allRepairs : state.allSales).slice();
    const q = state.search.toLowerCase().trim();
    if (q) {
      data = data.filter(d => {
        if (state.segment === 1) {
          return String(d.nama||'').toLowerCase().includes(q)
              || String(d.kod||'').toLowerCase().includes(q)
              || String(d.imei||'').toLowerCase().includes(q)
              || String(d.warna||'').toLowerCase().includes(q);
        }
        return String(d.nama||'').toLowerCase().includes(q)
            || String(d.tel||'').toLowerCase().includes(q)
            || String(d.model||'').toLowerCase().includes(q);
      });
    }
    if (state.exactDate) {
      const dd = state.exactDate;
      const s = new Date(dd.getFullYear(), dd.getMonth(), dd.getDate()).getTime();
      const e = s + 86400000;
      data = data.filter(d => { const t = num(d.timestamp); return t >= s && t < e; });
    }
    if (state.time !== 'SEMUA') {
      const now = new Date();
      const start = state.time === 'HARI_INI'
        ? new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        : new Date(now.getFullYear(), now.getMonth(), 1).getTime();
      data = data.filter(d => num(d.timestamp) >= start);
    }
    if (state.aff !== 'SEMUA') {
      data = data.filter(d => {
        const has = !!state.referrals[cleanTel(d.tel)];
        return state.aff === 'AFFILIATE' ? has : !has;
      });
    }
    if (state.sort === 'A-Z') {
      data.sort((a,b) => String(a.nama||'').toUpperCase().localeCompare(String(b.nama||'').toUpperCase()));
    } else {
      data.sort((a,b) => num(b.timestamp) - num(a.timestamp));
    }
    state.filtered = data;
    state.page = 1;
  }

  const totalPages = () => Math.max(1, Math.ceil(state.filtered.length / state.rowsPerPage));
  const pageData = () => {
    const s = (state.page - 1) * state.rowsPerPage;
    return state.filtered.slice(s, s + state.rowsPerPage);
  };

  // ── RENDER ──
  function render() {
    $('cntRepair').textContent = state.allRepairs.length;
    $('cntSales').textContent = state.allSales.length;

    const list = $('dcList'); list.innerHTML = '';
    const data = pageData();
    $('dcEmpty').hidden = data.length > 0;

    data.forEach((d, i) => {
      const idx = (state.page - 1) * state.rowsPerPage + i + 1;
      list.appendChild(state.segment === 0 ? repairCard(d, idx) : salesCard(d, idx));
    });

    const pag = $('dcPagination');
    if (state.filtered.length > state.rowsPerPage) {
      pag.hidden = false;
      $('pageInfo').textContent = state.page + ' / ' + totalPages();
      $('btnPrev').disabled = state.page <= 1;
      $('btnNext').disabled = state.page >= totalPages();
    } else {
      pag.hidden = true;
    }
    $('dcFooter').textContent = state.filtered.length + ' ' + (state.segment === 0 ? 'repair' : 'jualan');
  }

  function badge(label, icon, color) {
    return `<span class="dc-badge" style="background:${color}22;color:${color};border:1px solid ${color}55;"><i class="fas ${icon}"></i>${esc(label)}</span>`;
  }

  function repairCard(d, idx) {
    const status = String(d.status || '').toUpperCase();
    const harga = parseFloat(d.total ?? d.harga ?? 0) || 0;
    const tel = String(d.tel || '-');
    const telC = cleanTel(tel);
    const isReg = isRegular(d);
    const hasRef = !!state.referrals[telC];
    const hasAnyImg = ['img_sebelum_depan','img_sebelum_belakang','img_selepas_depan','img_selepas_belakang','img_cust']
      .some(k => d[k] && String(d[k]).length);
    const statusColor = status === 'COMPLETED' ? '#10b981' : (status === 'CANCEL' || status === 'CANCELLED') ? '#ef4444' : '#3b82f6';
    const el = document.createElement('div');
    el.className = 'dc-card' + (hasRef ? ' has-ref' : '');
    el.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <div class="dc-card__nama" data-action="open">
          <span style="color:#94a3b8;font-size:10px;">${idx}.</span>
          ${esc(String(d.nama || '-').toUpperCase())}
        </div>
        <div class="dc-card__harga">RM ${harga.toFixed(2)}</div>
      </div>
      <div class="dc-info">
        <span><i class="fas fa-phone" style="color:#10b981;"></i>${esc(tel)}</span>
        <span><i class="fas fa-mobile-screen-button" style="color:#3b82f6;"></i>${esc(d.model || '-')}</span>
      </div>
      <div class="dc-info" style="margin-top:2px;">
        <span><i class="fas fa-screwdriver-wrench" style="color:#eab308;"></i>${esc(d.kerosakan || '-')}</span>
      </div>
      <div class="dc-badges">
        ${badge(fmt(d.timestamp), 'fa-clock', '#94a3b8')}
        ${badge(status || '-', 'fa-circle-info', statusColor)}
        ${isReg ? badge('REGULAR ('+(state.phoneFrequency[telC])+'x)','fa-fire','#f97316') : ''}
        ${hasRef ? badge('AFFILIATE', 'fa-handshake', '#eab308') : ''}
        ${state.hasGalleryAddon
          ? `<span class="dc-badge" data-gal style="background:${hasAnyImg?'#eab30822':'#f1f5f9'};color:${hasAnyImg?'#eab308':'#94a3b8'};border:1px solid ${hasAnyImg?'#eab30855':'#e2e8f0'};cursor:pointer;"><i class="fas fa-images"></i>${hasAnyImg?'GALERI':'TIADA'}</span>`
          : `<span class="dc-badge" data-gal-lock style="background:#f1f5f9;color:#94a3b8;cursor:pointer;"><i class="fas fa-lock"></i>GALERI</span>`}
      </div>
    `;
    el.querySelector('[data-action="open"]').addEventListener('click', () => showPusatTindakan(d));
    const gal = el.querySelector('[data-gal]');
    if (gal) gal.addEventListener('click', () => showGallery(d));
    const lock = el.querySelector('[data-gal-lock]');
    if (lock) lock.addEventListener('click', () => snack('Sila langgan Add-on Gallery Premium', true));
    return el;
  }

  function salesCard(d, idx) {
    const nama = String(d.nama || '-').toUpperCase();
    const kod = String(d.kod || '');
    const imei = String(d.imei || '-');
    const warna = String(d.warna || '');
    const storage = String(d.storage || '');
    const harga = num(d.jual);
    const staff = String(d.staffJual || '-');
    const imgUrl = String(d.imageUrl || '');
    const el = document.createElement('div');
    el.className = 'dc-card sales';
    el.innerHTML = `
      <div class="dc-phone-img">
        ${imgUrl.startsWith('http') ? `<img src="${esc(imgUrl)}" onerror="this.outerHTML='<i class=\\'fas fa-mobile-screen-button\\' style=\\'color:#06b6d4;\\'></i>'">` : `<i class="fas fa-mobile-screen-button" style="color:#06b6d4;"></i>`}
      </div>
      <div style="flex:1;min-width:0;">
        <div style="display:flex;justify-content:space-between;gap:6px;">
          <div style="font-weight:900;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${idx}. ${esc(nama)}</div>
          <div class="dc-card__harga">RM ${harga.toFixed(2)}</div>
        </div>
        <div class="dc-info">
          ${storage ? `<span><i class="fas fa-database" style="color:#3b82f6;"></i>${esc(storage)}</span>` : ''}
          ${warna ? `<span><i class="fas fa-palette" style="color:#eab308;"></i>${esc(warna)}</span>` : ''}
        </div>
        <div class="dc-info" style="margin-top:2px;">
          <span><i class="fas fa-barcode" style="color:#94a3b8;"></i>IMEI: ${esc(imei)}</span>
        </div>
        <div class="dc-badges">
          ${badge(fmt(d.timestamp), 'fa-clock', '#94a3b8')}
          ${kod ? badge(kod, 'fa-tag', '#06b6d4') : ''}
          ${badge(staff, 'fa-user-tag', '#3b82f6')}
        </div>
      </div>
    `;
    return el;
  }

  // ── PUSAT TINDAKAN MODAL ──
  function showPusatTindakan(job) {
    const nama = String(job.nama || '-');
    const tel = String(job.tel || '-');
    const siri = String(job.siri || '-');
    const telC = cleanTel(tel);
    const hasRef = !!state.referrals[telC];
    const refCode = hasRef ? String(state.referrals[telC].referral_code || '-') : '';

    const body = $('actionBody');
    body.innerHTML = `
      <div style="background:#f8fafc;border:1px solid var(--border);border-radius:12px;padding:12px;margin-bottom:12px;">
        <div style="font-weight:900;font-size:13px;"><i class="fas fa-user" style="color:#2563eb;"></i> ${esc(nama.toUpperCase())}</div>
        <div style="margin-top:6px;font-size:12px;color:var(--text-muted);">
          <i class="fas fa-phone" style="color:#10b981;"></i> ${esc(tel)} &nbsp;
          <i class="fas fa-hashtag" style="color:#eab308;"></i> <span style="color:#eab308;font-weight:700;">${esc(siri)}</span>
        </div>
        ${isRegular(job) ? `<div style="margin-top:6px;"><span class="dc-badge" style="background:#f9731622;color:#f97316;border:1px solid #f9731655;"><i class="fas fa-fire"></i>REGULAR (${state.phoneFrequency[telC]}x)</span></div>` : ''}
      </div>
      <div class="dc-action" data-act="referral" style="background:#eab30815;border:1px solid #eab30855;color:#eab308;">
        <i class="fas fa-handshake"></i>
        <span style="flex:1;">${hasRef ? 'REFERRAL: ' + esc(refCode) : 'GENERATE REFERRAL'}</span>
        <i class="fas fa-chevron-right" style="opacity:.5;"></i>
      </div>
      <div class="dc-action" data-act="whatsapp" style="background:#10b98115;border:1px solid #10b98155;color:#10b981;">
        <i class="fab fa-whatsapp"></i>
        <span style="flex:1;">HANTAR LINK VIA WHATSAPP</span>
        <i class="fas fa-chevron-right" style="opacity:.5;"></i>
      </div>
      ${state.hasGalleryAddon ? `
      <div class="dc-action" data-act="gallery" style="background:#3b82f615;border:1px solid #3b82f655;color:#3b82f6;">
        <i class="fas fa-images"></i>
        <span style="flex:1;">LIHAT GALERI</span>
        <i class="fas fa-chevron-right" style="opacity:.5;"></i>
      </div>` : ''}
      ${hasRef ? buildClaimsSection(telC) : ''}
    `;
    body.querySelectorAll('[data-act]').forEach(btn => {
      btn.addEventListener('click', () => {
        const act = btn.getAttribute('data-act');
        closeModal('modalAction');
        if (act === 'referral') showReferralModal(job);
        else if (act === 'whatsapp') showSendLinkModal(job);
        else if (act === 'gallery') showGallery(job);
      });
    });
    body.querySelectorAll('[data-claim-toggle]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const id = btn.getAttribute('data-claim-toggle');
        const paid = btn.getAttribute('data-paid') === '1';
        const newStatus = paid ? 'BELUM BAYAR' : 'PAID';
        try {
          await db.collection('referral_claims_' + ownerID).doc(id).update({ status: newStatus });
          snack('Status dikemaskini: ' + newStatus);
          showPusatTindakan(job);
        } catch(e) { snack('Gagal: ' + e.message, true); }
      });
    });
    openModal('modalAction');
  }

  function buildClaimsSection(telC) {
    const refData = state.referrals[telC]; if (!refData) return '';
    const refCode = String(refData.referral_code || '');
    const claims = state.referralClaims[refCode] || [];
    let html = `<div style="margin:16px 0 8px;"><i class="fas fa-list-check" style="color:#eab308;"></i> <span style="color:#eab308;font-weight:900;font-size:11px;">REFERRAL CLAIMS</span></div>`;
    if (claims.length === 0) {
      html += `<div style="padding:12px;background:#f1f5f9;border-radius:8px;color:#94a3b8;font-size:11px;">Tiada claim lagi.</div>`;
      return html;
    }
    claims.forEach(c => {
      const status = String(c.status || 'BELUM BAYAR').toUpperCase();
      const isPaid = status === 'PAID';
      const comm = num(c.commission).toFixed(2);
      html += `
        <div class="dc-claim">
          <div>
            <div style="font-weight:700;font-size:11px;">${esc(c.claimer_name || '-')}</div>
            <div style="font-size:10px;color:var(--text-muted);">RM ${comm}</div>
          </div>
          <button data-claim-toggle="${esc(c._docId)}" data-paid="${isPaid?1:0}"
            style="padding:5px 10px;border-radius:6px;border:1px solid ${isPaid?'#10b981':'#eab308'};background:${isPaid?'#10b98122':'#eab30822'};color:${isPaid?'#10b981':'#eab308'};font-weight:900;font-size:9px;cursor:pointer;">
            ${isPaid ? 'PAID' : 'BELUM BAYAR'}
          </button>
        </div>`;
    });
    return html;
  }

  // ── REFERRAL MODAL ──
  function showReferralModal(job) {
    const tel = String(job.tel || '');
    const nama = String(job.nama || '-');
    const telC = cleanTel(tel);
    const existing = state.referrals[telC];
    const body = $('referralBody');
    body.innerHTML = `
      ${existing ? `
      <div style="background:#eab3081a;border:1px solid #eab30855;border-radius:8px;padding:12px;margin-bottom:12px;">
        <div style="font-size:9px;font-weight:900;color:var(--text-muted);">REFERRAL SEDIA ADA</div>
        <div style="font-size:16px;font-weight:900;color:#eab308;letter-spacing:1px;">${esc(existing.referral_code || '-')}</div>
        <div style="font-size:11px;">Komisen: RM ${num(existing.commission).toFixed(2)}</div>
        <div style="font-size:10px;color:var(--text-dim);">Had: ${esc(existing.usage_limit||'-')} | Bank: ${esc(existing.bank_name||'-')} ${esc(existing.bank_account||'')}</div>
      </div>` : ''}
      <label class="set-label">KATA LALUAN ADMIN</label>
      <input class="input" type="password" id="refPass" placeholder="Masukkan kata laluan">
      <label class="set-label" style="margin-top:10px;">KOMISEN (RM)</label>
      <input class="input" type="number" step="0.01" id="refComm" placeholder="0.00">
      <label class="set-label" style="margin-top:10px;">HAD PENGGUNAAN</label>
      <input class="input" type="number" id="refLimit" value="10">
      <label class="set-label" style="margin-top:10px;">NAMA BANK</label>
      <input class="input" id="refBankName" placeholder="Cth: MAYBANK">
      <label class="set-label" style="margin-top:10px;">NO. AKAUN BANK</label>
      <input class="input" id="refBankAcc" placeholder="Cth: 1234567890">
      <button id="refSave" style="margin-top:16px;width:100%;padding:14px;background:#eab308;color:#000;border:none;border-radius:10px;font-weight:900;cursor:pointer;">
        <i class="fas fa-handshake"></i> JANA REFERRAL
      </button>
    `;
    $('refSave').addEventListener('click', async () => {
      const pass = $('refPass').value.trim();
      const comm = parseFloat($('refComm').value) || 0;
      const limit = parseInt($('refLimit').value) || 10;
      if (!pass || pass !== state.svPass) { snack('Kata laluan tidak sah', true); return; }
      if (comm <= 0) { snack('Sila masukkan nilai komisen', true); return; }
      try {
        const code = generateCode('REF-');
        await db.collection('referrals_' + ownerID).add({
          referral_code: code,
          nama: nama.toUpperCase(),
          tel: tel,
          commission: comm,
          usage_limit: limit,
          usage_count: 0,
          bank_name: $('refBankName').value.trim().toUpperCase(),
          bank_account: $('refBankAcc').value.trim(),
          shopID: shopID,
          ownerID: ownerID,
          created_at: Date.now(),
          status: 'ACTIVE',
        });
        closeModal('modalReferral');
        snack('Referral ' + code + ' berjaya dijana!');
      } catch(e) { snack('Gagal: ' + e.message, true); }
    });
    openModal('modalReferral');
  }

  // ── SEND LINK MODAL ──
  function showSendLinkModal(job) {
    const tel = String(job.tel || '');
    const nama = String(job.nama || '-');
    const telC = cleanTel(tel);
    const voucher = String(job.voucher_generated || '');
    const refData = state.referrals[telC];
    const refCode = String(refData?.referral_code || '');
    const voucherLink = voucher ? 'https://rmspro.net/voucher?code=' + voucher + '&owner=' + ownerID : '';
    const referralLink = refCode ? 'https://rmspro.net/referral?code=' + refCode + '&owner=' + ownerID : '';

    const linkBox = (title, code, link, color) => `
      <div class="dc-link-box" style="background:${color}0f;border:1px solid ${color}44;">
        <div style="font-size:9px;font-weight:900;color:${color};letter-spacing:.5px;">${title}</div>
        <div class="code" style="color:${color};">${esc(code)}</div>
        <div class="url">${esc(link)}</div>
        <div class="dc-link-actions">
          <button data-wa="${esc(link)}" style="background:#10b981;"><i class="fab fa-whatsapp"></i> WHATSAPP</button>
          <button data-copy="${esc(link)}" style="background:#64748b;"><i class="fas fa-copy"></i> SALIN LINK</button>
        </div>
      </div>`;

    const body = $('linkBody');
    body.innerHTML = `
      <div style="font-size:12px;color:var(--text-muted);margin-bottom:12px;">PELANGGAN: <b>${esc(nama)}</b></div>
      ${voucherLink ? linkBox('VOUCHER LINK', voucher, voucherLink, '#06b6d4')
        : `<div style="padding:12px;background:#f1f5f9;border-radius:8px;color:#94a3b8;font-size:11px;margin-bottom:10px;">Tiada voucher.</div>`}
      ${referralLink ? linkBox('REFERRAL LINK', refCode, referralLink, '#eab308')
        : `<div style="padding:12px;background:#f1f5f9;border-radius:8px;color:#94a3b8;font-size:11px;">Tiada referral.</div>`}
    `;
    body.querySelectorAll('[data-wa]').forEach(b => b.addEventListener('click', () => {
      const link = b.getAttribute('data-wa');
      const waUrl = 'https://wa.me/' + formatWaTel(tel) + '?text=' + encodeURIComponent('Terima kasih! Gunakan link ini:\n' + link);
      window.open(waUrl, '_blank');
    }));
    body.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(b.getAttribute('data-copy')); snack('Link disalin!'); }
      catch { snack('Gagal salin', true); }
    }));
    openModal('modalLink');
  }

  // ── GALLERY ──
  function showGallery(job) {
    if (!state.hasGalleryAddon) { snack('Sila langgan Add-on Gallery Premium', true); return; }
    const siri = job.siri || '-';
    $('galTitle').textContent = 'GALERI #' + siri;
    const types = [
      {k:'img_sebelum_depan', label:'SEBELUM (DEPAN)', c:'#3b82f6'},
      {k:'img_sebelum_belakang', label:'SEBELUM (BLKNG)', c:'#3b82f6'},
      {k:'img_selepas_depan', label:'SELEPAS (DEPAN)', c:'#2563eb'},
      {k:'img_selepas_belakang', label:'SELEPAS (BLKNG)', c:'#2563eb'},
      {k:'img_cust', label:'GAMBAR CUST', c:'#eab308'},
    ];
    const body = $('galleryBody');
    body.innerHTML = types.map(t => {
      const url = String(job[t.k] || '');
      const has = url && (url.startsWith('http') || url.startsWith('data:'));
      return `
        <div class="dc-gal-cell" style="border-color:${t.c}33;">
          <div class="label" style="background:${t.c}22;color:${t.c};">${t.label}</div>
          <div class="img" ${has?`style="background-image:url('${esc(url)}');" data-full="${esc(url)}" data-label="${t.label}"`:''}>
            ${has ? '' : '<i class="fas fa-image" style="font-size:20px;"></i>'}
          </div>
        </div>`;
    }).join('');
    body.querySelectorAll('[data-full]').forEach(el => el.addEventListener('click', () => {
      const url = el.getAttribute('data-full');
      const w = window.open('', '_blank');
      if (w) w.document.write('<title>'+el.getAttribute('data-label')+'</title><body style="margin:0;background:#000;display:flex;align-items:center;justify-content:center;min-height:100vh;"><img src="'+url+'" style="max-width:100%;max-height:100vh;">');
    }));
    openModal('modalGallery');
  }

  // ── EXPORT CSV ──
  function exportCSV() {
    if (state.filtered.length === 0) { snack('Tiada data untuk eksport', true); return; }
    const rows = [];
    if (state.segment === 0) {
      rows.push('No,Tarikh,Nama,Telefon,Model,Kerosakan,Status,Harga,Regular,Affiliate');
    } else {
      rows.push('No,Tarikh,Nama,Kod,IMEI,Storage,Warna,Harga,Staff');
    }
    state.filtered.forEach((d, i) => {
      const tel = String(d.tel || '-');
      const telC = cleanTel(tel);
      const isReg = telC && (state.phoneFrequency[telC] || 0) > 1;
      const hasRef = !!state.referrals[telC];
      const esc = s => '"' + String(s ?? '-').replace(/"/g,'""') + '"';
      if (state.segment === 0) {
        rows.push([
          i+1, fmtFull(d.timestamp), esc(d.nama), tel, esc(d.model), esc(d.kerosakan),
          d.status || '-',
          'RM ' + (parseFloat(d.total ?? d.harga ?? 0) || 0).toFixed(2),
          isReg ? 'REGULAR' : '-',
          hasRef ? 'YA' : 'TIDAK',
        ].join(','));
      } else {
        rows.push([
          i+1, fmtFull(d.timestamp), esc(d.nama), d.kod || '-', d.imei || '-',
          d.storage || '-', d.warna || '-',
          'RM ' + num(d.jual).toFixed(2), d.staffJual || '-',
        ].join(','));
      }
    });
    const blob = new Blob(['\ufeff' + rows.join('\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    const ts = new Date().toISOString().replace(/[:.]/g,'-').slice(0,19);
    a.href = URL.createObjectURL(blob);
    a.download = 'db_cust_' + ts + '.csv';
    a.click();
    snack('Fail CSV disimpan');
  }

  // ── MODAL HELPERS ──
  function openModal(id){ $(id).classList.add('show'); }
  function closeModal(id){ $(id).classList.remove('show'); }
  document.querySelectorAll('.dc-modal-bg').forEach(bg => {
    bg.addEventListener('click', e => { if (e.target === bg) bg.classList.remove('show'); });
    bg.querySelectorAll('[data-close]').forEach(x => x.addEventListener('click', () => bg.classList.remove('show')));
  });

  // ── EVENTS ──
  document.querySelectorAll('.dc-toggle button').forEach(b => {
    b.addEventListener('click', () => {
      state.segment = parseInt(b.getAttribute('data-seg'));
      document.querySelectorAll('.dc-toggle button').forEach(x => x.classList.remove('is-active'));
      b.classList.add('is-active');
      applyFilter(); render();
    });
  });
  $('dcSearch').addEventListener('input', e => { state.search = e.target.value; applyFilter(); render(); });
  $('fSort').addEventListener('change', e => { state.sort = e.target.value; applyFilter(); render(); });
  $('fTime').addEventListener('change', e => { state.time = e.target.value; applyFilter(); render(); });
  $('fAff').addEventListener('change', e => { state.aff = e.target.value; applyFilter(); render(); });
  $('dcDateBtn').addEventListener('click', () => {
    if (state.exactDate) {
      state.exactDate = null;
      $('dcDateLbl').textContent = 'TARIKH';
      $('dcDateBtn').classList.remove('is-active');
      applyFilter(); render();
    } else {
      $('dcDate').showPicker ? $('dcDate').showPicker() : $('dcDate').click();
    }
  });
  $('dcDate').addEventListener('change', e => {
    if (e.target.value) {
      state.exactDate = new Date(e.target.value);
      $('dcDateLbl').textContent = e.target.value.split('-').reverse().slice(0,2).join('/');
      $('dcDateBtn').classList.add('is-active');
      applyFilter(); render();
    }
  });
  $('btnPrev').addEventListener('click', () => { if (state.page > 1) { state.page--; render(); } });
  $('btnNext').addEventListener('click', () => { if (state.page < totalPages()) { state.page++; render(); } });
  $('btnExport').addEventListener('click', exportCSV);
})();
