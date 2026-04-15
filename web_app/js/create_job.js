/* create_job.js — Supabase. Mirror create_job_screen.dart 1:1 (3-step wizard + voucher/referral + stock_usage). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;
  const tenantId = ctx.tenant_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'cj-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2400);
  }

  let step = 0;
  let custType = 'NEW CUST';
  let items = [{ nama: '', qty: 1, harga: 0 }];
  let pattern = [];
  let kodVoucher = '';
  let voucherAmt = 0;
  let branchSettings = {};
  const stockUsageHistory = []; // {usage_id, stock_part_id, kod, nama, jual}
  const ownerID = (ctx.email || '').split('@')[0] || 'unknown';
  const snapUrls = { depan: null, belakang: null };

  // ─── Load branch settings (voucherAmount / referralAmount) ───
  async function loadBranchSettings() {
    if (!branchId) return;
    try {
      const { data } = await window.sb
        .from('branches')
        .select('enabled_modules')
        .eq('id', branchId)
        .maybeSingle();
      branchSettings = (data && data.enabled_modules) || {};
    } catch (_) { branchSettings = {}; }
  }

  // ─── Snap upload (Supabase Storage) ───
  function wireSnap(key) {
    const card = document.querySelector(`.cj-snap-card[data-k="${key}"]`);
    if (!card) return;
    card.style.cursor = 'pointer';
    card.addEventListener('click', async () => {
      if (!window.SupabaseStorage) { snack('Storage helper missing', true); return; }
      const orig = card.innerHTML;
      card.innerHTML = '<div style="font-size:11px;">UPLOADING...</div>';
      try {
        const siri = 'DRAFT' + Date.now();
        const url = await window.SupabaseStorage.pickAndUpload({
          bucket: 'repairs',
          pathFn: () => `${ownerID}/${siri}/${key}_${Date.now()}.jpg`,
          maxDim: 1280, quality: 0.8,
        });
        if (!url) { card.innerHTML = orig; return; }
        snapUrls[key] = url;
        card.innerHTML = `<img src="${url}" style="width:60px;height:60px;object-fit:cover;border-radius:6px;"><div style="font-size:10px;margin-top:4px;">${key.toUpperCase()}</div>`;
      } catch (e) {
        card.innerHTML = orig;
        snack('Upload gagal: ' + e.message, true);
      }
    });
  }
  wireSnap('depan');
  wireSnap('belakang');

  const STEP_LABELS = ['Pelanggan', 'Kerosakan', 'Bayaran'];

  function renderStep() {
    $('stepIndicator').innerHTML = STEP_LABELS.map((lbl, i) => {
      const cls = i === step ? 'is-active' : (i < step ? 'is-done' : '');
      return `<span class="cj-step__dot ${cls}">${i + 1}</span><span style="font-weight:800;">${lbl}</span>${i < STEP_LABELS.length - 1 ? '<span class="cj-step__line"></span>' : ''}`;
    }).join('');
    document.querySelectorAll('section[data-step]').forEach((s) => {
      s.style.display = Number(s.dataset.step) === step ? '' : 'none';
    });
    $('btnPrev').style.display = step > 0 ? '' : 'none';
    $('btnNext').hidden = step >= 2;
    $('btnSave').hidden = step !== 2;
  }

  document.querySelectorAll('#custTypeToggle button').forEach((b) => {
    b.addEventListener('click', () => {
      document.querySelectorAll('#custTypeToggle button').forEach((x) => x.classList.remove('is-active'));
      b.classList.add('is-active');
      custType = b.dataset.v;
      $('custSearchRow').hidden = custType !== 'REGULAR';
    });
  });

  // ─── Customer dedup search dari customers table (mirror Flutter line 290) ───
  $('custSearch') && $('custSearch').addEventListener('input', async (e) => {
    const q = e.target.value.trim();
    if (q.length < 2) { $('custHits').hidden = true; return; }
    const { data } = await window.sb
      .from('customers')
      .select('nama,tel')
      .eq('tenant_id', tenantId)
      .or(`nama.ilike.%${q}%,tel.ilike.%${q}%`)
      .order('last_visit_at', { ascending: false })
      .limit(20);
    const hits = (data || []);
    $('custHits').innerHTML = hits.map((r, i) => `<div class="cj-cust-hit" data-i="${i}"><b>${r.nama || '—'}</b> · ${r.tel || ''}</div>`).join('');
    $('custHits').hidden = !hits.length;
    $('custHits').querySelectorAll('.cj-cust-hit').forEach((el) => {
      el.addEventListener('click', async () => {
        const r = hits[Number(el.dataset.i)];
        $('nama').value = r.nama || '';
        $('tel').value = r.tel || '';
        $('custHits').hidden = true;
        // Pull last job untuk pre-fill tel_wasap + model
        try {
          const { data: lastJob } = await window.sb
            .from('jobs').select('tel_wasap,model')
            .eq('tenant_id', tenantId).eq('tel', r.tel)
            .order('created_at', { ascending: false }).limit(1).maybeSingle();
          if (lastJob) {
            $('telWasap').value = lastJob.tel_wasap || '';
            $('model').value = lastJob.model || '';
          }
        } catch (_) {}
      });
    });
  });

  // ─── Pattern lock ───
  const patternBox = $('patternBox');
  if (patternBox) {
    patternBox.innerHTML = Array.from({ length: 9 }, (_, i) => `<div class="cj-pattern-dot" data-i="${i + 1}">${i + 1}</div>`).join('');
    patternBox.querySelectorAll('.cj-pattern-dot').forEach((d) => {
      d.addEventListener('click', () => {
        const i = Number(d.dataset.i);
        if (pattern.includes(i)) return;
        pattern.push(i);
        d.classList.add('is-on');
        $('patternTxt').textContent = pattern.join('-');
      });
    });
    $('patternClear').addEventListener('click', () => {
      pattern = [];
      patternBox.querySelectorAll('.cj-pattern-dot').forEach((d) => d.classList.remove('is-on'));
      $('patternTxt').textContent = '-';
    });
  }

  // ─── Items render ───
  function renderItems() {
    $('itemsWrap').innerHTML = items.map((it, i) => `
      <div class="cj-item-row">
        <input class="input" data-k="nama" data-i="${i}" placeholder="Nama item / servis" value="${it.nama || ''}">
        <input class="input" data-k="qty" data-i="${i}" type="number" min="1" value="${it.qty || 1}">
        <input class="input" data-k="harga" data-i="${i}" type="number" step="0.01" placeholder="0.00" value="${it.harga || 0}">
        <button class="cj-del" data-del="${i}"><i class="fas fa-trash"></i></button>
      </div>`).join('');
    $('itemsWrap').querySelectorAll('input').forEach((inp) => {
      inp.addEventListener('input', (e) => {
        const i = Number(e.target.dataset.i);
        const k = e.target.dataset.k;
        items[i][k] = k === 'nama' ? e.target.value : Number(e.target.value) || 0;
        recalcTotal();
      });
    });
    $('itemsWrap').querySelectorAll('[data-del]').forEach((btn) => {
      btn.addEventListener('click', () => {
        items.splice(Number(btn.dataset.del), 1);
        if (!items.length) items.push({ nama: '', qty: 1, harga: 0 });
        renderItems();
        recalcTotal();
      });
    });
  }
  $('addItem').addEventListener('click', () => { items.push({ nama: '', qty: 1, harga: 0 }); renderItems(); });

  // ─── Add item from stock_parts (mirror Flutter line 2200) ───
  function renderStockUsage() {
    if (!stockUsageHistory.length) { $('stockUsageList').innerHTML = ''; return; }
    $('stockUsageList').innerHTML = '<b>Stok diambil:</b><br>' + stockUsageHistory.map((u, i) =>
      `<div style="display:flex;justify-content:space-between;padding:4px 6px;background:#f1f5f9;border-radius:4px;margin:2px 0;">
        <span>${u.kod} — ${u.nama} (${fmtRM(u.jual)})</span>
        <button data-cancel="${i}" style="background:#fee2e2;color:#dc2626;border:none;border-radius:4px;padding:2px 8px;cursor:pointer;font-size:10px;">BATAL</button>
      </div>`
    ).join('');
    $('stockUsageList').querySelectorAll('[data-cancel]').forEach((btn) => {
      btn.addEventListener('click', () => cancelStockUsage(Number(btn.dataset.cancel)));
    });
  }

  async function addFromStock() {
    const kod = (window.prompt('Masukkan kod SKU stok:') || '').trim().toUpperCase();
    if (!kod) return;
    try {
      const { data: rows, error } = await window.sb
        .from('stock_parts')
        .select('id,sku,part_name,price,qty')
        .eq('tenant_id', tenantId)
        .eq('sku', kod)
        .gt('qty', 0)
        .order('created_at', { ascending: true })
        .limit(1);
      if (error) throw error;
      if (!rows || !rows.length) { snack(`Tiada stok "${kod}" available`, true); return; }
      const inv = rows[0];
      const newQty = (inv.qty || 0) - 1;
      const upd = await window.sb.from('stock_parts').update({ qty: newQty }).eq('id', inv.id);
      if (upd.error) throw upd.error;
      const usageRes = await window.sb.from('stock_usage').insert({
        tenant_id: tenantId,
        branch_id: branchId,
        stock_part_id: inv.id,
        part_name: inv.part_name,
        qty: 1,
        used_by: $('staffTerima').value || ctx.nama,
      }).select('id').single();
      if (usageRes.error) throw usageRes.error;
      stockUsageHistory.push({
        usage_id: usageRes.data.id,
        stock_part_id: inv.id,
        kod: inv.sku,
        nama: inv.part_name,
        jual: Number(inv.price) || 0,
      });
      items.push({ nama: inv.part_name, qty: 1, harga: Number(inv.price) || 0 });
      renderItems();
      renderStockUsage();
      recalcTotal();
      snack(`Stok diambil: ${inv.part_name}`);
    } catch (e) {
      snack('Gagal ambil stok: ' + (e.message || e), true);
    }
  }
  $('addFromStock') && $('addFromStock').addEventListener('click', addFromStock);

  async function cancelStockUsage(idx) {
    const u = stockUsageHistory[idx];
    if (!u) return;
    try {
      const cur = await window.sb.from('stock_parts').select('qty').eq('id', u.stock_part_id).maybeSingle();
      const curQty = (cur && cur.data && cur.data.qty) || 0;
      await window.sb.from('stock_parts').update({ qty: curQty + 1 }).eq('id', u.stock_part_id);
      await window.sb.from('stock_usage').delete().eq('id', u.usage_id);
      stockUsageHistory.splice(idx, 1);
      // Remove last matching item (best-effort)
      const ix = items.findIndex((it) => it.nama === u.nama && Number(it.harga) === Number(u.jual));
      if (ix >= 0) { items.splice(ix, 1); if (!items.length) items.push({ nama: '', qty: 1, harga: 0 }); renderItems(); }
      renderStockUsage();
      recalcTotal();
      snack(`Stok "${u.nama}" dibatalkan`);
    } catch (e) {
      snack('Gagal batal: ' + (e.message || e), true);
    }
  }

  function subtotal() {
    return items.reduce((s, it) => s + (Number(it.qty) || 0) * (Number(it.harga) || 0), 0);
  }
  function recalcTotal() {
    $('totalHarga').textContent = fmtRM(subtotal());
  }

  // ─── Promo (V-XXXX voucher / REF-XXXX referral) — mirror Flutter line 582 ───
  async function checkPromo() {
    const kod = ($('promo').value || '').trim().toUpperCase();
    $('promoMsg').textContent = '';
    if (!kod) { kodVoucher = ''; voucherAmt = 0; return; }

    if (kod.startsWith('V-')) {
      try {
        const { data: v } = await window.sb
          .from('shop_vouchers').select('*')
          .eq('tenant_id', tenantId).eq('voucher_code', kod).maybeSingle();
        if (!v) { snack(`Voucher ${kod} tidak dijumpai`, true); return; }
        const remaining = Number(v.remaining) || 0;
        if (remaining <= 0) { snack(`Voucher ${kod} habis kuota`, true); return; }
        const exp = v.expiry_date;
        if (exp && new Date(exp) < new Date()) { snack(`Voucher ${kod} tamat tempoh`, true); return; }
        const perClaim = Number(branchSettings.voucherAmount) || 5;
        voucherAmt = remaining < perClaim ? remaining : perClaim;
        kodVoucher = kod;
        $('promoMsg').textContent = `Voucher aktif. Potongan ${fmtRM(voucherAmt)}`;
        $('promoMsg').style.color = '#059669';
        snack(`Voucher ${kod} aktif`);
      } catch (e) { snack('Ralat semak voucher: ' + e.message, true); }
      return;
    }

    if (kod.startsWith('REF-')) {
      try {
        const { data: ref } = await window.sb
          .from('referrals').select('*')
          .eq('tenant_id', tenantId).eq('code', kod).maybeSingle();
        if (!ref) { snack(`Referral ${kod} tidak dijumpai`, true); return; }
        if ((ref.status || '').toUpperCase() !== 'ACTIVE') { snack('Referral tidak aktif', true); return; }
        const maxUses = Number(ref.max_uses) || 0;
        const usedCount = Number(ref.used_count) || 0;
        if (maxUses > 0 && usedCount >= maxUses) { snack('Referral habis kuota', true); return; }
        if (ref.valid_until && new Date(ref.valid_until) < new Date()) { snack('Referral tamat tempoh', true); return; }
        const discAmt = Number(ref.discount_amount) || 0;
        voucherAmt = discAmt > 0 ? discAmt : (Number(branchSettings.referralAmount) || 5);
        kodVoucher = kod;
        $('promoMsg').textContent = `Referral aktif. Potongan ${fmtRM(voucherAmt)}`;
        $('promoMsg').style.color = '#059669';
        snack(`Referral ${kod} aktif`);
      } catch (e) { snack('Ralat semak referral: ' + e.message, true); }
      return;
    }

    snack('Format kod tak dikenali. Guna V-XXXX atau REF-XXXX', true);
  }
  $('applyPromo') && $('applyPromo').addEventListener('click', checkPromo);

  async function loadStaff() {
    const { data } = await window.sb.from('users').select('id,nama').eq('tenant_id', tenantId).limit(100);
    const list = (data && data.length) ? data : [{ id: ctx.id, nama: ctx.nama }];
    $('staffTerima').innerHTML = list.map((u) => `<option value="${u.nama || u.id}">${u.nama || u.id}</option>`).join('');
    if (ctx.nama) $('staffTerima').value = ctx.nama;
  }

  function genSiri() {
    const d = new Date();
    const yy = String(d.getFullYear()).slice(2);
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const rnd = Math.floor(Math.random() * 9000) + 1000;
    return `J${yy}${mm}${dd}${rnd}`;
  }

  (function initDateTime() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    $('tarikh').value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  })();

  $('btnNext').addEventListener('click', () => {
    if (step === 0) {
      if (!$('nama').value.trim() || !$('tel').value.trim()) { snack('Nama & telefon wajib', true); return; }
    }
    step = Math.min(2, step + 1);
    renderStep();
  });
  $('btnPrev').addEventListener('click', () => { step = Math.max(0, step - 1); renderStep(); });
  $('btnReset').addEventListener('click', () => window.location.reload());

  // ─── SAVE ───
  $('btnSave').addEventListener('click', async () => {
    const harga = subtotal();
    const deposit = Number($('deposit').value) || 0;
    const diskaunRaw = Number($('diskaun').value) || 0;
    const diskaun = diskaunRaw + (Number(voucherAmt) || 0); // voucher tambah ke diskaun
    const total = Math.max(0, harga - diskaun);
    const baki = Math.max(0, total - deposit);
    const siri = genSiri();
    const payStatus = $('paymentStatus').value === 'PAID' ? 'PAID' : 'PENDING';

    const payload = {
      tenant_id: tenantId,
      branch_id: branchId,
      siri,
      nama: $('nama').value.trim(),
      tel: $('tel').value.trim(),
      tel_wasap: $('telWasap').value.trim() || null,
      model: $('model').value.trim(),
      kerosakan: items.filter((i) => i.nama).map((i) => i.nama).join(', '),
      jenis_servis: $('jenisServis').value,
      status: 'IN PROGRESS',
      tarikh: $('tarikh').value ? new Date($('tarikh').value).toISOString() : new Date().toISOString(),
      harga: Number(harga.toFixed(2)),
      deposit: Number(deposit.toFixed(2)),
      diskaun: Number(diskaun.toFixed(2)),
      tambahan: 0,
      total: Number(total.toFixed(2)),
      baki: Number(baki.toFixed(2)),
      payment_status: payStatus,
      cara_bayaran: $('caraBayaran').value,
      device_password: $('password').value.trim() || (pattern.length ? 'PATTERN:' + pattern.join('-') : null),
      cust_type: custType,
      staff_terima: $('staffTerima').value || ctx.nama,
      voucher_used: kodVoucher || null,
      voucher_used_amt: voucherAmt > 0 ? Number(voucherAmt.toFixed(2)) : null,
      catatan: (() => {
        const base = $('catatan').value.trim();
        if (!snapUrls.depan && !snapUrls.belakang) return base || null;
        const tag = `[IMG] depan=${snapUrls.depan || ''} belakang=${snapUrls.belakang || ''}`;
        return base ? `${base}\n${tag}` : tag;
      })(),
    };

    const { data: job, error } = await window.sb.from('jobs').insert(payload).select().single();
    if (error) { snack('Gagal: ' + error.message, true); return; }

    // job_items insert
    const itemRows = items.filter((i) => i.nama).map((i) => ({
      tenant_id: tenantId, job_id: job.id, nama: i.nama, qty: Number(i.qty) || 1, harga: Number(Number(i.harga || 0).toFixed(2)),
    }));
    if (itemRows.length) await window.sb.from('job_items').insert(itemRows);

    // job_timeline insert (audit trail — mirror Flutter pattern)
    try {
      await window.sb.from('job_timeline').insert({
        tenant_id: tenantId, job_id: job.id, status: 'IN PROGRESS',
        note: 'Tiket dibuka', by_user: ctx.nama || ctx.id,
      });
    } catch (_) {}

    // Backfill stock_usage rows dengan job_id (Flutter log usage tanpa job_id, link selepas siri ada)
    if (stockUsageHistory.length) {
      try {
        const ids = stockUsageHistory.map((u) => u.usage_id);
        await window.sb.from('stock_usage').update({ job_id: job.id }).in('id', ids);
      } catch (_) {}
    }

    // Voucher V-XXXX bump used_amount
    if (kodVoucher.startsWith('V-')) {
      try {
        const { data: v } = await window.sb.from('shop_vouchers').select('id,used_amount').eq('tenant_id', tenantId).eq('voucher_code', kodVoucher).maybeSingle();
        if (v) await window.sb.from('shop_vouchers').update({ used_amount: (Number(v.used_amount) || 0) + voucherAmt }).eq('id', v.id);
      } catch (_) {}
    }

    // Referral REF-XXXX bump used_count
    if (kodVoucher.startsWith('REF-')) {
      try {
        const { data: r } = await window.sb.from('referrals').select('id,used_count').eq('tenant_id', tenantId).eq('code', kodVoucher).maybeSingle();
        if (r) await window.sb.from('referrals').update({ used_count: (Number(r.used_count) || 0) + 1 }).eq('id', r.id);
      } catch (_) {}
    }

    // Customer upsert (last_visit_at touch, mirror Flutter customers dedup)
    try {
      const tel = $('tel').value.trim();
      if (tel) {
        await window.sb.from('customers').upsert({
          tenant_id: tenantId, tel, nama: $('nama').value.trim(),
          last_visit_at: new Date().toISOString(),
        }, { onConflict: 'tenant_id,tel' });
      }
    } catch (_) {}

    snack('Tiket ' + siri + ' disimpan');
    $('siriBadge').hidden = false;
    $('siriBadge').textContent = siri;

    // Reset
    items = [{ nama: '', qty: 1, harga: 0 }];
    pattern = [];
    kodVoucher = ''; voucherAmt = 0;
    stockUsageHistory.length = 0;
    snapUrls.depan = null; snapUrls.belakang = null;
    document.querySelectorAll('.cj-snap-card').forEach((c) => {
      const k = c.dataset.k;
      c.innerHTML = `<i class="fas fa-camera fa-2x"></i><div>${(k||'').toUpperCase()}</div>`;
    });
    ['nama','tel','telWasap','model','password','catatan','promo'].forEach((k) => { if ($(k)) $(k).value = ''; });
    ['deposit','diskaun'].forEach((k) => { if ($(k)) $(k).value = '0'; });
    $('promoMsg').textContent = '';
    renderItems();
    renderStockUsage();
    recalcTotal();
    if ($('patternTxt')) $('patternTxt').textContent = '-';
    patternBox && patternBox.querySelectorAll('.cj-pattern-dot').forEach((d) => d.classList.remove('is-on'));
    $('btnReset').hidden = false;
    step = 0;
    renderStep();
  });

  await loadBranchSettings();
  renderItems();
  recalcTotal();
  renderStockUsage();
  await loadStaff();
  renderStep();
})();
