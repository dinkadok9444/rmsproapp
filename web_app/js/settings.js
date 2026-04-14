/* Settings — port lib/screens/modules/settings_screen.dart */
(function () {
  'use strict';

  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerID, shopID] = branch.split('@');

  // ---- Color presets (sama dengan Flutter) ----
  const COLORS = [
    '#0D9488','#059669','#2563EB','#6366F1','#7C3AED',
    '#DC2626','#EA580C','#CA8A04','#0891B2','#1E293B',
  ];
  // Template names + tema warna sama dengan settings_screen.dart:1028
  const TEMPLATES = [
    { id: 'tpl_1',  name: 'Standard',   color: '#FF6600' },
    { id: 'tpl_2',  name: 'Moden',      color: '#2563EB' },
    { id: 'tpl_3',  name: 'Klasik',     color: '#374151' },
    { id: 'tpl_4',  name: 'Minimalis',  color: '#64748B' },
    { id: 'tpl_5',  name: 'Komersial',  color: '#DC2626' },
    { id: 'tpl_6',  name: 'Elegan',     color: '#92400E' },
    { id: 'tpl_7',  name: 'Tengah',     color: '#7C3AED' },
    { id: 'tpl_8',  name: 'Kompak',     color: '#0D9488' },
    { id: 'tpl_9',  name: 'Korporat',   color: '#1E3A5F' },
    { id: 'tpl_10', name: 'Kreatif',    color: '#EC4899' },
  ];
  let TPL_IMAGES = {}; // diisi dari config/pdf_templates

  // ---- State ----
  let original = {};
  let current  = {};
  let originalAdmin = {};
  let currentAdmin  = {};

  // ---- Build color & template grids ----
  const colorGrid = document.getElementById('colorGrid');
  colorGrid.innerHTML = COLORS.map(c => `<button class="color-chip" type="button" data-color="${c}" style="background:${c}" title="${c}"></button>`).join('');
  colorGrid.addEventListener('click', (e) => {
    const chip = e.target.closest('.color-chip');
    if (!chip) return;
    current.themeColor = chip.dataset.color;
    refreshColor();
    markDirty();
    // Live update header parent
    try { window.parent.postMessage({ type: 'theme', color: current.themeColor }, '*'); } catch (_) {}
  });

  const tplGrid = document.getElementById('tplGrid');
  function renderTplGrid() {
    tplGrid.innerHTML = TEMPLATES.map((t) => {
      const img = TPL_IMAGES[t.id];
      const inner = img
        ? `<img src="${img}" alt="${t.name}" loading="lazy">`
        : `<i class="fas fa-file-pdf"></i>`;
      return `
        <button class="tpl-chip" type="button" data-tpl="${t.id}" style="--tpl-color:${t.color}">
          <span class="tpl-chip__check"><i class="fas fa-check"></i></span>
          <span class="tpl-chip__img">${inner}</span>
          <span class="tpl-chip__caption">${t.name}</span>
        </button>`;
    }).join('');
    refreshTpl();
  }
  renderTplGrid();
  tplGrid.addEventListener('click', (e) => {
    const chip = e.target.closest('.tpl-chip');
    if (!chip) return;
    current.templatePdf = chip.dataset.tpl;
    refreshTpl();
    markDirty();
  });

  function refreshColor() {
    document.querySelectorAll('.color-chip').forEach(c => c.classList.toggle('is-active', c.dataset.color === current.themeColor));
  }
  function refreshTpl() {
    document.querySelectorAll('.tpl-chip').forEach(c => c.classList.toggle('is-active', c.dataset.tpl === current.templatePdf));
  }

  // ---- Field bindings (current = state, dirty = save bar) ----
  const inputs = {
    fPhone:        'phone',
    fStaffBox:     'staffBoxCount',
    fNotaInvoice:  'notaInvoice',
    fNotaQuotation:'notaQuotation',
    fNotaClaim:    'notaClaim',
    fNotaBooking:  'notaBooking',
  };
  Object.entries(inputs).forEach(([id, key]) => {
    document.getElementById(id).addEventListener('input', (e) => {
      current[key] = e.target.value;
      markDirty();
    });
  });

  document.getElementById('fLang').addEventListener('change', (e) => {
    localStorage.setItem('rms_lang', e.target.value);
    flash('Bahasa disimpan');
  });

  // Admin section bindings
  ['fSvTel','fSvPass'].forEach(id => {
    const key = id === 'fSvTel' ? 'svTel' : 'svPass';
    document.getElementById(id).addEventListener('input', (e) => {
      currentAdmin[key] = e.target.value;
      markDirty();
    });
  });
  document.getElementById('btnTogglePass').addEventListener('click', () => {
    const i = document.getElementById('fSvPass');
    i.type = i.type === 'password' ? 'text' : 'password';
  });

  // ---- Logo upload ----
  const logoPreview = document.getElementById('logoPreview');
  document.getElementById('logoFile').addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (!file) return;
    if (file.size > 500 * 1024) { alert('Saiz logo maksimum 500KB'); return; }
    const reader = new FileReader();
    reader.onload = () => {
      current.logoBase64 = reader.result; // data URI
      renderLogo(reader.result);
      markDirty();
      try { window.parent.postMessage({ type: 'logo', src: reader.result }, '*'); } catch (_) {}
    };
    reader.readAsDataURL(file);
  });
  document.getElementById('logoRemove').addEventListener('click', () => {
    current.logoBase64 = '';
    renderLogo(null);
    markDirty();
    try { window.parent.postMessage({ type: 'logo', src: '' }, '*'); } catch (_) {}
  });
  function renderLogo(src) {
    logoPreview.innerHTML = src ? `<img src="${src}" alt="logo">` : '<i class="fas fa-image"></i>';
  }

  // ---- Save bar ----
  const saveBar = document.getElementById('saveBar');
  function markDirty() { saveBar.classList.remove('is-hidden'); }
  function markClean() { saveBar.classList.add('is-hidden'); }

  document.getElementById('btnReset').addEventListener('click', () => {
    current = { ...original };
    currentAdmin = { ...originalAdmin };
    populate();
    markClean();
  });

  document.getElementById('btnSave').addEventListener('click', async () => {
    const btn = document.getElementById('btnSave');
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-circle-notch fa-spin"></i> Menyimpan…';
    try {
      const payload = {};
      ['phone','staffBoxCount','templatePdf','notaInvoice','notaQuotation','notaClaim','notaBooking','themeColor','logoBase64']
        .forEach(k => { if (current[k] !== original[k]) payload[k] = current[k] ?? ''; });
      if (Object.keys(payload).length) {
        await db.collection('shops_' + ownerID).doc(shopID).set(payload, { merge: true });
      }
      const adminPayload = {};
      ['svTel','svPass'].forEach(k => { if (currentAdmin[k] !== originalAdmin[k]) adminPayload[k] = currentAdmin[k] ?? ''; });
      if (Object.keys(adminPayload).length) {
        await db.collection('saas_dealers').doc(ownerID).set(adminPayload, { merge: true });
      }
      original = { ...current };
      originalAdmin = { ...currentAdmin };
      flash('Tersimpan ✓');
      markClean();
    } catch (err) {
      alert('Ralat menyimpan: ' + err.message);
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<i class="fas fa-floppy-disk"></i> Simpan Perubahan';
    }
  });

  function flash(msg) {
    const t = document.createElement('div');
    t.textContent = msg;
    Object.assign(t.style, {
      position: 'fixed', bottom: '90px', left: '50%', transform: 'translateX(-50%)',
      background: '#0F172A', color: '#fff', padding: '10px 20px', borderRadius: '999px',
      fontSize: '13px', fontWeight: '700', zIndex: 100, boxShadow: '0 8px 20px rgba(0,0,0,.2)'
    });
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2000);
  }

  // ---- Populate from Firestore ----
  function populate() {
    document.getElementById('fShopName').textContent = original.shopName || original.namaKedai || '—';
    document.getElementById('fSsm').textContent      = original.ssm || '—';
    document.getElementById('fAddress').textContent  = original.address || original.alamat || '—';
    document.getElementById('fEmail').textContent    = original.email || '—';
    document.getElementById('fBranchId').textContent = branch;
    document.getElementById('fPhone').value          = current.phone || '';
    document.getElementById('fStaffBox').value       = String(current.staffBoxCount || '1');
    document.getElementById('fNotaInvoice').value    = current.notaInvoice || '';
    document.getElementById('fNotaQuotation').value  = current.notaQuotation || '';
    document.getElementById('fNotaClaim').value      = current.notaClaim || '';
    document.getElementById('fNotaBooking').value    = current.notaBooking || '';
    document.getElementById('fLang').value           = localStorage.getItem('rms_lang') || 'ms';
    document.getElementById('fSvTel').value          = currentAdmin.svTel || '';
    document.getElementById('fSvPass').value         = currentAdmin.svPass || '';
    renderLogo(current.logoBase64 || null);
    refreshColor();
    refreshTpl();
  }

  async function loadTemplateImages() {
    try {
      const snap = await db.collection('config').doc('pdf_templates').get();
      if (!snap.exists) return;
      const d = snap.data() || {};
      TPL_IMAGES = {};
      TEMPLATES.forEach(t => { if (d[t.id]) TPL_IMAGES[t.id] = d[t.id]; });
      renderTplGrid();
    } catch (e) { console.warn('pdf_templates:', e); }
  }

  async function load() {
    loadTemplateImages(); // parallel
    const data = {};
    try {
      const dealer = await db.collection('saas_dealers').doc(ownerID).get();
      if (dealer.exists) Object.assign(data, dealer.data());
    } catch (e) { console.warn(e); }
    try {
      const shop = await db.collection('shops_' + ownerID).doc(shopID).get();
      if (shop.exists) Object.assign(data, shop.data());
    } catch (e) { console.warn(e); }

    original = {
      phone: data.phone || '',
      staffBoxCount: String(data.staffBoxCount || '1'),
      templatePdf: data.templatePdf || 'tpl_1',
      themeColor: data.themeColor || '#0D9488',
      logoBase64: data.logoBase64 || '',
      notaInvoice: data.notaInvoice || '',
      notaQuotation: data.notaQuotation || '',
      notaClaim: data.notaClaim || '',
      notaBooking: data.notaBooking || '',
      shopName: data.shopName, namaKedai: data.namaKedai,
      ssm: data.ssm,
      address: data.address, alamat: data.alamat,
      email: data.email,
    };
    originalAdmin = { svTel: data.svTel || '', svPass: data.svPass || '' };
    current = { ...original };
    currentAdmin = { ...originalAdmin };
    populate();
  }

  load();
})();
