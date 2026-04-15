/* marketplace_orders.js — Fasa 2: checkout + pesanan_saya + order_detail.
   Mirror checkout_screen.dart + pesanan_saya_screen.dart + order_detail_screen.dart.
   Depends on window.__mp (set by marketplace.js) — fs, ownerID, shopID, shopName.
   NOTE: ToyyibPay payment gateway call perlu Cloud Function proxy (secret key tak boleh expose).
   Buat masa ni, kita mark order as 'paid' terus (testing mode, sama macam dart fallback).
   Shipping cost quote juga skip — subtotal jadi grand total. */
(function () {
  'use strict';

  const waitMp = setInterval(() => {
    if (window.__mp) { clearInterval(waitMp); init(); }
  }, 50);

  function init() {
    const { fs, ownerID, shopID, shopName } = window.__mp;

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
    const fmtDateLong = (ts) => {
      if (!ts) return '-';
      const d = ts.toDate ? ts.toDate() : (ts instanceof Date ? ts : null);
      if (!d) return '-';
      const months = ['Jan','Feb','Mac','Apr','Mei','Jun','Jul','Ogo','Sep','Okt','Nov','Dis'];
      const p = (n) => String(n).padStart(2, '0');
      const h = d.getHours(), ap = h >= 12 ? 'PM' : 'AM';
      const h12 = ((h + 11) % 12) + 1;
      return `${p(d.getDate())} ${months[d.getMonth()]} ${d.getFullYear()}, ${p(h12)}:${p(d.getMinutes())} ${ap}`;
    };

    function snack(msg, err) {
      const el = document.createElement('div');
      el.className = 'mp-snack' + (err ? ' err' : '');
      el.textContent = msg;
      document.body.appendChild(el);
      setTimeout(() => el.remove(), 2400);
    }

    const STATUS_LABEL = {
      pending_payment: 'BELUM BAYAR',
      paid: 'DIBAYAR',
      shipped: 'DIHANTAR',
      completed: 'SELESAI',
      cancelled: 'DIBATALKAN',
    };
    const STATUS_COLOR = {
      pending_payment: '#D97706',
      paid: '#2563EB',
      shipped: '#8B5CF6',
      completed: '#10B981',
      cancelled: '#EF4444',
    };

    // ══════════════════════════════════════════════════════════════════
    // CHECKOUT (mirror checkout_screen.dart)
    // ══════════════════════════════════════════════════════════════════

    const FILTERS = {
      all: 'Semua',
      pending_payment: 'Belum Bayar',
      paid: 'Dibayar',
      shipped: 'Dihantar',
      completed: 'Selesai',
      cancelled: 'Dibatalkan',
    };

    // Replace Checkout modal content
    window.mpOpenCheckout = async function ({ item, quantity }) {
      const bg = $('mpCoBg'), host = $('mpCoContent');
      bg.classList.add('show');

      const docId = item._docId || item.docId || '';
      const price = Number(item.price) || 0;
      const subtotal = price * quantity;
      const commission = subtotal * 0.02;
      const sellerPayout = subtotal * 0.98;

      host.innerHTML = '<div class="mp-loading" style="padding:20px;"><div class="mp-spin"></div></div>';

      // Load receiver address from buyer's shop profile
      let receiver = {};
      try {
        const doc = await fs.collection('marketplace_shops').doc(`${ownerID}_${shopID}`).get();
        if (doc.exists) receiver = doc.data() || {};
      } catch (_) {}

      host.innerHTML = `
        <div style="padding:16px; display:flex; flex-direction:column; gap:14px;">
          <!-- Order Summary -->
          <div class="mp-co-card">
            <div class="mp-co-title">Ringkasan Pesanan</div>
            <div style="display:flex; gap:12px; align-items:flex-start;">
              <div style="width:64px; height:64px; border-radius:10px; background:var(--mp-bg-deep); display:flex; align-items:center; justify-content:center; overflow:hidden; flex-shrink:0;">
                ${item.imageUrl ? `<img src="${esc(item.imageUrl)}" style="width:100%; height:100%; object-fit:cover;">` : '<i class="fas fa-box-open" style="color:var(--mp-purple);"></i>'}
              </div>
              <div style="flex:1; min-width:0;">
                <div style="font-size:14px; font-weight:700; color:var(--mp-text);">${esc(item.itemName || 'Produk')}</div>
                <div style="font-size:13px; color:var(--mp-text-muted); margin-top:4px;">${fmtRM(price)} × ${quantity}</div>
              </div>
              <div style="font-size:15px; font-weight:800; color:var(--mp-red);">${fmtRM(subtotal)}</div>
            </div>
          </div>

          <!-- Alamat Penerima -->
          <div class="mp-co-card">
            <div class="mp-co-title"><i class="fas fa-location-dot" style="color:#10B981;"></i> Alamat Penerima</div>
            <small style="color:var(--mp-text-muted); font-size:10px;">Alamat untuk kurier hantar barang kepada anda</small>
            <div class="mp-co-fields" style="margin-top:12px; display:flex; flex-direction:column; gap:8px;">
              <input class="mp-co-inp" id="coNama" placeholder="Nama Penerima" value="${esc(receiver.receiverName || '')}">
              <input class="mp-co-inp" id="coTel" placeholder="No. Telefon" value="${esc(receiver.receiverPhone || '')}">
              <input class="mp-co-inp" id="coAlamat" placeholder="Alamat Penuh" value="${esc(receiver.receiverAlamat || '')}">
              <div style="display:flex; gap:8px;">
                <input class="mp-co-inp" id="coBandar" placeholder="Bandar" value="${esc(receiver.receiverBandar || '')}" style="flex:1;">
                <input class="mp-co-inp" id="coPoskod" placeholder="Poskod" value="${esc(receiver.receiverPoskod || '')}" style="width:100px;" inputmode="numeric">
              </div>
              <input class="mp-co-inp" id="coNegeri" placeholder="Negeri" value="${esc(receiver.receiverNegeri || '')}">
            </div>
          </div>

          <!-- Price breakdown -->
          <div class="mp-co-card">
            <div class="mp-co-title">Pecahan Harga</div>
            <div class="mp-co-row"><span>Harga Produk</span><b>${fmtRM(subtotal)}</b></div>
            <div class="mp-co-row"><span style="font-size:10px; font-style:italic; color:var(--mp-text-dim);"><i class="fas fa-circle-info"></i> Komisyen Platform (2%): ${fmtRM(commission)}</span></div>
            <hr style="border:none; border-top:1px solid var(--mp-border); margin:10px 0;">
            <div class="mp-co-row" style="font-weight:900;"><span style="font-size:16px;">Jumlah Bayaran</span><b style="font-size:20px; color:var(--mp-red);">${fmtRM(subtotal)}</b></div>
          </div>

          <!-- Seller receives -->
          <div style="padding:12px; background:rgba(139,92,246,.06); border:1px solid rgba(139,92,246,.18); border-radius:12px; display:flex; align-items:center; gap:10px;">
            <i class="fas fa-shop" style="color:var(--mp-purple); font-size:14px;"></i>
            <div style="flex:1; font-size:12px; color:var(--mp-purple); font-weight:600;">Penjual akan menerima: ${fmtRM(sellerPayout)} (98%)</div>
          </div>

          <button id="coPayBtn" class="mp-buy" style="width:100%;">BAYAR SEKARANG (${fmtRM(subtotal)})</button>
        </div>
      `;

      $('coPayBtn').addEventListener('click', async () => {
        const btn = $('coPayBtn');
        if (btn.disabled) return;

        const nama = $('coNama').value.trim();
        const tel = $('coTel').value.trim();
        const alamat = $('coAlamat').value.trim();
        const poskod = $('coPoskod').value.trim();
        if (!nama || !tel || !alamat || !poskod) {
          snack('Sila isi alamat penerima yang lengkap', true);
          return;
        }

        btn.disabled = true;
        btn.innerHTML = '<div class="mp-spin" style="margin:0 auto; width:18px; height:18px; border-color:rgba(255,255,255,.3); border-top-color:#fff;"></div>';

        try {
          const orderData = {
            itemDocId: docId,
            itemName: item.itemName || '',
            category: item.category || '',
            pricePerUnit: price,
            quantity,
            totalPrice: subtotal,
            productPrice: subtotal,
            shippingCost: 0,
            shippingService: '',
            commission,
            sellerPayout,
            sellerOwnerID: item.ownerID || '',
            sellerShopID: item.shopID || '',
            sellerShopName: item.shopName || '',
            buyerOwnerID: ownerID,
            buyerShopID: shopID,
            buyerShopName: shopName,
            receiverName: nama,
            receiverPhone: tel,
            receiverAlamat: alamat,
            receiverBandar: $('coBandar').value.trim(),
            receiverPoskod: poskod,
            receiverNegeri: $('coNegeri').value.trim(),
            status: 'pending_payment',
            paymentStatus: 'unpaid',
            billplzBillId: '',
            billplzUrl: '',
            trackingNumber: '',
            courierName: '',
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          };
          const orderRef = await fs.collection('marketplace_orders').add(orderData);

          // Testing mode — mark as paid directly (ToyyibPay gateway perlu Cloud Function proxy)
          await orderRef.update({
            status: 'paid',
            paymentStatus: 'paid',
            paidAt: firebase.firestore.FieldValue.serverTimestamp(),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          });

          // Notify seller
          if (item.ownerID) {
            await fs.collection('marketplace_notifications').add({
              targetOwnerID: item.ownerID,
              targetShopID: item.shopID || '',
              type: 'new_order',
              title: 'Pesanan Baru!',
              message: `${shopName} telah membuat pesanan ${item.itemName || ''} x${quantity}.`,
              orderDocId: orderRef.id,
              read: false,
              createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            });
          }

          bg.classList.remove('show');
          snack('Pesanan berjaya dibuat!');
          // Close product detail modal too
          document.getElementById('mpPdBg')?.classList.remove('show');
          // Switch to Pesanan tab
          const pesananTab = document.querySelector('#mpTabs .mp-tab[data-pane="pesanan"]');
          if (pesananTab) pesananTab.click();
        } catch (e) {
          console.error('checkout error', e);
          snack('Ralat: ' + (e.message || e), true);
          btn.disabled = false;
          btn.textContent = `BAYAR SEKARANG (${fmtRM(subtotal)})`;
        }
      });
    };

    // ══════════════════════════════════════════════════════════════════
    // PESANAN SAYA (mirror pesanan_saya_screen.dart)
    // ══════════════════════════════════════════════════════════════════

    const paneP = $('panePesanan');
    paneP.innerHTML = `
      <div class="mp-chips" id="mpPsChips"></div>
      <div id="mpPsHost"><div class="mp-loading"><div class="mp-spin"></div></div></div>
    `;

    let psFilter = 'all';
    let psDocs = [];
    let psUnsub = null;

    function renderPsChips() {
      $('mpPsChips').innerHTML = Object.entries(FILTERS).map(([k, v]) =>
        `<button class="mp-chip ${k === psFilter ? 'active' : ''}" data-f="${esc(k)}">${esc(v)}</button>`
      ).join('');
      $('mpPsChips').querySelectorAll('.mp-chip').forEach(el => {
        el.addEventListener('click', () => {
          psFilter = el.dataset.f; renderPsChips(); renderPsList();
        });
      });
    }

    function psOrderCard(id, d) {
      const status = d.status || '';
      const col = STATUS_COLOR[status] || '#94A3B8';
      const label = STATUS_LABEL[status] || status.toUpperCase();
      const qty = Number(d.quantity) || 1;
      const unit = Number(d.pricePerUnit ?? d.unitPrice) || 0;
      const total = Number(d.totalPrice) || 0;
      const trk = d.trackingNumber || '';

      let actionBtn = '';
      if (status === 'paid' || status === 'shipped') {
        actionBtn = `<button class="mp-ps-recv" data-recv="${esc(id)}"><i class="fas fa-circle-check"></i> TERIMA BARANG</button>`;
      }

      return `
        <div class="mp-ps-card" data-open="${esc(id)}">
          <div class="mp-ps-row1">
            <span class="mp-ps-badge" style="background:${col}1f; color:${col};">${esc(label)}</span>
            <span class="mp-ps-date">${fmtDate(d.createdAt)}</span>
          </div>
          <div class="mp-ps-name">${esc((d.itemName || '-').toUpperCase())}</div>
          <div class="mp-ps-shop"><i class="fas fa-shop"></i> ${esc(d.sellerShopName || '-')}</div>
          <div class="mp-ps-totals">
            <span>${qty} × ${fmtRM(unit)}</span>
            <b>${fmtRM(total)}</b>
          </div>
          ${status === 'shipped' && trk ? `<div class="mp-ps-trk"><i class="fas fa-truck"></i> ${esc(trk)}</div>` : ''}
          ${actionBtn}
        </div>`;
    }

    function renderPsList() {
      const host = $('mpPsHost');
      const filtered = psFilter === 'all' ? psDocs : psDocs.filter(x => (x.data.status || '') === psFilter);
      if (!filtered.length) {
        host.innerHTML = `
          <div class="mp-empty">
            <i class="fas fa-box-open"></i>
            <p>Tiada pesanan</p>
            <small>Pesanan anda akan dipaparkan di sini</small>
          </div>`;
        return;
      }
      host.innerHTML = filtered.map(x => psOrderCard(x.id, x.data)).join('');
      host.querySelectorAll('.mp-ps-card').forEach(el => {
        el.addEventListener('click', (e) => {
          // Ignore if click was on action button
          if (e.target.closest('.mp-ps-recv')) return;
          openOrderDetail(el.dataset.open);
        });
      });
      host.querySelectorAll('.mp-ps-recv').forEach(el => {
        el.addEventListener('click', async (e) => {
          e.stopPropagation();
          const id = el.dataset.recv;
          if (!confirm('Adakah anda pasti telah menerima barang ini?\nTindakan ini tidak boleh dibatalkan.')) return;
          try {
            await markOrderCompleted(id);
            snack('Pesanan ditandakan sebagai selesai!');
          } catch (err) {
            snack('Ralat: ' + (err.message || err), true);
          }
        });
      });
    }

    async function markOrderCompleted(orderId) {
      await fs.collection('marketplace_orders').doc(orderId).update({
        status: 'completed',
        completedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      // Increment soldCount pada produk
      const ord = await fs.collection('marketplace_orders').doc(orderId).get();
      const itemDocId = ord.data()?.itemDocId;
      if (itemDocId) {
        await fs.collection('marketplace_global').doc(itemDocId).update({
          soldCount: firebase.firestore.FieldValue.increment(1),
        });
      }
    }

    async function cancelOrder(orderId) {
      await fs.collection('marketplace_orders').doc(orderId).update({
        status: 'cancelled',
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }

    function subscribePs() {
      if (psUnsub) { try { psUnsub(); } catch (_) {} }
      psUnsub = fs.collection('marketplace_orders')
        .where('buyerOwnerID', '==', ownerID)
        .orderBy('createdAt', 'desc')
        .onSnapshot(
          (snap) => {
            psDocs = snap.docs.map(d => ({ id: d.id, data: d.data() || {} }));
            renderPsList();
          },
          (err) => {
            console.error('pesanan stream error', err);
            $('mpPsHost').innerHTML = `
              <div class="mp-empty"><i class="fas fa-triangle-exclamation" style="color:var(--mp-red);"></i>
              <p>Ralat</p><small>${esc(err.message || '')}</small></div>`;
          },
        );
    }

    renderPsChips();
    subscribePs();

    // ══════════════════════════════════════════════════════════════════
    // ORDER DETAIL modal (mirror order_detail_screen.dart)
    // ══════════════════════════════════════════════════════════════════

    // Inject order detail modal into DOM
    const odBg = document.createElement('div');
    odBg.className = 'mp-modal-bg'; odBg.id = 'mpOdBg';
    odBg.innerHTML = `
      <div class="mp-modal">
        <div class="mp-modal__head">
          <button class="mp-modal__close" id="mpOdBack"><i class="fas fa-arrow-left"></i></button>
          <h3>Butiran Pesanan</h3>
        </div>
        <div id="mpOdContent"></div>
      </div>`;
    document.body.appendChild(odBg);

    let odUnsub = null;
    function closeOd() {
      odBg.classList.remove('show');
      if (odUnsub) { try { odUnsub(); } catch (_) {} odUnsub = null; }
    }
    $('mpOdBack').addEventListener('click', closeOd);
    odBg.addEventListener('click', (e) => { if (e.target === odBg) closeOd(); });

    function stepperHtml(status, ts) {
      const steps = [
        { key: 'pending_payment', label: 'Dibuat', ts: ts.createdAt, icon: 'fa-file-invoice' },
        { key: 'paid', label: 'Dibayar', ts: ts.paidAt, icon: 'fa-money-check-dollar' },
        { key: 'shipped', label: 'Dihantar', ts: ts.shippedAt, icon: 'fa-truck' },
        { key: 'completed', label: 'Selesai', ts: ts.completedAt, icon: 'fa-circle-check' },
      ];
      const order = ['pending_payment', 'paid', 'shipped', 'completed'];
      const curIdx = status === 'cancelled' ? -1 : order.indexOf(status);
      if (status === 'cancelled') {
        return `<div class="mp-od-cancel"><i class="fas fa-ban"></i> Pesanan Dibatalkan</div>`;
      }
      return `
        <div class="mp-od-step">
          ${steps.map((s, i) => {
            const done = i <= curIdx;
            return `
              <div class="mp-od-step__item ${done ? 'done' : ''}">
                <div class="mp-od-step__dot"><i class="fas ${s.icon}"></i></div>
                <div class="mp-od-step__lbl">${s.label}</div>
                <div class="mp-od-step__ts">${s.ts ? fmtDate(s.ts) : '—'}</div>
              </div>
              ${i < steps.length - 1 ? `<div class="mp-od-step__line ${i < curIdx ? 'done' : ''}"></div>` : ''}
            `;
          }).join('')}
        </div>`;
    }

    function renderOd(id, o) {
      const isBuyer = (o.buyerOwnerID || '') === ownerID;
      const status = o.status || '';
      const trk = o.trackingNumber || '';

      let actionBar = '';
      if ((status === 'paid' || status === 'shipped') && isBuyer) {
        actionBar = `<button class="mp-buy" id="odRecv"><i class="fas fa-circle-check"></i> TERIMA BARANG</button>`;
      } else if (status === 'pending_payment') {
        actionBar = `<button class="mp-buy" id="odCancel" style="background:var(--mp-red);"><i class="fas fa-ban"></i> BATAL PESANAN</button>`;
      }

      $('mpOdContent').innerHTML = `
        <div style="padding:16px; display:flex; flex-direction:column; gap:14px;">
          ${stepperHtml(status, o)}

          <div class="mp-co-card">
            <div class="mp-co-title"><i class="fas fa-file-lines"></i> Maklumat Pesanan</div>
            <div class="mp-od-row"><span>ID Pesanan</span><b>${esc(id.length > 10 ? id.slice(0,5)+'...'+id.slice(-5) : id)}</b></div>
            <div class="mp-od-row"><span>Tarikh Dibuat</span><b>${fmtDateLong(o.createdAt)}</b></div>
            ${o.paidAt ? `<div class="mp-od-row"><span>Tarikh Dibayar</span><b>${fmtDateLong(o.paidAt)}</b></div>` : ''}
            ${o.shippedAt ? `<div class="mp-od-row"><span>Tarikh Dihantar</span><b>${fmtDateLong(o.shippedAt)}</b></div>` : ''}
            ${o.completedAt ? `<div class="mp-od-row"><span>Tarikh Selesai</span><b>${fmtDateLong(o.completedAt)}</b></div>` : ''}
          </div>

          <div class="mp-co-card">
            <div class="mp-co-title"><i class="fas fa-box-open"></i> Item Pesanan</div>
            <div class="mp-od-row"><span>Nama Item</span><b>${esc(o.itemName || '-')}</b></div>
            <div class="mp-od-row"><span>Kategori</span><b>${esc(o.category || '-')}</b></div>
            <div class="mp-od-row"><span>Kuantiti × Harga</span><b>${o.quantity || 0} × ${fmtRM(o.pricePerUnit)}</b></div>
            <hr style="border:none; border-top:1px solid var(--mp-border); margin:8px 0;">
            <div class="mp-od-row"><span>Jumlah</span><b style="font-size:15px;">${fmtRM(o.totalPrice)}</b></div>
          </div>

          <div class="mp-co-card">
            <div class="mp-co-title"><i class="fas fa-money-bill"></i> Maklumat Bayaran</div>
            <div class="mp-od-row"><span>Jumlah Bayaran</span><b>${fmtRM(o.totalPrice)}</b></div>
            <div class="mp-od-row"><span>Komisyen (2%)</span><b>${fmtRM(o.commission)}</b></div>
            <hr style="border:none; border-top:1px solid var(--mp-border); margin:8px 0;">
            <div class="mp-od-row"><span>Penjual Terima</span><b style="color:var(--mp-purple);">${fmtRM(o.sellerPayout)}</b></div>
          </div>

          <div class="mp-co-card">
            <div class="mp-co-title"><i class="fas fa-user-group"></i> Pihak Terlibat</div>
            <div class="mp-od-row"><span>Penjual</span><b>${esc(o.sellerShopName || '-')}</b></div>
            <div class="mp-od-row"><span>Pembeli</span><b>${esc(o.buyerShopName || '-')}</b></div>
          </div>

          ${trk ? `
          <div class="mp-co-card" style="background:#EFF6FF; border-color:#BFDBFE;">
            <div class="mp-co-title" style="color:#2563EB;"><i class="fas fa-truck"></i> Maklumat Penghantaran</div>
            <div class="mp-od-row"><span>Kurier</span><b>${esc(o.courierName || '-')}</b></div>
            <div class="mp-od-row">
              <span>No. Penjejakan</span>
              <span style="display:flex; align-items:center; gap:6px;">
                <b style="color:#2563EB;">${esc(trk)}</b>
                <button id="odCopyTrk" style="background:none; border:none; cursor:pointer; color:#2563EB;"><i class="fas fa-copy"></i></button>
              </span>
            </div>
          </div>` : ''}

          ${actionBar ? `<div style="padding:4px 0;">${actionBar}</div>` : ''}
        </div>
      `;

      const copyBtn = $('odCopyTrk');
      if (copyBtn) copyBtn.addEventListener('click', () => {
        navigator.clipboard?.writeText(trk).then(() => snack('No. penjejakan disalin.'));
      });
      const recvBtn = $('odRecv');
      if (recvBtn) recvBtn.addEventListener('click', async () => {
        if (!confirm('Adakah anda pasti telah menerima barang ini?')) return;
        try { await markOrderCompleted(id); snack('Pesanan disahkan selesai.'); closeOd(); }
        catch (err) { snack('Ralat: ' + (err.message || err), true); }
      });
      const cancelBtn = $('odCancel');
      if (cancelBtn) cancelBtn.addEventListener('click', async () => {
        if (!confirm('Adakah anda pasti ingin membatalkan pesanan ini?')) return;
        try { await cancelOrder(id); snack('Pesanan dibatalkan.'); closeOd(); }
        catch (err) { snack('Ralat: ' + (err.message || err), true); }
      });
    }

    function openOrderDetail(id) {
      odBg.classList.add('show');
      $('mpOdContent').innerHTML = '<div class="mp-loading" style="padding:40px;"><div class="mp-spin"></div></div>';
      if (odUnsub) { try { odUnsub(); } catch (_) {} }
      odUnsub = fs.collection('marketplace_orders').doc(id).onSnapshot(
        (doc) => {
          if (!doc.exists) {
            $('mpOdContent').innerHTML = '<div class="mp-empty"><i class="fas fa-circle-question"></i><p>Pesanan tidak dijumpai</p></div>';
            return;
          }
          renderOd(doc.id, doc.data() || {});
        },
        (err) => {
          $('mpOdContent').innerHTML = `<div class="mp-empty"><i class="fas fa-triangle-exclamation"></i><p>Ralat: ${esc(err.message || '')}</p></div>`;
        },
      );
    }

    // Expose for other phases
    window.__mp.openOrderDetail = openOrderDetail;
    window.__mp.markOrderCompleted = markOrderCompleted;
    window.__mp.cancelOrder = cancelOrder;
  }
})();
