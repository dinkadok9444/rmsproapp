/* Admin -> Rekod Jualan. Mirror rmsproapp/lib/screens/admin_modules/rekod_jualan_screen.dart.
   Table: tenants (id, owner_id, nama_kedai, config jsonb {ownerName, ownerContact, package/planType}, total_sales, ticket_count, created_at). */
(function () {
  'use strict';

  const PKG_PRICE = { '1': 30, '6': 150, '12': 250 };
  const FILTERS = ['Semua', 'Hari Ini', 'Minggu Ini', 'Bulan Ini'];

  let dealers = [];
  let sales = [];
  let saasFilter = 'Semua';
  let salesFilter = 'Semua';
  let searchQ = '';

  const $ = id => document.getElementById(id);
  const saasList = $('saasList');
  const salesList = $('salesList');

  $('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.querySelectorAll('.admin-tab').forEach(t => t.addEventListener('click', () => {
    document.querySelectorAll('.admin-tab').forEach(x => x.classList.remove('is-active'));
    t.classList.add('is-active');
    $('tabSaas').classList.toggle('hidden', t.dataset.tab !== 'saas');
    $('tabSales').classList.toggle('hidden', t.dataset.tab !== 'sales');
  }));
  $('saasSearch').addEventListener('input', e => { searchQ = e.target.value.toLowerCase(); renderSaas(); });

  renderChips('saasChips', () => saasFilter, v => { saasFilter = v; renderSaas(); });
  renderChips('salesChips', () => salesFilter, v => { salesFilter = v; renderSales(); });

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await Promise.all([loadSaas(), loadSales()]);
  })();

  function renderChips(elId, getter, setter) {
    const el = $(elId);
    el.innerHTML = FILTERS.map(f => `<button class="time-chip ${f === getter() ? 'is-active' : ''}" data-f="${esc(f)}">${esc(f)}</button>`).join('');
    el.querySelectorAll('.time-chip').forEach(b => b.addEventListener('click', () => {
      setter(b.dataset.f);
      el.querySelectorAll('.time-chip').forEach(x => x.classList.toggle('is-active', x.dataset.f === b.dataset.f));
    }));
  }

  async function loadSaas() {
    const { data, error } = await window.sb.from('tenants').select('id,owner_id,nama_kedai,config,created_at');
    if (error) { saasList.innerHTML = `<div class="admin-error">${error.message}</div>`; return; }
    dealers = (data || []).map(r => {
      const c = (r.config && typeof r.config === 'object') ? r.config : {};
      return {
        id: r.id, ownerID: r.owner_id, namaKedai: r.nama_kedai || '',
        ownerName: c.ownerName || '', ownerPhone: c.ownerContact || '',
        package: c.package || c.planType || '1', createdAt: r.created_at,
      };
    }).sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    renderSaas();
  }

  async function loadSales() {
    const { data, error } = await window.sb.from('tenants').select('id,owner_id,nama_kedai,config,total_sales,ticket_count,created_at').order('total_sales', { ascending: false }).limit(100);
    if (error) { salesList.innerHTML = `<div class="admin-error">${error.message}</div>`; return; }
    sales = (data || []).map(r => {
      const c = (r.config && typeof r.config === 'object') ? r.config : {};
      return {
        id: r.id, ownerID: r.owner_id, namaKedai: r.nama_kedai || '',
        ownerName: c.ownerName || '',
        ticketCount: r.ticket_count || 0, totalSales: Number(r.total_sales || 0), createdAt: r.created_at,
      };
    });
    renderSales();
  }

  function pkgKey(d) {
    const p = String(d.package || '').trim();
    if (p.includes('12')) return '12';
    if (p.includes('6')) return '6';
    return '1';
  }

  function matchTime(ts, filter) {
    if (filter === 'Semua' || !ts) return true;
    const d = new Date(ts); if (isNaN(d)) return true;
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (filter === 'Hari Ini') return d >= today;
    if (filter === 'Minggu Ini') { const ws = new Date(today); ws.setDate(today.getDate() - ((today.getDay() + 6) % 7)); return d >= ws; }
    if (filter === 'Bulan Ini') return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
    return true;
  }

  function renderSaas() {
    const filtered = dealers.filter(d => matchTime(d.createdAt, saasFilter) && (!searchQ
      || d.namaKedai.toLowerCase().includes(searchQ)
      || (d.ownerName || '').toLowerCase().includes(searchQ)
      || (d.ownerPhone || '').toLowerCase().includes(searchQ)
      || (d.id || '').toLowerCase().includes(searchQ)));
    let total = 0, c1 = 0, c6 = 0, c12 = 0;
    for (const d of filtered) { const k = pkgKey(d); total += PKG_PRICE[k]; if (k === '1') c1++; else if (k === '6') c6++; else c12++; }
    $('saasTotal').textContent = 'RM ' + fmtRM(total);
    $('cnt1').textContent = c1; $('cnt6').textContent = c6; $('cnt12').textContent = c12;
    $('saasCount').textContent = `${filtered.length} dealer`;
    if (!filtered.length) { saasList.innerHTML = '<div class="admin-empty">Tiada rekod</div>'; return; }
    saasList.innerHTML = filtered.map(d => {
      const k = pkgKey(d);
      const lbl = k === '12' ? '12 Bulan' : k === '6' ? '6 Bulan' : '1 Bulan';
      return `
        <div class="saas-card">
          <div class="saas-card__pkg is-${k}">${k}B</div>
          <div class="saas-card__body">
            <div class="saas-card__name">${esc(d.namaKedai || '-')}</div>
            <div class="saas-card__meta"><i class="fas fa-user"></i>${esc((d.ownerName || '-') + '  \u2022  ' + (d.ownerPhone || '-'))}</div>
            <div class="saas-card__date"><i class="fas fa-calendar" style="margin-right:5px;font-size:10px"></i>${esc(fmtDate(d.createdAt))}</div>
          </div>
          <div class="saas-card__amt">
            <div class="saas-card__rm">RM ${fmtRM(PKG_PRICE[k])}</div>
            <div class="saas-card__lbl is-${k}">${lbl}</div>
          </div>
        </div>`;
    }).join('');
  }

  function renderSales() {
    const filtered = sales.filter(d => matchTime(d.createdAt, salesFilter));
    let total = 0; for (const d of filtered) total += d.totalSales;
    $('salesTotal').textContent = 'RM ' + fmtRM(total);
    $('salesCount').textContent = filtered.length;
    if (!filtered.length) { salesList.innerHTML = '<div class="admin-empty">Tiada rekod</div>'; return; }
    salesList.innerHTML = filtered.map((d, i) => {
      const rank = i + 1;
      const topCls = rank === 1 ? 'is-top1' : rank === 2 ? 'is-top2' : rank === 3 ? 'is-top3' : '';
      const icon = rank === 1 ? '<i class="fas fa-trophy"></i>' : rank === 2 ? '<i class="fas fa-medal"></i>' : rank === 3 ? '<i class="fas fa-award"></i>' : `#${rank}`;
      return `
        <div class="rank-card ${topCls}">
          <div class="rank-badge ${topCls}">${icon}</div>
          <div class="rank-card__body">
            <div class="rank-card__name">${esc(d.namaKedai || '-')}</div>
            <div class="rank-card__id">ID: ${esc(d.id || '-')}</div>
            <div class="rank-card__tix"><i class="fas fa-ticket"></i>${esc(d.ticketCount)} tiket selesai</div>
          </div>
          <div class="rank-card__total">RM ${fmtRM(d.totalSales)}</div>
        </div>`;
    }).join('');
  }

  function fmtRM(n) { return Number(n || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  function fmtDate(v) {
    if (!v) return '-'; const d = new Date(v); if (isNaN(d)) return '-';
    return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
  }
  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }
})();
