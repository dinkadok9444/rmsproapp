/* Baikpulih — port 1:1 daripada lib/screens/modules/create_job_screen.dart
   Wizard 3-langkah (Pelanggan → Kerosakan & Harga → Bayaran) + Gambar (addon). */
(function () {
  'use strict';
  if (!document.getElementById('bpItems')) return;

  // ─── Branch / owner ───
  let ownerID = 'admin', shopID = 'MAIN';
  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = (p[0] || '').toLowerCase();
    shopID = (p[1] || '').toUpperCase();
  }
  const storage = (window.firebase && firebase.storage) ? firebase.storage() : null;

  // ─── State ───
  const state = {
    custType: 'NEW CUST',
    jenisServis: 'TAK PASTI',
    paymentStatus: 'UNPAID',
    caraBayaran: 'TAK PASTI',
    staffTerima: '',
    staffList: [],
    branchSettings: {},
    existingCustomers: [],
    activeVouchers: [],
    voucherByTel: {},
    kodVoucher: '',
    voucherAmt: 0,
    items: [{ nama: '', qty: 1, harga: 0 }],
    patternPts: [],
    imgDepan: null,
    imgBelakang: null,
    tarikhEdited: false,
    tarikh: new Date(),
    hasGallery: false,
    isSaving: false,
    lastSaved: null,
    shopInfo: {},
    step: 0,
    stepsOrder: ['1', '2', '3'], // gallery diselit antara 2 & 3 bila addon aktif
  };

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  const num = v => { const n = parseFloat(v); return isNaN(n) ? 0 : n; };
  const pad = (n, l = 2) => String(n).padStart(l, '0');
  const fmt = n => 'RM ' + (Number(n) || 0).toFixed(2);
  const cleanTel = t => String(t || '').replace(/\D/g, '');

  // ─── Tarikh auto ───
  function setTarikhInput() {
    const d = state.tarikh;
    $('bpTarikh').value = `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  setTarikhInput();
  setInterval(() => {
    if (!state.tarikhEdited && !state.isSaving) {
      state.tarikh = new Date();
      setTarikhInput();
    }
  }, 1000);
  $('bpTarikh').addEventListener('change', e => {
    state.tarikhEdited = true;
    state.tarikh = new Date(e.target.value);
  });

  // ─── Load branch / staff / vouchers / referrals / customers ───
  async function loadData() {
    const merged = {};
    try { const d = await db.collection('saas_dealers').doc(ownerID).get(); if (d.exists) Object.assign(merged, d.data() || {}); } catch (_) {}
    try { const s = await db.collection('shops_' + ownerID).doc(shopID).get(); if (s.exists) Object.assign(merged, s.data() || {}); } catch (_) {}

    let hasGallery = merged.addonGallery === true;
    if (hasGallery && merged.galleryExpire && Date.now() > merged.galleryExpire) hasGallery = false;
    state.hasGallery = hasGallery;
    state.branchSettings = merged;
    $('bpGallerySect').hidden = !hasGallery;
    if (hasGallery) state.stepsOrder = ['1', '2', 'gallery', '3'];

    state.shopInfo = {
      shopName: merged.shopName || merged.namaKedai || 'RMS PRO',
      address: merged.address || merged.alamat || '',
      phone: merged.phone || merged.ownerContact || '-',
      notaInvoice: merged.notaInvoice || 'Terima kasih atas sokongan anda.',
    };

    const staffList = Array.isArray(merged.staffList) ? merged.staffList.map(s => {
      if (typeof s === 'string') return s;
      if (s && typeof s === 'object') return s.name || s.nama || '';
      return '';
    }).filter(Boolean) : [];
    state.staffList = staffList;
    const sel = $('bpStaff');
    if (staffList.length) {
      sel.innerHTML = staffList.map(s => `<option value="${esc(s)}">${esc(s)}</option>`).join('');
      state.staffTerima = staffList[0];
      sel.value = staffList[0];
    } else {
      sel.innerHTML = '<option value="">(Tiada staff)</option>';
    }

    // Vouchers
    try {
      const vs = await db.collection('shop_vouchers_' + ownerID).get();
      vs.forEach(doc => {
        const d = doc.data() || {};
        state.activeVouchers.push({ code: d.code || doc.id, value: d.value || 0, ...d });
        const code = d.code || doc.id;
        const tel = cleanTel(d.customerTel || d.custTel);
        if (tel) (state.voucherByTel[tel] = state.voucherByTel[tel] || []).push(code);
        else (state.voucherByTel['_SHOP'] = state.voucherByTel['_SHOP'] || []).push(code);
      });
    } catch (_) {}

    // Referrals
    const referralByTel = {};
    try {
      const rs = await db.collection('referrals_' + ownerID).get();
      rs.forEach(doc => {
        const d = doc.data() || {};
        const tel = cleanTel(d.tel);
        if (!tel) return;
        referralByTel[tel] = d.refCode || doc.id;
      });
    } catch (_) {}

    // Existing customers
    try {
      const snap = await db.collection('repairs_' + ownerID).get();
      const seen = new Set();
      const custs = [];
      snap.forEach(doc => {
        const d = doc.data() || {};
        if (String(d.shopID || '').toUpperCase() !== shopID) return;
        const tel = String(d.tel || '').trim();
        if (!tel || seen.has(tel)) return;
        seen.add(tel);
        const key = cleanTel(tel);
        const vList = state.voucherByTel[key] || [];
        custs.push({
          nama: d.nama || '',
          tel,
          tel_wasap: d.tel_wasap || d.wasap || '',
          model: d.model || '',
          voucher: vList[0] || '',
          referral: referralByTel[key] || '',
        });
      });
      state.existingCustomers = custs;
      $('bpCustList').innerHTML = custs.slice(0, 50).map(c => `<option value="${esc(c.nama)}" label="${esc(c.tel)}">`).join('');
    } catch (_) {}
  }
  loadData();

  // ─── Wizard step logic ───
  const STEP_NAMES = { '1': 'PELANGGAN', '2': 'KEROSAKAN & HARGA', 'gallery': 'GAMBAR', '3': 'BAYARAN' };
  function showStep() {
    const key = state.stepsOrder[state.step];
    document.querySelectorAll('.bp-step').forEach(el => {
      el.hidden = el.dataset.step !== key;
      el.classList.toggle('is-active', el.dataset.step === key);
    });
    const total = state.stepsOrder.length;
    const now = state.step + 1;
    $('bpStepNow').textContent = now;
    $('bpStepTotal').textContent = total;
    $('bpStepName').textContent = STEP_NAMES[key] || '-';
    $('bpStepFill').style.width = Math.round((now / total) * 100) + '%';
    $('bpPrev').hidden = state.step === 0;
    const isLast = state.step === state.stepsOrder.length - 1;
    $('bpNext').hidden = isLast;
    $('bpSave').hidden = !isLast;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
  function validateStep() {
    const key = state.stepsOrder[state.step];
    if (key === '1') {
      if (!$('bpNama').value.trim()) return toast('Sila isi Nama Pelanggan', true), false;
      if (!$('bpTel').value.trim()) return toast('Sila isi No Telefon', true), false;
    } else if (key === '2') {
      const valid = state.items.filter(it => (it.nama || '').trim());
      if (!valid.length) return toast('Sila tambah sekurang-kurangnya satu item', true), false;
    }
    return true;
  }
  $('bpNext').addEventListener('click', () => {
    if (!validateStep()) return;
    if (state.step < state.stepsOrder.length - 1) { state.step++; showStep(); }
  });
  $('bpPrev').addEventListener('click', () => {
    if (state.step > 0) { state.step--; showStep(); }
  });

  // ─── Toggle NEW CUST / REGULAR ───
  $('bpCustTypeToggle').addEventListener('click', e => {
    const b = e.target.closest('button[data-v]'); if (!b) return;
    document.querySelectorAll('#bpCustTypeToggle button').forEach(x => x.classList.toggle('is-on', x === b));
    const v = b.dataset.v;
    state.custType = v;
    $('bpCustType').value = v;
    $('bpCustSearchRow').hidden = v !== 'REGULAR';
  });

  // ─── Customer search ───
  $('bpCustSearch').addEventListener('input', e => {
    const q = e.target.value.toLowerCase().trim();
    const hits = $('bpCustHits');
    if (!q) { hits.hidden = true; hits.innerHTML = ''; return; }
    const r = state.existingCustomers.filter(c =>
      (c.nama || '').toLowerCase().includes(q) ||
      (c.tel || '').includes(q) ||
      (c.voucher || '').toLowerCase().includes(q) ||
      (c.referral || '').toLowerCase().includes(q)
    ).slice(0, 8);
    hits.hidden = r.length === 0;
    hits.innerHTML = r.map((c, i) => {
      const badges = [
        c.voucher ? `<span class="bp-cust-badge bp-cust-badge--v"><i class="fas fa-ticket"></i>${esc(c.voucher)}</span>` : '',
        c.referral ? `<span class="bp-cust-badge bp-cust-badge--r"><i class="fas fa-user-plus"></i>${esc(c.referral)}</span>` : '',
      ].join('');
      return `
        <div class="bp-cust-hit" data-i="${i}">
          <i class="fas fa-user-check bp-cust-hit__ic"></i>
          <div class="bp-cust-hit__body">
            <div class="bp-cust-hit__name">${esc((c.nama || '').toUpperCase())}</div>
            <div class="bp-cust-hit__tel">Tel: ${esc(c.tel)}</div>
            ${badges ? `<div class="bp-cust-hit__badges">${badges}</div>` : ''}
          </div>
        </div>`;
    }).join('');
    hits._data = r;
  });
  $('bpCustHits').addEventListener('click', e => {
    const h = e.target.closest('.bp-cust-hit'); if (!h) return;
    const hits = $('bpCustHits'); const c = hits._data[+h.dataset.i];
    $('bpNama').value = c.nama;
    $('bpTel').value = c.tel;
    $('bpWasap').value = c.tel_wasap || '';
    $('bpCustSearch').value = '';
    hits.hidden = true;
    if (state.custType !== 'REGULAR') {
      state.custType = 'REGULAR'; $('bpCustType').value = 'REGULAR';
      document.querySelectorAll('#bpCustTypeToggle button').forEach(x => x.classList.toggle('is-on', x.dataset.v === 'REGULAR'));
    }
  });
  $('bpNama').addEventListener('change', e => {
    const val = e.target.value;
    try {
      const opt = $('bpCustList').querySelector(`option[value="${CSS.escape(val)}"]`);
      if (opt && opt.getAttribute('label') && !$('bpTel').value) $('bpTel').value = opt.getAttribute('label');
    } catch (_) {}
  });

  // ─── Backup modal ───
  $('bpBackupBtn').addEventListener('click', () => $('bpBackupModal').classList.add('is-open'));
  $('bpBackupClose').addEventListener('click', () => $('bpBackupModal').classList.remove('is-open'));
  $('bpBackupSave').addEventListener('click', () => {
    $('bpBackupModal').classList.remove('is-open');
    $('bpBackupBtn').classList.toggle('is-on', !!$('bpWasap').value.trim());
  });
  $('bpBackupModal').addEventListener('click', e => { if (e.target === $('bpBackupModal')) $('bpBackupModal').classList.remove('is-open'); });

  // ─── Pattern modal ───
  function refreshPatternUI() {
    const str = state.patternPts.join('-') || '-';
    $('bpPatternTxtModal').textContent = str;
    $('bpPatternTxt').textContent = str;
    $('bpPatternChip').hidden = state.patternPts.length === 0;
    $('bpPatternBtn').classList.toggle('is-on', state.patternPts.length > 0);
    document.querySelectorAll('.bp-pattern-dot').forEach(x =>
      x.classList.toggle('is-on', state.patternPts.includes(+x.dataset.n)));
  }
  (function buildPattern() {
    const box = $('bpPatternBox');
    box.innerHTML = '';
    for (let i = 1; i <= 9; i++) {
      const d = document.createElement('div');
      d.className = 'bp-pattern-dot';
      d.textContent = i;
      d.dataset.n = i;
      d.addEventListener('click', () => {
        const n = +d.dataset.n;
        const idx = state.patternPts.indexOf(n);
        if (idx >= 0) state.patternPts.splice(idx, 1); else state.patternPts.push(n);
        refreshPatternUI();
      });
      box.appendChild(d);
    }
  })();
  function clearPattern() { state.patternPts = []; refreshPatternUI(); }
  $('bpPatternBtn').addEventListener('click', () => $('bpPatternModal').classList.add('is-open'));
  $('bpPatternClose').addEventListener('click', () => $('bpPatternModal').classList.remove('is-open'));
  $('bpPatternSave').addEventListener('click', () => $('bpPatternModal').classList.remove('is-open'));
  $('bpPatternClear').addEventListener('click', clearPattern);
  $('bpPatternReset').addEventListener('click', clearPattern);
  $('bpPatternModal').addEventListener('click', e => { if (e.target === $('bpPatternModal')) $('bpPatternModal').classList.remove('is-open'); });

  // ─── Voucher modal (butang + di step 2) ───
  function refreshVoucherUI() {
    const has = !!state.kodVoucher;
    $('bpVoucherChip').hidden = !has;
    if (has) $('bpVoucherChipTxt').textContent = `${state.kodVoucher} (-${fmt(state.voucherAmt)})`;
    $('bpVoucherBtn').classList.toggle('is-on', has);
    $('bpVoucherBtn').classList.toggle('is-on--yellow', has);
    $('bpPromo').value = state.kodVoucher;
    $('bpPromoMsg').textContent = has ? `Voucher aktif: -${fmt(state.voucherAmt)}` : '';
    updateTotals();
  }
  async function applyVoucherCode(kod, msgEl) {
    kod = (kod || '').trim().toUpperCase();
    state.kodVoucher = ''; state.voucherAmt = 0;
    if (!kod) { msgEl.textContent = ''; refreshVoucherUI(); return; }
    try {
      if (kod.startsWith('V-')) {
        const d = await db.collection('shop_vouchers_' + ownerID).doc(kod).get();
        if (!d.exists) { msgEl.textContent = 'Voucher tidak dijumpai'; refreshVoucherUI(); return; }
        const data = d.data() || {};
        if ((data.claimed || 0) >= (data.maxClaim || 1)) { msgEl.textContent = 'Voucher telah digunakan'; refreshVoucherUI(); return; }
        state.kodVoucher = kod; state.voucherAmt = num(data.value);
        msgEl.textContent = `Voucher diguna: -${fmt(state.voucherAmt)}`;
      } else if (kod.startsWith('REF-')) {
        const d = await db.collection('referrals_' + ownerID).doc(kod).get();
        if (!d.exists) { msgEl.textContent = 'Referral tidak dijumpai'; refreshVoucherUI(); return; }
        const data = d.data() || {};
        state.kodVoucher = kod; state.voucherAmt = num(data.rewardValue || data.value || 5);
        msgEl.textContent = `Referral diguna: -${fmt(state.voucherAmt)}`;
      } else {
        msgEl.textContent = 'Format kod tidak sah (V-... atau REF-...)';
      }
    } catch (e) { msgEl.textContent = 'Ralat: ' + e.message; }
    refreshVoucherUI();
  }
  $('bpVoucherBtn').addEventListener('click', () => {
    $('bpVoucherInput').value = state.kodVoucher || '';
    $('bpVoucherMsg').textContent = '';
    $('bpVoucherModal').classList.add('is-open');
  });
  $('bpVoucherClose').addEventListener('click', () => $('bpVoucherModal').classList.remove('is-open'));
  $('bpVoucherApply').addEventListener('click', async () => {
    await applyVoucherCode($('bpVoucherInput').value, $('bpVoucherMsg'));
    if (state.kodVoucher) setTimeout(() => $('bpVoucherModal').classList.remove('is-open'), 800);
  });
  $('bpVoucherReset').addEventListener('click', () => applyVoucherCode('', $('bpPromoMsg')));
  $('bpVoucherModal').addEventListener('click', e => { if (e.target === $('bpVoucherModal')) $('bpVoucherModal').classList.remove('is-open'); });
  $('bpPromoApply').addEventListener('click', () => applyVoucherCode($('bpPromo').value, $('bpPromoMsg')));

  // ─── Items ───
  function renderItems() {
    $('bpItems').innerHTML = state.items.map((it, i) => `
      <div class="bp-item" data-i="${i}">
        <input type="text" data-f="nama" value="${esc(it.nama)}" placeholder="Cari Inventori / taip manual..." class="bp-input bp-item__nama">
        <div class="bp-item__row2">
          <input type="number" data-f="qty" value="${it.qty}" min="1" class="bp-input bp-item__qty">
          <input type="number" data-f="harga" value="${Number(it.harga).toFixed(2)}" step="0.01" min="0" placeholder="Harga (RM)" class="bp-input bp-item__harga">
          <div class="bp-item__sub">RM ${((Number(it.qty) || 0) * (Number(it.harga) || 0)).toFixed(2)}</div>
          <button type="button" class="icon-btn icon-btn--danger" data-del="${i}" ${state.items.length === 1 ? 'disabled' : ''}><i class="fas fa-trash"></i></button>
        </div>
      </div>
    `).join('');
    updateTotals();
  }
  $('bpItems').addEventListener('input', e => {
    const row = e.target.closest('.bp-item'); if (!row) return;
    const i = +row.dataset.i; const f = e.target.dataset.f;
    if (f === 'nama') state.items[i].nama = e.target.value;
    else if (f === 'qty') state.items[i].qty = Math.max(1, parseInt(e.target.value, 10) || 1);
    else if (f === 'harga') state.items[i].harga = Math.max(0, num(e.target.value));
    const sub = row.querySelector('.bp-item__sub');
    if (sub) sub.textContent = 'RM ' + ((Number(state.items[i].qty) || 0) * (Number(state.items[i].harga) || 0)).toFixed(2);
    updateTotals();
  });
  $('bpItems').addEventListener('click', e => {
    const b = e.target.closest('[data-del]'); if (!b || state.items.length === 1) return;
    state.items.splice(+b.dataset.del, 1);
    renderItems();
  });
  $('bpAddItem').addEventListener('click', () => {
    state.items.push({ nama: '', qty: 1, harga: 0 });
    renderItems();
  });

  function subtotal() { return state.items.reduce((s, it) => s + (Number(it.qty) || 0) * (Number(it.harga) || 0), 0); }
  function updateTotals() {
    const sub = subtotal();
    const dep = num($('bpDeposit').value);
    const dis = num($('bpDiskaun').value);
    const vch = state.voucherAmt;
    const baki = sub - vch - dis - dep;
    $('bpItemTotal').textContent = fmt(sub);
    $('bpSubTotal').textContent = fmt(sub);
    $('bpVoucherShow').textContent = '- ' + fmt(vch);
    $('bpDiskaunShow').textContent = '- ' + fmt(dis);
    $('bpDepositShow').textContent = '- ' + fmt(dep);
    $('bpBaki').textContent = fmt(baki);
  }
  $('bpDeposit').addEventListener('input', updateTotals);
  $('bpDiskaun').addEventListener('input', updateTotals);

  // ─── Gallery ───
  function readFileToDataUrl(file) {
    return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(file); });
  }
  document.querySelectorAll('.bp-gallery-card').forEach(c => {
    c.addEventListener('click', () => {
      const id = c.dataset.k === 'depan' ? 'bpFileDepan' : 'bpFileBelakang';
      $(id).click();
    });
  });
  $('bpFileDepan').addEventListener('change', async e => {
    const f = e.target.files[0]; if (!f) return;
    state.imgDepan = await readFileToDataUrl(f);
    const c = document.querySelector('.bp-gallery-card[data-k="depan"]');
    c.style.backgroundImage = `url(${state.imgDepan})`;
    c.classList.add('is-ok');
    c.innerHTML = '<i class="fas fa-circle-check fa-2x"></i><div>DEPAN OK</div>';
  });
  $('bpFileBelakang').addEventListener('change', async e => {
    const f = e.target.files[0]; if (!f) return;
    state.imgBelakang = await readFileToDataUrl(f);
    const c = document.querySelector('.bp-gallery-card[data-k="belakang"]');
    c.style.backgroundImage = `url(${state.imgBelakang})`;
    c.classList.add('is-ok');
    c.innerHTML = '<i class="fas fa-circle-check fa-2x"></i><div>BELAKANG OK</div>';
  });
  async function uploadImages(siri) {
    const out = {};
    if (!state.hasGallery || !storage) return out;
    async function up(b64, label) {
      if (!b64) return null;
      try {
        const ref = storage.ref(`repairs/${ownerID}/${siri}/${label}_${Date.now()}.jpg`);
        await ref.putString(b64, 'data_url', { contentType: 'image/jpeg' });
        return await ref.getDownloadURL();
      } catch (_) { return null; }
    }
    const a = await up(state.imgDepan, 'depan'); if (a) out.img_sebelum_depan = a;
    const b = await up(state.imgBelakang, 'belakang'); if (b) out.img_sebelum_belakang = b;
    return out;
  }

  // ─── Bindings ───
  $('bpJenis').addEventListener('change', e => { state.jenisServis = e.target.value; });
  $('bpPayStatus').addEventListener('change', e => { state.paymentStatus = e.target.value; });
  $('bpPayMethod').addEventListener('change', e => { state.caraBayaran = e.target.value; });
  $('bpStaff').addEventListener('change', e => { state.staffTerima = e.target.value; });

  // ─── Header back / close ───
  $('bpBack').addEventListener('click', () => history.back());
  $('bpClose').addEventListener('click', () => {
    if (confirm('Tutup tiket ini? Data akan hilang.')) location.href = 'index.html';
  });

  // ─── Siri + save (tak diubah) ───
  async function getNextSiri() {
    const ref = db.collection('counters_' + ownerID).doc(shopID + '_global');
    const newCount = await db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      let count = 1;
      if (snap.exists) count = ((snap.data() || {}).count || 0) + 1;
      tx.set(ref, { count }, { merge: true });
      return count;
    });
    let pure = shopID; if (pure.includes('-')) pure = pure.split('-')[1];
    return pure + String(newCount).padStart(5, '0');
  }
  function genVoucherCode() {
    const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let r = ''; for (let i = 0; i < 6; i++) r += c[Math.floor(Math.random() * c.length)];
    return 'V-' + r;
  }

  $('bpSave').addEventListener('click', simpanTiket);

  function resetForm() {
    state.items = [{ nama: '', qty: 1, harga: 0 }];
    ['bpNama', 'bpTel', 'bpWasap', 'bpModel', 'bpPass', 'bpCatatan', 'bpPromo', 'bpCustSearch'].forEach(id => $(id).value = '');
    $('bpDeposit').value = '0'; $('bpDiskaun').value = '0';
    state.custType = 'NEW CUST'; $('bpCustType').value = 'NEW CUST';
    document.querySelectorAll('#bpCustTypeToggle button').forEach(x => x.classList.toggle('is-on', x.dataset.v === 'NEW CUST'));
    $('bpCustSearchRow').hidden = true;
    $('bpJenis').value = 'TAK PASTI'; state.jenisServis = 'TAK PASTI';
    $('bpPayStatus').value = 'UNPAID'; state.paymentStatus = 'UNPAID';
    $('bpPayMethod').value = 'TAK PASTI'; state.caraBayaran = 'TAK PASTI';
    clearPattern();
    state.kodVoucher = ''; state.voucherAmt = 0; refreshVoucherUI();
    $('bpBackupBtn').classList.remove('is-on');
    state.imgDepan = null; state.imgBelakang = null;
    document.querySelectorAll('.bp-gallery-card').forEach(c => {
      c.style.backgroundImage = ''; c.classList.remove('is-ok');
      const k = c.dataset.k;
      c.innerHTML = `<i class="fas fa-camera fa-2x"></i><div>${k.toUpperCase()}</div>`;
    });
    state.tarikhEdited = false; state.tarikh = new Date(); setTarikhInput();
    $('bpCustHits').hidden = true;
    state.step = 0; showStep();
    renderItems();
  }

  async function simpanTiket() {
    if (state.isSaving) return;
    const nama = $('bpNama').value.trim();
    const tel = $('bpTel').value.trim();
    if (!nama || !tel) return toast('Sila isi Nama & No Telefon', true);
    const validItems = state.items.filter(it => (it.nama || '').trim());
    if (!validItems.length) return toast('Sila tambah sekurang-kurangnya satu item', true);
    if (!state.staffTerima && state.staffList.length) return toast('Sila pilih staff terima', true);

    state.isSaving = true;
    const btn = $('bpSave');
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> MENYIMPAN...';

    try {
      const siri = await getNextSiri();
      const voucherGen = genVoucherCode();
      const phonePass = $('bpPass').value.trim();
      const patternResult = state.patternPts.join('-');
      let finalPass = phonePass || 'Tiada';
      if (patternResult && finalPass === 'Tiada') finalPass = 'Pattern: ' + patternResult;
      else if (patternResult) finalPass += ' (Pattern: ' + patternResult + ')';

      const harga = subtotal();
      const deposit = num($('bpDeposit').value);
      const diskaun = num($('bpDiskaun').value);
      const voucherAmt = state.voucherAmt;
      const total = harga - voucherAmt - diskaun - deposit;

      const itemsArray = validItems.map(i => ({ nama: String(i.nama).trim(), qty: parseInt(i.qty) || 1, harga: num(i.harga) }));
      const kerosakan = itemsArray.map(i => `${i.nama} (x${i.qty})`).join(', ');
      const d = state.tarikh;
      const tarikhStr = `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
      const telWasap = $('bpWasap').value.trim();

      const data = {
        siri, receiptNo: siri, shopID,
        nama: nama.toUpperCase(), pelanggan: nama.toUpperCase(),
        tel, telefon: tel,
        tel_wasap: telWasap || '-', wasap: telWasap || '-',
        model: $('bpModel').value.trim().toUpperCase(),
        kerosakan,
        items_array: itemsArray,
        tarikh: tarikhStr,
        harga: harga.toFixed(2),
        deposit: deposit.toFixed(2),
        diskaun: diskaun.toFixed(2),
        tambahan: '0',
        total: total.toFixed(2),
        baki: total.toFixed(2),
        voucher_generated: voucherGen,
        voucher_used: state.kodVoucher,
        voucher_used_amt: voucherAmt,
        payment_status: state.paymentStatus,
        cara_bayaran: state.caraBayaran,
        catatan: $('bpCatatan').value.trim(),
        jenis_servis: state.jenisServis,
        staff_terima: state.staffTerima,
        staff_repair: '',
        staff_serah: '',
        password: finalPass,
        cust_type: state.custType,
        status: 'IN PROGRESS',
        status_history: [{ status: 'IN PROGRESS', timestamp: tarikhStr }],
        timestamp: Date.now(),
      };

      await db.collection('repairs_' + ownerID).doc(siri).set(data);
      const imgUrls = await uploadImages(siri);
      if (Object.keys(imgUrls).length) {
        await db.collection('repairs_' + ownerID).doc(siri).update(imgUrls);
        Object.assign(data, imgUrls);
      }

      if (state.kodVoucher.startsWith('REF-')) {
        try {
          await db.collection('referral_claims_' + ownerID).add({
            referralCode: state.kodVoucher, claimedBy: tel,
            claimedByName: nama.toUpperCase(),
            siri, amount: voucherAmt, shopID, timestamp: Date.now(),
          });
        } catch (_) {}
      }
      if (state.kodVoucher.startsWith('V-')) {
        try {
          await db.collection('shop_vouchers_' + ownerID).doc(state.kodVoucher).update({
            claimed: firebase.firestore.FieldValue.increment(1),
          });
        } catch (_) {}
      }

      state.lastSaved = data;
      $('bpDoneSiri').textContent = '#' + siri;
      $('bpDoneAmt').textContent = 'Baki: ' + fmt(total);
      $('bpDoneStatus').textContent = 'IN PROGRESS';
      $('bpDonePrint').textContent = '';
      $('bpDoneModal').classList.add('is-open');

      if (window.RmsPrinter && RmsPrinter.isConnected()) {
        try {
          $('bpDonePrint').textContent = 'Mencetak resit…';
          await RmsPrinter.printReceipt(data, state.shopInfo);
          $('bpDonePrint').textContent = '✓ Resit dicetak';
        } catch (e) {
          $('bpDonePrint').textContent = '✗ Gagal cetak: ' + e.message;
        }
      }
    } catch (e) {
      toast('Gagal simpan: ' + e.message, true);
    }
    state.isSaving = false;
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-floppy-disk"></i> SIMPAN TIKET';
  }

  // ─── Done modal ───
  $('bpDoneOk').addEventListener('click', () => {
    $('bpDoneModal').classList.remove('is-open');
    resetForm();
  });
  $('bpDoneModal').addEventListener('click', e => {
    if (e.target === $('bpDoneModal')) $('bpDoneModal').classList.remove('is-open');
  });
  $('bpDonePrintBtn').addEventListener('click', async () => {
    if (!state.lastSaved) return;
    if (window.RmsPrinter && RmsPrinter.isConnected()) {
      try {
        $('bpDonePrint').textContent = 'Mencetak resit…';
        await RmsPrinter.printReceipt(state.lastSaved, state.shopInfo);
        $('bpDonePrint').textContent = '✓ Resit dicetak';
      } catch (e) {
        $('bpDonePrint').textContent = '✗ Gagal: ' + e.message;
      }
    } else {
      window.print();
    }
  });

  // ─── Printer ───
  (function wirePrinter() {
    const btn = $('bpPrinterBtn');
    const lbl = $('bpPrinterLbl');
    if (!btn || !window.RmsPrinter) return;
    RmsPrinter.onChange(st => {
      if (!st.supported) { btn.classList.add('is-disabled'); btn.title = 'Tidak disokong'; return; }
      btn.classList.toggle('is-on', st.connected);
      if (lbl) lbl.textContent = st.connected ? (st.name || 'TERSAMBUNG') : 'PRINTER';
      btn.title = st.connected ? ('Printer: ' + (st.name || '')) : 'Sambung printer';
    });
    btn.addEventListener('click', async () => {
      if (!RmsPrinter.isSupported()) return toast('Web Bluetooth tidak disokong', true);
      if (RmsPrinter.isConnected()) {
        if (confirm('Putus sambungan printer?')) await RmsPrinter.disconnect();
        return;
      }
      try { await RmsPrinter.connect(); toast('Printer tersambung: ' + RmsPrinter.getName()); }
      catch (e) { toast('Gagal sambung: ' + e.message, true); }
    });
  })();

  // ─── Helpers ───
  function toast(msg, isErr) {
    const t = $('bpToast');
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.hidden = true, 2500);
  }

  // ─── Init ───
  renderItems();
  showStep();
})();
