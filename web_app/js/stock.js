/* Stock — 1:1 port of lib/screens/modules/stock_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID  = (shopRaw  || '').toUpperCase();

  // Init storage if available
  let storage = null;
  try { storage = firebase.storage(); } catch(_) {}

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const num = v => Number(v) || 0;

  const state = {
    inventory: [],
    filtered: [],
    search: '',
    pickedImage: null,   // File
  };

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'st-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2500);
  }

  // ─── Printer (shared RmsPrinter) ───
  (function wirePrinter(){
    const btn = document.getElementById('posPrinterBtn');
    const lbl = document.getElementById('posPrinterLbl');
    if(!btn || !lbl || !window.RmsPrinter) return;
    RmsPrinter.onChange(st => {
      if (!st.supported) {
        btn.classList.add('is-disabled');
        lbl.textContent = 'TIDAK DISOKONG';
        btn.title = 'Browser ini tidak sokong Web Bluetooth/USB. Guna Chrome/Edge.';
        return;
      }
      btn.classList.toggle('is-on', st.connected);
      lbl.textContent = st.connected ? (st.name || 'TERSAMBUNG') : 'PRINTER';
    });
    btn.addEventListener('click', async () => {
      if (!RmsPrinter.isSupported()) return snack('Web Bluetooth tidak disokong — guna Chrome/Edge', true);
      if (RmsPrinter.isConnected()) {
        if (confirm('Putus sambungan printer "' + RmsPrinter.getName() + '"?')) await RmsPrinter.disconnect();
        return;
      }
      try { await RmsPrinter.connect(); snack('Printer tersambung: ' + RmsPrinter.getName()); }
      catch (e) { snack('Gagal sambung: ' + e.message, true); }
    });
  })();

  function escposStockLabel(kod, nama, rm){
    const ESC_INIT='\x1B\x40', ESC_CENTER='\x1B\x61\x01', ESC_DBL='\x1B\x21\x30', ESC_NORMAL='\x1B\x21\x00',
          ESC_BOLD_ON='\x1B\x45\x01', ESC_BOLD_OFF='\x1B\x45\x00', CUT='\x1D\x56\x00';
    const txt = ESC_INIT + ESC_CENTER + ESC_BOLD_ON + 'LABEL STOK\n' + ESC_BOLD_OFF +
      '--------------------------------\n' +
      ESC_DBL + ESC_BOLD_ON + String(kod) + '\n' + ESC_NORMAL + ESC_BOLD_OFF +
      String(nama).substring(0,30) + '\n' +
      '--------------------------------\n' +
      ESC_DBL + ESC_BOLD_ON + 'RM ' + rm + '\n' + ESC_NORMAL + ESC_BOLD_OFF +
      '~ RMS Pro ~\n\n\n\n' + CUT;
    return new TextEncoder().encode(txt);
  }

  function generateKod() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let s = '';
    for (let i = 0; i < 6; i++) s += chars[Math.floor(Math.random() * chars.length)];
    return 'STK-' + s;
  }

  function filter() {
    const q = state.search.toLowerCase().trim();
    state.filtered = q ? state.inventory.filter(d =>
      String(d.kod||'').toLowerCase().includes(q) ||
      String(d.nama||'').toLowerCase().includes(q) ||
      String(d.no_siri_jual||'').toLowerCase().includes(q)
    ) : state.inventory.slice();
  }

  // ── LISTEN ──
  db.collection('inventory_' + ownerID).orderBy('timestamp', 'desc').onSnapshot(snap => {
    const list = [];
    snap.forEach(doc => list.push(Object.assign({ id: doc.id }, doc.data())));
    state.inventory = list;
    filter(); render();
  }, err => console.error('stock listener', err));

  // ── RENDER ──
  function render() {
    const wrap = $('stList'); wrap.innerHTML = '';
    $('stEmpty').hidden = state.filtered.length > 0;
    state.filtered.forEach(d => wrap.appendChild(stockCard(d)));

    // footer
    const totalQty = state.filtered.reduce((s,d) => s + num(d.qty), 0);
    const totalJual = state.filtered.reduce((s,d) => s + num(d.jual) * num(d.qty), 0);
    $('stFooter').innerHTML = `
      <span class="st-foot-chip" style="background:#64748b15;color:#64748b;">${state.filtered.length} item</span>
      <span class="st-foot-chip" style="background:#3b82f615;color:#3b82f6;">QTY: ${totalQty}</span>
      <span class="st-foot-chip" style="background:#10b98115;color:#10b981;">Jual: RM ${totalJual.toFixed(0)}</span>
    `;
  }

  function stockCard(d) {
    const qty = num(d.qty);
    const status = String(d.status || '').toUpperCase();
    const isSold = status === 'TERJUAL';
    const isRet  = status === 'RETURNED';
    const isUsed = status === 'USED';
    const kod = d.kod || '-';
    const nama = d.nama || '-';
    const jual = num(d.jual);
    const category = String(d.category || '');
    const tarikhMasuk = d.tarikh_masuk || '';
    const tkhJual = d.tkh_jual || '';
    const siriJual = d.no_siri_jual || '';
    const supplier = d.supplier || '';

    let sColor = '#10b981', sText = 'AVAILABLE';
    if (isSold) { sColor = '#ef4444'; sText = 'TERJUAL'; }
    else if (isRet) { sColor = '#f97316'; sText = 'RETURNED'; }
    else if (isUsed) { sColor = '#3b82f6'; sText = 'USED'; }

    const low = qty <= 2;
    const el = document.createElement('div');
    el.className = 'st-card' + (low ? ' low' : '');
    el.innerHTML = `
      <div class="st-qty ${low?'low':''}">${qty}</div>
      <div class="st-body">
        <div class="st-row1">
          <span class="st-kod">${esc(kod)}</span>
          <span>
            ${category ? `<span class="st-mini" style="background:#06b6d422;color:#06b6d4;">${esc(category)}</span>` : ''}
            <span class="st-mini" style="background:${sColor}22;color:${sColor};">${sText}</span>
          </span>
        </div>
        <div class="st-nama">${esc(nama)}</div>
        <div class="st-meta">
          <span class="st-jual">Jual: RM ${jual.toFixed(2)}</span>
          ${supplier ? `<span style="color:#eab308;">${esc(supplier)}</span>` : ''}
        </div>
        ${(tarikhMasuk || tkhJual || siriJual) ? `<div class="st-meta" style="margin-top:2px;">
          ${tarikhMasuk ? `<span>Masuk: ${esc(tarikhMasuk)}</span>` : ''}
          ${tkhJual ? `<span>Jual: ${esc(tkhJual)}</span>` : ''}
          ${siriJual ? `<span style="color:#3b82f6;font-weight:700;">#${esc(siriJual)}</span>` : ''}
        </div>` : ''}
      </div>
      <i class="fas fa-chevron-right" style="color:#94a3b8;font-size:10px;align-self:center;"></i>
    `;
    el.addEventListener('click', () => showEditModal(d));
    return el;
  }

  // ── ADD MODAL ──
  function openAddModal(prefill) {
    prefill = prefill || {};
    $('addKod').value = prefill.kod || generateKod();
    $('addNama').value = prefill.nama || '';
    $('addJual').value = prefill.jual != null ? Number(prefill.jual).toFixed(2) : '';
    $('addTarikh').value = new Date().toISOString().slice(0,10);
    $('addCategory').value = 'SPAREPART';
    state.pickedImage = null;
    $('addImgPick').style.backgroundImage = '';
    $('addImgPick').innerHTML = `<i class="fas fa-camera" style="font-size:22px;"></i><div style="font-size:10px;margin-top:4px;font-weight:700;">TAMBAH GAMBAR</div>`;
    open('mAdd');
  }

  $('btnAdd').addEventListener('click', () => openAddModal());
  $('addImgPick').addEventListener('click', () => $('addImgFile').click());
  $('addImgFile').addEventListener('change', e => {
    const f = e.target.files[0]; if (!f) return;
    if (f.size > 100 * 1024) { snack('Gambar melebihi 100KB. Sila pilih gambar lebih kecil.', true); e.target.value = ''; return; }
    state.pickedImage = f;
    const url = URL.createObjectURL(f);
    $('addImgPick').style.backgroundImage = `url('${url}')`;
    $('addImgPick').innerHTML = '';
  });
  $('addCopy').addEventListener('click', async () => {
    const k = $('addKod').value.trim();
    if (k) { try { await navigator.clipboard.writeText(k); snack('Kod "'+k+'" disalin'); } catch { snack('Gagal salin', true); } }
  });
  $('addAuto').addEventListener('click', () => { $('addKod').value = generateKod(); });
  $('addScan').addEventListener('click', () => {
    const code = prompt('Masukkan kod barcode / QR:');
    if (code) handleScannedCode(code);
  });
  $('addSave').addEventListener('click', async () => {
    const kod = $('addKod').value.trim();
    if (!kod) { snack('Sila isi Kod Item', true); return; }
    try {
      let imageUrl = '';
      if (state.pickedImage && storage) {
        const ts = Date.now();
        const ref = storage.ref().child('inventory/' + ownerID + '/' + kod + '_' + ts + '.jpg');
        const task = await ref.put(state.pickedImage, { contentType: 'image/jpeg' });
        imageUrl = await task.ref.getDownloadURL();
      }
      await db.collection('inventory_' + ownerID).add({
        kod: kod.toUpperCase(),
        nama: $('addNama').value.trim().toUpperCase(),
        category: $('addCategory').value,
        kos: 0,
        jual: parseFloat($('addJual').value) || 0,
        qty: 1,
        supplier: '',
        tarikh_masuk: $('addTarikh').value.trim(),
        tkh_jual: '',
        no_siri_jual: '',
        imageUrl: imageUrl,
        status: 'AVAILABLE',
        timestamp: Date.now(),
        shopID: shopID,
      });
      close('mAdd');
      snack('Stok berjaya ditambah');
    } catch(e) { snack('Gagal: ' + e.message, true); }
  });

  // Scan handler (search)
  $('btnScan').addEventListener('click', () => {
    const code = prompt('Masukkan kod barcode / QR:');
    if (!code) return;
    $('stSearch').value = code.trim().toUpperCase();
    state.search = $('stSearch').value;
    filter(); render();
  });

  function handleScannedCode(code) {
    const clean = code.trim().toUpperCase();
    if (!clean) return;
    const existing = state.inventory.find(d => String(d.kod||'').toUpperCase() === clean);
    openAddModal({
      kod: clean,
      nama: existing ? existing.nama : '',
      jual: existing ? existing.jual : null,
    });
  }

  // ── EDIT MODAL ──
  function showEditModal(item) {
    const docId = item.id;
    const qty = num(item.qty);
    const isSold = String(item.status||'').toUpperCase() === 'TERJUAL';
    const kod = item.kod || '-';
    $('editTitle').textContent = 'EDIT: ' + kod;
    const body = $('editBody');
    body.innerHTML = `
      <div style="display:flex;gap:8px;align-items:center;margin-bottom:12px;">
        <span class="st-mini" style="background:${isSold?'#ef444422':'#10b98122'};color:${isSold?'#ef4444':'#10b981'};">${isSold?'TERJUAL':'AVAILABLE'}</span>
        <span style="font-weight:900;color:${qty<=2?'#ef4444':'#0f172a'};">QTY: ${qty}</span>
        ${item.no_siri_jual ? `<span style="color:#3b82f6;font-size:9px;font-weight:700;">Siri Jual: ${esc(item.no_siri_jual)}</span>` : ''}
      </div>
      <div class="st-field"><label>Nama Item</label><input class="input" id="edNama" value="${esc(item.nama||'')}"></div>
      <div class="st-field"><label>Harga Jual (RM)</label><input class="input" type="number" step="0.01" id="edJual" value="${num(item.jual).toFixed(2)}"></div>
      <div style="display:flex;gap:8px;margin-top:4px;">
        <button class="st-btn primary" id="edSave" style="flex:1;"><i class="fas fa-floppy-disk"></i> KEMASKINI</button>
        <button class="st-btn blue" id="edPrint" style="flex:1;"><i class="fas fa-print"></i> CETAK LABEL</button>
      </div>
      <div style="margin-top:14px;color:#ef4444;font-weight:900;font-size:11px;"><i class="fas fa-clock-rotate-left"></i> REVERSE STOCK</div>
      <div style="display:flex;gap:8px;margin-top:6px;">
        <input class="input" id="edReverseSiri" placeholder="Cth: RMS-00001" style="flex:1;">
        <button class="st-act" id="edReverse" style="color:#ef4444;border-color:#ef444455;background:#ef444415;"><i class="fas fa-arrows-rotate"></i>REVERSE</button>
      </div>
      <button class="st-btn red" id="edDelete" style="margin-top:16px;"><i class="fas fa-trash-can"></i> PADAM ITEM</button>
    `;
    $('edSave').addEventListener('click', async () => {
      try {
        await db.collection('inventory_' + ownerID).doc(docId).update({
          nama: $('edNama').value.trim().toUpperCase(),
          jual: parseFloat($('edJual').value) || 0,
        });
        close('mEdit');
        snack('Stok berjaya dikemaskini');
      } catch(e) { snack('Gagal: ' + e.message, true); }
    });
    $('edPrint').addEventListener('click', () => printLabel(item));
    $('edReverse').addEventListener('click', async () => {
      const siri = $('edReverseSiri').value.trim().toUpperCase();
      if (!siri) { snack('Sila isi No. Siri', true); return; }
      if (String(item.no_siri_jual||'').toUpperCase() === siri) {
        try {
          await db.collection('inventory_' + ownerID).doc(docId).update({
            qty: num(item.qty) + 1,
            status: 'AVAILABLE',
            no_siri_jual: '',
            tkh_jual: '',
          });
          close('mEdit');
          snack('Stok berjaya di-reverse dari job ' + siri);
        } catch(e) { snack('Gagal: ' + e.message, true); }
      } else { snack('No. Siri tidak sepadan dengan item ini', true); }
    });
    $('edDelete').addEventListener('click', async () => {
      if (!confirm('Padam item "' + kod + '"?')) return;
      try {
        await db.collection('inventory_' + ownerID).doc(docId).delete();
        close('mEdit');
        snack('Item berjaya dipadam');
      } catch(e) { snack('Gagal: ' + e.message, true); }
    });
    open('mEdit');
  }

  // ── PRINT LABEL (RmsPrinter bila connect; fallback window.print) ──
  async function printLabel(item) {
    const kod = item.kod || '-';
    const nama = item.nama || '-';
    const jual = num(item.jual).toFixed(2);
    if (window.RmsPrinter && RmsPrinter.isConnected()) {
      try {
        await RmsPrinter.printRaw(escposStockLabel(kod, nama, jual));
        snack('Label dihantar ke printer');
        return;
      } catch(e){ snack('Gagal cetak: '+e.message, true); return; }
    }
    const w = window.open('', '_blank', 'width=400,height=300');
    if (!w) { snack('Popup disekat. Benarkan popup.', true); return; }
    w.document.write(`<!doctype html><html><head><title>Label ${kod}</title>
      <style>
        body{font-family:monospace;text-align:center;padding:12px;}
        h1{font-size:16px;margin:4px 0;}
        .line{border-top:2px dashed #000;margin:6px 0;}
        .kod{font-size:18px;font-weight:900;}
        .rm{font-size:20px;font-weight:900;}
        @media print { @page { size: 58mm auto; margin:2mm; } }
      </style></head><body>
      <h1>LABEL STOK</h1><div class="line"></div>
      <div class="kod">${esc(kod)}</div>
      <div>${esc(String(nama).substring(0,30))}</div>
      <div class="line"></div>
      <div class="rm">RM ${jual}</div>
      <div class="line"></div>
      <div style="font-size:10px;">~ RMS Pro ~</div>
      <script>window.onload=()=>setTimeout(()=>window.print(),100)<\/script>
      </body></html>`);
    w.document.close();
    snack('Label dihantar ke cetakan');
  }

  // ── HISTORY USED ──
  $('btnUsed').addEventListener('click', async () => {
    $('usedBody').innerHTML = '<div style="text-align:center;padding:20px;">Memuatkan…</div>';
    open('mUsed');
    try {
      const snap = await db.collection('stock_usage_' + ownerID).where('status', '==', 'USED').get();
      const list = [];
      snap.forEach(d => list.push(Object.assign({ _id: d.id }, d.data())));
      list.sort((a,b) => num(b.timestamp) - num(a.timestamp));
      const top = list.slice(0, 50);
      if (top.length === 0) { $('usedBody').innerHTML = '<div style="text-align:center;color:#94a3b8;padding:20px;">Tiada rekod guna.</div>'; return; }
      $('usedBody').innerHTML = '';
      top.forEach((d, i) => {
        const row = document.createElement('div');
        row.className = 'st-hist-row';
        row.style.background = '#f973160a';
        row.style.borderColor = '#f9731633';
        row.innerHTML = `
          <i class="fas fa-box-open" style="color:#f97316;"></i>
          <div style="flex:1;min-width:0;">
            <div style="color:#2563eb;font-size:9px;font-weight:900;">${esc(d.kod||'')}</div>
            <div style="font-size:11px;font-weight:700;">${esc(d.nama||'')}</div>
            <div style="font-size:9px;color:#94a3b8;">RM ${num(d.jual).toFixed(2)} • ${esc(d.tarikh||'')}</div>
          </div>
          <button class="st-act" style="color:#3b82f6;border-color:#3b82f655;background:#3b82f615;"><i class="fas fa-arrows-rotate"></i>REVERSE</button>
        `;
        row.querySelector('button').addEventListener('click', async () => {
          try {
            await db.collection('inventory_' + ownerID).doc(d.stock_doc_id||'').update({ status: 'AVAILABLE', tkh_guna: '' });
            await db.collection('stock_usage_' + ownerID).doc(d._id).update({ status: 'REVERSED', reversed_at: Date.now() });
            row.remove();
            snack('Stok "' + (d.nama||'') + '" di-reverse');
          } catch(e) { snack('Gagal: '+e.message, true); }
        });
        $('usedBody').appendChild(row);
      });
    } catch(e) { $('usedBody').innerHTML = '<div style="color:#ef4444;padding:20px;">'+esc(e.message)+'</div>'; }
  });

  // ── HISTORY RETURN ──
  $('btnReturn').addEventListener('click', async () => {
    $('returnBody').innerHTML = '<div style="text-align:center;padding:20px;">Memuatkan…</div>';
    open('mReturn');
    try {
      const all = [];
      for (const item of state.inventory) {
        const snap = await db.collection('inventory_' + ownerID).doc(item.id).collection('returns').orderBy('timestamp','desc').get();
        snap.forEach(d => all.push(Object.assign({}, d.data(), { _id: d.id, kod: item.kod||'', nama: item.nama||'', stock_doc_id: item.id })));
      }
      all.sort((a,b) => num(b.timestamp) - num(a.timestamp));
      const top = all.slice(0, 50);
      if (top.length === 0) { $('returnBody').innerHTML = '<div style="text-align:center;color:#94a3b8;padding:20px;">Tiada rekod return.</div>'; return; }
      $('returnBody').innerHTML = '';
      top.forEach(r => {
        const row = document.createElement('div');
        row.className = 'st-hist-row';
        row.style.background = '#ef44440a';
        row.style.borderColor = '#ef444433';
        row.innerHTML = `
          <i class="fas fa-rotate-left" style="color:#ef4444;"></i>
          <div style="flex:1;min-width:0;">
            <div style="color:#2563eb;font-size:9px;font-weight:900;">${esc(r.kod||'')}</div>
            <div style="font-size:11px;font-weight:700;">${esc(r.nama||'')}</div>
            <div style="font-size:9px;color:#f97316;font-weight:600;">QTY: ${num(r.qty)} • ${esc(r.reason||'-')}</div>
            <div style="font-size:9px;color:#94a3b8;">${esc(r.tarikh||'')}</div>
          </div>
          <button class="st-act" style="color:#3b82f6;border-color:#3b82f655;background:#3b82f615;"><i class="fas fa-arrows-rotate"></i>REVERSE</button>
        `;
        row.querySelector('button').addEventListener('click', async () => {
          try {
            const stockRef = db.collection('inventory_' + ownerID).doc(r.stock_doc_id);
            const ss = await stockRef.get();
            if (ss.exists) {
              const cur = num(ss.data().qty);
              await stockRef.update({ qty: cur + num(r.qty), status: 'AVAILABLE' });
            }
            await stockRef.collection('returns').doc(r._id).delete();
            row.remove();
            snack('Return "' + (r.nama||'') + '" di-reverse, +' + num(r.qty) + ' unit');
          } catch(e) { snack('Gagal: '+e.message, true); }
        });
        $('returnBody').appendChild(row);
      });
    } catch(e) { $('returnBody').innerHTML = '<div style="color:#ef4444;padding:20px;">'+esc(e.message)+'</div>'; }
  });

  // ── EVENTS ──
  $('stSearch').addEventListener('input', e => { state.search = e.target.value; filter(); render(); });

  // ── MODAL HELPERS ──
  function open(id){ $(id).classList.add('show'); }
  function close(id){ $(id).classList.remove('show'); }
  document.querySelectorAll('.st-modal-bg').forEach(bg => {
    bg.addEventListener('click', e => { if (e.target === bg) bg.classList.remove('show'); });
    bg.querySelectorAll('[data-close]').forEach(x => x.addEventListener('click', () => bg.classList.remove('show')));
  });
})();
