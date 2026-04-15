/* db_cust.js — Supabase. Derive customer DB from jobs + phone_sales. Mirror db_cust_screen.dart. */
(async function () {
  'use strict';
  const ctx = await window.requireAuth();
  if (!ctx) return;
  const tenantId = ctx.tenant_id;
  const branchId = ctx.current_branch_id;

  const $ = (id) => document.getElementById(id);
  const fmtRM = (n) => 'RM ' + (Number(n) || 0).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function snack(msg, err) {
    const el = document.createElement('div');
    el.className = 'dc-snack' + (err ? ' err' : '');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2000);
  }

  let JOBS = [];
  let SALES = [];
  let REFERRALS = [];
  let seg = 0; // 0=repair, 1=sales
  let filters = { sort: 'TERBARU', time: 'SEMUA', aff: 'SEMUA', search: '', date: '' };
  let page = 1;
  const PAGE_SIZE = 30;

  async function fetchAll() {
    const [j, s, r] = await Promise.all([
      window.sb.from('jobs').select('id,siri,nama,tel,model,total,payment_status,status,kerosakan,created_at').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(3000),
      window.sb.from('phone_sales').select('*').eq('branch_id', branchId).is('deleted_at', null).order('sold_at', { ascending: false }).limit(3000),
      window.sb.from('referrals').select('*').eq('tenant_id', tenantId).limit(2000),
    ]);
    JOBS = j.data || [];
    SALES = s.data || [];
    REFERRALS = r.data || [];
  }

  function hasRef(tel) {
    const t = (tel || '').replace(/\D/g, '');
    if (!t) return false;
    return REFERRALS.some((rf) => {
      try {
        const cb = typeof rf.created_by === 'string' ? JSON.parse(rf.created_by) : rf.created_by;
        return cb && (cb.tel || '').replace(/\D/g, '') === t;
      } catch (e) { return false; }
    });
  }

  function inTimeRange(iso) {
    if (!iso) return false;
    if (filters.time === 'SEMUA' && !filters.date) return true;
    const d = new Date(iso);
    if (filters.date) {
      const pick = new Date(filters.date);
      return d.toDateString() === pick.toDateString();
    }
    const now = new Date();
    if (filters.time === 'HARI_INI') return d.toDateString() === now.toDateString();
    if (filters.time === 'BULAN_INI') return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
    return true;
  }

  function repairCustomers() {
    const map = new Map();
    JOBS.forEach((j) => {
      const key = (j.tel || '').replace(/\D/g, '') || (j.nama || '').toLowerCase();
      if (!key) return;
      if (!inTimeRange(j.created_at)) return;
      const cur = map.get(key) || { key, nama: j.nama, tel: j.tel, model: j.model, total: 0, visits: 0, last: '', jobs: [] };
      cur.total += Number(j.total) || 0;
      cur.visits += 1;
      cur.jobs.push(j);
      if (!cur.last || (j.created_at || '') > cur.last) cur.last = j.created_at;
      map.set(key, cur);
    });
    return Array.from(map.values());
  }
  function salesList() {
    return SALES.filter((s) => inTimeRange(s.sold_at));
  }

  function applyFilters(rows) {
    const q = (filters.search || '').toLowerCase();
    return rows.filter((r) => {
      if (q) {
        const hay = [(r.nama||r.customer_name||''),(r.tel||r.customer_phone||''),(r.model||r.device_name||'')].join(' ').toLowerCase();
        if (!hay.includes(q)) return false;
      }
      if (filters.aff === 'AFFILIATE' && !hasRef(r.tel || r.customer_phone)) return false;
      if (filters.aff === 'BELUM' && hasRef(r.tel || r.customer_phone)) return false;
      return true;
    }).sort((a, b) => {
      if (filters.sort === 'A-Z') return (a.nama || a.customer_name || '').localeCompare(b.nama || b.customer_name || '');
      return (b.last || b.sold_at || '').localeCompare(a.last || a.sold_at || '');
    });
  }

  function renderRepairCard(c) {
    const ref = hasRef(c.tel);
    return `<div class="dc-card${ref ? ' has-ref' : ''}" data-tel="${c.tel || ''}">
      <div style="display:flex;justify-content:space-between;gap:8px;">
        <span class="dc-card__nama">${c.nama || '—'}</span>
        <span class="dc-card__harga">${fmtRM(c.total)}</span>
      </div>
      <div class="dc-info">
        <span><i class="fas fa-phone"></i>${c.tel || '—'}</span>
        <span><i class="fas fa-mobile-screen"></i>${c.model || '—'}</span>
        <span><i class="fas fa-clock-rotate-left"></i>${c.visits}x</span>
      </div>
      <div class="dc-badges">
        ${ref ? '<span class="dc-badge" style="background:#eab30822;color:#eab308;"><i class="fas fa-handshake"></i>AFFILIATE</span>' : ''}
        <span class="dc-badge" style="background:#2563eb22;color:#2563eb;">REPAIR</span>
      </div>
    </div>`;
  }
  function renderSalesCard(s) {
    return `<div class="dc-card sales">
      <div class="dc-phone-img"><i class="fas fa-mobile-screen"></i></div>
      <div style="flex:1;min-width:0;">
        <div style="display:flex;justify-content:space-between;">
          <span class="dc-card__nama">${s.customer_name || '—'}</span>
          <span class="dc-card__harga">${fmtRM(s.total_price)}</span>
        </div>
        <div class="dc-info">
          <span><i class="fas fa-phone"></i>${s.customer_phone || '—'}</span>
          <span><i class="fas fa-mobile-screen"></i>${s.device_name || '—'}</span>
        </div>
      </div>
    </div>`;
  }

  function refresh() {
    const repair = repairCustomers();
    const sales = salesList();
    $('cntRepair').textContent = repair.length;
    $('cntSales').textContent = sales.length;

    const rows = seg === 0 ? applyFilters(repair) : applyFilters(sales);
    const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    if (page > totalPages) page = totalPages;
    const slice = rows.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

    $('dcEmpty').hidden = rows.length > 0;
    $('dcList').innerHTML = slice.map((r) => seg === 0 ? renderRepairCard(r) : renderSalesCard(r)).join('');
    $('dcPagination').hidden = totalPages <= 1;
    $('pageInfo').textContent = `${page} / ${totalPages}`;
    $('btnPrev').disabled = page <= 1;
    $('btnNext').disabled = page >= totalPages;
    $('dcFooter').textContent = rows.length + ' rekod';
  }

  document.querySelectorAll('.dc-toggle button').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.dc-toggle button').forEach((b) => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      seg = Number(btn.dataset.seg);
      page = 1;
      refresh();
    });
  });

  $('dcSearch').addEventListener('input', (e) => { filters.search = e.target.value; page = 1; refresh(); });
  $('fSort').addEventListener('change', (e) => { filters.sort = e.target.value; refresh(); });
  $('fTime').addEventListener('change', (e) => { filters.time = e.target.value; filters.date = ''; $('dcDateLbl').textContent = 'TARIKH'; refresh(); });
  $('fAff').addEventListener('change', (e) => { filters.aff = e.target.value; refresh(); });
  $('dcDateBtn').addEventListener('click', () => $('dcDate').click());
  $('dcDate').addEventListener('change', (e) => { filters.date = e.target.value; $('dcDateLbl').textContent = e.target.value || 'TARIKH'; refresh(); });
  $('btnPrev').addEventListener('click', () => { if (page > 1) { page--; refresh(); } });
  $('btnNext').addEventListener('click', () => { page++; refresh(); });

  $('btnExport').addEventListener('click', () => {
    const rows = seg === 0 ? applyFilters(repairCustomers()) : applyFilters(salesList());
    const headers = seg === 0 ? ['Nama','Tel','Model','Total','Visits'] : ['Nama','Tel','Device','Total','Sold At'];
    const lines = [headers.join(',')];
    rows.forEach((r) => {
      const row = seg === 0
        ? [r.nama, r.tel, r.model, r.total, r.visits]
        : [r.customer_name, r.customer_phone, r.device_name, r.total_price, r.sold_at];
      lines.push(row.map((v) => `"${(v || '').toString().replace(/"/g, '""')}"`).join(','));
    });
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'db_cust_' + Date.now() + '.csv';
    a.click();
    snack('Export selesai');
  });

  document.querySelectorAll('[data-close]').forEach((el) => el.addEventListener('click', () => el.closest('.dc-modal-bg').classList.remove('show')));

  // ───────── Modal helpers ─────────
  function esc(s) { return (s == null ? '' : String(s)).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
  function fmtTel(tel) { return (tel || '').replace(/\D/g, ''); }
  function closeAllModals() { document.querySelectorAll('.dc-modal-bg.show').forEach((m) => m.classList.remove('show')); }

  function openActionModal(cust) {
    const nama = cust.nama || cust.customer_name || '—';
    const tel = cust.tel || cust.customer_phone || '';
    const telClean = fmtTel(tel);
    const waNum = telClean.startsWith('0') ? '6' + telClean : telClean;
    const jobs = (cust.jobs || []).slice().sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
    const job = jobs[0] || { nama, tel, siri: '—' };

    $('actionBody').innerHTML = `
      <div style="padding:12px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;margin-bottom:14px;">
        <div style="font-weight:900;font-size:13px;color:#0f172a;">${esc(nama.toUpperCase())}</div>
        <div style="font-size:11px;color:#64748b;margin-top:4px;">
          <i class="fas fa-phone" style="color:#10b981;"></i> ${esc(tel || '—')}
          ${job.siri ? ` · <i class="fas fa-hashtag" style="color:#eab308;"></i> ${esc(job.siri)}` : ''}
        </div>
      </div>
      <div class="dc-action" style="background:#25d36615;color:#25d366;border:1px solid #25d36633;" data-act="wa">
        <i class="fab fa-whatsapp"></i> WHATSAPP
      </div>
      <div class="dc-action" style="background:#10b98115;color:#10b981;border:1px solid #10b98133;" data-act="tel">
        <i class="fas fa-phone"></i> CALL ${esc(tel || '')}
      </div>
      <div class="dc-action" style="background:#3b82f615;color:#3b82f6;border:1px solid #3b82f633;" data-act="email">
        <i class="fas fa-envelope"></i> EMAIL
      </div>
      <div class="dc-action" style="background:#eab30815;color:#eab308;border:1px solid #eab30833;" data-act="referral">
        <i class="fas fa-handshake"></i> LIHAT REFERRAL
      </div>
      <div class="dc-action" style="background:#06b6d415;color:#06b6d4;border:1px solid #06b6d433;" data-act="link">
        <i class="fas fa-share-nodes"></i> HANTAR LINK
      </div>
      <div class="dc-action" style="background:#a855f715;color:#a855f7;border:1px solid #a855f733;" data-act="gallery">
        <i class="fas fa-images"></i> GALERI
      </div>
      <div class="dc-action" style="background:#f9731615;color:#f97316;border:1px solid #f9731633;" data-act="notes">
        <i class="fas fa-pen-to-square"></i> EDIT NOTES
      </div>`;

    $('modalAction').classList.add('show');

    $('actionBody').querySelectorAll('[data-act]').forEach((el) => {
      el.addEventListener('click', () => {
        const act = el.dataset.act;
        if (act === 'wa') {
          if (!waNum) { snack('Tel tiada', true); return; }
          window.open(`https://wa.me/${waNum}`, '_blank');
        } else if (act === 'tel') {
          if (!tel) { snack('Tel tiada', true); return; }
          window.location.href = `tel:${tel}`;
        } else if (act === 'email') {
          const em = prompt('Email pelanggan:');
          if (em) window.location.href = `mailto:${em}?subject=${encodeURIComponent('RMS Pro — ' + nama)}`;
        } else if (act === 'referral') {
          closeAllModals();
          openReferralModal(cust);
        } else if (act === 'link') {
          closeAllModals();
          openLinkModal(cust);
        } else if (act === 'gallery') {
          closeAllModals();
          openGalleryModal(cust);
        } else if (act === 'notes') {
          editNotes(cust);
        }
      });
    });
  }

  async function editNotes(cust) {
    const jobs = (cust.jobs || []).slice().sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
    const job = jobs[0];
    if (!job) { snack('Tiada job', true); return; }
    const cur = job.catatan || '';
    const v = prompt('Notes untuk ' + (cust.nama || '—') + ':', cur);
    if (v == null) return;
    const { error } = await window.sb.from('jobs').update({ catatan: v }).eq('id', job.id);
    if (error) { snack('Gagal: ' + error.message, true); return; }
    job.catatan = v;
    snack('Notes disimpan');
  }

  function openReferralModal(cust) {
    const telClean = fmtTel(cust.tel || cust.customer_phone);
    const myRefs = REFERRALS.filter((rf) => {
      try {
        const cb = typeof rf.created_by === 'string' ? JSON.parse(rf.created_by) : rf.created_by;
        return cb && fmtTel(cb.tel) === telClean;
      } catch (e) { return false; }
    });
    $('referralBody').innerHTML = `
      <div style="margin-bottom:12px;font-size:12px;color:#64748b;">
        Referral oleh <b style="color:#0f172a;">${esc(cust.nama || '—')}</b> (${esc(cust.tel || '—')})
      </div>
      ${myRefs.length === 0
        ? '<div class="dc-empty"><i class="fas fa-handshake"></i><p>Tiada referral.</p></div>'
        : myRefs.map((rf) => `
          <div class="dc-claim">
            <div>
              <div style="font-weight:900;font-size:13px;color:#eab308;">${esc(rf.code || '—')}</div>
              <div style="font-size:10px;color:#64748b;margin-top:2px;">
                Diskaun: ${rf.discount_percent ? rf.discount_percent + '%' : fmtRM(rf.discount_amount || 0)} ·
                Guna: ${rf.used_count || 0}${rf.max_uses ? '/' + rf.max_uses : ''} ·
                Status: ${esc(rf.status || 'ACTIVE')}
              </div>
            </div>
            <button class="dc-page-btn" data-copy="${esc(rf.code)}"><i class="fas fa-copy"></i></button>
          </div>
        `).join('')}
    `;
    $('referralBody').querySelectorAll('[data-copy]').forEach((b) => {
      b.addEventListener('click', () => { navigator.clipboard.writeText(b.dataset.copy); snack('Kod disalin'); });
    });
    $('modalReferral').classList.add('show');
  }

  function openLinkModal(cust) {
    const jobs = (cust.jobs || []).slice().sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
    const origin = window.location.origin;
    $('linkBody').innerHTML = `
      <div style="margin-bottom:12px;font-size:12px;color:#64748b;">
        Public tracking link untuk <b style="color:#0f172a;">${esc(cust.nama || '—')}</b>
      </div>
      ${jobs.length === 0
        ? '<div class="dc-empty"><i class="fas fa-link-slash"></i><p>Tiada job.</p></div>'
        : jobs.map((j) => {
          const url = `${origin}/track.html?siri=${encodeURIComponent(j.siri || '')}&tenant=${encodeURIComponent(ctx.tenant_id)}`;
          return `<div class="dc-link-box" style="background:#10b98115;border:1px solid #10b98133;">
            <div class="code" style="color:#10b981;">${esc(j.siri || '—')} — ${esc(j.model || '')}</div>
            <div class="url">${esc(url)}</div>
            <div class="dc-link-actions">
              <button style="background:#25d366;" data-wa="${esc(url)}" data-tel="${esc(cust.tel || '')}"><i class="fab fa-whatsapp"></i> WA</button>
              <button style="background:#2563eb;" data-copy="${esc(url)}"><i class="fas fa-copy"></i> SALIN</button>
            </div>
          </div>`;
        }).join('')}
    `;
    $('linkBody').querySelectorAll('[data-copy]').forEach((b) => {
      b.addEventListener('click', () => { navigator.clipboard.writeText(b.dataset.copy); snack('Link disalin'); });
    });
    $('linkBody').querySelectorAll('[data-wa]').forEach((b) => {
      b.addEventListener('click', () => {
        const tel = fmtTel(b.dataset.tel);
        const waNum = tel.startsWith('0') ? '6' + tel : tel;
        const msg = encodeURIComponent('Semak status repair anda: ' + b.dataset.wa);
        window.open(`https://wa.me/${waNum}?text=${msg}`, '_blank');
      });
    });
    $('modalLink').classList.add('show');
  }

  async function openGalleryModal(cust) {
    $('galTitle').textContent = 'GALERI — ' + (cust.nama || '—').toUpperCase();
    $('galleryBody').innerHTML = '<p style="padding:20px;color:#64748b;grid-column:1/-1;">Memuatkan…</p>';
    $('modalGallery').classList.add('show');

    const jobIds = (cust.jobs || []).map((j) => j.id).filter(Boolean);
    let imgRows = [];
    if (jobIds.length) {
      const { data } = await window.sb
        .from('jobs')
        .select('id, siri, img_sebelum_depan, img_sebelum_belakang, img_selepas_depan, img_selepas_belakang, img_cust')
        .in('id', jobIds);
      imgRows = data || [];
    }
    const types = [
      { key: 'img_sebelum_depan', label: 'SEBELUM (DEPAN)', color: '#2563eb' },
      { key: 'img_sebelum_belakang', label: 'SEBELUM (BLKNG)', color: '#2563eb' },
      { key: 'img_selepas_depan', label: 'SELEPAS (DEPAN)', color: '#10b981' },
      { key: 'img_selepas_belakang', label: 'SELEPAS (BLKNG)', color: '#10b981' },
      { key: 'img_cust', label: 'GAMBAR CUST', color: '#eab308' },
    ];
    const cells = [];
    imgRows.forEach((r) => {
      types.forEach((t) => {
        const url = (r[t.key] || '').toString();
        if (url && url.startsWith('http')) {
          cells.push(`<div class="dc-gal-cell" style="border-color:${t.color}33;">
            <div class="label" style="color:${t.color};background:${t.color}15;">${t.label} · ${esc(r.siri || '')}</div>
            <div class="img" style="background-image:url('${esc(url)}');" data-url="${esc(url)}"></div>
          </div>`);
        }
      });
    });
    $('galleryBody').innerHTML = cells.length
      ? cells.join('')
      : '<div class="dc-empty" style="grid-column:1/-1;"><i class="fas fa-image"></i><p>Tiada gambar.</p></div>';
    $('galleryBody').querySelectorAll('[data-url]').forEach((el) => {
      el.addEventListener('click', () => window.open(el.dataset.url, '_blank'));
    });
  }

  // Wire card clicks → action modal
  $('dcList').addEventListener('click', (e) => {
    const card = e.target.closest('.dc-card');
    if (!card) return;
    const tel = card.dataset.tel || '';
    const telClean = fmtTel(tel);
    if (seg === 0) {
      const c = repairCustomers().find((x) => fmtTel(x.tel) === telClean);
      if (c) openActionModal(c);
    } else {
      // Sales card — build minimal cust from sales row + related jobs
      const idx = Array.from($('dcList').children).indexOf(card);
      const rows = applyFilters(salesList());
      const s = rows[(page - 1) * PAGE_SIZE + idx];
      if (!s) return;
      const relJobs = JOBS.filter((j) => fmtTel(j.tel) === fmtTel(s.customer_phone));
      openActionModal({
        nama: s.customer_name,
        tel: s.customer_phone,
        model: s.device_name,
        jobs: relJobs,
      });
    }
  });

  window.sb.channel('dbcust-jobs-' + branchId).on('postgres_changes', { event: '*', schema: 'public', table: 'jobs', filter: `branch_id=eq.${branchId}` }, async () => { await fetchAll(); refresh(); }).subscribe();
  window.sb.channel('dbcust-sales-' + branchId).on('postgres_changes', { event: '*', schema: 'public', table: 'phone_sales', filter: `branch_id=eq.${branchId}` }, async () => { await fetchAll(); refresh(); }).subscribe();

  await fetchAll();
  refresh();
})();
