/* Branch data loader — Supabase. Mirror BranchService.initialize(). */
(function () {
  'use strict';
  if (!document.getElementById('shopName')) return;

  async function loadBranch() {
    const ctx = await window.requireAuth();
    if (!ctx) return;

    const data = {};

    if (ctx.tenant_id) {
      const { data: tenant } = await window.sb
        .from('tenants')
        .select('nama_kedai, config, bot_whatsapp, domain')
        .eq('id', ctx.tenant_id)
        .maybeSingle();
      if (tenant) Object.assign(data, tenant, tenant.config || {});
    }

    if (ctx.current_branch_id) {
      const { data: branch } = await window.sb
        .from('branches')
        .select('shop_code, nama_kedai, alamat, phone, email, logo_base64, enabled_modules, extras')
        .eq('id', ctx.current_branch_id)
        .maybeSingle();
      if (branch) {
        Object.assign(data, branch, branch.enabled_modules || {}, branch.extras || {});
        document.getElementById('shopBranch').textContent = String(branch.shop_code || '').toUpperCase();
      }
    }

    apply(data);
  }

  function apply(d) {
    const shopName = d.nama_kedai || d.shopName || 'RMS PRO';
    const addr = d.alamat || d.address || '';
    document.getElementById('shopName').textContent = String(shopName).toUpperCase();
    document.getElementById('shopAddr').textContent = addr;

    if (d.logo_base64 || d.logoBase64) {
      const av = document.querySelector('.branch-header__avatar');
      const raw = d.logo_base64 || d.logoBase64;
      const src = raw.includes(',') ? raw : 'data:image/png;base64,' + raw;
      if (av) av.innerHTML = `<img src="${src}" alt="logo">`;
    }

    if (d.themeColor) {
      const hex = String(d.themeColor).replace('#', '');
      const main = '#' + hex;
      document.documentElement.style.setProperty('--branch-theme', main);
      document.documentElement.style.setProperty('--branch-theme-dark', shade(main, -35));
      const meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute('content', main);
    }

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

  setTimeout(loadBranch, 50);

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
