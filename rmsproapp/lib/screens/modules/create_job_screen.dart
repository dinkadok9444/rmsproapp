import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dio/dio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/printer_service.dart';
import '../../services/app_language.dart';

const String _cloudRunUrl =
    'https://rms-backend-94407896005.asia-southeast1.run.app';

class CreateJobScreen extends StatefulWidget {
  const CreateJobScreen({super.key});
  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  final _repairService = RepairService();
  final _db = FirebaseFirestore.instance;
  final _printerService = PrinterService();
  final _lang = AppLanguage();

  // ─── Controllers ───
  final _namaCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _telWasapCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _catatanCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _depositCtrl = TextEditingController(text: '0');
  final _diskaunCtrl = TextEditingController(text: '0');
  final _promoCtrl = TextEditingController();
  final _custSearchCtrl = TextEditingController();

  // ─── State ───
  String _custType = 'NEW CUST';
  String _jenisServis = 'TAK PASTI';
  String _staffTerima = '';
  String _patternResult = '';
  String _savedSiri = '';
  String _kodVoucher = '';
  double _voucherAmt = 0;
  String _paymentStatus = 'UNPAID';
  String _caraBayaran = 'TAK PASTI';
  bool _isSaving = false;
  bool _isFormLocked = false;
  bool _hasGalleryAddon = false;
  bool _singleStaffMode = false;
  int _currentStep = 0; // wizard step (0..totalSteps-1)
  int get _totalSteps => (_hasGalleryAddon && !kIsWeb) ? 4 : 3;
  String? _imgDepan;
  String? _imgBelakang;
  String _ownerID = 'admin';
  String _shopID = 'MAIN';
  String _generatedVoucher = '';

  // Tarikh masuk — live clock until user edits
  DateTime _tarikhMasuk = DateTime.now();
  Timer? _clockTimer;
  bool _tarikhEdited = false;

  List<RepairItem> _items = [RepairItem(nama: '')];
  final Map<int, TextEditingController> _qtyCtrlCache = {};
  final Map<int, TextEditingController> _hargaCtrlCache = {};

  TextEditingController _getQtyCtrl(int i, RepairItem item) {
    return _qtyCtrlCache.putIfAbsent(i,
        () => TextEditingController(text: '${item.qty}'));
  }

  TextEditingController _getHargaCtrl(int i, RepairItem item) {
    return _hargaCtrlCache.putIfAbsent(i,
        () => TextEditingController(
            text: item.harga > 0 ? item.harga.toStringAsFixed(2) : ''));
  }
  List<String> _staffList = [];
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _activeVouchers = [];
  List<Map<String, dynamic>> _existingCustomers = [];
  List<Map<String, dynamic>> _custSearchResults = [];
  List<Map<String, dynamic>> _stockUsageHistory = []; // track scanned stock usage
  Map<String, dynamic> _branchSettings = {};
  Map<String, dynamic>? _savedJobData;

  final _jenisServisOptions = ['TAK PASTI', 'SIAP SEGERA', 'TINGGAL'];
  final _paymentStatusOptions = ['UNPAID', 'PAID'];
  final _caraBayaranOptions = ['CASH', 'ONLINE', 'QR', 'TAK PASTI'];

  @override
  void initState() {
    super.initState();
    _loadData();
    _startClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _formSub?.cancel();
    _namaCtrl.dispose();
    _telCtrl.dispose();
    _telWasapCtrl.dispose();
    _modelCtrl.dispose();
    _catatanCtrl.dispose();
    _passwordCtrl.dispose();
    _depositCtrl.dispose();
    _diskaunCtrl.dispose();
    _promoCtrl.dispose();
    _custSearchCtrl.dispose();
    super.dispose();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_tarikhEdited && mounted) {
        setState(() => _tarikhMasuk = DateTime.now());
      }
    });
  }

  Future<void> _loadData() async {
    await _repairService.init();
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;

    final staff = await _repairService.getStaffList();
    final inv = await _repairService.getInventory();
    final settings = await _repairService.getBranchSettings();

    // Load existing customers for autocomplete
    _loadExistingCustomers();

    if (mounted) {
      setState(() {
        _staffList = staff;
        _inventory = inv;
        if (_staffList.isNotEmpty) _staffTerima = _staffList.first;
        _hasGalleryAddon = settings?['hasGalleryAddon'] == true;
        _singleStaffMode = settings?['singleStaffMode'] == true;
        _branchSettings = settings ?? {};
      });
    }

    // Try pulling a draft
    _pullDraft();

    // Listen for pending customer forms (borang online)
    _listenCustomerForms();
  }

  StreamSubscription? _formSub;
  List<Map<String, dynamic>> _pendingForms = [];

  void _listenCustomerForms() {
    _formSub?.cancel();
    _formSub = _db
        .collection('customer_forms_$_ownerID')
        .where('status', isEqualTo: 'PENDING')
        .snapshots()
        .listen((snap) {
      final list = snap.docs
          .map((d) => {'_id': d.id, ...d.data()})
          .where((d) => (d['shopID'] ?? '').toString().toUpperCase() == _shopID.toUpperCase())
          .toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _pendingForms = list.take(10).toList());
    }, onError: (_) {
      // Fallback: manual fetch tanpa composite index
      _fetchPendingForms();
    });
  }

  Future<void> _fetchPendingForms() async {
    try {
      final snap = await _db
          .collection('customer_forms_$_ownerID')
          .where('status', isEqualTo: 'PENDING')
          .get();
      final list = snap.docs
          .map((d) => {'_id': d.id, ...d.data()})
          .where((d) => (d['shopID'] ?? '').toString().toUpperCase() == _shopID.toUpperCase())
          .toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _pendingForms = list.take(10).toList());
    } catch (_) {}
  }

  void _loadFromForm(Map<String, dynamic> form) {
    setState(() {
      _namaCtrl.text = form['nama'] ?? '';
      _telCtrl.text = form['tel'] ?? '';
      _modelCtrl.text = form['model'] ?? '';
      _passwordCtrl.text = form['password'] ?? 'Tiada';
      _patternResult = (form['pattern'] ?? '').toString();
      _catatanCtrl.text = form['catatan'] ?? '';
      _items = [RepairItem(nama: form['kerosakan'] ?? '')];

      // Backup tel -> wasap
      final backups = form['telBackup'];
      if (backups is List && backups.isNotEmpty) {
        _telWasapCtrl.text = backups.first.toString();
      }
    });

    // Mark as USED so next customer shows
    final docId = form['_id'];
    if (docId != null) {
      _db.collection('customer_forms_$_ownerID').doc(docId).update({
        'status': 'USED',
        'used_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _snack('Data borang pelanggan dimuatkan');
  }

  Future<void> _loadExistingCustomers() async {
    try {
      final snap = await _db.collection('repairs_$_ownerID').get();

      // Load active shop vouchers & referrals for cross-reference
      final voucherSnap = await _db.collection('shop_vouchers_$_ownerID').get();
      final refSnap = await _db.collection('referrals_$_ownerID').get();

      // Build voucher map: custTel -> list of active voucher codes
      final voucherByTel = <String, List<String>>{};
      final loadedVouchers = <Map<String, dynamic>>[];
      for (final doc in voucherSnap.docs) {
        final d = doc.data();
        if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
        if ((d['status'] ?? '').toString().toUpperCase() != 'ACTIVE') continue;
        final limit = (d['limit'] ?? 0) as int;
        final claimed = (d['claimed'] ?? 0) as int;
        if (limit > 0 && claimed >= limit) continue;
        final expiry = (d['expiry'] ?? '').toString();
        if (expiry.isNotEmpty && expiry != 'LIFETIME') {
          final expiryDate = DateTime.tryParse(expiry);
          if (expiryDate != null && expiryDate.isBefore(DateTime.now())) continue;
        }
        loadedVouchers.add({'code': d['code'] ?? doc.id, 'value': d['value'] ?? 0, ...d});
        final custTel = (d['custTel'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        final code = d['code'] ?? doc.id;
        if (custTel.isNotEmpty) {
          voucherByTel.putIfAbsent(custTel, () => []).add(code);
        } else {
          // Shop-wide voucher — available to all
          voucherByTel.putIfAbsent('_SHOP', () => []).add(code);
        }
      }
      _activeVouchers = loadedVouchers;

      // Build referral map: tel -> refCode
      final refByTel = <String, String>{};
      for (final doc in refSnap.docs) {
        final d = doc.data();
        if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
        if ((d['status'] ?? '').toString().toUpperCase() != 'ACTIVE') continue;
        final tel = (d['tel'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        if (tel.isNotEmpty) refByTel[tel] = d['refCode'] ?? doc.id;
      }

      final seen = <String>{};
      final custs = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
        final tel = (d['tel'] ?? '').toString();
        if (tel.isNotEmpty && tel != '-' && !seen.contains(tel)) {
          seen.add(tel);
          final cleanTel = tel.replaceAll(RegExp(r'\D'), '');
          // Gather voucher codes for this customer
          final custVouchers = <String>[
            ...(voucherByTel[cleanTel] ?? []),
            ...(voucherByTel['_SHOP'] ?? []),
          ];
          final refCode = refByTel[cleanTel] ?? '';
          custs.add({
            'nama': d['nama'] ?? '',
            'tel': tel,
            'tel_wasap': d['tel_wasap'] ?? d['wasap'] ?? '',
            'voucher': custVouchers.isNotEmpty ? custVouchers.first : '',
            'allVouchers': custVouchers,
            'referral': refCode,
          });
        }
      }
      if (mounted) setState(() => _existingCustomers = custs);
    } catch (_) {}
  }

  Future<void> _pullDraft() async {
    try {
      final drafts = await _repairService.getDrafts();
      if (drafts.isEmpty) return;
      final draft = drafts.first;

      if (mounted) {
        setState(() {
          _namaCtrl.text = (draft['nama'] ?? '').toString();
          _telCtrl.text = (draft['tel'] ?? '').toString();
          _telWasapCtrl.text =
              (draft['tel_wasap'] ?? draft['wasap'] ?? '').toString();
          _modelCtrl.text = (draft['model'] ?? '').toString();
          _catatanCtrl.text = (draft['catatan'] ?? '').toString();
          _passwordCtrl.text = (draft['password'] ?? '').toString();
          _jenisServis = (draft['jenis_servis'] ?? 'TAK PASTI').toString();
          if (!_jenisServisOptions.contains(_jenisServis)) {
            _jenisServis = 'TAK PASTI';
          }

          // Items
          if (draft['items_array'] is List &&
              (draft['items_array'] as List).isNotEmpty) {
            _items = (draft['items_array'] as List).map((i) {
              final m = Map<String, dynamic>.from(i as Map);
              return RepairItem(
                nama: (m['nama'] ?? '').toString(),
                qty: (m['qty'] as num?)?.toInt() ?? 1,
                harga: (m['harga'] as num?)?.toDouble() ?? 0,
              );
            }).toList();
          }

          final dep = double.tryParse(draft['deposit']?.toString() ?? '0');
          if (dep != null) _depositCtrl.text = dep.toStringAsFixed(0);
        });

        _snack('Draft ditarik masuk');

        // Delete draft after pulling
        final draftId = draft['id']?.toString();
        if (draftId != null) {
          await _repairService.deleteDraft(draftId);
        }
      }
    } catch (_) {}
  }

  // ─── Computed ───
  double get _totalHarga =>
      _items.fold(0.0, (s, i) => s + i.qty * i.harga);

  double get _depositVal => double.tryParse(_depositCtrl.text) ?? 0;
  double get _diskaunVal => double.tryParse(_diskaunCtrl.text) ?? 0;

  double get _totalBaki => _totalHarga - _voucherAmt - _depositVal - _diskaunVal;

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── Customer Search ───
  void _searchCustomers(String query) {
    if (query.isEmpty) {
      setState(() => _custSearchResults = []);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _custSearchResults = _existingCustomers.where((c) {
        return (c['nama'] ?? '').toString().toLowerCase().contains(q) ||
            (c['tel'] ?? '').toString().contains(q) ||
            (c['voucher'] ?? '').toString().toLowerCase().contains(q) ||
            (c['referral'] ?? '').toString().toLowerCase().contains(q);
      }).take(8).toList();
    });
  }

  void _selectCustomer(Map<String, dynamic> cust) {
    setState(() {
      _namaCtrl.text = (cust['nama'] ?? '').toString();
      _telCtrl.text = (cust['tel'] ?? '').toString();
      _telWasapCtrl.text = (cust['tel_wasap'] ?? '').toString();
      _custSearchResults = [];
      _custSearchCtrl.clear();
    });
  }

  // ─── Backup Tel Popup ───
  void _showBackupTelPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.phone, size: 14, color: AppColors.green),
            const SizedBox(width: 8),
            const Text('NO BACKUP', style: TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () { setState(() {}); Navigator.pop(ctx); },
              child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _telWasapCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'No telefon backup...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              filled: true, fillColor: Colors.grey.shade100,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: GestureDetector(
            onTap: () { setState(() {}); Navigator.pop(ctx); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('SIMPAN', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900))),
            ),
          )),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ─── Catatan Popup ───
  void _showCatatanPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.noteSticky, size: 14, color: AppColors.blue),
            const SizedBox(width: 8),
            const Text('CATATAN', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () { setState(() {}); Navigator.pop(ctx); },
              child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _catatanCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Nota tambahan...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              filled: true, fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: GestureDetector(
            onTap: () { setState(() {}); Navigator.pop(ctx); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('SIMPAN', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900))),
            ),
          )),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ─── Voucher Popup ───
  void _showVoucherPopup() {
    _promoCtrl.text = _kodVoucher;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.ticket, size: 14, color: AppColors.yellow),
            const SizedBox(width: 8),
            const Text('KOD VOUCHER / REFERRAL', style: TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(
              controller: _promoCtrl,
              style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Cth: V-ABC123 / REF-XXXX',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                filled: true, fillColor: Colors.grey.shade100,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                await _checkPromoCode();
                if (mounted) Navigator.pop(ctx);
              },
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(10)),
                child: const Center(child: Text('SEMAK', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900))),
              ),
            ),
          ]),
          if (_kodVoucher.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.yellow.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.circleCheck, size: 12, color: AppColors.yellow),
                const SizedBox(width: 8),
                Text('$_kodVoucher  -RM${_voucherAmt.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() { _kodVoucher = ''; _voucherAmt = 0; _promoCtrl.clear(); });
                    Navigator.pop(ctx);
                  },
                  child: const Text('BUANG', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ─── Voucher / Referral Check ───
  Future<void> _checkPromoCode() async {
    final kod = _promoCtrl.text.trim().toUpperCase();
    if (kod.isEmpty) {
      setState(() {
        _kodVoucher = '';
        _voucherAmt = 0;
      });
      return;
    }

    // Voucher code V-XXXX — search from shop_vouchers (Fungsi Lain)
    if (kod.startsWith('V-')) {
      try {
        final voucherSnap = await _db.collection('shop_vouchers_$_ownerID').doc(kod).get();
        if (voucherSnap.exists) {
          final vData = voucherSnap.data()!;
          final vStatus = (vData['status'] ?? '').toString().toUpperCase();
          final claimed = (vData['claimed'] ?? 0) as int;
          final limit = (vData['limit'] ?? 0) as int;

          if (vStatus != 'ACTIVE') {
            _snack('Voucher $kod tidak aktif!', err: true);
            return;
          }
          if (limit > 0 && claimed >= limit) {
            _snack('Voucher $kod sudah habis kuota!', err: true);
            return;
          }
          // Check expiry
          final expiry = (vData['expiry'] ?? '').toString();
          if (expiry.isNotEmpty && expiry != 'LIFETIME') {
            final expiryDate = DateTime.tryParse(expiry);
            if (expiryDate != null && expiryDate.isBefore(DateTime.now())) {
              _snack('Voucher $kod sudah tamat tempoh!', err: true);
              return;
            }
          }

          final vAmt = double.tryParse(vData['value']?.toString() ?? _branchSettings['voucherAmount']?.toString() ?? '5') ?? 5;
          setState(() {
            _kodVoucher = kod;
            _voucherAmt = vAmt;
          });
          _snack('Voucher $kod aktif! Potongan RM ${vAmt.toStringAsFixed(2)}');
        } else {
          _snack('Voucher $kod tidak dijumpai', err: true);
        }
      } catch (e) {
        _snack('Ralat semak voucher: $e', err: true);
      }
      return;
    }

    // Referral code REF-XXXX
    if (kod.startsWith('REF-')) {
      try {
        final refSnap =
            await _db.collection('referrals_$_ownerID').doc(kod).get();
        if (!refSnap.exists) {
          _snack('Kod referral $kod tidak dijumpai', err: true);
          return;
        }
        final refData = refSnap.data()!;
        final refTel = (refData['tel'] ?? '').toString();

        // Self-referral prevention
        if (refTel == _telCtrl.text.trim()) {
          _snack('Tidak boleh guna referral sendiri!', err: true);
          return;
        }

        final refAmt = double.tryParse(
                _branchSettings['referralAmount']?.toString() ?? '5') ??
            5;
        setState(() {
          _kodVoucher = kod;
          _voucherAmt = refAmt;
        });
        _snack(
            'Referral $kod aktif! Potongan RM ${refAmt.toStringAsFixed(2)}');
      } catch (e) {
        _snack('Ralat semak referral: $e', err: true);
      }
      return;
    }

    // Unknown format
    _snack('Format kod tidak dikenali. Guna V-XXXX atau REF-XXXX', err: true);
  }

  // ─── Pattern Drawing Dialog ───
  void _showPatternDialog() {
    final selected = <int>[];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Row(children: [
            const FaIcon(FontAwesomeIcons.gripVertical,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(_lang.get('cj_lukis_pattern'),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_lang.get('cj_tekan_titik'),
                style: const
                    TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              height: 220,
              child: _PatternGrid(
                selected: selected,
                onUpdate: () => setS(() {}),
              ),
            ),
            if (selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Pattern: ${selected.join('-')}',
                    style: const TextStyle(
                        color: AppColors.yellow,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ),
          ]),
          actions: [
            TextButton(
              onPressed: () => setS(() => selected.clear()),
              child: Text(_lang.get('cj_reset'),
                  style: const TextStyle(color: AppColors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_lang.get('batal'),
                  style: const TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: selected.length >= 2
                  ? () {
                      setState(
                          () => _patternResult = selected.join('-'));
                      Navigator.pop(ctx);
                      _snack('Pattern disimpan: ${selected.join('-')}');
                    }
                  : null,
              child: Text(_lang.get('simpan')),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Camera / Gallery ───
  Future<void> _ambilGambar(String jenis) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 480,
      maxHeight: 480,
      imageQuality: 25,
    );
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final sizeKB = bytes.length / 1024;
    final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    setState(() {
      if (jenis == 'depan') {
      _imgDepan = b64;
    } else {
      _imgBelakang = b64;
    }
    });
    _snack(
        'Gambar ${jenis.toUpperCase()} diambil (${sizeKB.toStringAsFixed(0)}KB)');
  }

  void _showSnapGambarModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.camera,
                  size: 14, color: AppColors.red),
              const SizedBox(width: 8),
              Text(_lang.get('cj_ambil_gambar'),
                  style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(FontAwesomeIcons.xmark,
                      size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: _snapCard('DEPAN', _imgDepan, () async {
                await _ambilGambar('depan');
                setS(() {});
                setState(() {});
              })),
              const SizedBox(width: 12),
              Expanded(
                  child: _snapCard('BELAKANG', _imgBelakang, () async {
                await _ambilGambar('belakang');
                setS(() {});
                setState(() {});
              })),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const FaIcon(FontAwesomeIcons.check, size: 12),
                label: Text(_lang.get('selesai')),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _snapCard(String label, String? img, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          image: img != null
              ? DecorationImage(
                  image:
                      MemoryImage(base64Decode(img.split(',').last)),
                  fit: BoxFit.cover)
              : null,
        ),
        child: img == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    const FaIcon(FontAwesomeIcons.camera,
                        size: 24, color: AppColors.textDim),
                    const SizedBox(height: 8),
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 10,
                            fontWeight: FontWeight.w900)),
                  ])
            : Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(4)),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FaIcon(FontAwesomeIcons.circleCheck,
                            size: 8, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(_lang.get('ok'),
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 8,
                                fontWeight: FontWeight.w900)),
                      ]),
                ),
              ),
      ),
    );
  }

  // ─── Upload images to Firebase Storage ───
  Future<Map<String, String>> _uploadImages(String siri) async {
    final result = <String, String>{};
    if (!_hasGalleryAddon) return result;

    Future<String?> upload(String? b64, String label) async {
      if (b64 == null) return null;
      try {
        final bytes = base64Decode(b64.split(',').last);
        final ref = FirebaseStorage.instance
            .ref('repairs/$_ownerID/$siri/${label}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        final task = await ref.putData(
            bytes, SettableMetadata(contentType: 'image/jpeg'));
        return await task.ref.getDownloadURL();
      } catch (_) {
        return null;
      }
    }

    final depanUrl = await upload(_imgDepan, 'depan');
    final belakangUrl = await upload(_imgBelakang, 'belakang');
    if (depanUrl != null) result['img_sebelum_depan'] = depanUrl;
    if (belakangUrl != null) result['img_sebelum_belakang'] = belakangUrl;
    return result;
  }

  // ─── Save Ticket ───
  Future<void> _simpanTiket() async {
    if (_namaCtrl.text.trim().isEmpty || _telCtrl.text.trim().isEmpty) {
      _snack('Sila isi Nama & No Telefon', err: true);
      return;
    }
    final validItems =
        _items.where((i) => i.nama.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      _snack('Sila tambah sekurang-kurangnya satu item', err: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final tarikhStr =
          DateFormat("yyyy-MM-dd'T'HH:mm").format(_tarikhMasuk);

      final siri = await _repairService.simpanTiket(
        nama: _namaCtrl.text.trim(),
        tel: _telCtrl.text.trim(),
        telWasap: _telWasapCtrl.text.trim(),
        model: _modelCtrl.text.trim().toUpperCase(),
        jenisServis: _jenisServis,
        catatan: _catatanCtrl.text.trim(),
        items: validItems,
        tarikh: tarikhStr,
        harga: _totalHarga,
        deposit: _depositVal,
        paymentStatus: _paymentStatus,
        caraBayaran: _caraBayaran,
        staffTerima: _staffTerima,
        phonePass: _passwordCtrl.text.trim(),
        patternResult: _patternResult,
        custType: _custType,
        kodVoucher: _kodVoucher,
        voucherAmt: _voucherAmt,
      );

      // Upload images to Firebase Storage
      final imageUrls = await _uploadImages(siri);
      if (imageUrls.isNotEmpty) {
        await _db
            .collection('repairs_$_ownerID')
            .doc(siri)
            .update(imageUrls);
      }

      // Create referral claim if referral code used
      if (_kodVoucher.startsWith('REF-')) {
        try {
          await _db.collection('referral_claims_$_ownerID').add({
            'referralCode': _kodVoucher,
            'claimedBy': _telCtrl.text.trim(),
            'claimedByName': _namaCtrl.text.trim().toUpperCase(),
            'siri': siri,
            'amount': _voucherAmt,
            'shopID': _shopID,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } catch (_) {}
      }

      // Update voucher claimed count if voucher code used
      if (_kodVoucher.startsWith('V-')) {
        try {
          await _db.collection('shop_vouchers_$_ownerID').doc(_kodVoucher).update({
            'claimed': FieldValue.increment(1),
          });
        } catch (_) {}
      }

      // Delete any draft that was pulled
      // (already deleted at pull time)

      // Read back saved data for receipt printing
      final savedSnap =
          await _db.collection('repairs_$_ownerID').doc(siri).get();
      _savedJobData = savedSnap.data();
      _generatedVoucher =
          _savedJobData?['voucher_generated']?.toString() ?? '';

      setState(() {
        _savedSiri = siri;
        _isFormLocked = true;
      });
      _snack('Berjaya Disimpan! Siri: #$siri');
    } catch (e) {
      _snack('Ralat: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── Quote Print (80mm Bluetooth) ───
  Future<void> _printQuote80mm() async {
    if (_savedJobData == null) {
      _snack('Tiada data untuk print', err: true);
      return;
    }
    _snack('Menyambung ke printer...');
    final ok =
        await _printerService.printReceipt(_savedJobData!, _branchSettings);
    if (ok) {
      _snack('Berjaya dicetak!');
    } else {
      _snack('Gagal cetak. Semak sambungan Bluetooth printer.', err: true);
    }
  }

  // ─── Quote Print (A4 PDF via Cloud Run) ───
  Future<void> _printQuoteA4() async {
    if (_savedJobData == null) {
      _snack('Tiada data untuk print', err: true);
      return;
    }
    try {
      _snack('Menjana PDF...');
      final dio = Dio();
      final resp = await dio.post(
        '$_cloudRunUrl/generate-quote-pdf',
        data: {
          'job': _savedJobData,
          'branch': _branchSettings,
          'ownerID': _ownerID,
          'shopID': _shopID,
        },
        options: Options(responseType: ResponseType.bytes),
      );

      if (resp.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/quote_$_savedSiri.pdf');
        await file.writeAsBytes(resp.data as List<int>);
        await OpenFilex.open(file.path);
        _snack('PDF dijana!');
      } else {
        _snack('Gagal jana PDF', err: true);
      }
    } catch (e) {
      _snack('Ralat PDF: $e', err: true);
    }
  }

  // ─── Reset ───
  void _resetForm() {
    setState(() {
      _namaCtrl.clear();
      _telCtrl.clear();
      _telWasapCtrl.clear();
      _modelCtrl.clear();
      _catatanCtrl.clear();
      _passwordCtrl.clear();
      _depositCtrl.text = '0';
      _diskaunCtrl.text = '0';
      _promoCtrl.clear();
      _custSearchCtrl.clear();
      _custType = 'NEW CUST';
      _jenisServis = 'TAK PASTI';
      _staffTerima = _staffList.isNotEmpty ? _staffList.first : '';
      _patternResult = '';
      _savedSiri = '';
      _kodVoucher = '';
      _voucherAmt = 0;
      _paymentStatus = 'UNPAID';
      _caraBayaran = 'TAK PASTI';
      _isFormLocked = false;
      _imgDepan = null;
      _imgBelakang = null;
      _items = [RepairItem(nama: '')];
      _tarikhEdited = false;
      _tarikhMasuk = DateTime.now();
      _savedJobData = null;
      _generatedVoucher = '';
      _custSearchResults = [];
    });
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Row(children: [
          FaIcon(FontAwesomeIcons.fileInvoice,
              size: 16, color: AppColors.primary),
          SizedBox(width: 10),
          Text(_lang.get('cj_buka_tiket'),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
          if (_savedSiri.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.4))),
              child: Text('#$_savedSiri',
                  style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ),
          ],
        ]),
        actions: [
          // Refresh pending forms
          Stack(
            children: [
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.envelopeOpenText,
                    size: 14, color: AppColors.green),
                tooltip: 'Refresh Borang Online',
                onPressed: () async {
                  await _fetchPendingForms();
                  if (_pendingForms.isNotEmpty) {
                    _loadFromForm(_pendingForms.first);
                  } else {
                    _snack('Tiada borang online baru', err: true);
                  }
                },
              ),
              if (_pendingForms.isNotEmpty)
                Positioned(
                  right: 6, top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                    child: Text('${_pendingForms.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.xmark,
                size: 16, color: AppColors.red),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _isFormLocked,
        child: Opacity(
          opacity: _isFormLocked ? 0.5 : 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── WIZARD STEP INDICATOR ───
                _buildStepIndicator(),
                const SizedBox(height: 14),

                // ═══════════ STEP 1: CUSTOMER ═══════════
                if (_currentStep == 0) ...[
                // ─── CUSTOMER TYPE TOGGLE ───
                _buildCustTypeToggle(),
                const SizedBox(height: 14),

                // ─── REGULAR CUSTOMER SEARCH ───
                if (_custType == 'REGULAR') ...[
                  _buildRegularCustSearch(),
                  const SizedBox(height: 14),
                ],

                // ─── NAMA ───
                _label(_lang.get('cj_nama_pelanggan')),
                const SizedBox(height: 6),
                _input(_namaCtrl, _lang.get('cj_masuk_nama')),
                const SizedBox(height: 14),

                // ─── TELEFON + BACKUP ───
                Row(children: [
                  _label(_lang.get('cj_no_telefon')),
                  const Spacer(),
                  GestureDetector(
                    onTap: _showBackupTelPopup,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _telWasapCtrl.text.isNotEmpty
                            ? AppColors.green.withValues(alpha: 0.15)
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _telWasapCtrl.text.isNotEmpty
                            ? AppColors.green.withValues(alpha: 0.4)
                            : AppColors.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        FaIcon(FontAwesomeIcons.plus, size: 8,
                            color: _telWasapCtrl.text.isNotEmpty ? AppColors.green : AppColors.textDim),
                        const SizedBox(width: 4),
                        Text(_telWasapCtrl.text.isNotEmpty ? '${_lang.get('cj_backup')}: ${_telWasapCtrl.text}' : _lang.get('cj_backup'),
                            style: TextStyle(
                                color: _telWasapCtrl.text.isNotEmpty ? AppColors.green : AppColors.textDim,
                                fontSize: 8, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                _input(_telCtrl, '011...',
                    keyboard: TextInputType.phone),
                const SizedBox(height: 14),

                // ─── MODEL PERANTI ───
                _label(_lang.get('cj_model_peranti')),
                const SizedBox(height: 6),
                _input(_modelCtrl, _lang.get('cj_model_hint')),
                const SizedBox(height: 14),
                ], // END STEP 1

                // ═══════════ STEP 2: DAMAGE & PRICE ═══════════
                if (_currentStep == 1) ...[
                // ─── ITEMS SECTION ───
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _label(_lang.get('cj_senarai_kerosakan')),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _items.add(RepairItem(nama: ''))),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.blue,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(_lang.get('cj_tambah'),
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ]),
                const SizedBox(height: 6),
                ...List.generate(_items.length, (i) => _buildItemRow(i)),

                // ─── STOCK USAGE HISTORY ───
                if (_stockUsageHistory.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _label(_lang.get('cj_stok_digunakan')),
                  const SizedBox(height: 6),
                  ...List.generate(_stockUsageHistory.length, (i) {
                    final u = _stockUsageHistory[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.green.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const FaIcon(FontAwesomeIcons.boxOpen, size: 12, color: AppColors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u['kod'] ?? '', style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900)),
                            Text(u['nama'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                            Text('RM ${((u['jual'] ?? 0) as num).toStringAsFixed(2)} • ${u['tarikh']}',
                                style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                          ],
                        )),
                        GestureDetector(
                          onTap: () => _cancelStockUsage(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const FaIcon(FontAwesomeIcons.xmark, size: 9, color: AppColors.red),
                              const SizedBox(width: 4),
                              Text(_lang.get('batal'), style: const TextStyle(color: AppColors.red, fontSize: 8, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        ),
                      ]),
                    );
                  }),
                ],
                const SizedBox(height: 14),

                // ─── STAFF TERIMA ───
                if (!_singleStaffMode && _staffList.isNotEmpty) ...[
                  _label(_lang.get('cj_staff_menerima')),
                  const SizedBox(height: 6),
                  _buildDropdown(
                    _staffList.contains(_staffTerima)
                        ? _staffTerima
                        : _staffList.first,
                    _staffList,
                    (v) => setState(() => _staffTerima = v!),
                  ),
                  const SizedBox(height: 14),
                ],

                // ─── PASSWORD + PATTERN + VOUCHER ───
                _label(_lang.get('cj_password_pattern')),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: _input(_passwordCtrl, _lang.get('cj_pass_hint'))),
                  const SizedBox(width: 6),
                  // Pattern button
                  GestureDetector(
                    onTap: _showPatternDialog,
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: _patternResult.isNotEmpty
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _patternResult.isNotEmpty
                                ? AppColors.primary
                                : AppColors.border),
                      ),
                      child: Center(
                          child: FaIcon(FontAwesomeIcons.gripVertical,
                              size: 14,
                              color: _patternResult.isNotEmpty
                                  ? AppColors.primary
                                  : AppColors.textDim)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Voucher + button
                  GestureDetector(
                    onTap: _showVoucherPopup,
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: _kodVoucher.isNotEmpty
                            ? AppColors.yellow.withValues(alpha: 0.15)
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _kodVoucher.isNotEmpty
                                ? AppColors.yellow
                                : AppColors.border),
                      ),
                      child: Center(
                          child: _kodVoucher.isNotEmpty
                            ? const FaIcon(FontAwesomeIcons.ticket,
                                size: 14, color: AppColors.yellow)
                            : const FaIcon(FontAwesomeIcons.plus,
                                size: 14, color: AppColors.textDim)),
                    ),
                  ),
                ]),
                // Active indicators
                if (_patternResult.isNotEmpty || _kodVoucher.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 12, children: [
                      if (_patternResult.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const FaIcon(FontAwesomeIcons.circleCheck,
                              size: 9, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text('Pattern: $_patternResult',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      if (_kodVoucher.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const FaIcon(FontAwesomeIcons.ticket,
                              size: 9, color: AppColors.yellow),
                          const SizedBox(width: 4),
                          Text('$_kodVoucher (-RM${_voucherAmt.toStringAsFixed(2)})',
                              style: const TextStyle(
                                  color: AppColors.yellow,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() {
                              _kodVoucher = '';
                              _voucherAmt = 0;
                              _promoCtrl.clear();
                            }),
                            child: const FaIcon(FontAwesomeIcons.xmark,
                                size: 10, color: AppColors.red),
                          ),
                        ]),
                    ]),
                  ),
                const SizedBox(height: 14),
                ], // END STEP 2

                // ═══════════ STEP 3: FINANCE ═══════════
                if (_currentStep == 2) ...[
                // ─── PAYMENT SUMMARY ───
                _buildPaymentSummary(),
                const SizedBox(height: 14),

                // ─── JENIS SERVIS + CATATAN ───
                Row(children: [
                  Expanded(flex: 4, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(_lang.get('cj_jenis_servis')),
                      const SizedBox(height: 6),
                      _buildDropdown(
                        _jenisServis,
                        _jenisServisOptions,
                        (v) => setState(() => _jenisServis = v!),
                      ),
                    ],
                  )),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(_lang.get('cj_nota')),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _showCatatanPopup,
                        child: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: _catatanCtrl.text.isNotEmpty
                                ? AppColors.blue.withValues(alpha: 0.15)
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _catatanCtrl.text.isNotEmpty
                                ? AppColors.blue : AppColors.border),
                          ),
                          child: Center(child: FaIcon(
                            _catatanCtrl.text.isNotEmpty ? FontAwesomeIcons.noteSticky : FontAwesomeIcons.plus,
                            size: 14,
                            color: _catatanCtrl.text.isNotEmpty ? AppColors.blue : AppColors.textDim)),
                        ),
                      ),
                    ],
                  ),
                ]),
                if (_catatanCtrl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_catatanCtrl.text,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontStyle: FontStyle.italic),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                const SizedBox(height: 14),

                ], // END STEP 3

                // ═══════════ STEP 4: PHOTO (only if gallery addon) ═══════════
                // ─── SNAP GAMBAR (atas butang simpan) ───
                if (_currentStep == 3 && _hasGalleryAddon && !kIsWeb) ...[
                  const SizedBox(height: 14),
                  _label(_lang.get('cj_gambar_kerosakan')),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _showSnapGambarModal,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FaIcon(FontAwesomeIcons.camera,
                                size: 14, color: AppColors.red),
                            const SizedBox(width: 10),
                            Text(
                              _imgDepan != null || _imgBelakang != null
                                  ? '${_lang.get('cj_gambar_diambil')} (${[
                                      if (_imgDepan != null) _lang.get('cj_depan'),
                                      if (_imgBelakang != null) _lang.get('cj_belakang')
                                    ].join(' + ')})'
                                  : _lang.get('cj_tekan_snap'),
                              style: TextStyle(
                                  color: _imgDepan != null
                                      ? AppColors.green
                                      : AppColors.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900),
                            ),
                          ]),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // ─── ACTION BUTTONS (last step only) ───
                if (_currentStep == _totalSteps - 1) ...[
                  _buildActionButtons(),

                  // ─── POST-SAVE: Quote/Print buttons ───
                  if (_isFormLocked && _savedSiri.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildPostSaveButtons(),
                  ],
                ],

                // ─── WIZARD NAV (Previous / Next) ───
                const SizedBox(height: 12),
                _buildWizardNav(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── CUSTOMER TYPE TOGGLE ───
  Widget _buildCustTypeToggle() {
    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _custType = 'NEW CUST';
            _custSearchResults = [];
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _custType == 'NEW CUST'
                  ? AppColors.primary
                  : AppColors.border,
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10)),
              border: Border.all(
                  color: _custType == 'NEW CUST'
                      ? AppColors.primary
                      : AppColors.border),
            ),
            child: Center(
              child: Text(_lang.get('cj_new_cust'),
                  style: TextStyle(
                      color: _custType == 'NEW CUST'
                          ? Colors.black
                          : AppColors.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
      Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _custType = 'REGULAR'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _custType == 'REGULAR'
                  ? AppColors.blue
                  : AppColors.border,
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(10)),
              border: Border.all(
                  color: _custType == 'REGULAR'
                      ? AppColors.blue
                      : AppColors.border),
            ),
            child: Center(
              child: Text(_lang.get('regular'),
                  style: TextStyle(
                      color: _custType == 'REGULAR'
                          ? Colors.black
                          : AppColors.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    ]);
  }

  // ─── REGULAR CUSTOMER AUTOCOMPLETE ───
  Widget _buildRegularCustSearch() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('CARI PELANGGAN SEDIA ADA'),
      const SizedBox(height: 6),
      _input(_custSearchCtrl, 'Cari nama / tel / voucher / referral...',
          onChanged: (v) => _searchCustomers(v)),
      if (_custSearchResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _custSearchResults.length,
            itemBuilder: (_, i) {
              final c = _custSearchResults[i];
              return InkWell(
                onTap: () => _selectCustomer(c),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const FaIcon(FontAwesomeIcons.userCheck,
                        size: 12, color: AppColors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                (c['nama'] ?? '').toString().toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                            Text(
                                'Tel: ${c['tel']}',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 9)),
                            Row(children: [
                              if ((c['voucher'] ?? '').toString().isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 3, right: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.yellow.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const FaIcon(FontAwesomeIcons.ticket, size: 7, color: AppColors.yellow),
                                    const SizedBox(width: 3),
                                    Text(c['voucher'], style: const TextStyle(color: AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w800)),
                                  ]),
                                ),
                              if ((c['referral'] ?? '').toString().isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 3),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.green.withValues(alpha: 0.3))),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const FaIcon(FontAwesomeIcons.userPlus, size: 7, color: AppColors.green),
                                    const SizedBox(width: 3),
                                    Text(c['referral'], style: const TextStyle(color: AppColors.green, fontSize: 8, fontWeight: FontWeight.w800)),
                                  ]),
                                ),
                            ]),
                          ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }

  // ─── PAYMENT SUMMARY ───
  Widget _buildPaymentSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primary.withValues(alpha: 0.05),
          AppColors.bgDeep.withValues(alpha: 0.3),
        ]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title
        Row(children: [
          const FaIcon(FontAwesomeIcons.receipt,
              size: 12, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(_lang.get('cj_ringkasan_bayaran'),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
        ]),
        const SizedBox(height: 12),

        // Row 1: Harga Asal + Diskaun
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('HARGA (RM)'),
              const SizedBox(height: 4),
              TextField(
                controller: TextEditingController(text: 'RM ${_totalHarga.toStringAsFixed(2)}'),
                readOnly: true,
                style: const TextStyle(
                    color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.bgDeep,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                ),
              ),
            ],
          )),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('DISKAUN (RM)'),
              const SizedBox(height: 4),
              _input(_diskaunCtrl, '0.00',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {})),
            ],
          )),
        ]),
        const SizedBox(height: 8),

        // Row 2: Voucher + Deposit
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('KOD VOUCHER'),
              const SizedBox(height: 4),
              Autocomplete<Map<String, dynamic>>(
                optionsBuilder: (v) {
                  if (v.text.isEmpty) return _activeVouchers.take(5);
                  return _activeVouchers.where((vc) =>
                      (vc['code'] ?? '').toString().toLowerCase()
                          .contains(v.text.toLowerCase())).take(5);
                },
                displayStringForOption: (o) => (o['code'] ?? '').toString(),
                onSelected: (o) {
                  final code = (o['code'] ?? '').toString();
                  final amt = double.tryParse(o['value']?.toString() ?? '0') ?? 0;
                  setState(() {
                    _kodVoucher = code;
                    _voucherAmt = amt;
                    _promoCtrl.text = code;
                  });
                  _snack('Voucher $code aktif! -RM${amt.toStringAsFixed(2)}');
                },
                fieldViewBuilder: (_, ctrl, fn, __) {
                  if (ctrl.text.isEmpty && _promoCtrl.text.isNotEmpty) {
                    ctrl.text = _promoCtrl.text;
                  }
                  return TextField(
                    controller: ctrl,
                    focusNode: fn,
                    onChanged: (v) => _promoCtrl.text = v,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: _kodVoucher.isNotEmpty
                          ? '$_kodVoucher (-RM${_voucherAmt.toStringAsFixed(0)})'
                          : 'Kod voucher...',
                      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.bgDeep,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                  );
                },
                optionsViewBuilder: (_, onSel, opts) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180, maxWidth: 260),
                      child: ListView(
                        shrinkWrap: true,
                        children: opts.map((o) => InkWell(
                          onTap: () => onSel(o),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(children: [
                              const FaIcon(FontAwesomeIcons.ticket, size: 10, color: AppColors.yellow),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o['code']?.toString() ?? '',
                                      style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
                                  Text('RM${(o['value'] ?? 0).toString()} | Baki: ${(o['limit'] ?? 0) - (o['claimed'] ?? 0)}',
                                      style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ]),
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('DEPOSIT (RM)'),
              const SizedBox(height: 4),
              _input(_depositCtrl, '0.00',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {})),
            ],
          )),
        ]),
        const SizedBox(height: 10),

        // Baki Akhir — label luar, kotak sama size
        _label('BAKI AKHIR'),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text('RM ${_totalBaki.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 12),

        // Payment Status
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('STATUS BAYARAN'),
                  const SizedBox(height: 4),
                  _buildDropdown(
                    _paymentStatus,
                    _paymentStatusOptions,
                    (v) => setState(() => _paymentStatus = v!),
                  ),
                ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('CARA BAYARAN'),
                  const SizedBox(height: 4),
                  _buildDropdown(
                    _caraBayaran,
                    _caraBayaranOptions,
                    (v) => setState(() => _caraBayaran = v!),
                  ),
                ]),
          ),
        ]),
      ]),
    );
  }

  // ─── ACTION BUTTONS ───
  Widget _buildStepIndicator() {
    final titles = <String>[
      _lang.get('cj_step_cust'),
      _lang.get('cj_step_kerosakan'),
      _lang.get('cj_step_kewangan'),
      if (_hasGalleryAddon && !kIsWeb) _lang.get('cj_step_gambar'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_lang.get('cj_langkah')} ${_currentStep + 1} ${_lang.get('cj_dari')} $_totalSteps — ${titles[_currentStep]}',
          style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(_totalSteps, (i) {
            final active = i <= _currentStep;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 4),
                height: 4,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildWizardNav() {
    final isLast = _currentStep == _totalSteps - 1;
    return Row(children: [
      if (_currentStep > 0)
        Expanded(
          child: GestureDetector(
            onTap: _isFormLocked
                ? null
                : () => setState(() => _currentStep--),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FaIcon(FontAwesomeIcons.chevronLeft,
                      size: 11, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Text(_lang.get('cj_previous'),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        ),
      if (_currentStep > 0 && !isLast) const SizedBox(width: 8),
      if (!isLast)
        Expanded(
          child: GestureDetector(
            onTap: _isFormLocked
                ? null
                : () => setState(() => _currentStep++),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_lang.get('cj_next'),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  const FaIcon(FontAwesomeIcons.chevronRight,
                      size: 11, color: Colors.black),
                ],
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _buildActionButtons() {
    return Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: (_isSaving || _isFormLocked) ? null : _simpanTiket,
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
          label: Text(_isSaving
              ? 'MENYIMPAN...'
              : _isFormLocked
                  ? 'SAVED'
                  : 'SIMPAN TIKET'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _resetForm,
          icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 12),
          label: Text(_lang.get('cj_reset')),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellow,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
    ]);
  }

  // ─── POST SAVE BUTTONS ───
  Widget _buildPostSaveButtons() {
    return AbsorbPointer(
      absorbing: false,
      child: Opacity(
        opacity: 1,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.green.withValues(alpha: 0.2)),
          ),
          child: Column(children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.circleCheck,
                  size: 14, color: AppColors.green),
              const SizedBox(width: 8),
              Text('${_lang.get('cj_tiket_berjaya')} #$_savedSiri',
                  style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ]),
            if (_generatedVoucher.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const FaIcon(FontAwesomeIcons.ticket,
                    size: 10, color: AppColors.yellow),
                const SizedBox(width: 6),
                Text('${_lang.get('cj_voucher_dijana')}: $_generatedVoucher',
                    style: const TextStyle(
                        color: AppColors.yellow,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: _generatedVoucher));
                    _snack('Voucher disalin!');
                  },
                  child: const FaIcon(FontAwesomeIcons.copy,
                      size: 10, color: AppColors.textMuted),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _printQuote80mm,
                  icon: const FaIcon(FontAwesomeIcons.print, size: 12),
                  label: Text(_lang.get('cj_quote_80mm')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.black,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _printQuoteA4,
                  icon: const FaIcon(FontAwesomeIcons.filePdf, size: 12),
                  label: Text(_lang.get('cj_quote_a4')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.black,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ─── SCAN STOCK FOR KEROSAKAN ───
  void _openStockScanner() {
    if (kIsWeb) {
      _snack('Scanner tidak tersedia di web', err: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BarcodeScannerPage(
          onScanned: (code) async {
            Navigator.pop(context);
            final cleanCode = code.trim().toUpperCase();
            if (cleanCode.isEmpty) return;

            // Query Firestore for earliest AVAILABLE stock with this kod
            final snap = await _db
                .collection('inventory_$_ownerID')
                .where('kod', isEqualTo: cleanCode)
                .where('status', isEqualTo: 'AVAILABLE')
                .get();

            if (snap.docs.isEmpty) {
              _snack('Tiada stok "$cleanCode" yang available', err: true);
              return;
            }

            // Pick the earliest stock (lowest timestamp)
            final docs = snap.docs.toList()
              ..sort((a, b) => ((a.data()['timestamp'] ?? 0) as num).compareTo((b.data()['timestamp'] ?? 0) as num));
            final doc = docs.first;
            final inv = doc.data();
            final docId = doc.id;
            final now = DateTime.now();

            // Mark stock as USED
            await _db.collection('inventory_$_ownerID').doc(docId).update({
              'status': 'USED',
              'tkh_guna': DateFormat('yyyy-MM-dd HH:mm').format(now),
            });

            // Record in stock usage history
            final usageRef = await _db.collection('stock_usage_$_ownerID').add({
              'stock_doc_id': docId,
              'kod': cleanCode,
              'nama': inv['nama'] ?? '',
              'kos': inv['kos'] ?? 0,
              'jual': inv['jual'] ?? 0,
              'shopID': _shopID,
              'timestamp': now.millisecondsSinceEpoch,
              'tarikh': DateFormat('yyyy-MM-dd HH:mm').format(now),
              'status': 'USED',
            });

            // Track locally for history display
            setState(() {
              _stockUsageHistory.add({
                'usage_id': usageRef.id,
                'stock_doc_id': docId,
                'kod': cleanCode,
                'nama': inv['nama'] ?? '',
                'jual': inv['jual'] ?? 0,
                'tarikh': DateFormat('HH:mm').format(now),
              });
              _items.add(RepairItem(
                nama: inv['nama']?.toString() ?? '',
                qty: 1,
                harga: (inv['jual'] as num?)?.toDouble() ?? 0,
              ));
            });
            _snack('Stok diambil: ${inv['nama']}');
          },
        ),
      ),
    );
  }

  // ─── CANCEL STOCK USAGE ───
  Future<void> _cancelStockUsage(int index) async {
    final usage = _stockUsageHistory[index];
    final stockDocId = usage['stock_doc_id'] as String;
    final usageId = usage['usage_id'] as String;

    // Restore stock to AVAILABLE
    await _db.collection('inventory_$_ownerID').doc(stockDocId).update({
      'status': 'AVAILABLE',
      'tkh_guna': '',
    });

    // Update usage record
    await _db.collection('stock_usage_$_ownerID').doc(usageId).update({
      'status': 'CANCELLED',
      'cancelled_at': DateTime.now().millisecondsSinceEpoch,
    });

    setState(() => _stockUsageHistory.removeAt(index));
    _snack('Stok "${usage['nama']}" dibatalkan, kembali ke inventori');
  }

  // ─── ITEM ROW WITH AUTOCOMPLETE ───
  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        // Item name autocomplete
        Autocomplete<Map<String, dynamic>>(
          optionsBuilder: (v) => v.text.isEmpty
              ? const Iterable.empty()
              : _inventory
                  .where((inv) =>
                      (inv['nama'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(v.text.toLowerCase()) ||
                      (inv['kod'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(v.text.toLowerCase()))
                  .take(5),
          displayStringForOption: (o) => o['nama']?.toString() ?? '',
          onSelected: (o) => setState(() {
            item.nama = o['nama']?.toString() ?? '';
            item.harga = (o['jual'] as num?)?.toDouble() ?? 0;
            // Update harga controller
            _hargaCtrlCache[index]?.text = item.harga > 0 ? item.harga.toStringAsFixed(2) : '';
          }),
          fieldViewBuilder: (_, ctrl, fn, onSubmit) {
            if (ctrl.text.isEmpty && item.nama.isNotEmpty) {
              ctrl.text = item.nama;
            }
            return TextField(
              controller: ctrl,
              focusNode: fn,
              onChanged: (v) => item.nama = v,
              style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Cari inventori / taip manual...',
                hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                filled: true,
                fillColor: Colors.grey.shade100,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                suffixIcon: !kIsWeb ? GestureDetector(
                  onTap: _openStockScanner,
                  child: Container(
                    width: 36,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(child: FaIcon(FontAwesomeIcons.barcode, size: 12, color: Colors.black)),
                  ),
                ) : null,
              ),
            );
          },
          optionsViewBuilder: (_, onSel, opts) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 200, maxWidth: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: opts
                      .map((o) => InkWell(
                            onTap: () => onSel(o),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(o['kod']?.toString() ?? '',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                  Text(o['nama']?.toString() ?? '',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      'RM ${(o['jual'] as num?)?.toStringAsFixed(2) ?? '0'} (Stok: ${o['qty']})',
                                      style: const TextStyle(
                                          color: AppColors.green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Qty + Harga + Delete
        Row(children: [
          SizedBox(
            width: 55,
            child: _rawInput(
                _getQtyCtrl(index, item), null, 'Qty',
                keyboard: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  item.qty = int.tryParse(v) ?? 1;
                  setState(() {});
                }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _rawInput(
                _getHargaCtrl(index, item), null,
                'Harga (RM)',
                keyboard:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) {
                  item.harga = double.tryParse(v) ?? 0;
                  setState(() {});
                }),
          ),
          const SizedBox(width: 8),
          // Item total
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
                'RM ${(item.qty * item.harga).toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _items.length > 1
                ? () => setState(() {
                    _items.removeAt(index);
                    _qtyCtrlCache.clear();
                    _hargaCtrlCache.clear();
                  })
                : null,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Center(
                  child: FaIcon(FontAwesomeIcons.trash,
                      size: 12, color: AppColors.red)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ─── DROPDOWN BUILDER ───
  Widget _buildDropdown(
      String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w900),
          items: items
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ─── HELPERS ───
  Widget _label(String t) => Text(t,
      style: const TextStyle(
          color: AppColors.textSub,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5));

  Widget _input(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text,
      ValueChanged<String>? onChanged,
      int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      onChanged: onChanged,
      maxLines: maxLines,
      style: const TextStyle(
          color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppColors.textDim, fontSize: 12),
        filled: true,
        fillColor: AppColors.bgDeep,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary)),
      ),
    );
  }

  Widget _rawInput(TextEditingController c, FocusNode? fn, String h,
      {TextInputType keyboard = TextInputType.text,
      TextAlign textAlign = TextAlign.start,
      ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      focusNode: fn,
      keyboardType: keyboard,
      textAlign: textAlign,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        hintText: h,
        hintStyle:
            const TextStyle(color: AppColors.textDim, fontSize: 11),
        filled: true,
        fillColor: AppColors.bgDeep,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PATTERN GRID WIDGET — 3x3 dot grid with touch/mouse drawing
// Output format: "1-2-5-8" etc
// ═══════════════════════════════════════════════════════════════════
class _PatternGrid extends StatefulWidget {
  final List<int> selected;
  final VoidCallback onUpdate;

  const _PatternGrid({required this.selected, required this.onUpdate});

  @override
  State<_PatternGrid> createState() => _PatternGridState();
}

class _PatternGridState extends State<_PatternGrid> {
  final _dotKeys = List.generate(9, (_) => GlobalKey());
  Offset? _currentPointer;
  final List<Offset> _dotCenters = List.filled(9, Offset.zero);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _computeDotCenters());
  }

  void _computeDotCenters() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    for (int i = 0; i < 9; i++) {
      final key = _dotKeys[i];
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final center = box.localToGlobal(
          Offset(box.size.width / 2, box.size.height / 2),
          ancestor: renderBox);
      _dotCenters[i] = center;
    }
  }

  int? _hitTest(Offset pos) {
    for (int i = 0; i < 9; i++) {
      if ((pos - _dotCenters[i]).distance < 28) return i + 1;
    }
    return null;
  }

  void _handlePointer(Offset localPos) {
    _currentPointer = localPos;
    final hit = _hitTest(localPos);
    if (hit != null && !widget.selected.contains(hit)) {
      widget.selected.add(hit);
      widget.onUpdate();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _handlePointer(d.localPosition),
      onPanUpdate: (d) => _handlePointer(d.localPosition),
      onPanEnd: (_) => setState(() => _currentPointer = null),
      child: CustomPaint(
        painter: _PatternLinePainter(
          dotCenters: _dotCenters,
          selected: widget.selected,
          currentPointer: _currentPointer,
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12),
          itemCount: 9,
          itemBuilder: (_, i) {
            final num = i + 1;
            final isSelected = widget.selected.contains(num);
            final order =
                isSelected ? widget.selected.indexOf(num) + 1 : 0;
            return Container(
              key: _dotKeys[i],
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.border,
                border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFF475569),
                    width: 2),
              ),
              child: Center(
                child: Text(isSelected ? '$order' : '$num',
                    style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textDim,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatternLinePainter extends CustomPainter {
  final List<Offset> dotCenters;
  final List<int> selected;
  final Offset? currentPointer;

  _PatternLinePainter({
    required this.dotCenters,
    required this.selected,
    this.currentPointer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (selected.isEmpty) return;
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < selected.length - 1; i++) {
      final from = dotCenters[selected[i] - 1];
      final to = dotCenters[selected[i + 1] - 1];
      canvas.drawLine(from, to, paint);
    }

    // Draw trailing line to current pointer
    if (currentPointer != null && selected.isNotEmpty) {
      final lastDot = dotCenters[selected.last - 1];
      final trailPaint = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.3)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(lastDot, currentPointer!, trailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternLinePainter old) => true;
}

// ─── BARCODE SCANNER PAGE ───
class _BarcodeScannerPage extends StatefulWidget {
  final void Function(String code) onScanned;
  const _BarcodeScannerPage({required this.onScanned});

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _scannerCtrl = MobileScannerController();
  final _lang = AppLanguage();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_lang.get('cj_scan_stok'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerCtrl.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerCtrl.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerCtrl,
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _hasScanned = true;
                widget.onScanned(barcodes.first.rawValue!);
              }
            },
          ),
          Center(
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Scan barcode stok untuk tambah ke senarai kerosakan',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
