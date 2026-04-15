/* dashboard_summary.js — Ringkasan Jualan (today). Mirror branch_dashboard summary card. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const fmt = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', {
    minimumFractionDigits: 2, maximumFractionDigits: 2,
  });

  const setText = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };

  // Greet
  const greet = document.querySelector('.dashboard-greeting h2');
  if (greet && ctx.nama) greet.textContent = `${ctx.nama} 👋`;

  async function loadSummary() {
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);
    const isoStart = todayStart.toISOString();

    // Phone sales (active only)
    const { data: phones } = await window.sb
      .from('phone_sales')
      .select('price_per_unit, total_price, notes')
      .eq('branch_id', branchId)
      .is('deleted_at', null)
      .gte('sold_at', isoStart);

    // Quick sales (kind != REFUND/REVERSAL)
    const { data: quicks } = await window.sb
      .from('quick_sales')
      .select('amount, kind')
      .eq('branch_id', branchId)
      .gte('sold_at', isoStart);

    // Repair jobs paid today
    const { data: jobs } = await window.sb
      .from('jobs')
      .select('total, harga')
      .eq('branch_id', branchId)
      .eq('payment_status', 'PAID')
      .gte('updated_at', isoStart);

    let count = 0, sales = 0, profit = 0, unit = 0;

    (phones || []).forEach((r) => {
      count++;
      const total = Number(r.total_price || r.price_per_unit || 0);
      sales += total;
      let kos = 0;
      try { const n = typeof r.notes === 'string' ? JSON.parse(r.notes) : r.notes; kos = Number(n?.kos || 0); } catch (_) {}
      profit += total - kos;
      unit++;
    });

    (quicks || []).forEach((r) => {
      if ((r.kind || '').toUpperCase().includes('REFUND')) return;
      count++;
      sales += Number(r.amount || 0);
      profit += Number(r.amount || 0);
      unit++;
    });

    (jobs || []).forEach((r) => {
      count++;
      const t = Number(r.total || r.harga || 0);
      sales += t;
      profit += t;
      unit++;
    });

    setText('stCount', String(count));
    setText('stSales', fmt(sales));
    setText('stProfit', fmt(profit));
    setText('stUnit', String(unit));
  }

  await loadSummary();
  // Refresh every minute
  setInterval(loadSummary, 60000);
})();
