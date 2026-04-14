/* Ringkasan Jualan — dashboard. Semua bil aktif (CUSTOMER + DEALER), semua masa. */
(function () {
  'use strict';
  if (!document.getElementById('stCount')) return;
  if (typeof firebase === 'undefined' || !firebase.firestore) return;

  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) return;
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();

  const $ = id => document.getElementById(id);
  const num = v => Number(v) || 0;
  const fmtMoney = n => 'RM ' + (Number(n) || 0).toFixed(2);

  firebase.firestore().collection('phone_receipts_' + ownerID)
    .onSnapshot(snap => {
      let count = 0, totalSales = 0, totalBuy = 0, unitCount = 0;
      snap.forEach(doc => {
        const d = doc.data() || {};
        if (String(d.shopID || '').toUpperCase() !== shopID) return;
        if (String(d.billStatus || 'ACTIVE').toUpperCase() !== 'ACTIVE') return;
        count += 1;
        totalSales += num(d.sellPrice);
        totalBuy += num(d.buyPrice);
        unitCount += Array.isArray(d.items) ? d.items.length : 1;
      });
      $('stCount').textContent = count;
      $('stSales').textContent = fmtMoney(totalSales);
      $('stProfit').textContent = fmtMoney(totalSales - totalBuy);
      $('stUnit').textContent = unitCount;
    }, err => console.warn('dashboard_summary:', err));
})();
