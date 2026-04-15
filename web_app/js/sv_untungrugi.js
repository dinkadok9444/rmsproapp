/* sv_untungrugi.js — Supervisor Untung/Rugi tab. Mirror sv_untungrugi_tab.dart.
   3 segments: REPAIR (jobs+stock_usage+expenses+losses), PHONE (phone_sales+losses),
   KEWANGAN (repair+quick_sales+phone_sales+expenses aggregated overview).
   NOTE: PDF/WA report modal not ported (Flutter uses CloudRun + native file APIs). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const sb = window.sb;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const $ = (id) => document.getElementById(id);
  const t = (k, p) => (window.svI18n ? window.svI18n.t(k, p) : k);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtRM = (n) => (n < 0 ? '-' : '') + 'RM ' + Math.abs(Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fmtRM0 = (n) => 'RM ' + Math.abs(Number(n) || 0).toLocaleString('en-MY', { maximumFractionDigits: 0 });
  const tsOf = (iso) => { if (!iso) return 0; const d = new Date(iso); return isNaN(d) ? 0 : d.getTime(); };

  // ── State
  let segment = 'REPAIR';
  let filterTime = 'TODAY';
  let customFrom = null, customTo = null;
  let repairs = [], usage = [], expenses = [], phoneSales = [], losses = [], jpSales = [];

  async function loadAll() {
    const [j, u, e, p, l, q] = await Promise.all([
      sb.from('jobs').select('id, nama, siri, total, jenis_servis, payment_status, created_at').eq('branch_id', branchId),
      sb.from('stock_usage').select('id, part_name, sku, cost, price, created_at').eq('branch_id', branchId),
      sb.from('expenses').select('id, amount, created_at').eq('branch_id', branchId),
      sb.from('phone_sales').select('id, device_name, sold_price, notes, sold_at, created_at').eq('branch_id', branchId),
      sb.from('losses').select('id, reason, item_type, estimated_value, created_at').eq('branch_id', branchId),
      sb.from('quick_sales').select('id, description, amount, kind, created_at').eq('branch_id', branchId),
    ]);
    repairs = (j.data || []).filter(d => {
      const ps = String(d.payment_status || '').toUpperCase();
      const nm = String(d.nama || '').toUpperCase();
      const js = String(d.jenis_servis || '').toUpperCase();
      return ps === 'PAID' && nm !== 'JUALAN PANTAS' && js !== 'JUALAN';
    }).map(d => ({ jumlah: Number(d.total) || 0, ts: tsOf(d.created_at) }));
    usage = (u.data || []).map(d => ({ kos: Number(d.cost) || 0, jual: Number(d.price) || 0, ts: tsOf(d.created_at) }));
    expenses = (e.data || []).map(d => ({ jumlah: Number(d.amount) || 0, ts: tsOf(d.created_at) }));
    phoneSales = (p.data || []).map(d => {
      const n = (d.notes && typeof d.notes === 'object') ? d.notes : {};
      const jual = d.sold_price != null ? Number(d.sold_price) : Number(n.jual) || 0;
      return { jual, kos: Number(n.kos) || 0, ts: tsOf(d.sold_at || d.created_at) };
    });
    losses = (l.data || []).map(d => ({ jumlah: Number(d.estimated_value) || 0, ts: tsOf(d.created_at) }));
    jpSales = (q.data || []).filter(d => String(d.kind || '').toUpperCase() === 'JUALAN PANTAS')
      .map(d => ({ jumlah: Number(d.amount) || 0, ts: tsOf(d.created_at) }));
    render();
  }

  ['jobs','stock_usage','expenses','phone_sales','losses','quick_sales'].forEach(tb => {
    sb.channel(`sv-ur-${tb}-${branchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: tb, filter: `branch_id=eq.${branchId}` }, loadAll)
      .subscribe();
  });

  function inRange(ts) {
    if (!ts) return false;
    const d = new Date(ts);
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    switch (filterTime) {
      case 'TODAY': return d >= todayStart;
      case 'THIS_WEEK': {
        const dow = now.getDay() || 7;
        const ws = new Date(todayStart); ws.setDate(ws.getDate() - (dow - 1));
        return d >= ws;
      }
      case 'THIS_MONTH': return d >= new Date(now.getFullYear(), now.getMonth(), 1);
      case 'CUSTOM': {
        if (!customFrom || !customTo) return true;
        const f = new Date(customFrom); const tt = new Date(customTo); tt.setHours(23,59,59,999);
        return d >= f && d <= tt;
      }
      default: return true;
    }
  }
  const filt = (list) => list.filter(r => inRange(r.ts));

  // ── Render
  function render() {
    const body = $('svUrBody');
    if (segment === 'REPAIR') body.innerHTML = renderRepair();
    else if (segment === 'PHONE') body.innerHTML = renderPhone();
    else body.innerHTML = renderKewangan();
  }

  function card(labelKey, value, sub, color, icon) {
    return `<div class="sv-ur__card" style="background:${color}14;border-color:${color}4d">
      <div class="sv-ur__card-ic" style="color:${color}"><i class="fas fa-${icon}"></i></div>
      <div class="sv-ur__card-lbl" style="color:${color}">${esc(labelKey)}</div>
      <div class="sv-ur__card-val" style="color:${color}">${esc(value)}</div>
      <div class="sv-ur__card-sub">${esc(sub)}</div>
    </div>`;
  }

  function renderRepair() {
    const fi = filt(repairs), fu = filt(usage), fe = filt(expenses), fl = filt(losses);
    const income = fi.reduce((s,r)=>s+r.jumlah,0);
    const modal = fu.reduce((s,r)=>s+r.kos,0);
    const exp = fe.reduce((s,r)=>s+r.jumlah,0);
    const lost = fl.reduce((s,r)=>s+r.jumlah,0);
    const profit = income - modal - exp - lost;
    const gPos = profit >= 0;
    return `<div class="sv-ur__grid">
      ${card(t('pl.count'), String(fi.length), t('pl.jobDone'), '#3B82F6', 'clipboard-check')}
      ${card(t('pl.cost'), fmtRM(modal), `${fu.length} ${t('pl.sparepart')}`, '#F59E0B', 'coins')}
      ${card(t('pl.profit'), fmtRM(profit), `${t('pl.income')}: ${fmtRM0(income)}`, gPos?'#10B981':'#EF4444', gPos?'arrow-trend-up':'arrow-trend-down')}
      ${card(t('pl.loss'), fmtRM(lost), `${fl.length} ${t('pl.records')}`, '#EF4444', 'triangle-exclamation')}
    </div>
    <div class="sv-ur__chips"><span style="background:rgba(239,68,68,0.1);color:#EF4444;border-color:rgba(239,68,68,0.3)">${esc(t('pl.expenseChip'))}: ${fmtRM0(exp)}</span></div>`;
  }

  function renderPhone() {
    const fs = filt(phoneSales), fl = filt(losses);
    const modal = fs.reduce((s,r)=>s+r.kos,0);
    const jual = fs.reduce((s,r)=>s+r.jual,0);
    const lost = fl.reduce((s,r)=>s+r.jumlah,0);
    const profit = jual - modal - lost;
    const gPos = profit >= 0;
    return `<div class="sv-ur__grid">
      ${card(t('pl.count'), String(fs.length), t('pl.unitSold'), '#3B82F6', 'mobile-screen-button')}
      ${card(t('pl.cost'), fmtRM(modal), t('pl.phoneModal'), '#F59E0B', 'coins')}
      ${card(t('pl.profit'), fmtRM(profit), `${t('pl.sales')}: ${fmtRM0(jual)}`, gPos?'#10B981':'#EF4444', gPos?'arrow-trend-up':'arrow-trend-down')}
      ${card(t('pl.loss'), fmtRM(lost), `${fl.length} ${t('pl.records')}`, '#EF4444', 'triangle-exclamation')}
    </div>`;
  }

  function renderKewangan() {
    const fR = filt(repairs), fJ = filt(jpSales), fP = filt(phoneSales), fE = filt(expenses);
    const tR = fR.reduce((s,r)=>s+r.jumlah,0);
    const tJ = fJ.reduce((s,r)=>s+r.jumlah,0);
    const tP = fP.reduce((s,r)=>s+r.jual,0);
    const tPkos = fP.reduce((s,r)=>s+r.kos,0);
    const jualanTotal = tR + tJ + tP;
    const expTotal = fE.reduce((s,r)=>s+r.jumlah,0);
    const kasar = jualanTotal - tPkos;
    const bersih = kasar - expTotal;

    const summary = `<div class="sv-ur__kw-cards">
      <div class="sv-ur__kw-card c-blue"><div class="sv-ur__kw-top"><i class="fas fa-cart-shopping"></i></div><div class="sv-ur__kw-lbl">${esc(t('kew.jualan'))}</div><div class="sv-ur__kw-amt">${fmtRM(jualanTotal)}</div></div>
      <div class="sv-ur__kw-card c-red"><div class="sv-ur__kw-top"><i class="fas fa-file-invoice-dollar"></i></div><div class="sv-ur__kw-lbl">${esc(t('kew.expense'))}</div><div class="sv-ur__kw-amt">${fmtRM(expTotal)}</div></div>
      <div class="sv-ur__kw-card ${kasar>=0?'c-green':'c-red'}"><div class="sv-ur__kw-top"><i class="fas fa-scale-balanced"></i></div><div class="sv-ur__kw-lbl">${esc(t('kew.kasar'))}</div><div class="sv-ur__kw-amt">${fmtRM(kasar)}</div></div>
      <div class="sv-ur__kw-card ${bersih>=0?'c-green':'c-red'}"><div class="sv-ur__kw-top"><i class="fas fa-face-${bersih>=0?'smile':'frown'}"></i></div><div class="sv-ur__kw-lbl">${esc(t('kew.bersih'))}</div><div class="sv-ur__kw-amt">${fmtRM(bersih)}</div></div>
    </div>`;

    const bar = (label, amt, total, color) => {
      const pct = total > 0 ? (amt/total*100) : 0;
      return `<div class="sv-kew__bar"><div class="sv-kew__bar-row"><span class="sv-kew__bar-dot" style="background:${color}"></span><span class="sv-kew__bar-lbl">${esc(label)}</span><span class="sv-kew__bar-amt">${fmtRM(amt)}</span><span class="sv-kew__bar-pct" style="color:${color}">${pct.toFixed(0)}%</span></div><div class="sv-kew__bar-track"><div class="sv-kew__bar-fill" style="width:${pct}%;background:${color}"></div></div></div>`;
    };
    const line = (label, amt, minus) => `<div class="sv-kew__fl">${minus ? '<span class="sv-kew__fl-minus">(-)</span>' : ''}<span class="sv-kew__fl-lbl">${esc(label)}</span><span class="sv-kew__fl-amt">${fmtRM(amt)}</span></div>`;
    const fbox = (lines, resLbl, resVal) => {
      const pos = resVal >= 0;
      return `<div class="sv-kew__formula">${lines.join('')}<div class="sv-kew__fl-div"></div><div class="sv-kew__fl sv-kew__fl-result" style="color:${pos?'#10B981':'#EF4444'}"><span class="sv-kew__fl-lbl" style="color:inherit;font-weight:900">${esc(resLbl)}</span><span class="sv-kew__fl-amt" style="color:inherit;font-size:16px">${fmtRM(resVal)}</span></div></div>`;
    };

    return summary + `<div class="sv-ur__kw-body">
      <div class="sv-kew__sec-title" style="color:#3B82F6"><i class="fas fa-chart-bar"></i><span>${esc(t('kew.pecahan'))}</span></div>
      ${bar(t('kew.repair'), tR, jualanTotal, '#06B6D4')}
      ${bar(t('kew.quickSale'), tJ, jualanTotal, '#3B82F6')}
      ${bar(t('kew.phone'), tP, jualanTotal, '#8B5CF6')}
      <div class="sv-kew__sec-title" style="color:#10B981"><i class="fas fa-calculator"></i><span>${esc(t('kew.kasar'))}</span></div>
      ${fbox([line(t('kew.totalSales'), jualanTotal, false), line(t('kew.costPhone'), tPkos, true)], t('kew.kasar'), kasar)}
      <div class="sv-kew__sec-title" style="color:${bersih>=0?'#10B981':'#EF4444'}"><i class="fas fa-calculator"></i><span>${esc(t('kew.bersih'))}</span></div>
      ${fbox([line(t('kew.kasar'), kasar, false), line(t('kew.expenseLbl'), expTotal, true)], t('kew.bersih'), bersih)}
    </div>`;
  }

  // ── Events
  $('svUrSegs').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-seg]'); if (!b) return;
    segment = b.dataset.seg;
    $('svUrSegs').querySelectorAll('button').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('svUrTime').addEventListener('change', (e) => {
    filterTime = e.target.value;
    $('svUrRange').classList.toggle('hidden', filterTime !== 'CUSTOM');
    render();
  });
  $('svUrFrom').addEventListener('change', (e) => { customFrom = e.target.value; render(); });
  $('svUrTo').addEventListener('change', (e) => { customTo = e.target.value; render(); });

  window.addEventListener('sv:lang:changed', render);

  await loadAll();
})();
