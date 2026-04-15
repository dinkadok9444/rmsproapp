/* kewangan.js — Supabase. Mirror kewangan_screen.dart. Aggregate jobs/quick_sales/phone_sales/expenses. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fmtDT = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
  };

  let segment = 0; // 0=kewangan, 1=jualan telefon
  let DATA = { JOBS: [], QS: [], PS: [], EXP: [] };
  let filters = { time: 'TODAY', sort: 'DESC', search: '', phoneType: 'CUSTOMER' };

  async function fetchAll() {
    const [j, qs, ps, ex] = await Promise.all([
      window.sb.from('jobs').select('id,siri,nama,total,payment_status,status,created_at').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(5000),
      window.sb.from('quick_sales').select('*').eq('branch_id', branchId).order('sold_at', { ascending: false }).limit(5000),
      window.sb.from('phone_sales').select('*').eq('branch_id', branchId).is('deleted_at', null).order('sold_at', { ascending: false }).limit(5000),
      window.sb.from('expenses').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(5000),
    ]);
    DATA.JOBS = j.data || [];
    DATA.QS = qs.data || [];
    DATA.PS = ps.data || [];
    DATA.EXP = ex.data || [];
  }

  function inTime(iso) {
    if (filters.time === 'ALL' || !iso) return filters.time === 'ALL';
    const d = new Date(iso); const now = new Date();
    if (filters.time === 'TODAY') return d.toDateString() === now.toDateString();
    if (filters.time === 'WEEK') { const delta = (now - d) / 86400000; return delta >= 0 && delta < 7; }
    if (filters.time === 'MONTH') return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
    if (filters.time === 'YEAR') return d.getFullYear() === now.getFullYear();
    return true;
  }

  function buildRows() {
    if (segment === 1) {
      // phone sales
      return DATA.PS.filter((s) => inTime(s.sold_at)).map((s) => ({
        id: s.id, kind: 'PHONE', ts: s.sold_at,
        label: s.device_name || '—', sub: (s.customer_name || '') + ' · ' + (s.customer_phone || ''),
        amount: Number(s.total_price) || 0, sign: 1, _raw: s,
      }));
    }
    // kewangan combined
    const jobRows = DATA.JOBS.filter((j) => (j.payment_status || '').toUpperCase() === 'PAID' && inTime(j.created_at)).map((j) => ({
      id: j.id, kind: 'REPAIR', ts: j.created_at, label: j.siri || '—', sub: j.nama || '', amount: Number(j.total) || 0, sign: 1,
    }));
    const qsRows = DATA.QS.filter((q) => inTime(q.sold_at)).map((q) => ({
      id: q.id, kind: 'QUICK', ts: q.sold_at,
      label: (() => { try { const d = JSON.parse(q.description||'{}'); const base = d.siri ? ('#'+d.siri) : (q.kind||'—'); const tax = d.tax_amt ? ` · Tax ${fmtRM(d.tax_amt)}` : ''; return base + tax; } catch (_) { return q.description || q.kind || '—'; } })(),
      sub: q.sold_by || '', amount: Number(q.amount) || 0, sign: 1,
    }));
    const psRows = DATA.PS.filter((s) => inTime(s.sold_at)).map((s) => ({
      id: s.id, kind: 'PHONE', ts: s.sold_at, label: s.device_name || '—', sub: s.customer_name || '', amount: Number(s.total_price) || 0, sign: 1,
    }));
    const exRows = DATA.EXP.filter((e) => inTime(e.created_at)).map((e) => ({
      id: e.id, kind: 'EXPENSE', ts: e.created_at, label: e.description || '—', sub: e.paid_by || '', amount: Number(e.amount) || 0, sign: -1,
    }));
    return [...jobRows, ...qsRows, ...psRows, ...exRows];
  }

  function refresh() {
    document.querySelectorAll('.kw-phone-only').forEach((el) => { el.hidden = segment !== 1; });
    let rows = buildRows();
    const q = (filters.search || '').toLowerCase();
    if (q) rows = rows.filter((r) => [(r.label||''),(r.sub||'')].join(' ').toLowerCase().includes(q));
    rows.sort((a, b) => filters.sort === 'ASC' ? (a.ts||'').localeCompare(b.ts||'') : (b.ts||'').localeCompare(a.ts||''));

    const sales = rows.filter((r) => r.sign > 0).reduce((s, r) => s + r.amount, 0);
    const expense = rows.filter((r) => r.sign < 0).reduce((s, r) => s + r.amount, 0);
    $('stSales').textContent = fmtRM(sales);
    $('stExpense').textContent = fmtRM(expense);
    $('stNet').textContent = fmtRM(sales - expense);
    $('stCount').textContent = rows.length;

    $('kwEmpty').hidden = rows.length > 0;
    $('kwList').innerHTML = rows.map((r) => {
      const color = r.sign < 0 ? '#dc2626' : '#10b981';
      const sign = r.sign < 0 ? '-' : '+';
      return `<div class="kw-card" data-kind="${r.kind}">
        <div class="kw-card__hd">
          <span class="kw-card__label">${r.label}</span>
          <span class="kw-card__amt" style="color:${color};">${sign}${fmtRM(r.amount)}</span>
        </div>
        <div class="kw-card__meta">
          <span>${r.kind}</span>
          <span>${r.sub || ''}</span>
          <span>${fmtDT(r.ts)}</span>
        </div>
      </div>`;
    }).join('');
    $('listTitle').textContent = segment === 1 ? 'Senarai Jualan Telefon' : 'Senarai Rekod';
    drawChart(rows);
  }

  let chart = null;
  function drawChart(rows) {
    const cv = document.getElementById('kwChart');
    if (!cv || typeof Chart === 'undefined') return;

    // Bucket per day (last 14 days)
    const days = 14;
    const buckets = {};
    const labels = [];
    const today = new Date(); today.setHours(0,0,0,0);
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(today); d.setDate(today.getDate() - i);
      const k = d.toISOString().slice(0,10);
      labels.push(`${d.getDate()}/${d.getMonth()+1}`);
      buckets[k] = { sales: 0, expense: 0 };
    }
    rows.forEach((r) => {
      const k = r.ts ? r.ts.slice(0,10) : null;
      if (!k || !buckets[k]) return;
      if (r.sign > 0) buckets[k].sales += r.amount;
      else buckets[k].expense += r.amount;
    });
    const sales = Object.values(buckets).map((b) => b.sales);
    const expense = Object.values(buckets).map((b) => b.expense);

    if (chart) { chart.data.labels = labels; chart.data.datasets[0].data = sales; chart.data.datasets[1].data = expense; chart.update('none'); return; }
    chart = new Chart(cv.getContext('2d'), {
      type: 'line',
      data: {
        labels,
        datasets: [
          { label: 'Jualan', data: sales, borderColor: '#10b981', backgroundColor: 'rgba(16,185,129,.15)', tension: 0.3, fill: true },
          { label: 'Belanja', data: expense, borderColor: '#dc2626', backgroundColor: 'rgba(220,38,38,.12)', tension: 0.3, fill: true },
        ],
      },
      options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } }, scales: { y: { beginAtZero: true } } },
    });
  }

  document.querySelectorAll('.kw-seg-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.kw-seg-btn').forEach((b) => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      segment = Number(btn.dataset.seg);
      refresh();
    });
  });

  $('fTime').addEventListener('change', (e) => { filters.time = e.target.value; refresh(); });
  $('fSort').addEventListener('change', (e) => { filters.sort = e.target.value; refresh(); });
  $('fSearch').addEventListener('input', (e) => { filters.search = e.target.value; refresh(); });
  $('fPhoneType') && $('fPhoneType').addEventListener('change', (e) => { filters.phoneType = e.target.value; refresh(); });

  ['jobs','quick_sales','phone_sales','expenses'].forEach((table) => {
    window.sb.channel('kw-' + table + '-' + branchId)
      .on('postgres_changes', { event: '*', schema: 'public', table, filter: `branch_id=eq.${branchId}` }, async () => { await fetchAll(); refresh(); }).subscribe();
  });

  await fetchAll();
  refresh();
})();
