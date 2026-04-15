/* sv_i18n.js — Tiny i18n for supervisor shell. MS (default) / EN.
   Persist to localStorage['rms.lang']. Fires window event 'sv:lang:changed'. */
(function () {
  'use strict';
  const KEY = 'rms.lang';

  const DICT = {
    // Shell & header
    'app.title':        { ms: 'RMS PRO', en: 'RMS PRO' },
    'hdr.branch':       { ms: 'BRANCH', en: 'BRANCH' },
    'hdr.supervisor':   { ms: 'SUPERVISOR', en: 'SUPERVISOR' },
    'notif.line':       { ms: 'Notifikasi: {n} baru.', en: 'Notifications: {n} new.' },

    // Top tabs
    'tab.dashboard':    { ms: 'Dashboard', en: 'Dashboard' },
    'tab.inventory':    { ms: 'Inventori', en: 'Inventory' },
    'tab.kewangan':     { ms: 'Kewangan', en: 'Finance' },
    'tab.refund':       { ms: 'Refund', en: 'Refund' },
    'tab.staff':        { ms: 'Staf', en: 'Staff' },
    'tab.marketing':    { ms: 'Marketing', en: 'Marketing' },
    'tab.expense':      { ms: 'Perbelanjaan', en: 'Expense' },
    'tab.untungrugi':   { ms: 'Untung Rugi', en: 'Profit/Loss' },
    'tab.marketplace':  { ms: 'Marketplace', en: 'Marketplace' },
    'tab.chat':         { ms: 'Chat', en: 'Chat' },
    'tab.settings':     { ms: 'Tetapan', en: 'Settings' },

    // Chat
    'ch.title':         { ms: 'CHAT STAF', en: 'STAFF CHAT' },
    'ch.sub':           { ms: 'Perbualan dalam syarikat (tenant-wide)', en: 'Company-wide conversation' },
    'ch.placeholder':   { ms: 'Tulis mesej...', en: 'Type a message...' },
    'ch.empty':         { ms: 'Belum ada mesej. Mulakan perbualan!', en: 'No messages yet. Start the conversation!' },
    'ch.you':           { ms: 'Anda', en: 'You' },
    'ch.confirmDel':    { ms: 'Padam mesej ini?', en: 'Delete this message?' },

    // Common
    'c.all':            { ms: 'Semua', en: 'All' },
    'c.today':          { ms: 'Hari Ini', en: 'Today' },
    'c.thisWeek':       { ms: 'Minggu Ini', en: 'This Week' },
    'c.thisMonth':      { ms: 'Bulan Ini', en: 'This Month' },
    'c.thisYear':       { ms: 'Tahun Ini', en: 'This Year' },
    'c.pickDate':       { ms: 'Pilih Tarikh', en: 'Pick Date' },
    'c.newest':         { ms: 'Terbaru', en: 'Newest' },
    'c.oldest':         { ms: 'Terlama', en: 'Oldest' },
    'c.save':           { ms: 'SIMPAN', en: 'SAVE' },
    'c.update':         { ms: 'KEMASKINI', en: 'UPDATE' },
    'c.cancel':         { ms: 'BATAL', en: 'CANCEL' },
    'c.delete':         { ms: 'PADAM', en: 'DELETE' },
    'c.summary':        { ms: 'Ringkasan', en: 'Summary' },
    'c.none':           { ms: 'Tiada rekod', en: 'No records' },
    'c.noMatch':        { ms: 'Tiada padanan', en: 'No match' },
    'c.errLoad':        { ms: 'Ralat muat data', en: 'Failed to load data' },
    'c.errSave':        { ms: 'Gagal simpan', en: 'Failed to save' },
    'c.errDelete':      { ms: 'Gagal padam', en: 'Failed to delete' },
    'c.deleted':        { ms: 'Rekod dipadam', en: 'Record deleted' },

    // Dashboard
    'dash.title':       { ms: 'DASHBOARD', en: 'DASHBOARD' },
    'dash.sub':         { ms: 'Statistik jualan & job', en: 'Sales & job statistics' },
    'dash.segRepair':   { ms: 'Job Repair', en: 'Repair Jobs' },
    'dash.segPhone':    { ms: 'Jualan Telefon', en: 'Phone Sales' },
    'dash.fAll':        { ms: 'Semua', en: 'All' },
    'dash.fToday':      { ms: 'Hari Ini', en: 'Today' },
    'dash.fWeek':       { ms: 'Minggu Ini', en: 'This Week' },
    'dash.fMonth':      { ms: 'Bulan Ini', en: 'This Month' },
    'dash.fYear':       { ms: 'Tahun Ini', en: 'This Year' },
    'dash.fCustom':     { ms: 'Pilih Tarikh', en: 'Pick Date' },

    // Settings
    'set.head':         { ms: 'Bahasa / Language', en: 'Language / Bahasa' },
    'set.desc':         { ms: 'Pilih bahasa paparan untuk mod Supervisor.', en: 'Choose display language for Supervisor mode.' },
    'set.savedMs':      { ms: 'Bahasa disimpan', en: 'Bahasa disimpan' },
    'set.savedEn':      { ms: 'Language saved', en: 'Language saved' },

    // Inventory
    'inv.sparepart':    { ms: 'SPAREPART', en: 'SPAREPART' },
    'inv.accessories':  { ms: 'ACCESSORIES', en: 'ACCESSORIES' },
    'inv.phone':        { ms: 'TELEFON', en: 'PHONE' },

    // Expense
    'exp.title':        { ms: 'PERBELANJAAN', en: 'EXPENSES' },
    'exp.newBtn':       { ms: 'REKOD BARU', en: 'NEW RECORD' },
    'exp.totalLbl':     { ms: 'JUMLAH PERBELANJAAN', en: 'TOTAL EXPENSES' },
    'exp.count':        { ms: '{n} rekod', en: '{n} records' },
    'exp.searchPh':     { ms: 'Cari perkara / kategori...', en: 'Search item / category...' },
    'exp.modalNew':     { ms: 'REKOD PERBELANJAAN BARU', en: 'NEW EXPENSE RECORD' },
    'exp.modalEdit':    { ms: 'KEMASKINI PERBELANJAAN', en: 'UPDATE EXPENSE' },
    'exp.kategori':     { ms: 'Kategori', en: 'Category' },
    'exp.perkara':      { ms: 'Perkara / Keterangan', en: 'Item / Description' },
    'exp.perkaraPh':    { ms: 'Cth: Gaji bulan Mac, Bil TNB Mac...', en: 'e.g. March salary, March TNB bill...' },
    'exp.jumlah':       { ms: 'Jumlah (RM)', en: 'Amount (RM)' },
    'exp.catatan':      { ms: 'Catatan (Opsional)', en: 'Notes (Optional)' },
    'exp.catatanPh':    { ms: 'Nota tambahan...', en: 'Additional notes...' },
    'exp.fillAll':      { ms: 'Isi perkara & jumlah', en: 'Fill item & amount' },
    'exp.savedNew':     { ms: 'Perbelanjaan direkodkan!', en: 'Expense recorded!' },
    'exp.savedEdit':    { ms: 'Perbelanjaan dikemaskini!', en: 'Expense updated!' },
    'exp.confirmDel':   { ms: 'Padam rekod perbelanjaan ini?', en: 'Delete this expense record?' },
    'exp.empty1':       { ms: 'Tiada rekod perbelanjaan', en: 'No expense records' },
    'exp.empty2':       { ms: 'Tekan + untuk rekod perbelanjaan baru', en: 'Tap + to add a new expense' },
    'expK.gaji':        { ms: 'Gaji Staff', en: 'Staff Salary' },
    'expK.tnb':         { ms: 'Bil TNB', en: 'Electricity Bill' },
    'expK.air':         { ms: 'Bil Air', en: 'Water Bill' },
    'expK.sewa':        { ms: 'Sewa', en: 'Rent' },
    'expK.internet':    { ms: 'Internet', en: 'Internet' },
    'expK.alat':        { ms: 'Alat Ganti', en: 'Spare Parts' },
    'expK.transport':   { ms: 'Pengangkutan', en: 'Transport' },
    'expK.makan':       { ms: 'Makan/Minum', en: 'Food/Drink' },
    'expK.lain':        { ms: 'Lain-lain', en: 'Others' },

    // Kewangan
    'kew.title':        { ms: 'LAPORAN KEWANGAN', en: 'FINANCE REPORT' },
    'kew.jualan':       { ms: 'JUALAN', en: 'SALES' },
    'kew.expense':      { ms: 'PERBELANJAAN', en: 'EXPENSES' },
    'kew.kasar':        { ms: 'UNTUNG KASAR', en: 'GROSS PROFIT' },
    'kew.bersih':       { ms: 'UNTUNG BERSIH', en: 'NET PROFIT' },
    'kew.pecahan':      { ms: 'PECAHAN JUALAN', en: 'SALES BREAKDOWN' },
    'kew.repair':       { ms: 'Servis / Repair', en: 'Service / Repair' },
    'kew.quickSale':    { ms: 'Jualan Pantas', en: 'Quick Sale' },
    'kew.phone':        { ms: 'Jualan Telefon', en: 'Phone Sales' },
    'kew.totalSales':   { ms: 'Jumlah Jualan', en: 'Total Sales' },
    'kew.costPhone':    { ms: 'Kos Barang (Telefon)', en: 'Goods Cost (Phone)' },
    'kew.expenseLbl':   { ms: 'Perbelanjaan', en: 'Expenses' },
    'kew.listSales':    { ms: 'SENARAI JUALAN', en: 'SALES LIST' },
    'kew.listExpense':  { ms: 'SENARAI PERBELANJAAN', en: 'EXPENSE LIST' },

    // Untung Rugi
    'pl.title':         { ms: 'UNTUNG RUGI', en: 'PROFIT & LOSS' },
    'pl.sub':           { ms: 'Analisis prestasi kewangan', en: 'Financial performance analysis' },
    'pl.revenue':       { ms: 'HASIL', en: 'REVENUE' },
    'pl.cogs':          { ms: 'KOS JUALAN', en: 'COGS' },
    'pl.gross':         { ms: 'UNTUNG KASAR', en: 'GROSS PROFIT' },
    'pl.opex':          { ms: 'PERBELANJAAN OPERASI', en: 'OPERATING EXPENSES' },
    'pl.net':           { ms: 'UNTUNG BERSIH', en: 'NET PROFIT' },
    'pl.margin':        { ms: 'Margin', en: 'Margin' },
    'pl.breakdown':     { ms: 'PECAHAN HASIL', en: 'REVENUE BREAKDOWN' },
    'pl.ratio':         { ms: 'NISBAH KEWANGAN', en: 'FINANCIAL RATIOS' },
    'pl.grossMargin':   { ms: 'Margin Kasar', en: 'Gross Margin' },
    'pl.netMargin':     { ms: 'Margin Bersih', en: 'Net Margin' },
    'pl.opexRatio':     { ms: 'Nisbah Operasi', en: 'Opex Ratio' },
    'pl.count':         { ms: 'COUNT', en: 'COUNT' },
    'pl.jobDone':       { ms: 'job siap', en: 'jobs done' },
    'pl.cost':          { ms: 'KOS', en: 'COST' },
    'pl.profit':        { ms: 'UNTUNG', en: 'PROFIT' },
    'pl.income':        { ms: 'Hasil', en: 'Revenue' },
    'pl.loss':          { ms: 'RUGI', en: 'LOSS' },
    'pl.records':       { ms: 'rekod', en: 'records' },
    'pl.sparepart':     { ms: 'sparepart', en: 'parts' },
    'pl.unitSold':      { ms: 'unit dijual', en: 'units sold' },
    'pl.phoneModal':    { ms: 'modal telefon', en: 'phone cost' },
    'pl.sales':         { ms: 'Jualan', en: 'Sales' },
    'pl.expenseChip':   { ms: 'Perbelanjaan', en: 'Expenses' },

    // Refund / Claim
    'rc.refund':        { ms: 'REFUND', en: 'REFUND' },
    'rc.claim':         { ms: 'CLAIM', en: 'CLAIM' },
    'rc.titleRefund':   { ms: 'KELULUSAN REFUND', en: 'REFUND APPROVAL' },
    'rc.titleClaim':    { ms: 'KELULUSAN CLAIM', en: 'CLAIM APPROVAL' },
    'rc.pending':       { ms: '{n} PENDING', en: '{n} PENDING' },
    'rc.searchPh':      { ms: 'Cari siri / nama...', en: 'Search serial / name...' },
    'rc.emptyR':        { ms: 'Tiada permohonan refund', en: 'No refund requests' },
    'rc.emptyC':        { ms: 'Tiada permohonan claim', en: 'No claim requests' },
    'rc.approve':       { ms: 'LULUS', en: 'APPROVE' },
    'rc.reject':        { ms: 'TOLAK', en: 'REJECT' },
    'rc.approveRQ':     { ms: 'Lulus refund ini?', en: 'Approve this refund?' },
    'rc.approveCQ':     { ms: 'Lulus claim ini?', en: 'Approve this claim?' },
    'rc.rejectQ':       { ms: 'Nyatakan sebab penolakan:', en: 'Provide rejection reason:' },
    'rc.reason':        { ms: 'Sebab', en: 'Reason' },
    'rc.approvedR':     { ms: 'Refund diluluskan', en: 'Refund approved' },
    'rc.rejectedR':     { ms: 'Refund ditolak', en: 'Refund rejected' },
    'rc.approvedC':     { ms: 'Claim diluluskan', en: 'Claim approved' },
    'rc.rejectedC':     { ms: 'Claim ditolak', en: 'Claim rejected' },

    // Staff
    'st.title':         { ms: 'SENARAI STAF', en: 'STAFF LIST' },
    'st.addBtn':        { ms: 'TAMBAH STAF', en: 'ADD STAFF' },
    'st.modalAdd':      { ms: 'TAMBAH STAF', en: 'ADD STAFF' },
    'st.modalEdit':     { ms: 'KEMASKINI STAF', en: 'UPDATE STAFF' },
    'st.fNama':         { ms: 'Nama', en: 'Name' },
    'st.fPhone':        { ms: 'No. Telefon', en: 'Phone' },
    'st.fPin':          { ms: 'PIN (4 digit)', en: 'PIN (4 digits)' },
    'st.fProfile':      { ms: 'URL Gambar (Opsional)', en: 'Photo URL (Optional)' },
    'st.empty':         { ms: 'Tiada staf', en: 'No staff' },
    'st.stActive':      { ms: 'AKTIF', en: 'ACTIVE' },
    'st.stSuspended':   { ms: 'DIGANTUNG', en: 'SUSPENDED' },
    'st.actSuspend':    { ms: 'Gantung', en: 'Suspend' },
    'st.actActivate':   { ms: 'Aktifkan', en: 'Activate' },
    'st.actResetPin':   { ms: 'Reset PIN', en: 'Reset PIN' },
    'st.resetPinQ':     { ms: 'PIN baru (4 digit):', en: 'New PIN (4 digits):' },
    'st.fillAll':       { ms: 'Isi nama, telefon & PIN', en: 'Fill name, phone & PIN' },
    'st.pin4':          { ms: 'PIN mesti 4 digit', en: 'PIN must be 4 digits' },
    'st.savedNew':      { ms: 'Staf ditambah', en: 'Staff added' },
    'st.savedEdit':     { ms: 'Staf dikemaskini', en: 'Staff updated' },
    'st.confirmDel':    { ms: 'Padam staf ini?', en: 'Delete this staff?' },
    'st.upload':        { ms: 'Muat Naik', en: 'Upload' },
    'st.uploading':     { ms: 'Memuat naik...', en: 'Uploading...' },
    'st.uploaded':      { ms: 'Gambar dimuat naik', en: 'Image uploaded' },
    'st.needPhoneFirst':{ ms: 'Isi telefon dulu', en: 'Fill phone first' },
    'st.uploadErr':     { ms: 'Gagal muat naik', en: 'Upload failed' },

    // Marketing
    'mk.voucher':       { ms: 'VOUCHER', en: 'VOUCHER' },
    'mk.referral':      { ms: 'REFERRAL', en: 'REFERRAL' },
    'mk.customer':      { ms: 'PELANGGAN', en: 'CUSTOMER' },
    'mk.vTitle':        { ms: 'VOUCHER BARU', en: 'NEW VOUCHER' },
    'mk.vCode':         { ms: 'Kod Voucher', en: 'Voucher Code' },
    'mk.vValue':        { ms: 'Nilai (RM)', en: 'Value (RM)' },
    'mk.vLimit':        { ms: 'Had Guna', en: 'Usage Limit' },
    'mk.vExpiry':       { ms: 'Tarikh Luput', en: 'Expiry Date' },
    'mk.rTitle':        { ms: 'REFERRAL BARU', en: 'NEW REFERRAL' },
    'mk.rCommission':   { ms: 'Komisen (%)', en: 'Commission (%)' },
    'mk.rBank':         { ms: 'Bank', en: 'Bank' },
    'mk.rAccNo':        { ms: 'No. Akaun', en: 'Account No.' },
    'mk.emptyV':        { ms: 'Tiada voucher', en: 'No vouchers' },
    'mk.emptyR':        { ms: 'Tiada referral', en: 'No referrals' },
    'mk.emptyC':        { ms: 'Tiada pelanggan', en: 'No customers' },
    'mk.claimed':       { ms: 'guna', en: 'used' },
    'mk.savedV':        { ms: 'Voucher ditambah', en: 'Voucher added' },
    'mk.savedR':        { ms: 'Referral ditambah', en: 'Referral added' },
    'mk.confirmDelV':   { ms: 'Padam voucher?', en: 'Delete voucher?' },
    'mk.confirmDelR':   { ms: 'Padam referral?', en: 'Delete referral?' },
    'mk.jobCount':      { ms: '{n} job', en: '{n} jobs' },

    // Marketplace
    'mp.title':         { ms: 'MARKETPLACE', en: 'MARKETPLACE' },
    'mp.blocked':       { ms: 'Menunggu migrasi Flutter marketplace ke Supabase. Modul ini masih guna Firestore di Flutter — port ke web ditangguh sehingga migrasi selesai.', en: 'Waiting for Flutter marketplace migration to Supabase. This module still uses Firestore on Flutter — web port deferred until migration completes.' },
  };

  let cur = localStorage.getItem(KEY) || 'ms';

  function t(key, params) {
    const entry = DICT[key];
    let s = (entry && entry[cur]) || (entry && entry.ms) || key;
    if (params) for (const k in params) s = s.replace('{' + k + '}', params[k]);
    return s;
  }
  function apply(root) {
    const r = root || document;
    r.querySelectorAll('[data-i18n]').forEach(el => {
      const k = el.getAttribute('data-i18n');
      const txt = t(k);
      // Preserve leading icon/marker child if any — only replace last text node if child is <i>
      const firstIcon = el.querySelector(':scope > i');
      if (firstIcon) {
        const span = el.querySelector(':scope > span[data-i18n-target]');
        if (span) span.textContent = txt;
        else {
          // append/replace trailing text node
          let tail = null;
          el.childNodes.forEach(n => { if (n.nodeType === 3) tail = n; });
          if (tail) tail.nodeValue = ' ' + txt; else el.appendChild(document.createTextNode(' ' + txt));
        }
      } else {
        el.textContent = txt;
      }
    });
    r.querySelectorAll('[data-i18n-ph]').forEach(el => el.setAttribute('placeholder', t(el.getAttribute('data-i18n-ph'))));
    r.querySelectorAll('[data-i18n-title]').forEach(el => el.setAttribute('title', t(el.getAttribute('data-i18n-title'))));
  }
  function setLang(code) {
    if (code !== 'ms' && code !== 'en') return;
    cur = code;
    localStorage.setItem(KEY, cur);
    apply();
    window.dispatchEvent(new CustomEvent('sv:lang:changed', { detail: { lang: cur } }));
  }
  function getLang() { return cur; }

  window.svI18n = { t, apply, setLang, getLang };
  // Initial pass once DOM is ready
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => apply());
  else apply();
})();
