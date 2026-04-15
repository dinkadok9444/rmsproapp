/* marketplace.js — Fasa 1: shell + browse + product detail.
   Mirror marketplace_shell.dart + marketplace_browse_screen.dart + product_detail_screen.dart.
   Data source = Firestore `marketplace_global` (mirror dart — marketplace kekal Firebase per RUNBOOK).
   Auth via Supabase; tenant.owner_id + branches.shop_code jadi ownerID/shopID (compat dengan dart).
*/
(async function () {
  'use strict';

  const ctx = await window.requireAuth();
  if (!ctx) return;

  // Firebase init (sama project sebagai Flutter app)
  const FB_CONFIG = {
    apiKey: 'AIzaSyCiCmpmEFnaZKx1OE84a2OgRDEn8E9Ulfk',
    appId: '1:94407896005:web:42a2ab858a0b24280379ac',
    messagingSenderId: '94407896005',
    projectId: 'rmspro-2f454',
    authDomain: 'rmspro-2f454.firebaseapp.com',
    storageBucket: 'rmspro-2f454.firebasestorage.app',
    databaseURL: 'https://rmspro-2f454-default-rtdb.asia-southeast1.firebasedatabase.app',
  };
  if (!window.firebase) { alert('Firebase SDK tak dimuatkan'); return; }
  if (!firebase.apps.length) firebase.initializeApp(FB_CONFIG);
  const fs = firebase.firestore();

  // Resolve ownerID (= tenants.owner_id) + shopID (= branches.shop_code)
  const [{ data: tenant }, { data: branch }] = await Promise.all([
    window.sb.from('tenants').select('owner_id, shop_name').eq('id', ctx.tenant_id).single(),
    window.sb.from('branches').select('shop_code, nama_kedai').eq('id', ctx.current_branch_id).single(),
  ]);
  const ownerID = tenant?.owner_id || '';
  const shopID = branch?.shop_code || '';
  const shopName = branch?.nama_kedai || tenant?.shop_name || '';

  if (!ownerID || !shopID) {
    document.getElementById('mpGridHost').innerHTML =
      '<div class="mp-empty"><i class="fas fa-triangle-exclamation"></i><p>Profil kedai tidak lengkap</p></div>';
    return;
  }

  // Expose untuk phase seterusnya (checkout / pesanan / kedai_saya)
  window.__mp = { fs, ownerID, shopID, shopName };

  // ── Helpers ────────────────────────────────────────────────────────────
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'mp-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2400);
  }

  // ── Shell: tab switcher ────────────────────────────────────────────────
  const tabs = document.querySelectorAll('#mpTabs .mp-tab');
  tabs.forEach(t => {
    t.addEventListener('click', () => {
      tabs.forEach(x => x.classList.remove('active'));
      t.classList.add('active');
      document.querySelectorAll('.mp-pane').forEach(p => p.classList.remove('active'));
      $('pane' + t.dataset.pane[0].toUpperCase() + t.dataset.pane.slice(1)).classList.add('active');
    });
  });

  // ── Browse: categories + search + grid stream ─────────────────────────
  const CATS = ['Semua', 'LCD', 'Bateri', 'Casing', 'Spare Part', 'Aksesori', 'Lain-lain'];
  let selectedCat = 'Semua';
  let searchQ = '';
  let unsub = null;
  let docs = [];

  function renderChips() {
    $('mpChips').innerHTML = CATS.map(c =>
      `<button class="mp-chip ${c === selectedCat ? 'active' : ''}" data-cat="${esc(c)}">${esc(c)}</button>`
    ).join('');
    $('mpChips').querySelectorAll('.mp-chip').forEach(el => {
      el.addEventListener('click', () => {
        selectedCat = el.dataset.cat;
        renderChips();
        subscribe();
      });
    });
  }

  function matchesSearch(d) {
    if (!searchQ) return true;
    const q = searchQ.toLowerCase();
    return (d.itemName || '').toLowerCase().includes(q)
        || (d.shopName || '').toLowerCase().includes(q)
        || (d.description || '').toLowerCase().includes(q);
  }

  function cardHtml(docId, d) {
    const img = d.imageUrl
      ? `<img src="${esc(d.imageUrl)}" alt="" onerror="this.style.display='none';this.nextElementSibling.style.display='flex';">
         <div class="ph" style="display:none;"><i class="fas fa-image"></i></div>`
      : `<div class="ph"><i class="fas fa-image"></i></div>`;
    const own = d.shopID === shopID ? `<span class="mp-card__own">KEDAI ANDA</span>` : '';
    const sold = (d.soldCount || 0) > 0 ? ` · <i class="fas fa-fire-flame-simple" style="color:var(--mp-orange);"></i> ${d.soldCount}` : '';
    const stock = Number(d.quantity) || 0;
    return `
      <div class="mp-card" data-id="${esc(docId)}">
        <div class="mp-card__img">${img}${own}</div>
        <div class="mp-card__body">
          <div class="mp-card__name">${esc(d.itemName || '—')}</div>
          <div class="mp-card__shop">${esc(d.shopName || '')}</div>
          <div class="mp-card__price">${fmtRM(d.price)}</div>
          <div class="mp-card__meta">Stok ${stock}${sold}</div>
        </div>
      </div>`;
  }

  function renderGrid() {
    const host = $('mpGridHost');
    const filtered = docs.filter(x => matchesSearch(x.data));
    if (!filtered.length) {
      host.innerHTML = `
        <div class="mp-empty">
          <i class="fas fa-box-open"></i>
          <p>Tiada item dalam marketplace</p>
          <small>Cuba tukar kategori atau kata carian</small>
        </div>`;
      return;
    }
    host.innerHTML = `<div class="mp-grid">${filtered.map(x => cardHtml(x.id, x.data)).join('')}</div>`;
    host.querySelectorAll('.mp-card').forEach(el => {
      el.addEventListener('click', () => openProductDetail(el.dataset.id));
    });
  }

  function subscribe() {
    if (unsub) { try { unsub(); } catch (_) {} }
    $('mpGridHost').innerHTML = '<div class="mp-loading"><div class="mp-spin"></div></div>';

    let q = fs.collection('marketplace_global');
    if (selectedCat !== 'Semua') q = q.where('category', '==', selectedCat);
    q = q.orderBy('createdAt', 'desc').limit(50);

    unsub = q.onSnapshot(
      (snap) => {
        docs = snap.docs.map(d => ({ id: d.id, data: d.data() || {} }));
        renderGrid();
      },
      (err) => {
        console.error('marketplace_global stream error', err);
        $('mpGridHost').innerHTML = `
          <div class="mp-empty">
            <i class="fas fa-triangle-exclamation" style="color:var(--mp-red);"></i>
            <p>Ralat memuatkan data</p>
            <small>${esc(err.message || '')}</small>
          </div>`;
      },
    );
  }

  // Search input
  const sInput = $('mpSearchInput');
  const sClr = $('mpSearchClear');
  sInput.addEventListener('input', () => {
    searchQ = sInput.value.trim();
    sClr.hidden = !searchQ;
    renderGrid();
  });
  sClr.addEventListener('click', () => {
    sInput.value = ''; searchQ = ''; sClr.hidden = true; renderGrid(); sInput.focus();
  });

  renderChips();
  subscribe();

  // ── Product Detail modal ──────────────────────────────────────────────
  let pdUnsub = null;
  let pdQty = 1;
  let pdDocId = '';
  let pdData = null;

  function closePd() {
    $('mpPdBg').classList.remove('show');
    if (pdUnsub) { try { pdUnsub(); } catch (_) {} pdUnsub = null; }
    pdDocId = ''; pdData = null; pdQty = 1;
  }
  $('mpPdBack').addEventListener('click', closePd);
  $('mpPdBg').addEventListener('click', (e) => { if (e.target === $('mpPdBg')) closePd(); });

  function renderPd() {
    if (!pdData) {
      $('mpPdContent').innerHTML = '<div class="mp-loading" style="height:300px;"><div class="mp-spin"></div></div>';
      return;
    }
    const d = pdData;
    const price = Number(d.price) || 0;
    const stock = Number(d.quantity) || 0;
    const sold = Number(d.soldCount) || 0;
    const isOwn = (d.ownerID || '') === ownerID;
    const img = d.imageUrl
      ? `<img src="${esc(d.imageUrl)}" alt="">`
      : `<div class="ph"><i class="fas fa-image"></i></div>`;

    let bar;
    if (isOwn) {
      bar = `<div class="mp-disabled">Ini produk anda</div>`;
    } else if (stock <= 0) {
      bar = `<div class="mp-disabled err">Stok habis</div>`;
    } else {
      if (pdQty > stock) pdQty = stock;
      bar = `
        <div class="mp-qty">
          <button id="pdMinus" ${pdQty <= 1 ? 'disabled' : ''}><i class="fas fa-minus"></i></button>
          <span>${pdQty}</span>
          <button id="pdPlus" ${pdQty >= stock ? 'disabled' : ''}><i class="fas fa-plus"></i></button>
        </div>
        <button class="mp-buy" id="pdBuy">BELI SEKARANG</button>`;
    }

    $('mpPdTitle').textContent = (d.itemName || 'Produk').toUpperCase();
    $('mpPdContent').innerHTML = `
      <div class="mp-pd-img">${img}</div>
      <div class="mp-pd-price">
        <div class="val">${fmtRM(price)}</div>
        <div class="meta">
          ${d.category ? `<span class="cat">${esc(d.category)}</span>` : ''}
          <span class="stk"><i class="fas fa-box-open"></i> Stok: ${stock}</span>
          ${sold > 0 ? `<span class="sold"><i class="fas fa-fire-flame-simple"></i> ${sold} terjual</span>` : ''}
        </div>
      </div>
      <div class="mp-pd-body">
        <h4>${esc(d.itemName || 'Produk')}</h4>
        ${d.description ? `<p>${esc(d.description)}</p>` : ''}
      </div>
      <div class="mp-pd-bar">${bar}</div>`;

    const minus = $('pdMinus'), plus = $('pdPlus'), buy = $('pdBuy');
    if (minus) minus.addEventListener('click', () => { if (pdQty > 1) { pdQty--; renderPd(); } });
    if (plus) plus.addEventListener('click', () => { if (pdQty < stock) { pdQty++; renderPd(); } });
    if (buy) buy.addEventListener('click', () => {
      // Fasa 2: sambung ke checkout. Buat masa ni, buka stub modal.
      if (typeof window.mpOpenCheckout === 'function') {
        window.mpOpenCheckout({ item: { ...d, _docId: pdDocId }, quantity: pdQty });
      } else {
        $('mpCoBg').classList.add('show');
        snack('Checkout akan disambungkan di Fasa 2');
      }
    });
  }

  function openProductDetail(docId) {
    pdDocId = docId; pdData = null; pdQty = 1;
    $('mpPdBg').classList.add('show');
    renderPd();
    pdUnsub = fs.collection('marketplace_global').doc(docId).onSnapshot(
      (doc) => {
        if (!doc.exists) {
          $('mpPdContent').innerHTML = '<div class="mp-empty"><i class="fas fa-circle-question"></i><p>Produk tidak dijumpai</p></div>';
          return;
        }
        pdData = doc.data() || {};
        renderPd();
      },
      (err) => {
        console.error('product detail stream error', err);
        $('mpPdContent').innerHTML = `<div class="mp-empty"><i class="fas fa-triangle-exclamation"></i><p>Ralat: ${esc(err.message || '')}</p></div>`;
      },
    );
  }

  // Expose untuk sub-modules Fasa lain
  window.__mp.openProductDetail = openProductDetail;
})();
