/* sv_dashboard.js — Supervisor Dashboard tab. Mirror sv_dashboard_tab.dart.
   Segment: Job Repair vs Jualan Telefon. Filter: Semua / Hari Ini / Minggu / Bulan / Tahun / Custom. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  let seg = 0; // 0=Repair, 1=Phone
  let filter = 'SEMUA';
  let rangeFrom = null, rangeTo = null;

  function rangeForFilter() {
    const now = new Date();
    const start = new Date(now); start.setHours(0, 0, 0, 0);
    if (filter === 'HARI_INI') return { from: start, to: null };
    if (filter === 'MINGGU_INI') {
      const d = new Date(start); const day = d.getDay() || 7; d.setDate(d.getDate() - (day - 1));
      return { from: d, to: null };
    }
    if (filter === 'BULAN_INI') return { from: new Date(now.getFullYear(), now.getMonth(), 1), to: null };
    if (filter === 'TAHUN_INI') return { from: new Date(now.getFullYear(), 0, 1), to: null };
    if (filter === 'CUSTOM' && rangeFrom) {
      const f = new Date(rangeFrom); const t = rangeTo ? new Date(rangeTo) : null;
      if (t) t.setHours(23, 59, 59, 999);
      return { from: f, to: t };
    }
    return { from: null, to: null };
  }

  async function fetchRepair() {
    const { from, to } = rangeForFilter();
    let q = window.sb.from('jobs').select('id, total, harga, baki, payment_status, staff_terima, created_at, status')
      .eq('branch_id', branchId).limit(5000);
    if (from) q = q.gte('created_at', from.toISOString());
    if (to) q = q.lte('created_at', to.toISOString());
    const { data } = await q;
    return data || [];
  }

  async function fetchPhone() {
    const { from, to } = rangeForFilter();
    let q = window.sb.from('phone_sales')
      .select('id, device_name, total_price, price_per_unit, sold_by, sold_at, customer_name, notes')
      .eq('branch_id', branchId).is('deleted_at', null).limit(5000);
    if (from) q = q.gte('sold_at', from.toISOString());
    if (to) q = q.lte('sold_at', to.toISOString());
    const { data } = await q;
    return data || [];
  }

  function kpiCard(label, value, color) {
    return `<div class="sv-kpi" style="background:${color}15;border-left:4px solid ${color};padding:14px;border-radius:10px;">
      <div style="font-size:10px;color:#64748b;font-weight:800;letter-spacing:.5px;">${label}</div>
      <div style="font-size:18px;font-weight:900;color:${color};margin-top:4px;">${value}</div></div>`;
  }

  function renderRepair(rows) {
    const count = rows.length;
    let sales = 0, paid = 0, outstanding = 0;
    const staffMap = {};
    rows.forEach((r) => {
      const t = Number(r.total || r.harga || 0);
      sales += t;
      if ((r.payment_status || '').toUpperCase() === 'PAID') paid += t;
      else outstanding += Number(r.baki || t);
      const s = r.staff_terima || '—';
      staffMap[s] = (staffMap[s] || 0) + 1;
    });
    const top = Object.entries(staffMap).sort((a, b) => b[1] - a[1]).slice(0, 5);
    return `
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:10px;margin-bottom:14px;">
        ${kpiCard('JUMLAH JOB', count, '#6366F1')}
        ${kpiCard('JUALAN', fmtRM(sales), '#10b981')}
        ${kpiCard('DIBAYAR', fmtRM(paid), '#2563eb')}
        ${kpiCard('OUTSTANDING', fmtRM(outstanding), '#f59e0b')}
      </div>
      <div style="background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:12px;margin-bottom:12px;">
        <div style="font-weight:900;font-size:11px;color:#475569;margin-bottom:8px;">TOP STAF</div>
        ${top.length === 0 ? '<div style="color:#94a3b8;font-size:11px;">Tiada data.</div>' :
          top.map(([nm, c]) => `<div style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #f1f5f9;">
            <span>${nm}</span><strong>${c} job</strong></div>`).join('')}
      </div>
      <div style="background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:12px;position:relative;height:240px;">
        <canvas id="svRepairChart"></canvas>
      </div>`;
  }

  function renderPhone(rows) {
    const count = rows.length;
    let sales = 0, profit = 0;
    const devMap = {};
    rows.forEach((r) => {
      const t = Number(r.total_price || r.price_per_unit || 0);
      sales += t;
      let kos = 0;
      try { const n = typeof r.notes === 'string' ? JSON.parse(r.notes) : r.notes; kos = Number(n?.kos || 0); } catch (_) {}
      profit += t - kos;
      const d = r.device_name || '—';
      devMap[d] = (devMap[d] || 0) + 1;
    });
    const top = Object.entries(devMap).sort((a, b) => b[1] - a[1]).slice(0, 5);
    return `
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:10px;margin-bottom:14px;">
        ${kpiCard('JUMLAH UNIT', count, '#6366F1')}
        ${kpiCard('JUALAN', fmtRM(sales), '#10b981')}
        ${kpiCard('UNTUNG', fmtRM(profit), '#2563eb')}
      </div>
      <div style="background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:12px;">
        <div style="font-weight:900;font-size:11px;color:#475569;margin-bottom:8px;">TOP MODEL</div>
        ${top.length === 0 ? '<div style="color:#94a3b8;font-size:11px;">Tiada data.</div>' :
          top.map(([nm, c]) => `<div style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #f1f5f9;">
            <span>${nm}</span><strong>${c} unit</strong></div>`).join('')}
      </div>`;
  }

  async function refresh() {
    const body = $('svDashBody');
    if (!body) return;
    body.innerHTML = '<div style="padding:30px;text-align:center;color:#94a3b8;">Memuatkan...</div>';
    if (seg === 0) {
      const rows = await fetchRepair();
      body.innerHTML = renderRepair(rows);
      drawRepairChart(rows);
    } else {
      const rows = await fetchPhone();
      body.innerHTML = renderPhone(rows);
    }
  }

  let svChart = null;
  function drawRepairChart(rows) {
    const cv = document.getElementById('svRepairChart');
    if (!cv || typeof Chart === 'undefined') return;
    if (svChart) { svChart.destroy(); svChart = null; }
    // Bucket per day, last 14 days, count + total
    const days = 14;
    const today = new Date(); today.setHours(0,0,0,0);
    const labels = [], countArr = [], salesArr = [];
    const buckets = {};
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(today); d.setDate(today.getDate() - i);
      const k = d.toISOString().slice(0,10);
      labels.push(`${d.getDate()}/${d.getMonth()+1}`);
      buckets[k] = { count: 0, sales: 0 };
    }
    rows.forEach((r) => {
      const k = r.created_at ? r.created_at.slice(0,10) : null;
      if (!k || !buckets[k]) return;
      buckets[k].count++;
      buckets[k].sales += Number(r.total || r.harga || 0);
    });
    Object.values(buckets).forEach((b) => { countArr.push(b.count); salesArr.push(b.sales); });
    svChart = new Chart(cv.getContext('2d'), {
      type: 'bar',
      data: {
        labels,
        datasets: [
          { type: 'bar', label: 'Job', data: countArr, backgroundColor: 'rgba(99,102,241,.7)', yAxisID: 'y' },
          { type: 'line', label: 'RM', data: salesArr, borderColor: '#10b981', backgroundColor: 'rgba(16,185,129,.15)', tension: 0.3, fill: true, yAxisID: 'y1' },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { position: 'bottom' } },
        scales: {
          y: { type: 'linear', position: 'left', beginAtZero: true, title: { display: true, text: 'Job' } },
          y1: { type: 'linear', position: 'right', beginAtZero: true, grid: { drawOnChartArea: false }, title: { display: true, text: 'RM' } },
        },
      },
    });
  }

  // ── Segment toggle ────────────────────────────────────────
  document.querySelectorAll('#svSeg .sv-seg__btn').forEach((b) => {
    b.addEventListener('click', () => {
      document.querySelectorAll('#svSeg .sv-seg__btn').forEach((x) => x.classList.remove('is-active'));
      b.classList.add('is-active');
      seg = Number(b.dataset.seg);
      refresh();
    });
  });

  // ── Filter ────────────────────────────────────────────────
  const fSel = $('svFilter');
  if (fSel) fSel.addEventListener('change', (e) => {
    filter = e.target.value;
    const pick = $('svRangePick');
    if (pick) pick.classList.toggle('hidden', filter !== 'CUSTOM');
    refresh();
  });
  const rf = $('svRangeFrom'); if (rf) rf.addEventListener('change', (e) => { rangeFrom = e.target.value; refresh(); });
  const rt = $('svRangeTo'); if (rt) rt.addEventListener('change', (e) => { rangeTo = e.target.value; refresh(); });

  window.addEventListener('sv:dashboard:refresh', refresh);

  await refresh();
  setInterval(refresh, 90000);
})();
