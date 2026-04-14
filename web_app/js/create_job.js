/* Create Job — port lib/screens/modules/create_job_screen.dart
   1:1 with simpanTiket in services/repair_service.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();
  const storage = firebase.storage ? firebase.storage() : null;

  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const num = v => { const n = parseFloat(v); return isNaN(n) ? 0 : n; };
  const fmtMoney = n => 'RM ' + (Number(n) || 0).toFixed(2);
  const pad = (n,l=2) => String(n).padStart(l,'0');

  function snack(msg, err=false){
    const el=document.createElement('div');
    el.className='cj-snack'+(err?' err':'');
    el.textContent=msg;
    document.body.appendChild(el);
    setTimeout(()=>el.remove(),2800);
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

  // ─── state ───
  const state = {
    step: 0,
    totalSteps: 3,
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
    items: [{nama:'', qty:1, harga:0}],
    patternPts: [],
    imgDepan: null,
    imgBelakang: null,
    tarikhEdited: false,
    tarikh: new Date(),
    savedSiri: '',
    savedData: null,
    isLocked: false,
    hasGallery: false,
  };

  // ─── live clock ───
  function setTarikhInput(){
    const d=state.tarikh;
    $('tarikh').value = `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  setInterval(()=>{ if(!state.tarikhEdited && !state.isLocked){ state.tarikh=new Date(); setTarikhInput(); } }, 1000);
  setTarikhInput();
  $('tarikh').addEventListener('change', e=>{
    state.tarikhEdited = true;
    state.tarikh = new Date(e.target.value);
  });

  // ─── load branch settings, staff, inventory, vouchers, customers ───
  async function loadData(){
    // merged saas_dealers + shops
    const merged = {};
    try { const d=await db.collection('saas_dealers').doc(ownerID).get(); if(d.exists) Object.assign(merged,d.data()||{}); } catch(e){}
    try { const s=await db.collection('shops_'+ownerID).doc(shopID).get(); if(s.exists) Object.assign(merged,s.data()||{}); } catch(e){}
    let hasGallery = merged.addonGallery === true;
    if (hasGallery && merged.galleryExpire && Date.now() > merged.galleryExpire) hasGallery=false;
    state.hasGallery = hasGallery;
    state.branchSettings = merged;
    const staffList = Array.isArray(merged.staffList) ? merged.staffList.map(s=>{
      if(typeof s==='string') return s;
      if(s && typeof s==='object') return s.name || s.nama || '';
      return '';
    }).filter(Boolean) : [];
    state.staffList = staffList;
    const sel = $('staffTerima');
    sel.innerHTML = staffList.map(s=>`<option>${esc(s)}</option>`).join('');
    if(staffList.length){ state.staffTerima = staffList[0]; sel.value = staffList[0]; }

    // vouchers
    try {
      const vs = await db.collection('shop_vouchers_'+ownerID).get();
      vs.forEach(doc=>{
        const d=doc.data()||{};
        state.activeVouchers.push({code:d.code||doc.id, value:d.value||0, ...d});
        const code=d.code||doc.id;
        const tel=String(d.customerTel||'');
        if(tel) (state.voucherByTel[tel]=state.voucherByTel[tel]||[]).push(code);
        else (state.voucherByTel['_SHOP']=state.voucherByTel['_SHOP']||[]).push(code);
      });
    } catch(e){}

    // existing customers from past repairs
    try {
      const snap = await db.collection('repairs_'+ownerID).get();
      const seen = new Set();
      const custs = [];
      snap.forEach(doc=>{
        const d=doc.data()||{};
        if(String(d.shopID||'').toUpperCase()!==shopID) return;
        const tel=String(d.tel||'').trim();
        if(!tel || seen.has(tel)) return;
        seen.add(tel);
        custs.push({nama:d.nama||'', tel:tel, tel_wasap:d.tel_wasap||'', model:d.model||''});
      });
      state.existingCustomers = custs;
    } catch(e){}
  }

  // ─── step indicator ───
  function renderStep(){
    const ind = $('stepIndicator');
    const labels = ['Pelanggan','Kerosakan','Bayaran'];
    ind.innerHTML = labels.map((l,i)=>{
      const cls = i===state.step?'is-active':(i<state.step?'is-done':'');
      return `<span class="cj-step__dot ${cls}">${i+1}</span><span style="font-weight:700;font-size:12px;color:${i===state.step?'#0f172a':'#64748b'};">${l}</span>${i<labels.length-1?'<span class="cj-step__line"></span>':''}`;
    }).join('');
    document.querySelectorAll('[data-step]').forEach(sec=>{
      sec.hidden = String(state.step) !== sec.getAttribute('data-step');
    });
    $('btnPrev').hidden = state.step===0;
    $('btnNext').hidden = state.step>=state.totalSteps-1;
    $('btnSave').hidden = state.step<state.totalSteps-1 || state.isLocked;
    $('btnReset').hidden = !state.isLocked;
  }

  // ─── customer type toggle ───
  $('custTypeToggle').addEventListener('click', e=>{
    const b=e.target.closest('button[data-v]'); if(!b) return;
    state.custType = b.dataset.v;
    document.querySelectorAll('#custTypeToggle button').forEach(x=>x.classList.toggle('is-active', x===b));
    $('custSearchRow').hidden = state.custType !== 'REGULAR';
  });

  // ─── customer search ───
  $('custSearch').addEventListener('input', e=>{
    const q = e.target.value.toLowerCase().trim();
    const hits = $('custHits');
    if(!q){ hits.hidden=true; hits.innerHTML=''; return; }
    const r = state.existingCustomers.filter(c=>
      (c.nama||'').toLowerCase().includes(q) || (c.tel||'').includes(q)).slice(0,10);
    hits.hidden = r.length===0;
    hits.innerHTML = r.map((c,i)=>`<div class="cj-cust-hit" data-i="${i}"><b>${esc(c.nama)}</b> — ${esc(c.tel)} <span style="color:#64748b;">${esc(c.model||'')}</span></div>`).join('');
    hits._data = r;
  });
  $('custHits').addEventListener('click', e=>{
    const h=e.target.closest('.cj-cust-hit'); if(!h) return;
    const c=$('custHits')._data[+h.dataset.i];
    $('nama').value = c.nama; $('tel').value = c.tel; $('telWasap').value = c.tel_wasap||''; $('model').value = c.model||'';
    $('custHits').hidden = true;
  });

  // ─── pattern ───
  (function(){
    const box = $('patternBox');
    box.innerHTML = '';
    for(let i=1;i<=9;i++){
      const d=document.createElement('div');
      d.className='cj-pattern-dot'; d.textContent=i; d.dataset.n=i;
      d.addEventListener('click', ()=>{
        const n=+d.dataset.n;
        const idx=state.patternPts.indexOf(n);
        if(idx>=0) state.patternPts.splice(idx,1); else state.patternPts.push(n);
        document.querySelectorAll('.cj-pattern-dot').forEach(x=>x.classList.toggle('is-on', state.patternPts.includes(+x.dataset.n)));
        $('patternTxt').textContent = state.patternPts.join('-') || '-';
      });
      box.appendChild(d);
    }
  })();
  $('patternClear').addEventListener('click', ()=>{
    state.patternPts=[];
    document.querySelectorAll('.cj-pattern-dot').forEach(x=>x.classList.remove('is-on'));
    $('patternTxt').textContent = '-';
  });

  // ─── items ───
  function renderItems(){
    const w = $('itemsWrap');
    w.innerHTML = state.items.map((it,i)=>`
      <div class="cj-item-row">
        <input class="input" data-k="nama" data-i="${i}" placeholder="Nama item/servis" value="${esc(it.nama)}">
        <input class="input" data-k="qty" data-i="${i}" type="number" min="1" value="${it.qty}">
        <input class="input" data-k="harga" data-i="${i}" type="number" step="0.01" placeholder="Harga" value="${it.harga || ''}">
        <button type="button" class="cj-del" data-i="${i}"${state.items.length<=1?' disabled':''}><i class="fas fa-trash"></i></button>
      </div>`).join('');
    updateTotal();
  }
  function updateTotal(){
    const t = state.items.reduce((s,it)=>s+(num(it.qty)*num(it.harga)),0);
    $('totalHarga').textContent = fmtMoney(t);
  }
  $('itemsWrap').addEventListener('input', e=>{
    const t=e.target; const i=+t.dataset.i; const k=t.dataset.k;
    if(!Number.isFinite(i) || !k) return;
    if(k==='qty') state.items[i].qty = parseInt(t.value)||1;
    else if(k==='harga') state.items[i].harga = num(t.value);
    else state.items[i][k] = t.value;
    updateTotal();
  });
  $('itemsWrap').addEventListener('click', e=>{
    const b=e.target.closest('.cj-del'); if(!b) return;
    const i=+b.dataset.i;
    if(state.items.length>1){ state.items.splice(i,1); renderItems(); }
  });
  $('addItem').addEventListener('click', ()=>{ state.items.push({nama:'',qty:1,harga:0}); renderItems(); });
  renderItems();

  // ─── promo ───
  $('applyPromo').addEventListener('click', async ()=>{
    const kod = $('promo').value.trim().toUpperCase();
    const msg = $('promoMsg');
    state.kodVoucher=''; state.voucherAmt=0;
    if(!kod){ msg.textContent=''; return; }
    try {
      if (kod.startsWith('V-')) {
        const d = await db.collection('shop_vouchers_'+ownerID).doc(kod).get();
        if(!d.exists){ msg.textContent='Voucher tidak dijumpai'; return; }
        const data = d.data()||{};
        const used = (data.claimed||0) >= (data.maxClaim||1);
        if(used){ msg.textContent='Voucher telah digunakan'; return; }
        state.kodVoucher = kod; state.voucherAmt = num(data.value);
        msg.textContent = `Voucher diguna: -${fmtMoney(state.voucherAmt)}`;
      } else if (kod.startsWith('REF-')) {
        const d = await db.collection('referrals_'+ownerID).doc(kod).get();
        if(!d.exists){ msg.textContent='Referral tidak dijumpai'; return; }
        const data = d.data()||{};
        state.kodVoucher = kod; state.voucherAmt = num(data.rewardValue || data.value || 5);
        msg.textContent = `Referral diguna: -${fmtMoney(state.voucherAmt)}`;
      } else {
        msg.textContent='Format kod tidak sah (V-... atau REF-...)';
      }
    } catch(e){ msg.textContent='Ralat: '+e.message; }
  });

  // ─── images ───
  function readFileToDataUrl(file){
    return new Promise((res,rej)=>{ const r=new FileReader(); r.onload=()=>res(r.result); r.onerror=rej; r.readAsDataURL(file); });
  }
  document.querySelectorAll('.cj-snap-card').forEach(c=>{
    c.addEventListener('click', ()=>{ $('file'+(c.dataset.k==='depan'?'Depan':'Belakang')).click(); });
  });
  $('fileDepan').addEventListener('change', async e=>{
    const f=e.target.files[0]; if(!f) return;
    state.imgDepan = await readFileToDataUrl(f);
    const c=document.querySelector('.cj-snap-card[data-k="depan"]'); c.style.backgroundImage=`url(${state.imgDepan})`; c.innerHTML='<div style="background:#10b981;color:#fff;padding:4px 8px;border-radius:6px;font-weight:800;">OK</div>';
  });
  $('fileBelakang').addEventListener('change', async e=>{
    const f=e.target.files[0]; if(!f) return;
    state.imgBelakang = await readFileToDataUrl(f);
    const c=document.querySelector('.cj-snap-card[data-k="belakang"]'); c.style.backgroundImage=`url(${state.imgBelakang})`; c.innerHTML='<div style="background:#10b981;color:#fff;padding:4px 8px;border-radius:6px;font-weight:800;">OK</div>';
  });

  // ─── bindings ───
  ['jenisServis','paymentStatus','caraBayaran','staffTerima'].forEach(id=>{
    $(id).addEventListener('change', e=>{ state[id]=e.target.value; });
  });

  $('btnPrev').addEventListener('click', ()=>{ if(state.step>0){ state.step--; renderStep(); } });
  $('btnNext').addEventListener('click', ()=>{ if(state.step<state.totalSteps-1){ state.step++; renderStep(); } });
  $('btnReset').addEventListener('click', resetForm);
  $('btnSave').addEventListener('click', simpanTiket);

  // ─── siri counter (transaction) ───
  async function getNextSiri(){
    const ref = db.collection('counters_'+ownerID).doc(shopID+'_global');
    const newCount = await db.runTransaction(async tx=>{
      const snap = await tx.get(ref);
      let count = 1;
      if(snap.exists) count = (snap.data().count||0) + 1;
      tx.set(ref, {count}, {merge:true});
      return count;
    });
    let pure = shopID; if(pure.includes('-')) pure = pure.split('-')[1];
    return pure + String(newCount).padStart(5,'0');
  }
  function genVoucherCode(){
    const c='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let r=''; for(let i=0;i<6;i++) r+=c[Math.floor(Math.random()*c.length)];
    return 'V-'+r;
  }

  async function uploadImages(siri){
    const out={};
    if(!state.hasGallery || !storage) return out;
    async function up(b64,label){
      if(!b64) return null;
      try {
        const ref = storage.ref(`repairs/${ownerID}/${siri}/${label}_${Date.now()}.jpg`);
        await ref.putString(b64, 'data_url', {contentType:'image/jpeg'});
        return await ref.getDownloadURL();
      } catch(e){ return null; }
    }
    const a = await up(state.imgDepan,'depan'); if(a) out.img_sebelum_depan=a;
    const b = await up(state.imgBelakang,'belakang'); if(b) out.img_sebelum_belakang=b;
    return out;
  }

  async function simpanTiket(){
    const nama = $('nama').value.trim();
    const tel = $('tel').value.trim();
    if(!nama || !tel){ snack('Sila isi Nama & No Telefon', true); return; }
    const validItems = state.items.filter(i=>(i.nama||'').trim());
    if(!validItems.length){ snack('Sila tambah sekurang-kurangnya satu item', true); return; }

    try {
      $('btnSave').disabled = true;
      const siri = await getNextSiri();
      const voucherGen = genVoucherCode();

      const phonePass = $('password').value.trim();
      const patternResult = state.patternPts.join('-');
      let finalPass = phonePass || 'Tiada';
      if(patternResult && finalPass==='Tiada') finalPass = 'Pattern: '+patternResult;
      else if(patternResult) finalPass += ' (Pattern: '+patternResult+')';

      const harga = state.items.reduce((s,it)=>s+(num(it.qty)*num(it.harga)),0);
      const deposit = num($('deposit').value);
      const voucherAmt = state.voucherAmt;
      const total = harga - voucherAmt - deposit;

      const kerosakan = validItems.map(i=>`${i.nama} (x${i.qty})`).join(', ');
      const itemsArray = validItems.map(i=>({nama:i.nama, qty:parseInt(i.qty)||1, harga:num(i.harga)}));

      const d = state.tarikh;
      const tarikhStr = `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;

      const telWasap = $('telWasap').value.trim();
      const data = {
        siri, receiptNo: siri, shopID,
        nama: nama.toUpperCase(), pelanggan: nama.toUpperCase(),
        tel, telefon: tel,
        tel_wasap: telWasap || '-', wasap: telWasap || '-',
        model: $('model').value.trim().toUpperCase(),
        kerosakan,
        items_array: itemsArray,
        tarikh: tarikhStr,
        harga: harga.toFixed(2),
        deposit: deposit.toFixed(2),
        diskaun: '0', tambahan: '0',
        total: total.toFixed(2),
        baki: total.toFixed(2),
        voucher_generated: voucherGen,
        voucher_used: state.kodVoucher,
        voucher_used_amt: voucherAmt,
        payment_status: state.paymentStatus,
        cara_bayaran: state.caraBayaran,
        catatan: $('catatan').value.trim(),
        jenis_servis: state.jenisServis,
        staff_terima: state.staffTerima,
        staff_repair: '',
        staff_serah: '',
        password: finalPass,
        cust_type: state.custType,
        status: 'IN PROGRESS',
        status_history: [{status:'IN PROGRESS', timestamp: tarikhStr}],
        timestamp: Date.now(),
      };
      await db.collection('repairs_'+ownerID).doc(siri).set(data);

      const imgUrls = await uploadImages(siri);
      if(Object.keys(imgUrls).length){
        await db.collection('repairs_'+ownerID).doc(siri).update(imgUrls);
        Object.assign(data, imgUrls);
      }

      if(state.kodVoucher.startsWith('REF-')){
        try {
          await db.collection('referral_claims_'+ownerID).add({
            referralCode: state.kodVoucher,
            claimedBy: tel,
            claimedByName: nama.toUpperCase(),
            siri, amount: voucherAmt, shopID,
            timestamp: Date.now(),
          });
        } catch(e){}
      }
      if(state.kodVoucher.startsWith('V-')){
        try { await db.collection('shop_vouchers_'+ownerID).doc(state.kodVoucher).update({claimed: firebase.firestore.FieldValue.increment(1)}); } catch(e){}
      }

      state.savedSiri = siri; state.savedData = data; state.isLocked = true;
      $('siriBadge').textContent = '#'+siri; $('siriBadge').hidden = false;
      snack('Berjaya Disimpan! Siri: #'+siri);
      renderStep();

      // Auto-cetak resit tiket jika printer disambung
      if (window.RmsPrinter && RmsPrinter.isConnected()) {
        try {
          const shopInfo = {
            shopName: state.branchSettings.shopName || state.branchSettings.namaKedai || 'RMS PRO',
            address: state.branchSettings.address || state.branchSettings.alamat || '',
            phone: state.branchSettings.phone || state.branchSettings.ownerContact || '-',
            notaInvoice: state.branchSettings.notaInvoice || 'Terima kasih atas sokongan anda.',
          };
          await RmsPrinter.printReceipt(data, shopInfo);
          snack('Resit dicetak');
        } catch(e){ snack('Gagal cetak: '+e.message, true); }
      }
    } catch(e){
      snack('Ralat: '+e.message, true);
    } finally {
      $('btnSave').disabled = false;
    }
  }

  function resetForm(){
    ['nama','tel','telWasap','model','catatan','password','promo'].forEach(id=>$(id).value='');
    $('deposit').value='0'; $('diskaun').value='0';
    state.items=[{nama:'',qty:1,harga:0}]; renderItems();
    state.patternPts=[]; $('patternTxt').textContent='-';
    document.querySelectorAll('.cj-pattern-dot').forEach(x=>x.classList.remove('is-on'));
    state.kodVoucher=''; state.voucherAmt=0; $('promoMsg').textContent='';
    state.imgDepan=null; state.imgBelakang=null;
    document.querySelectorAll('.cj-snap-card').forEach(c=>{
      c.style.backgroundImage=''; const k=c.dataset.k; c.innerHTML = `<i class="fas fa-camera fa-2x"></i><div>${k.toUpperCase()}</div>`;
    });
    state.custType='NEW CUST'; document.querySelectorAll('#custTypeToggle button').forEach(b=>b.classList.toggle('is-active', b.dataset.v==='NEW CUST'));
    $('custSearchRow').hidden=true;
    state.jenisServis='TAK PASTI'; $('jenisServis').value='TAK PASTI';
    state.paymentStatus='UNPAID'; $('paymentStatus').value='UNPAID';
    state.caraBayaran='TAK PASTI'; $('caraBayaran').value='TAK PASTI';
    state.savedSiri=''; state.savedData=null; state.isLocked=false;
    state.tarikhEdited=false; state.tarikh=new Date(); setTarikhInput();
    $('siriBadge').hidden=true;
    state.step=0; renderStep();
  }

  // ─── init ───
  renderStep();
  loadData();
})();
