/* Branch data loader — mirror BranchService.initialize() */
(function () {
  'use strict';
  if (!document.getElementById('shopName')) return; // hanya pada branch.html

  // Tentukan branch: URL ?branch=ownerID@SHOPID  >  localStorage  >  fallback
  const url = new URL(window.location.href);
  const fromUrl = url.searchParams.get('branch');
  if (fromUrl) localStorage.setItem('rms_current_branch', fromUrl);

  const current = localStorage.getItem('rms_current_branch');
  if (!current || !current.includes('@')) {
    // Belum login — balik ke login page
    window.location.replace('index.html');
    return;
  }

  const [ownerID, shopID] = current.split('@');
  document.getElementById('shopBranch').textContent = (shopID || '').toUpperCase();

  async function loadBranch() {
    const data = {};
    try {
      const dealer = await db.collection('saas_dealers').doc(ownerID).get();
      if (dealer.exists) Object.assign(data, dealer.data());
    } catch (e) { console.warn('saas_dealers:', e); }

    try {
      const shop = await db.collection('shops_' + ownerID).doc(shopID).get();
      if (shop.exists) Object.assign(data, shop.data());
    } catch (e) { console.warn('shops_' + ownerID + ':', e); }

    try {
      const gb = await db.collection('global_branches').doc(current).get();
      if (gb.exists) Object.assign(data, gb.data());
    } catch (e) { console.warn('global_branches:', e); }

    apply(data);
  }

  function apply(d) {
    const shopName = d.shopName || d.namaKedai || 'RMS PRO';
    const addr = d.address || d.alamat || '';
    document.getElementById('shopName').textContent = shopName.toUpperCase();
    document.getElementById('shopAddr').textContent = addr || '';

    // Logo (base64)
    if (d.logoBase64) {
      const av = document.querySelector('.branch-header__avatar');
      const src = d.logoBase64.includes(',') ? d.logoBase64 : 'data:image/png;base64,' + d.logoBase64;
      av.innerHTML = `<img src="${src}" alt="logo">`;
    }

    // Theme color
    if (d.themeColor) {
      const hex = String(d.themeColor).replace('#', '');
      const main = '#' + hex;
      document.documentElement.style.setProperty('--branch-theme', main);
      document.documentElement.style.setProperty('--branch-theme-dark', shade(main, -35));
      const meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute('content', main);
    }

    // Pro Mode badge update
    if (d.proMode === true) {
      const tile = document.querySelector('.branch-tile[data-module="Profesional"] .branch-tile__badge');
      if (tile) { tile.textContent = 'AKTIF'; tile.className = 'branch-tile__badge badge-on'; }
    }
  }

  function shade(hex, percent) {
    const num = parseInt(hex.slice(1), 16);
    const amt = Math.round(2.55 * percent);
    let r = (num >> 16) + amt, g = ((num >> 8) & 0xff) + amt, b = (num & 0xff) + amt;
    r = Math.max(0, Math.min(255, r)); g = Math.max(0, Math.min(255, g)); b = Math.max(0, Math.min(255, b));
    return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');
  }

  // Tunggu grid render dulu (app.js) baru load
  setTimeout(loadBranch, 50);

  // Jam & tarikh hidup
  const HARI = ['Ahad','Isnin','Selasa','Rabu','Khamis','Jumaat','Sabtu'];
  const BULAN = ['Jan','Feb','Mac','Apr','Mei','Jun','Jul','Ogo','Sep','Okt','Nov','Dis'];
  function tickClock() {
    const t = document.getElementById('hdrTime');
    const d = document.getElementById('hdrDate');
    if (!t || !d) return;
    const n = new Date();
    const hh = String(n.getHours()).padStart(2, '0');
    const mm = String(n.getMinutes()).padStart(2, '0');
    const ss = String(n.getSeconds()).padStart(2, '0');
    t.textContent = `${hh}:${mm}:${ss}`;
    d.textContent = `${HARI[n.getDay()]}, ${n.getDate()} ${BULAN[n.getMonth()]} ${n.getFullYear()}`;
  }
  tickClock();
  setInterval(tickClock, 1000);

  // Listen mesej dari iframe (settings, dll.) — update header live
  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.type === 'theme' && m.color) {
      const main = m.color.startsWith('#') ? m.color : '#' + m.color;
      document.documentElement.style.setProperty('--branch-theme', main);
      document.documentElement.style.setProperty('--branch-theme-dark', shade(main, -35));
      const meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute('content', main);
    } else if (m.type === 'logo') {
      const av = document.querySelector('.branch-header__avatar');
      if (!av) return;
      av.innerHTML = m.src ? `<img src="${m.src}" alt="logo">` : '<i class="fas fa-store"></i>';
    } else if (m.type === 'shop' && m.name) {
      document.getElementById('shopName').textContent = String(m.name).toUpperCase();
    } else if (m.type === 'addr') {
      document.getElementById('shopAddr').textContent = m.value || '';
    }
  });
})();
