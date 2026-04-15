/* inventory.js — Supabase. Combined inventory viewer: spareparts + accessories + phones. Read-only. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  let segment = 'SPAREPART';
  let DATA = { SPAREPART: [], ACCESSORIES: [], TELEFON: [] };
  let filters = { status: 'ALL', category: 'ALL', model: 'ALL', sort: 'DESC', search: '' };

  async function fetchAll() {
    const [sp, ac, ph] = await Promise.all([
      window.sb.from('stock_parts').select('*').eq('branch_id', branchId).limit(2000),
      window.sb.from('accessories').select('*').eq('branch_id', branchId).limit(2000),
      window.sb.from('phone_stock').select('*').eq('branch_id', branchId).limit(2000),
    ]);
    DATA.SPAREPART = sp.data || [];
    DATA.ACCESSORIES = ac.data || [];
    DATA.TELEFON = ph.data || [];
  }

  function currentRows() {
    let rows = (DATA[segment] || []).slice();
    const q = (filters.search || '').toLowerCase();
    rows = rows.filter((r) => {
      if (filters.status !== 'ALL' && (r.status || 'AVAILABLE').toUpperCase() !== filters.status) return false;
      if (filters.category !== 'ALL' && (r.category || '').toUpperCase() !== filters.category) return false;
      if (segment === 'TELEFON' && filters.model !== 'ALL' && (r.model || r.device_name || '') !== filters.model) return false;
      if (q) {
        const hay = [(r.sku||''),(r.part_name||''),(r.item_name||''),(r.device_name||''),(r.model||''),(r.imei||''),(r.siri||'')].join(' ').toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
    rows.sort((a, b) => {
      const ta = a.created_at || '';
      const tb = b.created_at || '';
      return filters.sort === 'ASC' ? ta.localeCompare(tb) : tb.localeCompare(ta);
    });
    return rows;
  }

  function renderStats(rows) {
    const items = rows.length;
    const qty = rows.reduce((s, r) => s + (Number(r.qty) || (segment === 'TELEFON' ? 1 : 0)), 0);
    const value = rows.reduce((s, r) => s + ((Number(r.price) || 0) * (Number(r.qty) || (segment === 'TELEFON' ? 1 : 0))), 0);
    const low = rows.filter((r) => segment !== 'TELEFON' && (Number(r.qty) || 0) <= 2).length;
    $('stItems').textContent = items;
    $('stQty').textContent = qty;
    $('stValue').textContent = fmtRM(value);
    $('stLow').textContent = low;
  }

  function populateCategoryFilter() {
    const src = DATA[segment] || [];
    const cats = Array.from(new Set(src.map((r) => (r.category || '').toUpperCase()).filter(Boolean)));
    $('fCategory').innerHTML = '<option value="ALL">Semua</option>' + cats.map((c) => `<option value="${c}">${c}</option>`).join('');
    if (segment === 'TELEFON') {
      const models = Array.from(new Set(src.map((r) => r.model || r.device_name || '').filter(Boolean)));
      $('fModel').innerHTML = '<option value="ALL">Semua</option>' + models.map((m) => `<option value="${m}">${m}</option>`).join('');
    }
    document.querySelectorAll('.inv-phone-only').forEach((el) => { el.hidden = segment !== 'TELEFON'; });
  }

  function refresh() {
    const rows = currentRows();
    renderStats(rows);
    const list = $('invList');
    $('invEmpty').hidden = rows.length > 0;
    list.innerHTML = rows.map((r) => {
      const name = r.part_name || r.item_name || r.device_name || r.model || '—';
      const sub = r.sku || r.imei || r.siri || '';
      const qty = segment === 'TELEFON' ? 1 : (Number(r.qty) || 0);
      return `<div class="inv-card" data-id="${r.id}">
        <div class="inv-card__hd">
          <span class="inv-card__name">${name}</span>
          <span class="inv-card__qty">${qty}</span>
        </div>
        <div class="inv-card__meta">
          <span>${sub}</span>
          <span>${r.category || ''}</span>
          <span>${fmtRM(r.price)}</span>
          <span class="inv-card__status">${r.status || 'AVAILABLE'}</span>
        </div>
      </div>`;
    }).join('');
    $('listTitle').textContent = 'Senarai ' + (segment === 'SPAREPART' ? 'Sparepart' : segment === 'ACCESSORIES' ? 'Aksesori' : 'Telefon');
  }

  document.querySelectorAll('.inv-seg-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.inv-seg-btn').forEach((b) => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      segment = btn.dataset.seg;
      filters.category = 'ALL'; filters.model = 'ALL';
      populateCategoryFilter();
      refresh();
    });
  });

  $('fStatus').addEventListener('change', (e) => { filters.status = e.target.value; refresh(); });
  $('fCategory').addEventListener('change', (e) => { filters.category = e.target.value; refresh(); });
  $('fModel').addEventListener('change', (e) => { filters.model = e.target.value; refresh(); });
  $('fSort').addEventListener('change', (e) => { filters.sort = e.target.value; refresh(); });
  $('fSearch').addEventListener('input', (e) => { filters.search = e.target.value; refresh(); });

  function subscribe(table) {
    window.sb.channel(table + '-inv-' + branchId)
      .on('postgres_changes', { event: '*', schema: 'public', table, filter: `branch_id=eq.${branchId}` }, async () => {
        await fetchAll(); populateCategoryFilter(); refresh();
      }).subscribe();
  }
  ['stock_parts','accessories','phone_stock'].forEach(subscribe);

  await fetchAll();
  populateCategoryFilter();
  refresh();
})();
