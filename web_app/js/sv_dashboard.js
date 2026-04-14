/* Supervisor > DASHBOARD tab
   Port of sv_dashboard_tab.dart (Flutter).
   Bilingual (MS / EN) via localStorage.rms_lang ('ms' default).
*/
(function () {
  'use strict';
  if (!document.body.classList.contains('supervisor-page')) return;

  // ---------- i18n ----------
  const DICT = {
    ms: {
      'dash.title': 'DASHBOARD',
      'dash.sub': 'Statistik jualan & job',
      'dash.segRepair': 'Job Repair',
      'dash.segPhone': 'Jualan Telefon',
      'dash.fAll': 'Semua',
      'dash.fToday': 'Hari Ini',
      'dash.fWeek': 'Minggu Ini',
      'dash.fMonth': 'Bulan Ini',
      'dash.fYear': 'Tahun Ini',
      'dash.fCustom': 'Pilih Tarikh',
      'dash.totalJobs': 'JUMLAH JOB',
      'dash.inProgress': 'In Progress',
      'dash.waitingPart': 'Waiting Part',
      'dash.readyPickup': 'Ready To Pickup',
      'dash.completed': 'Completed',
      'dash.cancel': 'Cancel',
      'dash.reject': 'Reject',
      'dash.salesToday': 'JUALAN HARI INI',
      'dash.unit': 'unit',
      'dash.profit': 'Profit',
      'dash.totalSales': 'Jumlah Jualan',
      'dash.totalSell': 'Jumlah Jual',
      'dash.totalCost': 'Jumlah Kos',
      'dash.totalProfit': 'Jumlah Profit',
    },
    en: {
      'dash.title': 'DASHBOARD',
      'dash.sub': 'Sales & job statistics',
      'dash.segRepair': 'Job Repair',
      'dash.segPhone': 'Phone Sales',
      'dash.fAll': 'All',
      'dash.fToday': 'Today',
      'dash.fWeek': 'This Week',
      'dash.fMonth': 'This Month',
      'dash.fYear': 'This Year',
      'dash.fCustom': 'Pick Date',
      'dash.totalJobs': 'TOTAL JOBS',
      'dash.inProgress': 'In Progress',
      'dash.waitingPart': 'Waiting Part',
      'dash.readyPickup': 'Ready To Pickup',
      'dash.completed': 'Completed',
      'dash.cancel': 'Cancel',
      'dash.reject': 'Reject',
      'dash.salesToday': 'SALES TODAY',
      'dash.unit': 'unit',
      'dash.profit': 'Profit',
      'dash.totalSales': 'Total Sales',
      'dash.totalSell': 'Total Revenue',
      'dash.totalCost': 'Total Cost',
      'dash.totalProfit': 'Total Profit',
    },
  };
  const lang = (localStorage.getItem('rms_lang') || 'ms') === 'en' ? 'en' : 'ms';
  const t = (k) => (DICT[lang] && DICT[lang][k]) || DICT.ms[k] || k;
  document.querySelectorAll('#svDash [data-i18n]').forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });

  // ---------- shell ----------
  const shell = window.SupervisorShell;
  if (!shell) return;
  const ownerID = shell.ownerID;
  const shopID = shell.shopID;
  const db = window.db;

  // ---------- state ----------
  let segment = 0;           // 0 = repair, 1 = phone
  let filter = 'SEMUA';
  let customStart = null;    // Date
  let customEnd = null;      // Date
  let repairDocs = [];
  let phoneDocs = [];
  let phoneEnabled = true;

  // ---------- helpers ----------
  const $ = (id) => document.getElementById(id);
  const body = $('svDashBody');

  function fmtMoney(n) {
    return 'RM' + (Number(n) || 0).toFixed(2);
  }
  function fmtDate(d) {
    const dd = String(d.getDate()).padStart(2, '0');
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    return `${dd}/${mm}/${d.getFullYear()}`;
  }

  function extractDate(data) {
    const ts = data.timestamp;
    if (typeof ts === 'number' && ts > 0) return new Date(ts);
    const tk = data.tarikh;
    if (typeof tk === 'string' && tk) {
      const d = new Date(tk);
      if (!isNaN(d)) return d;
    }
    return null;
  }

  function isInRange(data) {
    if (filter === 'SEMUA') return true;
    const d = extractDate(data);
    if (!d) return false;
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    switch (filter) {
      case 'HARI_INI':
        return d.getFullYear() === now.getFullYear() &&
               d.getMonth() === now.getMonth() &&
               d.getDate() === now.getDate();
      case 'MINGGU_INI': {
        const dow = today.getDay() === 0 ? 7 : today.getDay(); // Mon=1..Sun=7
        const weekStart = new Date(today); weekStart.setDate(today.getDate() - (dow - 1));
        const weekEnd = new Date(weekStart); weekEnd.setDate(weekStart.getDate() + 7);
        return d >= weekStart && d < weekEnd;
      }
      case 'BULAN_INI':
        return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
      case 'TAHUN_INI':
        return d.getFullYear() === now.getFullYear();
      case 'CUSTOM': {
        if (!customStart || !customEnd) return true;
        const s = new Date(customStart.getFullYear(), customStart.getMonth(), customStart.getDate());
        const e = new Date(customEnd.getFullYear(), customEnd.getMonth(), customEnd.getDate(), 23, 59, 59);
        return d >= s && d <= e;
      }
      default:
        return true;
    }
  }

  // ---------- render ----------
  function totalCard(total, label, icon, c1, c2) {
    return `
      <div class="sv-total" style="background:linear-gradient(135deg,${c1},${c2});box-shadow:0 4px 12px ${c1}55;">
        <div class="sv-total__ico"><i class="${icon}"></i></div>
        <div class="sv-total__info">
          <div class="sv-total__label">${label}</div>
          <div class="sv-total__num">${total}</div>
        </div>
      </div>`;
  }

  function statCard(label, count, icon, color, bg) {
    return `
      <div class="sv-card">
        <div class="sv-card__ico" style="background:${bg};color:${color};"><i class="${icon}"></i></div>
        <div class="sv-card__num" style="color:${color};">${count}</div>
        <div class="sv-card__label">${label.toUpperCase()}</div>
      </div>`;
  }

  function amountCard(label, amount, icon, color, bg) {
    return `
      <div class="sv-card">
        <div class="sv-card__ico" style="background:${bg};color:${color};"><i class="${icon}"></i></div>
        <div class="sv-card__num sv-card__num--sm" style="color:${color};">${fmtMoney(amount)}</div>
        <div class="sv-card__label">${label.toUpperCase()}</div>
      </div>`;
  }

  function renderRepair() {
    let total = 0, inProg = 0, waiting = 0, ready = 0, done = 0, canc = 0, rej = 0;
    for (const data of repairDocs) {
      if (!isInRange(data)) continue;
      total++;
      const s = String(data.status || '').toUpperCase();
      if (s === 'IN PROGRESS') inProg++;
      else if (s === 'WAITING PART') waiting++;
      else if (s === 'READY TO PICKUP') ready++;
      else if (s === 'COMPLETED') done++;
      else if (s === 'CANCEL' || s === 'CANCELLED') canc++;
      else if (s === 'REJECT') rej++;
    }
    body.innerHTML = `
      ${totalCard(total, t('dash.totalJobs'), 'fas fa-screwdriver-wrench', '#6366F1', '#8B5CF6')}
      <div class="sv-grid">
        ${statCard(t('dash.inProgress'),  inProg,  'fas fa-spinner',             '#4CAF50', '#E8F5E9')}
        ${statCard(t('dash.waitingPart'), waiting, 'fas fa-clock-rotate-left',   '#F59E0B', '#FFF8E1')}
        ${statCard(t('dash.readyPickup'), ready,   'fas fa-hand-holding-heart',  '#A78BFA', '#EDE9FE')}
        ${statCard(t('dash.completed'),   done,    'fas fa-circle-check',        '#4CAF50', '#E8F5E9')}
        ${statCard(t('dash.cancel'),      canc,    'fas fa-ban',                 '#FFC107', '#FFF8E1')}
        ${statCard(t('dash.reject'),      rej,     'fas fa-circle-xmark',        '#EF4444', '#FEE2E2')}
      </div>`;
  }

  function renderPhone() {
    let totalSales = 0, salesToday = 0;
    let tJual = 0, tKos = 0, jualToday = 0, kosToday = 0;
    const now = new Date();
    for (const data of phoneDocs) {
      const sid = String(data.shopID || '').toUpperCase();
      if (sid !== shopID) continue;
      if (!isInRange(data)) continue;
      totalSales++;
      const jual = Number(data.jual || 0);
      const kos = Number(data.kos || 0);
      tJual += jual; tKos += kos;
      const ts = data.timestamp;
      if (typeof ts === 'number') {
        const d = new Date(ts);
        if (d.getFullYear() === now.getFullYear() &&
            d.getMonth() === now.getMonth() &&
            d.getDate() === now.getDate()) {
          salesToday++; jualToday += jual; kosToday += kos;
        }
      }
    }
    const totalProfit = tJual - tKos;
    const profitToday = jualToday - kosToday;
    const profitColor = totalProfit >= 0 ? '#059669' : '#EF4444';
    const profitBg    = totalProfit >= 0 ? '#D1FAE5' : '#FEE2E2';

    body.innerHTML = `
      <div class="sv-hero">
        <div class="sv-hero__ico"><i class="fas fa-mobile-screen-button"></i></div>
        <div class="sv-hero__main">
          <div class="sv-hero__label">${t('dash.salesToday')}</div>
          <div class="sv-hero__num">${salesToday} ${t('dash.unit')}</div>
        </div>
        <div class="sv-hero__right">
          <div class="sv-hero__amt">${fmtMoney(jualToday)}</div>
          <div class="sv-hero__chip">${t('dash.profit')}: ${fmtMoney(profitToday)}</div>
        </div>
      </div>
      <div class="sv-grid">
        ${statCard(t('dash.totalSales'),  totalSales,   'fas fa-cart-shopping','#6366F1', '#EDE9FE')}
        ${amountCard(t('dash.totalSell'), tJual,        'fas fa-money-bill',   '#059669', '#D1FAE5')}
        ${amountCard(t('dash.totalCost'), tKos,         'fas fa-coins',        '#EA580C', '#FFF7ED')}
        ${amountCard(t('dash.totalProfit'),totalProfit, 'fas fa-chart-line',   profitColor, profitBg)}
      </div>`;
  }

  function render() {
    if (!phoneEnabled && segment === 1) segment = 0;
    if (segment === 0) renderRepair(); else renderPhone();
  }

  // ---------- events ----------
  document.querySelectorAll('#svSeg .sv-seg__btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      segment = Number(btn.dataset.seg) || 0;
      document.querySelectorAll('#svSeg .sv-seg__btn').forEach((b) =>
        b.classList.toggle('is-active', b === btn));
      render();
    });
  });

  const filterSel = $('svFilter');
  const rangePick = $('svRangePick');
  const rangePill = $('svRangePill');
  const rangeText = $('svRangeText');
  const rangeFrom = $('svRangeFrom');
  const rangeTo   = $('svRangeTo');

  filterSel.addEventListener('change', (e) => {
    filter = e.target.value;
    if (filter === 'CUSTOM') {
      rangePick.classList.remove('hidden');
    } else {
      rangePick.classList.add('hidden');
      rangePill.classList.add('hidden');
      customStart = null; customEnd = null;
      render();
    }
  });

  function applyCustom() {
    if (!rangeFrom.value || !rangeTo.value) return;
    customStart = new Date(rangeFrom.value);
    customEnd = new Date(rangeTo.value);
    rangeText.textContent = `${fmtDate(customStart)} - ${fmtDate(customEnd)}`;
    rangePill.classList.remove('hidden');
    render();
  }
  rangeFrom.addEventListener('change', applyCustom);
  rangeTo.addEventListener('change', applyCustom);

  // ---------- streams ----------
  try {
    db.collection('repairs_' + ownerID).onSnapshot(
      (snap) => {
        repairDocs = snap.docs.map((d) => d.data() || {});
        if (segment === 0) render();
      },
      (err) => console.warn('repairs_' + ownerID + ':', err)
    );
    db.collection('phone_sales_' + ownerID).onSnapshot(
      (snap) => {
        phoneDocs = snap.docs.map((d) => d.data() || {});
        if (segment === 1) render();
      },
      (err) => console.warn('phone_sales_' + ownerID + ':', err)
    );
  } catch (e) { console.warn('sv_dashboard stream fail:', e); }

  // Respect enabledModules.phone (hide phone segment if disabled)
  try {
    db.collection('shops_' + ownerID).doc(shopID).onSnapshot((snap) => {
      if (!snap.exists) return;
      const em = snap.data().enabledModules || {};
      phoneEnabled = em.phone !== false;
      $('svSegPhone').style.display = phoneEnabled ? '' : 'none';
      if (!phoneEnabled && segment === 1) {
        segment = 0;
        document.querySelectorAll('#svSeg .sv-seg__btn').forEach((b) =>
          b.classList.toggle('is-active', b.dataset.seg === '0'));
      }
      render();
    });
  } catch (e) { console.warn('sv_dashboard shop snap fail:', e); }

  render();
})();
