/* senarai_job.js — Supabase. Mirror senarai_job_screen.dart (list + filter + stats + edit modal). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const STATUSES = ['IN PROGRESS','WAITING PART','READY TO PICKUP','COMPLETED','CANCEL','REJECT','OVERDUE'];

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fmtDate = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    return `${d.getDate().toString().padStart(2,'0')}/${(d.getMonth()+1).toString().padStart(2,'0')}/${d.getFullYear()}`;
  };

  let ALL = [];
  let filter = { s: 'ALL', time: 'ALL', from: null, to: null, sort: 'TARIKH_DESC', q: '' };

  async function fetchJobs() {
    const { data, error } = await window.sb
      .from('jobs')
      .select('*')
      .eq('branch_id', branchId)
      .order('created_at', { ascending: false })
      .limit(2000);
    if (error) { console.error('jobs fetch:', error); return []; }
    return data || [];
  }

  function applyFilter(rows) {
    let out = rows.slice();
    if (filter.s !== 'ALL') out = out.filter((r) => (r.status || '').toUpperCase() === filter.s);

    const now = new Date(); now.setHours(0,0,0,0);
    let from = null, to = null;
    if (filter.time === 'TODAY') { from = now; }
    else if (filter.time === 'WEEK') { from = new Date(now); from.setDate(now.getDate() - 7); }
    else if (filter.time === 'MONTH') { from = new Date(now.getFullYear(), now.getMonth(), 1); }
    else if (filter.time === 'CUSTOM') {
      if (filter.from) from = new Date(filter.from);
      if (filter.to) { to = new Date(filter.to); to.setHours(23,59,59,999); }
    }
    if (from) out = out.filter((r) => r.created_at && new Date(r.created_at) >= from);
    if (to) out = out.filter((r) => r.created_at && new Date(r.created_at) <= to);

    if (filter.q) {
      const q = filter.q.toLowerCase();
      out = out.filter((r) =>
        (r.siri || '').toLowerCase().includes(q) ||
        (r.nama || '').toLowerCase().includes(q) ||
        (r.tel || '').toLowerCase().includes(q)
      );
    }

    out.sort((a, b) => {
      switch (filter.sort) {
        case 'TARIKH_ASC': return (a.created_at || '').localeCompare(b.created_at || '');
        case 'NAMA_ASC': return (a.nama || '').localeCompare(b.nama || '');
        case 'NAMA_DESC': return (b.nama || '').localeCompare(a.nama || '');
        default: return (b.created_at || '').localeCompare(a.created_at || '');
      }
    });

    return out;
  }

  function renderStats(rows) {
    $('stCount').textContent = rows.length;
    $('stProg').textContent = rows.filter((r) => (r.status || '').toUpperCase() === 'IN PROGRESS').length;
    $('stReady').textContent = rows.filter((r) => (r.status || '').toUpperCase() === 'READY TO PICKUP').length;
    $('stDone').textContent = rows.filter((r) => (r.status || '').toUpperCase() === 'COMPLETED').length;
  }

  function renderList(rows) {
    const host = $('sjList');
    const empty = $('sjEmpty');
    if (!rows.length) { host.innerHTML = ''; empty.hidden = false; return; }
    empty.hidden = true;
    host.innerHTML = rows.map((r) => {
      const st = (r.status || 'IN PROGRESS').toUpperCase();
      const ps = (r.payment_status || 'PENDING').toUpperCase();
      return `<div class="sj-item" data-id="${r.id}">
        <div class="sj-item__head">
          <span class="sj-item__siri">${r.siri || ''}</span>
          <span class="sj-item__status" data-st="${st}">${st}</span>
        </div>
        <div class="sj-item__body">
          <div><i class="fas fa-user"></i> ${r.nama || '—'}</div>
          <div><i class="fas fa-phone"></i> ${r.tel || '—'}</div>
          <div><i class="fas fa-mobile"></i> ${r.model || '—'}</div>
          <div><i class="fas fa-wrench"></i> ${r.kerosakan || '—'}</div>
        </div>
        <div class="sj-item__foot">
          <span><i class="fas fa-calendar"></i> ${fmtDate(r.created_at)}</span>
          <span>${fmtRM(r.total || r.harga)}</span>
          <span class="sj-pay" data-ps="${ps}">${ps}</span>
        </div>
      </div>`;
    }).join('');
    host.querySelectorAll('.sj-item').forEach((el) => {
      el.addEventListener('click', () => openModal(el.dataset.id));
    });
  }

  function refresh() {
    const filtered = applyFilter(ALL);
    renderStats(filtered);
    renderList(filtered);
  }

  async function openModal(id) {
    const job = ALL.find((j) => j.id === id);
    if (!job) return;
    const modal = $('jobModal');
    const bg = $('jobModalBg');
    modal.innerHTML = `
      <button class="sj-close" id="mClose">✕</button>
      <h3><i class="fas fa-screwdriver-wrench"></i> ${job.siri}</h3>
      <div class="sj-status-btns" id="mStatus">
        ${STATUSES.map((s) => `<button data-s="${s}" class="${(job.status||'').toUpperCase()===s?'is-active':''}">${s}</button>`).join('')}
      </div>
      <div class="sj-grid">
        <div class="sj-field"><label>Nama</label><input id="fNama" value="${job.nama||''}"></div>
        <div class="sj-field"><label>Telefon</label><input id="fTel" value="${job.tel||''}"></div>
        <div class="sj-field"><label>Model</label><input id="fModel" value="${job.model||''}"></div>
        <div class="sj-field"><label>Kerosakan</label><input id="fKero" value="${job.kerosakan||''}"></div>
        <div class="sj-field"><label>Harga</label><input type="number" step="0.01" id="fHarga" value="${job.harga||0}"></div>
        <div class="sj-field"><label>Deposit</label><input type="number" step="0.01" id="fDep" value="${job.deposit||0}"></div>
        <div class="sj-field"><label>Total</label><input type="number" step="0.01" id="fTotal" value="${job.total||0}"></div>
        <div class="sj-field"><label>Baki</label><input type="number" step="0.01" id="fBaki" value="${job.baki||0}"></div>
        <div class="sj-field"><label>Payment</label>
          <select id="fPay">
            <option value="PENDING" ${job.payment_status==='PENDING'?'selected':''}>PENDING</option>
            <option value="PARTIAL" ${job.payment_status==='PARTIAL'?'selected':''}>PARTIAL</option>
            <option value="PAID" ${job.payment_status==='PAID'?'selected':''}>PAID</option>
          </select>
        </div>
        <div class="sj-field"><label>Catatan</label><textarea id="fCat" rows="2">${job.catatan||''}</textarea></div>
      </div>
      <div class="sj-actions">
        <button class="btn-save" id="mSave"><i class="fas fa-save"></i> SIMPAN</button>
        <button class="btn-wa" id="mWa"><i class="fab fa-whatsapp"></i> WHATSAPP</button>
        <button class="btn-print" id="mPrint"><i class="fas fa-print"></i> CETAK</button>
        <button class="btn-print" id="mHist"><i class="fas fa-clock-rotate-left"></i> SEJARAH</button>
        <button class="btn-del" id="mDel"><i class="fas fa-trash"></i> PADAM</button>
      </div>
      <div id="mHistBox" hidden style="margin-top:10px;padding:10px;background:#f1f5f9;border-radius:8px;font-size:12px;"></div>`;
    bg.classList.add('is-open');

    let newStatus = job.status;
    modal.querySelectorAll('#mStatus button').forEach((b) => {
      b.addEventListener('click', () => {
        modal.querySelectorAll('#mStatus button').forEach((x) => x.classList.remove('is-active'));
        b.classList.add('is-active');
        newStatus = b.dataset.s;
      });
    });

    $('mClose').addEventListener('click', () => bg.classList.remove('is-open'));
    bg.addEventListener('click', (e) => { if (e.target === bg) bg.classList.remove('is-open'); });

    $('mSave').addEventListener('click', async () => {
      const originalStatus = (job.status || '').toUpperCase();
      const upStatus = (newStatus || '').toUpperCase();
      const nowIso = new Date().toISOString();
      const patch = {
        status: newStatus,
        payment_status: $('fPay').value,
        nama: $('fNama').value,
        tel: $('fTel').value,
        model: $('fModel').value,
        kerosakan: $('fKero').value,
        harga: Number($('fHarga').value) || 0,
        deposit: Number($('fDep').value) || 0,
        total: Number($('fTotal').value) || 0,
        baki: Number($('fBaki').value) || 0,
        catatan: $('fCat').value,
      };
      // Auto-stamp lifecycle timestamps (mirror Flutter)
      if (upStatus === 'READY TO PICKUP' && !job.tarikh_siap) patch.tarikh_siap = nowIso;
      if (upStatus === 'COMPLETED') {
        if (!job.tarikh_siap) patch.tarikh_siap = nowIso;
        patch.tarikh_pickup = nowIso;
      }

      const { error } = await window.sb.from('jobs').update(patch).eq('id', job.id);
      if (error) return alert('Gagal simpan: ' + error.message);

      // Timeline log on status change
      if (upStatus !== originalStatus) {
        try {
          await window.sb.from('job_timeline').insert({
            tenant_id: ctx.tenant_id, job_id: job.id, status: newStatus,
            note: nowIso, by_user: ctx.nama || ctx.id,
          });
        } catch (_) {}
      }

      // Inventory side-effects on lifecycle transition (mirror Flutter line 2770)
      const becameDone = (upStatus === 'READY TO PICKUP' || upStatus === 'COMPLETED') &&
                        originalStatus !== 'READY TO PICKUP' && originalStatus !== 'COMPLETED';
      const becameCancel = upStatus === 'CANCEL' &&
                          (originalStatus === 'READY TO PICKUP' || originalStatus === 'COMPLETED');
      if (becameDone || becameCancel) {
        try {
          const { data: items } = await window.sb.from('job_items').select('nama,qty').eq('job_id', job.id);
          for (const it of (items || [])) {
            const qty = Number(it.qty) || 0;
            if (!qty || !it.nama) continue;
            let parts = null;
            const byName = await window.sb.from('stock_parts')
              .select('id,qty').eq('tenant_id', ctx.tenant_id)
              .eq('part_name', it.nama).limit(1);
            if (byName.data && byName.data.length) parts = byName.data;
            else {
              const bySku = await window.sb.from('stock_parts')
                .select('id,qty').eq('tenant_id', ctx.tenant_id)
                .eq('sku', it.nama).limit(1);
              parts = (bySku.data && bySku.data.length) ? bySku.data : null;
            }
            if (!parts) continue;
            const cur = Number(parts[0].qty) || 0;
            const newQty = becameCancel ? cur + qty : Math.max(0, cur - qty);
            await window.sb.from('stock_parts').update({ qty: newQty }).eq('id', parts[0].id);
          }
        } catch (_) {}
      }

      bg.classList.remove('is-open');
      ALL = await fetchJobs();
      refresh();
    });

    $('mWa').addEventListener('click', () => {
      const tel = ($('fTel').value || '').replace(/[^\d]/g, '');
      if (!tel) return alert('Tel tak sah');
      const msg = `Salam, job ${job.siri} status: ${newStatus}. Terima kasih.`;
      const prefix = tel.startsWith('0') ? '6' + tel : tel;
      window.open(`https://wa.me/${prefix}?text=${encodeURIComponent(msg)}`, '_blank');
    });

    $('mPrint').addEventListener('click', async () => {
      const P = window.RmsPrinter;
      if (!P || !P.isConnected || !P.isConnected()) { alert('Printer tidak disambung. Klik butang PRINTER dulu.'); return; }
      const { data: items } = await window.sb.from('job_items').select('*').eq('job_id', job.id);
      const { data: br } = await window.sb.from('branches').select('*').eq('id', branchId).single();
      try {
        await P.printReceipt(Object.assign({}, job, { items_array: items || [] }), br || {});
      } catch (e) { alert('Gagal cetak: ' + e.message); }
    });

    $('mHist').addEventListener('click', async () => {
      const box = $('mHistBox');
      box.hidden = false;
      box.innerHTML = '<i>Memuatkan...</i>';
      try {
        const { data } = await window.sb.from('job_timeline')
          .select('status,note,by_user,created_at')
          .eq('job_id', job.id).order('created_at', { ascending: true });
        if (!data || !data.length) { box.innerHTML = '<i>Tiada sejarah.</i>'; return; }
        box.innerHTML = '<b>SEJARAH STATUS:</b><br>' + data.map((t) =>
          `<div style="padding:4px 0;border-bottom:1px solid #e2e8f0;">
            <b>${t.status}</b> · ${fmtDate(t.created_at)} · ${t.by_user || '—'}
          </div>`
        ).join('');
      } catch (e) { box.innerHTML = 'Gagal: ' + e.message; }
    });

    $('mDel').addEventListener('click', async () => {
      if (!confirm(`Padam job ${job.siri}?`)) return;
      const { error } = await window.sb.from('jobs').delete().eq('id', job.id);
      if (error) return alert('Gagal padam: ' + error.message);
      bg.classList.remove('is-open');
      ALL = await fetchJobs();
      refresh();
    });
  }

  document.querySelectorAll('#sjPills .sj-pill').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#sjPills .sj-pill').forEach((b) => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      filter.s = btn.dataset.s;
      refresh();
    });
  });
  $('fTime') && $('fTime').addEventListener('change', (e) => { filter.time = e.target.value; refresh(); });
  $('fFrom') && $('fFrom').addEventListener('change', (e) => { filter.from = e.target.value; filter.time = 'CUSTOM'; $('fTime').value='CUSTOM'; refresh(); });
  $('fTo') && $('fTo').addEventListener('change', (e) => { filter.to = e.target.value; filter.time = 'CUSTOM'; $('fTime').value='CUSTOM'; refresh(); });
  $('btnClearRange') && $('btnClearRange').addEventListener('click', () => { filter.from = null; filter.to = null; filter.time='ALL'; $('fFrom').value=''; $('fTo').value=''; $('fTime').value='ALL'; refresh(); });
  $('fSort') && $('fSort').addEventListener('change', (e) => { filter.sort = e.target.value; refresh(); });
  $('fSearch') && $('fSearch').addEventListener('input', (e) => { filter.q = e.target.value; refresh(); });
  $('btnExport') && $('btnExport').addEventListener('click', () => {
    const rows = applyFilter(ALL);
    const header = ['Siri','Tarikh','Nama','Telefon','Model','Kerosakan','Status','Payment','Harga','Total'];
    const csv = [header.join(',')].concat(rows.map((r) => [
      r.siri, fmtDate(r.created_at), r.nama, r.tel, r.model, r.kerosakan, r.status, r.payment_status, r.harga, r.total,
    ].map((v) => `"${String(v||'').replace(/"/g,'""')}"`).join(','))).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `senarai_job_${Date.now()}.csv`;
    a.click();
  });

  window.sb.channel('jobs-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'jobs', filter: `branch_id=eq.${branchId}` }, async () => {
      ALL = await fetchJobs();
      refresh();
    })
    .subscribe();

  ALL = await fetchJobs();
  refresh();

  // Printer button + label
  (function wirePrinter() {
    const btn = document.getElementById('posPrinterBtn');
    const lbl = document.getElementById('posPrinterLbl');
    if (!btn) return;
    const update = () => {
      const P = window.RmsPrinter;
      const on = !!(P && P.isConnected && P.isConnected());
      btn.classList.toggle('is-on', on);
      if (lbl) lbl.textContent = on ? (P.getName() || 'ON') : 'PRINTER';
    };
    if (window.RmsPrinter) window.RmsPrinter.onChange(update);
    btn.addEventListener('click', async () => {
      const P = window.RmsPrinter; if (!P) return;
      if (P.isConnected()) { await P.disconnect(); await P.disconnectUSB(); return; }
      try {
        if (P.bleSupported()) await P.connect();
        else if (P.usbSupported()) await P.connectUSB();
      } catch (e) { alert(e.message); }
    });
    update();
  })();
})();
