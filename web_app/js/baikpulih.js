/* baikpulih.js — Create repair ticket wizard. Mirror baikpulih HTML (3-step).
   Step 1: Pelanggan (nama, tel, model, tarikh). Step 2: Items + staff + password/pattern.
   Step 3: Bayaran (deposit, diskaun, voucher, method, status). Save → jobs + job_items. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function toast(msg, err) {
    const t = $('bpToast'); if (!t) return;
    t.textContent = msg; t.hidden = false;
    t.style.background = err ? '#dc2626' : '#0f172a';
    setTimeout(() => { t.hidden = true; }, 2200);
  }

  let step = 1; // 1, 2, 3 (skip gallery)
  let items = [{ nama: '', qty: 1, harga: 0 }];
  let pattern = [];
  let backupTel = '';
  let voucher = null;
  let custType = 'NEW CUST';
  let lastSavedJob = null;
  let lastShop = null;

  const STEP_NAMES = { 1: 'PELANGGAN', 2: 'KEROSAKAN', 3: 'BAYARAN' };

  function renderStep() {
    $('bpStepNow').textContent = String(step);
    $('bpStepName').textContent = STEP_NAMES[step] || '';
    $('bpStepFill').style.width = `${(step / 3) * 100}%`;
    document.querySelectorAll('.bp-step').forEach((s) => {
      const ds = s.dataset.step;
      s.hidden = String(ds) !== String(step);
      s.classList.toggle('is-active', String(ds) === String(step));
    });
    $('bpPrev').hidden = step <= 1;
    $('bpNext').hidden = step >= 3;
    $('bpSave').hidden = step !== 3;
  }

  // ── Cust type toggle ──────────────────────────────────────
  document.querySelectorAll('#bpCustTypeToggle button').forEach((b) => {
    b.addEventListener('click', () => {
      document.querySelectorAll('#bpCustTypeToggle button').forEach((x) => x.classList.remove('is-on'));
      b.classList.add('is-on');
      custType = b.dataset.v;
      $('bpCustSearchRow').hidden = custType !== 'REGULAR';
    });
  });

  // Regular cust search
  const bpSearch = $('bpCustSearch');
  if (bpSearch) bpSearch.addEventListener('input', async (e) => {
    const q = e.target.value.trim();
    if (q.length < 2) { $('bpCustHits').hidden = true; return; }
    const { data } = await window.sb.from('jobs')
      .select('nama,tel,model').eq('branch_id', branchId)
      .or(`nama.ilike.%${q}%,tel.ilike.%${q}%`).limit(10);
    const seen = {};
    const hits = (data || []).filter((r) => { if (!r.tel || seen[r.tel]) return false; seen[r.tel] = 1; return true; });
    $('bpCustHits').innerHTML = hits.map((r, i) => `<div class="bp-cust-hit" data-i="${i}" style="padding:8px;border-bottom:1px solid #f1f5f9;cursor:pointer;"><b>${r.nama}</b> · ${r.tel} · ${r.model || ''}</div>`).join('');
    $('bpCustHits').hidden = !hits.length;
    $('bpCustHits').querySelectorAll('.bp-cust-hit').forEach((el) => {
      el.addEventListener('click', () => {
        const r = hits[Number(el.dataset.i)];
        $('bpNama').value = r.nama || '';
        $('bpTel').value = r.tel || '';
        $('bpModel').value = r.model || '';
        $('bpCustHits').hidden = true;
      });
    });
  });

  // ── Backup modal ──────────────────────────────────────────
  $('bpBackupBtn').addEventListener('click', () => {
    $('bpWasap').value = backupTel;
    $('bpBackupModal').classList.add('is-open');
  });
  $('bpBackupClose').addEventListener('click', () => $('bpBackupModal').classList.remove('is-open'));
  $('bpBackupSave').addEventListener('click', () => {
    backupTel = $('bpWasap').value.trim();
    $('bpBackupModal').classList.remove('is-open');
    toast('No backup disimpan');
  });

  // ── Items ─────────────────────────────────────────────────
  function renderItems() {
    $('bpItems').innerHTML = items.map((it, i) => `
      <div class="bp-item-row" style="display:grid;grid-template-columns:2fr 60px 90px auto;gap:6px;margin-bottom:6px;">
        <input class="bp-input" data-k="nama" data-i="${i}" placeholder="Item / kerosakan" value="${it.nama || ''}">
        <input class="bp-input" data-k="qty" data-i="${i}" type="number" min="1" value="${it.qty || 1}">
        <input class="bp-input" data-k="harga" data-i="${i}" type="number" step="0.01" value="${it.harga || 0}">
        <button type="button" data-del="${i}" style="padding:8px;border:1px solid #dc262655;color:#dc2626;background:transparent;border-radius:8px;cursor:pointer;"><i class="fas fa-trash"></i></button>
      </div>`).join('');
    $('bpItems').querySelectorAll('input').forEach((inp) => {
      inp.addEventListener('input', (e) => {
        const i = Number(e.target.dataset.i);
        const k = e.target.dataset.k;
        items[i][k] = k === 'nama' ? e.target.value : (Number(e.target.value) || 0);
        recalc();
      });
    });
    $('bpItems').querySelectorAll('[data-del]').forEach((b) => {
      b.addEventListener('click', () => {
        items.splice(Number(b.dataset.del), 1);
        if (!items.length) items.push({ nama: '', qty: 1, harga: 0 });
        renderItems(); recalc();
      });
    });
  }
  $('bpAddItem').addEventListener('click', () => { items.push({ nama: '', qty: 1, harga: 0 }); renderItems(); });

  function subtotal() { return items.reduce((s, it) => s + (Number(it.qty) || 0) * (Number(it.harga) || 0), 0); }
  function recalc() {
    const sub = subtotal();
    $('bpItemTotal').textContent = fmtRM(sub);
    $('bpSubTotal').textContent = fmtRM(sub);
    const deposit = Number($('bpDeposit').value) || 0;
    const diskaun = Number($('bpDiskaun').value) || 0;
    const vAmt = voucher ? Number(voucher.amount || 0) : 0;
    $('bpVoucherShow').textContent = '- ' + fmtRM(vAmt);
    $('bpDiskaunShow').textContent = '- ' + fmtRM(diskaun);
    $('bpDepositShow').textContent = '- ' + fmtRM(deposit);
    const baki = Math.max(0, sub - vAmt - diskaun - deposit);
    $('bpBaki').textContent = fmtRM(baki);
  }
  ['bpDeposit', 'bpDiskaun'].forEach((k) => $(k).addEventListener('input', recalc));

  // ── Staff ─────────────────────────────────────────────────
  async function loadStaff() {
    const { data } = await window.sb.from('users').select('id,nama').eq('tenant_id', ctx.tenant_id).limit(100);
    const list = (data && data.length) ? data : [{ id: ctx.id, nama: ctx.nama }];
    $('bpStaff').innerHTML = list.map((u) => `<option value="${u.nama || u.id}">${u.nama || u.id}</option>`).join('');
    if (ctx.nama) $('bpStaff').value = ctx.nama;
  }

  // ── Pattern modal ─────────────────────────────────────────
  const patternBox = $('bpPatternBox');
  if (patternBox) {
    patternBox.innerHTML = Array.from({ length: 9 }, (_, i) => `<div class="bp-pattern-dot" data-i="${i + 1}" style="width:40px;height:40px;border:2px solid #cbd5e1;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;margin:4px;">${i + 1}</div>`).join('');
    patternBox.style.cssText = 'display:grid;grid-template-columns:repeat(3,1fr);gap:8px;justify-items:center;';
    patternBox.querySelectorAll('.bp-pattern-dot').forEach((d) => {
      d.addEventListener('click', () => {
        const i = Number(d.dataset.i);
        if (pattern.includes(i)) return;
        pattern.push(i);
        d.style.background = '#6366F1'; d.style.color = '#fff'; d.style.borderColor = '#6366F1';
        $('bpPatternTxtModal').textContent = pattern.join('-');
      });
    });
  }
  $('bpPatternBtn').addEventListener('click', () => $('bpPatternModal').classList.add('is-open'));
  $('bpPatternClose').addEventListener('click', () => $('bpPatternModal').classList.remove('is-open'));
  $('bpPatternClear').addEventListener('click', () => {
    pattern = [];
    patternBox.querySelectorAll('.bp-pattern-dot').forEach((d) => { d.style.background = ''; d.style.color = ''; d.style.borderColor = '#cbd5e1'; });
    $('bpPatternTxtModal').textContent = '-';
  });
  $('bpPatternSave').addEventListener('click', () => {
    if (pattern.length) {
      $('bpPatternChip').hidden = false;
      $('bpPatternTxt').textContent = pattern.join('-');
    }
    $('bpPatternModal').classList.remove('is-open');
  });
  $('bpPatternReset').addEventListener('click', () => {
    pattern = []; $('bpPatternChip').hidden = true; $('bpPatternTxt').textContent = '-';
  });

  // ── Voucher modal ─────────────────────────────────────────
  $('bpVoucherBtn').addEventListener('click', () => $('bpVoucherModal').classList.add('is-open'));
  $('bpVoucherClose').addEventListener('click', () => $('bpVoucherModal').classList.remove('is-open'));
  async function checkVoucher(code, targetMsg) {
    if (!code) return;
    const { data } = await window.sb
      .from('shop_vouchers')
      .select('id, voucher_code, allocated_amount, used_amount, remaining, expiry_date')
      .eq('tenant_id', tenantId)
      .eq('voucher_code', code.toUpperCase())
      .maybeSingle();
    const fail = (msg) => { $(targetMsg).textContent = msg; $(targetMsg).style.color = '#dc2626'; voucher = null; $('bpVoucherChip').hidden = true; recalc(); };
    if (!data) return fail('Kod tidak sah');
    if (data.expiry_date && new Date(data.expiry_date) < new Date()) return fail('Voucher dah expired');
    const remaining = Number(data.remaining ?? (data.allocated_amount - data.used_amount));
    if (remaining <= 0) return fail('Voucher dah habis pakai');
    voucher = { id: data.id, code: data.voucher_code, amount: remaining };
    $(targetMsg).textContent = `OK — potongan ${fmtRM(voucher.amount)}`;
    $(targetMsg).style.color = '#10b981';
    $('bpVoucherChip').hidden = false;
    $('bpVoucherChipTxt').textContent = `${voucher.code} · ${fmtRM(voucher.amount)}`;
    recalc();
  }
  $('bpVoucherApply').addEventListener('click', () => checkVoucher($('bpVoucherInput').value.trim(), 'bpVoucherMsg'));
  $('bpPromoApply').addEventListener('click', () => checkVoucher($('bpPromo').value.trim(), 'bpPromoMsg'));
  $('bpVoucherReset').addEventListener('click', () => { voucher = null; $('bpVoucherChip').hidden = true; recalc(); });

  // ── Nav ───────────────────────────────────────────────────
  $('bpNext').addEventListener('click', () => {
    if (step === 1) {
      if (!$('bpNama').value.trim() || !$('bpTel').value.trim()) { toast('Nama & telefon wajib', true); return; }
    }
    if (step === 2) {
      if (!items.some((i) => i.nama)) { toast('Tambah sekurang-kurangnya 1 item', true); return; }
    }
    step = Math.min(3, step + 1); renderStep(); recalc();
  });
  $('bpPrev').addEventListener('click', () => { step = Math.max(1, step - 1); renderStep(); });
  $('bpBack').addEventListener('click', () => { history.length > 1 ? history.back() : (window.location.href = 'branch.html'); });
  $('bpClose').addEventListener('click', () => { if (confirm('Tutup dan buang data?')) window.location.reload(); });

  // ── Save ──────────────────────────────────────────────────
  function genSiri() {
    const d = new Date();
    const yy = String(d.getFullYear()).slice(2);
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const rnd = Math.floor(Math.random() * 9000) + 1000;
    return `B${yy}${mm}${dd}${rnd}`;
  }

  $('bpSave').addEventListener('click', async () => {
    $('bpSave').disabled = true;
    try {
      const harga = subtotal();
      const deposit = Number($('bpDeposit').value) || 0;
      const diskaun = Number($('bpDiskaun').value) || 0;
      const vAmt = voucher ? Number(voucher.amount || 0) : 0;
      const total = Math.max(0, harga - diskaun - vAmt);
      const baki = Math.max(0, total - deposit);
      const siri = genSiri();
      const payStatus = $('bpPayStatus').value === 'PAID' ? 'PAID' : 'PENDING';

      const payload = {
        tenant_id: ctx.tenant_id,
        branch_id: branchId,
        siri,
        nama: $('bpNama').value.trim(),
        tel: $('bpTel').value.trim(),
        tel_wasap: backupTel || null,
        model: $('bpModel').value.trim(),
        kerosakan: items.filter((i) => i.nama).map((i) => i.nama).join(', '),
        jenis_servis: $('bpJenis').value,
        status: 'IN PROGRESS',
        tarikh: $('bpTarikh').value ? new Date($('bpTarikh').value).toISOString() : new Date().toISOString(),
        harga: Number(harga.toFixed(2)),
        deposit: Number(deposit.toFixed(2)),
        diskaun: Number(diskaun.toFixed(2)),
        tambahan: 0,
        total: Number(total.toFixed(2)),
        baki: Number(baki.toFixed(2)),
        payment_status: payStatus,
        cara_bayaran: $('bpPayMethod').value,
        device_password: $('bpPass').value.trim() || (pattern.length ? 'PATTERN:' + pattern.join('-') : null),
        cust_type: custType,
        staff_terima: $('bpStaff').value || ctx.nama,
        catatan: $('bpCatatan').value.trim() || null,
        voucher_used: voucher ? voucher.code : null,
        voucher_used_amt: voucher ? Number(vAmt.toFixed(2)) : 0,
      };

      const { data: job, error } = await window.sb.from('jobs').insert(payload).select().single();
      if (error) throw error;

      const itemRows = items.filter((i) => i.nama).map((i) => ({
        tenant_id: ctx.tenant_id, job_id: job.id, nama: i.nama,
        qty: Number(i.qty) || 1, harga: Number(Number(i.harga || 0).toFixed(2)),
      }));
      if (itemRows.length) await window.sb.from('job_items').insert(itemRows);

      // Bump voucher used_amount
      if (voucher && vAmt > 0) {
        const { data: vRow } = await window.sb.from('shop_vouchers').select('used_amount').eq('id', voucher.id).single();
        const newUsed = Number((Number(vRow?.used_amount || 0) + vAmt).toFixed(2));
        await window.sb.from('shop_vouchers').update({ used_amount: newUsed }).eq('id', voucher.id);
      }

      lastSavedJob = Object.assign({}, job, { items_array: itemRows });
      if (!lastShop) {
        const { data: br } = await window.sb.from('branches').select('*').eq('id', branchId).single();
        lastShop = br || {};
      }
      $('bpDoneSiri').textContent = '#' + siri;
      $('bpDoneAmt').textContent = fmtRM(total);
      $('bpDoneStatus').textContent = payStatus;
      $('bpDoneModal').classList.add('is-open');
    } catch (e) {
      toast('Gagal: ' + (e.message || e), true);
    } finally {
      $('bpSave').disabled = false;
    }
  });

  $('bpDoneOk').addEventListener('click', () => window.location.reload());
  $('bpDonePrintBtn').addEventListener('click', async () => {
    const P = window.RmsPrinter;
    if (!P || !P.isConnected || !P.isConnected()) { toast('Printer tidak disambung. Klik PRINTER dulu.', true); return; }
    if (!lastSavedJob) { toast('Tiada resit untuk dicetak', true); return; }
    try { await P.printReceipt(lastSavedJob, lastShop || {}); }
    catch (e) { toast('Gagal cetak: ' + e.message, true); }
  });
  $('bpPrinterBtn').addEventListener('click', async () => {
    const P = window.RmsPrinter;
    if (!P) { toast('Printer module tiada', true); return; }
    if (P.isConnected()) { await P.disconnect(); await P.disconnectUSB(); toast('Printer disconnect'); return; }
    try {
      if (P.bleSupported()) await P.connect();
      else if (P.usbSupported()) await P.connectUSB();
      else toast('Browser tak support printer', true);
      if (P.isConnected()) toast('Printer: ' + P.getName());
    } catch (e) { toast(e.message, true); }
  });

  // Init date
  (function initDate() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    $('bpTarikh').value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  })();

  renderItems();
  recalc();
  await loadStaff();
  renderStep();
})();
