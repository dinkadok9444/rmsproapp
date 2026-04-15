/* kolaborasi.js — Cross-tenant collab tasks. Mirror collab_screen.dart.
   Outbox = tasks saya post (owner_tenant_id=tenantId).
   Arkib = tasks saya ambil (taken_by_tenant_id=tenantId) atau archived. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  function toast(msg) {
    const t = $('clToast'); if (!t) return;
    t.textContent = msg; t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 1800);
  }

  let VIEW = 'OUTBOX'; // OUTBOX | INBOX | ARCHIVE
  let statusFilter = 'SEMUA';
  let ROWS = [];
  let TICKET = null; // clicked repair ticket
  let DEALER = null; // selected dealer tenant
  let SAVED_DEALERS = []; // from localStorage cache
  let PHOTOS = []; // photo URLs for current send modal
  const PHOTO_BUCKET = 'repairs';
  const storageHelper = window.storageHelper || window.SupabaseStorage;

  try { SAVED_DEALERS = JSON.parse(localStorage.getItem('cl-saved-dealers') || '[]'); } catch (_) {}

  async function fetchList() {
    let q = window.sb.from('collab_tasks').select('*').order('created_at', { ascending: false }).limit(500);
    if (VIEW === 'OUTBOX') {
      q = q.eq('owner_tenant_id', tenantId).eq('archived', false);
    } else if (VIEW === 'INBOX') {
      // OPEN tasks dari other tenants — boleh accept
      q = q.eq('status', 'OPEN').neq('owner_tenant_id', tenantId).eq('archived', false);
    } else {
      q = q.or(`taken_by_tenant_id.eq.${tenantId},archived.eq.true`);
    }
    const { data, error } = await q;
    if (error) { console.error(error); return []; }
    return data || [];
  }

  function filterRows(rows) {
    if (statusFilter === 'SEMUA') return rows;
    return rows.filter((r) => (r.status || '').toUpperCase() === statusFilter);
  }

  function statusColor(st) {
    switch ((st || '').toUpperCase()) {
      case 'OPEN': case 'PENDING': return '#2563eb';
      case 'TERIMA': case 'TAKEN': return '#10b981';
      case 'IN PROGRESS': return '#f59e0b';
      case 'COMPLETED': case 'DONE': return '#059669';
      case 'REJECT': case 'RETURN REJECT': return '#dc2626';
      case 'DELIVERED': return '#8b5cf6';
      default: return '#64748b';
    }
  }

  function render() {
    const rows = filterRows(ROWS);
    $('clCount').textContent = String(rows.length);
    const titles = {
      OUTBOX: '<i class="fas fa-paper-plane"></i> OUTBOX',
      INBOX: '<i class="fas fa-inbox"></i> INBOX',
      ARCHIVE: '<i class="fas fa-box-archive"></i> ARKIB',
    };
    const nextLabels = { OUTBOX: '<i class="fas fa-inbox"></i> INBOX', INBOX: '<i class="fas fa-box-archive"></i> ARKIB', ARCHIVE: '<i class="fas fa-paper-plane"></i> OUTBOX' };
    $('clTitle').innerHTML = `${titles[VIEW]} <span class="collab-count" id="clCount">${rows.length}</span>`;
    $('clArchiveBtn').innerHTML = nextLabels[VIEW];

    $('clEmpty').classList.toggle('hidden', rows.length > 0);
    $('clList').innerHTML = rows.map((r) => {
      const p = (r.payload && typeof r.payload === 'object') ? r.payload : {};
      const st = (r.status || 'OPEN').toUpperCase();
      const col = statusColor(st);
      return `<div class="lost-card" data-id="${r.id}" style="border-left:4px solid ${col};">
        <div class="lost-card__head">
          <div><b>${r.nama || '—'}</b> <span style="color:#94a3b8;font-size:10px;">· ${r.tel || ''}</span></div>
          <span style="padding:3px 8px;border-radius:6px;background:${col}15;color:${col};font-weight:900;font-size:10px;">${st}</span>
        </div>
        <div class="lost-card__body">
          <div><i class="fas fa-mobile"></i> ${r.model || '—'}</div>
          <div><i class="fas fa-wrench"></i> ${r.kerosakan || '—'}</div>
          ${r.harga ? `<div><i class="fas fa-money-bill"></i> RM ${Number(r.harga).toFixed(2)}</div>` : ''}
          ${p.kurier ? `<div><i class="fas fa-truck"></i> ${p.kurier} ${p.tracking ? '· ' + p.tracking : ''}</div>` : ''}
          ${r.poster_name ? `<div><i class="fas fa-store"></i> ${r.poster_name}</div>` : ''}
        </div>
      </div>`;
    }).join('');

    $('clList').querySelectorAll('.lost-card').forEach((el) => {
      el.addEventListener('click', () => openInfo(ROWS.find((r) => r.id === el.dataset.id)));
    });
  }

  function openInfo(row) {
    if (!row) return;
    const p = (row.payload && typeof row.payload === 'object') ? row.payload : {};
    $('clInfoStatus').textContent = row.status || '—';
    $('clInfoStatus').style.color = statusColor(row.status);
    $('clInfoNota').textContent = p.nota_dealer || p.catatan || '—';
    $('clInfoKurier').textContent = p.return_kurier || p.kurier || '—';
    $('clInfoTrack').textContent = p.return_tracking || p.tracking || '—';

    // Photo viewer
    const photoWrap = $('clInfoPhotos');
    if (photoWrap) {
      const photos = Array.isArray(p.photos) ? p.photos : [];
      if (!photos.length) {
        photoWrap.textContent = '—';
      } else {
        photoWrap.innerHTML = photos.map((u) => `<img src="${u}" data-full="${u}" style="width:60px;height:60px;object-fit:cover;border-radius:6px;border:1px solid #e2e8f0;cursor:pointer;">`).join('');
        photoWrap.querySelectorAll('img').forEach((im) => im.addEventListener('click', () => window.open(im.dataset.full, '_blank')));
      }
    }

    // INBOX dynamic actions: TERIMA / REJECT
    let actionBar = document.getElementById('clInfoActions');
    if (!actionBar) {
      actionBar = document.createElement('div');
      actionBar.id = 'clInfoActions';
      actionBar.style.cssText = 'display:flex;gap:8px;margin-top:14px;';
      $('clInfoModal').querySelector('.lost-modal').appendChild(actionBar);
    }
    actionBar.innerHTML = '';

    const isInbox = row.status === 'OPEN' && row.owner_tenant_id !== tenantId;
    const isMyTaken = row.taken_by_tenant_id === tenantId && row.status !== 'COMPLETED';

    if (isInbox) {
      const btnAccept = document.createElement('button');
      btnAccept.className = 'btn-submit';
      btnAccept.style.cssText = 'flex:1;background:#10b981;';
      btnAccept.innerHTML = '<i class="fas fa-check"></i> TERIMA';
      btnAccept.onclick = async () => {
        const { error } = await window.sb.from('collab_tasks').update({
          status: 'TERIMA', taken_by_tenant_id: tenantId,
        }).eq('id', row.id);
        if (error) return toast('Gagal: ' + error.message);
        toast('Tugasan diterima');
        $('clInfoModal').classList.remove('is-open');
        ROWS = await fetchList(); render();
      };
      const btnReject = document.createElement('button');
      btnReject.className = 'btn-submit';
      btnReject.style.cssText = 'flex:1;background:#dc2626;';
      btnReject.innerHTML = '<i class="fas fa-xmark"></i> REJECT';
      btnReject.onclick = async () => {
        const reason = prompt('Sebab reject?') || '';
        const { error } = await window.sb.from('collab_tasks').update({
          status: 'REJECT', payload: { ...p, reject_reason: reason, rejected_by_tenant: tenantId },
        }).eq('id', row.id);
        if (error) return toast('Gagal: ' + error.message);
        toast('Reject');
        $('clInfoModal').classList.remove('is-open');
        ROWS = await fetchList(); render();
      };
      actionBar.append(btnAccept, btnReject);
    } else if (isMyTaken) {
      const STATES = ['IN PROGRESS', 'COMPLETED', 'DELIVERED'];
      STATES.forEach((s) => {
        const b = document.createElement('button');
        b.className = 'btn-submit';
        b.style.cssText = `flex:1;background:${statusColor(s)};font-size:11px;`;
        b.textContent = s;
        b.onclick = async () => {
          const patch = { status: s };
          if (s === 'DELIVERED') {
            const k = prompt('Kurier?') || '';
            const t = prompt('Tracking?') || '';
            patch.payload = { ...p, return_kurier: k, return_tracking: t };
          }
          const { error } = await window.sb.from('collab_tasks').update(patch).eq('id', row.id);
          if (error) return toast('Gagal: ' + error.message);
          toast('Status updated');
          $('clInfoModal').classList.remove('is-open');
          ROWS = await fetchList(); render();
        };
        actionBar.appendChild(b);
      });
    }

    $('clInfoModal').classList.add('is-open');
  }

  // Filter / status
  $('clStatus').addEventListener('change', (e) => { statusFilter = e.target.value; render(); });

  // Cycle view: OUTBOX → INBOX → ARCHIVE → OUTBOX
  $('clArchiveBtn').addEventListener('click', async () => {
    VIEW = VIEW === 'OUTBOX' ? 'INBOX' : VIEW === 'INBOX' ? 'ARCHIVE' : 'OUTBOX';
    ROWS = await fetchList();
    render();
  });

  // ── Send task modal ───────────────────────────────────────
  $('clNewBtn').addEventListener('click', () => {
    TICKET = null; DEALER = null; PHOTOS = [];
    ['clSiri', 'clDealer', 'clKurier', 'clTrack', 'clCatatan'].forEach((k) => { $(k).value = ''; });
    $('clTicket').classList.add('hidden');
    $('clDealerInfo').classList.add('hidden');
    $('clDealerStatus').textContent = '';
    renderPhotoThumbs();
    renderSaved();
    $('clSendModal').classList.add('is-open');
  });

  function renderPhotoThumbs() {
    const wrap = $('clPhotoThumbs');
    if (!wrap) return;
    wrap.innerHTML = PHOTOS.map((u, i) => `
      <div style="position:relative;width:54px;height:54px;">
        <img src="${u}" style="width:54px;height:54px;object-fit:cover;border-radius:6px;border:1px solid #e2e8f0;cursor:pointer;" data-full="${u}">
        <button type="button" data-i="${i}" class="cl-photo-x" style="position:absolute;top:-6px;right:-6px;width:18px;height:18px;border-radius:50%;border:none;background:#dc2626;color:#fff;font-size:10px;cursor:pointer;line-height:1;">×</button>
      </div>`).join('');
    wrap.querySelectorAll('.cl-photo-x').forEach((b) => b.addEventListener('click', (e) => {
      e.stopPropagation();
      PHOTOS.splice(Number(b.dataset.i), 1);
      renderPhotoThumbs();
    }));
    wrap.querySelectorAll('img').forEach((im) => im.addEventListener('click', () => window.open(im.dataset.full, '_blank')));
  }

  const clPhotoBtn = $('clPhotoBtn');
  if (clPhotoBtn) clPhotoBtn.addEventListener('click', async () => {
    try {
      if (!storageHelper || !storageHelper.pickAndUpload) { toast('Storage helper tiada'); return; }
      toast('Memuat naik...');
      const url = await storageHelper.pickAndUpload({
        bucket: PHOTO_BUCKET,
        pathFn: (f) => `${tenantId}/collab/${Date.now()}_${(f.name||'photo').replace(/[^a-zA-Z0-9._-]/g,'_')}`,
      });
      if (!url) return;
      PHOTOS.push(url);
      renderPhotoThumbs();
      toast('Gambar ditambah');
    } catch (err) {
      toast('Gagal upload: ' + (err.message || err));
    }
  });

  function renderSaved() {
    const wrap = $('clSaved');
    if (!SAVED_DEALERS.length) { wrap.classList.add('hidden'); return; }
    wrap.classList.remove('hidden');
    $('clSavedChips').innerHTML = SAVED_DEALERS.map((d, i) => `
      <span class="cl-chip" data-i="${i}" style="padding:5px 10px;border-radius:16px;background:#e2e8f0;cursor:pointer;font-size:11px;margin:3px;display:inline-block;">${d.nama || d.id}</span>
    `).join('');
    $('clSavedChips').querySelectorAll('.cl-chip').forEach((el) => {
      el.addEventListener('click', (ev) => {
        const i = Number(el.dataset.i);
        if (ev.shiftKey) {
          SAVED_DEALERS.splice(i, 1);
          localStorage.setItem('cl-saved-dealers', JSON.stringify(SAVED_DEALERS));
          renderSaved();
        } else {
          DEALER = SAVED_DEALERS[i];
          $('clDealer').value = DEALER.code || DEALER.id || '';
          $('clDlKedai').textContent = DEALER.nama || '—';
          $('clDlTel').textContent = DEALER.tel || '—';
          $('clDealerInfo').classList.remove('hidden');
          $('clDealerStatus').textContent = '';
        }
      });
    });
  }

  $('clSendClose').addEventListener('click', () => $('clSendModal').classList.remove('is-open'));
  $('clInfoClose').addEventListener('click', () => $('clInfoModal').classList.remove('is-open'));

  // Search siri → jobs
  $('clSiriBtn').addEventListener('click', async () => {
    const siri = $('clSiri').value.trim().toUpperCase();
    if (!siri) return;
    const { data } = await window.sb.from('jobs').select('*')
      .eq('branch_id', branchId).ilike('siri', `%${siri}%`).limit(1);
    const r = data && data[0];
    if (!r) { toast('Tiket tidak jumpa'); $('clTicket').classList.add('hidden'); return; }
    TICKET = r;
    $('clTkNama').textContent = r.nama || '—';
    $('clTkModel').textContent = r.model || '—';
    $('clTkTel').textContent = r.tel || '—';
    $('clTkKero').textContent = r.kerosakan || '—';
    $('clTkPass').textContent = r.device_password || '—';
    $('clTicket').classList.remove('hidden');
  });

  // Dealer search — by tenant domain/shop code
  $('clDealerBtn').addEventListener('click', async () => {
    const code = $('clDealer').value.trim();
    if (!code) return;
    $('clDealerStatus').textContent = 'Mencari...';
    const { data } = await window.sb.from('tenants')
      .select('id, nama_kedai, domain, bot_whatsapp').or(`domain.eq.${code},id.eq.${code}`).limit(1);
    const t = data && data[0];
    if (!t) {
      $('clDealerInfo').classList.add('hidden');
      $('clDealerStatus').textContent = 'Dealer tidak jumpa';
      DEALER = null; return;
    }
    const tel = (t.bot_whatsapp && t.bot_whatsapp.phone) || '—';
    DEALER = { id: t.id, nama: t.nama_kedai, tel, code };
    $('clDlKedai').textContent = t.nama_kedai || '—';
    $('clDlTel').textContent = tel;
    $('clDealerInfo').classList.remove('hidden');
    $('clDealerStatus').textContent = '';
    // Save to localStorage
    if (!SAVED_DEALERS.find((x) => x.id === DEALER.id)) {
      SAVED_DEALERS.push(DEALER);
      if (SAVED_DEALERS.length > 10) SAVED_DEALERS = SAVED_DEALERS.slice(-10);
      localStorage.setItem('cl-saved-dealers', JSON.stringify(SAVED_DEALERS));
    }
  });

  $('clSubmit').addEventListener('click', async () => {
    if (!TICKET) { toast('Cari tiket dulu'); return; }
    if (!DEALER) { toast('Cari dealer dulu'); return; }
    const payload = {
      kurier: $('clKurier').value.trim(),
      tracking: $('clTrack').value.trim().toUpperCase(),
      catatan: $('clCatatan').value.trim(),
      siri: TICKET.siri,
      source_job_id: TICKET.id,
      photos: PHOTOS.slice(),
    };
    const row = {
      owner_tenant_id: tenantId,
      poster_shop_id: branchId,
      poster_name: ctx.nama || '',
      nama: TICKET.nama,
      tel: TICKET.tel,
      model: TICKET.model,
      kerosakan: TICKET.kerosakan,
      harga: TICKET.harga || 0,
      status: 'OPEN',
      archived: false,
      taken_by_tenant_id: DEALER.id,
      payload,
    };
    const { error } = await window.sb.from('collab_tasks').insert(row);
    if (error) { toast('Gagal: ' + error.message); return; }
    toast('Tugasan dihantar');
    $('clSendModal').classList.remove('is-open');
    ROWS = await fetchList(); render();
  });

  window.sb.channel('collab-' + tenantId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'collab_tasks' }, async () => {
      ROWS = await fetchList(); render();
    })
    .subscribe();

  ROWS = await fetchList();
  render();
})();
