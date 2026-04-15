/* Admin → Template PDF. Mirror rmsproapp/lib/screens/admin_modules/template_pdf_screen.dart.
   Table: platform_config (id='pdf_templates', value JSONB { tpl_1..tpl_10: url, updatedAt })
   Storage bucket: pdf_templates (path: tpl_N.jpg) */
(function () {
  'use strict';

  const TPL_ID = 'pdf_templates';
  const BUCKET = 'pdf_templates';

  const TEMPLATES = [
    { name: 'Standard',   color: '#FF6600', bg: '#FFF7ED', icon: 'fa-file' },
    { name: 'Moden',      color: '#2563EB', bg: '#EFF6FF', icon: 'fa-table-cells-large' },
    { name: 'Klasik',     color: '#374151', bg: '#F3F4F6', icon: 'fa-scroll' },
    { name: 'Minimalis',  color: '#64748B', bg: '#F8FAFC', icon: 'fa-minus' },
    { name: 'Komersial',  color: '#DC2626', bg: '#FEF2F2', icon: 'fa-tags' },
    { name: 'Elegan',     color: '#92400E', bg: '#FFFBEB', icon: 'fa-gem' },
    { name: 'Tengah',     color: '#7C3AED', bg: '#F5F3FF', icon: 'fa-align-center' },
    { name: 'Kompak',     color: '#0D9488', bg: '#F0FDFA', icon: 'fa-compress' },
    { name: 'Korporat',   color: '#1E3A5F', bg: '#F0F4F8', icon: 'fa-building-columns' },
    { name: 'Kreatif',    color: '#EC4899', bg: '#FDF2F8', icon: 'fa-paintbrush' },
  ];

  const listEl = document.getElementById('tplList');
  const countEl = document.getElementById('tplCount');
  const filePicker = document.getElementById('filePicker');
  let imageUrls = Array(10).fill(null);
  let busy = Array(10).fill(false);
  let pickIndex = -1;

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnRefresh').addEventListener('click', () => load(true));
  filePicker.addEventListener('change', onFileChosen);

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load(false);
  })();

  async function load(showToast) {
    const { data, error } = await window.sb
      .from('platform_config').select('value').eq('id', TPL_ID).maybeSingle();
    if (error) { listEl.innerHTML = `<div class="admin-error">${escapeHtml(error.message)}</div>`; return; }
    const val = (data && data.value && typeof data.value === 'object') ? data.value : {};
    let count = 0;
    for (let i = 0; i < 10; i++) {
      const v = val['tpl_' + (i + 1)];
      imageUrls[i] = (typeof v === 'string' && v) ? v : null;
      if (imageUrls[i]) count++;
    }
    render();
    if (showToast) toast(`Refresh: ${count} / 10 template dijumpai`);
  }

  function render() {
    const uploaded = imageUrls.filter(u => !!u).length;
    countEl.textContent = `${uploaded} / 10`;
    listEl.innerHTML = TEMPLATES.map((t, i) => cardHtml(t, i)).join('');
    listEl.querySelectorAll('[data-act="open"]').forEach(b => b.addEventListener('click', () => openPdf(parseInt(b.dataset.i, 10))));
    listEl.querySelectorAll('[data-act="upload"]').forEach(b => b.addEventListener('click', () => pickFile(parseInt(b.dataset.i, 10))));
    listEl.querySelectorAll('[data-act="remove"]').forEach(b => b.addEventListener('click', () => removeImage(parseInt(b.dataset.i, 10))));
  }

  function cardHtml(t, i) {
    const url = imageUrls[i];
    const isBusy = busy[i];
    const tplId = 'TPL_' + (i + 1);
    const borderStyle = url ? `border-color:${t.color}66;` : '';
    const preview = url
      ? `<img src="${escapeAttr(url)}" alt="${escapeHtml(t.name)}" onerror="this.outerHTML='<div class=\\'tpl-preview__empty\\' style=\\'color:${t.color}\\'><i class=\\'fas fa-triangle-exclamation\\'></i>RALAT</div>'">`
      : `<div class="tpl-preview__empty" style="color:${t.color}"><i class="fas fa-image"></i>BELUM ADA<br>GAMBAR</div>`;
    const actions = isBusy
      ? `<div class="tpl-busy" style="color:${t.color}"><i class="fas fa-spinner fa-spin"></i>SEDANG<br>PROSES...</div>`
      : `
        <button class="btn-act" data-act="open" data-i="${i}" style="color:${t.color};border-color:${t.color}33;background:${t.color}14">
          <i class="fas fa-file-pdf"></i> BUKA PDF
        </button>
        <button class="btn-act" data-act="upload" data-i="${i}" style="color:var(--blue);border-color:rgba(59,130,246,0.2);background:rgba(59,130,246,0.08)">
          <i class="fas fa-cloud-arrow-up"></i> UPLOAD GAMBAR
        </button>
        ${url ? `<button class="btn-act" data-act="remove" data-i="${i}" style="color:var(--red);border-color:rgba(239,68,68,0.2);background:rgba(239,68,68,0.08)">
          <i class="fas fa-trash"></i> PADAM
        </button>` : ''}
      `;
    return `
      <div class="tpl-card ${url ? 'is-active' : ''}" style="${borderStyle}">
        <div class="tpl-card__head" style="background:${t.bg}">
          <div class="tpl-card__icon" style="background:${t.color}1F;color:${t.color}"><i class="fas ${t.icon}"></i></div>
          <div>
            <div class="tpl-card__id" style="color:${t.color}">${tplId}</div>
            <div class="tpl-card__name" style="color:${t.color}">${escapeHtml(t.name)}</div>
          </div>
          <span class="tpl-badge ${url ? 'is-on' : 'is-off'}">
            <i class="fas ${url ? 'fa-circle-check' : 'fa-circle-xmark'}"></i>${url ? 'AKTIF' : 'KOSONG'}
          </span>
        </div>
        <div class="tpl-card__body">
          <div>
            <div class="tpl-col__label" style="color:${t.color}">PREVIEW</div>
            <div class="tpl-preview" style="background:${t.bg};border-color:${t.color}26">${preview}</div>
          </div>
          <div>
            <div class="tpl-col__label" style="color:${t.color}">TINDAKAN</div>
            <div class="tpl-action" style="border-color:${t.color}26">${actions}</div>
          </div>
        </div>
      </div>
    `;
  }

  async function openPdf(i) {
    // Versi web — generate PDF via endpoint yang sama bukan skop utama; hanya buka preview storage.
    const url = imageUrls[i];
    if (url) {
      window.open(url, '_blank');
      toast(`Preview ${TEMPLATES[i].name} dibuka`);
    } else {
      toast('Belum ada gambar. Upload dulu.', true);
    }
  }

  function pickFile(i) {
    pickIndex = i;
    filePicker.value = '';
    filePicker.click();
  }

  async function onFileChosen(e) {
    const file = e.target.files && e.target.files[0];
    const i = pickIndex;
    pickIndex = -1;
    if (!file || i < 0) return;
    busy[i] = true; render();
    try {
      const tplKey = 'tpl_' + (i + 1);
      const path = tplKey + '.jpg';
      const blob = await window.SupabaseStorage.compressImage(file);
      const { error: upErr } = await window.sb.storage.from(BUCKET)
        .upload(path, blob, { upsert: true, contentType: 'image/jpeg' });
      if (upErr) throw upErr;
      const { data: pub } = window.sb.storage.from(BUCKET).getPublicUrl(path);
      const publicUrl = pub && pub.publicUrl ? pub.publicUrl + '?v=' + Date.now() : '';
      await upsertValue({ [tplKey]: publicUrl });
      imageUrls[i] = publicUrl;
      toast(`${TEMPLATES[i].name} berjaya dimuat naik`);
    } catch (err) {
      toast('Gagal upload: ' + (err.message || err), true);
    } finally {
      busy[i] = false; render();
    }
  }

  async function removeImage(i) {
    if (!confirm(`Padam ${TEMPLATES[i].name}?`)) return;
    busy[i] = true; render();
    try {
      const tplKey = 'tpl_' + (i + 1);
      try { await window.sb.storage.from(BUCKET).remove([tplKey + '.jpg']); } catch(_) {}
      await removeValueKey(tplKey);
      imageUrls[i] = null;
      toast(`${TEMPLATES[i].name} dipadam`);
    } catch (err) {
      toast('Gagal padam: ' + (err.message || err), true);
    } finally {
      busy[i] = false; render();
    }
  }

  async function upsertValue(patch) {
    const { data: existing } = await window.sb.from('platform_config').select('value').eq('id', TPL_ID).maybeSingle();
    const value = (existing && existing.value && typeof existing.value === 'object') ? Object.assign({}, existing.value) : {};
    Object.assign(value, patch);
    value.updatedAt = new Date().toISOString();
    const { error } = await window.sb.from('platform_config').upsert({ id: TPL_ID, value });
    if (error) throw error;
  }

  async function removeValueKey(key) {
    const { data: existing } = await window.sb.from('platform_config').select('value').eq('id', TPL_ID).maybeSingle();
    const value = (existing && existing.value && typeof existing.value === 'object') ? Object.assign({}, existing.value) : {};
    delete value[key];
    value.updatedAt = new Date().toISOString();
    const { error } = await window.sb.from('platform_config').upsert({ id: TPL_ID, value });
    if (error) throw error;
  }

  function toast(msg, err) {
    const el = document.createElement('div');
    el.className = 'admin-toast';
    if (err) el.style.background = 'var(--red)';
    el.innerHTML = `<i class="fas ${err ? 'fa-circle-exclamation' : 'fa-circle-check'}"></i> ${escapeHtml(msg)}`;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2800);
  }
  function escapeHtml(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }
  function escapeAttr(s) { return escapeHtml(s); }
})();
