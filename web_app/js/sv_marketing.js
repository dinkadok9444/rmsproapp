/* sv_marketing.js — Supervisor Marketing tab. Mirror sv_marketing_tab.dart.
   3 segments: VOUCHER (shop_vouchers), REFERRAL (referrals, extras in created_by JSON),
   CUSTOMER (derive from jobs by dedupe tel). */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const sb = window.sb;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const $ = (id) => document.getElementById(id);
  const t = (k, p) => (window.svI18n ? window.svI18n.t(k, p) : k);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fmtDate = (iso) => { if (!iso) return '-'; const d = new Date(iso); if (isNaN(d)) return '-';
    const p = (n) => String(n).padStart(2, '0'); return `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)}`; };
  const parseJson = (v) => { try { return typeof v === 'string' && v ? JSON.parse(v) : (v && typeof v === 'object' ? v : {}); } catch { return {}; } };
  const toast = (msg, err) => { const el = document.createElement('div'); el.className = 'admin-toast';
    if (err) el.style.background = 'var(--red, #EF4444)';
    el.innerHTML = `<i class="fas fa-${err?'circle-exclamation':'circle-check'}"></i> ${esc(msg)}`;
    document.body.appendChild(el); setTimeout(()=>el.remove(), 2400); };
  const randCode = (prefix) => prefix + Math.random().toString(36).slice(2, 8).toUpperCase();

  let segment = 'VOUCHER';
  let search = '';
  let vouchers = [], referrals = [], customers = [];

  async function loadVouchers() {
    const { data, error } = await sb.from('shop_vouchers').select('*').eq('branch_id', branchId).order('created_at', { ascending: false });
    if (error) return;
    vouchers = (data || []).map(r => ({
      id: r.id, code: r.voucher_code || '', value: Number(r.value) || 0,
      limit: Number(r.max_uses) || 0, claimed: Number(r.used_amount) || 0,
      status: r.status || 'ACTIVE', expiry: r.expiry || 'LIFETIME', ts: r.created_at,
    }));
    if (segment === 'VOUCHER') render();
  }
  async function loadReferrals() {
    const { data, error } = await sb.from('referrals').select('*').eq('branch_id', branchId).order('created_at', { ascending: false });
    if (error) return;
    referrals = (data || []).map(r => {
      const extra = parseJson(r.created_by);
      return { id: r.id, code: r.code || '', nama: extra.nama || '', tel: extra.tel || '',
        commission: Number(extra.commission) || 0, bank: extra.bank || '', accNo: extra.accNo || '',
        active: r.active === true, ts: r.created_at };
    });
    if (segment === 'REFERRAL') render();
  }
  async function loadCustomers() {
    const { data, error } = await sb.from('jobs').select('nama, tel, created_at, jenis_servis').eq('branch_id', branchId);
    if (error) return;
    const seen = new Map();
    (data || []).forEach(r => {
      const nm = String(r.nama || '').toUpperCase();
      const js = String(r.jenis_servis || '').toUpperCase();
      if (nm === 'JUALAN PANTAS' || js === 'JUALAN') return;
      const tel = String(r.tel || '').replace(/\D/g, '');
      if (!tel) return;
      const cur = seen.get(tel);
      if (!cur) seen.set(tel, { tel, nama: r.nama || '', count: 1, ts: r.created_at });
      else { cur.count++; if (new Date(r.created_at) > new Date(cur.ts)) { cur.ts = r.created_at; cur.nama = r.nama || cur.nama; } }
    });
    customers = Array.from(seen.values()).sort((a,b) => new Date(b.ts) - new Date(a.ts));
    if (segment === 'CUSTOMER') render();
  }
  ['shop_vouchers','referrals','jobs'].forEach(tb => {
    sb.channel(`sv-mk-${tb}-${branchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: tb, filter: `branch_id=eq.${branchId}` },
        tb === 'shop_vouchers' ? loadVouchers : tb === 'referrals' ? loadReferrals : loadCustomers).subscribe();
  });

  function filtered() {
    const q = search.trim().toUpperCase();
    if (segment === 'VOUCHER') return q ? vouchers.filter(v => v.code.toUpperCase().includes(q)) : vouchers;
    if (segment === 'REFERRAL') return q ? referrals.filter(r => r.code.toUpperCase().includes(q) || r.nama.toUpperCase().includes(q) || r.tel.includes(q)) : referrals;
    return q ? customers.filter(c => c.nama.toUpperCase().includes(q) || c.tel.includes(q)) : customers;
  }

  function render() {
    const body = $('svMkBody');
    const addBtn = $('svMkAdd');
    addBtn.style.display = segment === 'CUSTOMER' ? 'none' : '';

    const list = filtered();
    if (!list.length) {
      const ek = segment === 'VOUCHER' ? 'mk.emptyV' : segment === 'REFERRAL' ? 'mk.emptyR' : 'mk.emptyC';
      body.innerHTML = `<div class="sv-mk__empty"><i class="fas fa-inbox"></i><div>${esc(t(ek))}</div></div>`;
      return;
    }
    if (segment === 'VOUCHER') {
      body.innerHTML = list.map(v => `<div class="sv-mk__card">
        <div class="sv-mk__card-top">
          <div class="sv-mk__card-code"><i class="fas fa-ticket"></i> ${esc(v.code)}</div>
          <div class="sv-mk__card-val">${fmtRM(v.value)}</div>
        </div>
        <div class="sv-mk__card-meta">${v.claimed}/${v.limit} ${esc(t('mk.claimed'))} · ${esc(v.expiry)} · ${fmtDate(v.ts)}</div>
        <button class="sv-mk__del" data-act="delV" data-code="${esc(v.code)}"><i class="fas fa-trash-can"></i></button>
      </div>`).join('');
    } else if (segment === 'REFERRAL') {
      body.innerHTML = list.map(r => `<div class="sv-mk__card">
        <div class="sv-mk__card-top">
          <div class="sv-mk__card-code"><i class="fas fa-handshake"></i> ${esc(r.code)}</div>
          <div class="sv-mk__card-val">${r.commission}%</div>
        </div>
        <div class="sv-mk__card-meta"><b>${esc(r.nama)}</b> · ${esc(r.tel)}${r.bank?` · ${esc(r.bank)} ${esc(r.accNo)}`:''}</div>
        <button class="sv-mk__del" data-act="delR" data-code="${esc(r.code)}"><i class="fas fa-trash-can"></i></button>
      </div>`).join('');
    } else {
      body.innerHTML = list.map(c => `<div class="sv-mk__card">
        <div class="sv-mk__card-top">
          <div class="sv-mk__card-code"><i class="fas fa-user"></i> ${esc(c.nama || '-')}</div>
          <div class="sv-mk__card-val">${esc(t('mk.jobCount', { n: c.count }))}</div>
        </div>
        <div class="sv-mk__card-meta"><i class="fas fa-phone"></i> ${esc(c.tel)} · ${fmtDate(c.ts)}</div>
      </div>`).join('');
    }
  }

  // Events
  $('svMkSegs').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-seg]'); if (!b) return;
    segment = b.dataset.seg; search = ''; $('svMkSearch').value = '';
    $('svMkSegs').querySelectorAll('button').forEach(x => x.classList.toggle('is-active', x === b));
    render();
  });
  $('svMkSearch').addEventListener('input', (e) => { search = e.target.value; render(); });
  $('svMkAdd').addEventListener('click', () => {
    if (segment === 'VOUCHER') {
      $('svMkVCode').value = randCode('V'); $('svMkVValue').value = ''; $('svMkVLimit').value = '1'; $('svMkVExpiry').value = '';
      $('svMkVModal').classList.remove('hidden');
    } else if (segment === 'REFERRAL') {
      $('svMkRNama').value=''; $('svMkRTel').value=''; $('svMkRCom').value='5'; $('svMkRBank').value=''; $('svMkRAcc').value='';
      $('svMkRModal').classList.remove('hidden');
    }
  });
  $('svMkVModal').addEventListener('click', (e) => { if (e.target.dataset.close) e.currentTarget.classList.add('hidden'); });
  $('svMkRModal').addEventListener('click', (e) => { if (e.target.dataset.close) e.currentTarget.classList.add('hidden'); });

  $('svMkVSave').addEventListener('click', async () => {
    const code = $('svMkVCode').value.trim().toUpperCase();
    const value = parseFloat($('svMkVValue').value);
    const limit = parseInt($('svMkVLimit').value) || 1;
    const expiry = $('svMkVExpiry').value || 'LIFETIME';
    if (!code || !(value > 0)) { toast(t('c.errSave'), true); return; }
    const { error } = await sb.from('shop_vouchers').insert({
      tenant_id: tenantId, branch_id: branchId, voucher_code: code, value, max_uses: limit, used_amount: 0, status: 'ACTIVE', expiry,
    });
    if (error) { toast(t('c.errSave'), true); return; }
    toast(t('mk.savedV')); $('svMkVModal').classList.add('hidden'); loadVouchers();
  });

  $('svMkRSave').addEventListener('click', async () => {
    const nama = $('svMkRNama').value.trim();
    const tel = $('svMkRTel').value.trim();
    const commission = parseFloat($('svMkRCom').value) || 0;
    const bank = $('svMkRBank').value.trim();
    const accNo = $('svMkRAcc').value.trim();
    if (!nama || !tel) { toast(t('exp.fillAll'), true); return; }
    const code = randCode('R');
    const extra = JSON.stringify({ nama, tel, commission, bank, accNo });
    const { error } = await sb.from('referrals').insert({
      tenant_id: tenantId, branch_id: branchId, code, active: true, created_by: extra,
    });
    if (error) { toast(t('c.errSave'), true); return; }
    toast(t('mk.savedR')); $('svMkRModal').classList.add('hidden'); loadReferrals();
  });

  $('svMkBody').addEventListener('click', async (e) => {
    const b = e.target.closest('button[data-act]'); if (!b) return;
    const code = b.dataset.code;
    if (b.dataset.act === 'delV') {
      if (!confirm(t('mk.confirmDelV'))) return;
      await sb.from('shop_vouchers').delete().eq('voucher_code', code).eq('branch_id', branchId);
      toast(t('c.deleted')); loadVouchers();
    } else if (b.dataset.act === 'delR') {
      if (!confirm(t('mk.confirmDelR'))) return;
      await sb.from('referrals').delete().eq('code', code).eq('branch_id', branchId);
      toast(t('c.deleted')); loadReferrals();
    }
  });

  window.addEventListener('sv:lang:changed', render);
  await Promise.all([loadVouchers(), loadReferrals(), loadCustomers()]);
})();
