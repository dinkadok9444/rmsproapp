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
      { id: 'Senarai_job',    label: 'Baikpulih',   icon: 'fa-screwdriver-wrench',  color: 'teal' },
      { id: 'JualTelefon',    label: 'Jual Fon',    icon: 'fa-mobile-screen-button',color: 'sky' },
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

  // ---------- ADMIN DASHBOARD (SaaS admin) ----------
  const adminGrid = document.getElementById('moduleGrid');
  if (adminGrid) {
    // Auth guard: admin only
    (async () => {
      if (typeof window.requireAuth !== 'function') return;
      const ctx = await window.requireAuth();
      if (!ctx) return;
      if (ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    })();

    const modules = [
      { icon: 'fa-list-check',   label: 'Senarai Aktif', color: 'green',    url: 'admin_senarai_aktif.html' },
      { icon: 'fa-user-plus',    label: 'Daftar Dealer', color: 'blue',     url: 'admin_daftar_manual.html' },
      { icon: 'fa-chart-pie',    label: 'Rekod Jualan',  color: 'orange',   url: 'admin_rekod_jualan.html' },
      { icon: 'fa-quote-left',   label: 'Kata-Kata',     color: 'indigo',   url: 'admin_katakata.html' },
      { icon: 'fa-bullhorn',     label: 'Notis Aduan',   color: 'red',      url: 'admin_notis_aduan.html' },
      { icon: 'fa-gear',         label: 'Tetapan API',   color: 'cyan',     url: 'admin_tetapan_sistem.html' },
      { icon: 'fa-trash',        label: 'Tong Sampah',   color: 'muted',    url: 'admin_tong_sampah.html' },
      { icon: 'fa-store',        label: 'Marketplace',   color: 'purple',   url: 'admin_marketplace.html' },
      { icon: 'fa-globe',        label: 'Domain',        color: 'violet',   url: 'admin_domain.html' },
      { icon: 'fa-file-pdf',     label: 'Template PDF',  color: 'pink',     url: 'admin_template_pdf.html' },
      { icon: 'fa-whatsapp',     label: 'Bot WhatsApp',  color: 'whatsapp', url: 'admin_whatsapp_bot.html', brand: true },
      { icon: 'fa-comment-dots', label: 'Feedback',      color: 'primary',  url: 'admin_saas_feedback.html' },
      { icon: 'fa-database',     label: 'Database User', color: 'sky',      url: 'admin_database_user.html' },
      { icon: 'fa-microchip',    label: 'Database Komponen', color: 'cyan', url: 'admin_database_komponen.html' },
      { icon: 'fa-toggle-on',    label: 'Suis Modul',    color: 'teal',     url: 'admin_suis_modul.html' },
      { icon: 'fa-comments',     label: 'Dealer Support', color: 'green',   url: 'admin_chat.html' },
    ];
    adminGrid.innerHTML = modules.map((m, i) => `
      <button class="module-tile" data-index="${i}" data-url="${m.url}">
        <span class="module-tile__icon bg-${m.color}"><i class="${m.brand ? 'fab' : 'fas'} ${m.icon}"></i></span>
        <span class="module-tile__label">${m.label}</span>
      </button>
    `).join('');

    adminGrid.addEventListener('click', (e) => {
      const tile = e.target.closest('.module-tile');
      if (!tile) return;
      const url = tile.dataset.url;
      if (url) window.location.href = url;
    });

    // Red badge on Dealer Support tile (count unread = last_from='user')
    (async function () {
      const supportTile = adminGrid.querySelector('.module-tile[data-url="admin_chat.html"]');
      if (!supportTile) return;
      function setBadge(n) {
        let b = supportTile.querySelector('.module-tile__badge');
        if (n > 0) {
          if (!b) { b = document.createElement('span'); b.className = 'module-tile__badge'; supportTile.appendChild(b); }
          b.textContent = n > 99 ? '99+' : String(n);
        } else if (b) b.remove();
      }
      async function refresh() {
        const { count } = await window.sb.from('sv_ticket_meta')
          .select('branch_id', { count: 'exact', head: true })
          .eq('last_from', 'user');
        setBadge(count || 0);
      }
      window.sb.channel('admin-grid-meta')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'sv_ticket_meta' }, refresh)
        .subscribe();
      refresh();
    })();

    const adminLogout = document.getElementById('btnLogout');
    if (adminLogout) adminLogout.addEventListener('click', () => {
      if (typeof window.doLogout === 'function') window.doLogout();
      else window.location.href = 'index.html';
    });
  }
})();
