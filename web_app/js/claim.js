/* Port dari lib/screens/modules/claim_warranty_screen.dart (MVP — tanpa PDF/print/foto) */
(function () {
  'use strict';
  if (!document.getElementById('cwList')) return;

  const STATUSES = [
    'Claim Waiting Approval', 'Claim Approve', 'Claim In Progress',
    'Claim Done', 'Claim Ready to Pickup', 'Claim Complete',
  ];

  let ownerID = 'admin', shopID = 'MAIN';
  let claims = [];
  let repairs = [];
  let staffList = [];
  let filterStatus = 'ALL';
  let searchText = '';
  let repairQuery = '';
  let editing = null;
  let pendingDeleteId = null;

  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0].toLowerCase();
    shopID = (p[1] || '').toUpperCase();
  }

  const $ = id => document.getElementById(id);
  const list = $('cwList'), empty = $('cwEmpty');
  const searchModal = $('cwSearchModal'), updateModal = $('cwUpdateModal'), delModal = $('cwDelModal');

  // Listeners
  db.collection('claims_' + ownerID).orderBy('timestamp', 'desc').onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.id = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    claims = arr;
    render();
  }, err => console.warn('claims:', err));

  db.collection('repairs_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data();
      if (String(v.shopID || '').toUpperCase() !== shopID) return;
      const nama = String(v.nama || '').toUpperCase();
      const jenis = String(v.jenis_servis || '').toUpperCase();
      if (nama === 'JUALAN PANTAS' || jenis === 'JUALAN') return;
      arr.push(v);
    });
    arr.sort((a, b) => Number(b.timestamp || 0) - Number(a.timestamp || 0));
    repairs = arr;
  }, err => console.warn('repairs:', err));

  // Load staff list from shops
  db.collection('shops_' + ownerID).doc(shopID).get().then(doc => {
    if (!doc.exists) return;
    const raw = (doc.data() || {}).staffList;
    if (Array.isArray(raw)) {
      staffList = raw.map(s => typeof s === 'string' ? s : (s.name || s.nama || '')).filter(Boolean);
    }
  }).catch(() => {});

  function statusStyle(s) {
    switch (String(s).toUpperCase()) {
      case 'CLAIM WAITING APPROVAL': return { color: 'yellow', icon: 'fa-hourglass-half' };
      case 'CLAIM APPROVE':          return { color: 'blue',   icon: 'fa-thumbs-up' };
      case 'CLAIM IN PROGRESS':      return { color: 'orange', icon: 'fa-screwdriver-wrench' };
      case 'CLAIM DONE':             return { color: 'cyan',   icon: 'fa-circle-check' };
      case 'CLAIM READY TO PICKUP':  return { color: 'purple', icon: 'fa-hand-holding-hand' };
      case 'CLAIM COMPLETE':         return { color: 'green',  icon: 'fa-flag-checkered' };
      default:                        return { color: 'muted',  icon: 'fa-clock' };
    }
  }

  function applyFilter() {
    const q = searchText.toLowerCase().trim();
    let data = claims.slice();
    if (filterStatus === 'ALL') {
      data = data.filter(d => String(d.claimStatus || '').toUpperCase() !== 'CLAIM APPROVE');
    } else {
      data = data.filter(d => String(d.claimStatus || '').toUpperCase() === filterStatus.toUpperCase());
    }
    if (q) {
      data = data.filter(d =>
        String(d.siri || '').toLowerCase().includes(q) ||
        String(d.nama || '').toLowerCase().includes(q) ||
        String(d.tel || '').toLowerCase().includes(q) ||
        String(d.model || '').toLowerCase().includes(q) ||
        String(d.claimID || '').toLowerCase().includes(q)
      );
    }
    return data;
  }

  function render() {
    const arr = applyFilter();
    $('cwCount').textContent = arr.length;
    if (!arr.length) {
      list.innerHTML = '';
      empty.querySelector('.lbl').textContent = claims.length ? 'Tiada padanan.' : 'Tiada rekod claim.';
      empty.querySelector('.sub').textContent = claims.length ? '' : 'Klik "Daftar Claim" untuk mula.';
      empty.classList.remove('hidden');
      return;
    }
    empty.classList.add('hidden');
    list.innerHTML = arr.map(c => card(c)).join('');
  }

  function card(c) {
    const st = statusStyle(c.claimStatus || 'Claim Waiting Approval');
    const warr = c.claimWarrantyExp ? `<span class="cw-warr ${isExpired(c.claimWarrantyExp) ? 'is-exp' : ''}"><i class="fas fa-shield-halved"></i> ${escHtml(c.claimWarrantyExp)}</span>` : '';
    return `
      <article class="lost-card cw-card c-${st.color}">
        <div class="lost-card__top">
          <div>
            <div class="cw-cid">#${escHtml(c.claimID || c.id)}</div>
            <div class="cw-siri">Siri: ${escHtml(c.siri || '-')}</div>
          </div>
          <div class="cw-status c-${st.color}"><i class="fas ${st.icon}"></i> ${escHtml(c.claimStatus || '-')}</div>
        </div>
        <div class="cw-cust">${escHtml(String(c.nama || '-').toUpperCase())}</div>
        <div class="cw-info-line">${escHtml(c.model || '-')} &nbsp;•&nbsp; ${escHtml(c.tel || '-')}</div>
        <div class="cw-info-line">Kerosakan: ${escHtml(c.kerosakan || '-')}</div>
        <div class="cw-foot">
          <div>
            <div class="cw-date">${fmtDateTime(c.timestamp)}</div>
            ${warr}
          </div>
          <button type="button" class="btn-edit" data-edit="${escAttr(c.id)}"><i class="fas fa-pen-to-square"></i> KEMASKINI</button>
        </div>
      </article>
    `;
  }

  // Events
  $('cwSearch').addEventListener('input', e => { searchText = e.target.value; render(); });
  $('cwFilter').addEventListener('change', e => { filterStatus = e.target.value; render(); });
  $('cwNewBtn').addEventListener('click', openRepairSearch);
  $('cwSearchClose').addEventListener('click', () => searchModal.classList.remove('is-open'));
  searchModal.addEventListener('click', e => { if (e.target === searchModal) searchModal.classList.remove('is-open'); });
  $('cwRepairSearch').addEventListener('input', e => { repairQuery = e.target.value; renderRepairResults(); });

  $('cwUpClose').addEventListener('click', () => updateModal.classList.remove('is-open'));
  updateModal.addEventListener('click', e => { if (e.target === updateModal) updateModal.classList.remove('is-open'); });
  $('cwUpSave').addEventListener('click', saveUpdate);
  $('cwUpDelete').addEventListener('click', () => {
    if (!editing) return;
    pendingDeleteId = editing.id;
    $('cwDelMsg').textContent = `Padam claim #${editing.claimID || editing.id}? Tindakan tidak boleh dibatalkan.`;
    delModal.classList.add('is-open');
  });
  $('cwUpStatus').addEventListener('change', syncDatesFromStatus);
  $('cwUpWType').addEventListener('change', syncWarranty);
  $('cwUpWTempoh').addEventListener('change', syncWarranty);

  $('cwDelCancel').addEventListener('click', () => { pendingDeleteId = null; delModal.classList.remove('is-open'); });
  delModal.addEventListener('click', e => { if (e.target === delModal) delModal.classList.remove('is-open'); });
  $('cwDelOk').addEventListener('click', async () => {
    if (!pendingDeleteId) return;
    try {
      await db.collection('claims_' + ownerID).doc(pendingDeleteId).delete();
      toast('Claim dipadam');
      delModal.classList.remove('is-open');
      updateModal.classList.remove('is-open');
    } catch (e) { toast('Ralat: ' + e.message, true); }
    pendingDeleteId = null;
  });

  list.addEventListener('click', e => {
    const b = e.target.closest('[data-edit]');
    if (!b) return;
    const c = claims.find(x => x.id === b.dataset.edit);
    if (c) openUpdate(c);
  });

  // Repair search
  function openRepairSearch() {
    repairQuery = '';
    $('cwRepairSearch').value = '';
    renderRepairResults();
    searchModal.classList.add('is-open');
  }

  function renderRepairResults() {
    const q = repairQuery.toLowerCase().trim();
    const results = q
      ? repairs.filter(r => String(r.siri || '').toLowerCase().includes(q) || String(r.tel || '').toLowerCase().includes(q)).slice(0, 20)
      : [];
    $('cwRepairCount').textContent = `${results.length} keputusan`;
    const box = $('cwRepairResults');
    if (!q) {
      box.innerHTML = '<div class="cw-results__empty"><i class="fas fa-file-circle-question"></i><div>Cari repair untuk daftar claim</div></div>';
      return;
    }
    if (!results.length) {
      box.innerHTML = '<div class="cw-results__empty"><i class="fas fa-circle-exclamation"></i><div>Tiada padanan</div></div>';
      return;
    }
    box.innerHTML = results.map(r => {
      const siri = r.siri || '-';
      const warr = r.warranty || 'TIADA';
      const hasWarr = warr && warr !== 'TIADA';
      const claimed = claims.some(c => (c.siri || '') === siri);
      const warrExp = r.warranty_exp || '';
      const warrLine = warrExp ? `<div class="cw-result__warr ${isExpired(warrExp) ? 'is-exp' : ''}">Warranty Tamat: ${escHtml(warrExp)}</div>` : '';
      const warrBadge = hasWarr ? `<span class="cw-warr"><i class="fas fa-shield-halved"></i> ${escHtml(warr)}</span>` : '';
      const btn = claimed
        ? `<div class="cw-result__done"><i class="fas fa-circle-check"></i> SUDAH DIDAFTARKAN</div>`
        : `<button type="button" class="btn-submit" data-reg="${escAttr(r.siri || '')}" style="margin:0; padding:9px; background:var(--blue); font-size:11px"><i class="fas fa-plus"></i> DAFTAR CLAIM</button>`;
      return `
        <div class="cw-result ${hasWarr ? 'has-warr' : ''}">
          <div class="cw-result__head">
            <span class="cw-result__siri">#${escHtml(siri)}</span>
            <span class="cw-result__status">${escHtml(String(r.status || '').toUpperCase())}</span>
            ${warrBadge}
          </div>
          <div class="cw-result__nama">${escHtml(String(r.nama || '-').toUpperCase())}</div>
          <div class="cw-result__meta">${escHtml(r.model || '-')} | ${escHtml(r.tel || '-')}</div>
          <div class="cw-result__meta">Kerosakan: ${escHtml(r.kerosakan || '-')}</div>
          <div class="cw-result__meta">Tarikh: ${fmtDateTime(r.timestamp)}</div>
          ${warrLine}
          <div style="margin-top:8px">${btn}</div>
        </div>
      `;
    }).join('');
  }
  $('cwRepairResults').addEventListener('click', async e => {
    const b = e.target.closest('[data-reg]');
    if (!b) return;
    const r = repairs.find(x => String(x.siri || '') === b.dataset.reg);
    if (!r) return;
    await registerClaim(r);
    searchModal.classList.remove('is-open');
  });

  async function registerClaim(r) {
    const now = Date.now();
    const claimID = 'CLM' + new Date(now).toISOString().replace(/[-T:.Z]/g, '').slice(0, 14);
    const data = {
      claimID,
      siri: r.siri || '-',
      nama: r.nama || '-',
      tel: r.tel || '-',
      tel_wasap: r.tel_wasap || '',
      model: r.model || '-',
      kerosakan: r.kerosakan || '-',
      harga: r.harga || '0',
      total: r.total || '0',
      items_array: r.items_array || [],
      originalWarranty: r.warranty || 'TIADA',
      originalWarrantyExp: r.warranty_exp || '',
      claimStatus: 'Claim Waiting Approval',
      claimWarranty: 'TIADA',
      claimWarrantyTempoh: 0,
      claimWarrantyExp: '',
      nota: '',
      staffTerima: '', staffRepair: '', staffSerah: '',
      tarikhHantar: isoLocal(new Date(now)),
      tarikhSiap: '', tarikhPickup: '',
      shopID, ownerID,
      timestamp: now,
      lastUpdated: now,
    };
    try {
      await db.collection('claims_' + ownerID).doc(claimID).set(data);
      toast(`Claim #${claimID} didaftarkan`);
    } catch (e) { toast('Ralat: ' + e.message, true); }
  }

  // Update modal
  function openUpdate(c) {
    editing = c;
    $('cwUpId').textContent = '#' + (c.claimID || c.id);
    const warrAsal = c.originalWarranty && c.originalWarranty !== 'TIADA'
      ? `<div><i class="fas fa-shield-halved" style="color:var(--yellow)"></i> Warranty Asal: ${escHtml(c.originalWarranty)}${c.originalWarrantyExp ? ` <span class="${isExpired(c.originalWarrantyExp) ? 'is-exp' : 'is-ok'}">(Tamat: ${escHtml(c.originalWarrantyExp)})</span>` : ''}</div>`
      : '';
    $('cwUpInfo').innerHTML = `
      <div><i class="fas fa-user"></i> <strong>${escHtml(String(c.nama || '-').toUpperCase())}</strong></div>
      <div><i class="fas fa-phone"></i> ${escHtml(c.tel || '-')} &nbsp; <i class="fas fa-mobile-screen-button"></i> ${escHtml(c.model || '-')}</div>
      <div><i class="fas fa-screwdriver-wrench"></i> Kerosakan: ${escHtml(c.kerosakan || '-')}</div>
      <div><i class="fas fa-hashtag"></i> Siri Repair: #${escHtml(c.siri || '-')}</div>
      ${warrAsal}
    `;
    $('cwUpStatus').value = c.claimStatus || 'Claim Waiting Approval';
    $('cwUpHantar').value = toLocalInput(c.tarikhHantar);
    $('cwUpSiap').value = toLocalInput(c.tarikhSiap);
    $('cwUpPickup').value = toLocalInput(c.tarikhPickup);
    fillStaff('cwUpStaffT', c.staffTerima || '');
    fillStaff('cwUpStaffR', c.staffRepair || '');
    fillStaff('cwUpStaffS', c.staffSerah || '');
    $('cwUpWType').value = c.claimWarranty || 'TIADA';
    $('cwUpWTempoh').value = String(c.claimWarrantyTempoh || 7);
    $('cwUpNota').value = c.nota || '';
    syncWarranty();
    updateModal.classList.add('is-open');
  }

  function fillStaff(id, current) {
    const el = $(id);
    const opts = ['', ...staffList];
    if (current && !opts.includes(current)) opts.push(current);
    el.innerHTML = opts.map(s => `<option value="${escAttr(s)}" ${s === current ? 'selected' : ''}>${s ? escHtml(s) : '—'}</option>`).join('');
  }

  function syncDatesFromStatus() {
    if (!editing) return;
    const s = $('cwUpStatus').value;
    const now = isoLocal(new Date());
    if (s === 'Claim In Progress' && !$('cwUpHantar').value) $('cwUpHantar').value = toLocalInput(now);
    if ((s === 'Claim Done' || s === 'Claim Ready to Pickup') && !$('cwUpSiap').value) $('cwUpSiap').value = toLocalInput(now);
    if (s === 'Claim Complete') {
      if (!$('cwUpSiap').value) $('cwUpSiap').value = toLocalInput(now);
      if (!$('cwUpPickup').value) $('cwUpPickup').value = toLocalInput(now);
    }
  }

  function syncWarranty() {
    const type = $('cwUpWType').value;
    const tempohWrap = $('cwUpWTempohWrap'), expEl = $('cwUpWExp');
    tempohWrap.classList.toggle('hidden', type !== 'TAMBAH');
    let exp = '';
    if (type === 'ASAL') exp = editing && editing.originalWarrantyExp || '';
    else if (type === 'TAMBAH') {
      const days = parseInt($('cwUpWTempoh').value || '0', 10);
      const base = editing && typeof editing.timestamp === 'number' ? editing.timestamp : Date.now();
      if (days > 0) {
        const d = new Date(base + days * 86400000);
        const p = n => String(n).padStart(2, '0');
        exp = `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()}`;
      }
    }
    expEl.dataset.exp = exp;
    if (exp) {
      const expired = isExpired(exp);
      expEl.innerHTML = `<i class="fas ${expired ? 'fa-triangle-exclamation' : 'fa-shield-halved'}"></i> WARRANTY TAMAT: ${escHtml(exp)}`;
      expEl.className = 'cw-exp ' + (expired ? 'is-exp' : 'is-ok');
      expEl.classList.remove('hidden');
    } else {
      expEl.classList.add('hidden');
    }
  }

  async function saveUpdate() {
    if (!editing) return;
    const data = {
      claimStatus: $('cwUpStatus').value,
      nota: $('cwUpNota').value.trim(),
      staffTerima: $('cwUpStaffT').value,
      staffRepair: $('cwUpStaffR').value,
      staffSerah: $('cwUpStaffS').value,
      tarikhHantar: fromLocalInput($('cwUpHantar').value),
      tarikhSiap: fromLocalInput($('cwUpSiap').value),
      tarikhPickup: fromLocalInput($('cwUpPickup').value),
      claimWarranty: $('cwUpWType').value,
      claimWarrantyTempoh: $('cwUpWType').value === 'TAMBAH' ? parseInt($('cwUpWTempoh').value || '0', 10) : 0,
      claimWarrantyExp: $('cwUpWExp').dataset.exp || '',
      lastUpdated: Date.now(),
    };
    try {
      await db.collection('claims_' + ownerID).doc(editing.id).update(data);
      toast('Claim dikemaskini');
      updateModal.classList.remove('is-open');
    } catch (e) { toast('Ralat: ' + e.message, true); }
  }

  // Helpers
  function isExpired(ddmmyyyy) {
    if (!ddmmyyyy) return false;
    const m = String(ddmmyyyy).match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
    if (!m) return false;
    const exp = new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]));
    return Date.now() > exp.getTime();
  }
  function fmtDateTime(ts) {
    if (typeof ts === 'number') {
      const d = new Date(ts);
      const p = n => String(n).padStart(2, '0');
      return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`;
    }
    if (typeof ts === 'string' && ts) return ts.replace('T', ' ');
    return '-';
  }
  function isoLocal(d) {
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function toLocalInput(s) {
    if (!s) return '';
    return String(s).slice(0, 16);
  }
  function fromLocalInput(s) { return s || ''; }
  function toast(msg, isErr) {
    const t = $('cwToast');
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.hidden = true, 2500);
  }
  function escHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function escAttr(s) { return escHtml(s); }
})();
