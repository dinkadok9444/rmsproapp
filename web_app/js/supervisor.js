/* supervisor.js — Supervisor shell. Mirror supervisor_dashboard_screen.dart.
   Handle: header info, tab switching, logout, branch switch, notification badge. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);

  // ── Header info ────────────────────────────────────────────
  async function loadHeader() {
    if (ctx.nama) { const s = $('staffName'); if (s) s.textContent = ctx.nama.toUpperCase(); }
    if (!branchId) return;
    const { data: br } = await window.sb
      .from('branches')
      .select('nama_kedai, shop_code, logo_base64')
      .eq('id', branchId)
      .single();
    if (br) {
      const nm = $('shopName'); if (nm && br.nama_kedai) nm.textContent = br.nama_kedai;
      const bt = $('shopBranchText'); if (bt) bt.textContent = br.shop_code || '—';
      if (br.logo_base64) {
        const av = $('supAvatar');
        if (av) av.innerHTML = `<img src="${br.logo_base64}" alt="logo" style="width:100%;height:100%;border-radius:inherit;object-fit:cover">`;
      }
    }
  }

  // ── Tab switching ──────────────────────────────────────────
  const tabs = document.querySelectorAll('#supTabs .sup-tile');
  const panes = document.querySelectorAll('.sup-tab-pane');
  tabs.forEach((t) => {
    t.addEventListener('click', () => {
      const key = t.dataset.tab;
      tabs.forEach((x) => x.classList.remove('is-active'));
      t.classList.add('is-active');
      panes.forEach((p) => p.classList.toggle('is-active', p.dataset.tab === key));
      // Notify sv_dashboard to reload if DASHBOARD re-activated
      if (key === 'DASHBOARD') window.dispatchEvent(new CustomEvent('sv:dashboard:refresh'));
    });
  });

  // ── Notification badge (pending feedback + pending refund) ─
  async function loadNotifCount() {
    let total = 0;
    try {
      const { count: fbCount } = await window.sb
        .from('feedback').select('id', { count: 'exact', head: true })
        .eq('branch_id', branchId).eq('resolved', false);
      total += fbCount || 0;
    } catch (_) {}
    try {
      const { count: rfCount } = await window.sb
        .from('refunds').select('id', { count: 'exact', head: true })
        .eq('branch_id', branchId).eq('status', 'PENDING');
      total += rfCount || 0;
    } catch (_) {}
    const badge = $('notifBadge');
    if (!badge) return;
    if (total > 0) { badge.textContent = String(total); badge.classList.remove('hidden'); }
    else badge.classList.add('hidden');
  }

  // ── Logout / branch switch ─────────────────────────────────
  const btnLogout = $('btnLogout');
  if (btnLogout) btnLogout.addEventListener('click', () => window.doLogout && window.doLogout());
  const btnBell = $('btnBell');
  if (btnBell) btnBell.addEventListener('click', () => { alert('Notifikasi: ' + ($('notifBadge').textContent || '0') + ' baru.'); });

  await loadHeader();
  await loadNotifCount();
  setInterval(loadNotifCount, 60000);
})();
