/* Port dari lib/screens/modules/booking_screen.dart */
(function () {
  'use strict';
  if (!document.getElementById('bkList')) return;

  const CLOUD_RUN = 'https://rms-backend-94407896005.asia-southeast1.run.app';
  const NOTIF_URL = 'https://us-central1-rmspro-2f454.cloudfunctions.net/sendBookingNotification';

  // ---------- branch context ----------
  let ownerID = 'admin', shopID = 'MAIN';
  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0]; shopID = (p[1] || '').toUpperCase();
  }

  // ---------- state ----------
  let bookings = [];
  let viewMode = 'ACTIVE';
  let sortOrder = 'desc';
  let searchText = '';
  let courierList = ['TIADA', 'J&T EXPRESS', 'POSLAJU', 'NINJAVAN', 'LALAMOVE'];
  let staffList = [];
  let branchSettings = {};
  let domain = 'https://rmspro.net';

  // ---------- helpers ----------
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const attr = s => String(s ?? '').replace(/"/g, '&quot;');
  const num = v => { const n = Number(v); return isNaN(n) ? 0 : n; };
  const money = v => 'RM ' + num(v).toFixed(2);

  function toast(msg, err = false) {
    const t = $('bkToast');
    t.textContent = msg;
    t.classList.toggle('is-err', !!err);
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => { t.hidden = true; }, 2500);
  }

  function openModal(id) { $(id).classList.add('is-open'); }
  function closeModal(id) { $(id).classList.remove('is-open'); }

  document.addEventListener('click', e => {
    const b = e.target.closest('[data-close]');
    if (b) closeModal(b.dataset.close);
    // click backdrop
    if (e.target.classList.contains('bk-modal-backdrop')) e.target.classList.remove('is-open');
  });

  function fmtDate(v) {
    if (typeof v === 'string' && v.includes('T')) return v.replace('T', ' ');
    if (typeof v === 'string') return v;
    return '-';
  }

  function kiraBaki(hargaEl, depositEl, bakiEl) {
    const h = num(hargaEl.value), d = num(depositEl.value);
    bakiEl.value = Math.max(0, h - d).toFixed(2);
  }

  function waFormat(tel) {
    let n = String(tel || '').replace(/[^0-9]/g, '');
    if (n.startsWith('0')) n = '6' + n;
    return n;
  }

  // ---------- Firebase init ----------
  const db = window.db || firebase.firestore();
  const storage = firebase.storage();

  async function loadSettings() {
    try {
      const doc = await db.collection('shops_' + ownerID).doc(shopID).get();
      if (doc.exists) {
        const d = doc.data();
        branchSettings = d;
        if (Array.isArray(d.courierList)) courierList = d.courierList.slice();
        if (!courierList.includes('TIADA')) courierList.unshift('TIADA');
        if (Array.isArray(d.staffList)) {
          staffList = d.staffList.map(s => typeof s === 'object' ? (s.name || s.nama || '') : s).filter(Boolean);
        }
      }
    } catch (e) { console.warn('shop settings', e); }
    try {
      const dealer = await db.collection('saas_dealers').doc(ownerID).get();
      if (dealer.exists) domain = dealer.data().domain || domain;
    } catch (_) {}
    refreshStaffSelect();
  }

  function refreshStaffSelect() {
    const sel = $('bkStaff');
    const wrap = $('bkStaffWrap');
    if (!staffList.length) { wrap.hidden = true; return; }
    wrap.hidden = false;
    sel.innerHTML = '<option value="">-- PILIH STAFF --</option>' +
      staffList.map(s => `<option value="${attr(s)}">${esc(s)}</option>`).join('');
  }

  // ---------- Live listener ----------
  db.collection('bookings_' + ownerID).onSnapshot(snap => {
    const list = [];
    snap.forEach(doc => {
      const d = doc.data(); d.key = doc.id;
      if (String(d.shopID || '').toUpperCase() === shopID) list.push(d);
    });
    bookings = list;
    render();
  }, err => console.warn('bookings listener', err));

  // ---------- Filter + sort ----------
  function filtered() {
    let list = bookings.slice();
    list = list.filter(b => {
      const s = String(b.status || 'ACTIVE');
      if (viewMode === 'ACTIVE') return s !== 'ARCHIVED' && s !== 'DELETED';
      return s === viewMode;
    });
    const q = searchText.toLowerCase().trim();
    if (q) {
      list = list.filter(b =>
        String(b.nama || '').toLowerCase().includes(q) ||
        String(b.tel || '').includes(q) ||
        String(b.siriBooking || '').toLowerCase().includes(q)
      );
    }
    switch (sortOrder) {
      case 'asc': list.sort((a, b) => num(a.timestamp) - num(b.timestamp)); break;
      case 'az':  list.sort((a, b) => String(a.nama || '').localeCompare(String(b.nama || ''))); break;
      case 'za':  list.sort((a, b) => String(b.nama || '').localeCompare(String(a.nama || ''))); break;
      default:    list.sort((a, b) => num(b.timestamp) - num(a.timestamp));
    }
    return list;
  }

  // ---------- Render ----------
  function render() {
    const arr = filtered();
    const list = $('bkList'), empty = $('bkEmpty');
    if (!arr.length) {
      list.innerHTML = ''; empty.classList.remove('hidden'); return;
    }
    empty.classList.add('hidden');
    list.innerHTML = arr.map(b => {
      const deposit = num(b.deposit);
      const hasPaid = deposit > 0;
      const staff = b.staff || '';
      const resit = String(b.resitUrl || '');
      const tagStaff = staff ? `<span class="bk-card__tag c-yellow"><i class="fas fa-user-tag"></i>${esc(staff)}</span>` : '';
      const viewResit = resit
        ? `<button type="button" class="bk-card__resit-btn" data-img="${attr(resit)}"><i class="fas fa-receipt"></i> LIHAT RESIT</button>`
        : '';
      return `
        <article class="bk-card" data-key="${attr(b.key)}">
          <div class="bk-card__siri" data-print="${attr(b.key)}">
            ${esc(b.siriBooking || '-')} <i class="fas fa-print"></i>
          </div>
          <div class="bk-card__row">
            <span class="bk-card__nama">${esc(b.nama || '-')}</span>
            <span class="bk-card__harga">${money(b.harga)}</span>
            ${hasPaid ? '<span class="bk-card__paid">PAID</span>' : ''}
          </div>
          ${viewResit}
          <div class="bk-card__tel" data-phone="${attr(b.key)}">
            <i class="fas fa-phone"></i> ${esc(b.tel || '-')}
          </div>
          <div class="bk-card__item">${esc(b.item || '-')}</div>
          <div class="bk-card__meta">
            <span class="bk-card__date">${esc(fmtDate(b.tarikhBooking))}</span>
            ${tagStaff}
          </div>
        </article>
      `;
    }).join('');
  }

  // ---------- List event delegation ----------
  $('bkList').addEventListener('click', e => {
    const print = e.target.closest('[data-print]');
    if (print) { const b = bookings.find(x => x.key === print.dataset.print); if (b) showPrintModal(b); return; }
    const phone = e.target.closest('[data-phone]');
    if (phone) { const b = bookings.find(x => x.key === phone.dataset.phone); if (b) showPhone(b); return; }
    const img = e.target.closest('[data-img]');
    if (img) { showFullImage(img.dataset.img); return; }
    const card = e.target.closest('.bk-card');
    if (card) { const b = bookings.find(x => x.key === card.dataset.key); if (b) showDetail(b); }
  });
  $('bkList').addEventListener('contextmenu', e => {
    const card = e.target.closest('.bk-card');
    if (!card) return;
    e.preventDefault();
    const b = bookings.find(x => x.key === card.dataset.key);
    if (b) showCardPopup(b);
  });
  // long-press (touch) for action popup
  let lpTimer = null;
  $('bkList').addEventListener('touchstart', e => {
    const card = e.target.closest('.bk-card');
    if (!card) return;
    lpTimer = setTimeout(() => {
      const b = bookings.find(x => x.key === card.dataset.key);
      if (b) showCardPopup(b);
    }, 550);
  }, { passive: true });
  $('bkList').addEventListener('touchend', () => clearTimeout(lpTimer));
  $('bkList').addEventListener('touchmove', () => clearTimeout(lpTimer));

  // ---------- Header controls ----------
  $('bkTabs').addEventListener('click', e => {
    const btn = e.target.closest('.bk-tab');
    if (!btn) return;
    $('bkTabs').querySelectorAll('.bk-tab').forEach(x => x.classList.remove('is-active'));
    btn.classList.add('is-active');
    viewMode = btn.dataset.mode;
    render();
  });
  $('bkSearch').addEventListener('input', e => { searchText = e.target.value; render(); });
  $('bkSort').addEventListener('change', e => { sortOrder = e.target.value; render(); });

  // ---------- NEW BOOKING ----------
  $('bkNewBtn').addEventListener('click', () => openAdd());

  function populatePayInfo(container) {
    const qr = branchSettings.bookingQrImageUrl || '';
    const bt = branchSettings.bookingBankType || '';
    const bn = branchSettings.bookingBankAccName || '';
    const ba = branchSettings.bookingBankAccount || '';
    let html = '';
    if (qr) html += `<img src="${attr(qr)}" alt="qr">`;
    if (!qr && !ba) html += `<div class="bk-paybox__empty">Belum ditetapkan — Sila set di ikon gear (⚙)</div>`;
    if (bt) html += `<div class="bk-paybox__bank">${esc(bt)}</div>`;
    if (bn) html += `<div class="bk-paybox__bankname">${esc(bn)}</div>`;
    if (ba) html += `<div class="bk-paybox__acc" data-copy="${attr(ba)}">${esc(ba)} <i class="fas fa-copy"></i></div>`;
    container.innerHTML = html;
  }

  let addResitUrl = '';
  function openAdd() {
    $('bkNama').value = ''; $('bkTel').value = '';
    $('bkItem').value = ''; $('bkHarga').value = '0';
    $('bkDeposit').value = '0'; $('bkBaki').value = '0';
    $('bkTarikhCust').value = '';
    addResitUrl = '';
    refreshStaffSelect();
    if ($('bkStaff')) $('bkStaff').value = '';
    // payment info
    populatePayInfo($('bkAddPayInfo'));
    // reset resit box
    const box = $('bkAddResitBox');
    box.classList.remove('has-img');
    box.querySelector('.bk-upload__empty').classList.remove('hidden');
    box.querySelector('.bk-upload__preview').classList.add('hidden');
    openModal('bkAddModal');
  }

  $('bkHarga').addEventListener('input', () => kiraBaki($('bkHarga'), $('bkDeposit'), $('bkBaki')));
  $('bkDeposit').addEventListener('input', () => kiraBaki($('bkHarga'), $('bkDeposit'), $('bkBaki')));

  $('bkAddResit').addEventListener('change', async e => {
    const f = e.target.files[0];
    if (!f) return;
    const url = await uploadResit(f);
    if (!url) return;
    addResitUrl = url;
    const box = $('bkAddResitBox');
    box.classList.add('has-img');
    box.querySelector('.bk-upload__empty').classList.add('hidden');
    const prev = box.querySelector('.bk-upload__preview');
    prev.classList.remove('hidden');
    prev.querySelector('img').src = url;
  });

  // click-to-copy account number (delegated)
  document.addEventListener('click', e => {
    const cp = e.target.closest('[data-copy]');
    if (cp) {
      navigator.clipboard.writeText(cp.dataset.copy).then(() => toast('No akaun disalin!'));
    }
  });

  $('bkAddSave').addEventListener('click', async () => {
    const nama = $('bkNama').value.trim().toUpperCase();
    const tel = $('bkTel').value.trim();
    const item = $('bkItem').value.trim().toUpperCase();
    if (!nama || !tel || !item) { toast('Sila isi maklumat', true); return; }
    const siri = 'BKG-' + String(Date.now()).slice(7);
    const harga = num($('bkHarga').value);
    const deposit = num($('bkDeposit').value);
    const baki = Math.max(0, harga - deposit);
    const staff = $('bkStaff') ? $('bkStaff').value : '';
    const now = new Date();
    const tarikhBooking = now.toISOString().slice(0, 16); // yyyy-MM-ddTHH:mm
    const rec = {
      shopID, siriBooking: siri, nama, tel, item, staff,
      tarikhBooking,
      tarikhCustDatang: $('bkTarikhCust').value.trim(),
      harga, deposit, baki,
      status: 'ACTIVE', kurier: 'TIADA', tracking_no: '', tracking_status: 'MENUNGGU PROSES',
      timestamp: Date.now(),
      resitUrl: addResitUrl || '',
      pdfUrl_INVOICE: '', pdfUrl_QUOTATION: '',
    };
    try {
      await db.collection('bookings_' + ownerID).add(rec);
      // push notify
      fetch(NOTIF_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ownerID, shopID, customerName: nama, item, siriBooking: siri }),
      }).catch(() => {});
      closeModal('bkAddModal');
      toast('Booking #' + siri + ' berjaya!');
    } catch (e) {
      toast('Gagal simpan: ' + e.message, true);
    }
  });

  // ---------- UPLOAD RESIT ----------
  async function uploadResit(file) {
    try {
      toast('Uploading resit...');
      const ref = storage.ref().child(`booking_resit/${ownerID}/${Date.now()}.jpg`);
      await ref.put(file, { contentType: file.type || 'image/jpeg' });
      return await ref.getDownloadURL();
    } catch (e) {
      toast('Gagal upload: ' + e.message, true);
      return null;
    }
  }

  // ---------- GEAR (Payment Settings) ----------
  $('bkGearBtn').addEventListener('click', () => openGear());

  let gearQr = '';
  function openGear() {
    gearQr = branchSettings.bookingQrImageUrl || '';
    $('bkBankType').value = branchSettings.bookingBankType || '';
    $('bkBankName').value = branchSettings.bookingBankAccName || '';
    $('bkBankAcc').value  = branchSettings.bookingBankAccount || '';
    renderGearQr();
    openModal('bkGearModal');
  }

  function renderGearQr() {
    const box = $('bkQrBox');
    const empty = box.querySelector('.bk-upload__empty');
    const prev = box.querySelector('.bk-upload__preview');
    const del = $('bkQrDel');
    if (gearQr) {
      box.classList.add('has-img');
      empty.classList.add('hidden');
      prev.classList.remove('hidden');
      prev.querySelector('img').src = gearQr;
      del.classList.remove('hidden');
    } else {
      box.classList.remove('has-img');
      empty.classList.remove('hidden');
      prev.classList.add('hidden');
      del.classList.add('hidden');
    }
  }

  $('bkQrFile').addEventListener('change', async e => {
    const f = e.target.files[0];
    if (!f) return;
    try {
      toast('Uploading QR...');
      const ref = storage.ref().child(`booking_settings/${ownerID}/${shopID}/qr_${Date.now()}.jpg`);
      await ref.put(f, { contentType: f.type || 'image/jpeg' });
      gearQr = await ref.getDownloadURL();
      renderGearQr();
      toast('QR berjaya dimuat naik');
    } catch (err) { toast('Gagal upload: ' + err.message, true); }
  });

  $('bkQrDel').addEventListener('click', () => { gearQr = ''; renderGearQr(); });

  $('bkGearSave').addEventListener('click', async () => {
    const data = {
      bookingQrImageUrl: gearQr,
      bookingBankType: $('bkBankType').value.trim().toUpperCase(),
      bookingBankAccName: $('bkBankName').value.trim().toUpperCase(),
      bookingBankAccount: $('bkBankAcc').value.trim(),
    };
    try {
      await db.collection('shops_' + ownerID).doc(shopID).set(data, { merge: true });
      Object.assign(branchSettings, data);
      closeModal('bkGearModal');
      toast('Tetapan pembayaran disimpan');
    } catch (e) { toast('Gagal simpan: ' + e.message, true); }
  });

  // ---------- COURIER ----------
  $('bkCourierBtn').addEventListener('click', () => openCourier());

  function openCourier() { $('bkNewCourier').value = ''; renderCourierList(); openModal('bkCourierModal'); }

  function renderCourierList() {
    $('bkCourierList').innerHTML = courierList.filter(k => k !== 'TIADA').map(k =>
      `<div class="bk-courier-list__item">
        <span>${esc(k)}</span>
        <button type="button" class="bk-courier-list__del" data-k="${attr(k)}"><i class="fas fa-trash"></i></button>
      </div>`).join('') || '<div class="bk-note">Tiada kurier. Tambah di atas.</div>';
  }

  $('bkAddCourier').addEventListener('click', async () => {
    const v = $('bkNewCourier').value.trim().toUpperCase();
    if (!v || courierList.includes(v)) return;
    courierList.push(v);
    $('bkNewCourier').value = '';
    await db.collection('shops_' + ownerID).doc(shopID).set({ courierList }, { merge: true });
    renderCourierList();
  });

  $('bkCourierList').addEventListener('click', async e => {
    const btn = e.target.closest('[data-k]');
    if (!btn) return;
    courierList = courierList.filter(x => x !== btn.dataset.k);
    await db.collection('shops_' + ownerID).doc(shopID).set({ courierList }, { merge: true });
    renderCourierList();
  });

  // ---------- DETAIL ----------
  function showDetail(b) {
    const kurierOpts = courierList.map(k => `<option ${k === (b.kurier || 'TIADA') ? 'selected' : ''} value="${attr(k)}">${esc(k)}</option>`).join('');
    const statusList = ['MENUNGGU PROSES', 'DALAM PERJALANAN', 'BARANG SAMPAI', 'COMPLETED'];
    const statusOpts = statusList.map(s => `<option ${s === (b.tracking_status || 'MENUNGGU PROSES') ? 'selected' : ''} value="${attr(s)}">${esc(s)}</option>`).join('');
    const resit = String(b.resitUrl || '');

    $('bkDetailTitle').innerHTML = `<i class="fas fa-user-astronaut"></i><span></span>`;
    $('bkDetailBody').innerHTML = `
      <div class="bk-detail-avatar">
        <div class="bk-detail-avatar__circle"><i class="fas fa-user-astronaut"></i></div>
        <div class="bk-detail-avatar__name">${esc(b.nama || '-')}</div>
        <div class="bk-detail-avatar__siri">${esc(b.siriBooking || '-')}</div>
      </div>

      <div class="bk-section c-primary">
        <div class="bk-section__title c-primary"><i class="fas fa-money-bill"></i> MAKLUMAT BAYARAN</div>
        <div class="bk-pay-grid">
          <div class="bk-field"><label>HARGA (RM)</label><input id="bkDHarga" type="number" step="0.01" class="bk-input" value="${num(b.harga).toFixed(2)}"></div>
          <div class="bk-field"><label>DEPOSIT (RM)</label><input id="bkDDeposit" type="number" step="0.01" class="bk-input" value="${num(b.deposit).toFixed(2)}"></div>
          <div class="bk-field"><label>BAKI (RM)</label><input id="bkDBaki" type="number" class="bk-input" value="${num(b.baki).toFixed(2)}" readonly></div>
        </div>
        <button type="button" class="bk-btn c-primary" id="bkDSavePay"><i class="fas fa-floppy-disk"></i> SIMPAN BAYARAN</button>
      </div>

      <div class="bk-section ${resit ? 'c-green' : 'c-muted'}">
        <div class="bk-section__title ${resit ? 'c-green' : 'c-muted'}" style="display:flex;justify-content:space-between;align-items:center">
          <span><i class="fas fa-receipt"></i> RESIT PEMBAYARAN</span>
          <label class="bk-btn c-cyan" style="width:auto;padding:6px 10px;font-size:10px;cursor:pointer">
            <input type="file" id="bkDResitFile" accept="image/*" hidden>
            <i class="fas fa-cloud-arrow-up"></i> ${resit ? 'Tukar' : 'Upload'}
          </label>
        </div>
        <div class="bk-detail-resit">
          ${resit
            ? `<img src="${attr(resit)}" data-img="${attr(resit)}" alt="resit"><div class="bk-note" style="text-align:center">Tekan gambar untuk lihat penuh</div>`
            : `<div class="bk-note">Customer belum upload resit</div>`}
        </div>
      </div>

      <div class="bk-section c-yellow">
        <div class="bk-section__title c-yellow"><i class="fas fa-truck"></i> PENGURUSAN TRACKING</div>
        <div class="bk-field"><label>JENIS KURIER</label><select id="bkDKurier" class="bk-input">${kurierOpts}</select></div>
        <div class="bk-field"><label>NO TRACKING</label><input id="bkDTrack" type="text" class="bk-input bk-caps" value="${attr(b.tracking_no || '')}" placeholder="Isi no tracking..."></div>
        <div class="bk-field"><label>STATUS SEMASA</label><select id="bkDStatus" class="bk-input">${statusOpts}</select></div>
      </div>

      <button type="button" class="bk-btn c-primary-soft" id="bkDSaveTrack"><i class="fas fa-arrows-rotate"></i> KEMASKINI TRACKING</button>

      <div class="bk-row">
        <button type="button" class="bk-btn c-green" id="bkDWa"><i class="fab fa-whatsapp"></i> WHATSAPP</button>
        <button type="button" class="bk-btn c-red" id="bkDDel"><i class="fas fa-trash-can"></i> DELETE</button>
      </div>
    `;

    openModal('bkDetailModal');

    // wire events
    const hargaEl = $('bkDHarga'), depEl = $('bkDDeposit'), bakiEl = $('bkDBaki');
    hargaEl.addEventListener('input', () => kiraBaki(hargaEl, depEl, bakiEl));
    depEl.addEventListener('input', () => kiraBaki(hargaEl, depEl, bakiEl));

    $('bkDSavePay').addEventListener('click', async () => {
      await db.collection('bookings_' + ownerID).doc(b.key).update({
        harga: num(hargaEl.value), deposit: num(depEl.value), baki: num(bakiEl.value),
      });
      toast('Bayaran dikemaskini');
    });

    $('bkDResitFile').addEventListener('change', async e => {
      const f = e.target.files[0];
      if (!f) return;
      const url = await uploadResit(f);
      if (!url) return;
      await db.collection('bookings_' + ownerID).doc(b.key).update({ resitUrl: url });
      b.resitUrl = url;
      showDetail(b); // refresh
      toast('Resit berjaya dimuat naik');
    });

    $('bkDSaveTrack').addEventListener('click', async () => {
      await db.collection('bookings_' + ownerID).doc(b.key).update({
        kurier: $('bkDKurier').value,
        tracking_no: $('bkDTrack').value.trim().toUpperCase(),
        tracking_status: $('bkDStatus').value,
      });
      closeModal('bkDetailModal');
      toast('Tracking dikemaskini');
    });

    $('bkDWa').addEventListener('click', () => sendWhatsApp(b));
    $('bkDDel').addEventListener('click', () => {
      confirmDialog(`Padam ${b.nama}?`, 'Rekod akan dibuang dari Firestore.', async () => {
        await db.collection('bookings_' + ownerID).doc(b.key).delete();
        closeModal('bkDetailModal');
        toast('Booking dipadam');
      });
    });
  }

  function sendWhatsApp(b) {
    const wa = waFormat(b.tel);
    const msg = `Salam ${b.nama || ''},\n\n*No Tempahan:* ${b.siriBooking || ''}\n*Item:* ${b.item || ''}\n*Harga:* RM${num(b.harga).toFixed(2)}\n*Deposit:* RM${num(b.deposit).toFixed(2)}\n*Baki:* RM${num(b.baki).toFixed(2)}\n\nTerima Kasih.`;
    window.open(`https://wa.me/${wa}?text=${encodeURIComponent(msg)}`, '_blank');
  }

  // ---------- PHONE MODAL ----------
  function showPhone(b) {
    $('bkPhoneText').textContent = b.tel || '-';
    $('bkPhoneCall').onclick = () => { closeModal('bkPhoneModal'); window.location.href = 'tel:' + b.tel; };
    $('bkPhoneWa').onclick = () => { closeModal('bkPhoneModal'); window.open('https://wa.me/' + waFormat(b.tel), '_blank'); };
    openModal('bkPhoneModal');
  }

  // ---------- ACTION POPUP ----------
  function showCardPopup(b) {
    $('bkActionTitle').textContent = String(b.nama || '-').toUpperCase();
    let html = '';
    const setStatus = async (s, msg) => {
      await db.collection('bookings_' + ownerID).doc(b.key).update({ status: s });
      closeModal('bkActionModal'); toast(msg);
    };
    if (viewMode === 'ACTIVE') {
      html += `<button type="button" class="bk-action-tile c-yellow" data-act="archive"><i class="fas fa-box-archive"></i> Arkib</button>`;
      html += `<button type="button" class="bk-action-tile c-red" data-act="soft-del"><i class="fas fa-trash-can"></i> Padam</button>`;
    } else if (viewMode === 'ARCHIVED') {
      html += `<button type="button" class="bk-action-tile c-primary" data-act="restore"><i class="fas fa-arrow-rotate-left"></i> Pulihkan</button>`;
    } else if (viewMode === 'DELETED') {
      html += `<button type="button" class="bk-action-tile c-primary" data-act="restore"><i class="fas fa-arrow-rotate-left"></i> Pulihkan</button>`;
      html += `<button type="button" class="bk-action-tile c-red" data-act="hard-del"><i class="fas fa-trash-can"></i> Padam Kekal</button>`;
    }
    $('bkActionBody').innerHTML = html;
    $('bkActionBody').onclick = async e => {
      const btn = e.target.closest('[data-act]');
      if (!btn) return;
      const act = btn.dataset.act;
      if (act === 'archive') return setStatus('ARCHIVED', 'Booking diarkibkan');
      if (act === 'soft-del') return setStatus('DELETED', 'Booking dialih ke sampah');
      if (act === 'restore') return setStatus('ACTIVE', 'Booking dipulihkan');
      if (act === 'hard-del') {
        closeModal('bkActionModal');
        confirmDialog(`Padam kekal ${b.nama}?`, 'Tindakan ini tidak boleh dibatalkan.', async () => {
          await db.collection('bookings_' + ownerID).doc(b.key).delete();
          toast('Booking dipadam kekal');
        });
      }
    };
    openModal('bkActionModal');
  }

  // ---------- CONFIRM DIALOG ----------
  function confirmDialog(title, msg, onOk) {
    $('bkConfirmTitle').textContent = title;
    $('bkConfirmMsg').textContent = msg;
    $('bkConfirmOk').onclick = async () => { closeModal('bkConfirmModal'); await onOk(); };
    openModal('bkConfirmModal');
  }

  // ---------- FULL IMAGE ----------
  function showFullImage(url) {
    const v = $('bkImgViewer');
    v.querySelector('img').src = url;
    v.classList.remove('hidden');
  }
  $('bkImgViewer').addEventListener('click', () => $('bkImgViewer').classList.add('hidden'));

  // ---------- PRINT ----------
  function showPrintModal(b) {
    const siri = b.siriBooking || '-';
    $('bkPrintSiri').textContent = '#' + siri;
    const hasInvoice = !!(b.pdfUrl_INVOICE);
    const hasQuote = !!(b.pdfUrl_QUOTATION);
    const btn = (cls, icon, title, desc) =>
      `<button type="button" class="bk-print-item c-${cls}">
        <span class="bk-print-item__icon"><i class="fas ${icon}"></i></span>
        <span class="bk-print-item__text">
          <span class="bk-print-item__title">${esc(title)}</span>
          <span class="bk-print-item__desc">${esc(desc)}</span>
        </span>
        <i class="fas fa-chevron-right bk-print-item__chev"></i>
      </button>`;
    const items = [];
    items.push({ html: btn('blue', 'fa-receipt', 'RESIT 80MM', 'Cetak thermal (Bluetooth) — web tidak disokong'), act: 'thermal' });
    items.push(hasInvoice
      ? { html: btn('green', 'fa-eye', 'VIEW BOOKING', 'Sudah dijana - tekan untuk buka'), act: 'view-inv' }
      : { html: btn('green', 'fa-file-pdf', 'GENERATE BOOKING', 'Jana booking A4 PDF'), act: 'gen-inv' });
    items.push(hasQuote
      ? { html: btn('yellow', 'fa-eye', 'VIEW QUOTATION', 'Sudah dijana - tekan untuk buka'), act: 'view-quo' }
      : { html: btn('yellow', 'fa-file-lines', 'GENERATE QUOTATION', 'Jana sebut harga A4 PDF'), act: 'gen-quo' });

    $('bkPrintBody').innerHTML = items.map(x => x.html).join('');
    const buttons = $('bkPrintBody').querySelectorAll('.bk-print-item');
    buttons.forEach((el, i) => {
      el.onclick = () => {
        const act = items[i].act;
        closeModal('bkPrintModal');
        if (act === 'thermal') toast('Thermal print tidak disokong di web', true);
        else if (act === 'view-inv') window.open(b.pdfUrl_INVOICE, '_blank');
        else if (act === 'view-quo') window.open(b.pdfUrl_QUOTATION, '_blank');
        else if (act === 'gen-inv') generatePDF(b, 'INVOICE');
        else if (act === 'gen-quo') generatePDF(b, 'QUOTATION');
      };
    });
    openModal('bkPrintModal');
  }

  function buildPdfPayload(b, typePDF) {
    return {
      typePDF, paperSize: 'A4',
      templatePdf: branchSettings.templatePdf || 'tpl_1',
      logoBase64: branchSettings.logoBase64 || '',
      namaKedai: branchSettings.shopName || branchSettings.namaKedai || 'RMS PRO',
      alamatKedai: branchSettings.address || branchSettings.alamat || '-',
      telKedai: branchSettings.phone || branchSettings.ownerContact || '-',
      noJob: b.siriBooking || '-',
      namaCust: b.nama || '-',
      telCust: b.tel || '-',
      tarikhResit: String(b.tarikhBooking || new Date().toISOString()).split('T')[0],
      stafIncharge: b.staff || 'Admin',
      items: [{ nama: b.item || '-', harga: num(b.harga) }],
      model: b.item || '-', kerosakan: b.item || '-',
      warranty: 'TIADA', warranty_exp: '',
      voucherAmt: 0, diskaunAmt: 0, tambahanAmt: 0,
      depositAmt: num(b.deposit), totalDibayar: num(b.harga),
      statusBayar: num(b.deposit) > 0 ? 'PAID' : 'UNPAID',
      nota: typePDF === 'INVOICE'
        ? (branchSettings.notaInvoice || 'Sila simpan dokumen ini untuk rujukan rasmi.')
        : (branchSettings.notaQuotation || 'Sebut harga ini sah untuk tempoh 7 hari sahaja.'),
    };
  }

  async function generatePDF(b, typePDF) {
    toast('Menjana ' + typePDF + '...');
    try {
      const controller = new AbortController();
      const to = setTimeout(() => controller.abort(), 15000);
      const res = await fetch(CLOUD_RUN + '/generate-pdf', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(buildPdfPayload(b, typePDF)),
        signal: controller.signal,
      });
      clearTimeout(to);
      if (!res.ok) { toast('Gagal menjana: ' + res.status, true); return; }
      const out = await res.json();
      const pdfUrl = out.pdfUrl || '';
      if (!pdfUrl) { toast('Pautan PDF tidak ditemui', true); return; }
      await db.collection('bookings_' + ownerID).doc(b.key).update({ ['pdfUrl_' + typePDF]: pdfUrl });
      toast(typePDF + ' berjaya dijana!');
      window.open(pdfUrl, '_blank');
    } catch (e) {
      toast('Gagal sambung server: ' + e.message, true);
    }
  }

  // ---------- init ----------
  loadSettings();
})();
