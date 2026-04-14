import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

class DbCustScreen extends StatefulWidget {
  const DbCustScreen({super.key});
  @override
  State<DbCustScreen> createState() => _DbCustScreenState();
}

class _DbCustScreenState extends State<DbCustScreen> {
  final _lang = AppLanguage();
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  String _ownerID = 'admin';
  String _shopID = 'MAIN';
  String _svPass = '';
  bool _hasGalleryAddon = false;
  bool _isLoading = true;

  // Segment: 0 = REPAIR, 1 = JUALAN
  int _selectedSegment = 0;

  // Filters
  String _sortMode = 'TERBARU'; // TERBARU, A-Z
  String _timeFilter = 'SEMUA'; // SEMUA, HARI_INI, BULAN_INI
  String _affiliateFilter = 'SEMUA'; // SEMUA, AFFILIATE, BELUM
  DateTime? _exactDate;

  // Data
  List<Map<String, dynamic>> _allRepairs = [];
  List<Map<String, dynamic>> _allSales = [];
  List<Map<String, dynamic>> _filtered = [];
  Map<String, int> _phoneFrequency = {};
  Map<String, Map<String, dynamic>> _referrals = {};
  Map<String, List<Map<String, dynamic>>> _referralClaims = {};

  // Pagination
  final int _rowsPerPage = 25;
  int _currentPage = 1;

  StreamSubscription? _repairSub;
  StreamSubscription? _salesSub;
  StreamSubscription? _referralSub;
  StreamSubscription? _claimsSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _repairSub?.cancel();
    _salesSub?.cancel();
    _referralSub?.cancel();
    _claimsSub?.cancel();
    _searchCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase();
      _shopID = branch.split('@')[1].toUpperCase();
    }

    // Load branch settings (svPass)
    try {
      final shopSnap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
      if (shopSnap.exists) {
        _svPass = (shopSnap.data()?['svPass'] ?? '').toString();
      }
    } catch (_) {}

    // Check gallery addon
    try {
      final dealerSnap = await _db.collection('saas_dealers').doc(_ownerID).get();
      if (dealerSnap.exists) {
        final d = dealerSnap.data()!;
        bool hasGal = d['addonGallery'] == true;
        if (hasGal && d['galleryExpire'] != null) {
          if (DateTime.now().millisecondsSinceEpoch > (d['galleryExpire'] as num)) hasGal = false;
        }
        // Also check branchSettings
        if (!hasGal) {
          try {
            final branchSnap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
            if (branchSnap.exists) {
              hasGal = branchSnap.data()?['hasGalleryAddon'] == true;
            }
          } catch (_) {}
        }
        if (mounted) setState(() => _hasGalleryAddon = hasGal);
      }
    } catch (_) {}

    _listenRepairs();
    _listenPhoneSales();
    _listenReferrals();
    _listenReferralClaims();
  }

  void _listenRepairs() {
    _repairSub = _db.collection('repairs_$_ownerID')
        .where('shopID', isEqualTo: _shopID)
        .snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      final freq = <String, int>{};
      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_docId'] = doc.id;
        final nama = (d['nama'] ?? '').toString().toUpperCase();
        final jenis = (d['jenis_servis'] ?? '').toString().toUpperCase();
        if (nama == 'JUALAN PANTAS' || jenis == 'JUALAN') continue;
        list.add(d);
        final tel = (d['tel'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        if (tel.isNotEmpty) freq[tel] = (freq[tel] ?? 0) + 1;
      }
      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      if (mounted) {
        setState(() {
          _allRepairs = list;
          _phoneFrequency = freq;
          _isLoading = false;
          _applyFilter();
        });
      }
    });
  }

  void _listenPhoneSales() {
    _salesSub = _db.collection('phone_sales_$_ownerID')
        .where('shopID', isEqualTo: _shopID)
        .snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_docId'] = doc.id;
        list.add(d);
      }
      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      if (mounted) {
        setState(() {
          _allSales = list;
          if (_selectedSegment == 1) _applyFilter();
        });
      }
    });
  }

  void _listenReferrals() {
    _referralSub = _db.collection('referrals_$_ownerID').snapshots().listen((snap) {
      final refs = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_docId'] = doc.id;
        final tel = (d['tel'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        if (tel.isNotEmpty) refs[tel] = d;
      }
      if (mounted) setState(() { _referrals = refs; _applyFilter(); });
    });
  }

  void _listenReferralClaims() {
    _claimsSub = _db.collection('referral_claims_$_ownerID').snapshots().listen((snap) {
      final claims = <String, List<Map<String, dynamic>>>{};
      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_docId'] = doc.id;
        final refCode = (d['referral_code'] ?? '').toString();
        if (refCode.isNotEmpty) {
          claims.putIfAbsent(refCode, () => []);
          claims[refCode]!.add(d);
        }
      }
      if (mounted) setState(() { _referralClaims = claims; });
    });
  }

  // ═══════════════════════════════════════
  // FILTERING
  // ═══════════════════════════════════════

  void _applyFilter() {
    var data = List<Map<String, dynamic>>.from(_selectedSegment == 0 ? _allRepairs : _allSales);
    final q = _searchCtrl.text.toLowerCase().trim();

    // Search
    if (q.isNotEmpty) {
      data = data.where((d) {
        if (_selectedSegment == 1) {
          return (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
              (d['kod'] ?? '').toString().toLowerCase().contains(q) ||
              (d['imei'] ?? '').toString().toLowerCase().contains(q) ||
              (d['warna'] ?? '').toString().toLowerCase().contains(q);
        }
        return (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
            (d['tel'] ?? '').toString().toLowerCase().contains(q) ||
            (d['model'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }

    // Exact date filter
    if (_exactDate != null) {
      final dayStart = DateTime(_exactDate!.year, _exactDate!.month, _exactDate!.day).millisecondsSinceEpoch;
      final dayEnd = dayStart + 86400000;
      data = data.where((d) {
        final ts = d['timestamp'] ?? 0;
        return ts >= dayStart && ts < dayEnd;
      }).toList();
    }

    // Time filter
    if (_timeFilter != 'SEMUA') {
      final now = DateTime.now();
      int startMs;
      if (_timeFilter == 'HARI_INI') {
        startMs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      } else {
        startMs = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      }
      data = data.where((d) => (d['timestamp'] ?? 0) >= startMs).toList();
    }

    // Affiliate filter
    if (_affiliateFilter != 'SEMUA') {
      data = data.where((d) {
        final tel = (d['tel'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        final hasRef = _referrals.containsKey(tel);
        return _affiliateFilter == 'AFFILIATE' ? hasRef : !hasRef;
      }).toList();
    }

    // Sort
    if (_sortMode == 'A-Z') {
      data.sort((a, b) => (a['nama'] ?? '').toString().toUpperCase().compareTo((b['nama'] ?? '').toString().toUpperCase()));
    } else {
      data.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    }

    _filtered = data;
    _currentPage = 1;
  }

  int get _totalPages => (_filtered.length / _rowsPerPage).ceil().clamp(1, 9999);

  List<Map<String, dynamic>> get _pageData {
    final s = (_currentPage - 1) * _rowsPerPage;
    return _filtered.sublist(s, (s + _rowsPerPage).clamp(0, _filtered.length));
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════

  String _fmt(dynamic ts) {
    if (ts is int && ts > 0) return DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(ts));
    return '-';
  }

  String _fmtFull(dynamic ts) {
    if (ts is int && ts > 0) return DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts));
    return '-';
  }

  bool _isRegular(Map<String, dynamic> d) {
    final tel = (d['tel'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    return tel.isNotEmpty && (_phoneFrequency[tel] ?? 0) > 1;
  }

  String _generateCode(String prefix) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    final code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return '$prefix$code';
  }

  String _formatWaTel(String tel) {
    var n = tel.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('0')) n = '6$n';
    if (!n.startsWith('6')) n = '60$n';
    return n;
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // ═══════════════════════════════════════
  // EXCEL EXPORT (desktop only)
  // ═══════════════════════════════════════

  Future<void> _exportExcel() async {
    if (_filtered.isEmpty) {
      _snack('Tiada data untuk eksport', err: true);
      return;
    }
    try {
      final buffer = StringBuffer();
      buffer.writeln(_selectedSegment == 0
          ? 'No,Tarikh,Nama,Telefon,Model,Kerosakan,Status,Harga,Regular,Affiliate'
          : 'No,Tarikh,Nama,Kod,IMEI,Storage,Warna,Harga,Staff');
      for (var i = 0; i < _filtered.length; i++) {
        final d = _filtered[i];
        final tel = (d['tel'] ?? '-').toString();
        final telClean = tel.replaceAll(RegExp(r'\D'), '');
        final isReg = telClean.isNotEmpty && (_phoneFrequency[telClean] ?? 0) > 1;
        final hasRef = _referrals.containsKey(telClean);
        if (_selectedSegment == 0) {
          buffer.writeln([
            i + 1,
            _fmtFull(d['timestamp']),
            '"${(d['nama'] ?? '-').toString().replaceAll('"', '""')}"',
            tel,
            '"${(d['model'] ?? '-').toString().replaceAll('"', '""')}"',
            '"${(d['kerosakan'] ?? '-').toString().replaceAll('"', '""')}"',
            d['status'] ?? '-',
            'RM ${(double.tryParse(d['total']?.toString() ?? d['harga']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}',
            isReg ? 'REGULAR' : '-',
            hasRef ? 'YA' : 'TIDAK',
          ].join(','));
        } else {
          buffer.writeln([
            i + 1,
            _fmtFull(d['timestamp']),
            '"${(d['nama'] ?? '-').toString().replaceAll('"', '""')}"',
            d['kod'] ?? '-',
            d['imei'] ?? '-',
            d['storage'] ?? '-',
            d['warna'] ?? '-',
            'RM ${((d['jual'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
            d['staffJual'] ?? '-',
          ].join(','));
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/db_cust_$timestamp.csv');
      await file.writeAsString(buffer.toString(), encoding: utf8);
      await OpenFilex.open(file.path);
      _snack('Fail CSV disimpan: ${file.path}');
    } catch (e) {
      _snack('Gagal eksport: $e', err: true);
    }
  }

  // ═══════════════════════════════════════
  // DATE PICKER
  // ═══════════════════════════════════════

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _exactDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary, onPrimary: Colors.black, surface: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _exactDate = picked;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
        _applyFilter();
      });
    }
  }

  // ═══════════════════════════════════════
  // PUSAT TINDAKAN MODAL
  // ═══════════════════════════════════════

  void _showPusatTindakan(Map<String, dynamic> job) {
    final nama = (job['nama'] ?? '-').toString();
    final tel = (job['tel'] ?? '-').toString();
    final siri = (job['siri'] ?? '-').toString();
    final telClean = tel.replaceAll(RegExp(r'\D'), '');
    final hasRefAlready = _referrals.containsKey(telClean);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, AppColors.bg]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.primary, width: 1.5)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.bullseye, size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(_lang.get('dc_pusat_tindakan'), style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 16),

            // Customer info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderMed),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const FaIcon(FontAwesomeIcons.user, size: 11, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(nama.toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const FaIcon(FontAwesomeIcons.phone, size: 10, color: AppColors.green),
                  const SizedBox(width: 8),
                  Text(tel, style: const TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                  const FaIcon(FontAwesomeIcons.hashtag, size: 10, color: AppColors.yellow),
                  const SizedBox(width: 6),
                  Text(siri, style: const TextStyle(color: AppColors.yellow, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                if (_isRegular(job)) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.orange.withValues(alpha: 0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const FaIcon(FontAwesomeIcons.fire, size: 9, color: AppColors.orange),
                      const SizedBox(width: 5),
                      Text('${_lang.get('regular')} (${_phoneFrequency[telClean] ?? 0}x)', style: const TextStyle(color: AppColors.orange, fontSize: 9, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // Action buttons
            // 1. Generate Referral
            _actionButton(
              icon: FontAwesomeIcons.handshake,
              label: hasRefAlready ? 'REFERRAL: ${_referrals[telClean]?['referral_code'] ?? '-'}' : _lang.get('dc_generate_referral'),
              color: AppColors.yellow,
              onTap: () {
                Navigator.pop(ctx);
                _showReferralModal(job);
              },
            ),
            const SizedBox(height: 10),

            // 3. Send WhatsApp
            _actionButton(
              icon: FontAwesomeIcons.whatsapp,
              label: '${_lang.get('dc_hantar_link')} VIA WHATSAPP',
              color: AppColors.green,
              onTap: () {
                Navigator.pop(ctx);
                _showSendLinkModal(job);
              },
            ),
            const SizedBox(height: 10),

            // 4. Gallery
            if (_hasGalleryAddon)
              _actionButton(
                icon: FontAwesomeIcons.images,
                label: 'LIHAT GALERI',
                color: AppColors.blue,
                onTap: () {
                  Navigator.pop(ctx);
                  _showGalleryModal(job);
                },
              ),

            // 5. Referral claims status (if affiliate)
            if (hasRefAlready) ...[
              const SizedBox(height: 16),
              const Divider(color: AppColors.borderMed),
              const SizedBox(height: 8),
              Row(children: [
                const FaIcon(FontAwesomeIcons.listCheck, size: 12, color: AppColors.yellow),
                const SizedBox(width: 8),
                Text(_lang.get('dc_referral_claims'), style: const TextStyle(color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 10),
              _buildReferralClaimsSection(telClean, ctx),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          FaIcon(icon, size: 14, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.3))),
          FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: color.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════
  // REFERRAL CLAIMS IN PUSAT TINDAKAN
  // ═══════════════════════════════════════

  Widget _buildReferralClaimsSection(String telClean, BuildContext ctx) {
    final refData = _referrals[telClean];
    if (refData == null) return const SizedBox.shrink();
    final refCode = (refData['referral_code'] ?? '').toString();
    final claims = _referralClaims[refCode] ?? [];

    if (claims.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(8)),
        child: Text(_lang.get('dc_tiada_claim'), style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
      );
    }

    return Column(
      children: claims.map((c) {
        final status = (c['status'] ?? 'BELUM BAYAR').toString().toUpperCase();
        final isPaid = status == 'PAID';
        final claimDocId = (c['_docId'] ?? '').toString();
        final claimerName = (c['claimer_name'] ?? '-').toString();
        final commission = (c['commission'] as num?)?.toDouble() ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isPaid ? AppColors.green.withValues(alpha: 0.3) : AppColors.yellow.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(claimerName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('RM ${commission.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textSub, fontSize: 10)),
            ])),
            GestureDetector(
              onTap: () async {
                final newStatus = isPaid ? 'BELUM BAYAR' : 'PAID';
                if (claimDocId.isNotEmpty) {
                  await _db.collection('referral_claims_$_ownerID').doc(claimDocId).update({'status': newStatus});
                  _snack('Status dikemaskini: $newStatus');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isPaid ? AppColors.green.withValues(alpha: 0.15) : AppColors.yellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isPaid ? AppColors.green : AppColors.yellow),
                ),
                child: Text(
                  isPaid ? 'PAID' : 'BELUM BAYAR',
                  style: TextStyle(color: isPaid ? AppColors.green : AppColors.yellow, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════
  // VOUCHER MODAL
  // ═══════════════════════════════════════

  void _showVoucherModal(Map<String, dynamic> job) {
    final passCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final docId = (job['_docId'] ?? '').toString();
    final existingVoucher = (job['voucher_generated'] ?? '').toString();
    final existingValue = (job['voucher_value'] as num?)?.toDouble() ?? 0;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, AppColors.bg]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.cyan, width: 1.5)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.ticket, size: 14, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text(_lang.get('dc_generate_voucher'), style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w900)),
              ]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 16),

            if (existingVoucher.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('dc_voucher_sedia'), style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(existingVoucher, style: const TextStyle(color: AppColors.cyan, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  if (existingValue > 0) Text('RM ${existingValue.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            _modalLabel('KATA LALUAN ADMIN'),
            _modalInput(passCtrl, 'Masukkan kata laluan', obscure: true),
            const SizedBox(height: 12),

            _modalLabel('NILAI VOUCHER (RM)'),
            _modalInput(valueCtrl, '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: saving ? null : () async {
                  final pass = passCtrl.text.trim();
                  final value = double.tryParse(valueCtrl.text) ?? 0;
                  if (pass.isEmpty || pass != _svPass) {
                    _snack('Kata laluan tidak sah', err: true);
                    return;
                  }
                  if (value <= 0) {
                    _snack('Sila masukkan nilai voucher', err: true);
                    return;
                  }
                  setS(() => saving = true);
                  try {
                    final code = _generateCode('V-');
                    await _db.collection('repairs_$_ownerID').doc(docId).update({
                      'voucher_generated': code,
                      'voucher_value': value,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('Voucher $code berjaya dijana!');
                  } catch (e) {
                    _snack('Gagal: $e', err: true);
                  }
                  setS(() => saving = false);
                },
                icon: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const FaIcon(FontAwesomeIcons.ticket, size: 12),
                label: Text(_lang.get('dc_jana_voucher')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),
      )),
    );
  }

  // ═══════════════════════════════════════
  // REFERRAL MODAL
  // ═══════════════════════════════════════

  void _showReferralModal(Map<String, dynamic> job) {
    final passCtrl = TextEditingController();
    final commCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '10');
    final bankNameCtrl = TextEditingController();
    final bankAccCtrl = TextEditingController();
    final tel = (job['tel'] ?? '').toString();
    final nama = (job['nama'] ?? '-').toString();
    final telClean = tel.replaceAll(RegExp(r'\D'), '');
    final existingRef = _referrals[telClean];
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, AppColors.bg]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.yellow, width: 1.5)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.handshake, size: 14, color: AppColors.yellow),
                const SizedBox(width: 8),
                Text(_lang.get('dc_generate_referral'), style: const TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
              ]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 16),

            if (existingRef != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('dc_referral_sedia'), style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(existingRef['referral_code'] ?? '-', style: const TextStyle(color: AppColors.yellow, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  Text('Komisen: RM ${((existingRef['commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textSub, fontSize: 11)),
                  Text('Had: ${existingRef['usage_limit'] ?? '-'} | Bank: ${existingRef['bank_name'] ?? '-'} ${existingRef['bank_account'] ?? ''}', style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            _modalLabel('KATA LALUAN ADMIN'),
            _modalInput(passCtrl, 'Masukkan kata laluan', obscure: true),
            const SizedBox(height: 12),

            _modalLabel('KOMISEN (RM)'),
            _modalInput(commCtrl, '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),

            _modalLabel('HAD PENGGUNAAN'),
            _modalInput(limitCtrl, '10', keyboardType: TextInputType.number),
            const SizedBox(height: 12),

            _modalLabel('NAMA BANK'),
            _modalInput(bankNameCtrl, 'Cth: MAYBANK'),
            const SizedBox(height: 12),

            _modalLabel('NO. AKAUN BANK'),
            _modalInput(bankAccCtrl, 'Cth: 1234567890'),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: saving ? null : () async {
                  final pass = passCtrl.text.trim();
                  final comm = double.tryParse(commCtrl.text) ?? 0;
                  final limit = int.tryParse(limitCtrl.text) ?? 10;
                  if (pass.isEmpty || pass != _svPass) {
                    _snack('Kata laluan tidak sah', err: true);
                    return;
                  }
                  if (comm <= 0) {
                    _snack('Sila masukkan nilai komisen', err: true);
                    return;
                  }
                  setS(() => saving = true);
                  try {
                    final code = _generateCode('REF-');
                    await _db.collection('referrals_$_ownerID').add({
                      'referral_code': code,
                      'nama': nama.toUpperCase(),
                      'tel': tel,
                      'commission': comm,
                      'usage_limit': limit,
                      'usage_count': 0,
                      'bank_name': bankNameCtrl.text.trim().toUpperCase(),
                      'bank_account': bankAccCtrl.text.trim(),
                      'shopID': _shopID,
                      'ownerID': _ownerID,
                      'created_at': DateTime.now().millisecondsSinceEpoch,
                      'status': 'ACTIVE',
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('Referral $code berjaya dijana!');
                  } catch (e) {
                    _snack('Gagal: $e', err: true);
                  }
                  setS(() => saving = false);
                },
                icon: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const FaIcon(FontAwesomeIcons.handshake, size: 12),
                label: Text(_lang.get('dc_jana_referral')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellow, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),
      )),
    );
  }

  // ═══════════════════════════════════════
  // SEND LINK MODAL (WhatsApp / Copy)
  // ═══════════════════════════════════════

  void _showSendLinkModal(Map<String, dynamic> job) {
    final tel = (job['tel'] ?? '').toString();
    final nama = (job['nama'] ?? '-').toString();
    final telClean = tel.replaceAll(RegExp(r'\D'), '');
    final voucher = (job['voucher_generated'] ?? '').toString();
    final refData = _referrals[telClean];
    final refCode = (refData?['referral_code'] ?? '').toString();

    final voucherLink = voucher.isNotEmpty ? 'https://rmspro.net/voucher?code=$voucher&owner=$_ownerID' : '';
    final referralLink = refCode.isNotEmpty ? 'https://rmspro.net/referral?code=$refCode&owner=$_ownerID' : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, AppColors.bg]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.green, width: 1.5)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.shareNodes, size: 14, color: AppColors.green),
                const SizedBox(width: 8),
                Text(_lang.get('dc_hantar_link'), style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
              ]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 16),

            Text('${_lang.get('dc_pelanggan')}: $nama', style: const TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // Voucher link
            if (voucherLink.isNotEmpty) ...[
              _linkSection('VOUCHER LINK', voucher, voucherLink, tel, AppColors.cyan),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(8)),
                child: Text(_lang.get('dc_tiada_voucher'), style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
              ),
              const SizedBox(height: 12),
            ],

            // Referral link
            if (referralLink.isNotEmpty) ...[
              _linkSection('REFERRAL LINK', refCode, referralLink, tel, AppColors.yellow),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(8)),
                child: Text(_lang.get('dc_tiada_referral'), style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _linkSection(String title, String code, String link, String tel, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(code, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(link, style: const TextStyle(color: AppColors.textDim, fontSize: 9), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () async {
              final waNum = _formatWaTel(tel);
              final msg = Uri.encodeComponent('Terima kasih! Gunakan link ini:\n$link');
              final waUrl = 'https://wa.me/$waNum?text=$msg';
              try {
                await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
              } catch (_) {
                _snack('Gagal buka WhatsApp', err: true);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const FaIcon(FontAwesomeIcons.whatsapp, size: 12, color: Colors.white),
                const SizedBox(width: 6),
                Text(_lang.get('whatsapp'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w900)),
              ]),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: link));
              _snack('Link disalin!');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderMed)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const FaIcon(FontAwesomeIcons.copy, size: 11, color: Colors.white),
                const SizedBox(width: 6),
                Text(_lang.get('dc_salin_link'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w900)),
              ]),
            ),
          )),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════
  // GALLERY MODAL
  // ═══════════════════════════════════════

  void _showGalleryModal(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '-';
    final imgTypes = [
      {'key': 'img_sebelum_depan', 'label': 'SEBELUM (DEPAN)', 'color': AppColors.blue},
      {'key': 'img_sebelum_belakang', 'label': 'SEBELUM (BLKNG)', 'color': AppColors.blue},
      {'key': 'img_selepas_depan', 'label': 'SELEPAS (DEPAN)', 'color': AppColors.primary},
      {'key': 'img_selepas_belakang', 'label': 'SELEPAS (BLKNG)', 'color': AppColors.primary},
      {'key': 'img_cust', 'label': 'GAMBAR CUST', 'color': AppColors.yellow},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scroll) => Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const FaIcon(FontAwesomeIcons.images, size: 14, color: AppColors.yellow),
              const SizedBox(width: 8),
              Expanded(child: Text('${_lang.get('dc_galeri')} #$siri', style: const TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
          ),
          const Divider(color: AppColors.borderMed, height: 1),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
              itemCount: imgTypes.length,
              itemBuilder: (_, i) {
                final type = imgTypes[i];
                final url = (job[type['key']] ?? '').toString();
                final hasImg = url.isNotEmpty && (url.startsWith('http') || url.startsWith('data:'));
                final color = type['color'] as Color;

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Column(children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
                      child: Text(type['label'] as String, textAlign: TextAlign.center,
                          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                    Expanded(
                      child: hasImg
                          ? GestureDetector(
                              onTap: () => _viewFullImage(url, type['label'] as String),
                              child: Stack(children: [
                                _buildImage(url, BoxFit.cover),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(color: AppColors.bgDeep.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4), border: Border.all(color: color)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      FaIcon(FontAwesomeIcons.expand, size: 8, color: color),
                                      const SizedBox(width: 4),
                                      Text(_lang.get('view'), style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
                                    ]),
                                  ),
                                ),
                              ]),
                            )
                          : Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                FaIcon(FontAwesomeIcons.image, size: 24, color: Colors.white.withValues(alpha: 0.05)),
                                const SizedBox(height: 6),
                                Text(_lang.get('dc_tiada_gambar'), style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 8, fontWeight: FontWeight.bold)),
                              ]),
                            ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildImage(String url, BoxFit fit) {
    if (url.startsWith('data:image')) {
      try {
        final b64 = url.split(',').last;
        return Image.memory(base64Decode(b64), width: double.infinity, height: double.infinity, fit: fit,
            errorBuilder: (_, _, _) => const Center(child: FaIcon(FontAwesomeIcons.circleExclamation, size: 20, color: AppColors.red)));
      } catch (_) {
        return const Center(child: FaIcon(FontAwesomeIcons.circleExclamation, size: 20, color: AppColors.red));
      }
    }
    if (url.startsWith('http')) {
      return Image.network(url, width: double.infinity, height: double.infinity, fit: fit,
          errorBuilder: (_, _, _) => const Center(child: FaIcon(FontAwesomeIcons.circleExclamation, size: 20, color: AppColors.red)));
    }
    return const Center(child: FaIcon(FontAwesomeIcons.image, size: 20, color: AppColors.textDim));
  }

  void _viewFullImage(String url, String label) {
    showDialog(
      context: context,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: _buildImage(url, BoxFit.contain))),
      ),
    );
  }

  // ═══════════════════════════════════════
  // MODAL HELPERS
  // ═══════════════════════════════════════

  Widget _modalLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      );

  Widget _modalInput(TextEditingController ctrl, String hint, {TextInputType keyboardType = TextInputType.text, bool obscure = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        filled: true,
        fillColor: AppColors.bgDeep,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        isDense: true,
      ),
    );
  }

  // ═══════════════════════════════════════
  // BUILD UI
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      _buildSegmentToggle(),
      _buildSearchBar(),
      _buildFilterRow(),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      FaIcon(FontAwesomeIcons.userSlash, size: 36, color: Colors.white.withValues(alpha: 0.08)),
                      const SizedBox(height: 12),
                      Text(_lang.get('dc_tiada_rekod'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: _pageData.length,
                    itemBuilder: (_, i) => _custCard(_pageData[i], (_currentPage - 1) * _rowsPerPage + i + 1),
                  ),
      ),
      if (_filtered.length > _rowsPerPage) _buildPagination(),
      _buildFooter(),
    ]);
  }

  // ─── SEGMENT TOGGLE ───
  Widget _buildSegmentToggle() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: AppColors.card,
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() { _selectedSegment = 0; _applyFilter(); }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _selectedSegment == 0 ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              border: Border.all(color: _selectedSegment == 0 ? AppColors.primary : AppColors.borderMed),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FaIcon(FontAwesomeIcons.screwdriverWrench, size: 11, color: _selectedSegment == 0 ? AppColors.primary : AppColors.textDim),
              const SizedBox(width: 8),
              Text('REPAIR', style: TextStyle(
                color: _selectedSegment == 0 ? AppColors.primary : AppColors.textDim,
                fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5,
              )),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _selectedSegment == 0 ? AppColors.primary.withValues(alpha: 0.2) : AppColors.borderLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_allRepairs.length}', style: TextStyle(
                  color: _selectedSegment == 0 ? AppColors.primary : AppColors.textDim,
                  fontSize: 9, fontWeight: FontWeight.w900,
                )),
              ),
            ]),
          ),
        )),
        Expanded(child: GestureDetector(
          onTap: () => setState(() { _selectedSegment = 1; _applyFilter(); }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _selectedSegment == 1 ? AppColors.cyan.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
              border: Border.all(color: _selectedSegment == 1 ? AppColors.cyan : AppColors.borderMed),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FaIcon(FontAwesomeIcons.cartShopping, size: 11, color: _selectedSegment == 1 ? AppColors.cyan : AppColors.textDim),
              const SizedBox(width: 8),
              Text('JUALAN', style: TextStyle(
                color: _selectedSegment == 1 ? AppColors.cyan : AppColors.textDim,
                fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5,
              )),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _selectedSegment == 1 ? AppColors.cyan.withValues(alpha: 0.2) : AppColors.borderLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_allSales.length}', style: TextStyle(
                  color: _selectedSegment == 1 ? AppColors.cyan : AppColors.textDim,
                  fontSize: 9, fontWeight: FontWeight.w900,
                )),
              ),
            ]),
          ),
        )),
      ]),
    );
  }

  // ─── HEADER ───
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(color: AppColors.card),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          const FaIcon(FontAwesomeIcons.database, size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(_lang.get('dc_db_pelanggan'), style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ]),
        Row(children: [
          // Excel export (desktop only)
          if (_isDesktop)
            GestureDetector(
              onTap: _exportExcel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.green.withValues(alpha: 0.4))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.fileExcel, size: 11, color: AppColors.green),
                  const SizedBox(width: 6),
                  Text(_lang.get('dc_excel'), style: const TextStyle(color: AppColors.green, fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }

  // ─── SEARCH BAR ───
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: AppColors.card,
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(_applyFilter),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: _lang.get('dc_cari_hint'),
              hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => setState(() { _searchCtrl.clear(); _applyFilter(); }),
                      child: const Icon(Icons.close, color: AppColors.textDim, size: 16),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.bgDeep,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Date picker
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: _exactDate != null ? AppColors.primary.withValues(alpha: 0.15) : AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _exactDate != null ? AppColors.primary.withValues(alpha: 0.5) : AppColors.borderMed),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.calendarDay, size: 12, color: _exactDate != null ? AppColors.primary : AppColors.textMuted),
              if (_exactDate != null) ...[
                const SizedBox(width: 6),
                Text(DateFormat('dd/MM').format(_exactDate!), style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() { _exactDate = null; _dateCtrl.clear(); _applyFilter(); }),
                  child: const FaIcon(FontAwesomeIcons.xmark, size: 9, color: AppColors.red),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  // ─── FILTER ROW ───
  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      color: AppColors.card,
      child: Row(children: [
        // Sort dropdown
        Expanded(child: _filterDropdown<String>(
          value: _sortMode,
          items: const {'TERBARU': 'TERBARU', 'A-Z': 'A-Z'},
          icon: FontAwesomeIcons.arrowDownWideShort,
          color: AppColors.primary,
          onChanged: (v) => setState(() { _sortMode = v!; _applyFilter(); }),
        )),
        const SizedBox(width: 8),
        // Time dropdown
        Expanded(child: _filterDropdown<String>(
          value: _timeFilter,
          items: const {'SEMUA': 'SEMUA', 'HARI_INI': 'HARI INI', 'BULAN_INI': 'BULAN INI'},
          icon: FontAwesomeIcons.calendar,
          color: AppColors.primary,
          onChanged: (v) => setState(() { _timeFilter = v!; _applyFilter(); }),
        )),
        const SizedBox(width: 8),
        // Affiliate dropdown
        Expanded(child: _filterDropdown<String>(
          value: _affiliateFilter,
          items: const {'SEMUA': 'SEMUA', 'AFFILIATE': 'AFFILIATE', 'BELUM': 'BELUM'},
          icon: FontAwesomeIcons.handshake,
          color: AppColors.yellow,
          onChanged: (v) => setState(() { _affiliateFilter = v!; _applyFilter(); }),
        )),
      ]),
    );
  }

  Widget _filterDropdown<T>({
    required T value,
    required Map<T, String> items,
    required IconData icon,
    required Color color,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        FaIcon(icon, size: 10, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              icon: FaIcon(FontAwesomeIcons.chevronDown, size: 8, color: color),
              dropdownColor: Colors.white,
              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900),
              items: items.entries.map((e) => DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ]),
    );
  }

  // ─── CUSTOMER CARD ───
  Widget _custCard(Map<String, dynamic> d, int index) {
    if (_selectedSegment == 1) return _salesCard(d, index);
    final status = (d['status'] ?? '').toString().toUpperCase();
    final harga = double.tryParse(d['total']?.toString() ?? d['harga']?.toString() ?? '0') ?? 0;
    final tel = (d['tel'] ?? '-').toString();
    final telClean = tel.replaceAll(RegExp(r'\D'), '');
    final isReg = _isRegular(d);
    final hasRef = _referrals.containsKey(telClean);
    final hasAnyImg = ['img_sebelum_depan', 'img_sebelum_belakang', 'img_selepas_depan', 'img_selepas_belakang', 'img_cust']
        .any((k) => (d[k] ?? '').toString().isNotEmpty);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasRef ? AppColors.yellow.withValues(alpha: 0.25) : AppColors.borderMed),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header - nama (tappable) + harga
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showPusatTindakan(d),
              child: Row(children: [
                Text('$index. ', style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
                Expanded(
                  child: Text(
                    (d['nama'] ?? '-').toString().toUpperCase(),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900, decoration: TextDecoration.underline, decorationColor: AppColors.primary, decorationStyle: TextDecorationStyle.dotted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
          Text('RM ${harga.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 6),

        // Info rows
        Row(children: [
          const FaIcon(FontAwesomeIcons.phone, size: 10, color: AppColors.green),
          const SizedBox(width: 6),
          Text(tel, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 10, color: AppColors.blue),
          const SizedBox(width: 6),
          Expanded(child: Text(d['model'] ?? '-', style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const FaIcon(FontAwesomeIcons.screwdriverWrench, size: 10, color: AppColors.yellow),
          const SizedBox(width: 6),
          Expanded(child: Text(d['kerosakan'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),

        // Badges row
        Wrap(spacing: 6, runSpacing: 4, children: [
          // Date
          _badge(_fmt(d['timestamp']), FontAwesomeIcons.clock, AppColors.textDim),

          // Status
          _badge(status, FontAwesomeIcons.circleInfo,
              status == 'COMPLETED' ? AppColors.green : status == 'CANCEL' || status == 'CANCELLED' ? AppColors.red : AppColors.blue),

          // Regular badge
          if (isReg)
            _badge('${_lang.get('regular')} (${_phoneFrequency[telClean]}x)', FontAwesomeIcons.fire, AppColors.orange),

          // Affiliate badge
          if (hasRef)
            _badge('AFFILIATE', FontAwesomeIcons.handshake, AppColors.yellow),

          // Gallery button
          if (_hasGalleryAddon)
            GestureDetector(
              onTap: () => _showGalleryModal(d),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasAnyImg ? AppColors.yellow.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hasAnyImg ? AppColors.yellow.withValues(alpha: 0.4) : AppColors.textDim.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.images, size: 9, color: hasAnyImg ? AppColors.yellow : AppColors.textDim),
                  const SizedBox(width: 4),
                  Text(hasAnyImg ? _lang.get('dc_galeri') : 'TIADA', style: TextStyle(color: hasAnyImg ? AppColors.yellow : AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            )
          else
            GestureDetector(
              onTap: () => _snack('Sila langgan Add-on Gallery Premium', err: true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.lock, size: 8, color: AppColors.textDim),
                  const SizedBox(width: 4),
                  Text(_lang.get('dc_galeri'), style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }

  // ─── PHONE SALES CARD ───
  Widget _salesCard(Map<String, dynamic> d, int index) {
    final nama = (d['nama'] ?? '-').toString().toUpperCase();
    final kod = (d['kod'] ?? '').toString();
    final imei = (d['imei'] ?? '-').toString();
    final warna = (d['warna'] ?? '').toString();
    final storage = (d['storage'] ?? '').toString();
    final harga = (d['jual'] as num?)?.toDouble() ?? 0;
    final staff = (d['staffJual'] ?? '-').toString();
    final imageUrl = (d['imageUrl'] ?? '').toString();
    final hasImg = imageUrl.isNotEmpty && imageUrl.startsWith('http');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Phone image
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
          ),
          child: hasImg
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.network(imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 18, color: AppColors.cyan))),
                )
              : const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 18, color: AppColors.cyan)),
        ),
        const SizedBox(width: 12),
        // Details
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text('$index. $nama', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
            Text('RM ${harga.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            if (storage.isNotEmpty) ...[
              const FaIcon(FontAwesomeIcons.database, size: 9, color: AppColors.blue),
              const SizedBox(width: 4),
              Text(storage, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
            ],
            if (warna.isNotEmpty) ...[
              const FaIcon(FontAwesomeIcons.palette, size: 9, color: AppColors.yellow),
              const SizedBox(width: 4),
              Text(warna, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const FaIcon(FontAwesomeIcons.barcode, size: 9, color: AppColors.textDim),
            const SizedBox(width: 4),
            Expanded(child: Text('IMEI: $imei', style: const TextStyle(color: AppColors.textMuted, fontSize: 10), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _badge(_fmt(d['timestamp']), FontAwesomeIcons.clock, AppColors.textDim),
            if (kod.isNotEmpty) _badge(kod, FontAwesomeIcons.tag, AppColors.cyan),
            _badge(staff, FontAwesomeIcons.userTag, AppColors.blue),
          ]),
        ])),
      ]),
    );
  }

  Widget _badge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(icon, size: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ─── PAGINATION ───
  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.card,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _pageBtn(FontAwesomeIcons.chevronLeft, _currentPage > 1, () => setState(() { _currentPage--; })),
        const SizedBox(width: 12),
        Text('$_currentPage / $_totalPages', style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(width: 12),
        _pageBtn(FontAwesomeIcons.chevronRight, _currentPage < _totalPages, () => setState(() { _currentPage++; })),
      ]),
    );
  }

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: enabled ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderMed),
        ),
        child: FaIcon(icon, size: 10, color: enabled ? AppColors.primary : AppColors.textDim),
      ),
    );
  }

  // ─── FOOTER ───
  Widget _buildFooter() {
    final totalCustomers = _filtered.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.borderMed))),
      child: Row(children: [
        const FaIcon(FontAwesomeIcons.users, size: 10, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text('$totalCustomers ${_selectedSegment == 0 ? 'repair' : 'jualan'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }

}
