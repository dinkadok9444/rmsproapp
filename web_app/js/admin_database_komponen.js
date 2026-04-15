/* Admin → Database Komponen. Master catalog kod komponen phone.
   Source: master_component_categories (dynamic tabs) + master_components (items). Owner-only write. */
(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const listEl = $('list');
  const searchEl = $('searchInput');
  const countEl = $('countMeta');
  const tabsEl = $('mkTabs');

  let CATS = [];
  let ROWS = [];
  let tab = null;
  let editingId = null;

  $('btnBack').addEventListener('click', () => { window.location.href = 'dashboard.html'; });
  $('btnReload').addEventListener('click', loadAll);
  searchEl.addEventListener('input', render);
  $('btnAddItem').addEventListener('click', () => openEdit(null));
  $('btnAddCategory').addEventListener('click', openCatModal);
  $('editClose').addEventListener('click', closeEdit);
  $('btnCancel').addEventListener('click', closeEdit);
  $('btnSave').addEventListener('click', save);
  $('btnDelete').addEventListener('click', remove);
  $('catClose').addEventListener('click', () => $('catModal').classList.add('hidden'));
  $('catAdd').addEventListener('click', addCategory);
  $('catInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') addCategory(); });

  (async function init() {
    const ctx = await window.requireAuth();
    if (!ctx || ctx.role !== 'admin') { window.location.href = '/index.html'; return; }
    await loadAll();
  })();

  async function loadAll() {
    listEl.innerHTML = `<div class="admin-loading"><i class="fas fa-spinner fa-spin"></i> Memuat…</div>`;
    const [cRes, iRes] = await Promise.all([
      window.sb.from('master_component_categories').select('*').order('sort_order', { ascending: true }).order('name', { ascending: true }),
      window.sb.from('master_components').select('*').order('brand').order('model').limit(10000),
    ]);
    if (cRes.error) { listEl.innerHTML = `<div class="admin-error">${cRes.error.message}</div>`; return; }
    if (iRes.error) { listEl.innerHTML = `<div class="admin-error">${iRes.error.message}</div>`; return; }
    CATS = cRes.data || [];
    ROWS = iRes.data || [];
    if (!tab || !CATS.find(c => c.name === tab)) tab = CATS[0] ? CATS[0].name : null;
    renderTabs();
    renderCategorySelect();
    render();
  }

  function renderTabs() {
    if (!CATS.length) {
      tabsEl.innerHTML = `<div class="admin-empty" style="padding:14px"><i class="fas fa-folder-open"></i><div>Belum ada category. Klik <b>TAMBAH CATEGORY</b>.</div></div>`;
      return;
    }
    tabsEl.innerHTML = CATS.map(c => {
      const count = ROWS.filter(r => r.category === c.name).length;
      const active = c.name === tab ? 'is-active' : '';
      return `<button class="mk-tab ${active}" data-tab="${esc(c.name)}">${esc(c.name)} <span class="mk-tab__count">${count}</span></button>`;
    }).join('');
    tabsEl.querySelectorAll('.mk-tab').forEach(b => b.addEventListener('click', () => {
      tab = b.dataset.tab;
      renderTabs();
      render();
    }));
  }

  function renderCategorySelect() {
    $('fCategory').innerHTML = CATS.map(c => `<option value="${esc(c.name)}">${esc(c.name)}</option>`).join('');
  }

  function render() {
    if (!tab) { listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-folder-open"></i><div>Tambah category dulu.</div></div>`; countEl.textContent = ''; return; }
    const q = searchEl.value.trim().toLowerCase();
    const all = ROWS.filter(r => r.category === tab);
    const filtered = all.filter(r => !q || [r.brand, r.model, r.code, r.notes].some(v => (v || '').toLowerCase().includes(q)));
    countEl.textContent = `${filtered.length} / ${all.length}`;
    if (!filtered.length) {
      listEl.innerHTML = `<div class="admin-empty"><i class="fas fa-inbox"></i><div>Tiada rekod.</div></div>`;
      return;
    }
    listEl.innerHTML = filtered.map(r => `
      <div class="mk-row" data-id="${r.id}">
        <div class="mk-row__main">
          <div class="mk-row__brand">${esc(r.brand)}</div>
          <div class="mk-row__model">${esc(r.model)}</div>
          ${r.notes ? `<div class="mk-row__notes">${esc(r.notes)}</div>` : ''}
        </div>
        <div class="mk-row__code">${esc(r.code)}</div>
        <button class="icon-btn mk-row__edit" title="Edit"><i class="fas fa-pen"></i></button>
      </div>
    `).join('');
    listEl.querySelectorAll('.mk-row').forEach(el => {
      el.querySelector('.mk-row__edit').addEventListener('click', () => {
        const row = ROWS.find(x => x.id === el.dataset.id);
        if (row) openEdit(row);
      });
    });
  }

  function openEdit(row) {
    if (!CATS.length) { alert('Tambah category dulu.'); return; }
    editingId = row ? row.id : null;
    $('editTitle').innerHTML = row ? '<i class="fas fa-pen"></i> Edit Item' : '<i class="fas fa-plus"></i> Tambah Item';
    $('fCategory').value = (row && row.category) || tab || CATS[0].name;
    $('fBrand').value = (row && row.brand) || '';
    $('fModel').value = (row && row.model) || '';
    $('fCode').value = (row && row.code) || '';
    $('fNotes').value = (row && row.notes) || '';
    $('btnDelete').hidden = !row;
    $('editModal').classList.remove('hidden');
  }

  function closeEdit() { $('editModal').classList.add('hidden'); editingId = null; }

  async function save() {
    const payload = {
      category: $('fCategory').value,
      brand: $('fBrand').value.trim(),
      model: $('fModel').value.trim(),
      code: $('fCode').value.trim(),
      notes: $('fNotes').value.trim() || null,
      updated_at: new Date().toISOString(),
    };
    if (!payload.brand || !payload.model || !payload.code) { alert('Brand, Model, dan Kod wajib diisi.'); return; }
    const btn = $('btnSave'); const original = btn.innerHTML;
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> MENYIMPAN…';
    try {
      const op = editingId
        ? window.sb.from('master_components').update(payload).eq('id', editingId)
        : window.sb.from('master_components').insert(payload);
      const { error } = await op;
      if (error) throw error;
      closeEdit();
      await loadAll();
      toast(editingId ? 'Berjaya dikemaskini.' : 'Berjaya ditambah.');
    } catch (e) { alert('Ralat: ' + e.message); }
    finally { btn.disabled = false; btn.innerHTML = original; }
  }

  async function remove() {
    if (!editingId) return;
    if (!confirm('Padam rekod ini?')) return;
    const { error } = await window.sb.from('master_components').delete().eq('id', editingId);
    if (error) { alert('Ralat: ' + error.message); return; }
    closeEdit();
    await loadAll();
    toast('Berjaya dipadam.');
  }

  // ---- Category management ----
  function openCatModal() { renderCatList(); $('catInput').value = ''; $('catModal').classList.remove('hidden'); }

  function renderCatList() {
    const listEl = $('catList');
    if (!CATS.length) { listEl.innerHTML = `<div class="admin-empty" style="padding:8px"><i class="fas fa-inbox"></i><div>Tiada category.</div></div>`; return; }
    listEl.innerHTML = CATS.map(c => {
      const count = ROWS.filter(r => r.category === c.name).length;
      return `<div class="mk-cat-row" data-id="${c.id}" data-name="${esc(c.name)}">
        <span>${esc(c.name)} <small style="color:var(--text-muted)">(${count})</small></span>
        <button class="icon-btn mk-cat-del" title="Padam"><i class="fas fa-trash"></i></button>
      </div>`;
    }).join('');
    listEl.querySelectorAll('.mk-cat-del').forEach(b => b.addEventListener('click', (e) => {
      const row = e.target.closest('.mk-cat-row');
      removeCategory(row.dataset.id, row.dataset.name);
    }));
  }

  async function addCategory() {
    const name = $('catInput').value.trim().toUpperCase();
    if (!name) return;
    if (CATS.find(c => c.name === name)) { alert('Category dah wujud.'); return; }
    const { error } = await window.sb.from('master_component_categories').insert({ name, sort_order: CATS.length + 1 });
    if (error) { alert('Ralat: ' + error.message); return; }
    $('catInput').value = '';
    await loadAll();
    renderCatList();
    toast('Category ditambah.');
  }

  async function removeCategory(id, name) {
    const count = ROWS.filter(r => r.category === name).length;
    if (count > 0) { alert(`Tak boleh padam — masih ada ${count} item dalam category "${name}". Pindah/padam item dulu.`); return; }
    if (!confirm(`Padam category "${name}"?`)) return;
    const { error } = await window.sb.from('master_component_categories').delete().eq('id', id);
    if (error) { alert('Ralat: ' + error.message); return; }
    await loadAll();
    renderCatList();
    toast('Category dipadam.');
  }

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }

  function toast(msg) {
    const t = document.createElement('div');
    t.className = 'admin-toast';
    t.innerHTML = `<i class="fas fa-circle-check"></i> ${msg}`;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2400);
  }
})();
