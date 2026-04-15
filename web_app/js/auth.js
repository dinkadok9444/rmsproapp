/* Auth — mirror lib/services/auth_service.dart (Supabase). */
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

  const DOMAIN = 'rmspro.internal';

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

  async function signIn(email, password) {
    const { data, error } = await window.sb.auth.signInWithPassword({ email, password });
    if (error) throw new Error(error.message.includes('Invalid') ? 'Katalaluan Salah' : error.message);
    return data.user;
  }

  // ---------- Owner / branch / admin ----------
  ownerForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearError();
    const raw = idEl.value.trim();
    const pass = passEl.value;
    if (!raw || !pass) return showError('Sila isi semua ruangan');

    setLoading(ownerForm, true);
    try {
      let email, destination;

      // 1) Admin
      if (raw.toLowerCase() === 'admin') {
        email = `admin@${DOMAIN}`;
        destination = 'dashboard.html';
      }
      // 2) Branch login "owner@BRANCH"
      else if (raw.includes('@')) {
        const [own, br] = raw.split('@');
        email = `owner.${own.toLowerCase()}.${br.toUpperCase()}@${DOMAIN}`;
        destination = 'branch.html';
      }
      // 3) Owner only — first branch picked auto via users.current_branch_id
      else {
        email = `${raw.toLowerCase()}@${DOMAIN}`;
        destination = 'branch.html';
      }

      await signIn(email, pass);

      // Verify tenant status
      const ctx = await window.getCurrentUserCtx();
      if (!ctx) throw new Error('Akaun tidak sah');
      if (ctx.tenant_id) {
        const { data: tenant } = await window.sb.from('tenants').select('status').eq('id', ctx.tenant_id).single();
        if (tenant && tenant.status && tenant.status !== 'Aktif') {
          await window.sb.auth.signOut();
          throw new Error('Akaun digantung');
        }
      }

      // Owner-only: pick first branch
      if (ctx.role === 'owner' && !ctx.current_branch_id) {
        const { data: branch } = await window.sb
          .from('branches')
          .select('id, shop_code')
          .eq('tenant_id', ctx.tenant_id)
          .limit(1)
          .maybeSingle();
        if (!branch) throw new Error('Sila daftar sekurang-kurangnya satu cawangan.');
        await window.sb.from('users').update({ current_branch_id: branch.id }).eq('id', ctx.id);
        window.clearUserCtx();
      }

      if (remember.checked) localStorage.setItem('rms_saved_id', raw);
      else localStorage.removeItem('rms_saved_id');

      window.location.href = destination;
    } catch (err) {
      showError(err.message || String(err));
      passEl.value = '';
    } finally {
      setLoading(ownerForm, false);
    }
  });

  // ---------- Staff login (phone+pin) ----------
  staffForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearError();
    const phone = phoneEl.value.trim().replace(/[\s\-()]/g, '');
    const pin = pinEl.value.trim();
    if (!phone || !pin) return showError('Sila isi semua ruangan');

    setLoading(staffForm, true);
    try {
      // Check global_staff status dulu
      const { data: gs } = await window.sb
        .from('global_staff')
        .select('status, nama, role, tenant_id, shop_code')
        .eq('phone', phone)
        .maybeSingle();
      if (!gs) throw new Error('No telefon tidak berdaftar');
      if (gs.status === 'suspended') throw new Error('Akaun staf digantung');

      await signIn(`staff.${phone}@${DOMAIN}`, pin);

      window.location.href = 'branch.html';
    } catch (err) {
      showError(err.message || String(err));
      pinEl.value = '';
    } finally {
      setLoading(staffForm, false);
    }
  });
})();
