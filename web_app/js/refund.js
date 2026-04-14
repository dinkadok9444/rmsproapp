/* Port dari lib/screens/modules/refund_screen.dart */
(function () {
  'use strict';
  if (!document.getElementById('rdList')) return;

  let ownerID = 'admin', shopID = 'MAIN';
  let refunds = [];
  let repairs = [];
  let adminPass = '';
  let sortOrder = 'ZA';
  let searchText = '';
  let foundRepair = null;
  let pendingApproveId = null;

  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0]; shopID = (p[1] || '').toUpperCase();
  }

  const $ = id => document.getElementById(id);
  const list = $('rdList'), empty = $('rdEmpty');
  const formModal = $('rdFormModal'), approveModal = $('rdApproveModal');

  // Load admin pass
  db.collection('shops_' + ownerID).doc(shopID).get()
    .then(doc => { if (doc.exists) adminPass = (doc.data() || {}).svPass || ''; })
    .catch(() => {});

  // Listeners
  db.collection('refunds_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.key = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    arr.sort((a, b) => Number(b.timestamp || 0) - Number(a.timestamp || 0));
    refunds = arr;
    render();
  }, err => console.warn('refunds:', err));

  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => arr.push(Object.assign({ id: d.id }, d.data())));
    repairs = arr;
  }, err => console.warn('repairs:', err));

  // Filter/sort
  function filtered() {
    let arr = refunds.slice();
    const q = searchText.toUpperCase().trim();
    if (q) {
      arr = arr.filter(d =>
        String(d.siri || '').toUpperCase().includes(q) ||
        String(d.reason || '').toUpperCase().includes(q) ||
        String(d.namaCust || '').toUpperCase().includes(q)
      );
    }
    arr.sort((a, b) => {
      const ta = Number(a.timestamp || 0), tb = Number(b.timestamp || 0);
      return sortOrder === 'AZ' ? ta - tb : tb - ta;
    });
    return arr;
  }

  function statusStyle(s) {
    const u = String(s).toUpperCase();
    if (u === 'APPROVED' || u === 'COMPLETED') return { color: 'green', icon: 'fa-circle-check' };
    if (u === 'REJECTED') return { color: 'red', icon: 'fa-circle-xmark' };
    return { color: 'yellow', icon: 'fa-clock' };
  }

  function render() {
    const arr = filtered();
    if (!refunds.length) {
      list.innerHTML = '';
      empty.querySelector('.lbl').textContent = 'Tiada permohonan refund.';
      empty.classList.remove('hidden');
      return;
    }
    if (!arr.length) {
      list.innerHTML = '';
      empty.querySelector('.lbl').textContent = 'Tiada padanan.';
      empty.classList.remove('hidden');
      return;
    }
    empty.classList.add('hidden');

    list.innerHTML = arr.map(r => {
      const status = String(r.status || 'PENDING').toUpperCase();
      const s = statusStyle(status);
      const amt = Number(r.amount || 0).toFixed(2);
      const asal = Number(r.hargaAsal || 0).toFixed(2);
      const approveBtn = status === 'PENDING'
        ? `<button type="button" class="rd-approve" data-approve="${escapeAttr(r.key)}"><i class="fas fa-check"></i> APPROVE</button>` : '';
      return `
        <article class="lost-card rd-card c-${s.color}">
          <div class="lost-card__top">
            <div class="rd-siri">#${escapeHtml(r.siri || '-')}</div>
            <div class="rd-status c-${s.color}"><i class="fas ${s.icon}"></i> ${status}</div>
          </div>
          <div class="rd-cust">${escapeHtml(r.namaCust || '-')}</div>
          <div class="rd-info">${escapeHtml(r.model || '-')} &nbsp;•&nbsp; ${escapeHtml(r.kerosakan || '-')}</div>
          <div class="rd-amounts">
            <div>
              <div class="rd-asal">Asal: RM ${asal}</div>
              <div class="rd-date">${fmtDate(r.timestamp)}</div>
            </div>
            <div class="rd-amt">RM ${amt}</div>
          </div>
          ${approveBtn}
        </article>
      `;
    }).join('');
  }

  // Events
  $('rdSearch').addEventListener('input', e => { searchText = e.target.value; render(); });
  $('rdSort').addEventListener('change', e => { sortOrder = e.target.value; render(); });
  $('rdNewBtn').addEventListener('click', openForm);
  $('rdFormClose').addEventListener('click', () => formModal.classList.remove('is-open'));
  formModal.addEventListener('click', e => { if (e.target === formModal) formModal.classList.remove('is-open'); });
  $('rdSearchBtn').addEventListener('click', doSearchSiri);
  $('rdSubmit').addEventListener('click', submitForm);

  list.addEventListener('click', e => {
    const b = e.target.closest('[data-approve]');
    if (!b) return;
    if (!adminPass) return toast('Sila set kata laluan admin di Tetapan', true);
    pendingApproveId = b.dataset.approve;
    $('rdPass').value = '';
    $('rdPassErr').classList.add('hidden');
    approveModal.classList.add('is-open');
  });
  $('rdApproveCancel').addEventListener('click', () => { pendingApproveId = null; approveModal.classList.remove('is-open'); });
  approveModal.addEventListener('click', e => { if (e.target === approveModal) approveModal.classList.remove('is-open'); });
  $('rdApproveOk').addEventListener('click', async () => {
    if ($('rdPass').value.trim() !== adminPass) {
      $('rdPassErr').classList.remove('hidden');
      return;
    }
    try {
      await db.collection('refunds_' + ownerID).doc(pendingApproveId).update({ status: 'COMPLETED' });
      toast('Refund diluluskan');
    } catch (e) { toast('Ralat: ' + e.message, true); }
    pendingApproveId = null;
    approveModal.classList.remove('is-open');
  });

  function openForm() {
    foundRepair = null;
    $('rdFound').classList.add('hidden');
    ['rdSiri', 'rdAmount', 'rdReason', 'rdAccName', 'rdBankName', 'rdAccNo'].forEach(id => $(id).value = '');
    $('rdMethod').value = 'TRANSFER';
    $('rdSpeed').value = 'SEGERA';
    formModal.classList.add('is-open');
  }

  function doSearchSiri() {
    const val = $('rdSiri').value.trim().toUpperCase();
    if (!val) return;
    const found = repairs.find(r => String(r.siri || '').toUpperCase() === val);
    if (!found) {
      foundRepair = null;
      $('rdFound').classList.add('hidden');
      return toast(`Siri [${val}] tidak dijumpai`, true);
    }
    foundRepair = found;
    $('rdFoundNama').textContent = found.nama || '-';
    $('rdFoundHarga').textContent = String(found.total ?? found.harga ?? 0);
    $('rdFoundModel').textContent = found.model || '-';
    $('rdFoundKero').textContent = found.kerosakan || '-';
    $('rdFound').classList.remove('hidden');
  }

  async function submitForm() {
    if (!foundRepair) return toast('Sila cari siri dahulu', true);
    const amount = parseFloat($('rdAmount').value);
    const reason = $('rdReason').value.trim();
    if (isNaN(amount) || !reason) return toast('Sila isi amaun dan sebab', true);
    const data = {
      shopID,
      siri: $('rdSiri').value.trim().toUpperCase(),
      namaCust: foundRepair.nama || '-',
      model: foundRepair.model || '-',
      kerosakan: foundRepair.kerosakan || '-',
      hargaAsal: Number(foundRepair.total ?? foundRepair.harga ?? 0),
      amount,
      reason,
      method: $('rdMethod').value,
      speed: $('rdSpeed').value,
      accName: $('rdAccName').value.trim(),
      bankName: $('rdBankName').value.trim(),
      accNo: $('rdAccNo').value.trim(),
      status: 'PENDING',
      timestamp: Date.now(),
    };
    try {
      await db.collection('refunds_' + ownerID).add(data);
      toast('Permohonan refund dihantar');
      formModal.classList.remove('is-open');
    } catch (e) { toast('Ralat: ' + e.message, true); }
  }

  function fmtDate(ts) {
    if (typeof ts !== 'number') return '-';
    const d = new Date(ts);
    const p = n => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${String(d.getFullYear()).slice(-2)}`;
  }
  function toast(msg, isErr) {
    const t = $('rdToast');
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.hidden = true, 2200);
  }
  function escapeHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function escapeAttr(s) { return escapeHtml(s); }

  render();
})();
