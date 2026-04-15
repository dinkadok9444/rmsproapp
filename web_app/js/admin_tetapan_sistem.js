/* Admin → Tetapan Sistem. Mirror admin_modules/tetapan_sistem_screen.dart.
   Tables: platform_config (id='courier'|'toyyibpay'|'pdf_default', value JSONB).
   Note: Web admin tiada branch context, jadi PDF settings disimpan sebagai default platform
         dalam platform_config id='pdf_default' (Flutter version simpan ke branches row tertentu). */
(function () {
  'use strict';

  const loadingEl = document.getElementById('tsLoading');
  const contentEl = document.getElementById('tsContent');

  const delyvaKey = document.getElementById('delyvaKey');
  const delyvaCustomer = document.getElementById('delyvaCustomer');
  const delyvaCompany = document.getElementById('delyvaCompany');
  const badgeDelyva = document.getElementById('badgeDelyva');

  const toyyibSecret = document.getElementById('toyyibSecret');
  const toyyibCat = document.getElementById('toyyibCat');
  const toyyibSandbox = document.getElementById('toyyibSandbox');
  const toyyibSandboxLabel = document.getElementById('toyyibSandboxLabel');
  const badgeToyyib = document.getElementById('badgeToyyib');

  const pdfUrl = document.getElementById('pdfUrl');
  const pdfCustom = document.getElementById('pdfCustom');
  const pdfCustomLabel = document.getElementById('pdfCustomLabel');
  const badgePdf = document.getElementById('badgePdf');

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnSave').addEventListener('click', saveAll);

  // Eye toggles
  document.querySelectorAll('.ts-eye').forEach(b => b.addEventListener('click', () => {
    const t = document.getElementById(b.dataset.target);
    const show = t.type === 'password';
    t.type = show ? 'text' : 'password';
    b.querySelector('i').className = show ? 'fas fa-eye-slash' : 'fas fa-eye';
  }));

  // Live badges
  delyvaKey.addEventListener('input', updateBadges);
  toyyibSecret.addEventListener('input', updateBadges);
  toyyibSandbox.addEventListener('change', updateBadges);
  pdfCustom.addEventListener('change', updateBadges);

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await loadAll();
  })();

  async function loadAll() {
    try {
      const [courier, toyyib, pdf] = await Promise.all([
        window.sb.from('platform_config').select('value').eq('id', 'courier').maybeSingle(),
        window.sb.from('platform_config').select('value').eq('id', 'toyyibpay').maybeSingle(),
        window.sb.from('platform_config').select('value').eq('id', 'pdf_default').maybeSingle(),
      ]);

      const c = (courier.data && courier.data.value) || {};
      delyvaKey.value = c.apiKey || '';
      delyvaCustomer.value = c.customerId || '';
      delyvaCompany.value = c.companyId || '';

      const t = (toyyib.data && toyyib.data.value) || {};
      toyyibSecret.value = t.secretKey || '';
      toyyibCat.value = t.categoryCode || '';
      toyyibSandbox.checked = t.isSandbox === undefined ? true : !!t.isSandbox;

      const p = (pdf.data && pdf.data.value) || {};
      pdfUrl.value = p.pdfCloudRunUrl || 'https://rms-backend-94407896005.asia-southeast1.run.app';
      pdfCustom.checked = !!p.useCustomPdfUrl;

      updateBadges();
      loadingEl.classList.add('hidden');
      contentEl.classList.remove('hidden');
    } catch (e) {
      loadingEl.innerHTML = `<div class="admin-error">${escapeHtml(e.message || String(e))}</div>`;
    }
  }

  function updateBadges() {
    badgeDelyva.classList.toggle('hidden', !delyvaKey.value.trim());

    if (toyyibSecret.value.trim()) {
      badgeToyyib.classList.remove('hidden');
      const isSb = toyyibSandbox.checked;
      badgeToyyib.textContent = isSb ? 'SANDBOX' : 'LIVE';
      badgeToyyib.classList.toggle('ts-badge--orange', isSb);
      badgeToyyib.classList.toggle('ts-badge--ok', !isSb);
    } else {
      badgeToyyib.classList.add('hidden');
    }
    toyyibSandboxLabel.textContent = toyyibSandbox.checked ? 'Sandbox Mode' : 'Live Mode';
    toyyibSandboxLabel.style.color = toyyibSandbox.checked ? 'var(--orange)' : 'var(--green)';

    const isCustom = pdfCustom.checked;
    badgePdf.textContent = isCustom ? 'CUSTOM' : 'DEFAULT';
    badgePdf.classList.toggle('ts-badge--ok', isCustom);
    badgePdf.classList.toggle('ts-badge--blue', !isCustom);
    pdfCustomLabel.textContent = isCustom ? 'Guna URL Custom' : 'Guna URL Default';
    pdfCustomLabel.style.color = isCustom ? 'var(--green)' : 'var(--blue)';
  }

  async function saveAll() {
    const btn = document.getElementById('btnSave');
    const orig = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> MENYIMPAN…';
    try {
      const nowIso = new Date().toISOString();
      const ops = [];

      if (delyvaKey.value.trim()) {
        ops.push(window.sb.from('platform_config').upsert({
          id: 'courier',
          value: {
            provider: 'delyva',
            apiKey: delyvaKey.value.trim(),
            customerId: delyvaCustomer.value.trim(),
            companyId: delyvaCompany.value.trim(),
            updatedAt: nowIso,
          },
        }));
      }

      if (toyyibSecret.value.trim()) {
        ops.push(window.sb.from('platform_config').upsert({
          id: 'toyyibpay',
          value: {
            secretKey: toyyibSecret.value.trim(),
            categoryCode: toyyibCat.value.trim(),
            isSandbox: toyyibSandbox.checked,
            updatedAt: nowIso,
          },
        }));
      }

      ops.push(window.sb.from('platform_config').upsert({
        id: 'pdf_default',
        value: {
          pdfCloudRunUrl: pdfUrl.value.trim(),
          useCustomPdfUrl: pdfCustom.checked,
          updatedAt: nowIso,
        },
      }));

      const results = await Promise.all(ops);
      for (const r of results) { if (r.error) throw r.error; }
      toast('Semua tetapan berjaya disimpan');
    } catch (e) {
      toast('Ralat: ' + (e.message || e), true);
    } finally {
      btn.disabled = false;
      btn.innerHTML = orig;
    }
  }

  function toast(msg, err) {
    const t = document.createElement('div');
    t.className = 'admin-toast';
    if (err) t.style.background = 'var(--red)';
    t.innerHTML = `<i class="fas fa-${err ? 'circle-exclamation' : 'circle-check'}"></i> ${escapeHtml(msg)}`;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2600);
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  }
})();
