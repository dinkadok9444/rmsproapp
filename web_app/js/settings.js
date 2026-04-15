/* settings.js — Branch settings. Mirror settings_screen.dart.
   Load branch + tenant config, render form, save to branches.config + tenants.config. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);

  function toast(msg, err) {
    const el = document.createElement('div');
    el.style.cssText = 'position:fixed;left:50%;bottom:90px;transform:translateX(-50%);background:' +
      (err ? '#dc2626' : '#0f172a') + ';color:#fff;padding:10px 18px;border-radius:10px;z-index:9999;font-weight:700;';
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2400);
  }

  let branch = null, tenant = null, dirty = false;
  const HEADER_COLORS = ['#6366F1', '#2563EB', '#0EA5E9', '#14B8A6', '#10B981', '#F59E0B', '#EF4444', '#EC4899', '#8B5CF6', '#64748B'];
  const TEMPLATES = ['Klasik', 'Moden', 'Minima', 'Warna'];

  function markDirty() { dirty = true; const bar = $('saveBar'); if (bar) bar.classList.remove('is-hidden'); }

  async function loadAll() {
    const [{ data: b }, { data: t }] = await Promise.all([
      window.sb.from('branches').select('*').eq('id', branchId).single(),
      window.sb.from('tenants').select('*').eq('id', tenantId).single(),
    ]);
    branch = b || {};
    tenant = t || {};
    const cfg = (branch.config && typeof branch.config === 'object') ? branch.config : {};

    // Shop info
    if ($('fShopName')) $('fShopName').textContent = branch.nama_kedai || '—';
    if ($('fSsm')) $('fSsm').textContent = cfg.ssm || '—';
    if ($('fAddress')) $('fAddress').textContent = branch.alamat || '—';
    if ($('fPhone')) $('fPhone').value = branch.phone || '';
    if ($('fEmail')) $('fEmail').textContent = branch.email || '—';
    if ($('fBranchId')) $('fBranchId').textContent = branch.shop_code || branch.id || '—';

    if (branch.logo_base64 && $('logoPreview')) {
      $('logoPreview').innerHTML = `<img src="${branch.logo_base64}" style="width:100%;height:100%;object-fit:cover;border-radius:inherit">`;
    }

    // Colors
    const headerColor = cfg.header_color || HEADER_COLORS[0];
    if ($('colorGrid')) {
      $('colorGrid').innerHTML = HEADER_COLORS.map((c) => `
        <button type="button" class="color-swatch${c === headerColor ? ' is-active' : ''}" data-c="${c}"
          style="width:36px;height:36px;border-radius:50%;border:3px solid ${c === headerColor ? '#0f172a' : 'transparent'};background:${c};cursor:pointer;margin:4px;"></button>
      `).join('');
      $('colorGrid').querySelectorAll('.color-swatch').forEach((b) => {
        b.addEventListener('click', () => {
          $('colorGrid').querySelectorAll('.color-swatch').forEach((x) => { x.classList.remove('is-active'); x.style.borderColor = 'transparent'; });
          b.classList.add('is-active'); b.style.borderColor = '#0f172a';
          markDirty();
        });
      });
    }

    const sbx = $('fStaffBox'); if (sbx) { sbx.value = String(cfg.staff_box || 1); sbx.addEventListener('change', markDirty); }

    const selTpl = cfg.pdf_template || 'Klasik';
    if ($('tplGrid')) {
      $('tplGrid').innerHTML = TEMPLATES.map((t) => `
        <button type="button" class="tpl-opt${t === selTpl ? ' is-active' : ''}" data-t="${t}"
          style="padding:10px 14px;border:2px solid ${t === selTpl ? '#6366F1' : '#e2e8f0'};border-radius:10px;background:${t === selTpl ? '#6366F115' : '#fff'};cursor:pointer;font-weight:700;margin:4px;">${t}</button>
      `).join('');
      $('tplGrid').querySelectorAll('.tpl-opt').forEach((b) => {
        b.addEventListener('click', () => {
          $('tplGrid').querySelectorAll('.tpl-opt').forEach((x) => { x.classList.remove('is-active'); x.style.borderColor = '#e2e8f0'; x.style.background = '#fff'; });
          b.classList.add('is-active'); b.style.borderColor = '#6366F1'; b.style.background = '#6366F115';
          markDirty();
        });
      });
    }

    if ($('fNotaInvoice')) $('fNotaInvoice').value = cfg.nota_invoice || '';
    if ($('fNotaQuotation')) $('fNotaQuotation').value = cfg.nota_quotation || '';
    if ($('fNotaClaim')) $('fNotaClaim').value = cfg.nota_claim || '';
    if ($('fNotaBooking')) $('fNotaBooking').value = cfg.nota_booking || '';
    if ($('fLang')) $('fLang').value = cfg.lang || 'ms';
    if ($('fSvTel')) $('fSvTel').value = cfg.admin_tel || '';
    if ($('fSvPass')) $('fSvPass').value = cfg.admin_pass || '';

    ['fPhone', 'fNotaInvoice', 'fNotaQuotation', 'fNotaClaim', 'fNotaBooking', 'fLang', 'fSvTel', 'fSvPass'].forEach((id) => {
      const el = $(id); if (el) el.addEventListener('input', markDirty);
    });
  }

  const ownerID = (ctx.email || '').split('@')[0] || 'unknown';
  const logoFile = $('logoFile');
  if (logoFile) logoFile.addEventListener('change', async (e) => {
    const file = e.target.files && e.target.files[0]; if (!file) return;
    if (!window.SupabaseStorage) { toast('Storage helper missing', true); return; }
    const prev = $('logoPreview');
    const prevHtml = prev ? prev.innerHTML : '';
    if (prev) prev.innerHTML = '<div style="font-size:11px;font-weight:800;">UPLOADING...</div>';
    try {
      const blob = await window.SupabaseStorage.resizeImage(file, 1280, 0.85);
      const shopCode = branch.shop_code || branchId || 'shop';
      const path = `${ownerID}/${shopCode}/logo_${Date.now()}.jpg`;
      const url = await window.SupabaseStorage.uploadFile({ bucket: 'staff_avatars', path, file: blob, contentType: 'image/jpeg' });
      branch.logo_base64 = url; // column is text — storing URL is compat-safe
      if (prev) prev.innerHTML = `<img src="${url}" style="width:100%;height:100%;object-fit:cover;border-radius:inherit">`;
      markDirty();
    } catch (err) {
      if (prev) prev.innerHTML = prevHtml;
      toast('Upload gagal: ' + err.message, true);
    } finally {
      logoFile.value = '';
    }
  });
  const logoRm = $('logoRemove');
  if (logoRm) logoRm.addEventListener('click', () => {
    branch.logo_base64 = null;
    $('logoPreview').innerHTML = '<i class="fas fa-image"></i>';
    markDirty();
  });

  const btnToggle = $('btnTogglePass');
  if (btnToggle) btnToggle.addEventListener('click', () => {
    const inp = $('fSvPass'); if (!inp) return;
    inp.type = inp.type === 'password' ? 'text' : 'password';
  });

  const btnReset = $('btnReset');
  if (btnReset) btnReset.addEventListener('click', async () => {
    if (!confirm('Buang perubahan?')) return;
    dirty = false; $('saveBar').classList.add('is-hidden');
    await loadAll();
  });

  const btnSave = $('btnSave');
  if (btnSave) btnSave.addEventListener('click', async () => {
    btnSave.disabled = true;
    try {
      const headerColor = $('colorGrid') && $('colorGrid').querySelector('.color-swatch.is-active')?.dataset.c || HEADER_COLORS[0];
      const pdfTpl = $('tplGrid') && $('tplGrid').querySelector('.tpl-opt.is-active')?.dataset.t || 'Klasik';
      const cfg = {
        ...(branch.config || {}),
        header_color: headerColor,
        staff_box: Number($('fStaffBox')?.value) || 1,
        pdf_template: pdfTpl,
        nota_invoice: $('fNotaInvoice')?.value || '',
        nota_quotation: $('fNotaQuotation')?.value || '',
        nota_claim: $('fNotaClaim')?.value || '',
        nota_booking: $('fNotaBooking')?.value || '',
        lang: $('fLang')?.value || 'ms',
        admin_tel: $('fSvTel')?.value || '',
        admin_pass: $('fSvPass')?.value || '',
      };
      const { error: brErr } = await window.sb.from('branches').update({
        phone: $('fPhone')?.value || null,
        logo_base64: branch.logo_base64 || null,
        config: cfg,
      }).eq('id', branchId);
      if (brErr) throw brErr;
      branch.config = cfg;
      toast('Tetapan disimpan');
      dirty = false; $('saveBar').classList.add('is-hidden');
    } catch (e) {
      toast('Gagal: ' + (e.message || e), true);
    } finally {
      btnSave.disabled = false;
    }
  });

  await loadAll();
})();
