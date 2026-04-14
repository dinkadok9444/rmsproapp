/* Link module — port lib/screens/modules/link_screen.dart */
(function () {
  'use strict';
  const branch = localStorage.getItem('rms_current_branch');
  if (!branch || !branch.includes('@')) { window.location.replace('index.html'); return; }
  const [ownerID, shopID] = branch.split('@');

  const DEFAULT_DOMAIN = 'https://rmspro.net';
  const SWATCHES = [
    '#020617','#0F172A','#1E293B','#334155','#475569',
    '#FFFFFF','#F8FAFC','#E2E8F0','#CBD5E1','#94A3B8',
    '#10B981','#059669','#3B82F6','#2563EB','#6366F1',
    '#8B5CF6','#A855F7','#EC4899','#EF4444','#F59E0B',
  ];

  const LINKS = [
    { key: 'booking', title: 'Borang Booking',   route: 'booking', icon: 'fa-calendar-check', color: '#06B6D4', bg: '#CFFAFE' },
    { key: 'borang',  title: 'Borang Pelanggan', route: 'borang',  icon: 'fa-file-lines',     color: '#3B82F6', bg: '#DBEAFE' },
    { key: 'catalog', title: 'Katalog Telefon',  route: 'catalog', icon: 'fa-store',          color: '#10B981', bg: '#D1FAE5' },
    { key: 'link',    title: 'Bio / Linktree',   route: 'link',    icon: 'fa-id-card',        color: '#8B5CF6', bg: '#EDE9FE' },
  ];

  let dealer = {};

  function normalizeDomain(d) {
    let s = String(d || '').trim();
    if (!s) return '';
    if (!/^https?:\/\//i.test(s)) s = 'https://' + s;
    return s.replace(/\/+$/, '');
  }
  function isCustomDomain() {
    const d = normalizeDomain(dealer.domain);
    return !!d && d !== DEFAULT_DOMAIN;
  }
  function buildUrl(route) {
    if (isCustomDomain()) return `${normalizeDomain(dealer.domain)}/${route}`;
    const code = (dealer.dealerCode || '').toString().trim();
    return `${DEFAULT_DOMAIN}/${route}/${code}`;
  }

  // Match dart _generateCode()
  function generateCode() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    let seed = Date.now() * 1000 + Math.floor(Math.random() * 1000);
    let out = '';
    for (let i = 0; i < 6; i++) {
      out += chars[seed % chars.length];
      seed = Math.floor(seed / chars.length) + i * 7;
    }
    return out;
  }

  function toast(msg) {
    document.querySelectorAll('.link-toast').forEach(t => t.remove());
    const el = document.createElement('div');
    el.className = 'link-toast';
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2000);
  }

  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); toast('Disalin ✓'); }
    catch { toast('Gagal menyalin'); }
  }

  function render() {
    // Domain card
    const dc = document.getElementById('domainCard');
    if (dealer.domain) {
      dc.hidden = false;
      document.getElementById('domainUrl').textContent = dealer.domain;
      const st = document.getElementById('domainStatus');
      const status = dealer.domainStatus || 'PENDING';
      st.textContent = status;
      st.className = 'domain-card__status ' + (status === 'ACTIVE' ? 'status-active' : 'status-pending');
    } else {
      dc.hidden = true;
    }

    const list = document.getElementById('linkList');
    list.innerHTML = LINKS.map(l => {
      const url = buildUrl(l.route);
      return `
        <div class="link-card" data-key="${l.key}">
          <div class="link-card__icon" style="background:${l.bg};color:${l.color}"><i class="fas ${l.icon}"></i></div>
          <div class="link-card__head">
            <h3 class="link-card__title">${l.title}</h3>
            <div class="link-card__url">${url}</div>
          </div>
          <div class="link-actions">
            <button class="link-btn link-btn--copy"   data-act="copy"   data-url="${url}" title="Salin"><i class="fas fa-copy"></i></button>
            <button class="link-btn link-btn--open"   data-act="open"   data-url="${url}" title="Buka"><i class="fas fa-arrow-up-right-from-square"></i></button>
            <button class="link-btn link-btn--wa"     data-act="wa"     data-url="${url}" title="Hantar WhatsApp"><i class="fab fa-whatsapp"></i></button>
            <button class="link-btn link-btn--custom" data-act="custom" data-key="${l.key}" data-title="${l.title}" title="Custom Theme"><i class="fas fa-palette"></i></button>
          </div>
        </div>`;
    }).join('');
  }

  document.addEventListener('click', (e) => {
    const btn = e.target.closest('.link-btn');
    if (!btn) return;
    const url = btn.dataset.url;
    switch (btn.dataset.act) {
      case 'copy': copyText(url); break;
      case 'open': window.open(url, '_blank', 'noopener'); break;
      case 'wa':   window.open('https://wa.me/?text=' + encodeURIComponent(url), '_blank', 'noopener'); break;
      case 'custom': openThemeModal(btn.dataset.key, btn.dataset.title); break;
    }
  });

  // ---- Theme modal ----
  const modal = document.getElementById('themeModal');
  let active = { key: '', bg: '#020617', text: '#FFFFFF', accent: '#3B82F6', fs: 14 };

  function buildSwatches(targetId, prop) {
    document.getElementById(targetId).innerHTML = SWATCHES.map(c =>
      `<button type="button" class="theme-swatch" data-prop="${prop}" data-color="${c}" style="background:${c}"></button>`
    ).join('');
  }
  buildSwatches('bgSwatches', 'bg');
  buildSwatches('textSwatches', 'text');
  buildSwatches('accentSwatches', 'accent');

  modal.addEventListener('click', (e) => {
    if (e.target === modal) { modal.classList.remove('is-open'); return; }
    const sw = e.target.closest('.theme-swatch');
    if (sw) {
      active[sw.dataset.prop] = sw.dataset.color;
      refreshSwatches();
      refreshPreview();
    }
  });
  document.getElementById('fsSlider').addEventListener('input', (e) => {
    active.fs = parseInt(e.target.value, 10);
    document.getElementById('fsLabel').textContent = active.fs;
    refreshPreview();
  });
  document.getElementById('themeCancel').addEventListener('click', () => modal.classList.remove('is-open'));
  document.getElementById('themeSave').addEventListener('click', async () => {
    const btn = document.getElementById('themeSave');
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-circle-notch fa-spin"></i> Menyimpan…';
    try {
      const path = `pageThemes.${active.key}`;
      await db.collection('saas_dealers').doc(ownerID).set({
        pageThemes: { [active.key]: { bgColor: active.bg, textColor: active.text, accentColor: active.accent, fontSize: active.fs } }
      }, { merge: true });
      toast('Tersimpan ✓');
      modal.classList.remove('is-open');
    } catch (err) {
      toast('Ralat: ' + err.message);
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<i class="fas fa-floppy-disk"></i> Simpan';
    }
  });

  function refreshSwatches() {
    ['bg','text','accent'].forEach(prop => {
      document.querySelectorAll(`.theme-swatch[data-prop="${prop}"]`).forEach(s => {
        s.classList.toggle('is-active', s.dataset.color === active[prop]);
      });
    });
  }
  function refreshPreview() {
    const p = document.getElementById('themePreview');
    p.style.background = active.bg;
    p.style.color = active.text;
    p.style.borderColor = active.accent;
    p.style.fontSize = active.fs + 'px';
  }

  function openThemeModal(key, title) {
    active.key = key;
    const t = (dealer.pageThemes || {})[key] || {};
    active.bg     = t.bgColor    || '#020617';
    active.text   = t.textColor  || '#FFFFFF';
    active.accent = t.accentColor|| '#3B82F6';
    active.fs     = t.fontSize   || 14;
    document.getElementById('themeModalTitle').textContent = 'Custom Theme — ' + title;
    document.getElementById('fsSlider').value = active.fs;
    document.getElementById('fsLabel').textContent = active.fs;
    refreshSwatches();
    refreshPreview();
    modal.classList.add('is-open');
  }

  // ---- Load ----
  async function load() {
    try {
      const snap = await db.collection('saas_dealers').doc(ownerID).get();
      if (snap.exists) dealer = snap.data() || {};
      if (!dealer.dealerCode) {
        dealer.dealerCode = generateCode();
        try {
          await db.collection('saas_dealers').doc(ownerID)
            .set({ dealerCode: dealer.dealerCode }, { merge: true });
        } catch (e) { console.warn('save dealerCode', e); }
      }
    } catch (e) { console.warn(e); }
    render();
  }
  load();
})();
