/* marketplace_seller.js — Fasa 3: kedai_saya + jualan_masuk.
   Mirror kedai_saya_screen.dart + jualan_masuk_screen.dart.
   Depends on window.__mp dari marketplace.js.
   NOTE:
   - Image upload produk guna URL input (Firebase Storage + compression skip buat masa ni).
   - Courier API (Delyva/EasyParcel) skip — seller key-in tracking+courier manual.
   - IC verification upload skip (complex storage flow). */
(function () {
  'use strict';

  const waitMp = setInterval(() => {
    if (window.__mp) { clearInterval(waitMp); init(); }
  }, 50);

  function init() {
    const { fs, ownerID, shopID, shopName } = window.__mp;
    const shopDocId = `${ownerID}_${shopID}`;

    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
    const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const fmtDate = (ts) => {
      if (!ts) return '-';
      const d = ts.toDate ? ts.toDate() : (ts instanceof Date ? ts : null);
      if (!d) return '-';
      const p = (n) => String(n).padStart(2, '0');
      return `${p(d.getDate())}/${p(d.getMonth()+1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
    };

    function snack(msg, err) {
      const el = document.createElement('div');
      el.className = 'mp-snack' + (err ? ' err' : '');
      el.textContent = msg;
      document.body.appendChild(el);
      setTimeout(() => el.remove(), 2400);
    }

    // Escape for attribute values (double quotes)
    const CATS = ['LCD', 'Bateri', 'Casing', 'Spare Part', 'Aksesori', 'Lain-lain'];

    // ══════════════════════════════════════════════════════════════════
    // KEDAI SAYA pane (mirror kedai_saya_screen.dart)
    // ══════════════════════════════════════════════════════════════════

    const paneK = $('paneKedai');
    paneK.innerHTML = `
      <div id="mpKsHeader"></div>
      <div class="mp-ks-section-head">
        <span class="mp-ks-icon"><i class="fas fa-boxes-packing"></i></span>
        <h3>Produk Saya</h3>
        <button class="mp-ks-fab" id="mpKsAdd"><i class="fas fa-plus"></i> Tambah</button>
      </div>
      <div id="mpKsProducts"><div class="mp-loading"><div class="mp-spin"></div></div></div>
    `;

    function renderKsHeader(totalProducts, totalSold) {
      $('mpKsHeader').innerHTML = `
        <div class="mp-ks-hdr">
          <div class="mp-ks-hdr-row">
            <div class="mp-ks-hdr-icon"><i class="fas fa-shop"></i></div>
            <div class="mp-ks-hdr-info">
              <div class="mp-ks-hdr-name">${esc(shopName || 'Kedai Saya')}</div>
              <div class="mp-ks-hdr-id">ID: ${esc(shopID)}</div>
            </div>
            <button class="mp-ks-hdr-gear" id="mpKsGear"><i class="fas fa-gear"></i></button>
          </div>
          <div class="mp-ks-hdr-stats">
            <div><i class="fas fa-box-open"></i> <b>${totalProducts}</b> <span>Produk</span></div>
            <div><i class="fas fa-cart-shopping"></i> <b>${totalSold}</b> <span>Terjual</span></div>
          </div>
        </div>`;
      $('mpKsGear').addEventListener('click', openSettings);
    }

    function ksProductCard(id, d) {
      const img = d.imageUrl
        ? `<img src="${esc(d.imageUrl)}" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'ph',innerHTML:'<i class=\\'fas fa-image\\'></i>'}))">`
        : `<div class="ph"><i class="fas fa-image"></i></div>`;
      const active = d.isActive !== false;
      return `
        <div class="mp-ks-card ${active ? '' : 'inactive'}">
          <div class="mp-ks-card__img">${img}</div>
          <div class="mp-ks-card__body">
            <div class="mp-ks-card__name">${esc(d.itemName || '—')}</div>
            <div class="mp-ks-card__price">${fmtRM(d.price)}</div>
            <div class="mp-ks-card__stk">Stok: ${Number(d.quantity) || 0}</div>
            ${!active ? '<span class="mp-ks-card__off">Tidak Aktif</span>' : ''}
          </div>
          <div class="mp-ks-card__acts">
            <button data-act="toggle" data-id="${esc(id)}" data-active="${active}" title="${active ? 'Nyahaktif' : 'Aktif'}">
              <i class="fas fa-toggle-${active ? 'on' : 'off'}" style="color:${active ? '#10B981' : '#94A3B8'};"></i>
            </button>
            <button data-act="edit" data-id="${esc(id)}" title="Edit">
              <i class="fas fa-pen-to-square" style="color:var(--mp-purple);"></i>
            </button>
            <button data-act="del" data-id="${esc(id)}" title="Padam">
              <i class="fas fa-trash-can" style="color:var(--mp-red);"></i>
            </button>
          </div>
        </div>`;
    }

    let ksDocs = [];
    let ksUnsub = null;

    function renderKsProducts() {
      const host = $('mpKsProducts');
      if (!ksDocs.length) {
        host.innerHTML = `
          <div class="mp-empty">
            <i class="fas fa-box-open"></i>
            <p>Tiada produk lagi</p>
            <small>Tekan "Tambah" untuk daftar produk</small>
          </div>`;
        return;
      }
      host.innerHTML = ksDocs.map(x => ksProductCard(x.id, x.data)).join('');
      host.querySelectorAll('button[data-act]').forEach(btn => {
        btn.addEventListener('click', async () => {
          const id = btn.dataset.id;
          const act = btn.dataset.act;
          const doc = ksDocs.find(x => x.id === id);
          if (!doc) return;
          try {
            if (act === 'toggle') {
              await fs.collection('marketplace_global').doc(id).update({
                isActive: !(doc.data.isActive !== false),
                updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
              });
            } else if (act === 'edit') {
              openProductForm(doc.data, id);
            } else if (act === 'del') {
              if (!confirm('Adakah anda pasti mahu padam produk ini?')) return;
              await fs.collection('marketplace_global').doc(id).delete();
              snack('Produk dipadam.');
            }
          } catch (err) {
            snack('Ralat: ' + (err.message || err), true);
          }
        });
      });
    }

    function subscribeKs() {
      ksUnsub = fs.collection('marketplace_global')
        .where('ownerID', '==', ownerID)
        .orderBy('createdAt', 'desc')
        .onSnapshot(
          (snap) => {
            ksDocs = snap.docs.map(d => ({ id: d.id, data: d.data() || {} }));
            let totalProducts = ksDocs.length;
            let totalSold = 0;
            ksDocs.forEach(x => totalSold += Number(x.data.soldCount) || 0);
            renderKsHeader(totalProducts, totalSold);
            renderKsProducts();
          },
          (err) => {
            console.error('kedai stream error', err);
            $('mpKsProducts').innerHTML = `
              <div class="mp-empty"><i class="fas fa-triangle-exclamation" style="color:var(--mp-red);"></i>
              <p>Ralat</p><small>${esc(err.message || '')}</small></div>`;
          },
        );
    }

    // ── Settings popup (bank, pickup, receiver) ────────────────────────
    function openSettings() {
      const bg = mkModal(`
        <div class="mp-modal__head">
          <h3><i class="fas fa-gear"></i> Tetapan Kedai</h3>
          <button class="mp-modal__close" data-close><i class="fas fa-xmark"></i></button>
        </div>
        <div style="padding:16px; display:flex; flex-direction:column; gap:10px;">
          ${settingsTile('Maklumat Bank', 'Akaun bank untuk terima bayaran', 'fa-building-columns', '#3B82F6', 'bank')}
          ${settingsTile('Alamat Pickup', 'Alamat asal untuk kurier pickup', 'fa-location-dot', '#10B981', 'pickup')}
          ${settingsTile('Alamat Penerima', 'Default alamat terima dari marketplace', 'fa-map-location-dot', '#3B82F6', 'receiver')}
        </div>`);
      bg.querySelectorAll('[data-s]').forEach(el => {
        el.addEventListener('click', () => {
          const s = el.dataset.s;
          closeModal(bg);
          if (s === 'bank') openBankForm();
          if (s === 'pickup') openAddressForm('pickup');
          if (s === 'receiver') openAddressForm('receiver');
        });
      });
    }

    function settingsTile(title, sub, icon, col, s) {
      return `
        <div class="mp-set-tile" data-s="${s}">
          <div class="mp-set-tile__ic" style="background:${col}1a; color:${col};"><i class="fas ${icon}"></i></div>
          <div class="mp-set-tile__txt">
            <b>${esc(title)}</b>
            <small>${esc(sub)}</small>
          </div>
          <i class="fas fa-chevron-right" style="color:var(--mp-text-dim);"></i>
        </div>`;
    }

    async function openBankForm() {
      const doc = await fs.collection('marketplace_shops').doc(shopDocId).get().catch(() => null);
      const d = doc && doc.exists ? (doc.data() || {}) : {};
      const bg = mkModal(`
        <div class="mp-modal__head" style="background:#3B82F6;">
          <h3><i class="fas fa-building-columns"></i> Maklumat Bank</h3>
          <button class="mp-modal__close" data-close><i class="fas fa-xmark"></i></button>
        </div>
        <div style="padding:16px; display:flex; flex-direction:column; gap:10px;">
          <input class="mp-co-inp" id="bkName" placeholder="Nama Bank (cth: Maybank)" value="${esc(d.bankName || '')}">
          <input class="mp-co-inp" id="bkNo" placeholder="No. Akaun" value="${esc(d.bankAccountNo || '')}">
          <input class="mp-co-inp" id="bkHolder" placeholder="Nama Pemilik Akaun" value="${esc(d.bankAccountName || '')}">
          <button class="mp-buy" style="background:#3B82F6;" id="bkSave"><i class="fas fa-floppy-disk"></i> SIMPAN</button>
        </div>`);
      bg.querySelector('#bkSave').addEventListener('click', async () => {
        try {
          await fs.collection('marketplace_shops').doc(shopDocId).set({
            bankName: $('bkName').value.trim(),
            bankAccountNo: $('bkNo').value.trim(),
            bankAccountName: $('bkHolder').value.trim(),
            ownerID, shopID,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          closeModal(bg);
          snack('Maklumat bank disimpan.');
        } catch (err) { snack('Ralat: ' + (err.message || err), true); }
      });
    }

    async function openAddressForm(kind) {
      const isPickup = kind === 'pickup';
      const prefix = isPickup ? 'pickup' : 'receiver';
      const color = isPickup ? '#10B981' : '#3B82F6';
      const title = isPickup ? 'Alamat Pickup' : 'Alamat Penerima';
      const iconClass = isPickup ? 'fa-location-dot' : 'fa-map-location-dot';
      const doc = await fs.collection('marketplace_shops').doc(shopDocId).get().catch(() => null);
      const d = doc && doc.exists ? (doc.data() || {}) : {};

      const namaFld = isPickup ? '' : `<input class="mp-co-inp" id="adNama" placeholder="Nama Penerima" value="${esc(d.receiverName || '')}">`;
      const phoneKey = isPickup ? 'phone' : 'receiverPhone';

      const bg = mkModal(`
        <div class="mp-modal__head" style="background:${color};">
          <h3><i class="fas ${iconClass}"></i> ${esc(title)}</h3>
          <button class="mp-modal__close" data-close><i class="fas fa-xmark"></i></button>
        </div>
        <div style="padding:16px; display:flex; flex-direction:column; gap:10px;">
          ${namaFld}
          <input class="mp-co-inp" id="adPhone" placeholder="No. Telefon" value="${esc(d[phoneKey] || '')}">
          <input class="mp-co-inp" id="adAlamat" placeholder="Alamat Penuh" value="${esc(d[prefix + 'Alamat'] || '')}">
          <div style="display:flex; gap:8px;">
            <input class="mp-co-inp" id="adBandar" placeholder="Bandar" value="${esc(d[prefix + 'Bandar'] || '')}" style="flex:1;">
            <input class="mp-co-inp" id="adPoskod" placeholder="Poskod" value="${esc(d[prefix + 'Poskod'] || '')}" style="width:100px;" inputmode="numeric">
          </div>
          <input class="mp-co-inp" id="adNegeri" placeholder="Negeri" value="${esc(d[prefix + 'Negeri'] || '')}">
          <button class="mp-buy" style="background:${color};" id="adSave"><i class="fas fa-floppy-disk"></i> SIMPAN</button>
        </div>`);
      bg.querySelector('#adSave').addEventListener('click', async () => {
        try {
          const patch = {
            [phoneKey]: $('adPhone').value.trim(),
            [prefix + 'Alamat']: $('adAlamat').value.trim(),
            [prefix + 'Bandar']: $('adBandar').value.trim(),
            [prefix + 'Poskod']: $('adPoskod').value.trim(),
            [prefix + 'Negeri']: $('adNegeri').value.trim(),
            ownerID, shopID,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          };
          if (!isPickup) patch.receiverName = ($('adNama') && $('adNama').value.trim()) || '';
          await fs.collection('marketplace_shops').doc(shopDocId).set(patch, { merge: true });
          closeModal(bg);
          snack(title + ' disimpan.');
        } catch (err) { snack('Ralat: ' + (err.message || err), true); }
      });
    }

    // ── Product form (add/edit) ─────────────────────────────────────────
    function openProductForm(existing, docId) {
      const isEdit = !!docId;
      const e = existing || {};
      const catsOpt = CATS.map(c =>
        `<option value="${esc(c)}" ${e.category === c ? 'selected' : ''}>${esc(c)}</option>`
      ).join('');
      const bg = mkModal(`
        <div class="mp-modal__head">
          <h3>${isEdit ? 'Kemaskini Produk' : 'Tambah Produk Baru'}</h3>
          <button class="mp-modal__close" data-close><i class="fas fa-xmark"></i></button>
        </div>
        <div style="padding:16px; display:flex; flex-direction:column; gap:10px;">
          <input class="mp-co-inp" id="pfName" placeholder="Nama Produk" value="${esc(e.itemName || '')}">
          <textarea class="mp-co-inp" id="pfDesc" rows="3" placeholder="Penerangan">${esc(e.description || '')}</textarea>
          <select class="mp-co-inp" id="pfCat">${catsOpt}</select>
          <div style="display:flex; gap:8px;">
            <input class="mp-co-inp" id="pfPrice" placeholder="Harga (RM)" inputmode="decimal" value="${e.price != null ? e.price : ''}" style="flex:1;">
            <input class="mp-co-inp" id="pfQty" placeholder="Kuantiti" inputmode="numeric" value="${e.quantity != null ? e.quantity : ''}" style="flex:1;">
          </div>
          <input class="mp-co-inp" id="pfImg" placeholder="URL Gambar (https://...)" value="${esc(e.imageUrl || '')}">
          <small style="color:var(--mp-text-dim); font-size:10px;">Nota: Upload gambar langsung belum disokong di web. Gunakan URL gambar (host kat Imgur/Cloudinary/dll).</small>
          <button class="mp-buy" id="pfSave">${isEdit ? 'KEMASKINI' : 'TAMBAH'}</button>
        </div>`);
      bg.querySelector('#pfSave').addEventListener('click', async () => {
        const btn = bg.querySelector('#pfSave');
        const name = $('pfName').value.trim();
        if (!name) { snack('Nama produk diperlukan', true); return; }
        const price = parseFloat($('pfPrice').value) || 0;
        const qty = parseInt($('pfQty').value, 10) || 0;
        btn.disabled = true;
        try {
          const payload = {
            itemName: name,
            description: $('pfDesc').value.trim(),
            category: $('pfCat').value,
            price, quantity: qty,
            imageUrl: $('pfImg').value.trim(),
            ownerID, shopID, shopName,
            isActive: true,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          };
          if (isEdit) {
            await fs.collection('marketplace_global').doc(docId).update(payload);
          } else {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
            payload.soldCount = 0;
            await fs.collection('marketplace_global').add(payload);
          }
          closeModal(bg);
          snack(isEdit ? 'Produk dikemaskini.' : 'Produk ditambah.');
        } catch (err) {
          snack('Ralat: ' + (err.message || err), true);
          btn.disabled = false;
        }
      });
    }

    $('mpKsAdd').addEventListener('click', () => openProductForm());

    // ══════════════════════════════════════════════════════════════════
    // JUALAN MASUK pane (mirror jualan_masuk_screen.dart)
    // ══════════════════════════════════════════════════════════════════

    const paneJ = $('paneJualan');
    paneJ.innerHTML = `
      <div id="mpJmStats"></div>
      <div id="mpJmHost"><div class="mp-loading"><div class="mp-spin"></div></div></div>
    `;

    let jmDocs = [];
    let jmUnsub = null;

    const STATUS_LABEL_J = {
      pending_payment: 'BELUM BAYAR', paid: 'DIBAYAR', shipped: 'DIHANTAR',
      completed: 'SELESAI', cancelled: 'DIBATALKAN',
    };
    const STATUS_COLOR_J = {
      pending_payment: '#D97706', paid: '#2563EB', shipped: '#8B5CF6',
      completed: '#10B981', cancelled: '#EF4444',
    };

    function renderJmStats() {
      let totalPayout = 0, completed = 0;
      jmDocs.forEach(x => {
        if (x.data.status === 'completed') {
          completed++;
          totalPayout += Number(x.data.sellerPayout) || 0;
        }
      });
      $('mpJmStats').innerHTML = `
        <div class="mp-jm-stats">
          <div class="mp-jm-stat" style="background:#10B9810f; border-color:#10B98140; color:#10B981;">
            <div class="mp-jm-stat__h"><i class="fas fa-money-bill-wave"></i> JUMLAH TERIMA</div>
            <div class="mp-jm-stat__v">${fmtRM(totalPayout)}</div>
          </div>
          <div class="mp-jm-stat" style="background:#8B5CF60f; border-color:#8B5CF640; color:#8B5CF6;">
            <div class="mp-jm-stat__h"><i class="fas fa-circle-check"></i> JUALAN SELESAI</div>
            <div class="mp-jm-stat__v">${completed}</div>
          </div>
        </div>`;
    }

    function jmOrderCard(id, d) {
      const status = d.status || '';
      const col = STATUS_COLOR_J[status] || '#94A3B8';
      const label = STATUS_LABEL_J[status] || status.toUpperCase();
      const qty = Number(d.quantity) || 1;
      const unit = Number(d.pricePerUnit ?? d.price) || 0;
      const total = Number(d.totalPrice) || 0;
      const payout = Number(d.sellerPayout) || 0;
      const trk = d.trackingNumber || '';

      let extras = '';
      if (status === 'shipped' && trk) {
        extras += `
          <div class="mp-jm-trk">
            <i class="fas fa-truck-fast"></i>
            <div>
              <b>${esc(d.courierName || 'Kurier')}</b>
              <span>${esc(trk)}</span>
            </div>
          </div>`;
      }
      if (status === 'paid') {
        extras += `
          <div class="mp-jm-acts">
            <button class="mp-jm-ship" data-ship="${esc(id)}"><i class="fas fa-truck-fast"></i> HANTAR</button>
            <button class="mp-jm-cancel" data-cancel="${esc(id)}"><i class="fas fa-xmark"></i> BATAL</button>
          </div>`;
      }

      return `
        <div class="mp-ps-card">
          <div class="mp-ps-row1">
            <span class="mp-ps-badge" style="background:${col}1f; color:${col};">${esc(label)}</span>
            <span class="mp-ps-date">${fmtDate(d.createdAt)}</span>
          </div>
          <div class="mp-ps-name">${esc((d.itemName || '-').toUpperCase())}</div>
          <div class="mp-ps-shop"><i class="fas fa-user"></i> Pembeli: ${esc((d.buyerShopName || '-').toUpperCase())}</div>
          <div class="mp-ps-totals">
            <span>${qty} × ${fmtRM(unit)} = ${fmtRM(total)}</span>
            <b style="color:#10B981;">Terima: ${fmtRM(payout)}</b>
          </div>
          ${extras}
        </div>`;
    }

    function renderJmList() {
      const host = $('mpJmHost');
      if (!jmDocs.length) {
        host.innerHTML = `
          <div class="mp-empty">
            <i class="fas fa-box-open"></i>
            <p>Tiada jualan masuk</p>
            <small>Pesanan pembeli akan muncul di sini</small>
          </div>`;
        return;
      }
      host.innerHTML = `<div style="padding:0 2px;">${jmDocs.map(x => jmOrderCard(x.id, x.data)).join('')}</div>`;
      host.querySelectorAll('[data-ship]').forEach(el => {
        el.addEventListener('click', () => openShipDialog(el.dataset.ship));
      });
      host.querySelectorAll('[data-cancel]').forEach(el => {
        el.addEventListener('click', async () => {
          if (!confirm('Batalkan pesanan ini? Tindakan tidak boleh diundur.')) return;
          try {
            await fs.collection('marketplace_orders').doc(el.dataset.cancel).update({
              status: 'cancelled',
              updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
            });
            snack('Pesanan dibatalkan.');
          } catch (err) { snack('Ralat: ' + (err.message || err), true); }
        });
      });
    }

    function openShipDialog(orderId) {
      const bg = mkModal(`
        <div class="mp-modal__head">
          <h3><i class="fas fa-truck-fast"></i> Uruskan Penghantaran</h3>
          <button class="mp-modal__close" data-close><i class="fas fa-xmark"></i></button>
        </div>
        <div style="padding:16px; display:flex; flex-direction:column; gap:12px;">
          <div style="background:#FFFBEB; border:1px solid #FDE68A; padding:12px; border-radius:12px; text-align:center;">
            <i class="fas fa-triangle-exclamation" style="color:#F59E0B; font-size:20px;"></i>
            <div style="font-weight:800; margin-top:8px;">Nota</div>
            <small style="color:var(--mp-text-muted);">Integrasi courier API (Delyva) belum disambung di web. Sila key-in no. tracking & nama kurier manual.</small>
          </div>
          <input class="mp-co-inp" id="shCourier" placeholder="Nama Kurier (cth: J&T, Pos Laju)">
          <input class="mp-co-inp" id="shTrk" placeholder="No. Penjejakan">
          <button class="mp-buy" id="shSave"><i class="fas fa-paper-plane"></i> TANDA DIHANTAR</button>
        </div>`);
      bg.querySelector('#shSave').addEventListener('click', async () => {
        const courier = $('shCourier').value.trim();
        const trk = $('shTrk').value.trim();
        if (!courier || !trk) { snack('Sila isi kurier dan no. penjejakan', true); return; }
        try {
          await fs.collection('marketplace_orders').doc(orderId).update({
            status: 'shipped',
            trackingNumber: trk,
            courierName: courier,
            shippedAt: firebase.firestore.FieldValue.serverTimestamp(),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          });
          closeModal(bg);
          snack('Pesanan ditanda dihantar.');
        } catch (err) { snack('Ralat: ' + (err.message || err), true); }
      });
    }

    function subscribeJm() {
      jmUnsub = fs.collection('marketplace_orders')
        .where('sellerOwnerID', '==', ownerID)
        .orderBy('createdAt', 'desc')
        .onSnapshot(
          (snap) => {
            jmDocs = snap.docs.map(d => ({ id: d.id, data: d.data() || {} }));
            renderJmStats();
            renderJmList();
          },
          (err) => {
            console.error('jualan stream error', err);
            $('mpJmHost').innerHTML = `
              <div class="mp-empty"><i class="fas fa-triangle-exclamation" style="color:var(--mp-red);"></i>
              <p>Ralat</p><small>${esc(err.message || '')}</small></div>`;
          },
        );
    }

    // ══════════════════════════════════════════════════════════════════
    // Generic modal helpers
    // ══════════════════════════════════════════════════════════════════

    function mkModal(html) {
      const bg = document.createElement('div');
      bg.className = 'mp-modal-bg show';
      bg.innerHTML = `<div class="mp-modal">${html}</div>`;
      document.body.appendChild(bg);
      bg.addEventListener('click', (e) => {
        if (e.target === bg || e.target.closest('[data-close]')) closeModal(bg);
      });
      return bg;
    }
    function closeModal(bg) { bg.remove(); }

    // Kick off subscriptions
    subscribeKs();
    subscribeJm();
  }
})();
