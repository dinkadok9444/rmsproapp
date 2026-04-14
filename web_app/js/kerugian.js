/* Port dari lib/screens/modules/lost_screen.dart */
(function () {
  'use strict';
  if (!document.getElementById('lsList')) return;

  const JENIS = ['Pecah Masa Repair', 'CN Tak Approve', 'Rosak / Defect', 'Hilang', 'Lain-lain'];

  let ownerID = 'admin', shopID = 'MAIN';
  let losses = [];
  let filterJenis = 'SEMUA';
  let sortOrder = 'ZA';
  let searchText = '';
  let editing = null; // existing record when editing
  let pendingDeleteId = null;

  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const p = branch.split('@');
    ownerID = p[0]; shopID = (p[1] || '').toUpperCase();
  }

  const $ = id => document.getElementById(id);
  const list = $('lsList'), empty = $('lsEmpty'), chips = $('lsChips');
  const formModal = $('lsFormModal'), deleteModal = $('lsDeleteModal');

  // Chips
  function renderChips() {
    const items = ['SEMUA', ...JENIS];
    chips.innerHTML = items.map(j => {
      const active = filterJenis.toUpperCase() === j.toUpperCase();
      return `<button type="button" class="lost-chip ${active ? 'is-active' : ''}" data-j="${escapeAttr(j)}">${escapeHtml(j)}</button>`;
    }).join('');
  }
  chips.addEventListener('click', e => {
    const b = e.target.closest('.lost-chip');
    if (!b) return;
    filterJenis = b.dataset.j;
    renderChips(); render();
  });

  // Listener
  db.collection('losses_' + ownerID).onSnapshot(snap => {
    const arr = [];
    snap.forEach(d => {
      const v = d.data(); v.key = d.id;
      if (String(v.shopID || '').toUpperCase() === shopID) arr.push(v);
    });
    arr.sort((a, b) => Number(b.timestamp || 0) - Number(a.timestamp || 0));
    losses = arr;
    render();
  }, err => console.warn('losses:', err));

  // Filter/sort
  function filtered() {
    let arr = losses.slice();
    if (filterJenis !== 'SEMUA') {
      arr = arr.filter(d => String(d.jenis || '').toUpperCase() === filterJenis.toUpperCase());
    }
    const q = searchText.toUpperCase().trim();
    if (q) {
      arr = arr.filter(d =>
        String(d.keterangan || '').toUpperCase().includes(q) ||
        String(d.jenis || '').toUpperCase().includes(q) ||
        String(d.siri || '').toUpperCase().includes(q)
      );
    }
    arr.sort((a, b) => {
      const ta = Number(a.timestamp || 0), tb = Number(b.timestamp || 0);
      return sortOrder === 'AZ' ? ta - tb : tb - ta;
    });
    return arr;
  }

  function jenisStyle(jenis) {
    const j = String(jenis).toUpperCase();
    if (j.includes('PECAH')) return { color: 'red', icon: 'fa-heart-crack' };
    if (j.includes('CN')) return { color: 'yellow', icon: 'fa-file-circle-xmark' };
    if (j.includes('ROSAK') || j.includes('DEFECT')) return { color: 'orange', icon: 'fa-screwdriver-wrench' };
    if (j.includes('HILANG')) return { color: 'purple', icon: 'fa-circle-question' };
    return { color: 'muted', icon: 'fa-triangle-exclamation' };
  }

  function render() {
    const arr = filtered();
    $('lsCount').textContent = `${arr.length} rekod`;
    const total = arr.reduce((s, d) => s + Number(d.jumlah || 0), 0);
    $('lsTotal').textContent = 'RM ' + total.toFixed(2);

    if (!losses.length) {
      list.innerHTML = '';
      empty.querySelector('.lbl').textContent = 'Tiada rekod kerugian.';
      empty.querySelector('.sub').textContent = 'Semoga perniagaan sentiasa selamat.';
      empty.classList.remove('hidden');
      return;
    }
    if (!arr.length) {
      list.innerHTML = '';
      empty.querySelector('.lbl').textContent = 'Tiada padanan.';
      empty.querySelector('.sub').textContent = '';
      empty.classList.remove('hidden');
      return;
    }
    empty.classList.add('hidden');

    list.innerHTML = arr.map(r => {
      const jenis = r.jenis || 'Lain-lain';
      const s = jenisStyle(jenis);
      const jumlah = Number(r.jumlah || 0).toFixed(2);
      const siri = r.siri ? `<div class="lost-card__siri">#${escapeHtml(r.siri)}</div>` : '';
      return `
        <article class="lost-card c-${s.color}">
          <div class="lost-card__top">
            <div class="lost-card__jenis">
              <span class="lost-card__icon"><i class="fas ${s.icon}"></i></span>
              <span>${escapeHtml(jenis)}</span>
            </div>
            <div class="lost-card__amt">- RM ${jumlah}</div>
          </div>
          <div class="lost-card__note">${escapeHtml(r.keterangan || '-')}</div>
          <div class="lost-card__foot">
            <div>
              ${siri}
              <div class="lost-card__date">${fmtDateTime(r.timestamp)}</div>
            </div>
            <div class="lost-card__actions">
              <button type="button" class="icon-btn" data-edit="${escapeAttr(r.key)}" title="Edit"><i class="fas fa-pen-to-square"></i></button>
              <button type="button" class="icon-btn icon-btn--danger" data-del="${escapeAttr(r.key)}" title="Padam"><i class="fas fa-trash-can"></i></button>
            </div>
          </div>
        </article>
      `;
    }).join('');
  }

  // Events
  $('lsSearch').addEventListener('input', e => { searchText = e.target.value; render(); });
  $('lsSort').addEventListener('change', e => { sortOrder = e.target.value; render(); });
  $('lsNewBtn').addEventListener('click', () => openForm(null));
  $('lsFormClose').addEventListener('click', () => formModal.classList.remove('is-open'));
  $('lsSubmit').addEventListener('click', submitForm);
  formModal.addEventListener('click', e => { if (e.target === formModal) formModal.classList.remove('is-open'); });

  list.addEventListener('click', e => {
    const edit = e.target.closest('[data-edit]');
    const del = e.target.closest('[data-del]');
    if (edit) {
      const r = losses.find(x => x.key === edit.dataset.edit);
      if (r) openForm(r);
    } else if (del) {
      pendingDeleteId = del.dataset.del;
      deleteModal.classList.add('is-open');
    }
  });
  $('lsDelCancel').addEventListener('click', () => { pendingDeleteId = null; deleteModal.classList.remove('is-open'); });
  $('lsDelOk').addEventListener('click', async () => {
    if (!pendingDeleteId) return;
    try {
      await db.collection('losses_' + ownerID).doc(pendingDeleteId).delete();
      toast('Rekod dipadam');
    } catch (e) { toast('Ralat: ' + e.message, true); }
    pendingDeleteId = null;
    deleteModal.classList.remove('is-open');
  });
  deleteModal.addEventListener('click', e => { if (e.target === deleteModal) deleteModal.classList.remove('is-open'); });

  function openForm(existing) {
    editing = existing;
    $('lsFormTitle').textContent = existing ? 'KEMASKINI KERUGIAN' : 'REKOD KERUGIAN';
    $('lsSubmitLbl').textContent = existing ? 'KEMASKINI' : 'SIMPAN';
    $('lsJenis').value = existing ? (existing.jenis || JENIS[0]) : JENIS[0];
    $('lsSiri').value = existing ? (existing.siri || '') : '';
    $('lsJumlah').value = existing ? Number(existing.jumlah || 0).toFixed(2) : '';
    $('lsKeterangan').value = existing ? (existing.keterangan || '') : '';
    formModal.classList.add('is-open');
  }

  async function submitForm() {
    const jumlah = parseFloat($('lsJumlah').value);
    const keterangan = $('lsKeterangan').value.trim();
    if (!keterangan || isNaN(jumlah)) return toast('Sila isi jumlah dan keterangan', true);
    const data = {
      shopID,
      jenis: $('lsJenis').value,
      siri: $('lsSiri').value.trim().toUpperCase(),
      jumlah,
      keterangan,
      timestamp: Date.now(),
    };
    try {
      if (editing && editing.key) {
        await db.collection('losses_' + ownerID).doc(editing.key).update(data);
        toast('Rekod dikemaskini');
      } else {
        await db.collection('losses_' + ownerID).add(data);
        toast('Kerugian direkodkan');
      }
      formModal.classList.remove('is-open');
    } catch (e) { toast('Ralat: ' + e.message, true); }
  }

  function fmtDateTime(ts) {
    if (typeof ts !== 'number') return '-';
    const d = new Date(ts);
    const p = n => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function toast(msg, isErr) {
    const t = $('lsToast');
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.hidden = true, 2200);
  }
  function escapeHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function escapeAttr(s) { return escapeHtml(s); }

  renderChips();
  render();
})();
