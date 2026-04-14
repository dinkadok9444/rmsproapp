/* Port dari lib/screens/modules/maklum_balas_screen.dart */
(function () {
  'use strict';
  if (!document.getElementById('mbList')) return;

  // --- State (mirror _MaklumBalasScreenState) ---
  let ownerID = 'admin';
  let shopID = 'MAIN';
  let feedbacks = [];
  let filterStar = 'Semua';
  let sortOrder = 'Terbaru';
  let dropdownValue = 'Semua_Terbaru';
  let showSearch = false;
  let searchText = '';

  // --- Init branch from localStorage (mirror _init) ---
  const branch = localStorage.getItem('rms_current_branch') || '';
  if (branch.includes('@')) {
    const parts = branch.split('@');
    ownerID = parts[0];
    shopID = (parts[1] || '').toUpperCase();
  }

  // --- DOM refs ---
  const elAvg = document.getElementById('mbAvg');
  const elCount = document.getElementById('mbCount');
  const elShowing = document.getElementById('mbShowing');
  const elList = document.getElementById('mbList');
  const elEmpty = document.getElementById('mbEmpty');
  const elFilter = document.getElementById('mbFilter');
  const elSearch = document.getElementById('mbSearch');
  const elSearchToggle = document.getElementById('mbSearchToggle');
  const elSearchWrap = document.getElementById('mbSearchWrap');
  const elModal = document.getElementById('mbStaffModal');

  // --- Firestore listener (feedback_<ownerID> where shopID==) ---
  db.collection('feedback_' + ownerID).onSnapshot(snap => {
    const list = [];
    snap.forEach(doc => {
      const d = doc.data();
      if (String(d.shopID || '').toUpperCase() === shopID) list.push(d);
    });
    feedbacks = list;
    render();
  }, err => console.warn('feedback listener:', err));

  // --- Events ---
  elFilter.addEventListener('change', () => {
    const v = elFilter.value;
    dropdownValue = v;
    if (v === 'Semua_Terbaru') { filterStar = 'Semua'; sortOrder = 'Terbaru'; }
    else if (v === 'Semua_Terdahulu') { filterStar = 'Semua'; sortOrder = 'Terdahulu'; }
    else { filterStar = v; }
    render();
  });
  elSearchToggle.addEventListener('click', () => {
    showSearch = !showSearch;
    elSearchWrap.classList.toggle('hidden', !showSearch);
    elSearchToggle.classList.toggle('is-active', showSearch);
    if (showSearch) elSearch.focus();
    else { searchText = ''; elSearch.value = ''; render(); }
  });
  elSearch.addEventListener('input', () => { searchText = elSearch.value; render(); });

  document.getElementById('mbStaffClose').addEventListener('click', () => elModal.classList.remove('is-open'));
  elModal.addEventListener('click', e => { if (e.target === elModal) elModal.classList.remove('is-open'); });

  // --- Derived (mirror _avgRating, _filtered) ---
  function avgRating() {
    if (!feedbacks.length) return 0;
    const total = feedbacks.reduce((s, d) => s + Number(d.rating || 0), 0);
    return total / feedbacks.length;
  }
  function filtered() {
    let list = feedbacks.slice();
    if (filterStar !== 'Semua') {
      const star = parseInt(filterStar, 10) || 0;
      list = list.filter(d => Number(d.rating || 0) === star);
    }
    const q = searchText.toLowerCase().trim();
    if (q) {
      list = list.filter(d =>
        String(d.siri || '').toLowerCase().includes(q) ||
        String(d.nama || '').toLowerCase().includes(q) ||
        String(d.tel  || '').toLowerCase().includes(q)
      );
    }
    list.sort((a, b) => {
      const ta = Number(a.timestamp || 0), tb = Number(b.timestamp || 0);
      return sortOrder === 'Terbaru' ? tb - ta : ta - tb;
    });
    return list;
  }

  // --- Render ---
  function render() {
    elAvg.textContent = avgRating().toFixed(1);
    elCount.textContent = `${feedbacks.length} Maklum Balas`;
    const list = filtered();
    elShowing.textContent = `Menunjukkan ${list.length} rekod`;
    if (!feedbacks.length) {
      elList.innerHTML = '';
      elEmpty.textContent = 'Tiada maklum balas.';
      elEmpty.classList.remove('hidden');
      return;
    }
    if (!list.length) {
      elList.innerHTML = '';
      elEmpty.textContent = 'Tiada padanan.';
      elEmpty.classList.remove('hidden');
      return;
    }
    elEmpty.classList.add('hidden');
    elList.innerHTML = list.map(f => card(f)).join('');
  }

  function card(f) {
    const rating = Math.max(0, Math.min(5, parseInt(f.rating || 0, 10)));
    const siri = f.siri || '-';
    const nama = String(f.nama || 'Pelanggan').toUpperCase();
    const tel = f.tel || '-';
    const komen = f.komen ? String(f.komen) : '';
    const tarikh = typeof f.timestamp === 'number' ? formatDate(f.timestamp) : '-';
    const stars = Array.from({length: 5}, (_, j) =>
      `<i class="${j < rating ? 'fas' : 'far'} fa-star"></i>`
    ).join('');
    const komenHtml = komen ? `<div class="mb-card__komen">"${escapeHtml(komen)}"</div>` : '';
    return `
      <article class="mb-card">
        <div class="mb-card__top">
          <span class="mb-card__siri">#${escapeHtml(siri)}</span>
          <span class="mb-card__stars">${stars}</span>
        </div>
        <div class="mb-card__nama">${escapeHtml(nama)}</div>
        <div class="mb-card__tel">${escapeHtml(tel)}</div>
        ${komenHtml}
        <div class="mb-card__foot">
          <span class="mb-card__date">${tarikh}</span>
          <button type="button" class="mb-staff-btn" data-siri="${escapeHtml(String(siri))}">
            <i class="fas fa-users"></i> LIHAT STAF
          </button>
        </div>
      </article>
    `;
  }

  // --- Staff lookup (mirror _lookupStaff) ---
  elList.addEventListener('click', async e => {
    const btn = e.target.closest('.mb-staff-btn');
    if (!btn) return;
    const siri = btn.dataset.siri || '';
    const staff = await lookupStaff(siri);
    document.getElementById('mbStaffTerima').textContent = (staff.terima || '-').toUpperCase();
    document.getElementById('mbStaffRepair').textContent = (staff.repair || '-').toUpperCase();
    document.getElementById('mbStaffSerah').textContent  = (staff.serah  || '-').toUpperCase();
    elModal.classList.add('is-open');
  });

  async function lookupStaff(siri) {
    const fallback = { terima: '-', repair: '-', serah: '-' };
    if (!siri || siri === '-') return fallback;
    try {
      const snap = await db.collection('repairs_' + ownerID)
        .where('siri', '==', siri).limit(1).get();
      if (!snap.empty) {
        const d = snap.docs[0].data();
        return {
          terima: d.staff_terima || d.staffTerima || '-',
          repair: d.staff_repair || d.staffRepair || '-',
          serah:  d.staff_serah  || d.staffSerah  || '-',
        };
      }
    } catch (_) {}
    return fallback;
  }

  // --- Helpers ---
  function formatDate(ms) {
    const d = new Date(ms);
    const pad = n => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${String(d.getFullYear()).slice(-2)}`;
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
  }
})();
