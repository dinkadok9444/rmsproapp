/* Admin → Senarai Aktif. Mirror senarai_aktif_screen.dart.
   Tables:
     - tenants (id, owner_id, nama_kedai, status, expire_date, single_staff_mode, config jsonb, created_at)
     - branches (id, tenant_id, shop_code, phone, email, alamat, logo_base64, single_staff_mode, expire_date, enabled_modules, extras jsonb)
*/
(function () {
  'use strict';

  // ───── State ─────────────────────────────────────────────────────────
  const PAGE_SIZE = 20;
  const FETCH_BATCH = 500;
  let dealers = [];
  let filtered = [];
  let searchQ = '';
  let filterNegeri = 'Semua';
  let sortMode = 'newest';
  let currentPage = 0;
  let menuEl = null;

  const MODUL_LIST = [
    { id:'widget', label:'Dashboard' },
    { id:'Stock', label:'Inventori' },
    { id:'DB_Cust', label:'Pelanggan' },
    { id:'Booking', label:'Booking' },
    { id:'Claim_warranty', label:'Claim' },
    { id:'Collab', label:'Kolaborasi' },
    { id:'Profesional', label:'Pro Mode' },
    { id:'Refund', label:'Refund' },
    { id:'Lost', label:'Kerugian' },
    { id:'MaklumBalas', label:'Prestasi' },
    { id:'Link', label:'Link' },
    { id:'Fungsi_lain', label:'Fungsi Lain' },
    { id:'Settings', label:'Tetapan' },
  ];

  // ───── Elements ──────────────────────────────────────────────────────
  const listEl    = document.getElementById('dealerList');
  const searchEl  = document.getElementById('searchInput');
  const negeriEl  = document.getElementById('filterNegeri');
  const sortEl    = document.getElementById('sortMode');
  const countEl   = document.getElementById('countBadge');
  const pagerEl   = document.getElementById('pager');
  const btnPrev   = document.getElementById('btnPrev');
  const btnNext   = document.getElementById('btnNext');
  const pageInfo  = document.getElementById('pageInfo');

  const detailModal = document.getElementById('detailModal');
  const dNama = document.getElementById('dNama');
  const dSid  = document.getElementById('dSid');
  const dBody = document.getElementById('dBody');

  const confirmModal = document.getElementById('confirmModal');

  // ───── Init ──────────────────────────────────────────────────────────
  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnReload').addEventListener('click', load);
  document.getElementById('dClose').addEventListener('click', closeDetail);
  detailModal.querySelector('.modal__backdrop').addEventListener('click', closeDetail);
  confirmModal.querySelector('.modal__backdrop').addEventListener('click', () => confirmModal.classList.add('hidden'));
  document.getElementById('confirmCancel').addEventListener('click', () => confirmModal.classList.add('hidden'));

  searchEl.addEventListener('input', () => { searchQ = searchEl.value.trim().toLowerCase(); applyFilter(); });
  negeriEl.addEventListener('change', () => { filterNegeri = negeriEl.value; applyFilter(); });
  sortEl.addEventListener('change',   () => { sortMode = sortEl.value; applyFilter(); });
  btnPrev.addEventListener('click', () => { if (currentPage > 0) { currentPage--; render(); } });
  btnNext.addEventListener('click', () => { if (currentPage < totalPages() - 1) { currentPage++; render(); } });

  document.addEventListener('click', (e) => { if (menuEl && !menuEl.contains(e.target)) closeMenu(); });

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  // ───── Data ──────────────────────────────────────────────────────────
  async function load() {
    listEl.innerHTML = `<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i> Memuat…</div>`;
    const { data, error } = await window.sb
      .from('tenants').select('*')
      .order('created_at', { ascending: false })
      .limit(FETCH_BATCH);
    if (error) { listEl.innerHTML = `<div class="admin-error">${escapeHtml(error.message)}</div>`; return; }
    dealers = (data || []).map(tenantToUi);
    buildNegeriOptions();
    applyFilter();
  }

  function tenantToUi(r) {
    const c = (r.config && typeof r.config === 'object') ? r.config : {};
    return {
      id: r.id,
      ownerID: r.owner_id,
      shopID: c.shopID || 'MAIN',
      namaKedai: r.nama_kedai || '',
      ownerName: c.ownerName || '',
      ownerContact: c.ownerContact || '',
      phone: c.ownerContact || '',
      email: c.email || c.emel || '',
      emel: c.emel || c.email || '',
      negeri: c.negeri || '',
      daerah: c.daerah || '',
      alamat: c.alamat || '',
      ssm: c.ssm || '',
      password: c.password || '',
      svTel: c.svTel || '',
      svPass: c.svPass || '',
      status: r.status || 'Aktif',
      expireDate: r.expire_date,
      createdAt: r.created_at,
      enabledModules: c.enabledModules || {},
      singleStaffMode: r.single_staff_mode === true,
      proMode: c.proMode === true,
      proModeExpire: c.proModeExpire || 0,
      addonGallery: c.addonGallery === true,
      galleryExpire: c.galleryExpire || 0,
      _config: c,
    };
  }

  function buildNegeriOptions() {
    const set = new Set();
    dealers.forEach(d => { if (d.negeri) set.add(d.negeri); });
    const cur = negeriEl.value || 'Semua';
    negeriEl.innerHTML = `<option value="Semua">Semua Negeri</option>` +
      [...set].sort().map(n => `<option value="${escapeHtml(n)}">${escapeHtml(n)}</option>`).join('');
    negeriEl.value = [...set].includes(cur) ? cur : 'Semua';
    filterNegeri = negeriEl.value;
  }

  function applyFilter() {
    const q = searchQ;
    filtered = dealers.filter(d => {
      const s = (d.namaKedai + ' ' + d.ownerName + ' ' + d.id + ' ' + d.phone).toLowerCase();
      const matchS = !q || s.includes(q);
      const matchN = filterNegeri === 'Semua' || d.negeri === filterNegeri;
      return matchS && matchN;
    });
    filtered.sort((a, b) => {
      if (sortMode === 'alpha') return a.namaKedai.toLowerCase().localeCompare(b.namaKedai.toLowerCase());
      if (sortMode === 'expiry') return toMs(a.expireDate) - toMs(b.expireDate);
      return toMs(b.createdAt) - toMs(a.createdAt);
    });
    currentPage = 0;
    countEl.textContent = filtered.length;
    render();
  }

  function totalPages() { return Math.max(1, Math.ceil(filtered.length / PAGE_SIZE)); }

  function render() {
    closeMenu();
    if (!filtered.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-store" style="font-size:36px;opacity:0.4;display:block;margin-bottom:8px"></i>Tiada rekod dijumpai</div>`;
      pagerEl.classList.add('hidden');
      return;
    }
    const tp = totalPages();
    if (currentPage >= tp) currentPage = tp - 1;
    const start = currentPage * PAGE_SIZE;
    const slice = filtered.slice(start, start + PAGE_SIZE);
    listEl.innerHTML = slice.map(dealerCard).join('');
    pagerEl.classList.toggle('hidden', filtered.length <= PAGE_SIZE);
    pageInfo.textContent = `Halaman ${currentPage + 1} / ${tp}`;
    btnPrev.disabled = currentPage === 0;
    btnNext.disabled = currentPage >= tp - 1;

    listEl.querySelectorAll('.dealer-card').forEach(el => {
      el.addEventListener('click', (ev) => {
        if (ev.target.closest('.dealer-menu-btn')) return;
        const id = el.dataset.id;
        const d = dealers.find(x => x.id === id);
        if (d) openDetail(d);
      });
    });
    listEl.querySelectorAll('.dealer-menu-btn').forEach(b => {
      b.addEventListener('click', (ev) => { ev.stopPropagation(); openMenu(b, b.dataset.id); });
    });
  }

  function dealerCard(d) {
    const status = d.status || 'Aktif';
    const isSus = status === 'Digantung' || status === 'Suspend';
    const isPen = status === 'Pending';
    const cls = isSus ? 'is-suspend' : (isPen ? 'is-pending' : '');
    const badge = isSus
      ? `<span class="dealer-badge is-suspend">SUSPEND</span>`
      : (isPen ? `<span class="dealer-badge is-pending">PENDING</span>` : `<span class="dealer-badge is-aktif">AKTIF</span>`);
    const expCol = expiryColor(d.expireDate);
    const proBadge = subBadge('PRO', d.proMode, 'purple', d.proModeExpire);
    const galBadge = subBadge('GALLERY', d.addonGallery, 'yellow', d.galleryExpire);
    const staffBadge = subBadge(d.singleStaffMode ? 'SINGLE' : 'MULTI', true, 'cyan', null);
    return `
      <div class="dealer-card ${cls}" data-id="${escapeHtml(d.id)}">
        <div class="dealer-card__head">
          <div class="dealer-card__main">
            <div class="dealer-card__nama">${escapeHtml(d.namaKedai || '-')}</div>
            <div class="dealer-card__owner">${escapeHtml(d.ownerName || '-')}</div>
          </div>
          <div class="dealer-card__expiry" style="color:${expCol}">
            <span class="d1">${escapeHtml(formatDate(d.expireDate))}</span>
            <span class="d2">${escapeHtml(bakiHari(d.expireDate))}</span>
          </div>
          ${badge}
          <button class="dealer-menu-btn" data-id="${escapeHtml(d.id)}" title="Menu"><i class="fas fa-ellipsis-vertical"></i></button>
        </div>
        <div class="dealer-card__info">
          <span class="dealer-chip c-orange"><i class="fas fa-id-badge"></i> ${escapeHtml(d.shopID || '-')}</span>
          <span class="dealer-chip c-blue"><i class="fas fa-location-dot"></i> ${escapeHtml(d.negeri || '-')}</span>
        </div>
        <div class="dealer-card__subs">${proBadge}${galBadge}${staffBadge}</div>
      </div>
    `;
  }

  function subBadge(label, active, color, expire) {
    const baki = expire ? bakiHari(expire) : '';
    const icon = active ? 'fa-circle-check' : 'fa-circle-xmark';
    const cls = active ? `is-on-${color}` : 'is-off';
    return `<span class="sub-badge ${cls}"><i class="fas ${icon}"></i>${escapeHtml(label)}${baki ? `<span class="baki">${escapeHtml(baki)}</span>` : ''}</span>`;
  }

  // ───── Row menu ──────────────────────────────────────────────────────
  function openMenu(anchor, id) {
    closeMenu();
    const d = dealers.find(x => x.id === id); if (!d) return;
    const isSus = d.status === 'Digantung' || d.status === 'Suspend';
    menuEl = document.createElement('div');
    menuEl.className = 'sa-menu';
    menuEl.innerHTML = `
      <button data-act="edit"><i class="fas fa-pen-to-square" style="color:var(--blue)"></i>Edit</button>
      <button data-act="suspend"><i class="fas ${isSus ? 'fa-circle-play' : 'fa-circle-pause'}" style="color:${isSus ? 'var(--green)' : 'var(--orange)'}"></i>${isSus ? 'Aktifkan' : 'Gantung'}</button>
      <button data-act="delete" class="is-danger"><i class="fas fa-trash"></i>Padam</button>
    `;
    document.body.appendChild(menuEl);
    const r = anchor.getBoundingClientRect();
    menuEl.style.top = (window.scrollY + r.bottom + 4) + 'px';
    menuEl.style.left = (window.scrollX + r.right - menuEl.offsetWidth) + 'px';
    menuEl.querySelector('[data-act="edit"]').addEventListener('click', () => { closeMenu(); openDetail(d); });
    menuEl.querySelector('[data-act="suspend"]').addEventListener('click', () => { closeMenu(); quickSuspend(d); });
    menuEl.querySelector('[data-act="delete"]').addEventListener('click', () => { closeMenu(); quickDelete(d); });
  }
  function closeMenu() { if (menuEl) { menuEl.remove(); menuEl = null; } }

  async function quickSuspend(d) {
    const isSus = d.status === 'Digantung' || d.status === 'Suspend';
    const newStatus = isSus ? 'Aktif' : 'Digantung';
    const ok = await confirmDialog({
      title: isSus ? 'Aktifkan akaun?' : 'Gantung akaun?',
      msg: escapeHtml(d.namaKedai || ''),
      okText: isSus ? 'Aktifkan' : 'Gantung',
      okClass: isSus ? 'btn-green' : 'btn-red',
    });
    if (!ok) return;
    const { error } = await window.sb.from('tenants').update({ status: newStatus }).eq('id', d.id);
    if (error) return toast('Ralat: ' + error.message, 'red');
    toast(`Status: ${newStatus}`, isSus ? 'green' : 'orange');
    await load();
  }

  async function quickDelete(d) {
    const ok = await confirmDialog({
      title: 'PADAM AKAUN?',
      msg: `Padam "${escapeHtml(d.namaKedai || '')}" secara kekal?`,
      okText: 'Padam', okClass: 'btn-red',
    });
    if (!ok) return;
    const { error } = await window.sb.from('tenants').delete().eq('id', d.id);
    if (error) return toast('Ralat: ' + error.message, 'red');
    toast('Akaun dipadam.', 'green');
    await load();
  }

  // ───── Detail drawer ─────────────────────────────────────────────────
  let curD = null;         // working copy
  let editAsas = false;
  let showPass = false;

  async function openDetail(d) {
    curD = JSON.parse(JSON.stringify(d));
    editAsas = false; showPass = false;
    renderDetail();
    detailModal.classList.remove('hidden');
    // load sv extras from branch
    try {
      const { data } = await window.sb.from('branches')
        .select('extras').eq('tenant_id', curD.id).eq('shop_code', curD.shopID || 'MAIN').maybeSingle();
      if (data && data.extras && typeof data.extras === 'object') {
        curD.svTel = data.extras.svTel || curD.svTel;
        curD.svPass = data.extras.svPass || curD.svPass;
        renderDetail();
      }
    } catch (_) {}
  }

  function closeDetail() { detailModal.classList.add('hidden'); curD = null; }

  function renderDetail() {
    if (!curD) return;
    dNama.textContent = curD.namaKedai || '-';
    dSid.textContent = 'ID: ' + (curD.shopID || 'MAIN');
    dBody.innerHTML = [
      sectionAsas(),
      sectionPackages(),
      sectionStaffMode(),
      sectionExpire(),
      sectionModules(),
      sectionDanger(),
    ].join('');
    bindDetailEvents();
  }

  function sectionAsas() {
    const d = curD;
    const pw = d.password || '';
    const pwShown = showPass ? pw : (pw ? '•'.repeat(Math.min(pw.length, 16)) : '-');
    const svPw = d.svPass || '';
    const svShown = showPass ? svPw : (svPw ? '•'.repeat(Math.min(svPw.length, 16)) : '-');

    const pill = editAsas
      ? `<button class="sa-section__pill p-save" id="pEditSave"><i class="fas fa-floppy-disk"></i>SIMPAN</button>`
      : `<button class="sa-section__pill p-edit" id="pEditSave"><i class="fas fa-pen-to-square"></i>EDIT</button>`;

    const body = editAsas ? `
      ${editField('owner', 'Pemilik', d.ownerName, 'fa-user')}
      ${editField('ssm', 'SSM', d.ssm, 'fa-id-card')}
      ${editField('alamat', 'Alamat', d.alamat, 'fa-location-dot', true)}
      ${editField('daerah', 'Daerah', d.daerah, 'fa-map-location-dot')}
      ${editField('negeri', 'Negeri', d.negeri, 'fa-flag')}
      ${editField('tel', 'Telefon', d.ownerContact, 'fa-phone')}
      ${editField('emel', 'Emel', d.emel, 'fa-envelope')}
      ${editField('pass', 'Password', d.password, 'fa-key')}
    ` : `
      ${infoRow('Pemilik', d.ownerName || '-')}
      ${infoRow('SSM', d.ssm || '-')}
      ${infoRow('Alamat', d.alamat || '-')}
      ${infoRow('Daerah', d.daerah || '-')}
      ${infoRow('Negeri', d.negeri || '-')}
      ${infoRow('Telefon', d.ownerContact || '-')}
      ${infoRow('Emel', d.emel || '-')}
      <div class="sa-info-row">
        <span class="lbl">Password</span>
        <span class="val" style="font-family:monospace">${escapeHtml(pwShown)}</span>
        <button class="icon-btn" id="togglePw" style="width:28px;height:28px" title="Tukar papar"><i class="fas ${showPass ? 'fa-eye-slash' : 'fa-eye'}"></i></button>
      </div>
      <hr style="border:0;border-top:1px solid var(--border);margin:10px 0">
      <div style="display:flex;align-items:center;gap:6px;margin-bottom:6px">
        <i class="fas fa-user-shield" style="color:var(--cyan);font-size:11px"></i>
        <span style="color:var(--cyan);font-size:10px;font-weight:900;letter-spacing:0.8px">SUPERVISOR</span>
      </div>
      ${infoRow('Tel SV', d.svTel || '-')}
      <div class="sa-info-row">
        <span class="lbl">Pass SV</span>
        <span class="val" style="font-family:monospace">${escapeHtml(svShown)}</span>
      </div>
    `;

    return `
      <div class="sa-section">
        <div class="sa-section__head">
          <div class="sa-section__title"><i class="fas fa-circle-info"></i>MAKLUMAT ASAS</div>
          ${pill}
        </div>
        <div class="sa-id-row"><i class="fas fa-id-badge" style="color:var(--orange)"></i><span class="lbl">Owner ID / Username</span><span class="val">${escapeHtml(d.id || '-')}</span></div>
        <div class="sa-id-row"><i class="fas fa-shop" style="color:var(--primary)"></i><span class="lbl">Shop ID</span><span class="val">${escapeHtml(d.shopID || 'MAIN')}</span></div>
        <div style="height:6px"></div>
        ${body}
      </div>
    `;
  }

  function sectionPackages() {
    const d = curD;
    const proStatus = d.proMode ? `<span style="color:var(--green)">AKTIF</span> · Tamat ${escapeHtml(formatDate(d.proModeExpire))} (${escapeHtml(bakiHari(d.proModeExpire))})` : `<span style="color:var(--text-dim)">TIDAK AKTIF</span>`;
    const galStatus = d.addonGallery ? `<span style="color:var(--green)">AKTIF</span> · Tamat ${escapeHtml(formatDate(d.galleryExpire))} (${escapeHtml(bakiHari(d.galleryExpire))})` : `<span style="color:var(--text-dim)">TIDAK AKTIF</span>`;
    return `
      <div class="sa-section">
        <div class="sa-section__head">
          <div class="sa-section__title"><i class="fas fa-crown" style="color:#a855f7"></i>PAKEJ PRO</div>
        </div>
        <div class="sa-status-line">Status: ${proStatus}</div>
        <div class="sa-pack-row">
          ${[7,30,90,365].map(n => `<button class="sa-pack-btn" data-pack="pro" data-days="${n}">+${n} hari</button>`).join('')}
          <button class="sa-pack-btn is-off" data-pack="pro" data-days="0"><i class="fas fa-power-off"></i> Tutup</button>
        </div>
      </div>
      <div class="sa-section">
        <div class="sa-section__head">
          <div class="sa-section__title"><i class="fas fa-images" style="color:var(--yellow)"></i>ADDON GALLERY</div>
        </div>
        <div class="sa-status-line">Status: ${galStatus}</div>
        <div class="sa-pack-row">
          ${[7,30,90,365].map(n => `<button class="sa-pack-btn" data-pack="gallery" data-days="${n}">+${n} hari</button>`).join('')}
          <button class="sa-pack-btn is-off" data-pack="gallery" data-days="0"><i class="fas fa-power-off"></i> Tutup</button>
        </div>
      </div>
    `;
  }

  function sectionStaffMode() {
    const d = curD;
    return `
      <div class="sa-section">
        <div class="sa-section__head">
          <div class="sa-section__title"><i class="fas fa-users" style="color:var(--cyan)"></i>MOD PEKERJA</div>
        </div>
        <div class="sa-pack-row">
          <button class="sa-pack-btn ${d.singleStaffMode ? '' : 'is-off'}" data-staff="1" style="${d.singleStaffMode ? 'border-color:rgba(0,196,125,0.4);background:rgba(0,196,125,0.1);color:var(--primary)' : ''}"><i class="fas fa-user"></i> Single Staff</button>
          <button class="sa-pack-btn ${!d.singleStaffMode ? '' : 'is-off'}" data-staff="0" style="${!d.singleStaffMode ? 'border-color:rgba(0,196,125,0.4);background:rgba(0,196,125,0.1);color:var(--primary)' : ''}"><i class="fas fa-users"></i> Multi Staff</button>
        </div>
      </div>
    `;
  }

  function sectionExpire() {
    const d = curD;
    const col = expiryColor(d.expireDate);
    const curDateIso = toDateInputValue(d.expireDate);
    return `
      <div class="sa-section">
        <div class="sa-section__head">
          <div class="sa-section__title"><i class="fas fa-calendar-day" style="color:var(--orange)"></i>TARIKH LUPUT LANGGANAN</div>
        </div>
        <div class="sa-status-line" style="color:${col}">${escapeHtml(formatDate(d.expireDate))} · ${escapeHtml(bakiHari(d.expireDate))}</div>
        <div class="sa-edit-field">
          <i class="fas fa-calendar"></i>
          <input type="date" id="expireInput" value="${escapeHtml(curDateIso)}">
          <button class="btn btn-primary btn-sm" id="expireSave" style="min-width:80px"><i class="fas fa-check"></i> SIMPAN</button>
        </div>
      </div>
    `;
  }

  function sectionModules() {
    const d = curD;
    const em = (d.enabledModules && typeof d.enabledModules === 'object') ? d.enabledModules : {};
    const isOn = (id) => Object.keys(em).length === 0 ? true : em[id] !== false;
    return `
      <div class="sa-section">
        <div class="sa-section__head">
          <div class="sa-section__title"><i class="fas fa-th-large" style="color:var(--indigo)"></i>MODUL DIBENARKAN</div>
        </div>
        ${MODUL_LIST.map(m => `
          <div class="sa-module-row">
            <span class="lbl">${escapeHtml(m.label)}</span>
            <label class="switch"><input type="checkbox" data-mod="${escapeHtml(m.id)}" ${isOn(m.id) ? 'checked' : ''}><span class="switch__slider"></span></label>
          </div>
        `).join('')}
      </div>
    `;
  }

  function sectionDanger() {
    const d = curD;
    const isSus = d.status === 'Digantung' || d.status === 'Suspend';
    return `
      <div class="sa-section" style="border-color:rgba(239,68,68,0.3)">
        <div class="sa-section__head">
          <div class="sa-section__title" style="color:var(--red)"><i class="fas fa-triangle-exclamation"></i>ZON BAHAYA</div>
        </div>
        <div class="sa-danger-actions">
          <button class="btn ${isSus ? 'btn-green' : 'btn-orange'}" id="btnSuspend"><i class="fas ${isSus ? 'fa-circle-play' : 'fa-circle-pause'}"></i> ${isSus ? 'AKTIFKAN SEMULA' : 'GANTUNG AKAUN'}</button>
          <button class="btn btn-red" id="btnDelete"><i class="fas fa-trash"></i> PADAM KEKAL</button>
        </div>
      </div>
    `;
  }

  function bindDetailEvents() {
    // edit/save asas
    const pEdit = document.getElementById('pEditSave');
    if (pEdit) pEdit.addEventListener('click', () => {
      if (editAsas) saveAsas(); else { editAsas = true; renderDetail(); }
    });
    const tpw = document.getElementById('togglePw');
    if (tpw) tpw.addEventListener('click', () => { showPass = !showPass; renderDetail(); });

    // packages
    dBody.querySelectorAll('[data-pack]').forEach(b => {
      b.addEventListener('click', () => kemaskiniLangganan(b.dataset.pack, parseInt(b.dataset.days, 10)));
    });

    // staff mode
    dBody.querySelectorAll('[data-staff]').forEach(b => {
      b.addEventListener('click', () => setStaffMode(b.dataset.staff === '1'));
    });

    // expire
    const expBtn = document.getElementById('expireSave');
    if (expBtn) expBtn.addEventListener('click', () => {
      const v = document.getElementById('expireInput').value;
      if (!v) return;
      saveExpire(v);
    });

    // modules
    dBody.querySelectorAll('[data-mod]').forEach(cb => {
      cb.addEventListener('change', () => toggleModule(cb.dataset.mod, cb.checked));
    });

    // danger
    const bSus = document.getElementById('btnSuspend'); if (bSus) bSus.addEventListener('click', detailSuspend);
    const bDel = document.getElementById('btnDelete');  if (bDel) bDel.addEventListener('click', detailDelete);
  }

  // ───── Detail actions ────────────────────────────────────────────────
  async function saveAsas() {
    const get = (id) => (document.getElementById('f_' + id)?.value || '').trim();
    const update = {
      ownerName: get('owner'),
      ssm:       get('ssm'),
      alamat:    get('alamat'),
      daerah:    get('daerah'),
      negeri:    get('negeri'),
      ownerContact: get('tel'),
      emel:      get('emel'),
      username:  curD.id,
      password:  get('pass'),
    };
    try {
      await updateTenantMerged(update);
      try { await updateBranchMerged(update); } catch (_) {}
      Object.assign(curD, { ownerName: update.ownerName, ssm: update.ssm, alamat: update.alamat,
        daerah: update.daerah, negeri: update.negeri, ownerContact: update.ownerContact,
        phone: update.ownerContact, emel: update.emel, email: update.emel, password: update.password });
      editAsas = false;
      renderDetail();
      toast('Maklumat dikemaskini', 'green');
      await silentReload();
    } catch (e) { toast('Ralat: ' + e.message, 'red'); }
  }

  async function kemaskiniLangganan(jenis, hari) {
    if (hari === 0) {
      const ok = await confirmDialog({ title:`Tutup ${jenis.toUpperCase()}?`, msg:`Pasti mahu MENUTUP akses ${jenis.toUpperCase()} untuk kedai ini?`, okText:'Tutup', okClass:'btn-red' });
      if (!ok) return;
    }
    const patch = {};
    if (hari === 0) {
      if (jenis === 'pro') { patch.proMode = false; patch.proModeExpire = 0; }
      else { patch.addonGallery = false; patch.galleryExpire = 0; }
    } else {
      const t = Date.now() + hari * 86400000;
      if (jenis === 'pro') { patch.proMode = true; patch.proModeExpire = t; }
      else { patch.addonGallery = true; patch.galleryExpire = t; }
    }
    try {
      await updateTenantMerged(patch);
      try { await updateBranchMerged(patch); } catch (_) {}
      Object.assign(curD, patch);
      renderDetail();
      toast(`Pakej ${jenis.toUpperCase()} dikemaskini.`, 'green');
      await silentReload();
    } catch (e) { toast('Ralat: ' + e.message, 'red'); }
  }

  async function setStaffMode(isSingle) {
    try {
      await updateTenantMerged({ singleStaffMode: isSingle });
      try { await updateBranchMerged({ singleStaffMode: isSingle }); } catch (_) {}
      curD.singleStaffMode = isSingle;
      renderDetail();
      toast(`Mod ${isSingle ? 'Single' : 'Multi'} Staff aktif.`, 'green');
      await silentReload();
    } catch (e) { toast('Ralat: ' + e.message, 'red'); }
  }

  async function saveExpire(isoDate) {
    try {
      const iso = new Date(isoDate + 'T00:00:00').toISOString();
      await updateTenantMerged({ expireDate: iso });
      try { await updateBranchMerged({ expireDate: iso }); } catch (_) {}
      curD.expireDate = iso;
      renderDetail();
      toast('Tarikh luput dikemaskini.', 'green');
      await silentReload();
    } catch (e) { toast('Ralat: ' + e.message, 'red'); }
  }

  async function toggleModule(id, value) {
    const current = (curD.enabledModules && typeof curD.enabledModules === 'object') ? { ...curD.enabledModules } : {};
    if (Object.keys(current).length === 0) {
      MODUL_LIST.forEach(m => { current[m.id] = true; });
    }
    current[id] = value;
    try {
      await updateTenantMerged({ enabledModules: current });
      try { await window.sb.from('branches').update({ enabled_modules: current }).eq('tenant_id', curD.id); } catch (_) {
        try { await updateBranchMerged({ enabledModules: current }); } catch (_) {}
      }
      curD.enabledModules = current;
      await silentReload();
    } catch (e) { toast('Ralat: ' + e.message, 'red'); }
  }

  async function detailSuspend() {
    const isSus = curD.status === 'Digantung' || curD.status === 'Suspend';
    const newStatus = isSus ? 'Aktif' : 'Digantung';
    const ok = await confirmDialog({
      title: isSus ? 'AKTIFKAN SEMULA akaun ini?' : 'GANTUNG akaun ini?',
      msg: isSus ? 'Akaun ini akan diaktifkan semula dan boleh digunakan.' : 'Akaun ini akan digantung dan tidak boleh digunakan sementara.',
      okText: isSus ? 'AKTIFKAN' : 'GANTUNG',
      okClass: isSus ? 'btn-green' : 'btn-red',
    });
    if (!ok) return;
    const { error } = await window.sb.from('tenants').update({ status: newStatus }).eq('id', curD.id);
    if (error) return toast('Ralat: ' + error.message, 'red');
    curD.status = newStatus;
    renderDetail();
    toast(`Akaun ${isSus ? 'diaktifkan' : 'digantung'}.`, isSus ? 'green' : 'orange');
    await silentReload();
  }

  async function detailDelete() {
    const ok1 = await confirmDialog({ title:'PADAM AKAUN?', msg:`Anda pasti mahu MEMADAM akaun "${escapeHtml(curD.namaKedai || '')}"? Tindakan ini TIDAK BOLEH dibatalkan.`, okText:'Ya, Padam', okClass:'btn-red' });
    if (!ok1) return;
    const ok2 = await confirmDialog({ title:'PENGESAHAN AKHIR', msg:'Ini adalah pengesahan AKHIR. Semua data akaun akan dipadam secara kekal.', okText:'PADAM KEKAL', okClass:'btn-red' });
    if (!ok2) return;
    const { error } = await window.sb.from('tenants').delete().eq('id', curD.id);
    if (error) return toast('Ralat: ' + error.message, 'red');
    toast('Akaun dipadam.', 'green');
    closeDetail();
    await load();
  }

  // ───── Supabase helpers (tenant + branch merged) ─────────────────────
  const TENANT_COL_KEYS = { status: 'status', singleStaffMode: 'single_staff_mode', expireDate: 'expire_date' };
  const BRANCH_COLS = { phone: 'phone', email: 'email', alamat: 'alamat', singleStaffMode: 'single_staff_mode', expireDate: 'expire_date', enabledModules: 'enabled_modules' };

  async function updateTenantMerged(update) {
    const cols = {}, configPatch = {};
    Object.entries(update).forEach(([k, v]) => {
      if (TENANT_COL_KEYS[k]) cols[TENANT_COL_KEYS[k]] = v;
      else configPatch[k] = v;
    });
    const { data: existing } = await window.sb.from('tenants').select('config').eq('id', curD.id).maybeSingle();
    const config = (existing && existing.config && typeof existing.config === 'object') ? { ...existing.config } : {};
    Object.assign(config, configPatch);
    const patch = { config, ...cols };
    const { error } = await window.sb.from('tenants').update(patch).eq('id', curD.id);
    if (error) throw error;
  }

  async function updateBranchMerged(update) {
    const shop = curD.shopID || 'MAIN';
    const { data: branch } = await window.sb.from('branches').select('id, extras').eq('tenant_id', curD.id).eq('shop_code', shop).maybeSingle();
    if (!branch) return;
    const extras = (branch.extras && typeof branch.extras === 'object') ? { ...branch.extras } : {};
    const cols = {};
    Object.entries(update).forEach(([k, v]) => {
      if (BRANCH_COLS[k]) cols[BRANCH_COLS[k]] = v;
      else extras[k] = v;
    });
    cols.extras = extras;
    const { error } = await window.sb.from('branches').update(cols).eq('id', branch.id);
    if (error) throw error;
  }

  async function silentReload() {
    const { data } = await window.sb.from('tenants').select('*').order('created_at', { ascending: false }).limit(FETCH_BATCH);
    dealers = (data || []).map(tenantToUi);
    applyFilter();
  }

  // ───── Dialogs / toast ──────────────────────────────────────────────
  function confirmDialog({ title, msg, okText, okClass }) {
    return new Promise(resolve => {
      document.getElementById('confirmTitle').textContent = title;
      document.getElementById('confirmMsg').innerHTML = msg;
      const okBtn = document.getElementById('confirmOk');
      okBtn.textContent = okText || 'OK';
      okBtn.className = 'btn ' + (okClass || 'btn-primary');
      confirmModal.classList.remove('hidden');
      const cleanup = (v) => {
        okBtn.removeEventListener('click', onOk);
        document.getElementById('confirmCancel').removeEventListener('click', onCancel);
        confirmModal.classList.add('hidden');
        resolve(v);
      };
      const onOk = () => cleanup(true);
      const onCancel = () => cleanup(false);
      okBtn.addEventListener('click', onOk);
      document.getElementById('confirmCancel').addEventListener('click', onCancel);
    });
  }

  function toast(msg, color) {
    const bgs = { green: 'var(--green)', red: 'var(--red)', orange: 'var(--orange)' };
    const el = document.createElement('div');
    el.className = 'admin-toast';
    if (color && bgs[color]) el.style.background = bgs[color];
    el.innerHTML = `<i class="fas fa-circle-check"></i> ${escapeHtml(msg)}`;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2800);
  }

  // ───── Helpers ──────────────────────────────────────────────────────
  function editField(id, label, val, icon, multiline) {
    const v = escapeHtml(val || '');
    const field = multiline
      ? `<textarea id="f_${id}" rows="2" placeholder="${escapeHtml(label)}">${v}</textarea>`
      : `<input id="f_${id}" type="text" placeholder="${escapeHtml(label)}" value="${v}">`;
    return `<div class="sa-edit-field"><i class="fas ${icon}"></i>${field}</div>`;
  }
  function infoRow(lbl, val) {
    return `<div class="sa-info-row"><span class="lbl">${escapeHtml(lbl)}</span><span class="val">${escapeHtml(val)}</span></div>`;
  }
  function toMs(ts) {
    if (!ts) return 0;
    if (typeof ts === 'number') return ts;
    const d = new Date(ts); return isNaN(d.getTime()) ? 0 : d.getTime();
  }
  function formatDate(ts) {
    const ms = toMs(ts); if (!ms) return '-';
    const d = new Date(ms);
    const m = ['Jan','Feb','Mac','Apr','Mei','Jun','Jul','Ogs','Sep','Okt','Nov','Dis'];
    return `${String(d.getDate()).padStart(2,'0')} ${m[d.getMonth()]} ${d.getFullYear()}`;
  }
  function toDateInputValue(ts) {
    const ms = toMs(ts); if (!ms) return '';
    const d = new Date(ms);
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  }
  function bakiHari(ts) {
    const ms = toMs(ts); if (!ms) return '-';
    const diff = Math.floor((ms - Date.now()) / 86400000);
    if (diff < 0) return 'Tamat Tempoh';
    if (diff === 0) return 'Luput Hari Ini';
    return `${diff} Hari Lagi`;
  }
  function expiryColor(ts) {
    const ms = toMs(ts); if (!ms) return 'var(--text-dim)';
    const diff = Math.floor((ms - Date.now()) / 86400000);
    return diff <= 7 ? 'var(--red)' : 'var(--green)';
  }
  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }
})();
