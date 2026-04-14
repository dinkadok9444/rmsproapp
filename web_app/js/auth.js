/* Auth — port lib/services/auth_service.dart */
(function () {
  'use strict';
  if (!document.getElementById('loginSegment')) return;

  const ownerForm = document.getElementById('ownerForm');
  const staffForm = document.getElementById('staffForm');
  const errorBox  = document.getElementById('loginError');
  const idEl      = document.getElementById('ownerId');
  const passEl    = document.getElementById('ownerPass');
  const remember  = document.getElementById('rememberMe');
  const phoneEl   = document.getElementById('staffPhone');
  const pinEl     = document.getElementById('staffPin');

  // Restore remembered id
  const saved = localStorage.getItem('rms_saved_id');
  if (saved) { idEl.value = saved; remember.checked = true; }

  function showError(msg) {
    errorBox.textContent = msg;
    errorBox.classList.remove('hidden');
  }
  function clearError() { errorBox.classList.add('hidden'); }

  function setLoading(form, on) {
    const btn = form.querySelector('button[type="submit"]');
    btn.disabled = on;
    btn.dataset.label = btn.dataset.label || btn.textContent;
    btn.innerHTML = on ? '<i class="fas fa-circle-notch fa-spin"></i> SEDANG MASUK…' : btn.dataset.label;
  }

  function token() {
    const c = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let t = '';
    for (let i = 0; i < 16; i++) t += c[Math.floor(Math.random() * c.length)];
    return t + Date.now().toString(36);
  }

  // ---------- Owner / branch / admin login ----------
  ownerForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearError();
    const raw = idEl.value.trim();
    const pass = passEl.value;
    if (!raw || !pass) return showError('Sila isi semua ruangan');

    setLoading(ownerForm, true);
    try {
      // 1) Admin
      if (raw.toLowerCase() === 'admin') {
        if (pass !== 'master123') throw new Error('Katalaluan Salah');
        localStorage.setItem('rms_session_token', token());
        localStorage.setItem('rms_user_role', 'admin');
        localStorage.setItem('rms_saved_id', 'admin');
        window.location.href = 'dashboard.html';
        return;
      }

      // 2) Branch login (format: owner@BRANCH)
      if (raw.includes('@')) {
        const [own, br] = raw.split('@');
        const branchId = own.toLowerCase() + '@' + br.toUpperCase();
        const snap = await db.collection('global_branches').doc(branchId).get();
        if (!snap.exists) throw new Error('ID Tidak Wujud');
        const d = snap.data();
        if (pass !== d.pass) throw new Error('Katalaluan Salah');
        finishBranch(branchId, raw);
        return;
      }

      // 3) Owner only — pick first shop
      const ownerID = raw.toLowerCase();
      const snap = await db.collection('saas_dealers').doc(ownerID).get();
      if (!snap.exists) throw new Error('ID Tidak Dijumpai');
      const d = snap.data();
      if (d.status && d.status !== 'Aktif') throw new Error('Akaun digantung');
      if (pass !== d.pass && pass !== d.password) throw new Error('Katalaluan Salah');

      const shops = await db.collection('shops_' + ownerID).limit(1).get();
      if (shops.empty) throw new Error('Sila daftar sekurang-kurangnya satu cawangan.');
      const branchId = ownerID + '@' + shops.docs[0].id;
      finishBranch(branchId, raw);
    } catch (err) {
      showError(err.message || String(err));
      passEl.value = '';
    } finally {
      setLoading(ownerForm, false);
    }
  });

  function finishBranch(branchId, rawInput) {
    localStorage.setItem('rms_session_token', token());
    localStorage.setItem('rms_current_branch', branchId);
    if (remember.checked) localStorage.setItem('rms_saved_id', rawInput);
    else localStorage.removeItem('rms_saved_id');
    window.location.href = 'branch.html';
  }

  // ---------- Staff login ----------
  staffForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearError();
    const phone = phoneEl.value.trim().replace(/[\s\-()]/g, '');
    const pin = pinEl.value.trim();
    if (!phone || !pin) return showError('Sila isi semua ruangan');

    setLoading(staffForm, true);
    try {
      const snap = await db.collection('global_staff').doc(phone).get();
      if (!snap.exists) throw new Error('No telefon tidak berdaftar');
      const d = snap.data();
      if (d.status === 'suspended') throw new Error('Akaun staf digantung');
      if (d.pin !== pin) throw new Error('PIN salah');

      const branchId = (d.ownerID || '') + '@' + (d.shopID || '');
      localStorage.setItem('rms_session_token', token());
      localStorage.setItem('rms_current_branch', branchId);
      localStorage.setItem('rms_staff_name', d.name || '');
      localStorage.setItem('rms_staff_phone', phone);
      localStorage.setItem('rms_staff_role', (d.role || 'staff').toLowerCase());
      window.location.href = 'branch.html';
    } catch (err) {
      showError(err.message || String(err));
      pinEl.value = '';
    } finally {
      setLoading(staffForm, false);
    }
  });
})();
