/* Supabase client — mirror config dengan rmsproapp/lib/services/supabase_config.dart */
/* Load via: <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script> sebelum file ni */

const SUPABASE_URL = 'https://lpurtgmqecabgwwenikb.supabase.co';
// Anon key — selamat expose, RLS yang guard data
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxwdXJ0Z21xZWNhYmd3d2VuaWtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODQ2MTUsImV4cCI6MjA5MTc2MDYxNX0.7FiqQwNJC6XXv0r8Emmt9KyygOnHfSrXVirsJBIsdhU';

window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, storageKey: 'rmspro-web-auth' },
});

/* ─── Helpers ───────────────────────────────────────────────────────────── */

/** Dapat tenant_id + branch_id current user (from users table). Cache dalam memori. */
let _currentUserCtx = null;
window.getCurrentUserCtx = async function () {
  if (_currentUserCtx) return _currentUserCtx;
  const { data: { user } } = await window.sb.auth.getUser();
  if (!user) return null;
  const { data } = await window.sb
    .from('users')
    .select('id, tenant_id, role, current_branch_id, nama, phone')
    .eq('id', user.id)
    .single();
  if (!data) return null;
  _currentUserCtx = { ...data, email: user.email };
  return _currentUserCtx;
};

window.clearUserCtx = function () {
  _currentUserCtx = null;
};

/** Require login — redirect ke index.html kalau belum auth. */
window.requireAuth = async function () {
  const ctx = await window.getCurrentUserCtx();
  if (!ctx) {
    window.location.href = '/index.html';
    return null;
  }
  return ctx;
};

/** Resolve tenant by hostname (multi-tenant SaaS). Cache. */
let _tenantByHost = null;
window.getTenantByHostname = async function () {
  if (_tenantByHost !== null) return _tenantByHost;
  const host = window.location.hostname;
  // Skip resolution for known platform hosts → return null so app falls back to auth ctx
  if (host === 'rmspro.net' || host === 'www.rmspro.net' || host === 'app.rmspro.net'
      || host.endsWith('.pages.dev') || host === 'localhost' || host === '127.0.0.1') {
    _tenantByHost = null;
    return null;
  }
  const { data } = await window.sb
    .from('tenants')
    .select('id, owner_id, shop_name, domain, subdomain, config, domain_status')
    .or(`domain.eq.${host},subdomain.eq.${host.split('.')[0]}`)
    .maybeSingle();
  _tenantByHost = data || null;
  if (_tenantByHost && _tenantByHost.config) {
    // Apply branding (page theme) jika ada
    try {
      const themes = _tenantByHost.config.pageThemes || {};
      const g = themes.global || {};
      if (g.bg) document.documentElement.style.setProperty('--brand-bg', g.bg);
      if (g.text) document.documentElement.style.setProperty('--brand-text', g.text);
      if (g.accent) document.documentElement.style.setProperty('--brand-accent', g.accent);
    } catch (_) {}
  }
  return _tenantByHost;
};

/** Logout. */
window.doLogout = async function () {
  await window.sb.auth.signOut();
  window.clearUserCtx();
  window.location.href = '/index.html';
};
