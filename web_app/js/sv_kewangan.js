/* sv_kewangan.js — Supervisor Kewangan tab. Mirror sv_kewangan_tab.dart.
   Sources: jobs (PAID, bukan JUALAN PANTAS), quick_sales (kind=JUALAN PANTAS), phone_sales, expenses.
   Compute: Jualan, Expense, Untung Kasar (Jualan - Kos Telefon), Untung Bersih (Kasar - Expense). */
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
  const tsOf = (iso) => { if (!iso) return 0; const d = new Date(iso); return isNaN(d) ? 0 : d.getTime(); };
  const fmtShort = (ts) => {
    if (!ts) return '-';
    const d = new Date(ts); const p = (n) => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth()+1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  };

  // ── State
  let filterTime = 'TODAY';
  let customFrom = null, customTo = null;
  let section = ''; // '', 'JUALAN', 'EXPENSE'
  let repairs = [], jpSales = [], phoneSales = [], expenses = [];

  // ── Data load
  async function loadAll() {
    const [j, q, p, e] = await Promise.all([
      sb.from('jobs').select('id, nama, siri, total, jenis_servis, payment_status, created_at').eq('branch_id', branchId),
      sb.from('quick_sales').select('id, description, amount, kind, created_at').eq('branch_id', branchId),
      sb.from('phone_sales').select('id, device_name, sold_price, notes, sold_at, created_at').eq('branch_id', branchId),
      sb.from('expenses').select('id, description, amount, paid_by, created_at').eq('branch_id', branchId),
    ]);
    repairs = (j.data || []).filter(d => {
      const ps = String(d.payment_status || '').toUpperCase();
      const nm = String(d.nama || '').toUpperCase();
      const js = String(d.jenis_servis || '').toUpperCase();
      return ps === 'PAID' && nm !== 'JUALAN PANTAS' && js !== 'JUALAN';
    }).map(d => ({ label: d.nama || '-', sublabel: '#' + (d.siri || '-'), jumlah: Number(d.total) || 0, ts: tsOf(d.created_at), jenis: 'REPAIR' }));
    jpSales = (q.data || []).filter(d => String(d.kind || '').toUpperCase() === 'JUALAN PANTAS')
      .map(d => ({ label: d.description || 'JUALAN PANTAS', sublabel: '#' + (d.description || '-'), jumlah: Number(d.amount) || 0, ts: tsOf(d.created_at), jenis: 'JUALAN PANTAS' }));
    phoneSales = (p.data || []).map(d => {
      const n = (d.notes && typeof d.notes === 'object') ? d.notes : {};
      const jual = d.sold_price != null ? Number(d.sold_price) : Number(n.jual) || 0;
      return { label: d.device_name || n.nama || 'TELEFON', sublabel: n.imei || '-', jumlah: jual, kos: Number(n.kos) || 0, ts: tsOf(d.sold_at || d.created_at), jenis: 'TELEFON' };
    });
    expenses = (e.data || []).map(d => ({ label: d.description || '-', sublabel: d.paid_by || '-', jumlah: Number(d.amount) || 0, ts: tsOf(d.created_at), jenis: 'EXPENSE' }));
    render();
  }

  ['jobs','quick_sales','phone_sales','expenses'].forEach(t => {
    sb.channel(`sv-kew-${t}-${branchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: t, filter: `branch_id=eq.${branchId}` }, loadAll)
      .subscribe();
  });

  // ── Filter
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
        const f = new Date(customFrom); const t = new Date(customTo); t.setHours(23,59,59,999);
        return d >= f && d <= t;
      }
      default: return true;
    }
  }

  // ── Render
  function render() {
    const fR = repairs.filter(r => inRange(r.ts));
    const fJ = jpSales.filter(r => inRange(r.ts));
    const fP = phoneSales.filter(r => inRange(r.ts));
    const fE = expenses.filter(r => inRange(r.ts));

    const tR = fR.reduce((s,r)=>s+r.jumlah,0);
    const tJ = fJ.reduce((s,r)=>s+r.jumlah,0);
    const tP = fP.reduce((s,r)=>s+r.jumlah,0);
    const tPkos = fP.reduce((s,r)=>s+(r.kos||0),0);
    const totalJualan = tR + tJ + tP;
    const totalExpense = fE.reduce((s,r)=>s+r.jumlah,0);
    const kasar = totalJualan - tPkos;
    const bersih = kasar - totalExpense;

    $('svKewBack').classList.toggle('hidden', !section);

    // Cards
    $('svKewCards').innerHTML = `
      <div class="sv-kew__card c-blue" data-sec="JUALAN">
        <div class="sv-kew__card-top"><i class="fas fa-cart-shopping"></i><i class="fas fa-chevron-right sv-kew__card-chev"></i></div>
        <div class="sv-kew__card-lbl">${esc(t('kew.jualan'))}</div>
        <div class="sv-kew__card-amt">${fmtRM(totalJualan)}</div>
      </div>
      <div class="sv-kew__card c-red" data-sec="EXPENSE">
        <div class="sv-kew__card-top"><i class="fas fa-file-invoice-dollar"></i><i class="fas fa-chevron-right sv-kew__card-chev"></i></div>
        <div class="sv-kew__card-lbl">${esc(t('kew.expense'))}</div>
        <div class="sv-kew__card-amt">${fmtRM(totalExpense)}</div>
      </div>
      <div class="sv-kew__card ${kasar>=0?'c-green':'c-red'}">
        <div class="sv-kew__card-top"><i class="fas fa-scale-balanced"></i></div>
        <div class="sv-kew__card-lbl">${esc(t('kew.kasar'))}</div>
        <div class="sv-kew__card-amt">${fmtRM(kasar)}</div>
      </div>
      <div class="sv-kew__card ${bersih>=0?'c-green':'c-red'}">
        <div class="sv-kew__card-top"><i class="fas fa-face-${bersih>=0?'smile':'frown'}"></i></div>
        <div class="sv-kew__card-lbl">${esc(t('kew.bersih'))}</div>
        <div class="sv-kew__card-amt">${fmtRM(bersih)}</div>
      </div>`;

    // Body
    if (section === 'JUALAN') {
      const all = [...fR, ...fJ, ...fP].sort((a,b)=>b.ts-a.ts);
      $('svKewBody').innerHTML = renderList(t('kew.listSales'), all, false);
    } else if (section === 'EXPENSE') {
      const sorted = fE.slice().sort((a,b)=>b.ts-a.ts);
      $('svKewBody').innerHTML = renderList(t('kew.listExpense'), sorted, true);
    } else {
      $('svKewBody').innerHTML = renderOverview(tR, tJ, tP, tPkos, totalExpense, totalJualan, kasar, bersih);
    }
  }

  function renderOverview(r, j, p, pKos, expense, jualanTotal, kasar, bersih) {
    const bar = (label, amt, total, color) => {
      const pct = total > 0 ? (amt/total*100) : 0;
      return `<div class="sv-kew__bar">
        <div class="sv-kew__bar-row">
          <span class="sv-kew__bar-dot" style="background:${color}"></span>
          <span class="sv-kew__bar-lbl">${esc(label)}</span>
          <span class="sv-kew__bar-amt">${fmtRM(amt)}</span>
          <span class="sv-kew__bar-pct" style="color:${color}">${pct.toFixed(0)}%</span>
        </div>
        <div class="sv-kew__bar-track"><div class="sv-kew__bar-fill" style="width:${pct}%;background:${color}"></div></div>
      </div>`;
    };
    const line = (label, amt, minus) => `<div class="sv-kew__fl">
      ${minus ? '<span class="sv-kew__fl-minus">(-)</span>' : ''}
      <span class="sv-kew__fl-lbl">${esc(label)}</span>
      <span class="sv-kew__fl-amt">${fmtRM(amt)}</span>
    </div>`;
    const fbox = (lines, resLbl, resVal) => {
      const pos = resVal >= 0;
      return `<div class="sv-kew__formula">
        ${lines.join('')}
        <div class="sv-kew__fl-div"></div>
        <div class="sv-kew__fl sv-kew__fl-result" style="color:${pos?'#10B981':'#EF4444'}">
          <span class="sv-kew__fl-lbl" style="color:inherit;font-weight:900">${esc(resLbl)}</span>
          <span class="sv-kew__fl-amt" style="color:inherit;font-size:16px">${fmtRM(resVal)}</span>
        </div>
      </div>`;
    };
    return `
      <div class="sv-kew__sec-title" style="color:#3B82F6"><i class="fas fa-chart-bar"></i><span>${esc(t('kew.pecahan'))}</span></div>
      ${bar(t('kew.repair'), r, jualanTotal, '#06B6D4')}
      ${bar(t('kew.quickSale'), j, jualanTotal, '#3B82F6')}
      ${bar(t('kew.phone'), p, jualanTotal, '#8B5CF6')}
      <div class="sv-kew__sec-title" style="color:#10B981"><i class="fas fa-calculator"></i><span>${esc(t('kew.kasar'))}</span></div>
      ${fbox([line(t('kew.totalSales'), jualanTotal, false), line(t('kew.costPhone'), pKos, true)], t('kew.kasar'), kasar)}
      <div class="sv-kew__sec-title" style="color:${bersih>=0?'#10B981':'#EF4444'}"><i class="fas fa-calculator"></i><span>${esc(t('kew.bersih'))}</span></div>
      ${fbox([line(t('kew.kasar'), kasar, false), line(t('kew.expenseLbl'), expense, true)], t('kew.bersih'), bersih)}
    `;
  }

  function renderList(title, records, isExpense) {
    if (!records.length) {
      return `<div class="sv-kew__empty"><i class="fas fa-${isExpense?'file-invoice':'coins'}"></i><div>${esc(t('c.none'))}</div></div>`;
    }
    const color = (j) => j === 'REPAIR' ? '#06B6D4' : j === 'JUALAN PANTAS' ? '#3B82F6' : j === 'TELEFON' ? '#8B5CF6' : '#EF4444';
    return records.map(r => {
      const col = color(r.jenis);
      const tag = isExpense ? 'EXPENSE' : r.jenis;
      return `<div class="sv-kew__row">
        <span class="sv-kew__row-tag" style="color:${col};background:${col}1a">${esc(tag)}</span>
        <div class="sv-kew__row-mid">
          <div class="sv-kew__row-lbl">${esc(r.label)}</div>
          <div class="sv-kew__row-sub">${esc(r.sublabel || '-')} | ${fmtShort(r.ts)}</div>
        </div>
        <div class="sv-kew__row-amt" style="color:${isExpense?'#EF4444':'#10B981'}">${isExpense?'-':'+'}${fmtRM(r.jumlah)}</div>
      </div>`;
    }).join('');
  }

  // ── Events
  $('svKewTime').addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    filterTime = b.dataset.t;
    $('svKewTime').querySelectorAll('button').forEach(x => x.classList.toggle('is-active', x === b));
    $('svKewRange').classList.toggle('hidden', filterTime !== 'CUSTOM');
    render();
  });
  $('svKewFrom').addEventListener('change', (e) => { customFrom = e.target.value; render(); });
  $('svKewTo').addEventListener('change', (e) => { customTo = e.target.value; render(); });
  $('svKewBack').addEventListener('click', () => { section = ''; render(); });
  $('svKewCards').addEventListener('click', (e) => {
    const c = e.target.closest('.sv-kew__card[data-sec]'); if (!c) return;
    section = c.dataset.sec; render();
  });

  window.addEventListener('sv:lang:changed', render);

  await loadAll();
})();
