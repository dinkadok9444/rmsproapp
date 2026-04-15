/* Admin -> Bot WhatsApp. Mirror rmsproapp/lib/screens/admin_modules/whatsapp_bot_screen.dart.
   Table: tenants (owner_id, nama_kedai, bot_whatsapp jsonb {noWhatsapp,status,phoneNumberId,accessToken,wabaId,verifyToken,greeting,notFound}). */
(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const listEl = $('botList');
  const cntEl = $('botCount');
  const addModal = $('addModal');
  const setModal = $('setModal');

  let bots = [];
  let allDealers = [];
  let selectedDealer = null;
  let editId = null;

  $('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  $('btnAdd').addEventListener('click', openAdd);
  $('addCancel').addEventListener('click', () => addModal.classList.add('hidden'));
  addModal.querySelector('.modal__backdrop').addEventListener('click', () => addModal.classList.add('hidden'));
  $('btnClearSel').addEventListener('click', () => { selectedDealer = null; showStep(1); });
  $('dealerSearch').addEventListener('input', renderDealers);
  $('addSave').addEventListener('click', doSetup);
  $('setCancel').addEventListener('click', () => setModal.classList.add('hidden'));
  setModal.querySelector('.modal__backdrop').addEventListener('click', () => setModal.classList.add('hidden'));
  $('setSave').addEventListener('click', saveSettings);

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    const { data, error } = await window.sb.from('tenants').select('id,owner_id,nama_kedai,bot_whatsapp').order('nama_kedai');
    if (error) { listEl.innerHTML = `<div class="admin-error">${error.message}</div>`; return; }
    bots = (data || []).filter(r => r.bot_whatsapp && typeof r.bot_whatsapp === 'object' && Object.keys(r.bot_whatsapp).length).map(r => ({
      id: r.owner_id || '', tenantId: r.id, namaKedai: r.nama_kedai || '', bot: r.bot_whatsapp || {},
    }));
    cntEl.textContent = bots.length;
    render();
  }

  function render() {
    if (!bots.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fab fa-whatsapp" style="font-size:26px;opacity:0.3;display:block;margin-bottom:8px"></i>Belum ada bot</div>`;
      return;
    }
    listEl.innerHTML = bots.map(b => {
      const active = (b.bot.status || '') === 'AKTIF';
      const noWa = b.bot.noWhatsapp || '-';
      return `
        <div class="host-card is-whatsapp ${active ? 'is-active' : 'is-pending'}">
          <div class="host-card__head">
            <div class="host-card__main">
              <div class="host-card__name">${esc(b.namaKedai)}</div>
              <div class="host-card__addr"><i class="fab fa-whatsapp"></i> ${esc(noWa)}</div>
            </div>
            <span class="host-card__badge ${active ? 'is-active' : 'is-pending'}">${active ? 'Aktif' : 'Tak Aktif'}</span>
          </div>
          <div class="host-card__actions">
            <button class="host-card__btn is-violet" data-act="set" data-id="${esc(b.id)}"><i class="fas fa-cog"></i> Tetapan</button>
            <button class="host-card__btn ${active ? 'is-orange' : 'is-green'}" data-act="tog" data-id="${esc(b.id)}"><i class="fas fa-power-off"></i> ${active ? 'Off' : 'On'}</button>
            <button class="host-card__btn is-red" data-act="del" data-id="${esc(b.id)}"><i class="fas fa-trash"></i> Padam</button>
          </div>
        </div>`;
    }).join('');
    listEl.querySelectorAll('[data-act]').forEach(b => b.addEventListener('click', () => {
      const it = bots.find(x => x.id === b.dataset.id); if (!it) return;
      if (b.dataset.act === 'set') openSettings(it);
      else if (b.dataset.act === 'tog') toggleBot(it);
      else if (b.dataset.act === 'del') delBot(it);
    }));
  }

  async function openAdd() {
    selectedDealer = null;
    ['waInput','phoneIdInput','accessTokenInput','wabaIdInput','verifyTokenInput','dealerSearch'].forEach(i => $(i).value = '');
    showStep(1);
    addModal.classList.remove('hidden');
    $('dealerList').innerHTML = '<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i></div>';
    const { data } = await window.sb.from('tenants').select('owner_id,nama_kedai').order('nama_kedai');
    allDealers = (data || []).map(r => ({ id: r.owner_id || '', namaKedai: r.nama_kedai || '' }));
    renderDealers();
  }
  function showStep(n) { $('addStep1').classList.toggle('hidden', n !== 1); $('addStep2').classList.toggle('hidden', n !== 2); }

  function renderDealers() {
    const q = $('dealerSearch').value.toLowerCase();
    const list = allDealers.filter(d => d.namaKedai.toLowerCase().includes(q) || d.id.toLowerCase().includes(q));
    $('dealerList').innerHTML = list.map(d => `
      <div class="picker-item" data-id="${esc(d.id)}">
        <i class="fas fa-store" style="color:var(--whatsapp);font-size:11px"></i>
        <div style="flex:1;min-width:0">
          <div class="picker-item__name">${esc(d.namaKedai)}</div>
          <div class="picker-item__id">${esc(d.id)}</div>
        </div>
        <i class="fas fa-chevron-right" style="color:var(--text-dim);font-size:10px"></i>
      </div>`).join('');
    $('dealerList').querySelectorAll('.picker-item').forEach(el => el.addEventListener('click', () => {
      selectedDealer = allDealers.find(x => x.id === el.dataset.id); if (!selectedDealer) return;
      $('selectedName').textContent = selectedDealer.namaKedai;
      showStep(2);
    }));
  }

  async function doSetup() {
    if (!selectedDealer) return;
    const wa = $('waInput').value.trim().replace(/[^0-9]/g, '');
    const phoneId = $('phoneIdInput').value.trim();
    const token = $('accessTokenInput').value.trim();
    if (!wa || !phoneId || !token) { toast('Sila isi No. WhatsApp, Phone Number ID & Access Token', 'orange'); return; }
    const nama = selectedDealer.namaKedai;
    const payload = {
      noWhatsapp: wa, status: 'AKTIF', createdAt: new Date().toISOString(),
      phoneNumberId: phoneId, accessToken: token,
      wabaId: $('wabaIdInput').value.trim(), verifyToken: $('verifyTokenInput').value.trim(),
      greeting: `Terima kasih kerana menghubungi ${nama}. Sila hantar nombor telefon anda untuk semak status repair.`,
      notFound: 'Maaf, tiada rekod repair dijumpai untuk nombor ini. Sila semak semula atau hubungi kedai.',
    };
    const { error } = await window.sb.from('tenants').update({ bot_whatsapp: payload }).eq('owner_id', selectedDealer.id);
    addModal.classList.add('hidden');
    if (error) { toast('Gagal: ' + error.message, 'red'); return; }
    toast(`Bot untuk ${nama} berjaya diaktifkan!`, 'green');
    await load();
  }

  function openSettings(item) {
    editId = item.id;
    const b = item.bot || {};
    $('setNoWa').value = b.noWhatsapp || '';
    $('setPhoneId').value = b.phoneNumberId || '';
    $('setAccessToken').value = b.accessToken || '';
    $('setWabaId').value = b.wabaId || '';
    $('setVerifyToken').value = b.verifyToken || '';
    $('setGreeting').value = b.greeting || '';
    $('setNotFound').value = b.notFound || '';
    setModal.classList.remove('hidden');
  }

  async function saveSettings() {
    if (!editId) return;
    const patch = {
      noWhatsapp: $('setNoWa').value.trim().replace(/[^0-9]/g, ''),
      phoneNumberId: $('setPhoneId').value.trim(),
      accessToken: $('setAccessToken').value.trim(),
      wabaId: $('setWabaId').value.trim(),
      verifyToken: $('setVerifyToken').value.trim(),
      greeting: $('setGreeting').value.trim(),
      notFound: $('setNotFound').value.trim(),
    };
    await mergeBot(editId, patch);
    setModal.classList.add('hidden');
    toast('Tetapan bot dikemaskini!', 'green');
    await load();
  }

  async function toggleBot(item) {
    const cur = (item.bot.status || '') === 'AKTIF' ? 'TIDAK_AKTIF' : 'AKTIF';
    try {
      await mergeBot(item.id, { status: cur });
      toast(cur === 'AKTIF' ? 'Bot diaktifkan' : 'Bot dinyahaktifkan', cur === 'AKTIF' ? 'green' : 'orange');
      await load();
    } catch (e) { toast('Gagal: ' + e.message, 'red'); }
  }

  async function delBot(item) {
    if (!confirm(`Padam bot WhatsApp untuk ${item.namaKedai}?`)) return;
    const { error } = await window.sb.from('tenants').update({ bot_whatsapp: {} }).eq('owner_id', item.id);
    if (error) { toast('Gagal padam: ' + error.message, 'red'); return; }
    toast('Bot telah dipadam', 'green');
    await load();
  }

  async function mergeBot(ownerId, patch) {
    const { data } = await window.sb.from('tenants').select('bot_whatsapp').eq('owner_id', ownerId).maybeSingle();
    const cur = (data && typeof data.bot_whatsapp === 'object' && data.bot_whatsapp) || {};
    const merged = Object.assign({}, cur, patch);
    const { error } = await window.sb.from('tenants').update({ bot_whatsapp: merged }).eq('owner_id', ownerId);
    if (error) throw error;
  }

  function toast(msg, color) {
    const t = document.createElement('div');
    t.className = 'admin-toast';
    t.style.background = `var(--${color === 'red' ? 'red' : color === 'orange' ? 'orange' : 'green'})`;
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2200);
  }
  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }
})();
