/* Admin -> Domain Management. Mirror rmsproapp/lib/screens/admin_modules/domain_management_screen.dart.
   Table: tenants (owner_id, nama_kedai, domain, domain_status, dns_records).
   Edge: https://lpurtgmqecabgwwenikb.supabase.co/functions/v1/cf-custom-hostname. */
(function () {
  'use strict';

  const EDGE = 'https://lpurtgmqecabgwwenikb.supabase.co/functions/v1/cf-custom-hostname';

  const listEl = document.getElementById('domList');
  const cntEl = document.getElementById('domCount');
  const addModal = document.getElementById('addModal');
  const dnsModal = document.getElementById('dnsModal');
  const step1 = document.getElementById('addStep1');
  const step2 = document.getElementById('addStep2');
  const dealerListEl = document.getElementById('dealerList');
  const dealerSearch = document.getElementById('dealerSearch');
  const selectedName = document.getElementById('selectedName');
  const domainInput = document.getElementById('domainInput');
  const dnsTitle = document.getElementById('dnsTitle');
  const dnsBody = document.getElementById('dnsBody');

  let domains = [];
  let allDealers = [];
  let selectedDealer = null;

  document.getElementById('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  document.getElementById('btnAdd').addEventListener('click', openAdd);
  document.getElementById('addCancel').addEventListener('click', closeAdd);
  addModal.querySelector('.modal__backdrop').addEventListener('click', closeAdd);
  document.getElementById('btnClearSel').addEventListener('click', () => { selectedDealer = null; showStep(1); });
  document.getElementById('addSave').addEventListener('click', doSetup);
  dealerSearch.addEventListener('input', renderDealers);
  document.getElementById('dnsClose').addEventListener('click', () => dnsModal.classList.add('hidden'));
  dnsModal.querySelector('.modal__backdrop').addEventListener('click', () => dnsModal.classList.add('hidden'));

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await load();
  })();

  async function load() {
    const { data, error } = await window.sb
      .from('tenants')
      .select('owner_id,nama_kedai,domain,domain_status,dns_records')
      .not('domain', 'is', null)
      .order('nama_kedai');
    if (error) { listEl.innerHTML = `<div class="admin-error">${error.message}</div>`; return; }
    domains = (data || []).map(r => ({
      id: r.owner_id || '',
      namaKedai: r.nama_kedai || '',
      domain: r.domain || '',
      domainStatus: r.domain_status || '',
      dnsRecords: Array.isArray(r.dns_records) ? r.dns_records : [],
    }));
    cntEl.textContent = domains.length;
    render();
  }

  function render() {
    if (!domains.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-globe" style="font-size:26px;opacity:0.3;display:block;margin-bottom:8px"></i>Belum ada domain</div>`;
      return;
    }
    listEl.innerHTML = domains.map(d => {
      const active = d.domainStatus === 'ACTIVE';
      const domainName = d.domain.replace('https://', '');
      return `
        <div class="host-card ${active ? 'is-active' : 'is-pending'}">
          <div class="host-card__head">
            <div class="host-card__main">
              <div class="host-card__name">${esc(d.namaKedai)}</div>
              <div class="host-card__addr">${esc(domainName)}</div>
            </div>
            <span class="host-card__badge ${active ? 'is-active' : 'is-pending'}">${active ? 'Aktif' : 'Pending'}</span>
          </div>
          <div class="host-card__actions">
            <button class="host-card__btn is-violet" data-act="dns" data-id="${esc(d.id)}"><i class="fas fa-server"></i> DNS</button>
            <button class="host-card__btn is-green" data-act="check" data-id="${esc(d.id)}"><i class="fas fa-rotate"></i> Semak</button>
            <button class="host-card__btn is-red" data-act="del" data-id="${esc(d.id)}"><i class="fas fa-trash"></i> Padam</button>
          </div>
        </div>`;
    }).join('');
    listEl.querySelectorAll('[data-act]').forEach(b => b.addEventListener('click', () => {
      const it = domains.find(x => x.id === b.dataset.id);
      if (!it) return;
      if (b.dataset.act === 'dns') showSavedDns(it);
      else if (b.dataset.act === 'check') checkStatus(it);
      else if (b.dataset.act === 'del') delDomain(it);
    }));
  }

  async function openAdd() {
    selectedDealer = null;
    domainInput.value = '';
    dealerSearch.value = '';
    showStep(1);
    addModal.classList.remove('hidden');
    dealerListEl.innerHTML = '<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i></div>';
    const { data } = await window.sb.from('tenants').select('owner_id,nama_kedai').order('nama_kedai');
    allDealers = (data || []).map(r => ({ id: r.owner_id || '', namaKedai: r.nama_kedai || '' }));
    renderDealers();
  }
  function closeAdd() { addModal.classList.add('hidden'); }
  function showStep(n) { step1.classList.toggle('hidden', n !== 1); step2.classList.toggle('hidden', n !== 2); }

  function renderDealers() {
    const q = dealerSearch.value.toLowerCase();
    const list = allDealers.filter(d => d.namaKedai.toLowerCase().includes(q) || d.id.toLowerCase().includes(q));
    dealerListEl.innerHTML = list.map(d => `
      <div class="picker-item" data-id="${esc(d.id)}">
        <i class="fas fa-store" style="color:var(--violet);font-size:11px"></i>
        <div style="flex:1;min-width:0">
          <div class="picker-item__name">${esc(d.namaKedai)}</div>
          <div class="picker-item__id">${esc(d.id)}</div>
        </div>
        <i class="fas fa-chevron-right" style="color:var(--text-dim);font-size:10px"></i>
      </div>`).join('');
    dealerListEl.querySelectorAll('.picker-item').forEach(el => el.addEventListener('click', () => {
      selectedDealer = allDealers.find(x => x.id === el.dataset.id);
      if (!selectedDealer) return;
      selectedName.textContent = selectedDealer.namaKedai;
      showStep(2);
    }));
  }

  async function doSetup() {
    if (!selectedDealer) return;
    const domain = domainInput.value.trim();
    if (!domain) return;
    closeAdd();
    try {
      const resp = await fetch(EDGE, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'add', hostname: domain, ownerID: selectedDealer.id }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.error || 'Gagal menambah domain.');
      toast('Domain ditambah', 'green');
      showDns({
        domain: data.domain || domain,
        status: data.status || 'PENDING_DNS',
        message: data.message || '',
        dnsRecords: Array.isArray(data.dnsRecords) ? data.dnsRecords : [],
      });
      await load();
    } catch (e) {
      toast('Gagal: ' + e.message, 'red');
    }
  }

  async function checkStatus(item) {
    try {
      const resp = await fetch(EDGE, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'check', hostname: item.domain }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.error || 'Gagal semak status.');
      showDns({
        domain: data.domain || '',
        status: data.status || '',
        message: data.message || '',
        dnsRecords: Array.isArray(data.dnsRecords) ? data.dnsRecords : [],
      });
      await load();
    } catch (e) {
      toast('Gagal semak: ' + e.message, 'red');
    }
  }

  function showSavedDns(item) {
    const records = Array.isArray(item.dnsRecords) ? item.dnsRecords : [];
    if (!records.length) { toast('Tiada DNS records. Tekan "Semak".', 'orange'); return; }
    showDns({
      domain: item.domain.replace('https://', ''),
      status: item.domainStatus || '',
      message: item.domainStatus === 'ACTIVE' ? 'Domain aktif dan sedia digunakan!' : 'Sila set DNS records berikut.',
      dnsRecords: records,
    });
  }

  function showDns({ domain, status, message, dnsRecords }) {
    const isActive = status === 'ACTIVE';
    dnsTitle.textContent = isActive ? 'DOMAIN AKTIF!' : 'DNS RECORDS';
    dnsTitle.style.color = isActive ? 'var(--green)' : 'var(--violet)';
    const records = (dnsRecords || []).map(r => ({ type: r.type || '', host: r.host || '@', value: r.value || '' }));
    dnsBody.innerHTML = `
      <div class="picker-chip picker-chip--violet"><i class="fas fa-language"></i> <span style="font-family:monospace">${esc(domain)}</span></div>
      <p style="font-size:11px;color:var(--text-sub);line-height:1.4;margin:0 0 12px">${esc(message)}</p>
      ${(!isActive && records.length) ? `
        <div style="font-size:10px;font-weight:900;letter-spacing:0.5px;margin-bottom:8px;color:var(--text-primary)">SET DNS RECORDS INI:</div>
        ${records.map(r => `
          <div class="dns-box">
            <div class="dns-box__row">
              <span class="dns-type">${esc(r.type)}</span>
              <span class="dns-host">Name: ${esc(r.host)}</span>
            </div>
            <div class="dns-value" data-copy="${esc(r.value)}"><span style="flex:1">${esc(r.value)}</span><i class="fas fa-copy"></i></div>
          </div>`).join('')}
      ` : ''}
    `;
    dnsBody.querySelectorAll('[data-copy]').forEach(el => el.addEventListener('click', () => {
      navigator.clipboard.writeText(el.dataset.copy).then(() => toast('Disalin!', 'green'));
    }));
    dnsModal.classList.remove('hidden');
  }

  async function delDomain(item) {
    if (!confirm(`Padam domain ${item.domain.replace('https://', '')} untuk ${item.namaKedai}?`)) return;
    const { error } = await window.sb.from('tenants').update({
      domain: null, domain_status: 'PENDING_DNS',
    }).eq('owner_id', item.id);
    if (error) { toast('Gagal padam: ' + error.message, 'red'); return; }
    toast('Domain telah dipadam', 'green');
    await load();
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
