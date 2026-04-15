/* sv_expense.js — Supervisor Expense tab. Mirror sv_expense_tab.dart.
   Table: expenses (id, tenant_id, branch_id, category, description, amount, notes, paid_by, created_at).
   Realtime stream + filter by time/kategori/search, CRUD via modal. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const sb = window.sb;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;
  if (!branchId) return;

  const t = (k, p) => (window.svI18n ? window.svI18n.t(k, p) : k);
  // Canonical kategori keys (persisted as MS in DB). Display uses i18n.
  const KATEGORI = ['Gaji Staff','Bil TNB','Bil Air','Sewa','Internet','Alat Ganti','Pengangkutan','Makan/Minum','Lain-lain'];
  const KAT_KEY  = { 'Gaji Staff':'expK.gaji','Bil TNB':'expK.tnb','Bil Air':'expK.air','Sewa':'expK.sewa','Internet':'expK.internet','Alat Ganti':'expK.alat','Pengangkutan':'expK.transport','Makan/Minum':'expK.makan','Lain-lain':'expK.lain' };
  const katLabel = (k) => KAT_KEY[k] ? t(KAT_KEY[k]) : k;
  const COLORS = {
    GAJI: '#3B82F6', TNB: '#F59E0B', AIR: '#06B6D4', SEWA: '#8B5CF6',
    INTERNET: '#6366F1', ALAT: '#EF4444', PENGANGKUTAN: '#10B981', MAKAN: '#F97316',
  };
  const ICONS = {
    GAJI: 'user-group', TNB: 'bolt', AIR: 'droplet', SEWA: 'house-chimney',
    INTERNET: 'wifi', ALAT: 'screwdriver-wrench', PENGANGKUTAN: 'truck', MAKAN: 'utensils',
  };
  const kattag = (k) => { const u = String(k || '').toUpperCase();
    for (const key of Object.keys(COLORS)) if (u.includes(key)) return key;
    return 'OTHER'; };
  const kCol = (k) => COLORS[kattag(k)] || '#64748B';
  const kIcon = (k) => ICONS[kattag(k)] || 'receipt';

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fmtDate = (iso) => {
    if (!iso) return '-';
    const d = new Date(iso); if (isNaN(d)) return '-';
    const p = (n) => String(n).padStart(2, '0');
    return `${p(d.getDate())}/${p(d.getMonth()+1)}/${String(d.getFullYear()).slice(-2)} ${p(d.getHours())}:${p(d.getMinutes())}`;
  };
  function toast(msg, err) {
    const t = document.createElement('div');
    t.className = 'admin-toast'; if (err) t.style.background = 'var(--red, #EF4444)';
    t.innerHTML = `<i class="fas fa-${err ? 'circle-exclamation' : 'circle-check'}"></i> ${esc(msg)}`;
    document.body.appendChild(t); setTimeout(() => t.remove(), 2600);
  }

  // ── State
  let rows = [];
  let filterTime = 'THIS_MONTH';
  let customFrom = null, customTo = null;
  let filterKat = 'SEMUA';
  let sort = 'ZA';
  let search = '';
  let editingId = null;

  // ── Data load + realtime
  async function reload() {
    const { data, error } = await sb.from('expenses').select('*').eq('branch_id', branchId).order('created_at', { ascending: false });
    if (error) { toast(t('c.errLoad'), true); return; }
    rows = data || [];
    render();
  }
  sb.channel('sv-expenses-' + branchId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'expenses', filter: `branch_id=eq.${branchId}` }, reload)
    .subscribe();

  // ── Filter chain
  function inTimeRange(iso) {
    if (!iso) return false;
    const d = new Date(iso); if (isNaN(d)) return false;
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    switch (filterTime) {
      case 'TODAY': return d >= todayStart;
      case 'THIS_WEEK': {
        const dow = now.getDay() || 7;
        const weekStart = new Date(todayStart); weekStart.setDate(weekStart.getDate() - (dow - 1));
        return d >= weekStart;
      }
      case 'THIS_MONTH': return d >= new Date(now.getFullYear(), now.getMonth(), 1);
      case 'CUSTOM': {
        if (!customFrom || !customTo) return true;
        const f = new Date(customFrom); const t = new Date(customTo); t.setHours(23,59,59,999);
        return d >= f && d <= t;
      }
      default: return true;
    }
  }
  function filtered() {
    let list = rows.filter(r => inTimeRange(r.created_at));
    if (filterKat !== 'SEMUA') list = list.filter(r => String(r.category || '').toUpperCase() === filterKat.toUpperCase());
    const q = search.trim().toUpperCase();
    if (q) list = list.filter(r =>
      String(r.description || '').toUpperCase().includes(q) ||
      String(r.category || '').toUpperCase().includes(q) ||
      String(r.notes || '').toUpperCase().includes(q) ||
      String(r.paid_by || '').toUpperCase().includes(q)
    );
    list.sort((a, b) => {
      const ta = new Date(a.created_at).getTime() || 0;
      const tb = new Date(b.created_at).getTime() || 0;
      return sort === 'AZ' ? ta - tb : tb - ta;
    });
    return list;
  }

  // ── Render
  function render() {
    const list = filtered();
    const total = list.reduce((s, r) => s + (Number(r.amount) || 0), 0);
    $('svExpCount').textContent = t('exp.count', { n: list.length });
    $('svExpTotal').textContent = fmtRM(total);

    // Chips (rebuild every render so labels reflect current lang)
    const chips = $('svExpChips');
    const all = ['SEMUA', ...KATEGORI];
    chips.innerHTML = all.map(k => `<button data-k="${esc(k)}">${esc(k === 'SEMUA' ? t('c.all').toUpperCase() : katLabel(k))}</button>`).join('');
    chips.querySelectorAll('button').forEach(b => b.classList.toggle('is-active', b.dataset.k === filterKat));
    if (!chips.dataset.bound) {
      chips.dataset.bound = '1';
      chips.addEventListener('click', (e) => {
        const b = e.target.closest('button'); if (!b) return;
        filterKat = b.dataset.k; render();
      });
    }

    // List
    const body = $('svExpBody');
    if (!rows.length) {
      body.innerHTML = `<div class="sv-exp__empty"><i class="fas fa-wallet"></i><div>${esc(t('exp.empty1'))}</div><small>${esc(t('exp.empty2'))}</small></div>`;
      return;
    }
    if (!list.length) { body.innerHTML = `<div class="sv-exp__empty"><div>${esc(t('c.noMatch'))}</div></div>`; return; }
    body.innerHTML = list.map(r => {
      const k = r.category || 'Lain-lain';
      const col = kCol(k);
      return `<div class="sv-exp__card">
        <div class="sv-exp__card-head">
          <div class="sv-exp__card-kat" style="color:${col}">
            <span class="sv-exp__card-ic" style="background:${col}26"><i class="fas fa-${kIcon(k)}" style="color:${col}"></i></span>
            <span>${esc(katLabel(k))}</span>
          </div>
          <div class="sv-exp__card-amt" style="color:${col};background:${col}1a;border-color:${col}66">- ${fmtRM(r.amount)}</div>
        </div>
        <div class="sv-exp__card-desc">${esc(r.description || '-')}</div>
        ${r.notes ? `<div class="sv-exp__card-note">${esc(r.notes)}</div>` : ''}
        <div class="sv-exp__card-foot">
          <div>
            ${r.paid_by ? `<div class="sv-exp__card-staff">${esc(r.paid_by)}</div>` : ''}
            <div class="sv-exp__card-ts">${fmtDate(r.created_at)}</div>
          </div>
          <div class="sv-exp__card-actions">
            <button data-act="edit" data-id="${esc(r.id)}"><i class="fas fa-pen-to-square"></i></button>
            <button data-act="del" data-id="${esc(r.id)}" class="is-danger"><i class="fas fa-trash-can"></i></button>
          </div>
        </div>
      </div>`;
    }).join('');
  }

  // ── Wire time buttons
  $('svExpTime').addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    filterTime = b.dataset.t;
    $('svExpTime').querySelectorAll('button').forEach(x => x.classList.toggle('is-active', x === b));
    $('svExpRange').classList.toggle('hidden', filterTime !== 'CUSTOM');
    render();
  });
  $('svExpFrom').addEventListener('change', (e) => { customFrom = e.target.value; render(); });
  $('svExpTo').addEventListener('change', (e) => { customTo = e.target.value; render(); });
  $('svExpSearch').addEventListener('input', (e) => { search = e.target.value; render(); });
  $('svExpSort').addEventListener('change', (e) => { sort = e.target.value; render(); });

  // ── Modal
  const modal = $('svExpModal');
  function openForm(existing) {
    editingId = existing ? existing.id : null;
    $('svExpModalTitle').textContent = existing ? t('exp.modalEdit') : t('exp.modalNew');
    $('svExpSaveLbl').textContent = existing ? t('c.update') : t('c.save');
    const sel = $('svExpFKategori');
    sel.innerHTML = '';
    KATEGORI.forEach(k => { const o = document.createElement('option'); o.value = k; o.textContent = katLabel(k); sel.appendChild(o); });
    sel.value = existing && KATEGORI.includes(existing.category) ? existing.category : KATEGORI[0];
    $('svExpFPerkara').value = existing?.description || '';
    $('svExpFJumlah').value = existing ? (Number(existing.amount) || 0).toFixed(2) : '';
    $('svExpFCatatan').value = existing?.notes || '';
    modal.classList.remove('hidden');
  }
  function closeForm() { modal.classList.add('hidden'); editingId = null; }
  modal.addEventListener('click', (e) => { if (e.target.dataset.close) closeForm(); });
  $('svExpAdd').addEventListener('click', () => openForm(null));

  $('svExpSave').addEventListener('click', async () => {
    const perkara = $('svExpFPerkara').value.trim();
    const jumlah = parseFloat($('svExpFJumlah').value);
    if (!perkara || !(jumlah >= 0)) { toast(t('exp.fillAll'), true); return; }
    const payload = {
      tenant_id: tenantId,
      branch_id: branchId,
      category: $('svExpFKategori').value,
      description: perkara,
      amount: jumlah,
      notes: $('svExpFCatatan').value.trim(),
    };
    let error;
    if (editingId) ({ error } = await sb.from('expenses').update(payload).eq('id', editingId));
    else { payload.paid_by = ctx.nama || ''; ({ error } = await sb.from('expenses').insert(payload)); }
    if (error) { toast(t('c.errSave'), true); return; }
    toast(editingId ? t('exp.savedEdit') : t('exp.savedNew'));
    closeForm(); reload();
  });

  // ── List actions (delegated)
  $('svExpBody').addEventListener('click', async (e) => {
    const b = e.target.closest('button[data-act]'); if (!b) return;
    const id = b.dataset.id;
    if (b.dataset.act === 'edit') {
      const row = rows.find(r => String(r.id) === String(id)); if (row) openForm(row);
    } else if (b.dataset.act === 'del') {
      if (!confirm(t('exp.confirmDel'))) return;
      const { error } = await sb.from('expenses').delete().eq('id', id);
      if (error) { toast(t('c.errDelete'), true); return; }
      toast(t('c.deleted')); reload();
    }
  });

  window.addEventListener('sv:lang:changed', render);

  await reload();
})();
