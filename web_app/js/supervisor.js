/* Supervisor dashboard — skeleton shell.
   Ports SupervisorDashboardScreen (Flutter) header + bottom-nav + tab swap.
   Individual tab modules are placeholders; wire logic in future iterations. */
(function () {
  'use strict';
  if (!document.body.classList.contains('supervisor-page')) return;

  // ---------- BRANCH GUARD ----------
  const url = new URL(window.location.href);
  const fromUrl = url.searchParams.get('branch');
  if (fromUrl) localStorage.setItem('rms_current_branch', fromUrl);

  const current = localStorage.getItem('rms_current_branch') || '';
  if (!current.includes('@')) {
    window.location.replace('index.html');
    return;
  }
  const [ownerID, shopID] = current.split('@');
  const shopIDUpper = (shopID || '').toUpperCase();

  // ---------- i18n (tab labels) ----------
  const TAB_DICT = {
    ms: { 'tab.dashboard':'Dashboard','tab.inventory':'Inventori','tab.kewangan':'Kewangan','tab.refund':'Refund','tab.staff':'Staf','tab.marketing':'Marketing','tab.expense':'Perbelanjaan','tab.untungrugi':'Untung Rugi','tab.marketplace':'Marketplace','tab.settings':'Tetapan' },
    en: { 'tab.dashboard':'Dashboard','tab.inventory':'Inventory','tab.kewangan':'Finance','tab.refund':'Refund','tab.staff':'Staff','tab.marketing':'Marketing','tab.expense':'Expenses','tab.untungrugi':'Profit/Loss','tab.marketplace':'Marketplace','tab.settings':'Settings' },
  };
  const __lang = (localStorage.getItem('rms_lang') || 'ms') === 'en' ? 'en' : 'ms';
  document.querySelectorAll('.sup-tile [data-i18n]').forEach((el) => {
    const k = el.dataset.i18n;
    const v = (TAB_DICT[__lang] && TAB_DICT[__lang][k]) || TAB_DICT.ms[k];
    if (v) el.textContent = v;
  });

  // ---------- HEADER / STAFF PILL ----------
  const $ = (id) => document.getElementById(id);
  $('shopBranchText').textContent = shopIDUpper;
  $('staffName').textContent = (localStorage.getItem('rms_staff_name') || 'SUPERVISOR').toUpperCase();

  // ---------- FIRESTORE: shop doc (themeColor, logoBase64, shopName, enabledModules) ----------
  const db = window.db;
  let enabledModules = {};

  function applyShop(d) {
    const shopName = d.shopName || d.namaKedai || 'RMS PRO';
    $('shopName').textContent = String(shopName).toUpperCase();

    if (d.logoBase64) {
      const av = $('supAvatar');
      const src = String(d.logoBase64).includes(',') ? d.logoBase64 : 'data:image/png;base64,' + d.logoBase64;
      av.innerHTML = `<img src="${src}" alt="logo">`;
    }

    // Theme override (supervisor brand stays indigo by default; shop can override)
    if (d.themeColor) {
      const hex = String(d.themeColor).replace('#', '');
      const main = '#' + hex;
      document.documentElement.style.setProperty('--sup-theme', main);
      document.documentElement.style.setProperty('--sup-theme-dark', shade(main, -20));
      const meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute('content', main);
    }

    enabledModules = (d.enabledModules && typeof d.enabledModules === 'object') ? d.enabledModules : {};
    // Hook for future: toggle tabs/cards based on enabledModules
  }

  function shade(hex, percent) {
    const num = parseInt(hex.slice(1), 16);
    const amt = Math.round(2.55 * percent);
    let r = (num >> 16) + amt, g = ((num >> 8) & 0xff) + amt, b = (num & 0xff) + amt;
    r = Math.max(0, Math.min(255, r));
    g = Math.max(0, Math.min(255, g));
    b = Math.max(0, Math.min(255, b));
    return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');
  }

  try {
    db.collection('shops_' + ownerID).doc(shopIDUpper).onSnapshot(
      (snap) => { if (snap.exists) applyShop(snap.data() || {}); },
      (err) => console.warn('shops_' + ownerID + ':', err)
    );
  } catch (e) { console.warn('shop snapshot failed:', e); }

  // ---------- NOTIFICATIONS (unread count badge) ----------
  const notifBadge = $('notifBadge');
  try {
    db.collection('marketplace_notifications')
      .where('targetOwnerID', '==', ownerID)
      .where('read', '==', false)
      .onSnapshot(
        (snap) => {
          const n = snap.size || 0;
          if (n > 0) {
            notifBadge.textContent = n > 99 ? '99+' : String(n);
            notifBadge.classList.remove('hidden');
          } else {
            notifBadge.classList.add('hidden');
          }
        },
        (err) => console.warn('marketplace_notifications:', err)
      );
  } catch (e) { console.warn('notif listener failed:', e); }

  // Bell click — placeholder; future: open notifications sheet
  $('btnBell').addEventListener('click', () => {
    // TODO: bottom-sheet listing marketplace_notifications
    alert('TODO: Senarai notifikasi (akan dilaksanakan kemudian).');
  });

  // ---------- LOGOUT — balik ke mod cawangan asal ----------
  $('btnLogout').addEventListener('click', () => {
    window.location.replace('branch.html');
  });

  // ---------- TAB SWITCHING (bottom nav) ----------
  const navItems = document.querySelectorAll('.sup-tile');
  const panes = document.querySelectorAll('.sup-tab-pane');

  function setTab(tabKey) {
    navItems.forEach((b) => b.classList.toggle('is-active', b.dataset.tab === tabKey));
    panes.forEach((p) => p.classList.toggle('is-active', p.dataset.tab === tabKey));
    window.scrollTo({ top: 0, behavior: 'instant' });
  }

  navItems.forEach((btn) => {
    btn.addEventListener('click', () => setTab(btn.dataset.tab));
  });

  // ---------- EXPORTS for future tab modules ----------
  window.SupervisorShell = {
    ownerID,
    shopID: shopIDUpper,
    getEnabledModules: () => enabledModules,
    setTab
  };
})();
