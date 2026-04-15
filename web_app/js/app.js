/* ===== RMS PRO WEB — UI SCAFFOLD =====
   Hanya navigasi & toggle UI. Auth/DB logic di auth.js + module-specific files.
*/
(function () {
  'use strict';

  // ---------- LOGIN PAGE (toggle owner/staff sahaja; submit dikendalikan auth.js) ----------
  const segment = document.getElementById('loginSegment');
  if (segment) {
    const ownerForm = document.getElementById('ownerForm');
    const staffForm = document.getElementById('staffForm');
    const errorBox  = document.getElementById('loginError');

    segment.addEventListener('click', (e) => {
      const btn = e.target.closest('.segment__item');
      if (!btn) return;
      segment.querySelectorAll('.segment__item').forEach(i => i.classList.remove('is-active'));
      btn.classList.add('is-active');
      const isOwner = btn.dataset.mode === 'owner';
      ownerForm.classList.toggle('hidden', !isOwner);
      staffForm.classList.toggle('hidden', isOwner);
      errorBox.classList.add('hidden');
    });

    const forgot = document.getElementById('forgotPass');
    if (forgot) forgot.addEventListener('click', (e) => { e.preventDefault(); alert('TODO: dialog reset password'); });
    const register = document.getElementById('registerBtn');
    if (register) register.addEventListener('click', (e) => { e.preventDefault(); alert('TODO: halaman daftar online'); });
  }

  // ---------- BRANCH DASHBOARD ----------
  const branchGrid = document.getElementById('branchGrid');
  if (branchGrid) {
    // Mirror lib/screens/branch_dashboard_screen.dart — semua butang seragam, satu baris
    const modules = [
      { id: 'widget',         label: 'Dashboard',   icon: 'fa-chart-line',          color: 'teal' },
      { id: 'POS',            label: 'POS',         icon: 'fa-cash-register',       color: 'red' },
      { id: 'Baikpulih',      label: 'Baikpulih',   icon: 'fa-screwdriver-wrench',  color: 'teal' },
      { id: 'JualTelefon',    label: 'Jual Fon',    icon: 'fa-mobile-screen-button',color: 'sky' },
      { id: 'Senarai_job',    label: 'Senarai',     icon: 'fa-clipboard-list',      color: 'indigo' },
      { id: 'Stock',          label: 'Inventori',   icon: 'fa-boxes-stacked',       color: 'amber' },
      { id: 'DB_Cust',        label: 'Pelanggan',   icon: 'fa-users',               color: 'violet' },
      { id: 'Booking',        label: 'Booking',     icon: 'fa-calendar-check',      color: 'cyan' },
      { id: 'Claim_warranty', label: 'Claim',       icon: 'fa-shield-halved',       color: 'pink' },
      { id: 'Collab',         label: 'Kolaborasi',  icon: 'fa-handshake',           color: 'indigo' },
      { id: 'Profesional',    label: 'Pro Mode',    icon: 'fa-user-tie',            color: 'purple', badge: 'off' },
      { id: 'Kewangan',       label: 'Kewangan',    icon: 'fa-wallet',              color: 'teal' },
      { id: 'Refund',         label: 'Refund',      icon: 'fa-money-bill-transfer', color: 'red' },
      { id: 'Lost',           label: 'Kerugian',    icon: 'fa-triangle-exclamation',color: 'redd' },
      { id: 'MaklumBalas',    label: 'Prestasi',    icon: 'fa-star',                color: 'amber' },
      { id: 'Link',           label: 'Link',        icon: 'fa-link',                color: 'sky' },
      { id: 'Fungsi_lain',    label: 'Fungsi Lain', icon: 'fa-grip',                color: 'slate' },
      { id: 'Settings',       label: 'Tetapan',     icon: 'fa-gear',                color: 'gray' },
    ];

    branchGrid.innerHTML = modules.map(m => `
      <button class="branch-tile c-${m.color}" data-module="${m.id}">
        ${m.badge ? `<span class="branch-tile__badge badge-${m.badge}">${m.badge.toUpperCase()}</span>` : ''}
        <span class="branch-tile__icon"><i class="fas ${m.icon}"></i></span>
        <span class="branch-tile__label">${m.label}</span>
      </button>
    `).join('');

    const moduleRoutes = {
      Settings: 'settings.html',
      Link: 'link.html',
      MaklumBalas: 'maklum_balas.html',
      Lost: 'kerugian.html',
      Refund: 'refund.html',
      Collab: 'kolaborasi.html',
      Claim_warranty: 'claim.html',
      POS: 'pos.html',
      Baikpulih: 'baikpulih.html',
      JualTelefon: 'jual_phone.html',
      Kewangan: 'kewangan.html',
      widget: 'widget.html',
      Booking: 'booking.html',
      Senarai_job: 'senarai_job.html',
      Stock: 'inventory.html',
      DB_Cust: 'db_cust.html',
    };
    const frame = document.getElementById('moduleFrame');
    const empty = document.getElementById('moduleEmpty');

    branchGrid.addEventListener('click', (e) => {
      const tile = e.target.closest('.branch-tile');
      if (!tile) return;

      branchGrid.querySelectorAll('.branch-tile').forEach(t => t.classList.remove('is-active'));
      tile.classList.add('is-active');

      const id = tile.dataset.module;
      const url = moduleRoutes[id];
      if (url) {
        empty.hidden = true;
        frame.hidden = false;
        if (frame.dataset.current !== url) { frame.src = url; frame.dataset.current = url; }
      } else {
        frame.hidden = true;
        empty.hidden = false;
        empty.textContent = `Modul "${id}" — TODO`;
      }
    });

    const logout = document.getElementById('btnLogout');
    if (logout) logout.addEventListener('click', () => { window.location.href = 'index.html'; });

    // Default: Dashboard aktif sebaik sahaja first login / kembali dari supervisor
    const defaultTile = branchGrid.querySelector('.branch-tile[data-module="widget"]');
    if (defaultTile) defaultTile.click();
  }

  // ---------- ADMIN DASHBOARD (kekal — untuk SaaS admin) ----------
  const adminGrid = document.getElementById('moduleGrid');
  if (adminGrid) {
    const modules = [
      { icon: 'fa-list-check',   label: 'Senarai Aktif', color: 'green' },
      { icon: 'fa-user-plus',    label: 'Daftar Dealer', color: 'blue' },
      { icon: 'fa-chart-pie',    label: 'Rekod Jualan',  color: 'orange' },
      { icon: 'fa-quote-left',   label: 'Kata-Kata',     color: 'indigo' },
      { icon: 'fa-bullhorn',     label: 'Notis Aduan',   color: 'red' },
      { icon: 'fa-gear',         label: 'Tetapan API',   color: 'cyan' },
      { icon: 'fa-trash',        label: 'Tong Sampah',   color: 'muted' },
      { icon: 'fa-store',        label: 'Marketplace',   color: 'purple' },
      { icon: 'fa-globe',        label: 'Domain',        color: 'violet' },
      { icon: 'fa-file-pdf',     label: 'Template PDF',  color: 'pink' },
      { icon: 'fa-whatsapp',     label: 'Bot WhatsApp',  color: 'whatsapp', brand: true },
      { icon: 'fa-comment-dots', label: 'Feedback',      color: 'primary' },
      { icon: 'fa-database',     label: 'Database User', color: 'sky' },
      { icon: 'fa-toggle-on',    label: 'Suis Modul',    color: 'teal' },
    ];
    adminGrid.innerHTML = modules.map((m, i) => `
      <button class="module-tile" data-index="${i}">
        <span class="module-tile__icon bg-${m.color}"><i class="${m.brand ? 'fab' : 'fas'} ${m.icon}"></i></span>
        <span class="module-tile__label">${m.label}</span>
      </button>
    `).join('');
    const adminLogout = document.getElementById('btnLogout');
    if (adminLogout) adminLogout.addEventListener('click', () => { window.location.href = 'index.html'; });
  }
})();
