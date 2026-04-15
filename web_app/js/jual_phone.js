/* jual_phone.js — List phone_sales with Active/Arkib/Padam tabs. Mirror jual_telefon_screen.dart. */
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
    return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
  };

  function snack(msg, err) {
    const el = document.createElement('div');
    el.style.cssText = 'position:fixed;left:50%;bottom:20px;transform:translateX(-50%);background:' +
      (err ? '#dc2626' : '#0f172a') + ';color:#fff;padding:10px 16px;border-radius:10px;z-index:9999;';
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  let seg = 'CUSTOMER'; // CUSTOMER | DEALER
  let tab = 'ACTIVE'; // ACTIVE | ARCHIVED | DELETED
  let timeFilter = 'SEMUA';
  let searchQ = '';
  let ROWS = [];

  function parseNotes(s) { try { return typeof s === 'string' ? JSON.parse(s || '{}') : (s || {}); } catch (_) { return {}; } }

  function timeRange() {
    const now = new Date();
    const start = new Date(now); start.setHours(0, 0, 0, 0);
    if (timeFilter === 'HARI INI') return start;
    if (timeFilter === 'MINGGU INI') { const d = new Date(start); const day = d.getDay() || 7; d.setDate(d.getDate() - (day - 1)); return d; }
    if (timeFilter === 'BULAN INI') return new Date(now.getFullYear(), now.getMonth(), 1);
    if (timeFilter === 'TAHUN INI') return new Date(now.getFullYear(), 0, 1);
    return null;
  }

  async function fetchRows() {
    let q = window.sb.from('phone_sales').select('*')
      .eq('branch_id', branchId)
      .order('sold_at', { ascending: false }).limit(1000);
    if (tab === 'DELETED') q = q.not('deleted_at', 'is', null);
    else q = q.is('deleted_at', null);
    const from = timeRange();
    if (from) q = q.gte('sold_at', from.toISOString());
    const { data, error } = await q;
    if (error) { console.error(error); return []; }
    let rows = data || [];
    if (tab === 'ARCHIVED') rows = rows.filter((r) => { const n = parseNotes(r.notes); return n.archived === true; });
    if (tab === 'ACTIVE') rows = rows.filter((r) => { const n = parseNotes(r.notes); return !n.archived; });
    // Filter segment
    rows = rows.filter((r) => {
      const n = parseNotes(r.notes);
      const isDealer = n.segment === 'DEALER' || n.dealer === true;
      return seg === 'DEALER' ? isDealer : !isDealer;
    });
    return rows;
  }

  function applySearch(rows) {
    if (!searchQ) return rows;
    const q = searchQ.toLowerCase();
    return rows.filter((r) => {
      const n = parseNotes(r.notes);
      return `${r.customer_name || ''} ${r.customer_phone || ''} ${r.device_name || ''} ${n.imei || ''} ${n.siri || r.id || ''}`.toLowerCase().includes(q);
    });
  }

  function render() {
    const rows = applySearch(ROWS);
    $('listTitle').textContent = tab === 'ACTIVE' ? 'Senarai Bil Aktif' : tab === 'ARCHIVED' ? 'Senarai Bil Arkib' : 'Senarai Bil Padam';
    $('jpEmpty').hidden = rows.length > 0;
    $('jpList').innerHTML = rows.map((r) => {
      const n = parseNotes(r.notes);
      return `<div class="jp-bill" data-id="${r.id}" style="background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:12px;margin-bottom:10px;cursor:pointer;">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;">
          <div style="flex:1;min-width:0;">
            <div style="font-weight:900;font-size:13px;">${r.device_name || '—'}</div>
            <div style="font-size:11px;color:#64748b;">${r.customer_name || '—'} · ${r.customer_phone || ''}</div>
            <div style="font-size:10px;color:#94a3b8;">${fmtDate(r.sold_at)}</div>
            ${n.imei ? `<div style="font-size:10px;color:#64748b;">IMEI: ${n.imei}</div>` : ''}
          </div>
          <div style="text-align:right;">
            <div style="font-weight:900;color:#2563eb;">${fmtRM(r.total_price || r.price_per_unit)}</div>
            <div style="font-size:10px;color:#64748b;">${seg === 'DEALER' ? 'DEALER' : 'CUSTOMER'}</div>
          </div>
        </div>
        <div style="display:flex;gap:6px;margin-top:8px;">
          ${tab === 'ACTIVE' ? '<button data-act="archive" style="flex:1;padding:6px;border:1px solid #f59e0b55;color:#f59e0b;background:transparent;border-radius:6px;cursor:pointer;"><i class="fas fa-box-archive"></i> Arkib</button>' : ''}
          ${tab !== 'DELETED' ? '<button data-act="del" style="flex:1;padding:6px;border:1px solid #dc262655;color:#dc2626;background:transparent;border-radius:6px;cursor:pointer;"><i class="fas fa-trash"></i> Padam</button>' : '<button data-act="restore" style="flex:1;padding:6px;border:1px solid #10b98155;color:#10b981;background:transparent;border-radius:6px;cursor:pointer;"><i class="fas fa-rotate-left"></i> Pulih</button>'}
        </div>
      </div>`;
    }).join('');

    $('jpList').querySelectorAll('.jp-bill').forEach((el) => {
      const row = ROWS.find((r) => r.id === el.dataset.id);
      el.querySelectorAll('[data-act]').forEach((b) => {
        b.addEventListener('click', async (e) => {
          e.stopPropagation();
          const act = b.dataset.act;
          if (act === 'archive') {
            const n = parseNotes(row.notes); n.archived = true;
            await window.sb.from('phone_sales').update({ notes: JSON.stringify(n) }).eq('id', row.id);
            snack('Diarkibkan');
          } else if (act === 'del') {
            if (!confirm('Padam bil ini?')) return;
            await window.sb.from('phone_sales').update({ deleted_at: new Date().toISOString() }).eq('id', row.id);
            snack('Dipadam');
          } else if (act === 'restore') {
            await window.sb.from('phone_sales').update({ deleted_at: null }).eq('id', row.id);
            snack('Dipulihkan');
          }
          ROWS = await fetchRows(); render();
        });
      });
      el.addEventListener('click', () => openDetail(row));
    });
  }

  function openDetail(row) {
    if (!row) return;
    const n = parseNotes(row.notes);
    alert(
      `${row.device_name || '—'}\n` +
      `Customer: ${row.customer_name || '—'} (${row.customer_phone || '—'})\n` +
      `Harga: ${fmtRM(row.price_per_unit)}\n` +
      `Total: ${fmtRM(row.total_price)}\n` +
      `IMEI: ${n.imei || '—'}\n` +
      `Tarikh: ${fmtDate(row.sold_at)}\n` +
      (n.note ? `Nota: ${n.note}` : '')
    );
  }

  // Segment
  document.querySelectorAll('#jpSegment .jp-seg-btn').forEach((b) => {
    b.addEventListener('click', async () => {
      document.querySelectorAll('#jpSegment .jp-seg-btn').forEach((x) => x.classList.remove('is-active'));
      b.classList.add('is-active');
      seg = b.dataset.seg;
      ROWS = await fetchRows(); render();
    });
  });
  // Arkib / Padam toggles (mirror Flutter: Arkib toggles ACTIVE↔ARCHIVED; Padam visible only in ARKIB/PADAM)
  function applyTabStyle() {
    const ark = document.getElementById('jpArkibBtn');
    const pad = document.getElementById('jpPadamBtn');
    if (ark) {
      const on = tab === 'ARCHIVED';
      ark.style.background = on ? '#f59e0b' : '#fff';
      ark.style.color = on ? '#fff' : '#64748b';
      ark.style.borderColor = on ? '#f59e0b' : '#e2e8f0';
    }
    if (pad) {
      const show = tab === 'ARCHIVED' || tab === 'DELETED';
      pad.hidden = !show;
      pad.style.display = show ? 'inline-flex' : 'none';
      const on = tab === 'DELETED';
      pad.style.background = on ? '#dc2626' : '#fff';
      pad.style.color = on ? '#fff' : '#dc2626';
      pad.style.borderColor = on ? '#dc2626' : '#e2e8f0';
    }
  }
  const arkBtn = document.getElementById('jpArkibBtn');
  if (arkBtn) arkBtn.addEventListener('click', async () => {
    tab = (tab === 'ARCHIVED') ? 'ACTIVE' : 'ARCHIVED';
    applyTabStyle();
    ROWS = await fetchRows(); render();
  });
  const padBtn = document.getElementById('jpPadamBtn');
  if (padBtn) padBtn.addEventListener('click', async () => {
    tab = (tab === 'DELETED') ? 'ARCHIVED' : 'DELETED';
    applyTabStyle();
    ROWS = await fetchRows(); render();
  });
  applyTabStyle();
  // Filter
  $('fTime').addEventListener('change', async (e) => { timeFilter = e.target.value; ROWS = await fetchRows(); render(); });
  $('fSearch').addEventListener('input', (e) => { searchQ = e.target.value; render(); });

  window.sb.channel('phone_sales-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'phone_sales', filter: `branch_id=eq.${branchId}` }, async () => { ROWS = await fetchRows(); render(); })
    .subscribe();

  // ─── CREATE BILL FLOW (mirror jual_telefon_screen.dart line 920+) ───
  function genSiri() {
    const d = new Date();
    return 'JT' + String(d.getFullYear()).slice(2) + String(d.getMonth()+1).padStart(2,'0') + String(d.getDate()).padStart(2,'0') + Math.floor(Math.random()*9000+1000);
  }

  async function openCreate() {
    const body = $('jpCreateBody');
    const isDealer = seg === 'DEALER';
    body.innerHTML = `
      <div style="margin-bottom:10px;padding:8px;background:#f1f5f9;border-radius:8px;font-size:12px;">
        <b>Mod:</b> ${isDealer ? 'DEALER' : 'CUSTOMER'} <span style="color:#64748b;">(tukar guna segment atas)</span>
      </div>
      ${isDealer ? `
      <div style="margin-bottom:10px;">
        <label style="font-size:11px;font-weight:700;">Pilih Dealer</label>
        <select id="jcDealer" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;"><option value="">— Pilih —</option></select>
      </div>` : ''}
      <div style="margin-bottom:10px;">
        <label style="font-size:11px;font-weight:700;">Cari Telefon (kod/nama)</label>
        <input id="jcPhoneSearch" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;" placeholder="Kod atau nama telefon...">
        <div id="jcPhoneHits" style="max-height:160px;overflow:auto;margin-top:4px;"></div>
        <div id="jcPhonePicked" style="margin-top:6px;"></div>
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;">
        <div><label style="font-size:11px;">Nama Pelanggan</label><input id="jcCustName" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;"></div>
        <div><label style="font-size:11px;">Telefon</label><input id="jcCustTel" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;" inputmode="tel"></div>
      </div>
      <div style="margin-bottom:10px;"><label style="font-size:11px;">Alamat</label><textarea id="jcCustAddr" rows="2" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;"></textarea></div>
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-bottom:10px;">
        <div><label style="font-size:11px;">Cara Bayar</label>
          <select id="jcPay" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;"><option>CASH</option><option>BANK</option><option>QR</option><option>ANSURAN</option></select></div>
        <div><label style="font-size:11px;">Tempoh</label>
          <select id="jcTerm" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;"><option>FULL</option><option>7 HARI</option><option>14 HARI</option><option>30 HARI</option></select></div>
        <div><label style="font-size:11px;">Waranti</label>
          <select id="jcWar" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;"><option>TIADA</option><option>1 BULAN</option><option>3 BULAN</option><option>6 BULAN</option></select></div>
      </div>
      <div style="margin-bottom:10px;"><label style="font-size:11px;">Staff</label>
        <input id="jcStaff" style="width:100%;padding:8px;border:1px solid #e2e8f0;border-radius:6px;" value="${ctx.nama || ''}"></div>
      <button id="jcSave" style="width:100%;padding:12px;background:#10b981;color:#fff;border:none;border-radius:8px;font-weight:900;cursor:pointer;">
        <i class="fas fa-save"></i> SIMPAN BIL
      </button>
      <div id="jcMsg" style="margin-top:8px;font-size:12px;text-align:center;"></div>
    `;
    $('jpCreateBg').style.display = 'flex';

    let pickedPhone = null;

    if (isDealer) {
      const { data: dealers } = await window.sb.from('dealers').select('id,nama_pemilik,nama_kedai,no_ssm').eq('tenant_id', ctx.tenant_id).order('nama_kedai');
      const sel = $('jcDealer');
      (dealers || []).forEach((d) => {
        const o = document.createElement('option');
        o.value = d.id; o.textContent = `${d.nama_kedai || d.nama_pemilik || '-'} (${d.no_ssm || ''})`;
        o.dataset.row = JSON.stringify(d);
        sel.appendChild(o);
      });
    }

    let searchTimer = null;
    $('jcPhoneSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimer);
      const q = e.target.value.trim();
      if (q.length < 2) { $('jcPhoneHits').innerHTML = ''; return; }
      searchTimer = setTimeout(async () => {
        const { data } = await window.sb.from('phone_stock')
          .select('id,device_name,price,cost,notes,qty,status')
          .eq('tenant_id', ctx.tenant_id)
          .gt('qty', 0).neq('status', 'SOLD')
          .or(`device_name.ilike.%${q}%`).limit(20);
        $('jcPhoneHits').innerHTML = (data || []).map((p, i) => {
          const n = parseNotes(p.notes);
          return `<div data-i="${i}" style="padding:6px;border-bottom:1px solid #e2e8f0;cursor:pointer;font-size:12px;">
            <b>${p.device_name}</b> · ${fmtRM(p.price)} <span style="color:#64748b;">${n.imei || n.kod || ''}</span>
          </div>`;
        }).join('');
        $('jcPhoneHits').querySelectorAll('[data-i]').forEach((el) => {
          el.addEventListener('click', () => {
            pickedPhone = data[Number(el.dataset.i)];
            const n = parseNotes(pickedPhone.notes);
            $('jcPhonePicked').innerHTML = `
              <div style="padding:8px;background:#dbeafe;border-radius:6px;font-size:12px;">
                <b>${pickedPhone.device_name}</b> — ${fmtRM(pickedPhone.price)}
                <div style="font-size:10px;color:#64748b;">IMEI: ${n.imei || '—'} · Kos: ${fmtRM(pickedPhone.cost)}</div>
              </div>`;
            $('jcPhoneHits').innerHTML = '';
            $('jcPhoneSearch').value = pickedPhone.device_name;
          });
        });
      }, 250);
    });

    $('jcSave').addEventListener('click', async () => {
      if (!pickedPhone) { $('jcMsg').textContent = 'Pilih telefon dahulu'; $('jcMsg').style.color = '#dc2626'; return; }
      if (isDealer && !$('jcDealer').value) { $('jcMsg').textContent = 'Pilih dealer'; $('jcMsg').style.color = '#dc2626'; return; }
      const siri = genSiri();
      const jual = Number(pickedPhone.price) || 0;
      const kos = Number(pickedPhone.cost) || 0;
      const n = parseNotes(pickedPhone.notes);
      const dealerOpt = isDealer ? $('jcDealer').selectedOptions[0] : null;
      const dealerRow = dealerOpt && dealerOpt.dataset.row ? JSON.parse(dealerOpt.dataset.row) : null;

      try {
        // 1. phone_stock update SOLD
        await window.sb.from('phone_stock').update({ status: 'SOLD', qty: 0 }).eq('id', pickedPhone.id);
        // 2. phone_sales insert
        await window.sb.from('phone_sales').insert({
          tenant_id: ctx.tenant_id, branch_id: branchId,
          phone_stock_id: pickedPhone.id, device_name: pickedPhone.device_name,
          qty: 1, price_per_unit: jual, total_price: jual,
          customer_name: $('jcCustName').value.trim().toUpperCase(),
          customer_phone: $('jcCustTel').value.trim(),
          sold_by: $('jcStaff').value, payment_method: $('jcPay').value,
          payment_status: 'PAID',
          notes: JSON.stringify({
            imei: n.imei || '', kod: n.kod || '', warna: n.warna || '', storage: n.storage || '',
            kos, siri, saleType: seg,
            ...(dealerRow ? { dealerName: dealerRow.nama_pemilik, dealerKedai: dealerRow.nama_kedai } : {}),
          }),
        });
        // 3. phone_receipts insert
        const receipt = {
          tenant_id: ctx.tenant_id, branch_id: branchId, siri,
          sale_type: seg, bill_status: 'ACTIVE',
          cust_name: $('jcCustName').value.trim().toUpperCase(),
          cust_phone: $('jcCustTel').value.trim(),
          cust_address: $('jcCustAddr').value.trim(),
          phone_name: pickedPhone.device_name,
          items: [{ nama: pickedPhone.device_name, kos, jual, imei: n.imei || '', stockId: pickedPhone.id, isAccessory: false }],
          buy_price: kos, sell_price: jual,
          payment_method: $('jcPay').value, payment_term: $('jcTerm').value,
          warranty: $('jcWar').value, staff_name: $('jcStaff').value,
        };
        if (dealerRow) {
          receipt.dealer_id = dealerRow.id;
          receipt.dealer_name = dealerRow.nama_pemilik || '';
          receipt.dealer_kedai = dealerRow.nama_kedai || '';
          receipt.dealer_ssm = dealerRow.no_ssm || '';
        }
        await window.sb.from('phone_receipts').insert(receipt);
        // 4. quick_sales income log
        await window.sb.from('quick_sales').insert({
          tenant_id: ctx.tenant_id, branch_id: branchId,
          kind: 'JUALAN TELEFON', description: siri,
          amount: jual, sold_by: $('jcStaff').value,
          payment_method: $('jcPay').value, sold_at: new Date().toISOString(),
        });
        snack('Bil ' + siri + ' disimpan');
        $('jpCreateBg').style.display = 'none';
        ROWS = await fetchRows(); render();
      } catch (e) {
        $('jcMsg').textContent = 'Gagal: ' + (e.message || e);
        $('jcMsg').style.color = '#dc2626';
      }
    });
  }

  $('jpFab').addEventListener('click', openCreate);
  $('jpCreateClose').addEventListener('click', () => { $('jpCreateBg').style.display = 'none'; });
  $('jpCreateBg').addEventListener('click', (e) => { if (e.target === $('jpCreateBg')) $('jpCreateBg').style.display = 'none'; });

  ROWS = await fetchRows();
  render();
})();
