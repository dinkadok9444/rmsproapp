/* Port dari lib/screens/modules/collab_screen.dart */
(function () {
  'use strict';
  if (!document.getElementById('clList')) return;

  let ownerID = 'admin', shopID = 'MAIN';
  let sentArr = [];
  let repairs = [];
  let savedDealers = [];
  let filterStatus = 'SEMUA';
  let showArchive = false;
  let foundTicket = null, foundDealer = null;
  let canSend = false;

  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0]; shopID = (p[1] || '').toUpperCase();
  }

  const $ = id => document.getElementById(id);
  const list = $('clList'), empty = $('clEmpty');
  const sendModal = $('clSendModal'), infoModal = $('clInfoModal');

  // Load saved dealers from shops_<owner>/<shop>.savedDealers
  db.collection('shops_' + ownerID).doc(shopID).get().then(doc => {
    if (!doc.exists) return;
    const raw = (doc.data() || {}).savedDealers;
    if (Array.isArray(raw)) savedDealers = raw.slice();
  }).catch(() => {});

  // Listeners
  db.collection('collab_global_network').onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.key = d.id;
      if (v.sender === shopID) arr.push(v);
    });
    arr.sort((a, b) => Number(b.timestamp || 0) - Number(a.timestamp || 0));
    sentArr = arr;
    render();
  }, err => console.warn('collab:', err));

  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => arr.push(Object.assign({ id: d.id }, d.data())));
    repairs = arr;
  }, err => console.warn('repairs:', err));

  function statusColor(s) {
    const u = String(s).toUpperCase();
    if (u === 'COMPLETE' || u === 'COMPLETED' || u === 'DELIVERED') return 'green';
    if (u === 'REJECT' || u === 'RETURN REJECT') return 'red';
    if (u === 'TERIMA' || u === 'IN PROGRESS') return 'blue';
    return 'yellow';
  }

  function filtered() {
    if (showArchive) return sentArr.filter(d => d.archived === true);
    const active = sentArr.filter(d => d.archived !== true);
    if (filterStatus === 'SEMUA') return active;
    return active.filter(d => String(d.status || 'PENDING') === filterStatus);
  }

  function render() {
    $('clTitle').innerHTML = showArchive
      ? '<i class="fas fa-box-archive"></i> ARKIB <span class="collab-count" id="clCount"></span>'
      : '<i class="fas fa-paper-plane"></i> OUTBOX <span class="collab-count" id="clCount"></span>';
    $('clArchiveBtn').innerHTML = showArchive
      ? '<i class="fas fa-arrow-left"></i> OUTBOX'
      : '<i class="fas fa-box-archive"></i> ARKIB';
    $('clFilterRow').classList.toggle('hidden', showArchive);

    const arr = filtered();
    const countEl = document.querySelector('.collab-count');
    if (countEl) countEl.textContent = arr.length;

    if (!arr.length) {
      list.innerHTML = '';
      empty.querySelector('.lbl').textContent = showArchive ? 'Tiada arkib.' : 'Tiada rekod dihantar.';
      empty.querySelector('.sub').textContent = showArchive ? '' : 'Tekan "Hantar Tugasan" untuk mula.';
      empty.classList.remove('hidden');
      return;
    }
    empty.classList.add('hidden');
    list.innerHTML = arr.map(d => card(d)).join('');
  }

  function card(d) {
    const col = statusColor(d.status || 'PENDING');
    const status = d.status || 'PENDING';
    const rx = d.receiver || '-';
    const arch = d.archived === true;
    const actionBtn = arch
      ? `<button type="button" class="icon-btn" data-restore="${escAttr(d.key)}" title="Pulih"><i class="fas fa-rotate-left"></i></button>`
      : `<button type="button" class="icon-btn" data-archive="${escAttr(d.key)}" title="Arkib"><i class="fas fa-box-archive"></i></button>`;
    return `
      <article class="lost-card collab-card c-${col}">
        <div class="lost-card__top">
          <span class="collab-rx"><i class="fas fa-store"></i> ${escHtml(rx)}</span>
          <span class="rd-status c-${col}">${escHtml(status)}</span>
        </div>
        <div class="collab-cust">${escHtml((d.namaCust || 'TIADA NAMA').toUpperCase())}</div>
        <div class="collab-row">
          <strong>#${escHtml(d.siri || '-')}</strong>
          <span class="collab-meta">${fmtDate(d.timestamp)} | ${escHtml(d.model || '-')}</span>
        </div>
        <div class="collab-update">Kemaskini: ${fmtDate(d.timestamp_update)}</div>
        <div class="collab-actions">
          <button type="button" class="btn-view" data-info="${escAttr(d.key)}"><i class="fas fa-eye"></i> LIHAT STATUS</button>
          ${actionBtn}
        </div>
      </article>
    `;
  }

  // Events
  $('clStatus').addEventListener('change', e => { filterStatus = e.target.value; render(); });
  $('clArchiveBtn').addEventListener('click', () => { showArchive = !showArchive; render(); });
  $('clNewBtn').addEventListener('click', openSend);
  $('clSendClose').addEventListener('click', () => sendModal.classList.remove('is-open'));
  sendModal.addEventListener('click', e => { if (e.target === sendModal) sendModal.classList.remove('is-open'); });
  $('clSiriBtn').addEventListener('click', searchTicket);
  $('clDealerBtn').addEventListener('click', () => checkDealer($('clDealer').value.trim().toUpperCase()));
  $('clSubmit').addEventListener('click', submitTask);
  $('clInfoClose').addEventListener('click', () => infoModal.classList.remove('is-open'));
  infoModal.addEventListener('click', e => { if (e.target === infoModal) infoModal.classList.remove('is-open'); });

  list.addEventListener('click', async e => {
    const info = e.target.closest('[data-info]');
    const arch = e.target.closest('[data-archive]');
    const rest = e.target.closest('[data-restore]');
    if (info) {
      const d = sentArr.find(x => x.key === info.dataset.info);
      if (d) openInfo(d);
    } else if (arch) {
      try {
        await db.collection('collab_global_network').doc(arch.dataset.archive).update({ archived: true });
        toast('Diarkib');
      } catch (e) { toast('Ralat: ' + e.message, true); }
    } else if (rest) {
      try {
        await db.collection('collab_global_network').doc(rest.dataset.restore).update({ archived: false });
        toast('Dipulihkan');
      } catch (e) { toast('Ralat: ' + e.message, true); }
    }
  });

  // Saved chips clicks
  $('clSavedChips').addEventListener('click', async e => {
    const chip = e.target.closest('[data-code]');
    if (!chip) return;
    const code = chip.dataset.code;
    if (e.shiftKey) {
      savedDealers = savedDealers.filter(d => d.code !== code);
      try {
        await db.collection('shops_' + ownerID).doc(shopID).set({ savedDealers }, { merge: true });
        renderSaved();
        toast('Dibuang dari senarai');
      } catch (err) { toast('Ralat: ' + err.message, true); }
    } else {
      $('clDealer').value = code;
      checkDealer(code);
    }
  });

  function openSend() {
    foundTicket = null; foundDealer = null; canSend = false;
    ['clSiri', 'clDealer', 'clKurier', 'clTrack', 'clCatatan'].forEach(id => $(id).value = '');
    $('clTicket').classList.add('hidden');
    $('clDealerInfo').classList.add('hidden');
    $('clDealerStatus').textContent = '';
    renderSaved();
    sendModal.classList.add('is-open');
  }

  function renderSaved() {
    const box = $('clSaved'), chips = $('clSavedChips');
    if (!savedDealers.length) { box.classList.add('hidden'); return; }
    box.classList.remove('hidden');
    chips.innerHTML = savedDealers.map(d => {
      const nm = d.name ? ` (${escHtml(d.name)})` : '';
      return `<button type="button" class="cl-chip" data-code="${escAttr(d.code || '')}"><i class="fas fa-store"></i> ${escHtml(d.code || '-')}${nm}</button>`;
    }).join('');
  }

  function searchTicket() {
    const v = $('clSiri').value.trim().toUpperCase();
    if (!v) return;
    const found = repairs.find(r => String(r.siri || '').toUpperCase() === v);
    if (!found) {
      foundTicket = null;
      $('clTicket').classList.add('hidden');
      return toast(`[${v}] tidak dijumpai`, true);
    }
    foundTicket = found;
    $('clTkNama').textContent = found.nama || '-';
    $('clTkModel').textContent = found.model || '-';
    $('clTkTel').textContent = found.tel || '-';
    $('clTkKero').textContent = found.kerosakan || '-';
    $('clTkPass').textContent = found.password || 'TIADA';
    $('clTicket').classList.remove('hidden');
  }

  async function checkDealer(code) {
    if (!code) return;
    foundDealer = null; canSend = false;
    $('clDealerInfo').classList.add('hidden');
    $('clDealerStatus').textContent = 'Sedang semak...';
    $('clDealerStatus').style.color = 'var(--text-muted)';
    try {
      const snap = await db.collection('saas_dealers').get();
      let dealer = null;
      snap.forEach(doc => {
        if (dealer) return;
        const d = doc.data();
        if (String(d.shopID || '').toUpperCase() === code) dealer = d;
      });
      if (!dealer) {
        $('clDealerStatus').textContent = 'Kod dealer tidak dijumpai';
        $('clDealerStatus').style.color = 'var(--red)';
        return;
      }
      const now = Date.now();
      const isPro = dealer.proMode === true && Number(dealer.proModeExpire || 0) > now;
      foundDealer = dealer;
      canSend = isPro;
      $('clDealerStatus').textContent = isPro ? '✓ Pro Mode aktif — boleh hantar' : '✗ Dealer tiada Pro Mode aktif';
      $('clDealerStatus').style.color = isPro ? 'var(--green)' : 'var(--red)';
      $('clDlKedai').textContent = dealer.namaKedai || '-';
      $('clDlTel').textContent = dealer.phone || '-';
      $('clDealerInfo').classList.remove('hidden');
    } catch (e) {
      $('clDealerStatus').textContent = 'Ralat semak: ' + e.message;
      $('clDealerStatus').style.color = 'var(--red)';
    }
  }

  async function submitTask() {
    if (!foundTicket) return toast('Sila cari siri dahulu', true);
    if (!canSend || !foundDealer) return toast('Sila semak kod dealer', true);
    const siri = String(foundTicket.siri || '');
    if (!siri) return toast('Tiket tiada siri', true);
    const rx = $('clDealer').value.trim().toUpperCase();
    if (rx === shopID) return toast('Tak boleh hantar ke kedai sendiri', true);

    let shopName = shopID;
    try {
      const sDoc = await db.collection('shops_' + ownerID).doc(shopID).get();
      if (sDoc.exists) shopName = (sDoc.data() || {}).shopName || shopID;
    } catch (_) {}

    const now = Date.now();
    const payload = {
      siri,
      sender: shopID, sender_name: shopName, receiver: rx,
      kurier: $('clKurier').value.trim(),
      hantar: $('clTrack').value.trim(),
      terima: '',
      catatan: $('clCatatan').value.trim(),
      namaCust: foundTicket.nama || '',
      model: foundTicket.model || '',
      kerosakan: foundTicket.kerosakan || '',
      password: foundTicket.password || '',
      catatan_pro: '',
      kurier_return: '',
      harga: 0, kos: 0,
      payment_status: 'UNPAID',
      cara_bayaran: 'CASH',
      status: 'PENDING',
      timestamp: now,
      timestamp_update: now,
    };

    try {
      await db.collection('collab_global_network').doc(siri).set(payload);
      // Auto-save dealer to book if new
      if (!savedDealers.some(d => d.code === rx)) {
        savedDealers.push({ code: rx, name: foundDealer.namaKedai || '', phone: foundDealer.phone || '', timestamp: now });
        await db.collection('shops_' + ownerID).doc(shopID).set({ savedDealers }, { merge: true });
      }
      toast(`Tugasan [${siri}] dihantar ke [${rx}]`);
      sendModal.classList.remove('is-open');
    } catch (e) { toast('Gagal hantar: ' + e.message, true); }
  }

  function openInfo(d) {
    const status = d.status || 'PENDING';
    const col = statusColor(status);
    const el = $('clInfoStatus');
    el.textContent = status;
    el.className = 'cl-info-status c-' + col;
    $('clInfoNota').textContent = d.catatan_pro || 'Tiada nota';
    $('clInfoKurier').textContent = d.kurier_return || 'Tiada';
    $('clInfoTrack').textContent = d.terima || 'Tiada';
    infoModal.classList.add('is-open');
  }

  function fmtDate(ts) {
    if (typeof ts !== 'number') return '-';
    const d = new Date(ts);
    const p = n => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${String(d.getFullYear()).slice(-2)}`;
  }
  function toast(msg, isErr) {
    const t = $('clToast');
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.hidden = true, 2500);
  }
  function escHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function escAttr(s) { return escHtml(s); }

  render();
})();
