/* sv_settings.js — Supervisor Settings tab. Mirror sv_settings_tab.dart.
   Language picker (MS/EN). Delegates to window.svI18n for persistence + live swap. */
(function () {
  'use strict';
  const sel = document.getElementById('svLangSelect');
  if (!sel || !window.svI18n) return;

  sel.value = window.svI18n.getLang();
  sel.addEventListener('change', () => {
    window.svI18n.setLang(sel.value);
    const msg = sel.value === 'en' ? 'Language saved' : 'Bahasa disimpan';
    const t = document.createElement('div');
    t.className = 'admin-toast';
    t.innerHTML = `<i class="fas fa-circle-check"></i> ${msg}`;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2200);
  });
  window.addEventListener('sv:lang:changed', (e) => { sel.value = e.detail.lang; });
})();
