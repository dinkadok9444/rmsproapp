/* Port dari lib/screens/modules/quick_sales_screen.dart — core flow (tanpa print/scan/NFC) */
(function () {
  'use strict';
  if (!document.getElementById('posProducts')) return;

  const PAYMENTS = [
    { key: 'CASH',      icon: 'fa-money-bill',         color: 'green'  },
    { key: 'QR',        icon: 'fa-qrcode',             color: 'cyan'   },
    { key: 'TRANSFER',  icon: 'fa-building-columns',   color: 'yellow' },
    { key: 'PAYWAVE',   icon: 'fa-wifi',               color: 'blue'   },
    { key: 'SPAYLATER', icon: 'fa-clock-rotate-left',  color: 'orange' },
  ];

  let ownerID = 'admin', shopID = 'MAIN';
  let products = []; // merged from 3 sources
  const cart = [];
  let category = 'SEMUA';
  let searchText = '';
  let custType = 'WALK-IN';
  let caraBayaran = 'CASH';
  let staffList = [];
  let staff = '';
  let existingCust = [];
  let isSaving = false;
  let shopInfo = {};
  let lastSale = null;
  let autoPrint = localStorage.getItem('pos_auto_print') !== 'false';
  let autoDrawer = localStorage.getItem('pos_auto_drawer') !== 'false';
  let sales = [];
  let histRange = 'today';
  let histSearch = '';

  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0]; shopID = (p[1] || '').toUpperCase();
  }

  const $ = id => document.getElementById(id);
  const prodEl = $('posProducts'), prodEmpty = $('posProductsEmpty');
  const cartList = $('posCartList'), cartEmpty = $('posCartEmpty');
  const payModal = $('posPayModal'), doneModal = $('posDoneModal');

  $('posShop').textContent = shopID;

  // ───── Load products from 3 sources ─────
  const bySource = { accessories: [], sparepart: [], telefon: [] };

  db.collection('accessories_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = Object.assign({ id: d.id, source: 'accessories', category: 'ACCESSORIES' }, d.data());
      if (Number(v.qty || 0) > 0) arr.push(v);
    });
    bySource.accessories = arr; rebuildProducts();
  }, e => console.warn('accessories:', e));

  db.collection('inventory_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = Object.assign({ id: d.id, source: 'sparepart' }, d.data());
      if (Number(v.qty || 0) > 0) arr.push(v);
    });
    bySource.sparepart = arr; rebuildProducts();
  }, e => console.warn('inventory:', e));

  db.collection('phone_stock_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = Object.assign({ id: d.id, source: 'telefon', category: 'TELEFON' }, d.data());
      if (String(v.shopID || '').toUpperCase() !== shopID) return;
      if (String(v.status || '').toUpperCase() === 'SOLD') return;
      arr.push(v);
    });
    bySource.telefon = arr; rebuildProducts();
  }, e => console.warn('phone_stock:', e));

  function rebuildProducts() {
    products = [].concat(bySource.accessories, bySource.sparepart, bySource.telefon);
    renderCategories();
    renderProducts();
  }

  // ───── Customers (for datalist) ─────
  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const seen = new Set();
    const arr = [];
    snap.forEach(d => {
      const v = d.data();
      if (String(v.shopID || '').toUpperCase() !== shopID) return;
      const tel = String(v.tel || '');
      if (!tel || tel === '-' || seen.has(tel)) return;
      seen.add(tel);
      arr.push({ nama: v.nama || '', tel });
    });
    existingCust = arr;
    const dl = $('posCustList');
    if (dl) dl.innerHTML = arr.slice(0, 50).map(c => `<option value="${escAttr(c.nama)}" label="${escAttr(c.tel)}">`).join('');
  }, e => console.warn('repairs:', e));

  // ───── Shop info + staff ─────
  db.collection('shops_' + ownerID).doc(shopID).get().then(doc => {
    if (!doc.exists) return;
    const data = doc.data() || {};
    const raw = data.staffList;
    if (Array.isArray(raw)) {
      staffList = raw.map(s => typeof s === 'string' ? s : (s.name || s.nama || '')).filter(Boolean);
    }
    staff = staffList[0] || '';
    renderStaff();
    shopInfo = {
      shopName: data.shopName || data.namaKedai || 'RMS PRO',
      address: data.address || data.alamat || '',
      phone: data.phone || data.ownerContact || '-',
      notaInvoice: data.notaInvoice || 'Terima kasih atas sokongan anda.',
    };
  }).catch(() => {});

  // ───── Printer ─────
  const printerBtn = $('posPrinterBtn'), printerLbl = $('posPrinterLbl');
  if (window.RmsPrinter) {
    RmsPrinter.onChange(st => {
      if (!st.supported) {
        printerBtn.classList.add('is-disabled');
        printerLbl.textContent = 'TIDAK DISOKONG';
        printerBtn.title = 'Browser ini tidak sokong Web Bluetooth. Guna Chrome/Edge.';
        return;
      }
      printerBtn.classList.toggle('is-on', st.connected);
      printerLbl.textContent = st.connected ? (st.name || 'TERSAMBUNG') : 'PRINTER';
    });
    printerBtn.addEventListener('click', async () => {
      if (!RmsPrinter.isSupported()) return toast('Web Bluetooth tidak disokong — guna Chrome/Edge', true);
      if (RmsPrinter.isConnected()) {
        if (confirm(`Putus sambungan printer "${RmsPrinter.getName()}"?`)) await RmsPrinter.disconnect();
        return;
      }
      try {
        await RmsPrinter.connect();
        toast('Printer tersambung: ' + RmsPrinter.getName());
      } catch (e) { toast('Gagal sambung: ' + e.message, true); }
    });
  }

  $('posAutoPrint').checked = autoPrint;
  $('posAutoDrawer').checked = autoDrawer;
  $('posAutoPrint').addEventListener('change', e => {
    autoPrint = e.target.checked;
    localStorage.setItem('pos_auto_print', String(autoPrint));
  });
  $('posAutoDrawer').addEventListener('change', e => {
    autoDrawer = e.target.checked;
    localStorage.setItem('pos_auto_drawer', String(autoDrawer));
  });

  // ───── Render: staff dropdown ─────
  function renderStaff() {
    const el = $('posStaff');
    if (!staffList.length) {
      el.innerHTML = '<option value="">(Tiada staff)</option>';
      return;
    }
    el.innerHTML = staffList.map(s => `<option value="${escAttr(s)}" ${s === staff ? 'selected' : ''}>${escHtml(s)}</option>`).join('');
  }
  $('posStaff').addEventListener('change', e => { staff = e.target.value; });

  // ───── Render: categories ─────
  function renderCategories() {
    const cats = ['SEMUA'];
    products.forEach(p => {
      const c = String(p.category || '').toUpperCase();
      if (c && !cats.includes(c)) cats.push(c);
    });
    if (!cats.includes(category)) category = 'SEMUA';
    $('posCats').innerHTML = cats.map(c =>
      `<button type="button" class="pos-cat ${c === category ? 'is-active' : ''}" data-cat="${escAttr(c)}">${escHtml(c)}</button>`
    ).join('');
  }
  $('posCats').addEventListener('click', e => {
    const b = e.target.closest('[data-cat]');
    if (!b) return;
    category = b.dataset.cat;
    renderCategories(); renderProducts();
  });

  // ───── Render: products ─────
  $('posSearch').addEventListener('input', e => { searchText = e.target.value.toLowerCase(); renderProducts(); });

  function filteredProducts() {
    let list = products;
    if (category !== 'SEMUA') {
      list = list.filter(p => String(p.category || '').toUpperCase() === category);
    }
    if (searchText) {
      list = list.filter(p =>
        String(p.nama || '').toLowerCase().includes(searchText) ||
        String(p.kod || '').toLowerCase().includes(searchText)
      );
    }
    return list;
  }

  function renderProducts() {
    const list = filteredProducts();
    if (!list.length) {
      prodEl.innerHTML = '';
      prodEmpty.classList.remove('hidden');
      return;
    }
    prodEmpty.classList.add('hidden');
    prodEl.innerHTML = list.map(p => {
      const nama = p.nama || '-';
      const harga = Number(p.harga || 0).toFixed(2);
      const qty = Number(p.qty || 0);
      const kod = p.kod ? `<div class="pos-prod__kod">${escHtml(p.kod)}</div>` : '';
      const cat = p.category ? `<div class="pos-prod__cat">${escHtml(p.category)}</div>` : '';
      return `
        <button type="button" class="pos-prod" data-src="${escAttr(p.source)}" data-id="${escAttr(p.id)}" title="${escAttr(nama)}">
          ${cat}
          <div class="pos-prod__nama">${escHtml(nama)}</div>
          ${kod}
          <div class="pos-prod__foot">
            <span class="pos-prod__harga">RM ${harga}</span>
            <span class="pos-prod__qty">Stok: ${qty}</span>
          </div>
        </button>
      `;
    }).join('');
  }
  prodEl.addEventListener('click', e => {
    const b = e.target.closest('.pos-prod');
    if (!b) return;
    const p = products.find(x => x.id === b.dataset.id && x.source === b.dataset.src);
    if (p) addToCart(p);
  });

  // ───── Cart ─────
  function cartKey(p) { return `${p.source}::${p.id}`; }

  function addToCart(p) {
    const key = cartKey(p);
    const found = cart.find(c => c._key === key);
    const stock = Number(p.qty || 0);
    if (found) {
      if (found.qty + 1 > stock) return toast('Stok tidak mencukupi', true);
      found.qty += 1;
    } else {
      cart.push({
        _key: key,
        source: p.source, id: p.id, stock,
        nama: p.nama || '-',
        harga: Number(p.harga || 0),
        diskaun: 0,
        qty: 1,
      });
    }
    renderCart();
  }

  function renderCart() {
    const payBtn = $('posPayBtn');
    if (!cart.length) {
      cartList.innerHTML = '';
      cartEmpty.classList.remove('hidden');
      $('posCartTotal').textContent = 'RM 0.00';
      $('posCartCount').textContent = '0';
      payBtn.disabled = true;
      return;
    }
    cartEmpty.classList.add('hidden');
    payBtn.disabled = false;

    cartList.innerHTML = cart.map((c, i) => {
      const sub = ((c.harga - c.diskaun) * c.qty).toFixed(2);
      return `
        <div class="pos-ci" data-i="${i}">
          <div class="pos-ci__top">
            <div class="pos-ci__nama">${escHtml(c.nama)}</div>
            <button type="button" class="pos-ci__del" data-del="${i}" title="Buang"><i class="fas fa-xmark"></i></button>
          </div>
          <div class="pos-ci__row">
            <div class="pos-qty">
              <button type="button" data-dec="${i}">−</button>
              <input type="number" min="1" value="${c.qty}" data-qty="${i}">
              <button type="button" data-inc="${i}">+</button>
            </div>
            <div class="pos-ci__price">
              <label>Harga</label>
              <input type="number" step="0.01" min="0" value="${c.harga.toFixed(2)}" data-harga="${i}">
            </div>
            <div class="pos-ci__price">
              <label>Diskaun</label>
              <input type="number" step="0.01" min="0" value="${c.diskaun.toFixed(2)}" data-disc="${i}">
            </div>
            <div class="pos-ci__sub">RM ${sub}</div>
          </div>
        </div>
      `;
    }).join('');
    updateTotals();
  }

  function updateTotals() {
    const total = cart.reduce((s, c) => s + (c.harga - c.diskaun) * c.qty, 0);
    const count = cart.reduce((s, c) => s + c.qty, 0);
    $('posCartTotal').textContent = 'RM ' + total.toFixed(2);
    $('posCartCount').textContent = String(count);
    $('posPayTotal').textContent = 'RM ' + total.toFixed(2);
  }

  cartList.addEventListener('click', e => {
    const inc = e.target.closest('[data-inc]');
    const dec = e.target.closest('[data-dec]');
    const del = e.target.closest('[data-del]');
    if (inc) {
      const i = +inc.dataset.inc;
      if (cart[i].qty + 1 > cart[i].stock) return toast('Stok tidak mencukupi', true);
      cart[i].qty += 1; renderCart();
    } else if (dec) {
      const i = +dec.dataset.dec;
      if (cart[i].qty > 1) { cart[i].qty -= 1; renderCart(); }
    } else if (del) {
      cart.splice(+del.dataset.del, 1); renderCart();
    }
  });
  cartList.addEventListener('input', e => {
    const q = e.target.dataset.qty, h = e.target.dataset.harga, d = e.target.dataset.disc;
    if (q != null) {
      const i = +q; let v = parseInt(e.target.value, 10) || 1;
      if (v < 1) v = 1;
      if (v > cart[i].stock) { v = cart[i].stock; toast('Stok maks: ' + cart[i].stock, true); }
      cart[i].qty = v; e.target.value = v;
      updateSubtotal(i);
    } else if (h != null) {
      cart[+h].harga = parseFloat(e.target.value) || 0;
      updateSubtotal(+h);
    } else if (d != null) {
      cart[+d].diskaun = parseFloat(e.target.value) || 0;
      updateSubtotal(+d);
    }
  });

  function updateSubtotal(i) {
    const c = cart[i];
    const row = cartList.querySelector(`.pos-ci[data-i="${i}"] .pos-ci__sub`);
    if (row) row.textContent = 'RM ' + ((c.harga - c.diskaun) * c.qty).toFixed(2);
    updateTotals();
  }

  $('posCartClear').addEventListener('click', () => { cart.length = 0; renderCart(); });

  // ───── Payment ─────
  $('posPayBtn').addEventListener('click', openPayment);
  $('posPayClose').addEventListener('click', () => payModal.classList.remove('is-open'));
  payModal.addEventListener('click', e => { if (e.target === payModal) payModal.classList.remove('is-open'); });

  $('posCustType').addEventListener('click', e => {
    const b = e.target.closest('[data-type]');
    if (!b) return;
    custType = b.dataset.type;
    document.querySelectorAll('#posCustType .pos-seg__item').forEach(x => x.classList.toggle('is-active', x === b));
  });

  function openPayment() {
    if (!cart.length) return toast('Cart kosong', true);
    if (!staff) return toast('Sila pilih staff', true);
    custType = 'WALK-IN'; caraBayaran = 'CASH';
    document.querySelectorAll('#posCustType .pos-seg__item').forEach(x => x.classList.toggle('is-active', x.dataset.type === 'WALK-IN'));
    ['posCustName', 'posCustTel', 'posCustAlamat'].forEach(id => $(id).value = '');
    renderPaymentGrid();
    updateTotals();
    payModal.classList.add('is-open');
  }

  function renderPaymentGrid() {
    $('posPayGrid').innerHTML = PAYMENTS.map(p =>
      `<button type="button" class="pos-pay c-${p.color} ${p.key === caraBayaran ? 'is-active' : ''}" data-pay="${p.key}">
        <i class="fas ${p.icon}"></i><span>${p.key}</span>
      </button>`
    ).join('');
  }
  $('posPayGrid').addEventListener('click', e => {
    const b = e.target.closest('[data-pay]');
    if (!b) return;
    caraBayaran = b.dataset.pay;
    renderPaymentGrid();
  });

  $('posCustName').addEventListener('change', e => {
    const match = existingCust.find(c => c.nama === e.target.value);
    if (match && !$('posCustTel').value) $('posCustTel').value = match.tel;
  });

  $('posPayConfirm').addEventListener('click', confirmPayment);

  async function confirmPayment() {
    if (isSaving) return;
    if (!cart.length) return toast('Cart kosong', true);
    if (!staff) return toast('Sila pilih staff', true);

    isSaving = true;
    const btn = $('posPayConfirm');
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> MENYIMPAN...';

    const custName = ($('posCustName').value.trim() || custType).toUpperCase();
    const custTel = $('posCustTel').value.trim() || '-';
    const custAlamat = $('posCustAlamat').value.trim() || '-';
    const now = new Date();
    const ts = now.getTime();
    const siri = String(10000000 + Math.floor(Math.random() * 90000000));

    const items_array = cart.map(c => ({
      nama: String(c.nama).toUpperCase(),
      qty: c.qty,
      harga: c.harga,
    }));
    const itemNames = items_array.map(i => i.nama).join(', ');
    const total = cart.reduce((s, c) => s + (c.harga - c.diskaun) * c.qty, 0);

    const data = {
      siri, receiptNo: siri, shopID,
      nama: custName, pelanggan: custName,
      tel: custTel, telefon: custTel, tel_wasap: custTel, wasap: custTel,
      alamat: custAlamat,
      model: itemNames.length > 50 ? itemNames.slice(0, 50) + '...' : itemNames,
      kerosakan: '-', items_array,
      tarikh: isoLocal(now),
      harga: total.toFixed(2),
      deposit: '0', diskaun: '0', tambahan: '0',
      total: total.toFixed(2), baki: '0',
      voucher_generated: '-', voucher_used: '-', voucher_used_amt: 0,
      payment_status: 'PAID', cara_bayaran: caraBayaran,
      catatan: '-', jenis_servis: 'JUALAN',
      staff_terima: staff, staff_repair: staff, staff_serah: staff,
      password: '-',
      cust_type: custType === 'ONLINE' ? 'ONLINE' : (custName === custType ? custType : 'NEW CUST'),
      status: 'COMPLETED', timestamp: ts,
    };

    try {
      await Promise.all([
        db.collection('jualan_pantas_' + ownerID).doc(siri).set(data),
        db.collection('kewangan_'       + ownerID).doc(siri).set(Object.assign({}, data, { jenis: 'JUALAN PANTAS', amount: total })),
        db.collection('repairs_'        + ownerID).doc(siri).set(data),
      ]);
      lastSale = data;
      payModal.classList.remove('is-open');
      $('posDoneSiri').textContent = '#' + siri;
      $('posDoneAmt').textContent = 'RM ' + total.toFixed(2);
      $('posDoneMethod').textContent = caraBayaran;
      $('posDoneStatus').textContent = '';
      doneModal.classList.add('is-open');
      cart.length = 0;
      renderCart();

      // Auto-print + kick drawer
      if (autoPrint && window.RmsPrinter && RmsPrinter.isConnected()) {
        try {
          $('posDoneStatus').textContent = 'Mencetak resit…';
          await RmsPrinter.printReceipt(data, shopInfo);
          $('posDoneStatus').textContent = '✓ Resit dicetak';
          if (autoDrawer && caraBayaran === 'CASH') {
            try { await RmsPrinter.kickCashDrawer(); } catch (_) {}
          }
        } catch (e) {
          $('posDoneStatus').textContent = '✗ Gagal cetak: ' + e.message;
        }
      } else if (autoPrint) {
        $('posDoneStatus').textContent = '⚠ Printer tidak tersambung';
      }
    } catch (e) {
      toast('Gagal: ' + e.message, true);
    }
    isSaving = false;
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-check"></i> SAHKAN BAYARAN';
  }

  $('posDoneOk').addEventListener('click', () => doneModal.classList.remove('is-open'));
  doneModal.addEventListener('click', e => { if (e.target === doneModal) doneModal.classList.remove('is-open'); });
  // ───── History ─────
  const histModal = $('posHistModal');
  db.collection('jualan_pantas_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v._id = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    arr.sort((a, b) => Number(b.timestamp || 0) - Number(a.timestamp || 0));
    sales = arr;
    if (!histModal.classList.contains('is-open')) return;
    renderHistory();
  }, e => console.warn('jualan_pantas:', e));

  function openHistory() {
    histSearch = ''; histRange = 'today';
    $('posHistSearch').value = '';
    $('posHistRange').value = 'today';
    renderHistory();
    histModal.classList.add('is-open');
  }
  $('posHistoryBtn').addEventListener('click', openHistory);
  $('posHistClose').addEventListener('click', () => histModal.classList.remove('is-open'));
  histModal.addEventListener('click', e => { if (e.target === histModal) histModal.classList.remove('is-open'); });
  $('posHistSearch').addEventListener('input', e => { histSearch = e.target.value.toLowerCase(); renderHistory(); });
  $('posHistRange').addEventListener('change', e => { histRange = e.target.value; renderHistory(); });

  function filterHistory() {
    const now = new Date();
    let cutoff = 0;
    if (histRange === 'today') {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      cutoff = d.getTime();
    } else if (histRange === 'week') cutoff = now.getTime() - 7 * 86400000;
    else if (histRange === 'month') cutoff = now.getTime() - 30 * 86400000;

    let arr = cutoff ? sales.filter(s => Number(s.timestamp || 0) >= cutoff) : sales.slice();
    const q = histSearch.trim();
    if (q) {
      arr = arr.filter(s =>
        String(s.siri || '').toLowerCase().includes(q) ||
        String(s.nama || '').toLowerCase().includes(q) ||
        String(s.tel || '').toLowerCase().includes(q)
      );
    }
    return arr;
  }

  function renderHistory() {
    const arr = filterHistory();
    const total = arr.reduce((s, x) => s + (parseFloat(x.total) || 0), 0);
    $('posHistCount').textContent = arr.length;
    $('posHistTotal').textContent = 'RM ' + total.toFixed(2);
    const listEl = $('posHistList'), emptyEl = $('posHistEmpty');
    if (!arr.length) {
      listEl.innerHTML = '';
      emptyEl.classList.remove('hidden');
      return;
    }
    emptyEl.classList.add('hidden');
    listEl.innerHTML = arr.map(s => {
      const amt = (parseFloat(s.total) || 0).toFixed(2);
      const items = Array.isArray(s.items_array) ? s.items_array.length : 0;
      const method = s.cara_bayaran || '-';
      const methodColor = paymentColor(method);
      return `
        <div class="pos-hist-row" data-siri="${escAttr(s.siri || s._id)}">
          <div class="pos-hist-row__main">
            <div class="pos-hist-row__top">
              <span class="pos-hist-row__siri">#${escHtml(s.siri || '-')}</span>
              <span class="pos-hist-row__method c-${methodColor}">${escHtml(method)}</span>
            </div>
            <div class="pos-hist-row__nama">${escHtml(String(s.nama || '-').toUpperCase())}</div>
            <div class="pos-hist-row__meta">${fmtDateTime(s.timestamp)} &nbsp;•&nbsp; ${items} item${items === 1 ? '' : 's'}</div>
          </div>
          <div class="pos-hist-row__right">
            <div class="pos-hist-row__amt">RM ${amt}</div>
            <button type="button" class="btn-reprint" data-reprint="${escAttr(s.siri || s._id)}" title="Cetak Semula"><i class="fas fa-print"></i></button>
          </div>
        </div>
      `;
    }).join('');
  }

  function paymentColor(m) {
    const u = String(m).toUpperCase();
    if (u === 'CASH') return 'green';
    if (u === 'QR') return 'cyan';
    if (u === 'TRANSFER') return 'yellow';
    if (u === 'PAYWAVE') return 'blue';
    if (u === 'SPAYLATER') return 'orange';
    return 'muted';
  }

  $('posHistList').addEventListener('click', async e => {
    const b = e.target.closest('[data-reprint]');
    if (!b) return;
    const sale = sales.find(x => (x.siri || x._id) === b.dataset.reprint);
    if (!sale) return;
    if (!window.RmsPrinter || !RmsPrinter.isConnected()) return toast('Printer tidak tersambung', true);
    const orig = b.innerHTML;
    b.disabled = true; b.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';
    try {
      await RmsPrinter.printReceipt(sale, shopInfo);
      toast('Resit #' + (sale.siri || sale._id) + ' dicetak semula');
    } catch (err) {
      toast('Gagal cetak: ' + err.message, true);
    }
    b.disabled = false; b.innerHTML = orig;
  });

  function fmtDateTime(ts) {
    if (typeof ts !== 'number') return '-';
    const d = new Date(ts);
    const p = n => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  $('posDoneReprint').addEventListener('click', async () => {
    if (!lastSale) return;
    if (!window.RmsPrinter || !RmsPrinter.isConnected()) return toast('Printer tidak tersambung', true);
    try {
      $('posDoneStatus').textContent = 'Mencetak semula…';
      await RmsPrinter.printReceipt(lastSale, shopInfo);
      $('posDoneStatus').textContent = '✓ Dicetak';
    } catch (e) {
      $('posDoneStatus').textContent = '✗ Gagal: ' + e.message;
    }
  });

  // ───── Helpers ─────
  function isoLocal(d) {
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function toast(msg, isErr) {
    const t = $('posToast');
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.hidden = true, 2500);
  }
  function escHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function escAttr(s) { return escHtml(s); }

  renderCart();
})();
