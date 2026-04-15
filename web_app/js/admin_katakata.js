/* Admin → Kata-Kata. Mirror katakata_screen.dart.
   Source: platform_config (id='kata_kata', value JSONB { motivasi, nasihatSolat, tarikhKemaskiniMotivasi, tarikhKemaskiniSolat }). */
(function () {
  'use strict';

  const CFG_ID = 'kata_kata';
  const loadingEl = document.getElementById('kkLoading');
  const contentEl = document.getElementById('kkContent');
  const txtMotivasi = document.getElementById('txtMotivasi');
  const txtSolat = document.getElementById('txtSolat');
  const tsMotivasi = document.getElementById('tsMotivasi');
  const tsSolat = document.getElementById('tsSolat');

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.querySelectorAll('.kk-save').forEach(b => b.addEventListener('click', () => save(b.dataset.target, b)));

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function readKK() {
    const { data, error } = await window.sb.from('platform_config').select('value').eq('id', CFG_ID).maybeSingle();
    if (error) throw error;
    return (data && data.value && typeof data.value === 'object') ? data.value : {};
  }

  async function writeKK(patch) {
    const existing = await readKK();
    const merged = Object.assign({}, existing, patch);
    const { error } = await window.sb.from('platform_config').upsert({ id: CFG_ID, value: merged });
    if (error) throw error;
  }

  async function load() {
    try {
      const d = await readKK();
      txtMotivasi.value = d.motivasi || '';
      txtSolat.value = d.nasihatSolat || '';
      tsMotivasi.textContent = fmt(d.tarikhKemaskiniMotivasi);
      tsSolat.textContent = fmt(d.tarikhKemaskiniSolat);
      loadingEl.classList.add('hidden');
      contentEl.classList.remove('hidden');
    } catch (e) {
      loadingEl.innerHTML = `<div class="admin-error">${e.message}</div>`;
    }
  }

  async function save(target, btn) {
    const isMotivasi = target === 'motivasi';
    const field = isMotivasi ? 'motivasi' : 'nasihatSolat';
    const stampField = isMotivasi ? 'tarikhKemaskiniMotivasi' : 'tarikhKemaskiniSolat';
    const val = (isMotivasi ? txtMotivasi : txtSolat).value.trim();
    if (!val) return;
    const original = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> MENYIMPAN…';
    try {
      const nowIso = new Date().toISOString();
      await writeKK({ [field]: val, [stampField]: nowIso });
      (isMotivasi ? tsMotivasi : tsSolat).textContent = fmt(nowIso);
      toast(isMotivasi ? 'Motivasi berjaya dikemaskini!' : 'Nasihat solat berjaya dikemaskini!');
    } catch (e) {
      alert('Ralat: ' + e.message);
    } finally {
      btn.disabled = false;
      btn.innerHTML = original;
    }
  }

  function fmt(v) {
    if (!v) return '-';
    const d = new Date(v); if (isNaN(d.getTime())) return '-';
    const months = ['Jan','Feb','Mac','Apr','Mei','Jun','Jul','Ogo','Sep','Okt','Nov','Dis'];
    let h = d.getHours(); const ampm = h >= 12 ? 'PM' : 'AM'; h = h % 12 || 12;
    const pad = n => String(n).padStart(2, '0');
    return `${pad(d.getDate())} ${months[d.getMonth()]} ${d.getFullYear()}, ${pad(h)}:${pad(d.getMinutes())} ${ampm}`;
  }

  function toast(msg) {
    const t = document.createElement('div');
    t.className = 'admin-toast';
    t.innerHTML = `<i class="fas fa-circle-check"></i> ${msg}`;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2400);
  }
})();
