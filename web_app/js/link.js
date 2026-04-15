/* link.js — Public links + module toggles. Mirror link_screen.dart.
   Tenant domain display + module enable/disable → branches.enabled_modules jsonb. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);

  function toast(msg, err) {
    const el = document.createElement('div');
    el.style.cssText = 'position:fixed;left:50%;bottom:20px;transform:translateX(-50%);background:' +
      (err ? '#dc2626' : '#0f172a') + ';color:#fff;padding:10px 18px;border-radius:10px;z-index:9999;font-weight:700;';
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  const LINKS = [
    { key: 'booking',  icon: 'fa-calendar-check', color: '#2563eb', label: 'Booking Online',   sub: 'Form booking customer' },
    { key: 'borang',   icon: 'fa-file-lines',     color: '#10b981', label: 'Borang Kerosakan', sub: 'Customer isi sendiri' },
    { key: 'katalog',  icon: 'fa-store',          color: '#f59e0b', label: 'Katalog Produk',   sub: 'Senarai phone & harga' },
    { key: 'bio',      icon: 'fa-id-card',        color: '#8b5cf6', label: 'Kad Bio Kedai',    sub: 'Profile kedai' },
    { key: 'tracking', icon: 'fa-truck-fast',     color: '#ec4899', label: 'Tracking Job',     sub: 'Customer semak status' },
  ];

  let branch = null, tenant = null;
  let enabled = {};

  async function loadAll() {
    const [{ data: b }, { data: t }] = await Promise.all([
      window.sb.from('branches').select('*').eq('id', branchId).single(),
      window.sb.from('tenants').select('*').eq('id', tenantId).single(),
    ]);
    branch = b || {};
    tenant = t || {};
    const em = (branch.enabled_modules && typeof branch.enabled_modules === 'object') ? branch.enabled_modules : {};
    enabled = {};
    LINKS.forEach((L) => { enabled[L.key] = em[L.key] !== false; });

    const domain = tenant.domain || null;
    if (domain && $('domainCard')) {
      const url = domain.startsWith('http') ? domain : `https://${domain}`;
      $('domainUrl').textContent = url;
      $('domainStatus').textContent = (tenant.status || 'active').toUpperCase();
      $('domainCard').hidden = false;
    } else if ($('domainCard')) {
      $('domainCard').hidden = true;
    }

    render();
  }

  function render() {
    const domain = tenant.domain || null;
    const base = domain ? (domain.startsWith('http') ? domain : `https://${domain}`) : '';
    $('linkList').innerHTML = LINKS.map((L) => {
      const on = enabled[L.key];
      const url = base ? `${base}/${L.key}` : '(domain belum set)';
      return `<div class="link-card" style="background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:14px;margin-bottom:10px;display:flex;gap:12px;align-items:center;">
        <div style="width:42px;height:42px;border-radius:10px;background:${L.color}15;color:${L.color};display:flex;align-items:center;justify-content:center;font-size:18px;flex-shrink:0;">
          <i class="fas ${L.icon}"></i>
        </div>
        <div style="flex:1;min-width:0;">
          <div style="font-weight:900;font-size:13px;">${L.label}</div>
          <div style="font-size:10px;color:#64748b;">${L.sub}</div>
          <div style="font-size:10px;color:#94a3b8;margin-top:4px;word-break:break-all;">${url}</div>
        </div>
        <div style="display:flex;gap:6px;align-items:center;flex-shrink:0;">
          ${base ? `<button type="button" class="lnk-copy" data-url="${url}" style="padding:6px 10px;background:#e2e8f0;border:none;border-radius:8px;cursor:pointer;" title="Salin"><i class="fas fa-copy"></i></button>` : ''}
          <label style="position:relative;display:inline-block;width:44px;height:24px;cursor:pointer;">
            <input type="checkbox" data-k="${L.key}" ${on ? 'checked' : ''} style="opacity:0;width:0;height:0;">
            <span style="position:absolute;inset:0;background:${on ? '#10b981' : '#cbd5e1'};border-radius:24px;transition:.2s;"></span>
            <span style="position:absolute;top:2px;left:${on ? '22px' : '2px'};width:20px;height:20px;background:#fff;border-radius:50%;transition:.2s;"></span>
          </label>
        </div>
      </div>`;
    }).join('');

    $('linkList').querySelectorAll('input[data-k]').forEach((cb) => {
      cb.addEventListener('change', async () => {
        const k = cb.dataset.k;
        enabled[k] = cb.checked;
        const { error } = await window.sb.from('branches').update({ enabled_modules: enabled }).eq('id', branchId);
        if (error) { toast('Gagal: ' + error.message, true); cb.checked = !cb.checked; enabled[k] = cb.checked; return; }
        toast('Tetapan dikemaskini');
        render();
      });
    });
    $('linkList').querySelectorAll('.lnk-copy').forEach((b) => {
      b.addEventListener('click', async (e) => {
        e.stopPropagation();
        try { await navigator.clipboard.writeText(b.dataset.url); toast('Dicopy'); }
        catch (_) { toast('Gagal copy', true); }
      });
    });
  }

  // ─── THEME MODAL (mirror link_screen.dart presetColors + tenants.config.pageThemes) ───
  const PRESET_COLORS = [
    '#020617', '#0f172a', '#1e293b', '#111827', '#18181b',
    '#ffffff', '#f8fafc', '#f1f5f9', '#fef2f2', '#fdf4ff',
    '#00ffa3', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899',
    '#ef4444', '#f59e0b', '#06b6d4', '#6366f1', '#14b8a6',
  ];
  const isDark = (hex) => {
    const h = hex.replace('#', '');
    const r = parseInt(h.substr(0, 2), 16), g = parseInt(h.substr(2, 2), 16), b = parseInt(h.substr(4, 2), 16);
    return (r * 299 + g * 587 + b * 114) / 1000 < 140;
  };
  let currentTheme = { bgColor: '#020617', textColor: '#ffffff', accentColor: '#00ffa3', fontSize: 14 };
  let currentPageKey = 'global';

  function renderSwatches(gridId, field) {
    const grid = $(gridId);
    if (!grid) return;
    grid.innerHTML = PRESET_COLORS.map((c) => {
      const sel = currentTheme[field] === c;
      return `<button type="button" data-c="${c}" class="theme-sw${sel ? ' is-sel' : ''}" style="width:32px;height:32px;border-radius:8px;background:${c};border:${sel ? '2.5px solid #3B82F6' : '1px solid #e2e8f0'};cursor:pointer;display:inline-flex;align-items:center;justify-content:center;color:${isDark(c) ? '#fff' : '#000'};font-size:12px;">${sel ? '<i class="fas fa-check"></i>' : ''}</button>`;
    }).join('');
    grid.querySelectorAll('[data-c]').forEach((b) => b.addEventListener('click', () => {
      currentTheme[field] = b.dataset.c;
      renderSwatches(gridId, field);
      updatePreview();
    }));
  }

  function updatePreview() {
    const pv = $('themePreview');
    if (pv) {
      pv.style.background = currentTheme.bgColor;
      pv.style.color = currentTheme.textColor;
      pv.style.fontSize = currentTheme.fontSize + 'px';
      pv.style.borderColor = currentTheme.accentColor;
      pv.style.padding = '16px';
      pv.style.borderRadius = '12px';
      pv.style.border = '2px solid ' + currentTheme.accentColor;
    }
  }

  async function openThemeModal(pageKey) {
    currentPageKey = pageKey || 'global';
    // Load existing theme from tenants.config.pageThemes[pageKey]
    currentTheme = { bgColor: '#020617', textColor: '#ffffff', accentColor: '#00ffa3', fontSize: 14 };
    try {
      const cfg = (tenant && typeof tenant.config === 'object' && tenant.config) || {};
      const themes = (cfg.pageThemes && typeof cfg.pageThemes === 'object') ? cfg.pageThemes : {};
      if (themes[currentPageKey] && typeof themes[currentPageKey] === 'object') {
        Object.assign(currentTheme, themes[currentPageKey]);
      }
    } catch (_) {}
    // Fallback to localStorage if never saved
    try {
      const ls = localStorage.getItem(`link_theme_${tenantId}_${currentPageKey}`);
      if (ls) Object.assign(currentTheme, JSON.parse(ls));
    } catch (_) {}

    renderSwatches('bgSwatches', 'bgColor');
    renderSwatches('textSwatches', 'textColor');
    renderSwatches('accentSwatches', 'accentColor');
    const fs = $('fsSlider'); if (fs) fs.value = currentTheme.fontSize;
    const fsL = $('fsLabel'); if (fsL) fsL.textContent = currentTheme.fontSize;
    updatePreview();
    const bg2 = $('themeModal'); if (bg2) bg2.classList.add('is-open');
  }
  window.openThemeModal = openThemeModal;

  const fsSlider = $('fsSlider');
  if (fsSlider) fsSlider.addEventListener('input', (e) => {
    currentTheme.fontSize = Number(e.target.value) || 14;
    const fsL = $('fsLabel'); if (fsL) fsL.textContent = currentTheme.fontSize;
    updatePreview();
  });

  const bg = $('themeModal');
  if (bg) {
    bg.addEventListener('click', (e) => { if (e.target === bg) bg.classList.remove('is-open'); });
    const tCancel = $('themeCancel'); if (tCancel) tCancel.addEventListener('click', () => bg.classList.remove('is-open'));
    const tSave = $('themeSave'); if (tSave) tSave.addEventListener('click', async () => {
      // Persist to tenants.config.pageThemes (mirror Flutter)
      try {
        const { data: row } = await window.sb.from('tenants').select('config').eq('id', tenantId).maybeSingle();
        const config = (row && row.config && typeof row.config === 'object') ? row.config : {};
        const themes = (config.pageThemes && typeof config.pageThemes === 'object') ? config.pageThemes : {};
        themes[currentPageKey] = {
          bgColor: currentTheme.bgColor,
          textColor: currentTheme.textColor,
          accentColor: currentTheme.accentColor,
          fontSize: Number(currentTheme.fontSize) || 14,
        };
        config.pageThemes = themes;
        const { error } = await window.sb.from('tenants').update({ config }).eq('id', tenantId);
        if (error) throw error;
        tenant.config = config;
        toast('Theme disimpan!');
      } catch (e) {
        // Fallback localStorage
        try {
          localStorage.setItem(`link_theme_${tenantId}_${currentPageKey}`, JSON.stringify(currentTheme));
          toast('Theme disimpan (lokal)');
        } catch (_) {
          toast('Gagal simpan theme', true);
        }
      }
      bg.classList.remove('is-open');
    });
  }

  await loadAll();

  window.sb.channel('link-branches-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'branches', filter: `id=eq.${branchId}` }, loadAll)
    .subscribe();
})();
