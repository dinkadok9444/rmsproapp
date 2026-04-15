/* Admin → Suis Modul SaaS. Mirror rmsproapp/lib/screens/admin_modules/suis_modul_screen.dart.
   Table: saas_settings (id='feature_flags', value JSONB). */
(function () {
  'use strict';

  const FLAGS = [
    { key: 'marketplace', icon: 'fa-store',    color: 'purple', title: 'Marketplace', desc: 'Platform jual beli antara kedai.',      defaultVal: false },
    { key: 'chat',        icon: 'fa-comments', color: 'green',  title: 'Dealer Support', desc: 'Chat sokongan antara user & Dealer Support.', defaultVal: true  },
  ];

  const SETTINGS_ID = 'feature_flags';
  const listEl = document.getElementById('flagList');

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    const { data, error } = await window.sb
      .from('saas_settings')
      .select('value')
      .eq('id', SETTINGS_ID)
      .maybeSingle();
    if (error) { listEl.innerHTML = `<div class="admin-error">${error.message}</div>`; return; }
    const raw = (data && data.value) || {};
    const flags = {};
    for (const f of FLAGS) flags[f.key] = raw[f.key] === undefined ? f.defaultVal : !!raw[f.key];
    render(flags);
  }

  function render(flags) {
    listEl.innerHTML = FLAGS.map(f => `
      <div class="flag-tile">
        <span class="flag-tile__icon bg-${f.color}"><i class="fas ${f.icon}"></i></span>
        <div class="flag-tile__body">
          <div class="flag-tile__title">${f.title}</div>
          <div class="flag-tile__desc">${f.desc}</div>
        </div>
        <label class="switch">
          <input type="checkbox" data-key="${f.key}" ${flags[f.key] ? 'checked' : ''}>
          <span class="switch__slider"></span>
        </label>
      </div>
    `).join('');

    listEl.querySelectorAll('input[type="checkbox"]').forEach(cb => {
      cb.addEventListener('change', async (e) => {
        const key = e.target.dataset.key;
        const val = e.target.checked;
        e.target.disabled = true;
        try {
          await setFlag(key, val);
        } catch (err) {
          e.target.checked = !val;
          alert('Gagal: ' + err.message);
        } finally {
          e.target.disabled = false;
        }
      });
    });
  }

  async function setFlag(key, value) {
    const { data: existing } = await window.sb
      .from('saas_settings')
      .select('value')
      .eq('id', SETTINGS_ID)
      .maybeSingle();
    const merged = Object.assign({}, (existing && existing.value) || {});
    merged[key] = value;
    const { error } = await window.sb
      .from('saas_settings')
      .upsert({ id: SETTINGS_ID, value: merged });
    if (error) throw error;
  }
})();
