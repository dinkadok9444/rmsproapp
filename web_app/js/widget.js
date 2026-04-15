/* widget.js — Supabase. Dashboard widget: repair stats + kewangan + komponen search. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function toast(msg) { const t = $('wgToast'); if (!t) return; t.textContent = msg; t.hidden = false; setTimeout(() => { t.hidden = true; }, 1600); }

  let DATA = { JOBS: [], QS: [], PS: [], EXP: [], RF: [], PARTS: [] };
  let statsFilter = 'TODAY';
  let kewFilter = 'TODAY';
  let kompTab = 'bateri';

  async function fetchAll() {
    const [j, qs, ps, ex, rf, pt] = await Promise.all([
      window.sb.from('jobs').select('id,status,total,payment_status,created_at').eq('branch_id', branchId).limit(5000),
      window.sb.from('quick_sales').select('*').eq('branch_id', branchId).limit(5000),
      window.sb.from('phone_sales').select('*').eq('branch_id', branchId).is('deleted_at', null).limit(5000),
      window.sb.from('expenses').select('*').eq('branch_id', branchId).limit(5000),
      window.sb.from('refunds').select('*').eq('branch_id', branchId).limit(5000),
      window.sb.from('stock_parts').select('sku,part_name,category').eq('branch_id', branchId).limit(5000),
    ]);
    DATA.JOBS = j.data || []; DATA.QS = qs.data || []; DATA.PS = ps.data || [];
    DATA.EXP = ex.data || []; DATA.RF = rf.data || []; DATA.PARTS = pt.data || [];
  }

  function inTime(iso, period) {
    if (period === 'ALL' || !iso) return period === 'ALL';
    const d = new Date(iso); const now = new Date();
    if (period === 'TODAY') return d.toDateString() === now.toDateString();
    if (period === 'WEEK') { const delta = (now - d) / 86400000; return delta >= 0 && delta < 7; }
    if (period === 'MONTH') return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
    if (period === 'YEAR') return d.getFullYear() === now.getFullYear();
    return true;
  }

  function refreshStats() {
    const rows = DATA.JOBS.filter((r) => inTime(r.created_at, statsFilter));
    const S = (s) => rows.filter((r) => (r.status || '').toUpperCase() === s).length;
    $('wgStTotal').textContent = rows.length;
    $('wgStProg').textContent = S('IN PROGRESS');
    $('wgStWait').textContent = S('WAITING PART');
    $('wgStReady').textContent = S('READY TO PICKUP');
    $('wgStComp').textContent = S('COMPLETED');
    $('wgStCancel').textContent = S('CANCELLED');
    drawStatsChart({
      'IN PROGRESS': S('IN PROGRESS'),
      'WAITING PART': S('WAITING PART'),
      'READY PICKUP': S('READY TO PICKUP'),
      'COMPLETED': S('COMPLETED'),
      'CANCELLED': S('CANCELLED'),
    });
  }

  let statsChart = null;
  function drawStatsChart(map) {
    const cv = document.getElementById('wgStatsChart');
    if (!cv || typeof Chart === 'undefined') return;
    const labels = Object.keys(map);
    const data = Object.values(map);
    const colors = ['#2563eb','#f59e0b','#a855f7','#10b981','#dc2626'];
    if (statsChart) { statsChart.data.datasets[0].data = data; statsChart.update('none'); return; }
    statsChart = new Chart(cv.getContext('2d'), {
      type: 'doughnut',
      data: { labels, datasets: [{ data, backgroundColor: colors, borderWidth: 0 }] },
      options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom', labels: { boxWidth: 12 } } } },
    });
  }

  function refreshKew() {
    const jobPaid = DATA.JOBS.filter((r) => (r.payment_status||'').toUpperCase() === 'PAID' && inTime(r.created_at, kewFilter)).reduce((s, r) => s + (Number(r.total)||0), 0);
    const qs = DATA.QS.filter((r) => inTime(r.sold_at, kewFilter)).reduce((s, r) => s + (Number(r.amount)||0), 0);
    const ps = DATA.PS.filter((r) => inTime(r.sold_at, kewFilter)).reduce((s, r) => s + (Number(r.total_price)||0), 0);
    const exp = DATA.EXP.filter((r) => inTime(r.created_at, kewFilter)).reduce((s, r) => s + (Number(r.amount)||0), 0);
    const rf = DATA.RF.filter((r) => (r.refund_status||'').toUpperCase() === 'APPROVED' && inTime(r.created_at, kewFilter)).reduce((s, r) => s + (Number(r.refund_amount)||0), 0);
    const sales = jobPaid + qs + ps;
    $('wgKwSales').textContent = fmtRM(sales);
    $('wgKwRefund').textContent = fmtRM(rf);
    $('wgKwExp').textContent = fmtRM(exp);
    $('wgKwNet').textContent = fmtRM(sales - exp - rf);
  }

  function refreshKomp(query) {
    const q = (query || '').toLowerCase().trim();
    const list = DATA.PARTS.filter((p) => {
      if (!q) return false;
      if (!((p.part_name||'').toLowerCase().includes(q) || (p.sku||'').toLowerCase().includes(q))) return false;
      const cat = (p.category||'').toLowerCase();
      return kompTab === 'bateri' ? cat.includes('bateri') || cat.includes('battery') : cat.includes('lcd') || cat.includes('screen');
    });
    const batCount = DATA.PARTS.filter((p) => q && ((p.part_name||'').toLowerCase().includes(q) || (p.sku||'').toLowerCase().includes(q)) && ((p.category||'').toLowerCase().includes('bateri') || (p.category||'').toLowerCase().includes('battery'))).length;
    const lcdCount = DATA.PARTS.filter((p) => q && ((p.part_name||'').toLowerCase().includes(q) || (p.sku||'').toLowerCase().includes(q)) && ((p.category||'').toLowerCase().includes('lcd') || (p.category||'').toLowerCase().includes('screen'))).length;
    $('wgBatCount').textContent = batCount;
    $('wgLcdCount').textContent = lcdCount;
    const res = $('wgKompResults');
    if (!q) {
      res.innerHTML = '<div class="wg-komp-empty"><i class="fas fa-magnifying-glass"></i><div>Cari model untuk papar kod bateri/LCD</div></div>';
    } else if (!list.length) {
      res.innerHTML = '<div class="wg-komp-empty"><i class="fas fa-circle-xmark"></i><div>Tiada padanan.</div></div>';
    } else {
      res.innerHTML = list.map((p) => `<div class="wg-komp-row"><b>${p.sku||''}</b> — ${p.part_name||''}</div>`).join('');
    }
  }

  $('wgStatsFilter').addEventListener('change', (e) => { statsFilter = e.target.value; refreshStats(); });
  $('wgKewFilter').addEventListener('change', (e) => { kewFilter = e.target.value; refreshKew(); });
  $('wgKompBtn').addEventListener('click', () => refreshKomp($('wgKompInput').value));
  $('wgKompInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') refreshKomp(e.target.value); });
  document.querySelectorAll('.wg-komp-tab').forEach((b) => b.addEventListener('click', () => {
    document.querySelectorAll('.wg-komp-tab').forEach((x) => x.classList.remove('is-active'));
    b.classList.add('is-active');
    kompTab = b.dataset.tab;
    refreshKomp($('wgKompInput').value);
  }));

  ['jobs','quick_sales','phone_sales','expenses','refunds'].forEach((table) => {
    window.sb.channel('wg-' + table + '-' + branchId)
      .on('postgres_changes', { event: '*', schema: 'public', table, filter: `branch_id=eq.${branchId}` }, async () => { await fetchAll(); refreshStats(); refreshKew(); }).subscribe();
  });

  await fetchAll();
  refreshStats();
  refreshKew();

  // ─── QUOTE ROTATION (mirror _loadQuote + rotate every 8s) ───
  const FALLBACK_QUOTES = [
    'Konsisten adalah kunci kejayaan. Lakukan yang terbaik hari ini.',
    'Setiap pelanggan yang berpuas hati adalah iklan percuma untuk perniagaan anda.',
    'Kualiti kerja hari ini menentukan reputasi esok.',
    'Jangan tunggu peluang — cipta peluang.',
    'Pelanggan tidak beli produk, mereka beli pengalaman.',
    'Kejayaan datang dari disiplin harian, bukan motivasi semalam.',
    'Repair dengan hati, bukan sekadar tangan.',
    'Usaha kecil yang konsisten mengalahkan usaha besar yang sekejap.',
  ];
  const qEl = $('wgQuote');
  if (qEl) {
    let quotes = FALLBACK_QUOTES.slice();
    try {
      const { data: row } = await window.sb.from('system_settings').select('message').eq('id', 'pengumuman').maybeSingle();
      if (row && row.message) quotes.unshift(String(row.message));
    } catch (_) {}
    let qi = 0;
    const setQuote = (t) => { qEl.textContent = '"' + t + '"'; };
    setQuote(quotes[0]);
    setInterval(() => {
      qi = (qi + 1) % quotes.length;
      setQuote(quotes[qi]);
    }, 8000);
  }
})();
