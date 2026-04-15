/* pos.js — Supabase. Mirror quick_sales_screen.dart (products grid → cart → checkout + history). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const toast = (msg) => {
    const t = $('posToast'); if (!t) return;
    t.textContent = msg; t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 2000);
  };

  let PRODUCTS = []; // {id, source, sku, name, price, qty, category}
  let cart = {}; // id -> { prod, qty }
  let activeCat = 'SEMUA';
  let searchQ = '';
  let payMethod = 'CASH';
  let custType = 'WALK-IN';
  let voucher = null; // { id, code, amount }

  async function fetchProducts() {
    const [{ data: parts }, { data: acc }] = await Promise.all([
      window.sb.from('stock_parts').select('*').eq('branch_id', branchId).limit(2000),
      window.sb.from('accessories').select('*').eq('branch_id', branchId).limit(2000),
    ]);
    const out = [];
    (parts || []).filter((r) => (r.category || '').trim().toUpperCase() === 'FAST SERVICE').forEach((r) => out.push({
      id: 'P:' + r.id, _id: r.id, source: 'stock_parts',
      sku: r.sku || '', name: r.part_name || r.sku || '—',
      price: Number(r.price) || 0, qty: Number(r.qty) || 0,
      category: 'FAST SERVICE',
    }));
    (acc || []).forEach((r) => out.push({
      id: 'A:' + r.id, _id: r.id, source: 'accessories',
      sku: r.sku || '', name: r.item_name || r.sku || '—',
      price: Number(r.price) || 0, qty: Number(r.qty) || 0,
      category: 'ACCESSORIES',
    }));
    PRODUCTS = out;
  }

  function renderCats() {
    const cats = ['SEMUA', 'FAST SERVICE', 'ACCESSORIES'];
    $('posCats').innerHTML = cats.map((c) => `<button class="pos-cat${c === activeCat ? ' is-active' : ''}" data-c="${c}">${c}</button>`).join('');
    $('posCats').querySelectorAll('.pos-cat').forEach((b) => {
      b.addEventListener('click', () => { activeCat = b.dataset.c; renderCats(); renderProducts(); });
    });
  }

  function renderProducts() {
    const q = searchQ.toLowerCase();
    const rows = PRODUCTS.filter((p) => {
      if (activeCat !== 'SEMUA' && p.category !== activeCat) return false;
      if (q && !(p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q))) return false;
      return true;
    });
    if (!rows.length) { $('posProducts').innerHTML = ''; $('posProductsEmpty').classList.remove('hidden'); return; }
    $('posProductsEmpty').classList.add('hidden');
    $('posProducts').innerHTML = rows.map((p) => `
      <div class="pos-prod" data-id="${p.id}">
        ${p.category ? `<span class="pos-prod__cat">${p.category}</span>` : ''}
        <div class="pos-prod__nama">${p.name}</div>
        <div class="pos-prod__kod">${p.sku || ''}</div>
        <div class="pos-prod__foot">
          <span class="pos-prod__harga">${fmtRM(p.price)}</span>
          <span class="pos-prod__qty">${p.category === 'FAST SERVICE' ? ('Guna: ' + (Number(p.qty) || 0)) : ('Stok: ' + p.qty)}</span>
        </div>
      </div>`).join('');
    $('posProducts').querySelectorAll('.pos-prod').forEach((el) => {
      el.addEventListener('click', () => addToCart(el.dataset.id));
    });
  }

  function addToCart(id) {
    if (!$('posStaff').value) { toast('Pilih staff dahulu!'); $('posStaff').focus(); return; }
    const p = PRODUCTS.find((x) => x.id === id);
    if (!p) return;
    if (!cart[id]) cart[id] = { prod: p, qty: 0 };
    cart[id].qty++;
    renderCart();
  }

  function renderCart() {
    const list = Object.values(cart);
    $('posCartCount').textContent = list.reduce((s, x) => s + x.qty, 0);
    const total = list.reduce((s, x) => s + x.qty * x.prod.price, 0);
    $('posCartTotal').textContent = fmtRM(total);
    const disc = Number($('posDiskaun') && $('posDiskaun').value || 0);
    const vAmt = voucher ? Math.min(Number(voucher.amount || 0), Math.max(0, total - disc)) : 0;
    const tax = $('posTaxEnable') && $('posTaxEnable').checked ? Number($('posTaxPct').value || 0) : 0;
    const taxAmt = Math.max(0, total - disc - vAmt) * (tax / 100);
    const net = Math.max(0, total - disc - vAmt + taxAmt);
    if ($('posPayTotalInput')) $('posPayTotalInput').value = net.toFixed(2);
    if ($('posBaki')) { const paid = Number($('posBayaran').value) || 0; $('posBaki').textContent = fmtRM(paid - net); $('posBakiRow').querySelector('span').textContent = 'BAKI'; }
    $('posPayBtn').disabled = !list.length;
    $('posCartEmpty').classList.toggle('hidden', list.length > 0);
    $('posCartList').innerHTML = list.map((x) => `
      <div class="pos-cart__item" data-id="${x.prod.id}">
        <div class="pos-cart__nameRow">
          <span class="pos-cart__name">${x.prod.name}</span>
          <span class="pos-cart__amt">${fmtRM(x.qty * x.prod.price)}</span>
        </div>
        <div class="pos-cart__row">
          <button class="pos-cart__btn" data-act="-">−</button>
          <span class="pos-cart__q">${x.qty}</span>
          <button class="pos-cart__btn" data-act="+">+</button>
          <button class="pos-cart__btn pos-cart__del" data-act="x"><i class="fas fa-trash"></i></button>
        </div>
      </div>`).join('');
    $('posCartList').querySelectorAll('[data-act]').forEach((b) => {
      b.addEventListener('click', () => {
        const id = b.closest('[data-id]').dataset.id;
        const c = cart[id]; if (!c) return;
        if (b.dataset.act === '+') {
          if (c.qty + 1 > c.prod.qty) { toast('Stok tak cukup'); return; }
          c.qty++;
        } else if (b.dataset.act === '-') {
          c.qty--; if (c.qty <= 0) delete cart[id];
        } else {
          delete cart[id];
        }
        renderCart();
      });
    });
  }

  $('posCartClear').addEventListener('click', () => { cart = {}; renderCart(); });
  $('posSearch').addEventListener('input', (e) => { searchQ = e.target.value; renderProducts(); });

  // --- Payment modal
  const PAY_METHODS = [
    { k: 'CASH', i: 'fa-money-bill', c: 'c-green' },
    { k: 'QR', i: 'fa-qrcode', c: 'c-cyan' },
    { k: 'ONLINE', i: 'fa-globe', c: 'c-blue' },
    { k: 'CARD', i: 'fa-credit-card', c: 'c-orange' },
  ];
  function renderPayGrid() {
    $('posPayGrid').innerHTML = PAY_METHODS.map((m) => `<button type="button" class="pos-pay ${m.c}${m.k === payMethod ? ' is-active' : ''}" data-k="${m.k}"><i class="fas ${m.i}"></i> ${m.k}</button>`).join('');
    $('posPayGrid').querySelectorAll('[data-k]').forEach((b) => {
      b.addEventListener('click', () => { payMethod = b.dataset.k; renderPayGrid(); });
    });
  }
  renderPayGrid();

  document.querySelectorAll('#posCustType .pos-seg__item').forEach((b) => {
    b.addEventListener('click', () => {
      document.querySelectorAll('#posCustType .pos-seg__item').forEach((x) => x.classList.remove('is-active'));
      b.classList.add('is-active');
      custType = b.dataset.type;
    });
  });

  $('posPayBtn').addEventListener('click', () => { renderCart(); $('posPayModal').classList.add('is-open'); });
  $('posPayClose').addEventListener('click', () => { $('posPayModal').classList.remove('is-open'); });
  $('posCustToggleBtn').addEventListener('click', () => {
    $('posCustFields').classList.toggle('hidden');
    $('posCustToggleBtn').classList.toggle('is-on');
  });
  $('posVoucherBtn').addEventListener('click', () => {
    $('posVoucherWrap').classList.toggle('hidden');
    $('posVoucherBtn').classList.toggle('is-on');
    if (!$('posVoucherWrap').classList.contains('hidden')) $('posVoucherCode').focus();
  });
  $('posDiskaunBtn').addEventListener('click', () => {
    $('posDiskaunWrap').classList.toggle('hidden');
    $('posDiskaunBtn').classList.toggle('is-on');
    if (!$('posDiskaunWrap').classList.contains('hidden')) $('posDiskaun').focus();
  });
  $('posVoucherApply').addEventListener('click', async () => {
    const code = ($('posVoucherCode').value || '').trim().toUpperCase();
    const msg = $('posVoucherMsg');
    const fail = (t) => { msg.style.color = '#dc2626'; msg.textContent = t; voucher = null; renderCart(); };
    if (!code) return fail('Masukkan kod voucher');
    const { data } = await window.sb
      .from('shop_vouchers')
      .select('id, voucher_code, allocated_amount, used_amount, remaining, expiry_date')
      .eq('tenant_id', ctx.tenant_id)
      .eq('voucher_code', code)
      .maybeSingle();
    if (!data) return fail('Kod tidak sah');
    if (data.expiry_date && new Date(data.expiry_date) < new Date()) return fail('Voucher dah expired');
    const remaining = Number(data.remaining ?? (data.allocated_amount - data.used_amount));
    if (remaining <= 0) return fail('Voucher dah habis pakai');
    voucher = { id: data.id, code: data.voucher_code, amount: remaining };
    msg.style.color = '#10b981';
    msg.textContent = `OK — potongan ${fmtRM(remaining)}`;
    renderCart();
  });
  $('posVoucherReset').addEventListener('click', () => {
    voucher = null; $('posVoucherCode').value = '';
    $('posVoucherMsg').textContent = '—'; $('posVoucherMsg').style.color = '#64748b';
    renderCart();
  });
  $('posDiskaun').addEventListener('input', () => renderCart());
  function recalcBaki() {
    const due = Number($('posPayTotalInput').value) || 0;
    const paid = Number($('posBayaran').value) || 0;
    $('posBaki').textContent = fmtRM(paid - due);
    $('posBakiRow').querySelector('span').textContent = 'BAKI';
  }
  $('posBayaran').addEventListener('input', recalcBaki);
  $('posPayTotalInput').addEventListener('input', recalcBaki);

  let lastSale = null;
  $('posPayConfirm').addEventListener('click', async () => {
    const list = Object.values(cart);
    if (!list.length) return;
    const subtotal = list.reduce((s, x) => s + x.qty * x.prod.price, 0);
    const diskaun = Number($('posDiskaun').value) || 0;
    const vAmt = voucher ? Math.min(Number(voucher.amount || 0), Math.max(0, subtotal - diskaun)) : 0;
    const tax = $('posTaxEnable') && $('posTaxEnable').checked ? Number($('posTaxPct').value || 0) : 0;
    const taxAmt = Math.max(0, subtotal - diskaun - vAmt) * (tax / 100);
    const edited = Number($('posPayTotalInput').value);
    const computed = Math.max(0, subtotal - diskaun - vAmt + taxAmt);
    const total = Number.isFinite(edited) && edited >= 0 ? edited : computed;
    const siri = 'S' + Date.now().toString(36).toUpperCase();

    const desc = {
      siri,
      cust_type: custType,
      customer_name: $('posCustName').value.trim() || null,
      customer_tel: $('posCustTel').value.trim() || null,
      customer_alamat: $('posCustAlamat').value.trim() || null,
      subtotal: Number(subtotal.toFixed(2)),
      diskaun,
      voucher_code: voucher ? voucher.code : null,
      voucher_amt: Number(vAmt.toFixed(2)),
      tax_pct: tax,
      tax_amt: Number(taxAmt.toFixed(2)),
      items: list.map((x) => ({ id: x.prod._id, source: x.prod.source, name: x.prod.name, sku: x.prod.sku, qty: x.qty, price: x.prod.price })),
    };

    const { data, error } = await window.sb.from('quick_sales').insert({
      tenant_id: ctx.tenant_id,
      branch_id: branchId,
      kind: 'SALE',
      description: JSON.stringify(desc),
      amount: Number(total.toFixed(2)),
      sold_by: $('posStaff').value || ctx.nama,
      sold_at: new Date().toISOString(),
      payment_method: payMethod,
    }).select().single();
    if (error) { toast('Gagal: ' + error.message); return; }

    // Customer upsert (mirror create_job — dedup by tenant_id,tel)
    try {
      const tel = (desc.customer_tel || '').trim();
      if (tel) {
        await window.sb.from('customers').upsert({
          tenant_id: ctx.tenant_id,
          tel,
          nama: (desc.customer_name || '').trim(),
          last_visit_at: new Date().toISOString(),
        }, { onConflict: 'tenant_id,tel' });
      }
    } catch (_) {}

    // Bump voucher used_amount
    if (voucher && vAmt > 0) {
      const { data: vRow } = await window.sb.from('shop_vouchers').select('used_amount').eq('id', voucher.id).single();
      const newUsed = Number((Number(vRow && vRow.used_amount || 0) + vAmt).toFixed(2));
      await window.sb.from('shop_vouchers').update({ used_amount: newUsed }).eq('id', voucher.id);
    }

    // Decrement stock (FAST SERVICE: count usage instead)
    for (const x of list) {
      if (x.prod.category === 'FAST SERVICE') {
        const used = (Number(x.prod.qty) || 0) + x.qty;
        await window.sb.from(x.prod.source).update({ qty: used, status: 'AVAILABLE' }).eq('id', x.prod._id);
        continue;
      }
      const newQty = Math.max(0, x.prod.qty - x.qty);
      const newStatus = (x.prod.source === 'stock_parts' && newQty === 0) ? 'OUT_OF_STOCK' : undefined;
      const patch = { qty: newQty };
      if (newStatus) patch.status = newStatus;
      await window.sb.from(x.prod.source).update(patch).eq('id', x.prod._id);
    }

    lastSale = { siri, total, method: payMethod, row: data };
    $('posDoneSiri').textContent = '#' + siri;
    $('posDoneAmt').textContent = fmtRM(total);
    $('posDoneMethod').textContent = payMethod;
    $('posDoneStatus').textContent = 'Rekod #' + (data && data.id ? data.id.slice(0, 8) : '');
    $('posPayModal').classList.remove('is-open');
    $('posDoneModal').classList.add('is-open');

    // Auto-print + drawer
    const P = window.RmsPrinter;
    if ($('posAutoPrint').checked && P && P.isConnected && P.isConnected()) {
      doPrint(lastSale).catch(() => {});
    }
    if (payMethod === 'CASH' && P && P.isConnected && P.isConnected()) {
      P.kickCashDrawer().catch(() => {});
    }

    cart = {};
    renderCart();
    await fetchProducts();
    renderCats();
    renderProducts();
    loadCustomerList().catch(() => {});
  });

  $('posDoneOk').addEventListener('click', () => { $('posDoneModal').classList.remove('is-open'); });

  async function doPrint(sale) {
    if (!sale) return;
    const P = window.RmsPrinter;
    if (!P || !P.isConnected || !P.isConnected()) { toast('Printer tidak disambung'); return; }
    const shop = {
      shopName: (branchRow && (branchRow.nama_kedai || branchRow.name)) || $('posShop').textContent || 'RMS PRO',
      address: (branchRow && branchRow.alamat) || '',
      phone: (branchRow && branchRow.phone) || '',
      email: (branchRow && branchRow.email) || '',
      notaInvoice: ($('posFooterNote') && $('posFooterNote').value.trim()) || undefined,
    };
    const job = {
      siri: sale.siri,
      nama: (sale.row && JSON.parse(sale.row.description || '{}').customer_name) || 'Walk-in',
      tel: (sale.row && JSON.parse(sale.row.description || '{}').customer_tel) || '-',
      model: '-',
      tarikh: sale.row && sale.row.sold_at,
      items_array: (JSON.parse(sale.row.description || '{}').items || []).map((x) => ({ nama: x.name, qty: x.qty, harga: x.price })),
    };
    try { await P.printReceipt(job, shop); } catch (e) { toast('Gagal cetak: ' + e.message); }
  }

  $('posDoneReprint').addEventListener('click', () => doPrint(lastSale));

  // Printer connect button + label
  function updatePrinterLbl() {
    const P = window.RmsPrinter;
    const lbl = $('posPrinterLbl');
    if (!lbl) return;
    lbl.textContent = (P && P.isConnected && P.isConnected()) ? (P.getName() || 'CONNECTED') : 'PRINTER';
  }
  if (window.RmsPrinter) {
    window.RmsPrinter.onChange(updatePrinterLbl);
  }
  $('posPrinterBtn').addEventListener('click', async () => {
    const P = window.RmsPrinter; if (!P) { toast('Printer module tiada'); return; }
    if (P.isConnected()) { await P.disconnect(); await P.disconnectUSB(); return; }
    try {
      if (P.bleSupported()) await P.connect();
      else if (P.usbSupported()) await P.connectUSB();
      else toast('Browser tak support printer');
    } catch (e) { toast(e.message); }
  });

  // --- Customer datalist (from pos_trackings + past quick_sales customer_name)
  async function loadCustomerList() {
    const out = new Map();
    const { data: pt } = await window.sb.from('pos_trackings').select('customer_name,customer_tel').eq('tenant_id', ctx.tenant_id).limit(500);
    (pt || []).forEach((r) => { if (r.customer_name) out.set(r.customer_name, r.customer_tel || ''); });
    const { data: qs } = await window.sb.from('quick_sales').select('description').eq('branch_id', branchId).eq('kind', 'SALE').order('sold_at', { ascending: false }).limit(300);
    (qs || []).forEach((r) => { try { const d = JSON.parse(r.description || '{}'); if (d.customer_name) out.set(d.customer_name, d.customer_tel || out.get(d.customer_name) || ''); } catch (_) {} });
    $('posCustList').innerHTML = [...out.entries()].map(([n, t]) => `<option value="${n}">${t}</option>`).join('');
  }
  $('posCustName').addEventListener('change', () => {
    const v = $('posCustName').value;
    const opt = $('posCustList').querySelector(`option[value="${v.replace(/"/g,'\\"')}"]`);
    if (opt && opt.textContent && !$('posCustTel').value) $('posCustTel').value = opt.textContent;
  });

  // --- Staff dropdown
  async function loadStaff() {
    const { data } = await window.sb
      .from('branch_staff')
      .select('user:users(id,nama,role)')
      .eq('branch_id', branchId)
      .limit(100);
    let list = (data || [])
      .map((r) => r.user)
      .filter((u) => u && u.nama && u.role !== 'owner');
    if (!list.length && ctx.nama) list = [{ id: ctx.id, nama: ctx.nama }];
    $('posStaff').innerHTML = '<option value="">— Pilih Staff —</option>' + list.map((u) => `<option value="${u.nama}">${u.nama}</option>`).join('');
    $('posStaff').value = '';
    try {
      const raw = localStorage.getItem('posStaffDefault');
      if (raw) {
        const o = JSON.parse(raw);
        const today = new Date().toISOString().slice(0, 10);
        if (o && o.date === today && list.some((u) => u.nama === o.nama)) {
          $('posStaff').value = o.nama;
          $('posStaffDefault').classList.add('is-on');
        }
      }
    } catch (_) {}
  }

  // --- History modal
  let HIST = [];
  async function fetchHistory() {
    const { data } = await window.sb
      .from('quick_sales').select('*')
      .eq('branch_id', branchId).eq('kind', 'SALE')
      .order('sold_at', { ascending: false }).limit(500);
    HIST = data || [];
    renderHist();
  }
  function renderHist() {
    const range = $('posHistRange').value;
    const q = ($('posHistSearch').value || '').toLowerCase();
    const now = Date.now();
    let fromT = 0, toT = Infinity;
    if (range === 'custom') {
      if ($('posHistFrom').value) fromT = new Date($('posHistFrom').value + 'T00:00:00').getTime();
      if ($('posHistTo').value) toT = new Date($('posHistTo').value + 'T23:59:59').getTime();
    } else {
      fromT = range === 'today' ? new Date().setHours(0,0,0,0)
        : range === 'week' ? now - 7*864e5
        : range === 'month' ? now - 30*864e5
        : 0;
    }
    const rows = HIST.filter((r) => {
      const t = r.sold_at ? new Date(r.sold_at).getTime() : 0;
      if (t < fromT || t > toT) return false;
      if (q) {
        const desc = (r.description || '').toLowerCase();
        if (!desc.includes(q)) return false;
      }
      return true;
    });
    $('posHistCount').textContent = rows.length;
    $('posHistTotal').textContent = fmtRM(rows.reduce((s, r) => s + Number(r.amount || 0), 0));
    $('posHistEmpty').classList.toggle('hidden', rows.length > 0);
    const methodColor = (m) => ({ CASH:'c-green', CARD:'c-blue', QR:'c-cyan', EWALLET:'c-yellow', BANK:'c-orange' }[String(m||'').toUpperCase()] || 'c-muted');
    $('posHistList').innerHTML = rows.map((r) => {
      let d = {}; try { d = JSON.parse(r.description || '{}'); } catch (e) {}
      const dt = r.sold_at ? new Date(r.sold_at) : null;
      const dtStr = dt ? `${String(dt.getDate()).padStart(2,'0')}/${String(dt.getMonth()+1).padStart(2,'0')} ${String(dt.getHours()).padStart(2,'0')}:${String(dt.getMinutes()).padStart(2,'0')}` : '';
      return `<div class="pos-hist-row" data-id="${r.id}">
        <div class="pos-hist-row__main">
          <div class="pos-hist-row__top">
            <span class="pos-hist-row__siri">#${d.siri || r.id.slice(0,8)}</span>
            <span class="pos-hist-row__method ${methodColor(r.payment_method)}">${r.payment_method || '—'}</span>
          </div>
          <div class="pos-hist-row__nama">${d.customer_name || 'Walk-in'}${d.customer_tel ? ' · ' + d.customer_tel : ''}</div>
          <div class="pos-hist-row__meta">${dtStr}</div>
        </div>
        <div class="pos-hist-row__right">
          <span class="pos-hist-row__amt">${fmtRM(r.amount)}</span>
          <button type="button" class="pos-hist-row__print" data-id="${r.id}" title="Cetak resit"><i class="fas fa-print"></i></button>
        </div>
      </div>`;
    }).join('');
    $('posHistList').querySelectorAll('.pos-hist-row__print').forEach((b) => {
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = b.dataset.id;
        const r = rows.find((x) => x.id === id);
        if (!r) return;
        let d = {}; try { d = JSON.parse(r.description || '{}'); } catch (_) {}
        doPrint({ siri: d.siri || r.id.slice(0,8), total: r.amount, method: r.payment_method, row: r });
      });
    });
    window.__POS_HIST_ROWS = rows;
  }

  async function printRangeSummary() {
    const rows = window.__POS_HIST_ROWS || [];
    if (!rows.length) { toast('Tiada rekod dalam julat'); return; }
    const P = window.RmsPrinter;
    if (!P || !P.isConnected || !P.isConnected()) { toast('Printer tidak disambung'); return; }
    const fromStr = $('posHistFrom').value || '—';
    const toStr = $('posHistTo').value || '—';
    const rangeLbl = $('posHistRange').options[$('posHistRange').selectedIndex].text;
    const total = rows.reduce((s, r) => s + Number(r.amount || 0), 0);
    const lines = [];
    lines.push('RINGKASAN JUALAN POS');
    lines.push((branchRow && (branchRow.nama_kedai || branchRow.name)) || '');
    lines.push('================================');
    lines.push('Julat: ' + rangeLbl);
    if ($('posHistRange').value === 'custom') lines.push(`${fromStr} — ${toStr}`);
    lines.push('--------------------------------');
    rows.forEach((r) => {
      let d = {}; try { d = JSON.parse(r.description || '{}'); } catch (_) {}
      const dt = r.sold_at ? new Date(r.sold_at) : null;
      const dtStr = dt ? `${String(dt.getDate()).padStart(2,'0')}/${String(dt.getMonth()+1).padStart(2,'0')} ${String(dt.getHours()).padStart(2,'0')}:${String(dt.getMinutes()).padStart(2,'0')}` : '';
      lines.push(`${dtStr} #${d.siri || r.id.slice(0,6)}`);
      lines.push(`  ${(d.customer_name || 'Walk-in').slice(0,24)}  ${fmtRM(r.amount)}`);
    });
    lines.push('--------------------------------');
    lines.push(`JUMLAH (${rows.length}): ${fmtRM(total)}`);
    lines.push('================================');
    try {
      if (P.printText) await P.printText(lines.join('\n') + '\n\n\n');
      else await P.printReceipt({ siri: 'RANGE', nama: 'RINGKASAN', items_array: rows.map((r) => ({ nama: `#${(JSON.parse(r.description||'{}').siri)||r.id.slice(0,6)}`, qty: 1, harga: Number(r.amount||0) })) }, { shopName: (branchRow && (branchRow.nama_kedai || branchRow.name)) || 'RMS PRO' });
      toast('Cetak ringkasan dihantar');
    } catch (e) { toast('Gagal cetak: ' + e.message); }
  }
  $('posHistPrintRange').addEventListener('click', printRangeSummary);
  $('posHistoryBtn').addEventListener('click', async () => { await fetchHistory(); $('posHistModal').classList.add('is-open'); });
  $('posHistClose').addEventListener('click', () => $('posHistModal').classList.remove('is-open'));
  try {
    const s = JSON.parse(localStorage.getItem('posSettings') || '{}');
    if (s.footerNote != null) $('posFooterNote').value = s.footerNote;
    if (s.autoPrint != null) $('posAutoPrint').checked = !!s.autoPrint;
    if (s.taxEnable != null) $('posTaxEnable').checked = !!s.taxEnable;
    if (s.taxPct != null) $('posTaxPct').value = s.taxPct;
    $('posTaxRow').classList.toggle('hidden', !$('posTaxEnable').checked);
  } catch (_) {}
  $('posStaffDefault').addEventListener('click', () => {
    const nama = $('posStaff').value;
    if (!nama) { toast('Pilih staff dahulu'); return; }
    const today = new Date().toISOString().slice(0, 10);
    try {
      if ($('posStaffDefault').classList.contains('is-on')) {
        localStorage.removeItem('posStaffDefault');
        $('posStaffDefault').classList.remove('is-on');
        toast('Default dibuang');
      } else {
        localStorage.setItem('posStaffDefault', JSON.stringify({ nama, date: today }));
        $('posStaffDefault').classList.add('is-on');
        toast('Default set: ' + nama);
      }
    } catch (e) { toast('Gagal: ' + e.message); }
  });
  $('posSaveSettings').addEventListener('click', () => {
    try {
      localStorage.setItem('posSettings', JSON.stringify({
        footerNote: $('posFooterNote').value,
        autoPrint: $('posAutoPrint').checked,
        taxEnable: $('posTaxEnable').checked,
        taxPct: Number($('posTaxPct').value) || 0,
      }));
      toast('Tetapan disimpan');
      $('posSettingsModal').classList.remove('is-open');
    } catch (e) { toast('Gagal simpan: ' + e.message); }
  });
  $('posSettingsBtn').addEventListener('click', () => $('posSettingsModal').classList.add('is-open'));
  $('posSettingsClose').addEventListener('click', () => $('posSettingsModal').classList.remove('is-open'));
  $('posTaxEnable').addEventListener('change', () => {
    $('posTaxRow').classList.toggle('hidden', !$('posTaxEnable').checked);
    renderCart();
  });
  $('posTaxPct').addEventListener('input', () => renderCart());
  $('posPushDrawerBtn').addEventListener('click', async () => {
    const P = window.RmsPrinter;
    if (!P || !P.isConnected || !P.isConnected()) { toast('Printer tak bersambung'); return; }
    try { await P.kickCashDrawer(); toast('Drawer dibuka'); } catch (e) { toast('Gagal: ' + e.message); }
  });
  $('posHistRange').addEventListener('change', renderHist);
  $('posHistSearch').addEventListener('input', renderHist);
  $('posHistFrom').addEventListener('change', () => { $('posHistRange').value = 'custom'; renderHist(); });
  $('posHistTo').addEventListener('change', () => { $('posHistRange').value = 'custom'; renderHist(); });

  // --- Branch info (for receipt + header)
  let branchRow = null;
  (async () => {
    const { data } = await window.sb.from('branches').select('name,nama_kedai,phone,alamat,email').eq('id', branchId).single();
    branchRow = data || {};
    $('posShop').textContent = (branchRow.nama_kedai || branchRow.name || '').toUpperCase();
  })();

  // Realtime
  window.sb.channel('pos-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'stock_parts', filter: `branch_id=eq.${branchId}` }, async () => { await fetchProducts(); renderProducts(); })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'accessories', filter: `branch_id=eq.${branchId}` }, async () => { await fetchProducts(); renderProducts(); })
    .subscribe();

  await loadStaff();
  await fetchProducts();
  renderCats();
  renderProducts();
  renderCart();
  loadCustomerList().catch(() => {});
  updatePrinterLbl();
})();
