/* Senarai Job — port lib/screens/modules/senarai_job_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();

  const $ = id => document.getElementById(id);
  // Pending hint dari Dashboard Widget
  let pendingStatus = 'ALL';
  try {
    const raw = localStorage.getItem('_pending_Senarai_job');
    if (raw) {
      const hint = JSON.parse(raw);
      if (hint && hint.status) pendingStatus = String(hint.status).toUpperCase();
      localStorage.removeItem('_pending_Senarai_job');
    }
  } catch (_) {}

  const state = {
    status: pendingStatus,
    filterTime: 'ALL',
    filterFrom: null,
    filterTo: null,
    filterSort: 'TARIKH_DESC',
    search: '',
    all: [],
    inventory: [],
    shopSettings: {},
    staffList: [],
    warrantyRules: {},
  };

  const fmtMoney = n => 'RM ' + (Number(n) || 0).toFixed(2);
  const num = v => { const n=parseFloat(v); return isNaN(n)?0:n; };
  function tsMs(v) {
    if (v == null) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') { const n = Number(v); return Number.isNaN(n) ? 0 : n; }
    if (v && typeof v.toMillis === 'function') return v.toMillis();
    if (v && v.seconds != null) return v.seconds * 1000;
    return 0;
  }
  function fmtDate(ms) {
    if (!ms) return '-';
    const d = new Date(ms);
    const pad = n => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }
  function snack(msg, err=false){
    const el=document.createElement('div');
    el.style.cssText='position:fixed;left:50%;bottom:20px;transform:translateX(-50%);background:'+(err?'#dc2626':'#0f172a')+';color:#fff;padding:10px 16px;border-radius:10px;z-index:9999;box-shadow:0 8px 24px rgba(0,0,0,.2);';
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

  function timeStart() {
    const now = new Date();
    const start = new Date(now); start.setHours(0,0,0,0);
    switch (state.filterTime) {
      case 'TODAY': return start.getTime();
      case 'WEEK': {
        const wd = now.getDay() === 0 ? 7 : now.getDay();
        const offset = wd % 7;
        start.setDate(start.getDate() - offset);
        return start.getTime();
      }
      case 'MONTH': start.setDate(1); return start.getTime();
      default: return 0;
    }
  }

  // listeners
  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const list = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      if (String(d.shopID || '').toUpperCase() !== shopID) return;
      const nama = String(d.nama || '').toUpperCase();
      const jenis = String(d.jenis_servis || '').toUpperCase();
      if (nama === 'JUALAN PANTAS' || jenis === 'JUALAN') return;
      list.push({ _id: doc.id, ...d, timestamp: tsMs(d.timestamp) });
    });
    state.all = list;
    render();
  }, err => console.warn('repairs:', err));

  db.collection('inventory_'+ownerID).onSnapshot(snap=>{
    const list=[]; snap.forEach(doc=>list.push({id:doc.id,...(doc.data()||{})}));
    state.inventory = list;
  }, err=>{});

  (async ()=>{
    try {
      const s=await db.collection('shops_'+ownerID).doc(shopID).get();
      if(s.exists){
        const d=s.data()||{};
        state.shopSettings=d;
        state.warrantyRules = d.warranty_rules||{};
        state.staffList = Array.isArray(d.staffList)?d.staffList.map(x=>typeof x==='string'?x:(x.name||x.nama||'')).filter(Boolean):[];
      }
    } catch(e){}
    try {
      const d=await db.collection('saas_dealers').doc(ownerID).get();
      if(d.exists){
        const dd=d.data()||{};
        if(!state.staffList.length && Array.isArray(dd.staffList)){
          state.staffList = dd.staffList.map(x=>typeof x==='string'?x:(x.name||x.nama||'')).filter(Boolean);
        }
      }
    } catch(e){}
  })();

  function filtered() {
    let data = state.all.slice();
    const q = state.search.toLowerCase().trim();
    if (q) {
      data = data.filter(d =>
        String(d.siri || '').toLowerCase().includes(q) ||
        String(d.nama || '').toLowerCase().includes(q) ||
        String(d.tel || '').toLowerCase().includes(q) ||
        String(d.model || '').toLowerCase().includes(q) ||
        String(d.kerosakan || '').toLowerCase().includes(q));
    }
    if (state.status !== 'ALL') {
      if (state.status === 'OVERDUE') {
        const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
        data = data.filter(d => {
          const s = String(d.status || '').toUpperCase();
          return d.timestamp < cutoff && s !== 'COMPLETED' && s !== 'CANCEL';
        });
      } else {
        data = data.filter(d => String(d.status || '').toUpperCase() === state.status);
      }
    }
    if (state.filterFrom != null && state.filterTo != null) {
      const from = state.filterFrom, to = state.filterTo;
      data = data.filter(d => d.timestamp >= from && d.timestamp <= to);
    } else {
      const tStart = timeStart();
      if (tStart > 0) data = data.filter(d => d.timestamp >= tStart);
    }
    switch (state.filterSort) {
      case 'TARIKH_ASC': data.sort((a,b) => (a.timestamp||0) - (b.timestamp||0)); break;
      case 'NAMA_ASC': data.sort((a,b) => String(a.nama||'').localeCompare(String(b.nama||''))); break;
      case 'NAMA_DESC': data.sort((a,b) => String(b.nama||'').localeCompare(String(a.nama||''))); break;
      default: data.sort((a,b) => (b.timestamp||0) - (a.timestamp||0));
    }
    return data;
  }

  function statusClass(s) {
    const u = String(s || '').toUpperCase();
    if (u === 'IN PROGRESS') return 'sj-status--inprogress';
    if (u === 'WAITING PART') return 'sj-status--waiting';
    if (u === 'READY TO PICKUP') return 'sj-status--ready';
    if (u === 'COMPLETED') return 'sj-status--completed';
    if (u === 'CANCEL' || u === 'CANCELLED') return 'sj-status--cancel';
    if (u === 'REJECT') return 'sj-status--reject';
    return '';
  }

  function render() {
    const arr = filtered();
    let nProg=0, nReady=0, nDone=0;
    state.all.forEach(d => {
      const s=String(d.status||'').toUpperCase();
      if(s==='IN PROGRESS') nProg++;
      else if(s==='READY TO PICKUP') nReady++;
      else if(s==='COMPLETED') nDone++;
    });
    $('stCount').textContent = state.all.length;
    $('stProg').textContent = nProg;
    $('stReady').textContent = nReady;
    $('stDone').textContent = nDone;

    const list = $('sjList');
    $('sjEmpty').hidden = arr.length > 0;
    list.innerHTML = arr.map(d => {
      const status = String(d.status || 'IN PROGRESS');
      const pay = String(d.payment_status || 'UNPAID').toUpperCase();
      const amountCls = pay === 'PAID' ? '' : 'sj-item__amount--unpaid';
      const total = num(d.total ?? d.harga);
      return `
        <div class="sj-item" data-id="${esc(d._id)}">
          <div class="sj-item__badge"><i class="fas fa-screwdriver-wrench"></i></div>
          <div class="sj-item__main">
            <div class="sj-item__title">${esc(d.nama || '-')} — ${esc(d.model || d.kerosakan || '-')}</div>
            <div class="sj-item__sub">#${esc(d.siri || d._id)} • ${esc(d.tel || '-')} ${d.kerosakan ? '• ' + esc(d.kerosakan) : ''}</div>
            <div class="sj-item__meta">
              <span><i class="fas fa-user-check"></i> T: ${esc(d.staff_terima || '-')}</span>
              <span><i class="fas fa-user-gear"></i> R: ${esc(d.staff_repair || '-')}</span>
              <span><i class="fas fa-clock"></i> ${fmtDate(d.timestamp)}</span>
            </div>
          </div>
          <div class="sj-item__right">
            <span class="sj-status ${statusClass(status)}">${esc(status)}</span>
            <div class="sj-item__amount ${amountCls}">${fmtMoney(total)}</div>
            <span class="sj-status ${pay === 'PAID' ? 'sj-status--completed' : 'sj-status--reject'}">${esc(pay)}</span>
          </div>
        </div>`;
    }).join('');
  }

  // events
  $('sjPills').addEventListener('click', e => {
    const b = e.target.closest('.sj-pill'); if (!b) return;
    state.status = b.dataset.s;
    document.querySelectorAll('.sj-pill').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('fTime').addEventListener('change', e => { state.filterTime = e.target.value; render(); });
  function updateRange(){
    const fv = $('fFrom').value, tv = $('fTo').value;
    if(fv && tv){
      const fd = new Date(fv); fd.setHours(0,0,0,0);
      const td = new Date(tv); td.setHours(23,59,59,999);
      state.filterFrom = fd.getTime();
      state.filterTo = td.getTime();
    } else {
      state.filterFrom = null; state.filterTo = null;
    }
    render();
  }
  $('fFrom').addEventListener('change', updateRange);
  $('fTo').addEventListener('change', updateRange);
  $('btnClearRange').addEventListener('click', () => {
    $('fFrom').value = ''; $('fTo').value = '';
    state.filterFrom = null; state.filterTo = null;
    render();
  });
  $('fSort').addEventListener('change', e => { state.filterSort = e.target.value; render(); });
  $('fSearch').addEventListener('input', e => { state.search = e.target.value; render(); });

  $('sjList').addEventListener('click', e=>{
    const it = e.target.closest('.sj-item'); if(!it) return;
    const id = it.dataset.id;
    const job = state.all.find(x=>x._id===id);
    if(job) openJobModal(job);
  });

  $('btnExport').addEventListener('click', ()=>{
    const arr = filtered();
    const header='siri,tarikh,nama,tel,model,kerosakan,status,payment,total,staff_terima,staff_repair,staff_serah,warranty\n';
    const rows = arr.map(d=>{
      const esc2 = s => `"${String(s==null?'':s).replace(/"/g,'""')}"`;
      return [d.siri||d._id,d.tarikh||'',d.nama||'',d.tel||'',d.model||'',d.kerosakan||'',d.status||'',d.payment_status||'UNPAID',d.total||d.harga||'0',d.staff_terima||'',d.staff_repair||'',d.staff_serah||'',d.warranty||''].map(esc2).join(',');
    }).join('\n');
    const blob=new Blob([header+rows],{type:'text/csv'});
    const a=document.createElement('a'); a.href=URL.createObjectURL(blob); a.download=`senarai_job_${Date.now()}.csv`; a.click();
  });

  // ─── DETAIL / EDIT MODAL ───
  const STATUSES = ['IN PROGRESS','WAITING PART','READY TO PICKUP','COMPLETED','CANCEL','REJECT'];
  const PAY_STATUSES = ['UNPAID','PAID'];
  const CARA_BAYARAN = ['CASH','ONLINE','QR','TAK PASTI'];

  function closeModal(){ $('jobModalBg').classList.remove('is-open'); }
  $('jobModalBg').addEventListener('click', e=>{ if(e.target===$('jobModalBg')) closeModal(); });

  function nowStr(){ const d=new Date(); const p=n=>String(n).padStart(2,'0'); return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; }

  function getLatestReadyDate(history){
    if(!Array.isArray(history)) return '';
    for(let i=history.length-1;i>=0;i--){
      if(String(history[i].status||'').toUpperCase()==='READY TO PICKUP') return history[i].timestamp||'';
    }
    return '';
  }

  function calcWarrantyItems(items, readyDate){
    if(!readyDate || !items.length) return [];
    const rules = state.warrantyRules||{};
    return items.map(it=>{
      const nama=String(it.nama||'').toLowerCase();
      let days=0, wStr='TIADA';
      for(const k of Object.keys(rules)){
        if(nama.includes(String(k).toLowerCase())){
          days = parseInt(rules[k])||0; wStr = days>0?(days+' Hari'):'TIADA'; break;
        }
      }
      let expStr='';
      if(days>0){
        const d = new Date(readyDate); d.setDate(d.getDate()+days);
        const p=n=>String(n).padStart(2,'0');
        expStr = `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}`;
      }
      return {nama:it.nama, qty:it.qty, warranty:wStr, warranty_exp:expStr};
    });
  }

  async function deductInventory(items){
    const inv = state.inventory;
    for(const it of items){
      const match = inv.find(x=>String(x.nama||'').toLowerCase()===String(it.nama||'').toLowerCase());
      if(!match) continue;
      const newQty = Math.max(0,(num(match.qty)) - (parseInt(it.qty)||1));
      try { await db.collection('inventory_'+ownerID).doc(match.id).update({qty:newQty}); } catch(e){}
    }
  }
  async function reverseInventory(items){
    const snap = await db.collection('inventory_'+ownerID).get();
    for(const it of items){
      snap.forEach(doc=>{
        const d=doc.data()||{};
        if(String(d.nama||'').toLowerCase()===String(it.nama||'').toLowerCase()){
          doc.ref.update({qty: num(d.qty) + (parseInt(it.qty)||1)}).catch(()=>{});
        }
      });
    }
  }

  async function createKewanganRecord(job){
    const siri = job.siri || job._id;
    const existing = await db.collection('kewangan_'+ownerID).where('siri','==',siri).limit(1).get().catch(()=>null);
    if(existing && !existing.empty) return;
    await db.collection('kewangan_'+ownerID).add({
      siri,
      shopID,
      tarikh: nowStr(),
      jenis: 'REPAIR',
      jumlah: num(job.total),
      cara_bayaran: job.cara_bayaran || 'CASH',
      staff: job.staff_repair || job.staff_terima || '-',
      nama: job.nama || '',
      timestamp: Date.now(),
    });
  }

  function openJobModal(job){
    // deep clone editable state
    const items = Array.isArray(job.items_array) ? JSON.parse(JSON.stringify(job.items_array)) : [];
    if(!items.length && job.kerosakan){
      items.push({nama:job.kerosakan, qty:1, harga: num(job.harga)});
    }
    let status = String(job.status||'IN PROGRESS');
    const originalStatus = status;
    let paymentStatus = String(job.payment_status||'UNPAID');
    let caraBayaran = String(job.cara_bayaran||'TAK PASTI');
    let staffBaiki = String(job.staff_repair||'');
    let staffSerah = String(job.staff_serah||'');
    let tambahan = num(job.tambahan);
    let diskaun = num(job.diskaun);
    let deposit = num(job.deposit);
    let tSiap = job.tarikh_siap||'';
    let tPickup = job.tarikh_pickup||'';
    let statusHistory = Array.isArray(job.status_history) ? JSON.parse(JSON.stringify(job.status_history)) : [];
    if(!statusHistory.length){
      statusHistory.push({status: status, timestamp: job.tarikh || nowStr()});
    }
    const editable = status !== 'COMPLETED' && status !== 'CANCEL' && status !== 'REJECT';

    function calcHarga(){ return items.reduce((s,it)=>s + num(it.qty)*num(it.harga), 0); }
    function calcTotal(){ return calcHarga() + tambahan - diskaun - deposit - num(job.voucher_used_amt); }

    const siri = job.siri || job._id;

    function renderModal(){
      const m = $('jobModal');
      const canEdit = editable;
      m.innerHTML = `
        <button class="sj-close" id="mClose"><i class="fas fa-times"></i> Tutup</button>
        <h3><i class="fas fa-file-invoice"></i> Tiket #${esc(siri)} <span class="sj-status ${statusClass(status)}">${esc(status)}</span></h3>

        <div class="sj-grid">
          <div class="sj-field"><label><i class="fas fa-user"></i> Nama</label><input value="${esc(job.nama||'')}" disabled></div>
          <div class="sj-field"><label><i class="fas fa-phone"></i> Telefon</label><input value="${esc(job.tel||'')}" disabled></div>
          <div class="sj-field"><label><i class="fas fa-mobile-alt"></i> Model</label><input value="${esc(job.model||'')}" disabled></div>
          <div class="sj-field"><label><i class="fas fa-lock"></i> Password</label><input value="${esc(job.password||'-')}" disabled></div>
          <div class="sj-field"><label><i class="fas fa-calendar"></i> Tarikh Masuk</label><input value="${esc(job.tarikh||'')}" disabled></div>
          <div class="sj-field"><label><i class="fas fa-tools"></i> Jenis Servis</label><input value="${esc(job.jenis_servis||'')}" disabled></div>
        </div>

        <div class="sj-field">
          <label><i class="fas fa-tasks"></i> Status</label>
          <div class="sj-status-btns" id="mStatusBtns">
            ${STATUSES.map(s=>`<button type="button" data-s="${s}" class="${s===status?'is-active':''}" ${canEdit?'':'disabled'}>${s}</button>`).join('')}
          </div>
        </div>

        <div class="sj-grid">
          <div class="sj-field"><label><i class="fas fa-credit-card"></i> Status Bayaran</label>
            <select id="mPay" ${canEdit?'':'disabled'}>${PAY_STATUSES.map(p=>`<option ${p===paymentStatus?'selected':''}>${p}</option>`).join('')}</select>
          </div>
          <div class="sj-field"><label><i class="fas fa-money-bill"></i> Cara Bayaran</label>
            <select id="mCara" ${canEdit?'':'disabled'}>${CARA_BAYARAN.map(c=>`<option ${c===caraBayaran?'selected':''}>${c}</option>`).join('')}</select>
          </div>
          <div class="sj-field"><label><i class="fas fa-user-gear"></i> Staff Repair</label>
            <select id="mStaffR" ${canEdit?'':'disabled'}><option value="">-</option>${state.staffList.map(s=>`<option ${s===staffBaiki?'selected':''}>${esc(s)}</option>`).join('')}</select>
          </div>
          <div class="sj-field"><label><i class="fas fa-user-check"></i> Staff Serah</label>
            <select id="mStaffS" ${canEdit?'':'disabled'}><option value="">-</option>${state.staffList.map(s=>`<option ${s===staffSerah?'selected':''}>${esc(s)}</option>`).join('')}</select>
          </div>
          <div class="sj-field"><label><i class="fas fa-calendar-check"></i> Tarikh Siap</label><input id="mTSiap" type="datetime-local" value="${esc(tSiap)}" ${canEdit?'':'disabled'}></div>
          <div class="sj-field"><label><i class="fas fa-calendar-day"></i> Tarikh Pickup</label><input id="mTPickup" type="datetime-local" value="${esc(tPickup)}" ${canEdit?'':'disabled'}></div>
        </div>

        <div class="sj-field">
          <label><i class="fas fa-list"></i> Items</label>
          <div id="mItems"></div>
          ${canEdit?'<button type="button" id="mAddItem" style="padding:8px;border:1px dashed #e2e8f0;background:#fff;border-radius:8px;cursor:pointer;"><i class="fas fa-plus"></i> Tambah Item</button>':''}
        </div>

        <div class="sj-grid">
          <div class="sj-field"><label><i class="fas fa-plus-circle"></i> Tambahan</label><input id="mTambahan" type="number" step="0.01" value="${tambahan}" ${canEdit?'':'disabled'}></div>
          <div class="sj-field"><label><i class="fas fa-percent"></i> Diskaun</label><input id="mDiskaun" type="number" step="0.01" value="${diskaun}" ${canEdit?'':'disabled'}></div>
          <div class="sj-field"><label><i class="fas fa-hand-holding-usd"></i> Deposit</label><input id="mDeposit" type="number" step="0.01" value="${deposit}" ${canEdit?'':'disabled'}></div>
          <div class="sj-field"><label><i class="fas fa-money-bill"></i> Jumlah / Baki</label><input id="mTotal" value="${fmtMoney(calcTotal())}" disabled></div>
        </div>

        <div class="sj-field"><label><i class="fas fa-sticky-note"></i> Catatan</label><textarea id="mCatatan" rows="3" ${canEdit?'':'disabled'}>${esc(job.catatan||'')}</textarea></div>

        <div class="sj-field">
          <label><i class="fas fa-history"></i> Sejarah Status</label>
          ${statusHistory.map(h=>`<div class="sj-hist"><b>${esc(h.status)}</b> — ${esc(h.timestamp||'')}</div>`).join('') || '<div class="sj-hist">-</div>'}
        </div>

        <div class="sj-field"><label><i class="fas fa-ticket-alt"></i> Voucher Dijana</label><input value="${esc(job.voucher_generated||'-')}" disabled></div>

        <div class="sj-actions">
          ${canEdit?'<button class="btn-save" id="mSave"><i class="fas fa-save"></i> Simpan Kemaskini</button>':''}
          <button class="btn-wa" id="mWA"><i class="fab fa-whatsapp"></i> WhatsApp</button>
          <button class="btn-print" id="mPrint"><i class="fas fa-print"></i> Cetak</button>
          <button class="btn-del" id="mDel"><i class="fas fa-trash"></i> Padam</button>
        </div>
      `;

      renderItems();
      bindModal();
    }

    function renderItems(){
      const w = $('mItems');
      if(!w) return;
      w.innerHTML = items.map((it,i)=>`
        <div class="sj-item-edit">
          <input data-k="nama" data-i="${i}" value="${esc(it.nama||'')}" ${editable?'':'disabled'}>
          <input data-k="qty" data-i="${i}" type="number" min="1" value="${it.qty||1}" ${editable?'':'disabled'}>
          <input data-k="harga" data-i="${i}" type="number" step="0.01" value="${num(it.harga)||''}" ${editable?'':'disabled'}>
          <button type="button" class="cj-del" data-i="${i}" ${editable && items.length>1?'':'disabled'} style="background:#fee2e2;color:#dc2626;border:none;border-radius:6px;padding:6px 10px;cursor:pointer;"><i class="fas fa-trash"></i></button>
        </div>`).join('');
      w.oninput = e=>{
        const i=+e.target.dataset.i; const k=e.target.dataset.k;
        if(!Number.isFinite(i)||!k) return;
        if(k==='qty') items[i].qty=parseInt(e.target.value)||1;
        else if(k==='harga') items[i].harga=num(e.target.value);
        else items[i][k]=e.target.value;
        $('mTotal').value = fmtMoney(calcTotal());
      };
      w.onclick = e=>{
        const b=e.target.closest('.cj-del'); if(!b) return;
        const i=+b.dataset.i;
        if(items.length>1){ items.splice(i,1); renderItems(); $('mTotal').value=fmtMoney(calcTotal()); }
      };
    }

    function bindModal(){
      $('mClose').onclick = closeModal;
      const sb = $('mStatusBtns');
      if(sb) sb.onclick = e=>{
        const b=e.target.closest('button[data-s]'); if(!b||!editable) return;
        const newStatus = b.dataset.s;
        const needReason = newStatus==='IN PROGRESS' || newStatus==='CANCEL' || newStatus==='REJECT';
        let reason='';
        if(newStatus!==status && needReason){
          reason = prompt('Sebab tukar ke '+newStatus+':') || '';
          if(!reason){ return; }
        }
        status = newStatus;
        if(status==='READY TO PICKUP' && !tSiap){ tSiap = nowStr(); const el=$('mTSiap'); if(el) el.value=tSiap; }
        if(status==='COMPLETED' && !tPickup){ tPickup = nowStr(); const el=$('mTPickup'); if(el) el.value=tPickup; }
        statusHistory.push({status, timestamp: nowStr(), ...(reason?{reason}:{})});
        renderModal();
      };
      const add = $('mAddItem'); if(add) add.onclick = ()=>{ items.push({nama:'',qty:1,harga:0}); renderItems(); };
      const bind = (id, fn)=>{ const el=$(id); if(el) el.oninput=fn; };
      bind('mTambahan', e=>{ tambahan=num(e.target.value); $('mTotal').value=fmtMoney(calcTotal()); });
      bind('mDiskaun', e=>{ diskaun=num(e.target.value); $('mTotal').value=fmtMoney(calcTotal()); });
      bind('mDeposit', e=>{ deposit=num(e.target.value); $('mTotal').value=fmtMoney(calcTotal()); });
      const mp=$('mPay'); if(mp) mp.onchange=e=>paymentStatus=e.target.value;
      const mc=$('mCara'); if(mc) mc.onchange=e=>caraBayaran=e.target.value;
      const msr=$('mStaffR'); if(msr) msr.onchange=e=>staffBaiki=e.target.value;
      const mss=$('mStaffS'); if(mss) mss.onchange=e=>staffSerah=e.target.value;
      const ms=$('mTSiap'); if(ms) ms.onchange=e=>tSiap=e.target.value;
      const mk=$('mTPickup'); if(mk) mk.onchange=e=>tPickup=e.target.value;

      $('mWA').onclick = ()=>{
        const tel = String(job.tel||job.tel_wasap||'').replace(/\D/g,'');
        if(!tel){ snack('Tiada no telefon', true); return; }
        let ph = tel; if(ph.startsWith('0')) ph='6'+ph; else if(!ph.startsWith('60')) ph='60'+ph;
        const msg = `Salam ${job.nama||''},\nTiket #${siri}\nModel: ${job.model||'-'}\nStatus: ${status}\nJumlah: ${fmtMoney(calcTotal())}`;
        window.open(`https://wa.me/${ph}?text=${encodeURIComponent(msg)}`, '_blank');
      };
      $('mPrint').onclick = async ()=>{
        // Use shared RmsPrinter jika connect (BT/USB/WiFi ESC/POS)
        if (window.RmsPrinter && RmsPrinter.isConnected()) {
          try {
            const shopInfo = {
              shopName: state.shopSettings.shopName || state.shopSettings.namaKedai || shopID,
              address: state.shopSettings.address || state.shopSettings.alamat || '',
              phone: state.shopSettings.phone || state.shopSettings.ownerContact || '-',
              notaInvoice: state.shopSettings.notaInvoice || 'Terima kasih atas sokongan anda.',
            };
            const jobData = Object.assign({}, job, {
              siri, items_array: items,
              deposit: num(deposit), diskaun: num(diskaun),
              total: calcTotal().toFixed(2),
            });
            await RmsPrinter.printReceipt(jobData, shopInfo);
            snack('Resit #' + siri + ' dicetak');
            return;
          } catch(e){ snack('Gagal cetak: '+e.message, true); return; }
        }
        // Fallback: browser print (bila RmsPrinter tidak disokong / tidak disambung)
        const w = window.open('', '_blank');
        const rows = items.map(it=>`<tr><td>${esc(it.nama)}</td><td>${it.qty}</td><td>${fmtMoney(it.harga)}</td></tr>`).join('');
        w.document.write(`<html><head><title>Tiket ${siri}</title><style>body{font-family:monospace;padding:20px;}table{width:100%;border-collapse:collapse;}td,th{border-bottom:1px dashed #999;padding:4px;text-align:left;}h2,h4{margin:4px 0;}</style></head><body>
          <h2>${esc(state.shopSettings.shopName||shopID)}</h2>
          <p>${esc(state.shopSettings.address||'')}</p>
          <h4>TIKET REPAIR #${esc(siri)}</h4>
          <p>Tarikh: ${esc(job.tarikh||'')}<br>Nama: ${esc(job.nama||'')}<br>Telefon: ${esc(job.tel||'')}<br>Model: ${esc(job.model||'')}<br>Status: ${esc(status)}</p>
          <table><thead><tr><th>Item</th><th>Qty</th><th>Harga</th></tr></thead><tbody>${rows}</tbody></table>
          <p style="text-align:right;">Jumlah: ${fmtMoney(calcHarga())}<br>Deposit: ${fmtMoney(deposit)}<br>Diskaun: ${fmtMoney(diskaun)}<br><b>Total: ${fmtMoney(calcTotal())}</b></p>
          <p>Password: ${esc(job.password||'-')}</p>
          <p>Catatan: ${esc($('mCatatan')?$('mCatatan').value:job.catatan||'')}</p>
          <script>window.print();</script></body></html>`);
        w.document.close();
      };
      $('mDel').onclick = async ()=>{
        if(!confirm('Padam tiket #'+siri+'?')) return;
        try {
          await db.collection('repairs_'+ownerID).doc(job._id).delete();
          snack('Tiket dipadam'); closeModal();
        } catch(e){ snack('Ralat: '+e.message, true); }
      };
      const sv = $('mSave');
      if(sv) sv.onclick = async ()=>{
        sv.disabled=true;
        try {
          const itemsArr = items.filter(i=>(i.nama||'').trim()).map(i=>({nama:i.nama, qty:parseInt(i.qty)||1, harga:num(i.harga)}));
          const kerosakan = itemsArr.map(i=>`${i.nama} (x${i.qty})`).join(', ');
          const readyDate = getLatestReadyDate(statusHistory);
          const wItems = calcWarrantyItems(itemsArr, readyDate);
          let warrantySummary='TIADA', warrantyExp='';
          if(wItems.length){
            warrantySummary = wItems.map(w=>`${w.nama}: ${w.warranty}`).join(', ');
            warrantyExp = wItems.reduce((a,w)=>(w.warranty_exp||'')>a?(w.warranty_exp||''):a,'');
          }
          const catatanVal = $('mCatatan') ? $('mCatatan').value : job.catatan;
          const updateData = {
            status, payment_status: paymentStatus, cara_bayaran: caraBayaran,
            staff_repair: staffBaiki, staff_serah: staffSerah,
            catatan: catatanVal,
            warranty: warrantySummary, warranty_exp: warrantyExp, warranty_items: wItems,
            items_array: itemsArr, kerosakan,
            harga: calcHarga().toFixed(2),
            tambahan: tambahan.toFixed(2),
            diskaun: diskaun.toFixed(2),
            deposit: deposit.toFixed(2),
            total: calcTotal().toFixed(2),
            baki: calcTotal().toFixed(2),
            status_history: statusHistory,
          };
          if(paymentStatus==='PAID') updateData.paid_at = Date.now();
          if(tSiap) updateData.tarikh_siap = tSiap;
          if(tPickup) updateData.tarikh_pickup = tPickup;

          await db.collection('repairs_'+ownerID).doc(job._id).update(updateData);

          if((status==='READY TO PICKUP'||status==='COMPLETED') && originalStatus!=='READY TO PICKUP' && originalStatus!=='COMPLETED'){
            await deductInventory(itemsArr);
          }
          if(status==='CANCEL' && originalStatus!=='CANCEL' && (originalStatus==='READY TO PICKUP'||originalStatus==='COMPLETED')){
            await reverseInventory(itemsArr);
          }
          if(paymentStatus==='PAID'){
            const updatedJob = {...job, total: calcTotal().toFixed(2), cara_bayaran: caraBayaran, staff_repair: staffBaiki};
            await createKewanganRecord(updatedJob);
          }
          snack('Tiket #'+siri+' berjaya dikemaskini');
          closeModal();
        } catch(e){
          snack('Ralat: '+e.message, true);
        } finally {
          sv.disabled=false;
        }
      };
    }

    renderModal();
    $('jobModalBg').classList.add('is-open');
  }

  render();
})();
