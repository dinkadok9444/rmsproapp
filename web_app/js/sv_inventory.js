/* sv_inventory.js — Supervisor Inventory tab. Mirror sv_inventory_tab.dart.
   3-segment router (SPAREPART/ACCESSORIES/TELEFON) → iframe to existing branch pages. */
(function () {
  'use strict';
  const URLS = { STOCK: 'stock.html', ACC: 'accessories.html', PHONE: 'phone_stock.html' };
  const seg = document.getElementById('svInvSeg');
  const frame = document.getElementById('svInvFrame');
  if (!seg || !frame) return;

  let current = null;
  function activate(key) {
    if (key === current) return;
    current = key;
    seg.querySelectorAll('.sv-inv__btn').forEach((b) => b.classList.toggle('is-active', b.dataset.seg === key));
    frame.src = URLS[key] || URLS.STOCK;
  }

  seg.addEventListener('click', (e) => {
    const btn = e.target.closest('.sv-inv__btn');
    if (btn) activate(btn.dataset.seg);
  });

  // Lazy-load: only load first iframe when INVENTORY tab first activated
  const pane = document.querySelector('.sup-tab-pane[data-tab="INVENTORY"]');
  const tileBtn = document.querySelector('#supTabs .sup-tile[data-tab="INVENTORY"]');
  function ensureLoaded() { if (!current) activate('STOCK'); }
  if (pane && pane.classList.contains('is-active')) ensureLoaded();
  if (tileBtn) tileBtn.addEventListener('click', ensureLoaded);
})();
