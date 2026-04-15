/* booking.js — Supabase. Mirror booking_screen.dart (list aktif/arkib/sampah + add + status). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fmtDate = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()}`;
  };
  function toast(msg) {
    const t = $('bkToast'); if (!t) return;
    t.textContent = msg; t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 1800);
  }
  function parseNotes(s) { try { return JSON.parse(s || '{}'); } catch (e) { return {}; } }

  let ALL = [];
  let mode = 'ACTIVE'; // ACTIVE | ARCHIVED | DELETED
  let searchQ = '';
  let sort = 'desc';
  const ownerID = (ctx.email || '').split('@')[0] || 'unknown';
  let currentQrUrl = null;   // branch.extras.bookingQr
  let currentResitUrl = null; // per-booking receipt url

  async function fetchBookings() {
    const { data, error } = await window.sb
      .from('bookings').select('*')
      .eq('branch_id', branchId)
      .order('created_at', { ascending: false })
      .limit(2000);
    if (error) { console.error(error); return []; }
    return data || [];
  }

  function filterByMode(rows) {
    return rows.filter((r) => {
      const st = (r.status || 'PENDING').toUpperCase();
      if (mode === 'DELETED') return st === 'DELETED';
      if (mode === 'ARCHIVED') return st === 'ARCHIVED';
      return st !== 'DELETED' && st !== 'ARCHIVED';
    });
  }

  function refresh() {
    let rows = filterByMode(ALL);
    if (searchQ) {
      const q = searchQ.toLowerCase();
      rows = rows.filter((r) => (r.nama||'').toLowerCase().includes(q) || (r.tel||'').toLowerCase().includes(q) || (r.model||'').toLowerCase().includes(q) || (r.id||'').toLowerCase().includes(q));
    }
    rows.sort((a,b) => {
      if (sort === 'asc') return (a.created_at||'').localeCompare(b.created_at||'');
      if (sort === 'az') return (a.nama||'').localeCompare(b.nama||'');
      if (sort === 'za') return (b.nama||'').localeCompare(a.nama||'');
      return (b.created_at||'').localeCompare(a.created_at||'');
    });
    $('bkEmpty').classList.toggle('hidden', rows.length > 0);
    $('bkList').innerHTML = rows.map((r) => {
      const notes = parseNotes(r.notes);
      const st = (r.status || 'PENDING').toUpperCase();
      return `<div class="bk-card" data-id="${r.id}">
        <div class="bk-card__head">
          <div><b>${r.nama || '—'}</b></div>
          <span class="bk-card__status st-${st}">${st}</span>
        </div>
        <div class="bk-card__body">
          <div><i class="fas fa-phone"></i> ${r.tel || '—'}</div>
          <div><i class="fas fa-mobile"></i> ${r.model || '—'}</div>
          <div><i class="fas fa-wrench"></i> ${r.kerosakan || '—'}</div>
          <div><i class="fas fa-calendar"></i> ${fmtDate(r.created_at)}</div>
          ${notes.harga ? `<div><i class="fas fa-money-bill"></i> ${fmtRM(notes.harga)}</div>` : ''}
        </div>
      </div>`;
    }).join('');
    $('bkList').querySelectorAll('.bk-card').forEach((el) => {
      el.addEventListener('click', () => openDetail(ALL.find((r) => r.id === el.dataset.id)));
    });
  }

  function openDetail(row) {
    if (!row) return;
    const notes = parseNotes(row.notes);
    const st = (row.status || 'PENDING').toUpperCase();
    $('bkDetailTitle').querySelector('span').textContent = row.nama || '—';
    $('bkDetailBody').innerHTML = `
      <div class="bk-field"><label>TELEFON</label><div>${row.tel || '—'}</div></div>
      <div class="bk-field"><label>MODEL / KEROSAKAN</label><div>${row.model || '—'} — ${row.kerosakan || '—'}</div></div>
      <div class="bk-field"><label>HARGA</label><div>${fmtRM(notes.harga)}</div></div>
      <div class="bk-field"><label>DEPOSIT / BAKI</label><div>${fmtRM(notes.deposit)} / ${fmtRM(notes.baki)}</div></div>
      <div class="bk-field"><label>TARIKH CUST</label><div>${notes.tarikh_cust || '—'}</div></div>
      <div class="bk-field"><label>STATUS</label>
        <select id="dStatus" class="bk-input">
          ${['PENDING','CONFIRMED','COMPLETED','ARCHIVED','DELETED'].map((s) => `<option value="${s}"${s===st?' selected':''}>${s}</option>`).join('')}
        </select>
      </div>
      <div class="bk-modal__actions">
        <button class="bk-btn c-primary" id="dPrint"><i class="fas fa-print"></i></button>
        <button class="bk-btn c-whatsapp" id="dPhone"><i class="fas fa-phone"></i></button>
        <button class="bk-btn c-yellow" id="dCourier"><i class="fas fa-truck"></i></button>
        <button class="bk-btn c-blue" id="dImg"><i class="fas fa-image"></i></button>
      </div>
      <div class="bk-modal__actions">
        <button class="btn-submit" id="dSave">SIMPAN</button>
        <button class="btn-danger" id="dDel">PADAM</button>
      </div>`;
    $('bkDetailModal').classList.add('is-open');
    $('dPrint').addEventListener('click', () => openPrintModal(row));
    $('dPhone').addEventListener('click', () => openPhoneModal(row));
    $('dCourier').addEventListener('click', () => { courierTargetId = row.id; renderCourierList(); $('bkCourierModal').classList.add('is-open'); });
    $('dImg').addEventListener('click', () => {
      const n = parseNotes(row.notes);
      openImgViewer([row.qr_url, row.resit_url, n.resit_url, n.qr_url]);
    });
    $('dSave').addEventListener('click', async () => {
      const { error } = await window.sb.from('bookings').update({ status: $('dStatus').value }).eq('id', row.id);
      if (error) { toast('Gagal: ' + error.message); return; }
      toast('Disimpan');
      $('bkDetailModal').classList.remove('is-open');
      ALL = await fetchBookings(); refresh();
    });
    $('dDel').addEventListener('click', async () => {
      if (!confirm('Padam booking?')) return;
      const { error } = await window.sb.from('bookings').update({ status: 'DELETED' }).eq('id', row.id);
      if (error) { toast('Gagal: ' + error.message); return; }
      toast('Dipadam');
      $('bkDetailModal').classList.remove('is-open');
      ALL = await fetchBookings(); refresh();
    });
  }

  // Tabs
  document.querySelectorAll('#bkTabs .bk-tab').forEach((t) => {
    t.addEventListener('click', () => {
      document.querySelectorAll('#bkTabs .bk-tab').forEach((x) => x.classList.remove('is-active'));
      t.classList.add('is-active');
      mode = t.dataset.mode;
      refresh();
    });
  });

  $('bkSearch').addEventListener('input', (e) => { searchQ = e.target.value; refresh(); });
  $('bkSort').addEventListener('change', (e) => { sort = e.target.value; refresh(); });

  // Close handlers
  document.querySelectorAll('[data-close]').forEach((b) => {
    b.addEventListener('click', () => {
      const id = b.dataset.close;
      if (id) $(id).classList.remove('is-open');
    });
  });

  // Add modal
  $('bkNewBtn').addEventListener('click', () => {
    ['bkNama','bkTel','bkItem','bkTarikhCust'].forEach((k) => { if ($(k)) $(k).value = ''; });
    ['bkHarga','bkDeposit','bkBaki'].forEach((k) => { if ($(k)) $(k).value = '0'; });
    currentResitUrl = null;
    const box = $('bkAddResitBox');
    if (box) {
      const empty = box.querySelector('.bk-upload__empty');
      const preview = box.querySelector('.bk-upload__preview');
      if (empty) empty.classList.remove('hidden');
      if (preview) preview.classList.add('hidden');
    }
    $('bkAddModal').classList.add('is-open');
  });

  function recalcBaki() {
    const h = Number($('bkHarga').value) || 0;
    const d = Number($('bkDeposit').value) || 0;
    $('bkBaki').value = Math.max(0, h - d).toFixed(2);
  }
  $('bkHarga').addEventListener('input', recalcBaki);
  $('bkDeposit').addEventListener('input', recalcBaki);

  $('bkAddSave').addEventListener('click', async () => {
    const nama = $('bkNama').value.trim();
    const tel = $('bkTel').value.trim();
    const item = $('bkItem').value.trim();
    if (!nama || !tel || !item) { toast('Nama, tel, item wajib'); return; }
    const harga = Number($('bkHarga').value) || 0;
    const deposit = Number($('bkDeposit').value) || 0;
    const notes = {
      harga, deposit, baki: Math.max(0, harga - deposit),
      tarikh_cust: $('bkTarikhCust').value || null,
      resit_url: currentResitUrl || null,
    };
    // split item into model + kerosakan (first part before "-")
    let model = item, kerosakan = '';
    const dash = item.indexOf('-');
    if (dash > 0) { model = item.slice(0, dash).trim(); kerosakan = item.slice(dash + 1).trim(); }

    const { error } = await window.sb.from('bookings').insert({
      tenant_id: ctx.tenant_id,
      branch_id: branchId,
      nama, tel, model, kerosakan,
      status: 'PENDING',
      notes: JSON.stringify(notes),
    });
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Booking disimpan');
    $('bkAddModal').classList.remove('is-open');
    ALL = await fetchBookings(); refresh();
  });

  // ── Branch QR load/upload ────────────────────────────────
  let branchRow = null;
  async function loadBranchQr() {
    const { data } = await window.sb.from('branches').select('*').eq('id', branchId).single();
    branchRow = data || {};
    const extras = (branchRow.extras && typeof branchRow.extras === 'object') ? branchRow.extras : {};
    currentQrUrl = extras.bookingQr || null;
    renderQrPreview();
    renderPayInfo();
    if (extras.bank_type) $('bkBankType').value = extras.bank_type;
    if (extras.bank_name) $('bkBankName').value = extras.bank_name;
    if (extras.bank_acc) $('bkBankAcc').value = extras.bank_acc;
  }
  function renderQrPreview() {
    const box = $('bkQrBox'); if (!box) return;
    const empty = box.querySelector('.bk-upload__empty');
    const preview = box.querySelector('.bk-upload__preview');
    const img = preview && preview.querySelector('img');
    if (currentQrUrl) {
      if (empty) empty.classList.add('hidden');
      if (preview) preview.classList.remove('hidden');
      if (img) img.src = currentQrUrl;
      if ($('bkQrDel')) $('bkQrDel').classList.remove('hidden');
    } else {
      if (empty) empty.classList.remove('hidden');
      if (preview) preview.classList.add('hidden');
      if ($('bkQrDel')) $('bkQrDel').classList.add('hidden');
    }
  }
  function renderPayInfo() {
    const box = $('bkAddPayInfo'); if (!box) return;
    const extras = (branchRow && branchRow.extras) || {};
    if (!currentQrUrl && !extras.bank_type) {
      box.innerHTML = '<div class="bk-paybox__empty">Belum ditetapkan — Sila set di ikon gear (⚙)</div>';
      return;
    }
    box.innerHTML = `
      ${currentQrUrl ? `<img src="${currentQrUrl}" style="max-width:120px;border-radius:8px;">` : ''}
      ${extras.bank_type ? `<div><b>${extras.bank_type}</b></div>` : ''}
      ${extras.bank_name ? `<div>${extras.bank_name}</div>` : ''}
      ${extras.bank_acc ? `<div>${extras.bank_acc}</div>` : ''}`;
  }

  // QR upload via hidden input click (input sits inside label#bkQrBox — triggers natively).
  // Override: intercept change to use Storage instead of raw file.
  const qrInput = $('bkQrFile');
  if (qrInput) qrInput.addEventListener('change', async (e) => {
    e.preventDefault();
    const f = qrInput.files && qrInput.files[0];
    if (!f) return;
    if (!window.SupabaseStorage) { toast('Storage helper missing'); return; }
    const shopCode = (branchRow && (branchRow.shop_code || branchRow.id)) || 'shop';
    const box = $('bkQrBox');
    const empty = box.querySelector('.bk-upload__empty');
    if (empty) empty.innerHTML = '<span>UPLOADING...</span>';
    try {
      const blob = await window.SupabaseStorage.resizeImage(f, 1280, 0.85);
      const path = `${ownerID}/${shopCode}/qr_${Date.now()}.jpg`;
      const url = await window.SupabaseStorage.uploadFile({ bucket: 'booking_settings', path, file: blob, contentType: 'image/jpeg' });
      currentQrUrl = url;
      renderQrPreview();
    } catch (err) {
      toast('Upload gagal: ' + err.message);
    } finally {
      qrInput.value = '';
      if (empty) empty.innerHTML = '<i class="fas fa-cloud-arrow-up"></i><span>Upload Gambar QR</span>';
    }
  });
  if ($('bkQrDel')) $('bkQrDel').addEventListener('click', () => {
    currentQrUrl = null;
    renderQrPreview();
  });

  // Receipt upload for add modal
  const resitInput = $('bkAddResit');
  if (resitInput) resitInput.addEventListener('change', async (e) => {
    const f = resitInput.files && resitInput.files[0];
    if (!f) return;
    if (!window.SupabaseStorage) { toast('Storage helper missing'); return; }
    const box = $('bkAddResitBox');
    const empty = box && box.querySelector('.bk-upload__empty');
    const preview = box && box.querySelector('.bk-upload__preview');
    const img = preview && preview.querySelector('img');
    if (empty) empty.innerHTML = '<span>UPLOADING...</span>';
    try {
      const blob = await window.SupabaseStorage.resizeImage(f, 1280, 0.85);
      const path = `${ownerID}/receipts/${Date.now()}.jpg`;
      const url = await window.SupabaseStorage.uploadFile({ bucket: 'booking_settings', path, file: blob, contentType: 'image/jpeg' });
      currentResitUrl = url;
      if (empty) empty.classList.add('hidden');
      if (preview) { preview.classList.remove('hidden'); if (img) img.src = url; }
    } catch (err) {
      toast('Upload gagal: ' + err.message);
    } finally {
      resitInput.value = '';
      if (empty) empty.innerHTML = '<i class="fas fa-cloud-arrow-up"></i><span>Tekan untuk upload resit</span>';
    }
  });

  // ── Courier list (stored in branch.extras.courierList) ──────────
  const DEFAULT_COURIERS = ['J&T EXPRESS', 'POSLAJU', 'NINJAVAN', 'LALAMOVE', 'DHL', 'SKYNET', 'POS EKSPRES'];
  function getCourierList() {
    const extras = (branchRow && branchRow.extras && typeof branchRow.extras === 'object') ? branchRow.extras : {};
    const list = Array.isArray(extras.courierList) ? extras.courierList.slice() : DEFAULT_COURIERS.slice();
    return list;
  }
  async function saveCourierList(list) {
    const extras = (branchRow && branchRow.extras && typeof branchRow.extras === 'object') ? { ...branchRow.extras } : {};
    extras.courierList = list;
    const { error } = await window.sb.from('branches').update({ extras }).eq('id', branchId);
    if (error) throw error;
    if (branchRow) branchRow.extras = extras;
  }
  function renderCourierList() {
    const wrap = $('bkCourierList'); if (!wrap) return;
    const list = getCourierList();
    wrap.innerHTML = list.map((k, i) => `
      <div class="bk-courier-row">
        <span class="bk-courier-name" data-pick="${i}">${k}</span>
        <button type="button" class="bk-hbtn c-red bk-courier-del" data-del="${i}"><i class="fas fa-trash"></i></button>
      </div>`).join('') || '<div class="bk-empty-mini">Tiada kurier</div>';
    wrap.querySelectorAll('[data-pick]').forEach((el) => {
      el.addEventListener('click', () => {
        const idx = Number(el.dataset.pick);
        const name = getCourierList()[idx];
        if (!name) return;
        pickCourierForCurrent(name);
      });
    });
    wrap.querySelectorAll('[data-del]').forEach((el) => {
      el.addEventListener('click', async () => {
        const idx = Number(el.dataset.del);
        const list = getCourierList();
        list.splice(idx, 1);
        try { await saveCourierList(list); renderCourierList(); } catch (e) { toast('Gagal: ' + e.message); }
      });
    });
  }
  let courierTargetId = null; // booking row id to apply courier to (optional)
  function pickCourierForCurrent(name) {
    if (!courierTargetId) { toast('Kurier dipilih: ' + name); $('bkCourierModal').classList.remove('is-open'); return; }
    const row = ALL.find((r) => r.id === courierTargetId);
    if (!row) return;
    const notes = parseNotes(row.notes);
    notes.courier = name;
    // optional tracking URL template per courier
    const trackMap = {
      'J&T EXPRESS': 'https://www.jtexpress.my/index/query/gzquery.html',
      'POSLAJU': 'https://www.pos.com.my/postal-services/quick-access/?track-trace',
      'NINJAVAN': 'https://www.ninjavan.co/en-my/tracking',
      'LALAMOVE': 'https://www.lalamove.com/en-my/',
      'DHL': 'https://www.dhl.com/my-en/home/tracking.html',
      'SKYNET': 'https://www.skynet.com.my/tracking',
      'POS EKSPRES': 'https://www.pos.com.my/postal-services/quick-access/?track-trace',
    };
    notes.courier_track = trackMap[name] || null;
    window.sb.from('bookings').update({ notes: JSON.stringify(notes) }).eq('id', row.id).then(({ error }) => {
      if (error) { toast('Gagal: ' + error.message); return; }
      toast('Kurier: ' + name);
      $('bkCourierModal').classList.remove('is-open');
      fetchBookings().then((d) => { ALL = d; refresh(); });
    });
  }
  $('bkAddCourier') && $('bkAddCourier').addEventListener('click', async () => {
    const inp = $('bkNewCourier'); if (!inp) return;
    const v = (inp.value || '').trim().toUpperCase();
    if (!v) return;
    const list = getCourierList();
    if (list.includes(v)) { toast('Sudah wujud'); return; }
    list.push(v);
    try { await saveCourierList(list); inp.value = ''; renderCourierList(); } catch (e) { toast('Gagal: ' + e.message); }
  });

  // ── Print modal ─────────────────────────────────────────────
  function bookingToJob(row) {
    const notes = parseNotes(row.notes);
    const items = Array.isArray(notes.items) && notes.items.length
      ? notes.items
      : [{ nama: [row.model, row.kerosakan].filter(Boolean).join(' - ') || '-', qty: 1, harga: Number(notes.harga) || 0 }];
    const total = Number(notes.harga) || items.reduce((s, x) => s + (Number(x.harga) || 0) * (Number(x.qty) || 1), 0);
    return {
      siri: row.id ? ('BK-' + String(row.id).slice(0, 8).toUpperCase()) : '-',
      nama: row.nama || '-',
      tel: row.tel || '-',
      model: row.model || '-',
      kerosakan: row.kerosakan || '-',
      tarikh: row.created_at,
      items_array: items,
      harga: total,
      total: total,
      payment_status: (Number(notes.deposit) || 0) > 0 ? 'PAID' : 'UNPAID',
    };
  }
  function openPrintModal(row) {
    if (!row) return;
    const job = bookingToJob(row);
    $('bkPrintSiri').textContent = '#' + job.siri;
    const P = window.RmsPrinter;
    const connected = P && P.isConnected && P.isConnected();
    const body = $('bkPrintBody');
    body.innerHTML = `
      <button type="button" class="bk-btn c-blue" id="bkPrintReceipt">
        <i class="fas fa-receipt"></i> RESIT 80MM
        <small style="display:block;opacity:.7;font-size:9px;">${connected ? 'Printer tersambung' : 'Printer tidak disambung'}</small>
      </button>`;
    $('bkPrintModal').classList.add('is-open');
    $('bkPrintReceipt').addEventListener('click', async () => {
      if (!P || !P.isConnected || !P.isConnected()) { toast('Printer tidak disambung'); return; }
      const shop = {
        shopName: (branchRow && (branchRow.name || branchRow.shop_name)) || 'RMS PRO',
        address: (branchRow && branchRow.address) || '',
        phone: (branchRow && branchRow.phone) || '',
      };
      try { await P.printReceipt(job, shop); toast('Cetak dihantar'); $('bkPrintModal').classList.remove('is-open'); }
      catch (e) { toast('Gagal cetak: ' + e.message); }
    });
  }

  // ── Phone modal ─────────────────────────────────────────────
  function openPhoneModal(row) {
    if (!row) return;
    const tel = (row.tel || '').toString();
    if (!tel) { toast('Tiada nombor'); return; }
    let wa = tel.replace(/[^0-9]/g, '');
    if (wa.startsWith('0')) wa = '6' + wa;
    $('bkPhoneText').innerHTML = '<i class="fas fa-phone"></i> ' + tel;
    $('bkPhoneModal').classList.add('is-open');
    const call = $('bkPhoneCall');
    const waBtn = $('bkPhoneWa');
    call.onclick = () => { window.location.href = 'tel:' + tel.replace(/\s+/g, ''); };
    waBtn.onclick = () => {
      const notes = parseNotes(row.notes);
      const harga = (Number(notes.harga) || 0).toFixed(2);
      const deposit = (Number(notes.deposit) || 0).toFixed(2);
      const baki = (Number(notes.baki) || 0).toFixed(2);
      const siri = row.id ? ('BK-' + String(row.id).slice(0, 8).toUpperCase()) : '-';
      const msg = `Salam ${row.nama || ''},\n\n*No Tempahan:* ${siri}\n*Item:* ${row.model || '-'} ${row.kerosakan ? '- ' + row.kerosakan : ''}\n*Harga:* RM${harga}\n*Deposit:* RM${deposit}\n*Baki:* RM${baki}\n\nTerima Kasih.`;
      window.open('https://wa.me/' + wa + '?text=' + encodeURIComponent(msg), '_blank');
    };
  }

  // ── Image viewer ────────────────────────────────────────────
  function openImgViewer(urls) {
    const arr = (Array.isArray(urls) ? urls : [urls]).filter(Boolean);
    if (!arr.length) { toast('Tiada imej'); return; }
    const v = $('bkImgViewer');
    const img = v.querySelector('img');
    let idx = 0;
    const render = () => { img.src = arr[idx]; };
    render();
    v.classList.remove('hidden');
    v.onclick = (e) => {
      // click right half = next, left half = prev, outside image = close
      if (e.target === img) {
        const rect = img.getBoundingClientRect();
        if (e.clientX - rect.left > rect.width / 2) idx = (idx + 1) % arr.length;
        else idx = (idx - 1 + arr.length) % arr.length;
        render();
      } else {
        v.classList.add('hidden');
      }
    };
  }

  // expose for inline handlers
  window.bkOpenPhone = (id) => openPhoneModal(ALL.find((r) => r.id === id));
  window.bkOpenPrint = (id) => openPrintModal(ALL.find((r) => r.id === id));
  window.bkOpenImg = (id) => {
    const r = ALL.find((x) => x.id === id); if (!r) return;
    const notes = parseNotes(r.notes);
    openImgViewer([r.qr_url, r.resit_url, notes.resit_url, notes.qr_url]);
  };
  window.bkOpenCourier = (id) => {
    courierTargetId = id || null;
    renderCourierList();
    $('bkCourierModal').classList.add('is-open');
  };

  // Gear/courier buttons
  $('bkGearBtn').addEventListener('click', () => { $('bkGearModal').classList.add('is-open'); });
  $('bkCourierBtn') && $('bkCourierBtn').addEventListener('click', () => { courierTargetId = null; renderCourierList(); $('bkCourierModal').classList.add('is-open'); });
  $('bkGearSave') && $('bkGearSave').addEventListener('click', async () => {
    try {
      const extras = (branchRow && branchRow.extras && typeof branchRow.extras === 'object') ? { ...branchRow.extras } : {};
      extras.bookingQr = currentQrUrl || null;
      extras.bank_type = $('bkBankType').value.trim();
      extras.bank_name = $('bkBankName').value.trim();
      extras.bank_acc = $('bkBankAcc').value.trim();
      const { error } = await window.sb.from('branches').update({ extras }).eq('id', branchId);
      if (error) throw error;
      if (branchRow) branchRow.extras = extras;
      renderPayInfo();
      toast('Tetapan disimpan');
      $('bkGearModal').classList.remove('is-open');
    } catch (e) {
      toast('Gagal: ' + (e.message || e));
    }
  });

  window.sb.channel('bookings-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'bookings', filter: `branch_id=eq.${branchId}` }, async () => { ALL = await fetchBookings(); refresh(); })
    .subscribe();

  ALL = await fetchBookings();
  refresh();
  await loadBranchQr();
})();
