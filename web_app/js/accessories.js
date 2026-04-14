/* Accessories — port lib/screens/modules/accessories_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch') || '';
  if (!branch.includes('@')) { window.location.replace('index.html'); return; }
  const ownerID = branch.split('@')[0].toLowerCase();
  const shopID = branch.split('@')[1].toUpperCase();
  const storage = firebase.storage ? firebase.storage() : null;

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  function snack(msg, err=false){ const el=document.createElement('div'); el.className='ac-snack'+(err?' err':''); el.textContent=msg; document.body.appendChild(el); setTimeout(()=>el.remove(),2500); }

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

  function escposAccLabel(kod, nama, rm){
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
  function closeAll(){ document.querySelectorAll('.ac-modal-bg').forEach(m => m.classList.remove('is-open')); }
  document.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', () => $(b.getAttribute('data-close')).classList.remove('is-open')));

  let inventory = [], filtered = [], loaded = false;
  let pickedImageFile = null, pickedImageUrl = '';
  let currentEdit = null;

  function genKod(){
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let s = ''; for (let i=0;i<6;i++) s += chars[Math.floor(Math.random()*chars.length)];
    return 'STK-' + s;
  }
  function todayISO(){ const d = new Date(); const p = n => String(n).padStart(2,'0'); return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}`; }

  db.collection('accessories_'+ownerID).orderBy('timestamp','desc').onSnapshot(snap => {
    inventory = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    loaded = true;
    filterAndRender();
  });

  $('acSearch').addEventListener('input', e => {
    $('acClear').hidden = !e.target.value;
    filterAndRender();
  });
  $('acClear').addEventListener('click', () => { $('acSearch').value = ''; $('acClear').hidden = true; filterAndRender(); });
  $('acScan').addEventListener('click', () => {
    const code = prompt('Scan / taipkan kod atau siri:');
    if (code) { $('acSearch').value = code.trim().toUpperCase(); $('acClear').hidden = false; filterAndRender(); }
  });

  function filterAndRender(){
    const q = ($('acSearch').value || '').toLowerCase().trim();
    filtered = !q ? inventory.slice() : inventory.filter(d =>
      (d.kod||'').toString().toLowerCase().includes(q) ||
      (d.nama||'').toString().toLowerCase().includes(q) ||
      (d.no_siri_jual||'').toString().toLowerCase().includes(q));
    renderList();
    renderFoot();
  }

  function renderList(){
    const host = $('acList');
    if (!loaded) { host.innerHTML = `<div class="ac-empty"><i class="fas fa-spinner fa-spin"></i><div>Memuatkan...</div></div>`; return; }
    if (!filtered.length) { host.innerHTML = `<div class="ac-empty"><i class="fas fa-box-open"></i><div>Tiada item</div></div>`; return; }
    host.innerHTML = filtered.map((d, i) => {
      const qty = Number(d.qty || 0);
      const status = (d.status || '').toString().toUpperCase();
      const isLow = qty <= 2;
      let stCol = '#10b981', stTxt = 'AVAILABLE';
      if (status === 'TERJUAL') { stCol = '#dc2626'; stTxt = 'TERJUAL'; }
      else if (status === 'RETURNED') { stCol = '#f97316'; stTxt = 'RETURNED'; }
      else if (status === 'USED') { stCol = '#2563eb'; stTxt = 'USED'; }
      const cat = (d.category || '').toString();
      const jual = Number(d.jual || 0);
      const tkhM = d.tarikh_masuk || '', tkhJ = d.tkh_jual || '', siri = d.no_siri_jual || '';
      const supp = d.supplier || '';
      return `<div class="ac-card${isLow?' low':''}" data-idx="${i}">
        <div class="ac-qty">${qty}</div>
        <div class="ac-content">
          <div class="ac-row1">
            <div class="ac-kod">${esc(d.kod || '-')}</div>
            ${cat ? `<span class="ac-cat">${esc(cat)}</span>` : ''}
            <span class="ac-status" style="background:${stCol}26;color:${stCol};">${stTxt}</span>
          </div>
          <div class="ac-nama">${esc(d.nama || '-')}</div>
          <div class="ac-info"><span class="jual">Jual: RM ${jual.toFixed(2)}</span>${supp ? `<span class="supp">${esc(supp)}</span>` : ''}</div>
          ${(tkhM || tkhJ || siri) ? `<div class="ac-meta">${tkhM ? `Masuk: ${esc(tkhM)}` : ''}${tkhJ ? ` • Jual: ${esc(tkhJ)}` : ''}${siri ? `<span class="siri">#${esc(siri)}</span>` : ''}</div>` : ''}
        </div>
        <i class="fas fa-chevron-right ac-chev"></i>
      </div>`;
    }).join('');
    host.querySelectorAll('.ac-card').forEach(c => c.addEventListener('click', () => openEdit(filtered[+c.getAttribute('data-idx')])));
  }

  function renderFoot(){
    if (!filtered.length) { $('acFoot').hidden = true; return; }
    $('acFoot').hidden = false;
    const totalQty = filtered.reduce((s,d) => s + Number(d.qty || 0), 0);
    const totalJual = filtered.reduce((s,d) => s + Number(d.jual || 0) * Number(d.qty || 0), 0);
    $('acFoot').innerHTML = `
      <span class="ac-chip" style="background:rgba(100,116,139,.08);color:#64748b;">${filtered.length} item</span>
      <span class="ac-chip" style="background:rgba(37,99,235,.08);color:#2563eb;">QTY: ${totalQty}</span>
      <span class="ac-chip" style="background:rgba(16,185,129,.08);color:#10b981;flex:1;">Jual: RM ${totalJual.toFixed(0)}</span>`;
  }

  // ── Add Stock Modal ──
  $('btnAdd').addEventListener('click', () => openAdd(null));

  function openAdd(prefill){
    pickedImageFile = null; pickedImageUrl = '';
    $('imgPicker').style.backgroundImage = '';
    $('imgPicker').innerHTML = '<i class="fas fa-camera" style="font-size:24px;"></i><div style="font-size:9px;font-weight:700;">TAMBAH GAMBAR</div>';
    $('fKod').value = prefill?.kod || genKod();
    $('fNama').value = prefill?.nama || '';
    $('fJual').value = prefill?.jual != null ? Number(prefill.jual).toFixed(2) : '';
    $('fCat').value = 'ACCESSORIES';
    $('fTarikh').value = todayISO();
    $('addTitle').textContent = 'TAMBAH STOK';
    $('modalAdd').classList.add('is-open');
  }

  $('imgPicker').addEventListener('click', () => $('imgFile').click());
  $('imgFile').addEventListener('change', e => {
    const f = e.target.files[0]; if (!f) return;
    if (f.size > 100 * 1024) { snack('Gambar melebihi 100KB. Sila pilih gambar lebih kecil.', true); return; }
    pickedImageFile = f;
    const url = URL.createObjectURL(f);
    $('imgPicker').style.backgroundImage = `url('${url}')`;
    $('imgPicker').innerHTML = '';
  });

  $('kodCopy').addEventListener('click', () => {
    const v = $('fKod').value.trim();
    if (!v) return;
    navigator.clipboard.writeText(v).then(() => snack(`Kod "${v}" disalin`));
  });
  $('kodAuto').addEventListener('click', () => { $('fKod').value = genKod(); });
  $('kodScan').addEventListener('click', () => {
    const code = prompt('Scan / taipkan kod:');
    if (!code) return;
    const clean = code.trim().toUpperCase();
    closeAll();
    const existing = inventory.find(d => (d.kod||'').toString().toUpperCase() === clean);
    openAdd({ kod: clean, nama: existing?.nama, jual: existing?.jual });
  });

  async function uploadImage(file, kod){
    if (!storage) return '';
    const ts = Date.now();
    const ref = storage.ref().child(`inventory/${ownerID}/${kod}_${ts}.jpg`);
    const task = await ref.put(file, { contentType: 'image/jpeg' });
    return await task.ref.getDownloadURL();
  }

  $('saveStock').addEventListener('click', async () => {
    const kod = $('fKod').value.trim();
    if (!kod) { snack('Sila isi Kod Item', true); return; }
    $('saveLbl').textContent = 'MENYIMPAN...';
    try {
      let imgUrl = '';
      if (pickedImageFile) { try { imgUrl = await uploadImage(pickedImageFile, kod); } catch(_){} }
      await db.collection('accessories_'+ownerID).add({
        kod: kod.toUpperCase(),
        nama: $('fNama').value.trim().toUpperCase(),
        category: $('fCat').value,
        kos: 0,
        jual: parseFloat($('fJual').value) || 0,
        qty: 1,
        supplier: '',
        tarikh_masuk: $('fTarikh').value.trim(),
        tkh_jual: '',
        no_siri_jual: '',
        imageUrl: imgUrl,
        status: 'AVAILABLE',
        timestamp: Date.now(),
        shopID,
      });
      closeAll();
      snack('Stok berjaya ditambah');
    } catch(e){ snack('Ralat: '+e.message, true); }
    finally { $('saveLbl').textContent = 'SIMPAN STOK'; }
  });

  // ── Edit Modal ──
  function openEdit(item){
    currentEdit = item;
    const qty = Number(item.qty || 0);
    const isSold = (item.status || '').toString().toUpperCase() === 'TERJUAL';
    const kod = item.kod || '-';
    $('editTitle').textContent = `${kod}`;
    const stCol = isSold ? '#dc2626' : '#10b981';
    const stTxt = isSold ? 'TERJUAL' : 'AVAILABLE';
    let html = `<span class="ac-badge" style="color:${stCol};border-color:${stCol}4d;background:${stCol}26;">${stTxt}</span>
      <span style="color:${qty<=2?'#dc2626':'#0f172a'};font-size:11px;font-weight:900;">QTY: ${qty}</span>`;
    if (item.no_siri_jual) html += `<span style="color:#2563eb;font-size:9px;font-weight:700;">Siri Jual: ${esc(item.no_siri_jual)}</span>`;
    $('editStatusRow').innerHTML = html;
    $('eNama').value = item.nama || '';
    $('eJual').value = item.jual != null ? item.jual : 0;
    $('eSiri').value = '';
    $('modalEdit').classList.add('is-open');
  }

  $('eUpdate').addEventListener('click', async () => {
    await db.collection('accessories_'+ownerID).doc(currentEdit.id).update({
      nama: $('eNama').value.trim().toUpperCase(),
      jual: parseFloat($('eJual').value) || 0,
    });
    closeAll();
    snack('Stok berjaya dikemaskini');
  });

  $('ePrint').addEventListener('click', async () => {
    const it = currentEdit;
    const kod = it.kod || '-', nama = it.nama || '-', jual = Number(it.jual || 0).toFixed(2);
    if (window.RmsPrinter && RmsPrinter.isConnected()) {
      try {
        await RmsPrinter.printRaw(escposAccLabel(kod, nama, jual));
        snack('Label dihantar ke printer');
        return;
      } catch(e){ snack('Gagal cetak: '+e.message, true); return; }
    }
    const w = window.open('', '_blank', 'width=320,height=420');
    w.document.write(`<html><head><title>LABEL ${esc(kod)}</title><style>
      body{font-family:monospace;text-align:center;padding:10px;}
      .big{font-size:20px;font-weight:900;}
      hr{border:none;border-top:1px dashed #000;}
    </style></head><body>
      <div class="big">LABEL STOK</div><hr>
      <div class="big">${esc(kod)}</div>
      <div>${esc(nama.length>30?nama.slice(0,30):nama)}</div><hr>
      <div class="big">RM ${jual}</div><hr>
      <div>~ RMS Pro ~</div>
      <script>window.print();<\/script>
    </body></html>`);
    w.document.close();
  });

  $('eReverse').addEventListener('click', async () => {
    const siri = $('eSiri').value.trim().toUpperCase();
    if (!siri) { snack('Sila isi No. Siri', true); return; }
    const it = currentEdit;
    if ((it.no_siri_jual || '').toString().toUpperCase() !== siri) {
      snack('No. Siri tidak sepadan dengan item ini', true); return;
    }
    const currentQty = Number(it.qty || 0);
    await db.collection('accessories_'+ownerID).doc(it.id).update({
      qty: currentQty + 1, status: 'AVAILABLE', no_siri_jual: '', tkh_jual: '',
    });
    closeAll();
    snack('Stok berjaya di-reverse dari job '+siri);
  });

  $('eDelete').addEventListener('click', async () => {
    const kod = currentEdit.kod || '-';
    if (!confirm(`Adakah anda pasti untuk padam "${kod}"?`)) return;
    await db.collection('accessories_'+ownerID).doc(currentEdit.id).delete();
    closeAll();
    snack('Item berjaya dipadam');
  });

  // ── History Used ──
  $('btnHistUsed').addEventListener('click', async () => {
    $('usedList').innerHTML = '<div class="ac-empty"><i class="fas fa-spinner fa-spin"></i></div>';
    $('modalUsed').classList.add('is-open');
    try {
      const snap = await db.collection('acc_usage_'+ownerID).where('status','==','USED').get();
      let list = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      list.sort((a,b) => (b.timestamp||0) - (a.timestamp||0));
      list = list.slice(0, 50);
      if (!list.length) { $('usedList').innerHTML = `<div class="ac-empty"><div>Tiada rekod diguna</div></div>`; return; }
      $('usedList').innerHTML = list.map((d, i) => `
        <div class="ac-hist-item" style="background:rgba(245,158,11,.04);border:1px solid rgba(245,158,11,.2);" data-i="${i}">
          <i class="fas fa-box-open" style="color:#f59e0b;"></i>
          <div style="flex:1;">
            <div style="color:#f59e0b;font-size:9px;font-weight:900;">${esc(d.kod||'')}</div>
            <div style="color:#0f172a;font-size:11px;font-weight:700;">${esc(d.nama||'')}</div>
            <div style="color:#cbd5e1;font-size:9px;">RM ${Number(d.jual||0).toFixed(2)} • ${esc(d.tarikh||'')}</div>
          </div>
          <button class="ac-act-btn blue" data-rev="${i}" style="margin:0;"><i class="fas fa-arrows-rotate"></i> REVERSE</button>
        </div>`).join('');
      $('usedList').querySelectorAll('[data-rev]').forEach(b => b.addEventListener('click', async () => {
        const d = list[+b.getAttribute('data-rev')];
        if (d.stock_doc_id) {
          await db.collection('accessories_'+ownerID).doc(d.stock_doc_id).update({ status: 'AVAILABLE', tkh_guna: '' });
        }
        await db.collection('acc_usage_'+ownerID).doc(d._id).update({ status: 'REVERSED', reversed_at: Date.now() });
        b.closest('.ac-hist-item').remove();
        snack(`Stok "${d.nama || ''}" di-reverse`);
      }));
    } catch(e){ $('usedList').innerHTML = `<div class="ac-empty"><div>Ralat: ${esc(e.message)}</div></div>`; }
  });

  // ── History Return ──
  $('btnHistReturn').addEventListener('click', async () => {
    $('returnList').innerHTML = '<div class="ac-empty"><i class="fas fa-spinner fa-spin"></i></div>';
    $('modalReturn').classList.add('is-open');
    try {
      const all = [];
      for (const it of inventory) {
        const snap = await db.collection('accessories_'+ownerID).doc(it.id).collection('returns').orderBy('timestamp','desc').get();
        snap.forEach(d => all.push({ ...d.data(), _id: d.id, kod: it.kod || '', nama: it.nama || '', stock_doc_id: it.id }));
      }
      all.sort((a,b) => (b.timestamp||0) - (a.timestamp||0));
      const list = all.slice(0, 50);
      if (!list.length) { $('returnList').innerHTML = `<div class="ac-empty"><div>Tiada rekod return</div></div>`; return; }
      $('returnList').innerHTML = list.map((r, i) => `
        <div class="ac-hist-item" style="background:rgba(220,38,38,.04);border:1px solid rgba(220,38,38,.2);">
          <i class="fas fa-rotate-left" style="color:#dc2626;"></i>
          <div style="flex:1;">
            <div style="color:#f59e0b;font-size:9px;font-weight:900;">${esc(r.kod)}</div>
            <div style="color:#0f172a;font-size:11px;font-weight:700;">${esc(r.nama)}</div>
            <div style="color:#f97316;font-size:9px;font-weight:600;">QTY: ${esc(r.qty)} • ${esc(r.reason || '-')}</div>
            <div style="color:#cbd5e1;font-size:9px;">${esc(r.tarikh || '')}</div>
          </div>
          <button class="ac-act-btn blue" data-rev="${i}" style="margin:0;"><i class="fas fa-arrows-rotate"></i> REVERSE</button>
        </div>`).join('');
      $('returnList').querySelectorAll('[data-rev]').forEach(b => b.addEventListener('click', async () => {
        const r = list[+b.getAttribute('data-rev')];
        const rQty = Number(r.qty || 0);
        const stockSnap = await db.collection('accessories_'+ownerID).doc(r.stock_doc_id).get();
        if (stockSnap.exists) {
          const cur = Number(stockSnap.data().qty || 0);
          await db.collection('accessories_'+ownerID).doc(r.stock_doc_id).update({ qty: cur + rQty, status: 'AVAILABLE' });
        }
        await db.collection('accessories_'+ownerID).doc(r.stock_doc_id).collection('returns').doc(r._id).delete();
        b.closest('.ac-hist-item').remove();
        snack(`Return "${r.nama}" di-reverse, +${rQty} unit`);
      }));
    } catch(e){ $('returnList').innerHTML = `<div class="ac-empty"><div>Ralat: ${esc(e.message)}</div></div>`; }
  });
})();
