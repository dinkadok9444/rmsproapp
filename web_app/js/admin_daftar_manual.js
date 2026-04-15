/* Admin → Daftar Manual. Mirror admin_modules/daftar_manual_screen.dart.
   Tables: tenants (insert: owner_id, nama_kedai, password_hash, status, active, expire_date, config),
           branches (insert: tenant_id, shop_code, nama_kedai, email, phone, alamat, enabled_modules, extras, active). */
(function () {
  'use strict';

  const NEGERI = [
    'Johor','Kedah','Kelantan','Melaka','Negeri Sembilan',
    'Pahang','Perak','Perlis','Pulau Pinang','Sabah',
    'Sarawak','Selangor','Terengganu',
    'WP Kuala Lumpur','WP Putrajaya','WP Labuan',
  ];
  const STATE_CODE = {
    'Johor':'JHR','Kedah':'KDH','Kelantan':'KTN','Melaka':'MLK','Negeri Sembilan':'NSN',
    'Pahang':'PHG','Perak':'PRK','Perlis':'PLS','Pulau Pinang':'PNG','Sabah':'SBH',
    'Sarawak':'SWK','Selangor':'SGR','Terengganu':'TRG',
    'WP Kuala Lumpur':'KUL','WP Putrajaya':'PJY','WP Labuan':'LBN',
  };
  const DURATION_MONTHS = { '1 bulan':1, '6 bulan':6, '12 bulan':12 };
  const DEFAULT_MODULES = {
    widget:true, Stock:true, DB_Cust:true, Booking:true,
    Claim_warranty:true, Collab:true, Profesional:true, Refund:true,
    Lost:true, MaklumBalas:true, Link:true, Fungsi_lain:true, Settings:true,
  };

  const listEl = document.getElementById('dealerList');
  const countEl = document.getElementById('dealerCount');
  const modal = document.getElementById('addModal');
  let dealers = [];

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnReload').addEventListener('click', load);
  document.getElementById('btnAdd').addEventListener('click', openModal);
  document.getElementById('btnSubmit').addEventListener('click', submit);
  modal.querySelectorAll('[data-close]').forEach(el => el.addEventListener('click', closeModal));

  // Populate dropdowns
  document.getElementById('fNegeri').innerHTML = NEGERI.map(n => `<option value="${n}"${n==='Selangor'?' selected':''}>${n}</option>`).join('');

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    listEl.innerHTML = `<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i> Memuat…</div>`;
    const { data, error } = await window.sb
      .from('tenants')
      .select('id, owner_id, nama_kedai, status, expire_date, config')
      .order('created_at', { ascending: false })
      .limit(500);
    if (error) { listEl.innerHTML = `<div class="admin-error">${escapeHtml(error.message)}</div>`; return; }
    dealers = (data || []).map(r => {
      const c = (r.config && typeof r.config === 'object') ? r.config : {};
      return {
        id: r.id,
        ownerID: r.owner_id || '',
        namaKedai: r.nama_kedai || '',
        ownerName: c.ownerName || '',
        ownerContact: c.ownerContact || '',
        daerah: c.daerah || '',
        negeri: c.negeri || '',
        status: r.status || 'Aktif',
        expiry: r.expire_date || '',
      };
    });
    dealers.sort((a, b) => a.namaKedai.toLowerCase().localeCompare(b.namaKedai.toLowerCase()));
    render();
  }

  function render() {
    countEl.textContent = `${dealers.length} dealer berdaftar`;
    if (!dealers.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-user-plus" style="font-size:24px;color:var(--text-dim);opacity:0.5;display:block;margin-bottom:8px"></i>Belum ada dealer<div style="font-size:10px;color:var(--text-dim);margin-top:4px">Tekan "Tambah" untuk daftar dealer baru</div></div>`;
      return;
    }
    listEl.innerHTML = dealers.map(card).join('');
  }

  function card(d) {
    const isActive = d.status === 'Aktif';
    const expiryStr = fmtDate(d.expiry);
    return `
      <div class="reg-card ${isActive ? 'is-active' : 'is-inactive'}">
        <div class="reg-card__head">
          <div class="reg-card__main">
            <div class="reg-card__name">${escapeHtml(d.namaKedai)}</div>
            <div class="reg-card__id">${escapeHtml(d.ownerID)}</div>
          </div>
          <span class="reg-badge ${isActive ? 'is-active' : 'is-inactive'}">${isActive ? 'Aktif' : 'Tidak Aktif'}</span>
        </div>
        <div class="reg-card__row">
          <span><i class="fas fa-user"></i> ${escapeHtml(d.ownerName || '-')}</span>
          <span><i class="fas fa-phone"></i> ${escapeHtml(d.ownerContact || '-')}</span>
        </div>
        <div class="reg-card__row">
          <span><i class="fas fa-location-dot"></i> ${escapeHtml(((d.daerah||'') + (d.negeri ? ', '+d.negeri : '')) || '-')}</span>
          <span class="reg-card__expiry"><i class="fas fa-calendar-check"></i> Tamat: ${escapeHtml(expiryStr)}</span>
        </div>
      </div>
    `;
  }

  function openModal() {
    ['fSystemId','fPassword','fOwnerName','fOwnerPhone','fShopName','fShopEmail','fShopPhone','fDistrict','fAddress'].forEach(id => document.getElementById(id).value = '');
    document.getElementById('fNegeri').value = 'Selangor';
    document.getElementById('fDuration').value = '1 bulan';
    document.getElementById('fSystemIdErr').classList.add('hidden');
    modal.classList.remove('hidden');
  }

  function closeModal() { modal.classList.add('hidden'); }

  async function submit() {
    const btn = document.getElementById('btnSubmit');
    const errEl = document.getElementById('fSystemIdErr');
    const systemId = document.getElementById('fSystemId').value.trim().toLowerCase();
    const password = document.getElementById('fPassword').value.trim();
    const ownerName = document.getElementById('fOwnerName').value.trim();
    const ownerPhone = document.getElementById('fOwnerPhone').value.trim();
    const shopName = document.getElementById('fShopName').value.trim();
    const shopEmail = document.getElementById('fShopEmail').value.trim();
    const shopPhone = document.getElementById('fShopPhone').value.trim();
    const district = document.getElementById('fDistrict').value.trim();
    const address = document.getElementById('fAddress').value.trim();
    const negeri = document.getElementById('fNegeri').value;
    const duration = document.getElementById('fDuration').value;

    errEl.classList.add('hidden');

    if (!systemId || !password || !ownerName || !shopName) {
      toast('Sila isi semua maklumat wajib', true);
      return;
    }
    if (!/^[a-z0-9]+$/.test(systemId)) {
      errEl.textContent = 'Hanya huruf kecil dan nombor sahaja';
      errEl.classList.remove('hidden');
      return;
    }

    const orig = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> MENYIMPAN…';
    try {
      const { data: existing } = await window.sb.from('tenants').select('id').eq('owner_id', systemId).maybeSingle();
      if (existing) {
        errEl.textContent = 'System ID ini sudah wujud';
        errEl.classList.remove('hidden');
        return;
      }

      const months = DURATION_MONTHS[duration] || 1;
      const expiry = new Date(); expiry.setDate(expiry.getDate() + months * 30);
      const shopID = generateShopID(negeri);

      const { data: t, error: tErr } = await window.sb.from('tenants').insert({
        owner_id: systemId,
        nama_kedai: shopName,
        password_hash: password,
        status: 'Aktif',
        active: true,
        expire_date: expiry.toISOString(),
        config: {
          enabledModules: DEFAULT_MODULES,
          ownerName, ownerContact: ownerPhone,
          email: shopEmail, daerah: district, negeri, alamat: address,
          duration,
        },
      }).select('id').single();
      if (tErr) throw tErr;

      const { error: bErr } = await window.sb.from('branches').insert({
        tenant_id: t.id,
        shop_code: shopID,
        nama_kedai: shopName,
        email: shopEmail,
        phone: shopPhone,
        alamat: address,
        enabled_modules: DEFAULT_MODULES,
        extras: { daerah: district, negeri },
        active: true,
      });
      if (bErr) throw bErr;

      closeModal();
      toast(`Pendaftaran berjaya! ID: ${systemId} / Shop: ${shopID}`);
      await load();
    } catch (e) {
      toast('Ralat: ' + (e.message || e), true);
    } finally {
      btn.disabled = false;
      btn.innerHTML = orig;
    }
  }

  function generateShopID(negeri) {
    const code = STATE_CODE[negeri] || 'XXX';
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let suffix = '';
    for (let i = 0; i < 5; i++) suffix += chars[Math.floor(Math.random() * chars.length)];
    return `${code}-${suffix}`;
  }

  function fmtDate(v) {
    if (!v) return '-';
    const d = new Date(v); if (isNaN(d.getTime())) return '-';
    return `${d.getDate()}/${d.getMonth()+1}/${d.getFullYear()}`;
  }

  function toast(msg, err) {
    const t = document.createElement('div');
    t.className = 'admin-toast';
    if (err) t.style.background = 'var(--red)';
    t.innerHTML = `<i class="fas fa-${err ? 'circle-exclamation' : 'circle-check'}"></i> ${escapeHtml(msg)}`;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2800);
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }
})();
