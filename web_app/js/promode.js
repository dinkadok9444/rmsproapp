/* Pro Mode — port lib/screens/modules/profesional_screen.dart (read-only subset) */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerRaw, shopRaw] = branch.split('@');
  const ownerID = (ownerRaw || '').toLowerCase();
  const shopID = (shopRaw || '').toUpperCase();

  const $ = id => document.getElementById(id);
  const state = {
    tab: 'online',
    search: '',
    showArchived: false,
    online: [],
    offline: [],
    dealers: [],
    proMode: false,
    proExpire: 0,
  };

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }
  function num(v) { return Number(v) || 0; }
  function fmtMoney(n) { return 'RM ' + num(n).toFixed(2); }
  function tsMs(v) {
    if (v == null) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') { const n = Number(v); return Number.isNaN(n) ? (Date.parse(v) || 0) : n; }
    if (v && typeof v.toMillis === 'function') return v.toMillis();
    if (v && v.seconds != null) return v.seconds * 1000;
    return 0;
  }
  function fmtDate(ms) {
    if (!ms) return '-';
    const d = new Date(ms);
    const p = n => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth()+1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  // Pro mode watcher
  db.collection('shops_' + ownerID).doc(shopID).onSnapshot(snap => {
    if (!snap.exists) return;
    const d = snap.data() || {};
    state.proMode = d.proMode === true;
    state.proExpire = typeof d.proModeExpire === 'number' ? d.proModeExpire : 0;
    renderStatus();
  }, err => console.warn('shop:', err));

  // Online tasks
  db.collection('collab_global_network').onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      d.id = doc.id;
      if (String(d.receiver || '').toUpperCase() === shopID ||
          String(d.receiver || '').toLowerCase() === `${ownerID}@${shopID}`.toLowerCase()) {
        out.push(d);
      }
    });
    out.sort((a,b) => tsMs(b.timestamp) - tsMs(a.timestamp));
    state.online = out;
    renderList();
  }, err => console.warn('collab:', err));

  // Offline tasks
  db.collection('pro_walkin_' + ownerID).onSnapshot(snap => {
    const out = [];
    snap.forEach(doc => {
      const d = doc.data() || {};
      d.id = doc.id;
      if (String(d.shopID || '').toUpperCase() === shopID) out.push(d);
    });
    out.sort((a,b) => tsMs(b.timestamp) - tsMs(a.timestamp));
    state.offline = out;
    renderList();
  }, err => console.warn('pro_walkin:', err));

  // Dealer book
  db.collection('pro_dealers_' + ownerID)
    .where('shopID', '==', shopID)
    .onSnapshot(snap => {
      const out = [];
      snap.forEach(doc => { const d = doc.data() || {}; d._id = doc.id; out.push(d); });
      out.sort((a,b) => String(a.nama || '').localeCompare(String(b.nama || '')));
      state.dealers = out;
      renderDealers();
    }, err => console.warn('dealers:', err));

  // ---- render ----
  function renderStatus() {
    const active = state.proMode && (state.proExpire <= 0 || Date.now() < state.proExpire);
    const box = $('pmStatus');
    const badge = $('pmBadge');
    const title = $('pmTitle');
    const sub = $('pmSub');
    if (active) {
      box.classList.remove('is-inactive');
      badge.innerHTML = '<i class="fas fa-crown"></i>';
      title.textContent = 'Pro Mode AKTIF';
      sub.textContent = state.proExpire > 0
        ? 'Tamat: ' + fmtDate(state.proExpire)
        : 'Tiada had tempoh';
    } else {
      box.classList.add('is-inactive');
      badge.innerHTML = '<i class="fas fa-lock"></i>';
      title.textContent = 'Pro Mode TIDAK AKTIF';
      sub.textContent = 'Aktifkan Pro Mode dalam aplikasi Flutter.';
    }
  }

  function filterBySearch(arr, keys) {
    const q = state.search.toLowerCase().trim();
    if (!q) return arr;
    return arr.filter(d => keys.some(k => String(d[k] || '').toLowerCase().includes(q)));
  }
  function filterArchive(arr) {
    return state.showArchived ? arr : arr.filter(d => d.archived !== true);
  }

  function renderList() {
    const isOnline = state.tab === 'online';
    const src = isOnline ? state.online : state.offline;
    const keys = isOnline
      ? ['siri', 'namaCust', 'model', 'sender']
      : ['namaKedai', 'model', 'namaCust', 'siri'];
    let arr = filterArchive(filterBySearch(src, keys));

    $('listTitle').textContent = isOnline ? 'Tugasan Online' : 'Tugasan Offline';
    $('pmCount').textContent = arr.length;
    $('pmEmpty').hidden = arr.length > 0;

    $('pmList').innerHTML = arr.map(d => {
      const paid = String(d.payment_status || '').toUpperCase() === 'PAID';
      const archived = d.archived === true;
      const statusCls = archived ? 'status-archived' : (paid ? 'status-paid' : 'status-pending');
      const statusTxt = archived ? 'Arkib' : (paid ? 'Paid' : (d.payment_status || 'Pending'));
      const title = isOnline
        ? `${esc(d.namaCust || d.nama || '-')} — ${esc(d.model || d.kerosakan || '-')}`
        : `${esc(d.namaKedai || '-')} — ${esc(d.model || d.kerosakan || '-')}`;
      const sender = isOnline ? (d.sender || '-') : (d.namaCust || '-');
      return `
        <div class="pm-card ${archived ? 'is-archived' : ''}">
          <div class="pm-card__head">
            <div class="pm-card__siri">#${esc(d.siri || d.id)}</div>
            <span class="pm-card__status ${statusCls}">${esc(statusTxt)}</span>
          </div>
          <div class="pm-card__title">${title}</div>
          <div class="pm-card__sub">${isOnline ? 'Sender' : 'Customer'}: ${esc(sender)}</div>
          <div class="pm-card__meta">
            <span><i class="fas fa-clock"></i> ${fmtDate(tsMs(d.timestamp))}</span>
            <span><i class="fas fa-credit-card"></i> ${esc(d.cara_bayaran || '-')}</span>
            <span><i class="fas fa-user"></i> ${esc(d.staff_repair || d.staff_terima || '-')}</span>
            <span class="pm-card__amount">${fmtMoney(d.total)}</span>
          </div>
        </div>`;
    }).join('');
  }

  function renderDealers() {
    const arr = state.dealers;
    $('pmDealerCount').textContent = arr.length;
    $('pmDealerEmpty').hidden = arr.length > 0;
    $('pmDealers').innerHTML = arr.map(d => {
      const nm = String(d.nama || d.namaKedai || '-');
      const init = nm.trim().charAt(0).toUpperCase() || '?';
      return `
        <div class="pm-dealer">
          <div class="pm-dealer__avatar">${esc(init)}</div>
          <div>
            <div class="pm-dealer__name">${esc(nm)}</div>
            <div class="pm-dealer__shop">${esc(d.namaKedai || d.cawangan || '-')}</div>
            <div class="pm-dealer__tel"><i class="fas fa-phone"></i> ${esc(d.tel || d.telefon || '-')}</div>
          </div>
        </div>`;
    }).join('');
  }

  // ---- events ----
  $('pmTabs').addEventListener('click', e => {
    const b = e.target.closest('.pm-tab');
    if (!b) return;
    state.tab = b.dataset.tab;
    document.querySelectorAll('.pm-tab').forEach(x => x.classList.toggle('is-active', x === b));
    renderList();
  });
  $('pmSearch').addEventListener('input', e => { state.search = e.target.value; renderList(); });
  $('pmArchived').addEventListener('change', e => { state.showArchived = e.target.checked; renderList(); });

  renderStatus();
  renderList();
  renderDealers();
})();
