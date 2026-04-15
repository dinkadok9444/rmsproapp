/* sv_staff.js — Supervisor Staff tab. Mirror sv_staff_tab.dart.
   Tables: branch_staff (id, branch_id, tenant_id, nama, phone, pin, status, payload JSON),
   global_staff (tel PK, payload, upsert mirror), staff_logs (for delete cascade).
   NOTE: image upload skipped — takes URL text input for now. */
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
  const toast = (msg, err) => {
    const el = document.createElement('div');
    el.className = 'admin-toast'; if (err) el.style.background = 'var(--red, #EF4444)';
    el.innerHTML = `<i class="fas fa-${err?'circle-exclamation':'circle-check'}"></i> ${esc(msg)}`;
    document.body.appendChild(el); setTimeout(()=>el.remove(), 2400);
  };

  let staff = [];
  let editingId = null;

  async function reload() {
    const { data, error } = await sb.from('branch_staff').select('*').eq('branch_id', branchId).order('created_at');
    if (error) { toast(t('c.errLoad'), true); return; }
    staff = (data || []).map(r => ({
      id: r.id, nama: r.nama || '', phone: r.phone || '', pin: r.pin || '',
      status: r.status || 'active',
      profileUrl: (r.payload && typeof r.payload === 'object') ? (r.payload.profileUrl || '') : '',
    }));
    render();
  }
  sb.channel(`sv-staff-${branchId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'branch_staff', filter: `branch_id=eq.${branchId}` }, reload)
    .subscribe();

  function render() {
    $('svStCount').textContent = String(staff.length);
    const body = $('svStBody');
    if (!staff.length) { body.innerHTML = `<div class="sv-st__empty"><i class="fas fa-users"></i><div>${esc(t('st.empty'))}</div></div>`; return; }
    body.innerHTML = staff.map(s => {
      const isActive = s.status === 'active';
      const initial = (s.nama || '?').charAt(0).toUpperCase();
      return `<div class="sv-st__card">
        <div class="sv-st__avatar">${s.profileUrl ? `<img src="${esc(s.profileUrl)}" alt="">` : esc(initial)}</div>
        <div class="sv-st__info">
          <div class="sv-st__nama">${esc(s.nama || '-')}</div>
          <div class="sv-st__meta"><i class="fas fa-phone"></i> ${esc(s.phone || '-')} · PIN: <b>${esc(s.pin || '----')}</b></div>
          <span class="sv-st__status ${isActive?'is-active':'is-suspended'}">${esc(t(isActive ? 'st.stActive' : 'st.stSuspended'))}</span>
        </div>
        <div class="sv-st__acts">
          <button data-act="edit" data-id="${esc(s.id)}" title="Edit"><i class="fas fa-pen-to-square"></i></button>
          <button data-act="toggle" data-id="${esc(s.id)}" title="${esc(t(isActive ? 'st.actSuspend' : 'st.actActivate'))}"><i class="fas fa-${isActive?'pause':'play'}"></i></button>
          <button data-act="pin" data-id="${esc(s.id)}" title="${esc(t('st.actResetPin'))}"><i class="fas fa-key"></i></button>
          <button data-act="del" data-id="${esc(s.id)}" class="is-danger" title="Del"><i class="fas fa-trash-can"></i></button>
        </div>
      </div>`;
    }).join('');
  }

  // Modal
  const modal = $('svStModal');
  function openModal(existing) {
    editingId = existing ? existing.id : null;
    $('svStModalTitle').textContent = t(existing ? 'st.modalEdit' : 'st.modalAdd');
    $('svStSaveLbl').textContent = t(existing ? 'c.update' : 'c.save');
    $('svStFNama').value = existing?.nama || '';
    $('svStFPhone').value = existing?.phone || '';
    $('svStFPin').value = existing?.pin || '';
    $('svStFProfile').value = existing?.profileUrl || '';
    updatePreview(existing?.profileUrl || '');
    modal.classList.remove('hidden');
  }
  function closeModal() { modal.classList.add('hidden'); editingId = null; }
  modal.addEventListener('click', (e) => { if (e.target.dataset.close) closeModal(); });
  $('svStAdd').addEventListener('click', () => openModal(null));

  $('svStSave').addEventListener('click', async () => {
    const nama = $('svStFNama').value.trim();
    const phone = $('svStFPhone').value.trim();
    const pin = $('svStFPin').value.trim();
    const profileUrl = $('svStFProfile').value.trim();
    if (!nama || !phone || !pin) { toast(t('st.fillAll'), true); return; }
    if (!/^\d{4}$/.test(pin)) { toast(t('st.pin4'), true); return; }
    const payload = profileUrl ? { profileUrl } : {};
    if (editingId) {
      const { error } = await sb.from('branch_staff').update({ nama, phone, pin, payload }).eq('id', editingId);
      if (error) { toast(t('c.errSave'), true); return; }
      await sb.from('global_staff').upsert({ tel: phone, payload: { nama, phone, pin, ...payload } }, { onConflict: 'tel' });
      toast(t('st.savedEdit'));
    } else {
      const { error } = await sb.from('branch_staff').insert({ tenant_id: tenantId, branch_id: branchId, nama, phone, pin, status: 'active', payload });
      if (error) { toast(t('c.errSave'), true); return; }
      await sb.from('global_staff').upsert({ tel: phone, payload: { nama, phone, pin, ...payload } }, { onConflict: 'tel' });
      toast(t('st.savedNew'));
    }
    closeModal(); reload();
  });

  $('svStBody').addEventListener('click', async (e) => {
    const b = e.target.closest('button[data-act]'); if (!b) return;
    const id = b.dataset.id;
    const s = staff.find(x => String(x.id) === String(id));
    if (!s) return;
    if (b.dataset.act === 'edit') { openModal(s); return; }
    if (b.dataset.act === 'toggle') {
      const newStatus = s.status === 'active' ? 'suspended' : 'active';
      const { error } = await sb.from('branch_staff').update({ status: newStatus }).eq('id', id);
      if (error) { toast(t('c.errSave'), true); return; }
      toast(t(newStatus === 'active' ? 'st.stActive' : 'st.stSuspended'));
      reload();
      return;
    }
    if (b.dataset.act === 'pin') {
      const newPin = prompt(t('st.resetPinQ'), s.pin || '');
      if (!newPin || !/^\d{4}$/.test(newPin)) { if (newPin != null) toast(t('st.pin4'), true); return; }
      const { error } = await sb.from('branch_staff').update({ pin: newPin }).eq('id', id);
      if (error) { toast(t('c.errSave'), true); return; }
      toast(t('st.savedEdit')); reload();
      return;
    }
    if (b.dataset.act === 'del') {
      if (!confirm(t('st.confirmDel'))) return;
      await sb.from('branch_staff').delete().eq('id', id);
      if (s.phone) {
        await sb.from('global_staff').delete().eq('tel', s.phone);
        try { await sb.from('staff_logs').delete().eq('staff_phone', s.phone); } catch {}
      }
      toast(t('c.deleted')); reload();
    }
  });

  function updatePreview(url) {
    const el = $('svStFPreview');
    if (url) el.innerHTML = `<img src="${esc(url)}" alt="">`;
    else el.innerHTML = `<i class="fas fa-user"></i>`;
  }
  $('svStFProfile').addEventListener('input', (e) => updatePreview(e.target.value.trim()));
  $('svStUpload').addEventListener('click', async () => {
    const phone = $('svStFPhone').value.trim().replace(/[\s\-()]/g, '');
    if (!phone) { toast(t('st.needPhoneFirst'), true); return; }
    if (!window.SupabaseStorage) { toast('Storage helper missing', true); return; }
    try {
      toast(t('st.uploading'));
      const url = await window.SupabaseStorage.pickAndUpload({
        bucket: 'staff_avatars',
        pathFn: () => `${tenantId}/${branchId}/${phone}.jpg`,
        maxDim: 512,
      });
      if (!url) return;
      const bust = url + (url.includes('?') ? '&' : '?') + 'v=' + Date.now();
      $('svStFProfile').value = bust;
      updatePreview(bust);
      toast(t('st.uploaded'));
    } catch (e) {
      toast(t('st.uploadErr'), true);
    }
  });

  window.addEventListener('sv:lang:changed', render);
  await reload();
})();
