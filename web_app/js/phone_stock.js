/* Phone Stock — port rmsproapp/lib/screens/modules/phone_stock_screen.dart */
(function(){
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID  = (shopRaw  || '').toUpperCase();
  const storage = firebase.storage ? firebase.storage() : null;

  // Firestore collection refs (1:1 with Dart)
  const C = {
    stock:        'phone_stock_'         + ownerID,
    sales:        'phone_sales_'         + ownerID,
    salesTrash:   'phone_sales_trash_'   + ownerID,
    trash:        'phone_trash_'         + ownerID,
    categories:   'phone_categories_'    + ownerID,
    suppliers:    'phone_suppliers_'     + ownerID,
    returns:      'phone_returns_'       + ownerID,
    transfers:    'phone_transfers_'     + ownerID,
    savedBranch:  'saved_branches_'      + ownerID,
    shops:        'shops_'               + ownerID,
    dealers:      'saas_dealers',
  };

  const state = {
    inventory: [],
    filtered: [],
    incoming: [],
    categories: ['BARU','SECOND HAND'],
    suppliers: [],
    staffList: [],
    selectedModel: 'SEMUA',
    selectedKategori: 'SEMUA',
    search: '',
    autoPrintBarcode: localStorage.getItem('ps_auto_print_barcode') === '1',
    autoPrintDetail:  localStorage.getItem('ps_auto_print_detail')  === '1',
  };

  const $ = id => document.getElementById(id);
  const esc = s => String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const UP = s => String(s||'').toUpperCase();
  const num = v => { const n=parseFloat(v); return isNaN(n)?0:n; };
  const now = () => Date.now();
  function tsMs(v){ if(v==null) return 0; if(typeof v==='number') return v; if(v && typeof v.toMillis==='function') return v.toMillis(); if(v && v.seconds!=null) return v.seconds*1000; const n=Number(v); return isNaN(n)?0:n;}
  function fmtDate(ms, withTime=false){
    if(!ms) return '-';
    const d=new Date(ms); const p=n=>String(n).padStart(2,'0');
    const base = `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)}`;
    return withTime ? base+' '+p(d.getHours())+':'+p(d.getMinutes()) : base;
  }
  function fmtISODate(ms){ const d=new Date(ms); const p=n=>String(n).padStart(2,'0'); return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}`; }
  function fmtHM(ms){ const d=new Date(ms); const p=n=>String(n).padStart(2,'0'); return `${p(d.getHours())}:${p(d.getMinutes())}`; }
  function snack(msg, err=false){
    const el=document.createElement('div'); el.className='ps-snack'+(err?' err':''); el.textContent=msg;
    document.body.appendChild(el); setTimeout(()=>el.remove(),2800);
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

  // Build simple ESC/POS label bytes for phone stock
  function escposLabel(lines){
    const ESC_INIT = '\x1B\x40';
    const ESC_CENTER = '\x1B\x61\x01';
    const ESC_LEFT = '\x1B\x61\x00';
    const ESC_BOLD_ON = '\x1B\x45\x01';
    const ESC_BOLD_OFF = '\x1B\x45\x00';
    const ESC_DBL = '\x1B\x21\x30';
    const ESC_NORMAL = '\x1B\x21\x00';
    const CUT = '\x1D\x56\x00';
    let out = ESC_INIT + ESC_CENTER;
    lines.forEach(ln => {
      if (ln && ln.big) out += ESC_DBL + ESC_BOLD_ON + (ln.text||'') + '\n' + ESC_NORMAL + ESC_BOLD_OFF;
      else out += (ln && ln.text != null ? ln.text : ln || '') + '\n';
    });
    out += '\n\n\n' + CUT;
    return new TextEncoder().encode(out);
  }
  function genKod(){
    const ch='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let r=''; for(let i=0;i<6;i++) r+=ch[Math.floor(Math.random()*ch.length)];
    return 'PH-'+r;
  }

  // ── Parse barcode (plain-text, JSON, delimited) ──
  function parseBarcode(raw){
    const out={}; const t=String(raw||'').trim();
    try{ const j=JSON.parse(t); if(j && typeof j==='object'){
      if(j.imei) out.imei=String(j.imei); if(j.IMEI) out.imei=String(j.IMEI);
      if(j.model) out.nama=String(j.model); if(j.name) out.nama=String(j.name);
      if(j.storage) out.storage=String(j.storage);
      if(j.color) out.warna=String(j.color); if(j.colour) out.warna=String(j.colour);
      return out;
    }}catch(e){}
    for(const d of [',','|',';']){
      if(t.includes(d)){
        const parts=t.split(d).map(s=>s.trim()).filter(Boolean);
        for(const p of parts){
          if(/^\d{15}$/.test(p)) out.imei=p;
          else if(/^\d+\s*(GB|TB)$/i.test(p)) out.storage=p.toUpperCase();
          else if(p.length > (out.nama?out.nama.length:0)) out.nama=p;
        }
        return out;
      }
    }
    if(/^\d{15}$/.test(t)){ out.imei=t; return out; }
    const mI=t.match(/\b(\d{15})\b/); if(mI) out.imei=mI[1];
    const mS=t.match(/\b(\d+\s*(GB|TB))\b/i); if(mS) out.storage=mS[1].toUpperCase();
    let rem=t;
    if(out.imei) rem=rem.replace(out.imei,'');
    if(out.storage) rem=rem.replace(/\b\d+\s*(GB|TB)\b/gi,'');
    rem=rem.replace(/[,|;\s]+/g,' ').trim();
    if(rem.length>2) out.nama=rem;
    return out;
  }

  // ── Load categories / suppliers / staff ──
  async function loadCategories(){
    try{
      const s=await db.collection(C.categories).orderBy('name').get();
      const custom=[]; s.forEach(d=>{ const n=UP(d.data().name||''); if(n) custom.push(n); });
      state.categories=['BARU','SECOND HAND',...custom.filter(c=>c!=='BARU'&&c!=='SECOND HAND')];
    }catch(e){}
  }
  async function loadSuppliers(){
    try{
      const s=await db.collection(C.suppliers).orderBy('name').get();
      const list=[]; s.forEach(d=>{ const n=UP(d.data().name||''); if(n) list.push(n); });
      state.suppliers=list;
    }catch(e){}
  }
  async function loadStaff(){
    try{
      const s=await db.collection(C.shops).doc(shopID).get();
      if(s.exists){
        const d=s.data()||{};
        if(Array.isArray(d.staffList)) state.staffList=d.staffList.map(x=>typeof x==='string'?x:(x.name||x.nama||'')).filter(Boolean);
      }
      if(!state.staffList.length){
        const dr=await db.collection(C.dealers).doc(ownerID).get();
        if(dr.exists){ const dd=dr.data()||{}; if(Array.isArray(dd.staffList)) state.staffList=dd.staffList.map(x=>typeof x==='string'?x:(x.name||x.nama||'')).filter(Boolean); }
      }
    }catch(e){}
  }

  // ── Main stock listener ──
  db.collection(C.stock).orderBy('timestamp','desc').onSnapshot(snap=>{
    const list=[];
    snap.forEach(d=>{
      const data=d.data()||{};
      if(UP(data.shopID||'')!==shopID) return;
      if(UP(data.status||'')==='SOLD') return;
      list.push({id:d.id, ...data});
    });
    state.inventory=list; applyFilter(); render();
  },err=>console.warn('stock:',err));

  // Incoming transfers
  db.collection(C.transfers).where('toShopID','==',shopID).where('status','==','PENDING').onSnapshot(snap=>{
    const list=[]; snap.forEach(d=>list.push({id:d.id, ...(d.data()||{})}));
    state.incoming=list; render();
  },err=>{});

  function modelList(){
    const set=new Set();
    state.inventory.forEach(d=>{ const n=UP(d.nama||''); if(n) set.add(n); });
    return ['SEMUA', ...Array.from(set).sort()];
  }

  function applyFilter(){
    let data=state.inventory.slice();
    if(state.selectedModel!=='SEMUA') data=data.filter(d=>UP(d.nama||'')===state.selectedModel);
    if(state.selectedKategori!=='SEMUA') data=data.filter(d=>UP(d.kategori||'')===state.selectedKategori);
    const q=state.search.toLowerCase().trim();
    if(q) data=data.filter(d=>
      String(d.kod||'').toLowerCase().includes(q) ||
      String(d.nama||'').toLowerCase().includes(q) ||
      String(d.imei||'').toLowerCase().includes(q));
    state.filtered=data;
  }

  function statusColor(s){ s=UP(s); return s==='SOLD'?'var(--ps-red)':s==='RESERVED'?'var(--ps-yellow)':'var(--ps-green)'; }
  function katColor(k){ return UP(k)==='SECOND HAND'?'var(--ps-yellow)':'var(--ps-cyan)'; }

  // ── Render grid + footer + filters ──
  function render(){
    // model dropdown
    const mSel=$('filterModel'); const cur=state.selectedModel;
    mSel.innerHTML=modelList().map(m=>`<option value="${esc(m)}"${m===cur?' selected':''}>${esc(m)}</option>`).join('');
    // kategori dropdown
    const kSel=$('filterKategori'); const kCur=state.selectedKategori;
    kSel.innerHTML=['SEMUA',...state.categories].map(k=>`<option value="${esc(k)}"${k===kCur?' selected':''}>${esc(k)}</option>`).join('');

    const grid=$('psGrid'); const empty=$('psEmpty');
    grid.innerHTML='';
    const items=[...state.incoming.map(x=>({_inc:true,...x})), ...state.filtered];
    if(!items.length){ empty.hidden=false; } else empty.hidden=true;
    for(const d of items){
      if(d._inc) grid.appendChild(cardIncoming(d)); else grid.appendChild(cardPhone(d));
    }

    // footer
    const total=state.filtered.length;
    const avail=state.filtered.filter(d=>UP(d.status||'')==='AVAILABLE').length;
    const reserved=state.filtered.filter(d=>UP(d.status||'')==='RESERVED').length;
    let totalJual=0; state.filtered.forEach(d=>{ totalJual+=num(d.jual); });
    $('psFooter').innerHTML=`
      <div>
        <span class="ps-foot-badge" style="background:rgba(37,99,235,.15);color:var(--ps-primary)">${total} UNIT</span>
        <span class="ps-foot-badge" style="background:rgba(16,185,129,.15);color:var(--ps-green)">${avail} ADA</span>
        ${reserved>0?`<span class="ps-foot-badge" style="background:rgba(245,158,11,.15);color:var(--ps-yellow)">${reserved} RESERVED</span>`:''}
      </div>
      <div style="color:var(--ps-green);font-weight:900;font-size:11px;">Jumlah: RM${totalJual.toFixed(2)}</div>`;

    // settings icon highlight
    $('btnSettings').classList.toggle('active', state.autoPrintBarcode||state.autoPrintDetail);
  }

  function cardPhone(d){
    const el=document.createElement('div'); el.className='ps-card';
    const status=UP(d.status||'AVAILABLE');
    const kategori=UP(d.kategori||'');
    const img=d.imageUrl||'';
    el.innerHTML=`
      <div class="ps-card__img">
        ${img?`<img src="${esc(img)}" onerror="this.style.display='none'">`:`<i class="fas fa-mobile-screen-button"></i>`}
        <span class="ps-badge status-right" style="background:${statusColor(status)}">${esc(status)}</span>
        ${kategori?`<span class="ps-badge kat-left" style="background:${katColor(kategori)}">${esc(kategori)}</span>`:''}
      </div>
      <div style="padding:6px 8px 2px;">
        <div style="font-weight:900;font-size:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${esc(d.nama||'-')}</div>
        <div style="color:var(--ps-green);font-weight:900;font-size:11px;">RM${num(d.jual).toFixed(2)}</div>
      </div>
      <div class="ps-card__actions">
        <button class="btn-eye"  style="background:rgba(37,99,235,.1);border-color:rgba(37,99,235,.25);color:var(--ps-primary)"  title="Lihat"><i class="fas fa-eye"></i></button>
        <button class="btn-edit" style="background:rgba(59,130,246,.1);border-color:rgba(59,130,246,.25);color:var(--ps-blue)"    title="Edit"><i class="fas fa-pen-to-square"></i></button>
        <button class="btn-prn"  style="background:rgba(245,158,11,.1);border-color:rgba(245,158,11,.25);color:var(--ps-yellow)"  title="Cetak"><i class="fas fa-barcode"></i></button>
      </div>`;
    el.querySelector('.btn-eye').addEventListener('click',e=>{e.stopPropagation();showDetailModal(d);});
    el.querySelector('.btn-edit').addEventListener('click',e=>{e.stopPropagation();showEditModal(d);});
    el.querySelector('.btn-prn').addEventListener('click',e=>{e.stopPropagation();showPrintDialog(d);});
    // long press => return/transfer (desktop: right-click)
    el.addEventListener('contextmenu',e=>{e.preventDefault();showLongPressOptions(d);});
    let pressTimer=null;
    el.addEventListener('touchstart',()=>{pressTimer=setTimeout(()=>showLongPressOptions(d),650);});
    el.addEventListener('touchend',()=>{if(pressTimer) clearTimeout(pressTimer);});
    return el;
  }

  function cardIncoming(d){
    const el=document.createElement('div'); el.className='ps-card ps-incoming';
    const img=d.imageUrl||'';
    el.innerHTML=`
      <div class="ps-card__img" style="filter:grayscale(1);">
        ${img?`<img src="${esc(img)}">`:`<i class="fas fa-mobile-screen-button"></i>`}
        <span class="ps-badge status-right" style="background:var(--ps-yellow)">INCOMING</span>
        <span class="ps-badge kat-left" style="background:rgba(0,0,0,.55)">Dari: ${esc(d.fromShopID||'-')}</span>
      </div>
      <div style="padding:6px 8px;font-weight:900;font-size:11px;">${esc(d.nama||'-')}</div>
      <div style="padding:0 6px 6px;">
        <button class="btn-accept" style="width:100%;padding:6px;border-radius:6px;border:none;background:var(--ps-green);color:#fff;font-weight:900;cursor:pointer;"><i class="fas fa-check"></i> TERIMA</button>
      </div>`;
    el.querySelector('.btn-accept').addEventListener('click',()=>acceptTransfer(d,d.id));
    return el;
  }

  // ── Modal helpers ──
  function openModal(html,level=1){
    const bg=level===2?$('modalBg2'):$('modalBg');
    const box=level===2?$('modalBox2'):$('modalBox');
    box.innerHTML=html; bg.classList.add('is-open');
    bg.onclick=e=>{ if(e.target===bg) closeModal(level); };
  }
  function closeModal(level=1){
    const bg=level===2?$('modalBg2'):$('modalBg');
    bg.classList.remove('is-open');
  }

  // ── Detail modal ──
  function showDetailModal(d){
    const img=d.imageUrl||''; const status=UP(d.status||'AVAILABLE');
    const html=`
      <h3><i class="fas fa-mobile-screen-button" style="color:var(--ps-primary)"></i> ${esc(d.nama||'-')}
        <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
      ${img?`<img src="${esc(img)}" style="width:100%;max-height:280px;object-fit:cover;border-radius:10px;margin-bottom:10px;">`:''}
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">
        <span style="padding:3px 8px;border-radius:6px;font-weight:900;font-size:10px;background:${statusColor(status)}33;color:${statusColor(status)}">${esc(status)}</span>
        <span style="color:var(--ps-green);font-weight:900;font-size:18px;">RM${num(d.jual).toFixed(2)}</span>
      </div>
      <div class="ps-detail-row"><b>Kod</b><span>${esc(d.kod||'-')}</span></div>
      ${d.kategori?`<div class="ps-detail-row"><b>Kategori</b><span>${esc(UP(d.kategori))}</span></div>`:''}
      ${d.imei?`<div class="ps-detail-row"><b>IMEI</b><span>${esc(d.imei)}</span></div>`:''}
      ${d.warna?`<div class="ps-detail-row"><b>Warna</b><span>${esc(d.warna)}</span></div>`:''}
      ${d.storage?`<div class="ps-detail-row"><b>Storage</b><span>${esc(d.storage)}</span></div>`:''}
      <div class="ps-detail-row"><b>Tarikh Masuk</b><span>${esc(d.tarikh_masuk||fmtDate(tsMs(d.timestamp)))}</span></div>
      ${d.supplier?`<div class="ps-detail-row"><b>Supplier</b><span>${esc(d.supplier)}</span></div>`:''}
      ${d.staffMasuk?`<div class="ps-detail-row"><b>Staff Masuk</b><span>${esc(d.staffMasuk)}</span></div>`:''}
      ${d.nota?`<div class="ps-detail-row"><b>Nota</b><span>${esc(d.nota)}</span></div>`:''}
      <div class="ps-actions">
        <button class="btn-save" data-a="edit" style="background:var(--ps-blue)"><i class="fas fa-pen-to-square"></i> EDIT</button>
        <button class="btn-save" data-a="print"><i class="fas fa-barcode"></i> BARCODE</button>
      </div>`;
    openModal(html);
    $('modalBox').querySelector('[data-a=edit]').onclick=()=>{closeModal();showEditModal(d);};
    $('modalBox').querySelector('[data-a=print]').onclick=()=>{closeModal();showPrintDialog(d);};
  }
  window.__psCloseModal=closeModal;

  // ── Add/Edit modal ──
  function showAddModal(){
    const state2={ kod:genKod(), nama:'', imei:'', warna:'', storage:'', jual:'', nota:'', kategori:state.categories[0]||'BARU', supplier:state.suppliers[0]||'', staffMasuk:state.staffList[0]||'', imageFile:null, imagePreview:'' };
    openAddEditModal('add', state2, null);
  }
  function showEditModal(item){
    const state2={
      id:item.id, kod:item.kod||'', nama:item.nama||'', imei:item.imei||'', warna:item.warna||'', storage:item.storage||'',
      jual:item.jual||'', nota:item.nota||'', status:UP(item.status||'AVAILABLE'),
      kategori:UP(item.kategori||'BARU'), supplier:item.supplier||'', staffJual:item.staffJual||state.staffList[0]||'',
      imageFile:null, imagePreview:item.imageUrl||'', imageUrl:item.imageUrl||'',
    };
    if(!state.categories.includes(state2.kategori)) state2.kategori=state.categories[0];
    openAddEditModal('edit', state2, item);
  }

  function openAddEditModal(mode, s, original){
    const isEdit=mode==='edit';
    const statusOptions=['AVAILABLE','SOLD','RESERVED'];
    const statusCol={AVAILABLE:'var(--ps-green)',SOLD:'var(--ps-red)',RESERVED:'var(--ps-yellow)'};
    function render2(){
      const html=`
        <h3>${isEdit?'<i class="fas fa-pen-to-square" style="color:var(--ps-yellow)"></i> Edit Stok':'<i class="fas fa-mobile-screen-button" style="color:var(--ps-primary)"></i> Tambah Stok Telefon'}
          <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
        <div class="ps-img-drop" id="imgDrop">
          ${s.imagePreview?`<img src="${esc(s.imagePreview)}">`:`<i class="fas fa-camera fa-2x"></i><div>Tekan untuk pilih gambar</div>`}
        </div>
        <div class="ps-field"><label><i class="fas fa-tag"></i> Kategori</label>
          <div class="ps-row-inline">
            <select id="fKategori">${state.categories.map(c=>`<option value="${esc(c)}"${c===s.kategori?' selected':''}>${esc(c)}</option>`).join('')}</select>
            <button class="ps-mini-btn" id="addKat" style="color:var(--ps-green);border-color:rgba(16,185,129,.4);background:rgba(16,185,129,.1)"><i class="fas fa-plus"></i> CUSTOM</button>
          </div>
        </div>
        ${isEdit?'':`<div class="ps-field"><label><i class="fas fa-truck"></i> Supplier</label>
          <div class="ps-row-inline">
            <select id="fSupplier"><option value="">-- Pilih supplier --</option>${state.suppliers.map(x=>`<option value="${esc(x)}"${x===s.supplier?' selected':''}>${esc(x)}</option>`).join('')}</select>
            <button class="ps-mini-btn" id="addSup" style="color:var(--ps-green);border-color:rgba(16,185,129,.4);background:rgba(16,185,129,.1)"><i class="fas fa-plus"></i> TAMBAH</button>
          </div>
        </div>`}
        <div class="ps-field"><label><i class="fas fa-barcode"></i> Kod Item</label>
          <div class="ps-row-inline">
            <input id="fKod" ${isEdit?'readonly':''} value="${esc(s.kod)}" placeholder="Cth: PH-ABC123">
            ${isEdit?'':`<button class="ps-mini-btn" id="btnAuto" style="color:var(--ps-cyan);border-color:rgba(6,182,212,.4);background:rgba(6,182,212,.1)"><i class="fas fa-rotate"></i> AUTO</button>
            <button class="ps-mini-btn" id="btnScan2" style="color:var(--ps-primary);border-color:rgba(37,99,235,.4);background:rgba(37,99,235,.1)"><i class="fas fa-qrcode"></i> SCAN</button>`}
          </div>
        </div>
        ${isEdit?'':`<div class="ps-field"><label><i class="fas fa-user"></i> Staff</label>
          <select id="fStaff"><option value="">-- Pilih --</option>${state.staffList.map(x=>`<option value="${esc(x)}"${x===s.staffMasuk?' selected':''}>${esc(x)}</option>`).join('')}</select>
        </div>`}
        <div class="ps-field"><label><i class="fas fa-mobile-screen-button"></i> Nama Telefon</label><input id="fNama" value="${esc(s.nama)}" placeholder="Cth: iPhone 13 Pro Max"></div>
        <div class="ps-field"><label><i class="fas fa-hashtag"></i> IMEI</label><input id="fImei" value="${esc(s.imei)}" inputmode="numeric" placeholder="No IMEI telefon"></div>
        <div class="ps-row2">
          <div class="ps-field"><label><i class="fas fa-palette"></i> Warna</label><input id="fWarna" value="${esc(s.warna)}" placeholder="Cth: Black"></div>
          <div class="ps-field"><label><i class="fas fa-hard-drive"></i> Storage</label><input id="fStorage" value="${esc(s.storage)}" placeholder="Cth: 128GB"></div>
        </div>
        <div class="ps-field"><label><i class="fas fa-money-bill"></i> Harga Jual (RM)</label><input id="fJual" type="number" step="0.01" value="${esc(s.jual)}" placeholder="0.00"></div>
        <div class="ps-field"><label><i class="fas fa-sticky-note"></i> Nota</label><input id="fNota" value="${esc(s.nota)}" placeholder="Nota tambahan (pilihan)"></div>
        ${isEdit?`
          <div class="ps-field"><label><i class="fas fa-flag"></i> Status</label>
            <div class="ps-status-btns" id="statusBtns">${statusOptions.map(st=>`<button data-s="${st}" class="${st===s.status?'active':''}" style="${st===s.status?`background:${statusCol[st]}`:''}">${st}</button>`).join('')}</div>
          </div>
          ${s.status==='SOLD'?`<div class="ps-field"><label><i class="fas fa-user-tie"></i> Staff Jual</label>
            <select id="fStaffJual"><option value="">-- Pilih --</option>${state.staffList.map(x=>`<option value="${esc(x)}"${x===s.staffJual?' selected':''}>${esc(x)}</option>`).join('')}</select>
          </div>`:''}
          <div class="ps-actions">
            <button class="btn-save" id="btnSave"><i class="fas fa-check"></i> KEMASKINI</button>
            <button class="btn-del" id="btnDel"><i class="fas fa-trash"></i></button>
          </div>
        `:`
          <div class="ps-actions">
            <button class="btn-save" id="btnSave"><i class="fas fa-floppy-disk"></i> SIMPAN</button>
          </div>
        `}`;
      openModal(html);
      bindAE();
    }
    function bindAE(){
      const box=$('modalBox');
      const drop=box.querySelector('#imgDrop');
      drop.onclick=()=>{
        const f=$('fileImg');
        f.value=''; f.onchange=async()=>{
          const file=f.files[0]; if(!file) return;
          if(file.size>400*1024){ snack('Gambar melebihi 400KB. Pilih yang lebih kecil.', true); return; }
          s.imageFile=file;
          s.imagePreview=await new Promise(res=>{const r=new FileReader(); r.onload=e=>res(e.target.result); r.readAsDataURL(file);});
          render2();
        };
        f.click();
      };
      box.querySelector('#addKat').onclick=async()=>{
        const name=UP((prompt('Nama kategori baru:')||'').trim());
        if(!name) return;
        if(!state.categories.includes(name)){
          await db.collection(C.categories).add({name, timestamp:now()});
          state.categories.push(name);
        }
        s.kategori=name; render2();
      };
      if(!isEdit){
        box.querySelector('#addSup').onclick=async()=>{
          const name=UP((prompt('Nama supplier baru:')||'').trim());
          if(!name) return;
          if(!state.suppliers.includes(name)){
            await db.collection(C.suppliers).add({name, timestamp:now()});
            state.suppliers.push(name);
          }
          s.supplier=name; render2();
        };
        box.querySelector('#btnAuto').onclick=()=>{ s.kod=genKod(); render2(); };
        box.querySelector('#btnScan2').onclick=()=>{
          const raw=prompt('Tampal data barcode/IMEI:');
          if(!raw) return;
          const p=parseBarcode(raw);
          if(p.imei && !s.imei) s.imei=p.imei;
          if(p.nama && !s.nama) s.nama=UP(p.nama);
          if(p.storage && !s.storage) s.storage=UP(p.storage);
          if(p.warna && !s.warna) s.warna=UP(p.warna);
          const keys=Object.keys(p);
          if(keys.length) snack('Auto-detect: '+keys.join(', ')); else snack('Tiada data dikesan', true);
          render2();
        };
      }
      if(isEdit){
        box.querySelectorAll('#statusBtns button').forEach(b=>{ b.onclick=()=>{ s.status=b.dataset.s; render2(); }; });
        box.querySelector('#btnDel').onclick=()=>{ closeModal(); confirmDelete(original); };
      }
      box.querySelector('#btnSave').onclick=()=>saveAE(s, isEdit, original);
    }
    render2();
  }

  async function uploadImage(file, kod){
    if(!storage) throw new Error('Storage unavailable');
    const ref=storage.ref().child(`phone_stock/${ownerID}/${kod}_${now()}.jpg`);
    const b64=await new Promise(res=>{const r=new FileReader(); r.onload=e=>res(e.target.result); r.readAsDataURL(file);});
    await ref.putString(b64, 'data_url', {contentType: file.type||'image/jpeg'});
    return await ref.getDownloadURL();
  }

  async function saveAE(s, isEdit, original){
    // Collect latest values
    const box=$('modalBox');
    s.kod=UP(box.querySelector('#fKod').value.trim());
    s.nama=UP(box.querySelector('#fNama').value.trim());
    s.imei=box.querySelector('#fImei').value.trim();
    s.warna=UP(box.querySelector('#fWarna').value.trim());
    s.storage=UP(box.querySelector('#fStorage').value.trim());
    s.jual=num(box.querySelector('#fJual').value);
    s.nota=box.querySelector('#fNota').value.trim();
    s.kategori=box.querySelector('#fKategori').value;
    if(!isEdit){
      s.supplier=box.querySelector('#fSupplier').value;
      s.staffMasuk=box.querySelector('#fStaff').value;
    }
    if(isEdit && s.status==='SOLD'){
      const sel=box.querySelector('#fStaffJual'); if(sel) s.staffJual=sel.value;
    }
    if(!s.nama){ snack('Sila isi Nama Telefon', true); return; }

    try{
      let imageUrl=s.imageUrl||'';
      if(s.imageFile){ imageUrl=await uploadImage(s.imageFile, s.kod); }
      if(!isEdit){
        const saved={
          kod:s.kod, nama:s.nama, imei:s.imei, warna:s.warna, storage:s.storage,
          jual:num(s.jual), nota:s.nota,
          tarikh_masuk:fmtISODate(now()), masa_masuk:fmtHM(now()),
          staffMasuk:s.staffMasuk||'', imageUrl,
          kategori:s.kategori, supplier:s.supplier||'',
          status:'AVAILABLE', timestamp:now(), shopID:shopID,
        };
        await db.collection(C.stock).add(saved);
        closeModal();
        snack('Stok telefon berjaya ditambah');
        if(state.autoPrintBarcode) printBarcodeLabel(saved);
        else if(state.autoPrintDetail) printDetailLabel(saved);
      } else {
        const upd={
          kod:s.kod, nama:s.nama, imei:s.imei, warna:s.warna, storage:s.storage,
          jual:num(s.jual), nota:s.nota, kategori:s.kategori, status:s.status,
        };
        if(s.status==='SOLD') upd.staffJual=s.staffJual||'';
        if(imageUrl) upd.imageUrl=imageUrl;
        await db.collection(C.stock).doc(original.id).update(upd);
        if(s.status==='SOLD'){
          const existing=await db.collection(C.sales).where('stockDocId','==',original.id).limit(1).get();
          if(existing.empty){
            const ref=db.collection(C.sales).doc();
            await ref.set({
              kod:s.kod, nama:s.nama, imei:s.imei, warna:s.warna, storage:s.storage,
              jual:num(s.jual), imageUrl:imageUrl||original.imageUrl||'',
              tarikh_jual:fmtISODate(now()), timestamp:now(), shopID:shopID,
              stockDocId:original.id, staffJual:s.staffJual||'', siri:ref.id,
            });
          }
        }
        closeModal();
        snack(s.status==='SOLD'?'Stok dikemaskini & direkod dalam jualan':'Stok dikemaskini');
      }
    }catch(e){ console.error(e); snack('Gagal simpan: '+e.message, true); }
  }

  async function confirmDelete(item){
    if(!confirm(`${item.nama||item.kod} akan dimasukkan ke tong sampah. Auto padam kekal selepas 30 hari. Teruskan?`)) return;
    try{
      const data={...item}; delete data.id;
      data.deletedAt=now(); data.originalDocId=item.id;
      await db.collection(C.trash).add(data);
      await db.collection(C.stock).doc(item.id).delete();
      snack('Stok dimasukkan ke tong sampah');
    }catch(e){ snack('Gagal padam', true); }
  }

  // ── Print (RmsPrinter bila connect; fallback browser print) ──
  async function printBarcodeLabel(item){
    const imei=item.imei||''; if(!imei){ snack('IMEI tiada — tidak boleh cetak barcode', true); return; }
    if (window.RmsPrinter && RmsPrinter.isConnected()) {
      try {
        const bytes = escposLabel([
          {text: item.kod||'-', big:true},
          {text: (item.nama||'-').substring(0,30)},
          {text: 'RM ' + num(item.jual).toFixed(2)},
          {text: 'IMEI:'},
          {text: imei, big:true},
        ]);
        await RmsPrinter.printRaw(bytes);
        snack('Label dihantar ke printer');
        return;
      } catch(e){ snack('Gagal cetak: '+e.message, true); return; }
    }
    const w=window.open('','_blank','width=380,height=560');
    w.document.write(`<!DOCTYPE html><html><head><title>Barcode</title>
      <script src="https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js"><\/script>
      <style>body{font-family:Inter,sans-serif;text-align:center;padding:10px;}h2{margin:4px 0;}</style></head><body>
      <h3>${esc(item.kod||'-')}</h3>
      <div>${esc(item.nama||'-')}</div>
      <div>RM ${num(item.jual).toFixed(2)}</div>
      <svg id="bc"></svg>
      <script>JsBarcode('#bc','${esc(imei)}',{format:'CODE128',width:2,height:60,displayValue:true});window.onload=()=>setTimeout(()=>window.print(),300);<\/script>
      </body></html>`);
    w.document.close();
  }
  async function printDetailLabel(item){
    if (window.RmsPrinter && RmsPrinter.isConnected()) {
      try {
        const lines = [
          {text: item.nama||'-', big:true},
          {text: 'Kod: ' + (item.kod||'-')},
        ];
        if (item.imei) lines.push({text: 'IMEI: ' + item.imei});
        if (item.warna) lines.push({text: 'Warna: ' + item.warna});
        if (item.storage) lines.push({text: 'Storage: ' + item.storage});
        lines.push({text: 'RM ' + num(item.jual).toFixed(2), big:true});
        await RmsPrinter.printRaw(escposLabel(lines));
        snack('Label dihantar ke printer');
        return;
      } catch(e){ snack('Gagal cetak: '+e.message, true); return; }
    }
    const w=window.open('','_blank','width=380,height=560');
    w.document.write(`<!DOCTYPE html><html><head><title>Detail</title>
      <style>body{font-family:Inter,sans-serif;padding:10px;font-size:12px;}h3{margin:2px 0;}</style></head><body>
      <h3>${esc(item.nama||'-')}</h3>
      <div>Kod: ${esc(item.kod||'-')}</div>
      ${item.imei?`<div>IMEI: ${esc(item.imei)}</div>`:''}
      ${item.warna?`<div>Warna: ${esc(item.warna)}</div>`:''}
      ${item.storage?`<div>Storage: ${esc(item.storage)}</div>`:''}
      <div><b>RM ${num(item.jual).toFixed(2)}</b></div>
      <script>window.onload=()=>setTimeout(()=>window.print(),250);<\/script>
      </body></html>`);
    w.document.close();
  }
  function showPrintDialog(item){
    const html=`
      <h3><i class="fas fa-print" style="color:var(--ps-primary)"></i> CETAK LABEL
        <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
      <div style="display:flex;gap:10px;">
        <button class="btn-save" id="pBar" style="flex:1;padding:22px;flex-direction:column;background:rgba(37,99,235,.08);color:var(--ps-primary);border:1px solid rgba(37,99,235,.3);"><i class="fas fa-barcode fa-2x"></i><br>BARCODE<br><small>Scan terus ke telefon</small></button>
        <button class="btn-save" id="pDet" style="flex:1;padding:22px;flex-direction:column;background:rgba(234,88,12,.08);color:var(--ps-orange);border:1px solid rgba(234,88,12,.3);"><i class="fas fa-file-lines fa-2x"></i><br>DETAIL<br><small>Info penuh telefon</small></button>
      </div>`;
    openModal(html);
    $('modalBox').querySelector('#pBar').onclick=()=>{closeModal();printBarcodeLabel(item);};
    $('modalBox').querySelector('#pDet').onclick=()=>{closeModal();printDetailLabel(item);};
  }

  // ── Settings modal (auto print) ──
  function showSettings(){
    function render3(){
      const html=`
        <h3><i class="fas fa-gear" style="color:var(--ps-primary)"></i> TETAPAN INVENTORI
          <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
        <div style="color:var(--ps-muted);font-size:11px;margin-bottom:12px;">Auto print lepas simpan stok baru</div>
        <div style="background:var(--ps-bg-deep);padding:12px;border-radius:10px;">
          <div style="display:flex;align-items:center;gap:10px;margin-bottom:12px;">
            <i class="fas fa-barcode" style="color:var(--ps-primary)"></i>
            <div style="flex:1;">
              <div style="font-weight:800;font-size:12px;">Auto Print Barcode</div>
              <div style="font-size:10px;color:var(--ps-muted);">Cetak barcode IMEI selepas simpan</div>
            </div>
            <div class="ps-switch ${state.autoPrintBarcode?'on':''}" id="swBarcode"></div>
          </div>
          <div style="display:flex;align-items:center;gap:10px;">
            <i class="fas fa-file-lines" style="color:var(--ps-orange)"></i>
            <div style="flex:1;">
              <div style="font-weight:800;font-size:12px;">Auto Print Detail</div>
              <div style="font-size:10px;color:var(--ps-muted);">Cetak detail penuh selepas simpan</div>
            </div>
            <div class="ps-switch ${state.autoPrintDetail?'on':''}" id="swDetail"></div>
          </div>
        </div>`;
      openModal(html);
      $('modalBox').querySelector('#swBarcode').onclick=()=>{
        state.autoPrintBarcode=!state.autoPrintBarcode;
        if(state.autoPrintBarcode && state.autoPrintDetail){ state.autoPrintDetail=false; localStorage.setItem('ps_auto_print_detail','0'); }
        localStorage.setItem('ps_auto_print_barcode', state.autoPrintBarcode?'1':'0');
        render3(); render();
      };
      $('modalBox').querySelector('#swDetail').onclick=()=>{
        state.autoPrintDetail=!state.autoPrintDetail;
        if(state.autoPrintDetail && state.autoPrintBarcode){ state.autoPrintBarcode=false; localStorage.setItem('ps_auto_print_barcode','0'); }
        localStorage.setItem('ps_auto_print_detail', state.autoPrintDetail?'1':'0');
        render3(); render();
      };
    }
    render3();
  }

  // ── Long press options ──
  function showLongPressOptions(item){
    const html=`
      <h3>${esc(item.nama||'-')} <small style="font-weight:400;color:var(--ps-muted)">${esc(item.kod||'')}</small>
        <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
      <div class="ps-actions">
        <button class="btn-save" id="btnRet" style="background:var(--ps-red)"><i class="fas fa-truck-ramp-box"></i> RETURN SUPPLIER</button>
        <button class="btn-save" id="btnTr"  style="background:var(--ps-blue)"><i class="fas fa-right-left"></i> TRANSFER</button>
      </div>`;
    openModal(html);
    $('modalBox').querySelector('#btnRet').onclick=()=>{closeModal();showReturnTypeDialog(item);};
    $('modalBox').querySelector('#btnTr').onclick=()=>{closeModal();showTransferDialog(item);};
  }

  // ── Return flow ──
  function showReturnTypeDialog(item){
    const html=`
      <h3>Return Supplier <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
      <div style="font-weight:700;font-size:12px;margin-bottom:4px;">${esc(item.nama||'-')}</div>
      <div style="color:var(--ps-muted);font-size:11px;margin-bottom:12px;">Pilih jenis return:</div>
      <div class="ps-actions">
        <button class="btn-save" id="btnP" style="background:var(--ps-red)">PERMANENT</button>
        <button class="btn-save" id="btnC" style="background:var(--ps-yellow)">CLAIM</button>
      </div>`;
    openModal(html);
    $('modalBox').querySelector('#btnP').onclick=()=>{closeModal();processReturn(item,'PERMANENT');};
    $('modalBox').querySelector('#btnC').onclick=()=>{closeModal();processReturn(item,'CLAIM');};
  }
  async function processReturn(item, type){
    try{
      const data={...item}; const docId=data.id; delete data.id;
      data.returnType=type; data.returnStatus='RETURNED';
      data.returnDate=now(); data.originalDocId=docId; data.fromShopID=shopID;
      await db.collection(C.returns).add(data);
      await db.collection(C.stock).doc(docId).delete();
      await db.collection(C.sales).add({
        nama:item.nama||'-', kod:item.kod||'', imei:item.imei||'', warna:item.warna||'', storage:item.storage||'',
        jual:item.jual||0, shopID, actionType:'RETURN '+type, supplier:item.supplier||'',
        timestamp:now(), staffJual:'-',
      });
      snack(type==='PERMANENT'?'Stok di-return permanent ke supplier':'Stok dihantar untuk claim');
    }catch(e){ snack('Gagal return',true); }
  }

  // ── Transfer flow ──
  function showTransferDialog(item){
    const html=`
      <h3><i class="fas fa-right-left" style="color:var(--ps-blue)"></i> TRANSFER CAWANGAN
        <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
      <div style="font-size:11px;margin-bottom:10px;"><b>${esc(item.nama||'-')}</b>  •  ${esc(item.kod||'')}</div>
      <div id="savedBranchWrap" style="margin-bottom:10px;"></div>
      <div class="ps-field"><label><i class="fas fa-shop"></i> ID Kedai Destinasi</label>
        <input id="toShop" placeholder="Masukkan ID kedai cawangan"></div>
      <div class="ps-actions">
        <button class="btn-save" id="tsSave" style="background:var(--ps-blue)"><i class="fas fa-floppy-disk"></i> SIMPAN & TRANSFER</button>
        <button class="btn-save" id="tsOnly"><i class="fas fa-paper-plane"></i> TRANSFER SAHAJA</button>
      </div>`;
    openModal(html);
    db.collection(C.savedBranch).where('fromShopID','==',shopID).get().then(snap=>{
      if(snap.empty) return;
      const saved=[]; snap.forEach(d=>saved.push({id:d.id, ...(d.data()||{})}));
      const wrap=$('modalBox').querySelector('#savedBranchWrap');
      wrap.innerHTML=`<div style="font-size:10px;font-weight:900;color:var(--ps-muted);margin-bottom:4px;">Cawangan Tersimpan:</div>`+
        `<div style="display:flex;gap:6px;flex-wrap:wrap;">`+
        saved.map(b=>`<button type="button" class="ps-mini-btn" data-s="${esc(b.toShopID||'')}" style="background:rgba(59,130,246,.1);color:var(--ps-blue);border-color:rgba(59,130,246,.3)">${esc(b.toShopID||'-')}</button>`).join('')+`</div>`;
      wrap.querySelectorAll('button[data-s]').forEach(b=>{ b.onclick=()=>{ $('modalBox').querySelector('#toShop').value=b.dataset.s; }; });
    });
    const doT=async(save)=>{
      const to=UP(($('modalBox').querySelector('#toShop').value||'').trim());
      if(!to){ snack('Sila masukkan ID kedai',true); return; }
      if(to===shopID){ snack('Tidak boleh transfer ke kedai sendiri',true); return; }
      closeModal();
      await processTransfer(item, to, save);
    };
    $('modalBox').querySelector('#tsSave').onclick=()=>doT(true);
    $('modalBox').querySelector('#tsOnly').onclick=()=>doT(false);
  }
  async function processTransfer(item, toShopID, saveShop){
    try{
      const data={...item}; const docId=data.id; delete data.id;
      const transferData={...data, fromShopID:shopID, toShopID, status:'PENDING', transferDate:now(), originalDocId:docId};
      await db.collection(C.transfers).add(transferData);
      await db.collection(C.stock).doc(docId).delete();
      await db.collection(C.sales).add({
        nama:item.nama||'-', kod:item.kod||'', imei:item.imei||'', warna:item.warna||'', storage:item.storage||'',
        jual:item.jual||0, shopID, actionType:'TRANSFER KE '+toShopID, supplier:item.supplier||'',
        timestamp:now(), staffJual:'-',
      });
      if(saveShop){
        const ex=await db.collection(C.savedBranch).where('fromShopID','==',shopID).where('toShopID','==',toShopID).get();
        if(ex.empty) await db.collection(C.savedBranch).add({fromShopID:shopID, toShopID, savedAt:now()});
      }
      snack('Stok berjaya ditransfer ke '+toShopID);
    }catch(e){ snack('Gagal transfer',true); }
  }
  async function acceptTransfer(transfer, transferDocId){
    try{
      const data={...transfer};
      ['id','fromShopID','toShopID','status','transferDate','originalDocId'].forEach(k=>delete data[k]);
      data.shopID=shopID; data.status='AVAILABLE'; data.timestamp=now();
      await db.collection(C.stock).add(data);
      await db.collection(C.transfers).doc(transferDocId).update({status:'ACCEPTED'});
      await db.collection(C.sales).add({
        nama:transfer.nama||'-', kod:transfer.kod||'', imei:transfer.imei||'', warna:transfer.warna||'', storage:transfer.storage||'',
        jual:transfer.jual||0, shopID, actionType:'TERIMA DARI '+(transfer.fromShopID||'-'),
        supplier:transfer.supplier||'', timestamp:now(), staffJual:'-',
      });
      snack('Stok berjaya diterima');
    }catch(e){ snack('Gagal terima',true); }
  }

  // ── History (Sales/Return/Transfer/Trash) ──
  function showHistory(tab=0){
    let current=tab, searchQ='', dateF=null;
    function render4(){
      const html=`
        <h3><i class="fas fa-clock-rotate-left" style="color:var(--ps-primary)"></i> HISTORY & REKOD
          <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
        <div class="ps-search-row" style="margin-bottom:6px;">
          <i class="fas fa-search" style="color:var(--ps-muted)"></i>
          <input id="hSearch" placeholder="Cari nama, IMEI, kod, supplier..." value="${esc(searchQ)}">
          <input id="hDate" type="date" value="${dateF?fmtISODate(dateF):''}" style="border:none;background:transparent;width:130px;">
        </div>
        <div class="ps-segment">
          <button data-i="0" class="${current===0?'is-active':''}" style="${current===0?'background:var(--ps-green);border-color:var(--ps-green)':''}"><i class="fas fa-clock-rotate-left"></i> HISTORY</button>
          <button data-i="1" class="${current===1?'is-active':''}" style="${current===1?'background:var(--ps-red);border-color:var(--ps-red)':''}"><i class="fas fa-truck-ramp-box"></i> RETURN</button>
          <button data-i="2" class="${current===2?'is-active':''}" style="${current===2?'background:var(--ps-blue);border-color:var(--ps-blue)':''}"><i class="fas fa-right-left"></i> TRANSFER</button>
          <button data-i="3" class="${current===3?'is-active':''}" style="${current===3?'background:var(--ps-red);border-color:var(--ps-red)':''}"><i class="fas fa-trash-can"></i> SAMPAH</button>
        </div>
        <div id="histList" style="max-height:55vh;overflow-y:auto;"><div style="text-align:center;padding:20px;color:var(--ps-muted);">Memuat...</div></div>`;
      openModal(html);
      $('modalBox').querySelector('#hSearch').oninput=e=>{searchQ=e.target.value.toLowerCase().trim();loadH();};
      $('modalBox').querySelector('#hDate').onchange=e=>{dateF=e.target.value?new Date(e.target.value).getTime():null;loadH();};
      $('modalBox').querySelectorAll('.ps-segment button').forEach(b=>{
        b.onclick=()=>{current=parseInt(b.dataset.i);render4();};
      });
      loadH();
    }
    async function loadH(){
      const host=$('modalBox').querySelector('#histList'); if(!host) return;
      host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-muted);">Memuat...</div>`;
      try{
        if(current===3){
          const snap=await db.collection(C.salesTrash).orderBy('deletedAt','desc').limit(100).get();
          const THIRTY=30*24*60*60*1000; const nowMs=now();
          const list=[]; snap.forEach(d=>{
            const data=d.data()||{};
            if(UP(data.shopID||'')!==shopID) return;
            const del=tsMs(data.deletedAt)||0;
            if((nowMs-del)>=THIRTY) return;
            if(searchQ){
              const s=`${data.nama||''} ${data.kod||''} ${data.imei||''} ${data.supplier||''}`.toLowerCase();
              if(!s.includes(searchQ)) return;
            }
            if(dateF){
              const di=new Date(del), df=new Date(dateF);
              if(di.toDateString()!==df.toDateString()) return;
            }
            list.push({id:d.id, ...data, _del:del});
          });
          if(!list.length){ host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-muted);">Tiada rekod dalam tong sampah</div>`; return; }
          host.innerHTML=list.map(d=>{
            const daysLeft=30-Math.floor((nowMs-d._del)/(24*60*60*1000));
            return `<div class="ps-hist-item" style="background:rgba(220,38,38,.03);border-color:rgba(220,38,38,.2);">
              <div style="font-weight:900;font-size:11px;">${esc(d.nama||'-')}   RM${num(d.jual).toFixed(0)}</div>
              <div style="font-size:9px;color:var(--ps-muted);">${esc(d.warna||'-')} • ${esc(d.storage||'-')} • IMEI: ${esc(d.imei||'-')}</div>
              <div style="display:flex;align-items:center;gap:6px;margin-top:4px;">
                <span class="ps-action-badge" style="background:${daysLeft<=7?'rgba(220,38,38,.15)':'rgba(245,158,11,.15)'};color:${daysLeft<=7?'var(--ps-red)':'var(--ps-yellow)'};">${daysLeft} hari lagi</span>
                <div style="flex:1;"></div>
                <button data-rec="${d.id}" style="padding:4px 8px;border-radius:6px;background:rgba(16,185,129,.1);border:1px solid rgba(16,185,129,.3);color:var(--ps-green);font-size:9px;font-weight:900;cursor:pointer;"><i class="fas fa-rotate-left"></i> RECOVER</button>
              </div></div>`;
          }).join('');
          host.querySelectorAll('button[data-rec]').forEach(b=>{
            b.onclick=async()=>{
              const it=list.find(x=>x.id===b.dataset.rec); if(!it) return;
              const data={...it}; delete data.id; delete data._del; delete data.deletedAt; delete data.originalSaleDocId;
              await db.collection(C.sales).add(data);
              await db.collection(C.salesTrash).doc(it.id).delete();
              snack('Rekod berjaya di-recover'); loadH();
            };
          });
        } else {
          const snap=await db.collection(C.sales).orderBy('timestamp','desc').limit(200).get();
          const list=[]; snap.forEach(d=>{
            const data=d.data()||{};
            if(UP(data.shopID||'')!==shopID) return;
            const action=UP(data.actionType||'SOLD');
            if(current===1 && !action.includes('RETURN') && !action.includes('REVERSE')) return;
            if(current===2 && !action.includes('TRANSFER') && !action.includes('TERIMA')) return;
            if(searchQ){
              const s=`${data.nama||''} ${data.kod||''} ${data.imei||''} ${data.supplier||''} ${data.staffJual||''}`.toLowerCase();
              if(!s.includes(searchQ)) return;
            }
            if(dateF){
              const ts=tsMs(data.timestamp)||0;
              const di=new Date(ts), df=new Date(dateF);
              if(di.toDateString()!==df.toDateString()) return;
            }
            list.push({id:d.id, ...data});
          });
          if(!list.length){ host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-muted);">Tiada rekod jualan</div>`; return; }
          host.innerHTML=list.map(d=>{
            const action=UP(d.actionType||'SOLD');
            const col = action.includes('RETURN')?'var(--ps-red)':action.includes('TRANSFER')||action.includes('TERIMA')?'var(--ps-blue)':action.includes('REVERSE')?'var(--ps-yellow)':'var(--ps-green)';
            const ts=tsMs(d.timestamp);
            const tarikh=ts?fmtDate(ts,true):(d.tarikh_jual||'-');
            return `<div class="ps-hist-item">
              <div style="display:flex;align-items:center;gap:6px;">
                <div style="flex:1;font-weight:900;font-size:11px;">${esc(d.nama||'-')}   RM${num(d.jual).toFixed(0)}</div>
                <span class="ps-action-badge" style="background:${col}29;color:${col};">${esc(action)}</span>
              </div>
              <div style="font-size:9px;color:var(--ps-muted);margin-top:2px;">${esc(d.warna||'-')} • ${esc(d.storage||'-')} • IMEI: ${esc(d.imei||'-')}${d.supplier?` • ${esc(d.supplier)}`:''}</div>
              <div style="display:flex;align-items:center;gap:6px;margin-top:3px;">
                <div style="flex:1;font-size:9px;color:var(--ps-dim);">${esc(tarikh)} • ${esc(d.staffJual||d.staffName||'-')} • #${esc(d.siri||d.id)}</div>
                <button data-del="${d.id}" style="padding:4px;border-radius:4px;background:rgba(220,38,38,.1);border:1px solid rgba(220,38,38,.3);color:var(--ps-red);cursor:pointer;"><i class="fas fa-trash" style="font-size:10px;"></i></button>
              </div></div>`;
          }).join('');
          host.querySelectorAll('button[data-del]').forEach(b=>{
            b.onclick=async()=>{
              const it=list.find(x=>x.id===b.dataset.del); if(!it) return;
              if(!confirm(`${it.nama||'-'} akan dimasukkan ke tong sampah. Boleh recover dalam 30 hari. Teruskan?`)) return;
              const data={...it}; delete data.id;
              data.deletedAt=now(); data.originalSaleDocId=it.id;
              await db.collection(C.salesTrash).add(data);
              await db.collection(C.sales).doc(it.id).delete();
              snack('Rekod dimasukkan ke tong sampah'); loadH();
            };
          });
        }
      }catch(e){ console.error(e); host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-red);">Gagal muat: ${esc(e.message)}</div>`; }
    }
    render4();
  }

  // ── Return list ──
  function showReturnList(){
    let q='';
    function render5(){
      const html=`
        <h3><i class="fas fa-truck-ramp-box" style="color:var(--ps-red)"></i> RETURN SUPPLIER
          <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
        <div class="ps-search-row" style="margin-bottom:6px;"><i class="fas fa-search" style="color:var(--ps-muted)"></i><input id="rSearch" placeholder="Cari nama, IMEI, supplier..." value="${esc(q)}"></div>
        <div id="retList" style="max-height:60vh;overflow-y:auto;"><div style="text-align:center;padding:20px;color:var(--ps-muted);">Memuat...</div></div>`;
      openModal(html);
      $('modalBox').querySelector('#rSearch').oninput=e=>{q=e.target.value.toLowerCase().trim();load();};
      load();
    }
    async function load(){
      const host=$('modalBox').querySelector('#retList'); if(!host) return;
      try{
        const snap=await db.collection(C.returns).orderBy('returnDate','desc').get();
        const list=[]; snap.forEach(d=>{
          const data=d.data()||{};
          if(UP(data.fromShopID||'')!==shopID) return;
          if(q){
            const s=`${data.nama||''} ${data.kod||''} ${data.imei||''} ${data.supplier||''}`.toLowerCase();
            if(!s.includes(q)) return;
          }
          list.push({id:d.id, ...data});
        });
        if(!list.length){ host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-muted);">Tiada rekod return</div>`; return; }
        host.innerHTML=list.map(d=>{
          const type=UP(d.returnType||'-'); const status=UP(d.returnStatus||'-');
          const col=type==='PERMANENT'?'var(--ps-red)':'var(--ps-yellow)';
          const isRev=(type==='CLAIM' && status==='RETURNED');
          const dt=d.returnDate?fmtDate(tsMs(d.returnDate)):'-';
          return `<div class="ps-hist-item" style="background:${col}0A;border-color:${col}40;">
            <div style="display:flex;gap:6px;align-items:center;">
              <div style="flex:1;font-weight:900;font-size:11px;">${esc(d.nama||'-')}   RM${num(d.jual).toFixed(0)}</div>
              <span class="ps-action-badge" style="background:${col}29;color:${col};">${esc(type)}</span>
            </div>
            ${d.imei?`<div style="font-size:9px;color:var(--ps-muted);">IMEI: ${esc(d.imei)}</div>`:''}
            <div style="display:flex;align-items:center;gap:6px;font-size:9px;color:var(--ps-dim);margin-top:3px;">
              <div style="flex:1;">${esc(dt)} • ${esc(status)}</div>
              ${isRev?`<button data-rev="${d.id}" style="padding:4px 8px;border-radius:6px;background:rgba(16,185,129,.1);border:1px solid rgba(16,185,129,.3);color:var(--ps-green);font-weight:900;cursor:pointer;"><i class="fas fa-rotate-left"></i> REVERSE</button>`:''}
            </div></div>`;
        }).join('');
        host.querySelectorAll('button[data-rev]').forEach(b=>{
          b.onclick=async()=>{
            const it=list.find(x=>x.id===b.dataset.rev); if(!it) return;
            const data={...it}; delete data.id;
            ['returnType','returnStatus','returnDate','originalDocId','fromShopID'].forEach(k=>delete data[k]);
            data.status='AVAILABLE'; data.shopID=shopID; data.timestamp=now();
            await db.collection(C.stock).add(data);
            await db.collection(C.returns).doc(it.id).delete();
            await db.collection(C.sales).add({
              nama:it.nama||'-', kod:it.kod||'', imei:it.imei||'', warna:it.warna||'', storage:it.storage||'',
              jual:it.jual||0, shopID, actionType:'REVERSE CLAIM', supplier:it.supplier||'',
              timestamp:now(), staffJual:'-',
            });
            snack('Stok berjaya di-reverse masuk semula'); load();
          };
        });
      }catch(e){ host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-red);">${esc(e.message)}</div>`; }
    }
    render5();
  }

  // ── Transfer list ──
  function showTransferList(){
    let q='';
    function render6(){
      const html=`
        <h3><i class="fas fa-right-left" style="color:var(--ps-blue)"></i> TRANSFER CAWANGAN
          <button class="ps-close" onclick="window.__psCloseModal(1)"><i class="fas fa-xmark"></i></button></h3>
        <div class="ps-search-row" style="margin-bottom:6px;"><i class="fas fa-search" style="color:var(--ps-muted)"></i><input id="tSearch" placeholder="Cari nama, IMEI, cawangan..." value="${esc(q)}"></div>
        <div id="trList" style="max-height:60vh;overflow-y:auto;"><div style="text-align:center;padding:20px;color:var(--ps-muted);">Memuat...</div></div>`;
      openModal(html);
      $('modalBox').querySelector('#tSearch').oninput=e=>{q=e.target.value.toLowerCase().trim();load();};
      load();
    }
    async function load(){
      const host=$('modalBox').querySelector('#trList'); if(!host) return;
      try{
        const snap=await db.collection(C.transfers).orderBy('transferDate','desc').get();
        const list=[]; snap.forEach(d=>{
          const data=d.data()||{};
          const from=UP(data.fromShopID||''), to=UP(data.toShopID||'');
          if(from!==shopID && to!==shopID) return;
          if(q){
            const s=`${data.nama||''} ${data.kod||''} ${data.imei||''} ${data.fromShopID||''} ${data.toShopID||''}`.toLowerCase();
            if(!s.includes(q)) return;
          }
          list.push({id:d.id, ...data});
        });
        if(!list.length){ host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-muted);">Tiada rekod transfer</div>`; return; }
        host.innerHTML=list.map(d=>{
          const from=UP(d.fromShopID||'-'), to=UP(d.toShopID||'-'); const st=UP(d.status||'-');
          const isFrom=from===shopID;
          const stCol=st==='PENDING'?'var(--ps-yellow)':'var(--ps-green)';
          const dt=d.transferDate?fmtDate(tsMs(d.transferDate)):'-';
          return `<div class="ps-hist-item" style="background:${isFrom?'rgba(59,130,246,.05)':'rgba(37,99,235,.05)'};">
            <div style="display:flex;gap:6px;align-items:center;">
              <div style="flex:1;font-weight:900;font-size:11px;">${esc(d.nama||'-')}   RM${num(d.jual).toFixed(0)}</div>
              <span class="ps-action-badge" style="background:${stCol}29;color:${stCol};">${esc(st)}</span>
            </div>
            ${d.imei?`<div style="font-size:9px;color:var(--ps-muted);">IMEI: ${esc(d.imei)}</div>`:''}
            <div style="font-size:9px;color:var(--ps-dim);margin-top:3px;">
              <i class="fas fa-arrow-${isFrom?'right':'left'}"></i> ${esc(isFrom?'Ke: '+to:'Dari: '+from)} • ${esc(dt)}
            </div></div>`;
        }).join('');
      }catch(e){ host.innerHTML=`<div style="text-align:center;padding:20px;color:var(--ps-red);">${esc(e.message)}</div>`; }
    }
    render6();
  }

  // ── Bind top controls ──
  $('btnAdd').onclick=showAddModal;
  $('btnHistory').onclick=()=>showHistory(0);
  $('btnReturnList').onclick=showReturnList;
  $('btnTransferList').onclick=showTransferList;
  $('btnSettings').onclick=showSettings;
  $('btnScan').onclick=()=>{
    const raw=prompt('Tampal barcode/IMEI untuk cari:');
    if(!raw) return;
    $('searchInput').value=raw.trim().toUpperCase();
    state.search=raw.trim().toLowerCase();
    applyFilter(); render();
  };
  $('searchInput').addEventListener('input',e=>{
    state.search=e.target.value;
    $('clearSearch').style.display=e.target.value?'inline':'none';
    applyFilter(); render();
  });
  $('clearSearch').onclick=()=>{ $('searchInput').value=''; state.search=''; $('clearSearch').style.display='none'; applyFilter(); render(); };
  $('filterModel').onchange=e=>{state.selectedModel=e.target.value; applyFilter(); render();};
  $('filterKategori').onchange=e=>{state.selectedKategori=e.target.value; applyFilter(); render();};

  // Init
  (async()=>{
    await Promise.all([loadCategories(), loadSuppliers(), loadStaff()]);
    render();
  })();
})();
