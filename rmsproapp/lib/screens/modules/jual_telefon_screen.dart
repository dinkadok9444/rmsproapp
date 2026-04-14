import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../services/repair_service.dart';

const String _cloudRunUrl = 'https://rms-backend-94407896005.asia-southeast1.run.app';

class JualTelefonScreen extends StatefulWidget {
  const JualTelefonScreen({super.key});
  @override
  State<JualTelefonScreen> createState() => _JualTelefonScreenState();
}

class _JualTelefonScreenState extends State<JualTelefonScreen> {
  final _lang = AppLanguage();
  final _db = FirebaseFirestore.instance;
  final _repairService = RepairService();
  String _ownerID = '', _shopID = '';
  Map<String, dynamic> _branchSettings = {};
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  List<Map<String, dynamic>> _phoneStock = [];
  List<String> _staffList = [];
  StreamSubscription? _sub;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _filterTime = 'SEMUA';
  DateTime? _customStart;
  DateTime? _customEnd;

  // View mode: AKTIF / ARKIB / PADAM
  String _viewMode = 'AKTIF';
  List<Map<String, dynamic>> _archivedSales = [];
  List<Map<String, dynamic>> _filteredArchived = [];
  List<Map<String, dynamic>> _deletedSales = [];
  List<Map<String, dynamic>> _filteredDeleted = [];
  final _archiveSearchCtrl = TextEditingController();
  final _deletedSearchCtrl = TextEditingController();

  // Segment: CUSTOMER / DEALER
  String _segment = 'CUSTOMER';
  List<Map<String, dynamic>> _savedDealers = [];
  StreamSubscription? _dealerSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dealerSub?.cancel();
    _searchCtrl.dispose();
    _archiveSearchCtrl.dispose();
    _deletedSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase(); // FIXED: toLowerCase() untuk sync dengan history
      _shopID = branch.split('@')[1].toUpperCase();
    }
    try {
      final shopDoc = await _db.collection('shops_$_ownerID').doc(_shopID).get();
      if (shopDoc.exists) _branchSettings = shopDoc.data() ?? {};
    } catch (_) {}
    await _repairService.init();
    _staffList = await _repairService.getStaffList();
    if (_ownerID.isNotEmpty) {
      _listenSales();
      _listenStock();
      _listenDealers();
    }
  }

  void _listenDealers() {
    _dealerSub = _db.collection('dealers_$_ownerID')
        .where('shopID', isEqualTo: _shopID)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) {
        final data = d.data();
        data['_id'] = d.id;
        return data;
      }).toList();
      if (mounted) setState(() => _savedDealers = list);
    });
  }

  void _listenSales() {
    _sub = _db
        .collection('phone_receipts_$_ownerID')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
      final all = snap.docs.map((d) {
        final data = d.data();
        data['_id'] = d.id;
        return data;
      }).where((d) => (d['shopID'] ?? '').toString().toUpperCase() == _shopID).toList();

      final active = <Map<String, dynamic>>[];
      final archived = <Map<String, dynamic>>[];
      final deleted = <Map<String, dynamic>>[];

      for (final d in all) {
        final status = (d['billStatus'] ?? 'ACTIVE').toString().toUpperCase();
        if (status == 'DELETED') {
          // Auto permanent delete after 30 days
          final deletedAt = (d['deletedAt'] ?? 0) as num;
          if (deletedAt > 0) {
            final deletedDate = DateTime.fromMillisecondsSinceEpoch(deletedAt.toInt());
            if (DateTime.now().difference(deletedDate).inDays >= 30) {
              // Permanent delete
              _db.collection('phone_receipts_$_ownerID').doc(d['_id']).delete();
              continue;
            }
          }
          deleted.add(d);
        } else if (status == 'ARCHIVED') {
          archived.add(d);
        } else {
          active.add(d);
        }
      }

      if (mounted) setState(() {
        _sales = active;
        _archivedSales = archived;
        _deletedSales = deleted;
        _loading = false;
        _applyFilter();
      });
    });
  }

  void _applyFilter() {
    var data = List<Map<String, dynamic>>.from(_sales);

    // Segment filter
    data = data.where((d) {
      final type = (d['saleType'] ?? 'CUSTOMER').toString().toUpperCase();
      return type == _segment;
    }).toList();

    // Search filter
    final query = _searchCtrl.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      data = data.where((d) =>
          (d['phoneName'] ?? '').toString().toLowerCase().contains(query) ||
          (d['custName'] ?? '').toString().toLowerCase().contains(query) ||
          (d['custPhone'] ?? '').toString().toLowerCase().contains(query) ||
          (d['siri'] ?? '').toString().toLowerCase().contains(query) ||
          _itemsContainQuery(d['items'], query)).toList();
    }

    // Time filter
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    if (_filterTime == 'HARI INI') {
      final ms = todayStart.millisecondsSinceEpoch;
      data = data.where((d) => ((d['timestamp'] ?? 0) as num).toInt() >= ms).toList();
    } else if (_filterTime == 'MINGGU INI') {
      final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
      final ms = weekStart.millisecondsSinceEpoch;
      data = data.where((d) => ((d['timestamp'] ?? 0) as num).toInt() >= ms).toList();
    } else if (_filterTime == 'BULAN INI') {
      final monthStart = DateTime(now.year, now.month, 1);
      final ms = monthStart.millisecondsSinceEpoch;
      data = data.where((d) => ((d['timestamp'] ?? 0) as num).toInt() >= ms).toList();
    } else if (_filterTime == 'TAHUN INI') {
      final yearStart = DateTime(now.year, 1, 1);
      final ms = yearStart.millisecondsSinceEpoch;
      data = data.where((d) => ((d['timestamp'] ?? 0) as num).toInt() >= ms).toList();
    } else if (_filterTime == 'CUSTOM' && _customStart != null && _customEnd != null) {
      final startMs = _customStart!.millisecondsSinceEpoch;
      final endMs = _customEnd!.add(const Duration(days: 1)).millisecondsSinceEpoch;
      data = data.where((d) {
        final ts = ((d['timestamp'] ?? 0) as num).toInt();
        return ts >= startMs && ts < endMs;
      }).toList();
    }

    _filteredSales = data;

    // Filter archived
    var archData = List<Map<String, dynamic>>.from(_archivedSales);
    archData = archData.where((d) {
      final type = (d['saleType'] ?? 'CUSTOMER').toString().toUpperCase();
      return type == _segment;
    }).toList();
    final archQuery = _archiveSearchCtrl.text.toLowerCase().trim();
    if (archQuery.isNotEmpty) {
      archData = archData.where((d) =>
          (d['phoneName'] ?? '').toString().toLowerCase().contains(archQuery) ||
          (d['custName'] ?? '').toString().toLowerCase().contains(archQuery) ||
          (d['custPhone'] ?? '').toString().toLowerCase().contains(archQuery) ||
          (d['siri'] ?? '').toString().toLowerCase().contains(archQuery) ||
          _itemsContainQuery(d['items'], archQuery)).toList();
    }
    _filteredArchived = archData;

    // Filter deleted
    var delData = List<Map<String, dynamic>>.from(_deletedSales);
    delData = delData.where((d) {
      final type = (d['saleType'] ?? 'CUSTOMER').toString().toUpperCase();
      return type == _segment;
    }).toList();
    final delQuery = _deletedSearchCtrl.text.toLowerCase().trim();
    if (delQuery.isNotEmpty) {
      delData = delData.where((d) =>
          (d['phoneName'] ?? '').toString().toLowerCase().contains(delQuery) ||
          (d['custName'] ?? '').toString().toLowerCase().contains(delQuery) ||
          (d['custPhone'] ?? '').toString().toLowerCase().contains(delQuery) ||
          (d['siri'] ?? '').toString().toLowerCase().contains(delQuery) ||
          _itemsContainQuery(d['items'], delQuery)).toList();
    }
    _filteredDeleted = delData;
  }

  bool _itemsContainQuery(dynamic items, String query) {
    if (items is! List) return false;
    for (final item in items) {
      if (item is Map) {
        if ((item['imei'] ?? '').toString().toLowerCase().contains(query)) return true;
      }
    }
    return false;
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF0EA5E9), surface: Color(0xFF1E293B), onSurface: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _filterTime = 'CUSTOM';
        _customStart = picked.start;
        _customEnd = picked.end;
        _applyFilter();
      });
    }
  }

  // Cancel bill → move to archive
  Future<void> _cancelBill(Map<String, dynamic> sale) async {
    final id = sale['_id'] as String?;
    if (id == null) return;
    try {
      await _db.collection('phone_receipts_$_ownerID').doc(id).update({
        'billStatus': 'ARCHIVED',
        'archivedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _snack('Bill dibatalkan & diarkibkan');
    } catch (e) {
      _snack('Gagal cancel: $e', err: true);
    }
  }

  // Restore from archive → active
  Future<void> _restoreFromArchive(Map<String, dynamic> sale) async {
    final id = sale['_id'] as String?;
    if (id == null) return;
    try {
      await _db.collection('phone_receipts_$_ownerID').doc(id).update({
        'billStatus': 'ACTIVE',
        'archivedAt': FieldValue.delete(),
      });
      _snack('Bill dipulihkan');
    } catch (e) {
      _snack('Gagal pulihkan: $e', err: true);
    }
  }

  // Move from archive → deleted (soft delete)
  Future<void> _softDelete(Map<String, dynamic> sale) async {
    final id = sale['_id'] as String?;
    if (id == null) return;
    try {
      await _db.collection('phone_receipts_$_ownerID').doc(id).update({
        'billStatus': 'DELETED',
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _snack('Bill dipadam (boleh recover dalam 30 hari)');
    } catch (e) {
      _snack('Gagal padam: $e', err: true);
    }
  }

  // Recover from deleted → archive
  Future<void> _recoverFromDeleted(Map<String, dynamic> sale) async {
    final id = sale['_id'] as String?;
    if (id == null) return;
    try {
      await _db.collection('phone_receipts_$_ownerID').doc(id).update({
        'billStatus': 'ARCHIVED',
        'deletedAt': FieldValue.delete(),
      });
      _snack('Bill dipulihkan ke arkib');
    } catch (e) {
      _snack('Gagal recover: $e', err: true);
    }
  }

  // Permanent delete
  Future<void> _permanentDelete(Map<String, dynamic> sale) async {
    final id = sale['_id'] as String?;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padam Kekal?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        content: const Text('Bill ini akan dipadam secara kekal dan tidak boleh dipulihkan.', style: TextStyle(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Padam Kekal', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection('phone_receipts_$_ownerID').doc(id).delete();
      _snack('Bill dipadam secara kekal');
    } catch (e) {
      _snack('Gagal padam kekal: $e', err: true);
    }
  }

  String _remainingDays(Map<String, dynamic> sale) {
    final deletedAt = (sale['deletedAt'] ?? 0) as num;
    if (deletedAt <= 0) return '30 hari';
    final deletedDate = DateTime.fromMillisecondsSinceEpoch(deletedAt.toInt());
    final remaining = 30 - DateTime.now().difference(deletedDate).inDays;
    return '${remaining > 0 ? remaining : 0} hari';
  }

  void _listenStock() {
    _db.collection('phone_stock_$_ownerID').snapshots().listen((snap) {
      final list = snap.docs.map((d) {
        final data = d.data();
        data['_id'] = d.id;
        return data;
      }).where((d) =>
          (d['shopID'] ?? '').toString().toUpperCase() == _shopID &&
          (d['status'] ?? '').toString().toUpperCase() != 'SOLD' &&
          ((d['qty'] ?? 1) as num) > 0
      ).toList();
      if (mounted) setState(() => _phoneStock = list);
    });
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _fmtDate(dynamic ts) {
    if (ts is int && ts > 0) return DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts));
    return '-';
  }

  String _generateSiri() {
    final r = Random();
    return r.nextInt(900000 + 100000).toString().padLeft(6, '0');
  }

  void _showSaleForm() {
    final namaCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    String paymentMethod = 'CASH';
    String selectedStaff = _staffList.isNotEmpty ? _staffList.first : '';
    bool saving = false;
    String formError = '';
    List<Map<String, dynamic>> suggestions = [];
    List<Map<String, dynamic>> cartItems = [];
    final isDealer = _segment == 'DEALER';
    Map<String, dynamic>? selectedDealer;
    Map<String, dynamic>? selectedCawangan;
    String dealerSearch = '';
    String paymentTerm = 'TUNAI';
    int customTermDays = 0;
    String warranty = 'TIADA';
    int customWarrantyMonths = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 14, color: Color(0xFF0EA5E9)),
                    const SizedBox(width: 8),
                    Text(_lang.get('jt_jual_telefon'), style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
                  ]),
                  const Divider(height: 20, color: AppColors.border),

                  if (isDealer) ...[
                    const _SectionLabel('PILIH DEALER'),
                    const SizedBox(height: 8),
                    // Search dealer field
                    TextField(
                      onChanged: (v) => setS(() => dealerSearch = v.toLowerCase().trim()),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Cari dealer...',
                        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                        prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFFF59E0B)),
                        filled: true, fillColor: AppColors.bgDeep, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Dealer list
                    ...() {
                      final filtered = dealerSearch.isEmpty
                          ? _savedDealers
                          : _savedDealers.where((d) =>
                              (d['namaPemilik'] ?? d['nama'] ?? '').toString().toLowerCase().contains(dealerSearch) ||
                              (d['namaKedai'] ?? '').toString().toLowerCase().contains(dealerSearch) ||
                              (d['telPemilik'] ?? d['tel'] ?? '').toString().toLowerCase().contains(dealerSearch)).toList();
                      if (filtered.isEmpty) {
                        return [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10)),
                            child: Column(children: [
                              const FaIcon(FontAwesomeIcons.userTie, size: 20, color: AppColors.textDim),
                              const SizedBox(height: 8),
                              const Text('Tiada dealer', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () { Navigator.pop(ctx); _showDealerManager(); },
                                child: const Text('Tambah di Senarai Dealer', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
                              ),
                            ]),
                          ),
                        ];
                      }
                      return filtered.map<Widget>((d) {
                        final isSelected = selectedDealer?['_id'] == d['_id'];
                        final namaP = (d['namaPemilik'] ?? d['nama'] ?? '-').toString();
                        final namaK = (d['namaKedai'] ?? '').toString();
                        final cawangan = (d['cawangan'] is List) ? List<Map<String, dynamic>>.from((d['cawangan'] as List).map((c) => Map<String, dynamic>.from(c as Map))) : <Map<String, dynamic>>[];
                        return GestureDetector(
                          onTap: () => setS(() {
                            selectedDealer = d;
                            selectedCawangan = null;
                            namaCtrl.text = namaP;
                            telCtrl.text = (d['telPemilik'] ?? d['tel'] ?? '').toString();
                            alamatCtrl.text = (d['alamatKedai'] ?? d['alamat'] ?? '').toString();
                            paymentMethod = (d['bayaran'] ?? 'CASH').toString();
                            paymentTerm = (d['term'] ?? 'TUNAI').toString();
                            warranty = (d['warranty'] ?? 'TIADA').toString();
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.1) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? const Color(0xFFF59E0B) : AppColors.borderMed),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                FaIcon(isSelected ? FontAwesomeIcons.solidCircleCheck : FontAwesomeIcons.userTie,
                                    size: 12, color: isSelected ? const Color(0xFFF59E0B) : AppColors.textMuted),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(namaP, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
                                  if (namaK.isNotEmpty)
                                    Text(namaK, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w600)),
                                  Text('${d['telPemilik'] ?? d['tel'] ?? '-'} · SSM: ${d['noSSM'] ?? '-'}', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                                ])),
                                if (cawangan.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text('${cawangan.length} cawangan', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 8, fontWeight: FontWeight.w700)),
                                  ),
                                if (isSelected)
                                  const Padding(padding: EdgeInsets.only(left: 6), child: FaIcon(FontAwesomeIcons.check, size: 10, color: Color(0xFFF59E0B))),
                              ]),
                              // Cawangan picker (only when selected)
                              if (isSelected && cawangan.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const _SectionLabel('PILIH CAWANGAN'),
                                const SizedBox(height: 4),
                                // Default (HQ)
                                GestureDetector(
                                  onTap: () => setS(() {
                                    selectedCawangan = null;
                                    alamatCtrl.text = (d['alamatKedai'] ?? d['alamat'] ?? '').toString();
                                  }),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: selectedCawangan == null ? const Color(0xFF0EA5E9).withValues(alpha: 0.1) : AppColors.bgDeep,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: selectedCawangan == null ? const Color(0xFF0EA5E9) : AppColors.border),
                                    ),
                                    child: Row(children: [
                                      FaIcon(FontAwesomeIcons.store, size: 9, color: selectedCawangan == null ? const Color(0xFF0EA5E9) : AppColors.textDim),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text('${namaK.isNotEmpty ? namaK : namaP} (HQ)', style: TextStyle(color: selectedCawangan == null ? const Color(0xFF0EA5E9) : AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w700))),
                                    ]),
                                  ),
                                ),
                                ...cawangan.map((c) {
                                  final isCSelected = selectedCawangan != null && selectedCawangan!['namaKedai'] == c['namaKedai'];
                                  return GestureDetector(
                                    onTap: () => setS(() {
                                      selectedCawangan = c;
                                      alamatCtrl.text = (c['alamatKedai'] ?? '').toString();
                                    }),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isCSelected ? const Color(0xFF0EA5E9).withValues(alpha: 0.1) : AppColors.bgDeep,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isCSelected ? const Color(0xFF0EA5E9) : AppColors.border),
                                      ),
                                      child: Row(children: [
                                        FaIcon(FontAwesomeIcons.store, size: 9, color: isCSelected ? const Color(0xFF0EA5E9) : AppColors.textDim),
                                        const SizedBox(width: 8),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text((c['namaKedai'] ?? '-').toString(), style: TextStyle(color: isCSelected ? const Color(0xFF0EA5E9) : AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w700)),
                                          Text('${c['alamatKedai'] ?? '-'}', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                                        ])),
                                      ]),
                                    ),
                                  );
                                }),
                              ],
                            ]),
                          ),
                        );
                      }).toList();
                    }(),
                  ] else ...[
                    const _SectionLabel('MAKLUMAT PELANGGAN'),
                    const SizedBox(height: 8),
                    _formField('Nama Pelanggan', namaCtrl, 'cth: Ahmad'),
                    const SizedBox(height: 8),
                    _formField('No. Telefon', telCtrl, '01x-xxxxxxx', keyboard: TextInputType.phone),
                    const SizedBox(height: 8),
                    _formField('Alamat', alamatCtrl, 'Alamat (pilihan)'),
                  ],
                  const SizedBox(height: 16),

                  const _SectionLabel('PILIH TELEFON DARI INVENTORI'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: modelCtrl,
                        onChanged: (v) {
                          final q = v.toLowerCase().trim();
                          if (q.isEmpty) {
                            setS(() { suggestions = []; });
                          } else {
                            setS(() {
                              suggestions = _phoneStock.where((s) =>
                                (s['nama'] ?? '').toString().toLowerCase().contains(q) ||
                                (s['kod'] ?? '').toString().toLowerCase().contains(q) ||
                                (s['imei'] ?? '').toString().toLowerCase().contains(q)
                              ).take(5).toList();
                            });
                          }
                        },
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: 'Model Telefon',
                          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800),
                          hintText: 'Taip untuk cari dari stok...',
                          hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                          filled: true, fillColor: AppColors.bg, isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderMed)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderMed)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0EA5E9))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _scanBarcode(modelCtrl, setS),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFF0EA5E9), borderRadius: BorderRadius.circular(10)),
                        child: const FaIcon(FontAwesomeIcons.barcode, size: 16, color: Colors.white),
                      ),
                    ),
                  ]),

                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                      child: Column(children: suggestions.map((s) {
                        final nama = (s['nama'] ?? '-').toString();
                        final kod = (s['kod'] ?? '').toString();
                        final jualNormal = ((s['jual'] ?? 0) as num).toDouble();
                        final jualDealer = ((s['jualDealer'] ?? 0) as num).toDouble();
                        final jual = isDealer && jualDealer > 0 ? jualDealer : jualNormal;
                        final imei = (s['imei'] ?? '').toString();
                        final alreadyInCart = cartItems.any((c) => c['_id'] == s['_id']);
                        return GestureDetector(
                          onTap: alreadyInCart ? null : () => setS(() {
                            final cartItem = Map<String, dynamic>.from(s);
                            if (isDealer && jualDealer > 0) cartItem['jual'] = jualDealer;
                            cartItems.add(cartItem);
                            modelCtrl.clear();
                            suggestions = [];
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
                            child: Row(children: [
                              const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 11, color: Color(0xFF0EA5E9)),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                                if (kod.isNotEmpty || imei.isNotEmpty)
                                  Text('${kod.isNotEmpty ? kod : ''} ${imei.isNotEmpty ? '· IMEI: $imei' : ''}',
                                      style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                              ])),
                              if (alreadyInCart)
                                Text(_lang.get('jt_ditambah'), style: const TextStyle(color: AppColors.textDim, fontSize: 9))
                              else
                                Text('RM ${jual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        );
                      }).toList()),
                    ),
                  ],

                  if (cartItems.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...cartItems.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      final nama = (item['nama'] ?? '-').toString();
                      final kos = ((item['kos'] ?? 0) as num).toDouble();
                      final jual = ((item['jual'] ?? 0) as num).toDouble();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Center(child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 10, fontWeight: FontWeight.w900))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
                            Text('Beli: RM ${kos.toStringAsFixed(2)} · Jual: RM ${jual.toStringAsFixed(2)}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                          ])),
                          GestureDetector(
                            onTap: () => setS(() => cartItems.removeAt(i)),
                            child: const FaIcon(FontAwesomeIcons.circleXmark, size: 14, color: AppColors.red),
                          ),
                        ]),
                      );
                    }),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Text('${cartItems.length} item', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('JUMLAH: RM ${cartItems.fold<double>(0, (s, e) => s + ((e['jual'] ?? 0) as num).toDouble()).toStringAsFixed(2)}',
                            style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),

                  GestureDetector(
                    onTap: () => _showAddOnPicker(setS, cartItems),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const FaIcon(FontAwesomeIcons.plus, size: 10, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        Text(_lang.get('jt_addon_aksesori'),
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),

                  // Staff dropdown
                  if (_staffList.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _SectionLabel('STAFF INCHARGE'),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _staffList.contains(selectedStaff) ? selectedStaff : _staffList.first,
                          isExpanded: true,
                          dropdownColor: AppColors.bgDeep,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                          items: _staffList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setS(() => selectedStaff = v ?? ''),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  Row(children: [
                    // KAEDAH BAYARAN
                    Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: paymentMethod,
                          isExpanded: true,
                          dropdownColor: AppColors.bgDeep,
                          icon: const FaIcon(FontAwesomeIcons.caretDown, size: 10, color: AppColors.textMuted),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                          items: ['CASH', 'TRANSFER'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (v) => setS(() => paymentMethod = v ?? 'CASH'),
                        ),
                      ),
                    )),
                    const SizedBox(width: 6),
                    // TERM BAYARAN
                    Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: paymentTerm,
                          isExpanded: true,
                          dropdownColor: AppColors.bgDeep,
                          icon: const FaIcon(FontAwesomeIcons.caretDown, size: 10, color: AppColors.textMuted),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                          items: ['TUNAI', '7 HARI', '14 HARI', '30 HARI'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setS(() { paymentTerm = v ?? 'TUNAI'; customTermDays = 0; }),
                        ),
                      ),
                    )),
                    const SizedBox(width: 6),
                    // WARRANTY
                    Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: warranty,
                          isExpanded: true,
                          dropdownColor: AppColors.bgDeep,
                          icon: const FaIcon(FontAwesomeIcons.caretDown, size: 10, color: AppColors.textMuted),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                          items: ['TIADA', '1 BULAN', '2 BULAN', '3 BULAN'].map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                          onChanged: (v) => setS(() { warranty = v ?? 'TIADA'; customWarrantyMonths = 0; }),
                        ),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 20),

                  if (formError.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const FaIcon(FontAwesomeIcons.circleExclamation, size: 12, color: AppColors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(formError, style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w700))),
                      ]),
                    ),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : () async {
                        if (isDealer && selectedDealer == null) {
                          setS(() => formError = 'Sila pilih dealer dahulu');
                          return;
                        }
                        if (cartItems.isEmpty) {
                          setS(() => formError = 'Sila tambah sekurang-kurangnya satu item');
                          return;
                        }
                        setS(() { formError = ''; saving = true; });

                        final siri = _generateSiri();
                        final now = DateTime.now().millisecondsSinceEpoch;
                        double totalSell = 0;
                        double totalBuy = 0;
                        final itemNames = <String>[];

                        try {
                          for (final item in cartItems) {
                            final stockId = (item['_id'] ?? '').toString();
                            final nama = (item['nama'] ?? '-').toString();
                            final kos = ((item['kos'] ?? 0) as num).toDouble();
                            final jual = ((item['jual'] ?? 0) as num).toDouble();
                            final imei = (item['imei'] ?? '').toString();
                            final isAccessory = (item['_isAccessory'] ?? false) == true;
                            totalSell += jual;
                            totalBuy += kos;
                            itemNames.add(nama);

                            if (stockId.isNotEmpty) {
                              final collection = isAccessory ? 'inventory_$_ownerID' : 'phone_stock_$_ownerID';
                              if (isAccessory) {
                                final currentQty = ((item['qty'] ?? 1) as num).toInt();
                                if (currentQty <= 1) {
                                  await _db.collection(collection).doc(stockId).update({'qty': 0});
                                } else {
                                  await _db.collection(collection).doc(stockId).update({'qty': currentQty - 1});
                                }
                              } else {
                                await _db.collection(collection).doc(stockId).update({'status': 'SOLD', 'qty': 0, 'soldSiri': siri});
                                
                                final phoneSaleData = <String, dynamic>{
                                  'kod': item['kod'] ?? '',
                                  'nama': nama,
                                  'imei': imei,
                                  'warna': item['warna'] ?? '',
                                  'storage': item['storage'] ?? '',
                                  'kos': kos,
                                  'jual': jual,
                                  'imageUrl': item['imageUrl'] ?? '',
                                  'tarikh_jual': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                  'timestamp': now,
                                  'shopID': _shopID,
                                  'stockDocId': stockId,
                                  'siri': siri,
                                  'staffName': selectedStaff,
                                  'saleType': _segment,
                                  'custName': namaCtrl.text.trim().toUpperCase(),
                                  'custPhone': telCtrl.text.trim(),
                                };
                                if (isDealer && selectedDealer != null) {
                                  phoneSaleData['dealerName'] = selectedDealer!['namaPemilik'] ?? selectedDealer!['nama'] ?? '';
                                  phoneSaleData['dealerKedai'] = selectedDealer!['namaKedai'] ?? '';
                                }
                                await _db.collection('phone_sales_$_ownerID').add(phoneSaleData);
                              }
                            }
                          }

                          final receiptData = <String, dynamic>{
                            'siri': siri,
                            'custName': namaCtrl.text.trim().toUpperCase(),
                            'custPhone': telCtrl.text.trim(),
                            'custAddress': alamatCtrl.text.trim(),
                            'phoneName': itemNames.join(', '),
                            'items': cartItems.map((c) => {
                              'nama': c['nama'] ?? '',
                              'kos': c['kos'] ?? 0,
                              'jual': c['jual'] ?? 0,
                              'imei': c['imei'] ?? '',
                              'stockId': c['_id'] ?? '',
                              'isAccessory': c['_isAccessory'] ?? false,
                            }).toList(),
                            'buyPrice': totalBuy,
                            'sellPrice': totalSell,
                            'paymentMethod': paymentMethod,
                            'shopID': _shopID,
                            'status': 'SOLD',
                            'staffName': selectedStaff,
                            'timestamp': now,
                            'saleType': _segment,
                            'paymentTerm': paymentTerm == 'CUSTOM' ? '$customTermDays HARI' : paymentTerm,
                            'warranty': warranty == 'CUSTOM' ? '$customWarrantyMonths BULAN' : warranty,
                          };
                          if (isDealer && selectedDealer != null) {
                            receiptData['dealerId'] = selectedDealer!['_id'];
                            receiptData['dealerName'] = selectedDealer!['namaPemilik'] ?? selectedDealer!['nama'] ?? '';
                            receiptData['dealerKedai'] = selectedDealer!['namaKedai'] ?? '';
                            receiptData['dealerSSM'] = selectedDealer!['noSSM'] ?? '';
                            if (selectedCawangan != null) {
                              receiptData['cawanganNama'] = selectedCawangan!['namaKedai'] ?? '';
                              receiptData['cawanganAlamat'] = selectedCawangan!['alamatKedai'] ?? '';
                            }
                          }
                          await _db.collection('phone_receipts_$_ownerID').add(receiptData);

                          await _db.collection('jualan_pantas_$_ownerID').add({
                            'siri': siri,
                            'nama': 'JUALAN TELEFON',
                            'model': itemNames.join(', '),
                            'tel': telCtrl.text.trim(),
                            'total': totalSell.toString(),
                            'payment_status': 'PAID',
                            'jenis_servis': 'JUALAN',
                            'shopID': _shopID,
                            'timestamp': now,
                          });

                          if (ctx.mounted) Navigator.pop(ctx);
                          _snack('Jualan #$siri (${cartItems.length} item) ditambah');
                        } catch (e) {
                          setS(() => formError = 'Gagal: $e');
                        }
                        setS(() => saving = false);
                      },
                      icon: saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const FaIcon(FontAwesomeIcons.plus, size: 12),
                      label: Text(saving ? 'Menyimpan...' : 'TAMBAH JUALAN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9), foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scanBarcode(TextEditingController ctrl, StateSetter setS) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Stack(children: [
          MobileScanner(onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue != null) {
              final scanned = barcode!.rawValue!;
              ctrl.text = scanned;
              Navigator.pop(ctx);
              final match = _phoneStock.where((s) =>
                (s['imei'] ?? '').toString() == scanned ||
                (s['kod'] ?? '').toString() == scanned
              ).toList();
              if (match.isNotEmpty) {
                setS(() { ctrl.text = (match.first['nama'] ?? scanned).toString(); });
              }
            }
          }),
          Positioned(top: 16, right: 16, child: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: Colors.white),
            ),
          )),
          Positioned(bottom: 30, left: 0, right: 0, child: Center(
            child: Text(_lang.get('jt_scan_barcode'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  void _showAddOnPicker(StateSetter parentSetS, List<Map<String, dynamic>> cartItems) {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> inventory = [];
    List<Map<String, dynamic>> filtered = [];
    bool loading = true;

    _db.collection('inventory_$_ownerID').get().then((snap) {
      inventory = snap.docs.map((d) {
        final data = d.data();
        data['_id'] = d.id;
        return data;
      }).where((d) =>
        (d['shopID'] ?? '').toString().toUpperCase() == _shopID &&
        ((d['qty'] ?? 0) as num) > 0
      ).toList();
      filtered = List.from(inventory);
      loading = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.plus, size: 12, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Text(_lang.get('jt_addon_title'), style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w900)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (v) {
                      final q = v.toLowerCase().trim();
                      setS(() {
                        filtered = q.isEmpty ? List.from(inventory) : inventory.where((s) =>
                          (s['nama'] ?? '').toString().toLowerCase().contains(q) ||
                          (s['kod'] ?? '').toString().toLowerCase().contains(q)
                        ).toList();
                      });
                    },
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: _lang.get('jt_cari_hint'), hintStyle: const TextStyle(fontSize: 11, color: AppColors.textDim),
                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textMuted),
                      filled: true, fillColor: AppColors.bgDeep, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _scanBarcode(searchCtrl, setS);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(10)),
                    child: const FaIcon(FontAwesomeIcons.barcode, size: 14, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                  : filtered.isEmpty
                      ? Center(child: Text(_lang.get('jt_tiada_item'), style: const TextStyle(color: AppColors.textDim, fontSize: 12)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final item = filtered[i];
                            final nama = (item['nama'] ?? '-').toString();
                            final kod = (item['kod'] ?? '').toString();
                            final jual = ((item['jual'] ?? 0) as num).toDouble();
                            final qty = ((item['qty'] ?? 0) as num).toInt();
                            final alreadyAdded = cartItems.any((c) => c['_id'] == item['_id']);
                            return GestureDetector(
                              onTap: alreadyAdded ? null : () {
                                final addon = Map<String, dynamic>.from(item);
                                addon['_isAccessory'] = true;
                                parentSetS(() => cartItems.add(addon));
                                Navigator.pop(ctx);
                                _snack('$nama ditambah');
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: alreadyAdded ? AppColors.bgDeep : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.borderMed),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                    child: const Center(child: FaIcon(FontAwesomeIcons.boxOpen, size: 14, color: Color(0xFFF59E0B))),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                                    Text('$kod · Stok: $qty', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                                  ])),
                                  if (alreadyAdded)
                                    const FaIcon(FontAwesomeIcons.circleCheck, size: 14, color: AppColors.green)
                                  else
                                    Text('RM ${jual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
                                ]),
                              ),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _generateInvoice(Map<String, dynamic> sale) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Color(0xFF0EA5E9)),
          const SizedBox(height: 16),
          Text(_lang.get('jt_menjana_invoice'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      )),
    );

    try {
      final siri = sale['siri'] ?? '-';
      final sellPrice = double.tryParse(sale['sellPrice']?.toString() ?? '0') ?? 0;
      final payload = {
        'typePDF': 'INVOICE',
        'paperSize': 'A4',
        'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
        'logoBase64': _branchSettings['logoBase64'] ?? '',
        'namaKedai': _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'Repair Management System',
        'alamatKedai': _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
        'telKedai': _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
        'noJob': siri,
        'namaCust': sale['custName'] ?? '-',
        'telCust': sale['custPhone'] ?? '-',
        'tarikhResit': (sale['tarikh_jual'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now())),
        'stafIncharge': sale['staffName'] ?? 'Admin',
        'items': [
          {
            'nama': '${sale['phoneName'] ?? '-'} (JUALAN TELEFON)',
            'harga': sellPrice,
          }
        ],
        'model': sale['phoneName'] ?? '-',
        'kerosakan': 'JUALAN TELEFON',
        'warranty': 'TIADA',
        'warranty_exp': '',
        'voucherAmt': 0,
        'diskaunAmt': 0,
        'tambahanAmt': 0,
        'depositAmt': 0,
        'totalDibayar': sellPrice,
        'statusBayar': 'PAID',
        'nota': _branchSettings['notaInvoice'] ?? 'Terima kasih atas pembelian telefon.',
      };

      final response = await http.post(
        Uri.parse('$_cloudRunUrl/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pdfUrl = (data['pdfUrl'] ?? data['url'] ?? '').toString();
        if (pdfUrl.isNotEmpty) {
          await _db.collection('phone_receipts_$_ownerID').doc(sale['_id']).update({'invoiceUrl': pdfUrl});
          _snack('Invoice berjaya dijana!');
          _downloadAndOpenPDF(pdfUrl, siri.toString());
        } else {
          _snack('Pautan PDF tidak ditemui', err: true);
        }
      } else {
        _snack('Gagal menjana: ${response.statusCode}', err: true);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Gagal sambung server: $e', err: true);
    }
  }

  Future<void> _downloadAndOpenPDF(String pdfUrl, String siri) async {
    if (kIsWeb) {
      launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication);
      return;
    }
    _snack('Memuat turun Invoice...');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'INVOICE_TELEFON_$siri.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (!file.existsSync()) {
        await Dio().download(pdfUrl, filePath);
      }

      if (!mounted) return;
      _showPdfActions(pdfUrl, filePath, fileName, siri);
    } catch (e) {
      _snack('Gagal muat turun: $e', err: true);
    }
  }

  void _showPdfActions(String pdfUrl, String filePath, String fileName, String siri) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.filePdf, size: 14, color: Color(0xFF0EA5E9)),
            const SizedBox(width: 8),
            Expanded(child: Text('INVOICE #$siri', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w900))),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
            child: Row(children: [
              const FaIcon(FontAwesomeIcons.circleCheck, size: 24, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_lang.get('jt_invoice_sedia'), style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w900)),
                Text(fileName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ])),
            ]),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                OpenFilex.open(filePath);
              },
              icon: const FaIcon(FontAwesomeIcons.fileCircleCheck, size: 14),
              label: Text(_lang.get('buka_print_pdf')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pdfUrl));
                _snack('Link PDF disalin!');
              },
              icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
              label: Text(_lang.get('salin_link')),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.border, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(
              onPressed: () {
                final msg = Uri.encodeComponent('INVOICE Jualan Telefon #$siri\n$pdfUrl');
                launchUrl(Uri.parse('https://wa.me/?text=$msg'), mode: LaunchMode.externalApplication);
              },
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 12),
              label: Text(_lang.get('hantar_wa')),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
            )),
          ]),
        ]),
      ),
    );
  }

  Future<void> _saveDealer(Map<String, dynamic> dealerData, StateSetter setS) async {
    final nama = (dealerData['namaPemilik'] ?? '').toString().trim();
    final existing = _savedDealers.where((d) => (d['namaPemilik'] ?? '').toString().toUpperCase() == nama.toUpperCase()).toList();
    if (existing.isNotEmpty) {
      await _db.collection('dealers_$_ownerID').doc(existing.first['_id']).update(dealerData);
      _snack('Dealer dikemaskini');
    } else {
      dealerData['shopID'] = _shopID;
      dealerData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      dealerData['cawangan'] = dealerData['cawangan'] ?? [];
      await _db.collection('dealers_$_ownerID').add(dealerData);
      _snack('Dealer disimpan');
    }
  }

  void _showAddDealerPopup(StateSetter parentSetS) {
    final namaPemilikCtrl = TextEditingController();
    final telPemilikCtrl = TextEditingController();
    final namaKedaiCtrl = TextEditingController();
    final alamatKedaiCtrl = TextEditingController();
    final telKedaiCtrl = TextEditingController();
    final ssmCtrl = TextEditingController();
    String bayaran = 'CASH';
    String term = 'TUNAI';
    String warranty = 'TIADA';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) => Container(
        margin: const EdgeInsets.only(top: 80),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(dCtx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.userPlus, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              const Text('TAMBAH DEALER BARU', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pop(dCtx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const Divider(height: 20, color: AppColors.border),
            const _SectionLabel('MAKLUMAT PEMILIK'),
            const SizedBox(height: 6),
            _formField('Nama Pemilik', namaPemilikCtrl, 'cth: Ahmad bin Ali'),
            const SizedBox(height: 6),
            _formField('No. Telefon Pemilik', telPemilikCtrl, '01x-xxxxxxx', keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            const _SectionLabel('MAKLUMAT KEDAI'),
            const SizedBox(height: 6),
            _formField('Nama Kedai', namaKedaiCtrl, 'cth: Ali Phone Enterprise'),
            const SizedBox(height: 6),
            _formField('Alamat Kedai', alamatKedaiCtrl, 'Alamat penuh kedai'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _formField('No. Telefon Kedai', telKedaiCtrl, '0x-xxxxxxx', keyboard: TextInputType.phone)),
              const SizedBox(width: 6),
              Expanded(child: _formField('No. SSM', ssmCtrl, 'No. pendaftaran SSM')),
            ]),
            const SizedBox(height: 12),
            const _SectionLabel('TETAPAN JUALAN'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: bayaran, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                  items: ['CASH', 'TRANSFER'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setS(() => bayaran = v ?? 'CASH'),
                )),
              )),
              const SizedBox(width: 6),
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: term, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                  items: ['TUNAI', '7 HARI', '14 HARI', '30 HARI'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setS(() => term = v ?? 'TUNAI'),
                )),
              )),
              const SizedBox(width: 6),
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: warranty, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                  items: ['TIADA', '1 BULAN', '2 BULAN', '3 BULAN'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setS(() => warranty = v ?? 'TIADA'),
                )),
              )),
            ]),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                if (namaPemilikCtrl.text.trim().isEmpty) {
                  _snack('Sila isi nama pemilik', err: true);
                  return;
                }
                if (namaKedaiCtrl.text.trim().isEmpty) {
                  _snack('Sila isi nama kedai', err: true);
                  return;
                }
                _saveDealer({
                  'namaPemilik': namaPemilikCtrl.text.trim().toUpperCase(),
                  'telPemilik': telPemilikCtrl.text.trim(),
                  'namaKedai': namaKedaiCtrl.text.trim().toUpperCase(),
                  'alamatKedai': alamatKedaiCtrl.text.trim(),
                  'telKedai': telKedaiCtrl.text.trim(),
                  'noSSM': ssmCtrl.text.trim().toUpperCase(),
                  'bayaran': bayaran,
                  'term': term,
                  'warranty': warranty,
                  'cawangan': [],
                }, parentSetS);
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white),
                  SizedBox(width: 6),
                  Text('SIMPAN DEALER', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ])),
        ),
      )),
    );
  }

  void _showDealerManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.bookmark, size: 12, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                const Text('SENARAI DEALER', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w900)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim)),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onTap: () => _showAddDealerPopup(setS),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white),
                      SizedBox(width: 6),
                      Text('TAMBAH DEALER', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // Dealer list
                if (_savedDealers.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Tiada dealer tersimpan', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ))
                else
                  ..._savedDealers.map((d) {
                    final cawangan = (d['cawangan'] is List) ? List<Map<String, dynamic>>.from((d['cawangan'] as List).map((c) => Map<String, dynamic>.from(c as Map))) : <Map<String, dynamic>>[];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderMed),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Center(child: FaIcon(FontAwesomeIcons.userTie, size: 14, color: Color(0xFFF59E0B))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((d['namaPemilik'] ?? d['nama'] ?? '-').toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
                            if ((d['namaKedai'] ?? '').toString().isNotEmpty)
                              Text((d['namaKedai'] ?? '').toString(), style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w700)),
                            Text('${d['telPemilik'] ?? d['tel'] ?? '-'} · SSM: ${d['noSSM'] ?? '-'}', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                            const SizedBox(height: 2),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text((d['bayaran'] ?? 'CASH').toString(), style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 7, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text((d['term'] ?? 'TUNAI').toString(), style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 7, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text((d['warranty'] ?? 'TIADA').toString(), style: const TextStyle(color: Color(0xFF10B981), fontSize: 7, fontWeight: FontWeight.w800)),
                              ),
                            ]),
                          ])),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 14, color: AppColors.textMuted),
                            color: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [
                                FaIcon(FontAwesomeIcons.penToSquare, size: 12, color: Color(0xFF0EA5E9)),
                                SizedBox(width: 10),
                                Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              ])),
                              const PopupMenuItem(value: 'history', child: Row(children: [
                                FaIcon(FontAwesomeIcons.clockRotateLeft, size: 12, color: Color(0xFFF59E0B)),
                                SizedBox(width: 10),
                                Text('History Belian', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              ])),
                              const PopupMenuItem(value: 'cawangan', child: Row(children: [
                                FaIcon(FontAwesomeIcons.store, size: 12, color: Color(0xFF10B981)),
                                SizedBox(width: 10),
                                Text('Tambah Cawangan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              ])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [
                                FaIcon(FontAwesomeIcons.trashCan, size: 12, color: AppColors.red),
                                SizedBox(width: 10),
                                Text('Padam', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red)),
                              ])),
                            ],
                            onSelected: (val) async {
                              if (val == 'edit') {
                                _showEditDealer(d, setS);
                              } else if (val == 'history') {
                                _showDealerHistory(d);
                              } else if (val == 'cawangan') {
                                _showAddCawangan(d, setS);
                              } else if (val == 'delete') {
                                await _db.collection('dealers_$_ownerID').doc(d['_id']).delete();
                                _snack('Dealer dipadam');
                                if (ctx.mounted) setS(() {});
                              }
                            },
                          ),
                        ]),
                        // Cawangan list
                        if (cawangan.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const _SectionLabel('CAWANGAN'),
                          const SizedBox(height: 4),
                          ...cawangan.asMap().entries.map((entry) {
                            final ci = entry.key;
                            final c = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.15)),
                              ),
                              child: Row(children: [
                                const FaIcon(FontAwesomeIcons.store, size: 9, color: Color(0xFF0EA5E9)),
                                const SizedBox(width: 8),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text((c['namaKedai'] ?? '-').toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
                                  Text('${c['alamatKedai'] ?? '-'} · ${c['telKedai'] ?? '-'}', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                                ])),
                                GestureDetector(
                                  onTap: () async {
                                    cawangan.removeAt(ci);
                                    await _db.collection('dealers_$_ownerID').doc(d['_id']).update({'cawangan': cawangan});
                                    _snack('Cawangan dipadam');
                                    if (ctx.mounted) setS(() {});
                                  },
                                  child: const FaIcon(FontAwesomeIcons.xmark, size: 10, color: AppColors.red),
                                ),
                              ]),
                            );
                          }),
                        ],
                      ]),
                    );
                  }),
              ]),
            )),
          ]),
        );
      }),
    );
  }

  void _showDealerHistory(Map<String, dynamic> dealer) {
    final dealerId = (dealer['_id'] ?? '').toString();
    final dealerName = (dealer['namaPemilik'] ?? dealer['nama'] ?? '-').toString();
    final searchCtrl = TextEditingController();
    String filterTime = 'SEMUA';
    String searchQuery = '';
    DateTimeRange? customRange;

    // Get all sales for this dealer
    final allDealerSales = _sales.where((s) => (s['dealerId'] ?? '').toString() == dealerId).toList()
      ..sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        // Apply filters
        var filtered = List<Map<String, dynamic>>.from(allDealerSales);

        if (searchQuery.isNotEmpty) {
          filtered = filtered.where((s) =>
            (s['phoneName'] ?? '').toString().toLowerCase().contains(searchQuery) ||
            (s['siri'] ?? '').toString().toLowerCase().contains(searchQuery)
          ).toList();
        }

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        if (filterTime == 'HARI INI') {
          final ms = todayStart.millisecondsSinceEpoch;
          filtered = filtered.where((s) => ((s['timestamp'] ?? 0) as num).toInt() >= ms).toList();
        } else if (filterTime == 'MINGGU INI') {
          final ms = todayStart.subtract(Duration(days: todayStart.weekday - 1)).millisecondsSinceEpoch;
          filtered = filtered.where((s) => ((s['timestamp'] ?? 0) as num).toInt() >= ms).toList();
        } else if (filterTime == 'BULAN INI') {
          final ms = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
          filtered = filtered.where((s) => ((s['timestamp'] ?? 0) as num).toInt() >= ms).toList();
        } else if (filterTime == 'TAHUN INI') {
          final ms = DateTime(now.year, 1, 1).millisecondsSinceEpoch;
          filtered = filtered.where((s) => ((s['timestamp'] ?? 0) as num).toInt() >= ms).toList();
        } else if (filterTime == 'TARIKH' && customRange != null) {
          final startMs = customRange!.start.millisecondsSinceEpoch;
          final endMs = DateTime(customRange!.end.year, customRange!.end.month, customRange!.end.day, 23, 59, 59).millisecondsSinceEpoch;
          filtered = filtered.where((s) {
            final ts = ((s['timestamp'] ?? 0) as num).toInt();
            return ts >= startMs && ts <= endMs;
          }).toList();
        }

        final totalBelian = filtered.fold<double>(0, (s, e) => s + ((e['sellPrice'] ?? 0) as num).toDouble());

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 12, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('HISTORY BELIAN · $dealerName', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim)),
                ]),
                const SizedBox(height: 10),
                // Total belian
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const FaIcon(FontAwesomeIcons.sackDollar, size: 12, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    const Text('JUMLAH BELIAN', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('RM ${totalBelian.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    Text('(${filtered.length} resit)', style: const TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 8),
                // Search
                TextField(
                  controller: searchCtrl,
                  onChanged: (v) => setS(() => searchQuery = v.toLowerCase().trim()),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Cari model / no. siri...',
                    hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFFF59E0B)),
                    filled: true, fillColor: AppColors.bgDeep, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                  ),
                ),
                const SizedBox(height: 8),
                // Filter dropdown + calendar
                Row(children: [
                  Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: filterTime,
                        isExpanded: true,
                        dropdownColor: AppColors.bgDeep,
                        isDense: true,
                        icon: const FaIcon(FontAwesomeIcons.caretDown, size: 10, color: AppColors.textMuted),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                        items: ['SEMUA', 'HARI INI', 'MINGGU INI', 'BULAN INI', 'TAHUN INI'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                        onChanged: (v) => setS(() { filterTime = v ?? 'SEMUA'; customRange = null; }),
                      ),
                    ),
                  )),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: customRange,
                        builder: (c, child) => Theme(
                          data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFF59E0B))),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setS(() { filterTime = 'TARIKH'; customRange = picked; });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: filterTime == 'TARIKH' ? const Color(0xFFF59E0B) : AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: filterTime == 'TARIKH' ? const Color(0xFFF59E0B) : AppColors.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        FaIcon(FontAwesomeIcons.calendarDays, size: 12, color: filterTime == 'TARIKH' ? Colors.white : AppColors.textMuted),
                        if (filterTime == 'TARIKH' && customRange != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${DateFormat('dd/MM').format(customRange!.start)} - ${DateFormat('dd/MM').format(customRange!.end)}',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Sales list
            Expanded(child: filtered.isEmpty
              ? const Center(child: Text('Tiada rekod', style: TextStyle(color: AppColors.textDim, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    final siri = (s['siri'] ?? '-').toString();
                    final phoneName = (s['phoneName'] ?? '-').toString();
                    final sell = ((s['sellPrice'] ?? 0) as num).toDouble();
                    final ts = (s['timestamp'] ?? 0) as num;
                    final date = ts.toInt() > 0 ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts.toInt())) : '-';
                    final payment = (s['paymentMethod'] ?? '-').toString();
                    final term = (s['paymentTerm'] ?? '-').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderMed),
                      ),
                      child: Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 10, fontWeight: FontWeight.w900))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(phoneName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                          Text('#$siri · $date', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
                              child: Text(payment, style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 7, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
                              child: Text(term, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 7, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ])),
                        Text('RM ${sell.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w900)),
                      ]),
                    );
                  },
                ),
            ),
          ]),
        );
      }),
    );
  }

  void _showEditDealer(Map<String, dynamic> dealer, StateSetter parentSetS) {
    final namaPCtrl = TextEditingController(text: (dealer['namaPemilik'] ?? dealer['nama'] ?? '').toString());
    final telPCtrl = TextEditingController(text: (dealer['telPemilik'] ?? dealer['tel'] ?? '').toString());
    final namaKCtrl = TextEditingController(text: (dealer['namaKedai'] ?? '').toString());
    final alamatKCtrl = TextEditingController(text: (dealer['alamatKedai'] ?? dealer['alamat'] ?? '').toString());
    final telKCtrl = TextEditingController(text: (dealer['telKedai'] ?? '').toString());
    final ssmCtrl = TextEditingController(text: (dealer['noSSM'] ?? '').toString());
    String editBayaran = (dealer['bayaran'] ?? 'CASH').toString();
    String editTerm = (dealer['term'] ?? 'TUNAI').toString();
    String editWarranty = (dealer['warranty'] ?? 'TIADA').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dCtx) => Container(
        margin: const EdgeInsets.only(top: 80),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(dCtx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              const Text('EDIT DEALER', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pop(dCtx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const Divider(height: 20, color: AppColors.border),
            const _SectionLabel('MAKLUMAT PEMILIK'),
            const SizedBox(height: 6),
            _formField('Nama Pemilik', namaPCtrl, 'Nama pemilik'),
            const SizedBox(height: 6),
            _formField('No. Telefon Pemilik', telPCtrl, '01x-xxxxxxx', keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            const _SectionLabel('MAKLUMAT KEDAI'),
            const SizedBox(height: 6),
            _formField('Nama Kedai', namaKCtrl, 'Nama kedai'),
            const SizedBox(height: 6),
            _formField('Alamat Kedai', alamatKCtrl, 'Alamat kedai'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _formField('No. Telefon Kedai', telKCtrl, '0x-xxxxxxx', keyboard: TextInputType.phone)),
              const SizedBox(width: 6),
              Expanded(child: _formField('No. SSM', ssmCtrl, 'No. SSM')),
            ]),
            const SizedBox(height: 12),
            const _SectionLabel('TETAPAN JUALAN'),
            const SizedBox(height: 6),
            StatefulBuilder(builder: (_, editSetS) => Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: editBayaran, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                  items: ['CASH', 'TRANSFER'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => editSetS(() => editBayaran = v ?? 'CASH'),
                )),
              )),
              const SizedBox(width: 6),
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: editTerm, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                  items: ['TUNAI', '7 HARI', '14 HARI', '30 HARI'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => editSetS(() => editTerm = v ?? 'TUNAI'),
                )),
              )),
              const SizedBox(width: 6),
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: editWarranty, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                  items: ['TIADA', '1 BULAN', '2 BULAN', '3 BULAN'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => editSetS(() => editWarranty = v ?? 'TIADA'),
                )),
              )),
            ])),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                if (namaPCtrl.text.trim().isEmpty) {
                  _snack('Sila isi nama pemilik', err: true);
                  return;
                }
                await _db.collection('dealers_$_ownerID').doc(dealer['_id']).update({
                  'namaPemilik': namaPCtrl.text.trim().toUpperCase(),
                  'telPemilik': telPCtrl.text.trim(),
                  'namaKedai': namaKCtrl.text.trim().toUpperCase(),
                  'alamatKedai': alamatKCtrl.text.trim(),
                  'telKedai': telKCtrl.text.trim(),
                  'noSSM': ssmCtrl.text.trim().toUpperCase(),
                  'bayaran': editBayaran,
                  'term': editTerm,
                  'warranty': editWarranty,
                });
                _snack('Dealer dikemaskini');
                if (dCtx.mounted) Navigator.pop(dCtx);
                parentSetS(() {});
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white),
                  SizedBox(width: 6),
                  Text('KEMASKINI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ])),
        ),
      ),
    );
  }

  void _showAddCawangan(Map<String, dynamic> dealer, StateSetter parentSetS) {
    final namaCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    final telCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          FaIcon(FontAwesomeIcons.store, size: 14, color: Color(0xFF0EA5E9)),
          SizedBox(width: 8),
          Text('TAMBAH CAWANGAN', style: TextStyle(color: Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _formField('Nama Kedai', namaCtrl, 'cth: Ali Phone Cawangan 2'),
          const SizedBox(height: 8),
          _formField('Alamat Kedai', alamatCtrl, 'Alamat cawangan'),
          const SizedBox(height: 8),
          _formField('No. Telefon Kedai', telCtrl, '0x-xxxxxxx', keyboard: TextInputType.phone),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800))),
          ElevatedButton(
            onPressed: () async {
              if (namaCtrl.text.trim().isEmpty) {
                _snack('Sila isi nama kedai cawangan', err: true);
                return;
              }
              final cawangan = (dealer['cawangan'] is List) ? List<Map<String, dynamic>>.from((dealer['cawangan'] as List).map((c) => Map<String, dynamic>.from(c as Map))) : <Map<String, dynamic>>[];
              cawangan.add({
                'namaKedai': namaCtrl.text.trim().toUpperCase(),
                'alamatKedai': alamatCtrl.text.trim(),
                'telKedai': telCtrl.text.trim(),
              });
              await _db.collection('dealers_$_ownerID').doc(dealer['_id']).update({'cawangan': cawangan});
              _snack('Cawangan ditambah');
              if (dCtx.mounted) Navigator.pop(dCtx);
              parentSetS(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('SIMPAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showTradeInPopup() {
    final namaCtrl = TextEditingController();
    final storageCtrl = TextEditingController();
    final warnaCtrl = TextEditingController();
    final tarikhCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlgState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            FaIcon(FontAwesomeIcons.arrowRightArrowLeft, size: 14, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('TRADE-IN', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 14, fontWeight: FontWeight.w900)),
          ]),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _formField('Model Telefon', namaCtrl, 'Cth: iPhone 12 Pro Max'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _formField('Storage', storageCtrl, 'Cth: 128GB')),
                const SizedBox(width: 8),
                Expanded(child: _formField('Warna', warnaCtrl, 'Cth: Black')),
              ]),
              const SizedBox(height: 8),
              _formField('Tarikh Masuk', tarikhCtrl, 'yyyy-mm-dd'),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (namaCtrl.text.trim().isEmpty) {
                  _snack('Sila isi model telefon', err: true);
                  return;
                }
                setDlgState(() => saving = true);

                final rand = Random();
                final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
                final kod = 'PH-$code';

                await _db.collection('phone_stock_$_ownerID').add({
                  'kod': kod,
                  'nama': namaCtrl.text.trim().toUpperCase(),
                  'imei': '',
                  'warna': warnaCtrl.text.trim().toUpperCase(),
                  'storage': storageCtrl.text.trim().toUpperCase(),
                  'jual': 0,
                  'nota': 'TRADE-IN',
                  'tarikh_masuk': tarikhCtrl.text.trim(),
                  'imageUrl': '',
                  'status': 'AVAILABLE',
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'shopID': _shopID,
                });

                if (ctx.mounted) Navigator.pop(ctx);
                _snack('Trade-in berjaya masuk stok');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SIMPAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      }),
    );
  }

  void _viewInvoice(Map<String, dynamic> sale) {
    final pdfUrl = (sale['invoiceUrl'] ?? '').toString();
    final siri = (sale['siri'] ?? '-').toString();
    if (pdfUrl.isEmpty) return;
    _downloadAndOpenPDF(pdfUrl, siri);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: Color(0xFF0EA5E9), width: 2))),
        child: Row(children: [
          const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 14, color: Color(0xFF0EA5E9)),
          const SizedBox(width: 8),
          Text('${_lang.get('jt_jual_telefon')} (${_filteredSales.length})', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w900)),
          const Spacer(),
          if (_segment == 'DEALER')
            GestureDetector(
              onTap: _showDealerManager,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.bookmark, size: 10, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Text('${_savedDealers.length}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          GestureDetector(
            onTap: _showSaleForm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF0EA5E9), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white),
                const SizedBox(width: 6),
                Text(_lang.get('tambah'), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ]),
      ),

      // Segment toggle: CUSTOMER / DEALER
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          for (final seg in ['CUSTOMER', 'DEALER']) ...[
            Expanded(child: GestureDetector(
              onTap: () => setState(() { _segment = seg; _applyFilter(); }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _segment == seg
                      ? (seg == 'DEALER' ? const Color(0xFFF59E0B) : const Color(0xFF0EA5E9))
                      : AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _segment == seg
                      ? (seg == 'DEALER' ? const Color(0xFFF59E0B) : const Color(0xFF0EA5E9))
                      : AppColors.border),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(
                    seg == 'DEALER' ? FontAwesomeIcons.userTie : FontAwesomeIcons.user,
                    size: 10,
                    color: _segment == seg ? Colors.white : AppColors.textSub,
                  ),
                  const SizedBox(width: 6),
                  Text(seg, style: TextStyle(
                    color: _segment == seg ? Colors.white : AppColors.textSub,
                    fontSize: 10, fontWeight: FontWeight.w900,
                  )),
                ]),
              ),
            )),
            if (seg == 'CUSTOMER') const SizedBox(width: 8),
          ],
        ]),
      ),

      // Ringkasan jualan dipindah ke Dashboard.

      // Filter dropdown + Arkib button row
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          // Dropdown filter
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _viewMode == 'AKTIF' ? const Color(0xFF0EA5E9) : AppColors.border),
            ),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _filterTime,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textMuted),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w800),
              items: ['SEMUA', 'HARI INI', 'MINGGU INI', 'BULAN INI', 'TAHUN INI', 'CUSTOM'].map((v) => DropdownMenuItem(
                value: v,
                child: Text(
                  v == 'CUSTOM' && _filterTime == 'CUSTOM' && _customStart != null && _customEnd != null
                      ? '${DateFormat('dd/MM').format(_customStart!)} - ${DateFormat('dd/MM').format(_customEnd!)}'
                      : v,
                  style: TextStyle(color: _filterTime == v ? const Color(0xFF0EA5E9) : AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              )).toList(),
              onChanged: (v) {
                if (v == 'CUSTOM') {
                  _pickCustomDateRange();
                } else {
                  setState(() { _filterTime = v ?? 'SEMUA'; _applyFilter(); });
                }
              },
            )),
          )),
          const SizedBox(width: 8),
          // Arkib button
          GestureDetector(
            onTap: () => setState(() {
              _viewMode = _viewMode == 'ARKIB' ? 'AKTIF' : 'ARKIB';
              _applyFilter();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _viewMode == 'ARKIB' ? const Color(0xFFF59E0B) : AppColors.bgDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _viewMode == 'ARKIB' ? const Color(0xFFF59E0B) : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.boxArchive, size: 10, color: _viewMode == 'ARKIB' ? Colors.white : AppColors.textMuted),
                const SizedBox(width: 6),
                Text('ARKIB', style: TextStyle(color: _viewMode == 'ARKIB' ? Colors.white : AppColors.textSub, fontSize: 9, fontWeight: FontWeight.w900)),
                if (_archivedSales.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: _viewMode == 'ARKIB' ? Colors.white.withValues(alpha: 0.3) : const Color(0xFFF59E0B).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text('${_archivedSales.length}', style: TextStyle(color: _viewMode == 'ARKIB' ? Colors.white : const Color(0xFFF59E0B), fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ],
              ]),
            ),
          ),
          // Padam button (only show when in ARKIB view)
          if (_viewMode == 'ARKIB' || _viewMode == 'PADAM') ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() {
                _viewMode = _viewMode == 'PADAM' ? 'ARKIB' : 'PADAM';
                _applyFilter();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: _viewMode == 'PADAM' ? AppColors.red : AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _viewMode == 'PADAM' ? AppColors.red : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.trash, size: 10, color: _viewMode == 'PADAM' ? Colors.white : AppColors.textMuted),
                  if (_deletedSales.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: _viewMode == 'PADAM' ? Colors.white.withValues(alpha: 0.3) : AppColors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text('${_deletedSales.length}', style: TextStyle(color: _viewMode == 'PADAM' ? Colors.white : AppColors.red, fontSize: 8, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ]),
      ),

      // Search bar for current view
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: TextField(
          controller: _viewMode == 'AKTIF' ? _searchCtrl : _viewMode == 'ARKIB' ? _archiveSearchCtrl : _deletedSearchCtrl,
          onChanged: (_) => setState(() => _applyFilter()),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: _viewMode == 'AKTIF'
                ? 'Cari nama, no telefon, IMEI, siri...'
                : _viewMode == 'ARKIB'
                    ? 'Cari dalam arkib...'
                    : 'Cari dalam padam...',
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
            prefixIcon: Icon(Icons.search, size: 16, color: _viewMode == 'AKTIF' ? AppColors.textMuted : _viewMode == 'ARKIB' ? const Color(0xFFF59E0B) : AppColors.red),
            suffixIcon: (_viewMode == 'AKTIF' ? _searchCtrl : _viewMode == 'ARKIB' ? _archiveSearchCtrl : _deletedSearchCtrl).text.isNotEmpty
                ? GestureDetector(
                    onTap: () => setState(() {
                      if (_viewMode == 'AKTIF') { _searchCtrl.clear(); }
                      else if (_viewMode == 'ARKIB') { _archiveSearchCtrl.clear(); }
                      else { _deletedSearchCtrl.clear(); }
                      _applyFilter();
                    }),
                    child: const Icon(Icons.close, size: 14, color: AppColors.textMuted))
                : null,
            filled: true, fillColor: AppColors.bgDeep, isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ),

      // View mode indicator banner
      if (_viewMode != 'AKTIF')
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _viewMode == 'ARKIB' ? const Color(0xFFF59E0B).withValues(alpha: 0.1) : AppColors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _viewMode == 'ARKIB' ? const Color(0xFFF59E0B).withValues(alpha: 0.3) : AppColors.red.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            FaIcon(_viewMode == 'ARKIB' ? FontAwesomeIcons.boxArchive : FontAwesomeIcons.trash,
                size: 10, color: _viewMode == 'ARKIB' ? const Color(0xFFF59E0B) : AppColors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(
              _viewMode == 'ARKIB'
                  ? 'Arkib — Bill yang dibatalkan (${_filteredArchived.length})'
                  : 'Padam — Auto padam kekal selepas 30 hari (${_filteredDeleted.length})',
              style: TextStyle(color: _viewMode == 'ARKIB' ? const Color(0xFFF59E0B) : AppColors.red, fontSize: 9, fontWeight: FontWeight.w700),
            )),
            GestureDetector(
              onTap: () => setState(() { _viewMode = 'AKTIF'; _applyFilter(); }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(6)),
                child: const Text('KEMBALI', style: TextStyle(color: AppColors.textSub, fontSize: 8, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),

      // List view based on viewMode
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0EA5E9)))
            : _viewMode == 'AKTIF'
                ? _filteredSales.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        FaIcon(FontAwesomeIcons.mobileScreenButton, size: 40, color: AppColors.textDim.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(_lang.get('jt_tiada_rekod'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _filteredSales.length,
                        itemBuilder: (_, i) => _saleCard(_filteredSales[i]),
                      )
                : _viewMode == 'ARKIB'
                    ? _filteredArchived.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            FaIcon(FontAwesomeIcons.boxArchive, size: 40, color: AppColors.textDim.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            const Text('Tiada bill dalam arkib', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ]))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _filteredArchived.length,
                            itemBuilder: (_, i) => _archivedCard(_filteredArchived[i]),
                          )
                    : _filteredDeleted.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            FaIcon(FontAwesomeIcons.trash, size: 40, color: AppColors.textDim.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            const Text('Tiada bill yang dipadam', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ]))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _filteredDeleted.length,
                            itemBuilder: (_, i) => _deletedCard(_filteredDeleted[i]),
                          ),
      ),
    ]);
  }

  Widget _saleCard(Map<String, dynamic> s) {
    final sellPrice = ((s['sellPrice'] ?? 0) as num).toDouble();
    final hasInvoice = (s['invoiceUrl'] ?? '').toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Baris 1: Model + Harga jual
        Text('${s['phoneName'] ?? '-'}   RM${sellPrice.toStringAsFixed(0)}',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        const SizedBox(height: 3),
        // Baris 2: Pelanggan • Bayaran
        if ((s['custName'] ?? '').toString().isNotEmpty)
          Text('${s['custName']}${(s['custPhone'] ?? '').toString().isNotEmpty ? '  •  ${s['custPhone']}' : ''}  •  ${s['paymentMethod'] ?? 'CASH'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 1),
        const SizedBox(height: 3),
        // Baris 3: Tarikh • Staff | Cancel + No Siri
        Row(children: [
          Expanded(child: Text('${_fmtDate(s['timestamp'])}  •  ${s['staffName'] ?? '-'}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 1)),
          GestureDetector(
            onTap: () => _cancelBill(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.red, fontSize: 7, fontWeight: FontWeight.w900)),
            ),
          ),
          GestureDetector(
            onTap: () => _showSalePrintPopup(s, hasInvoice),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.3)),
              ),
              child: Text('#${s['siri'] ?? '-'}', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 8, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _archivedCard(Map<String, dynamic> s) {
    final sellPrice = ((s['sellPrice'] ?? 0) as num).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s['phoneName'] ?? '-'}   RM${sellPrice.toStringAsFixed(0)}',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        const SizedBox(height: 3),
        if ((s['custName'] ?? '').toString().isNotEmpty)
          Text('${s['custName']}${(s['custPhone'] ?? '').toString().isNotEmpty ? '  •  ${s['custPhone']}' : ''}  •  ${s['paymentMethod'] ?? 'CASH'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 1),
        const SizedBox(height: 3),
        Row(children: [
          Expanded(child: Text('${_fmtDate(s['timestamp'])}  •  ${s['staffName'] ?? '-'}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 1)),
          GestureDetector(
            onTap: () => _restoreFromArchive(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.arrowRotateLeft, size: 7, color: AppColors.green),
                SizedBox(width: 3),
                Text('PULIH', style: TextStyle(color: AppColors.green, fontSize: 7, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
          GestureDetector(
            onTap: () => _softDelete(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.trash, size: 7, color: AppColors.red),
                SizedBox(width: 3),
                Text('PADAM', style: TextStyle(color: AppColors.red, fontSize: 7, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _deletedCard(Map<String, dynamic> s) {
    final sellPrice = ((s['sellPrice'] ?? 0) as num).toDouble();
    final remaining = _remainingDays(s);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${s['phoneName'] ?? '-'}   RM${sellPrice.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis, maxLines: 1)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text('$remaining lagi', style: const TextStyle(color: AppColors.red, fontSize: 7, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 3),
        if ((s['custName'] ?? '').toString().isNotEmpty)
          Text('${s['custName']}${(s['custPhone'] ?? '').toString().isNotEmpty ? '  •  ${s['custPhone']}' : ''}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 1),
        const SizedBox(height: 3),
        Row(children: [
          Expanded(child: Text('${_fmtDate(s['timestamp'])}  •  ${s['staffName'] ?? '-'}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 1)),
          GestureDetector(
            onTap: () => _recoverFromDeleted(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.arrowRotateLeft, size: 7, color: AppColors.green),
                SizedBox(width: 3),
                Text('RECOVER', style: TextStyle(color: AppColors.green, fontSize: 7, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
          GestureDetector(
            onTap: () => _permanentDelete(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.ban, size: 7, color: AppColors.red),
                SizedBox(width: 3),
                Text('PADAM KEKAL', style: TextStyle(color: AppColors.red, fontSize: 7, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  void _showSalePrintPopup(Map<String, dynamic> s, bool hasInvoice) {
    final siri = s['siri'] ?? '-';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.print, size: 14, color: Color(0xFF0EA5E9)),
            const SizedBox(width: 8),
            Text('CETAK #$siri', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          // Generate / View Invoice A4
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              if (hasInvoice) {
                _viewInvoice(s);
              } else {
                _generateInvoice(s);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Center(child: FaIcon(FontAwesomeIcons.filePdf, size: 14, color: AppColors.green))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(hasInvoice ? 'BUKA INVOICE A4' : 'GENERATE INVOICE A4', style: const TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w900)),
                  Text(hasInvoice ? 'Invoice sedia ada' : 'Jana invoice PDF baru', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                ])),
              ]),
            ),
          ),
          // WhatsApp (only if has invoice)
          if (hasInvoice)
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                final pdfUrl = (s['invoiceUrl'] ?? '').toString();
                final msg = Uri.encodeComponent('INVOICE Jualan Telefon #$siri\n$pdfUrl');
                launchUrl(Uri.parse('https://wa.me/?text=$msg'), mode: LaunchMode.externalApplication);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF25D366).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: FaIcon(FontAwesomeIcons.whatsapp, size: 14, color: Color(0xFF25D366)))),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('HANTAR WHATSAPP', style: TextStyle(color: Color(0xFF25D366), fontSize: 11, fontWeight: FontWeight.w900)),
                    Text('Hantar link invoice ke pelanggan', style: TextStyle(color: AppColors.textDim, fontSize: 9)),
                  ])),
                ]),
              ),
            ),
        ]),
      ),
    );
  }


  Widget _formField(String label, TextEditingController ctrl, String hint, {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800),
        hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
        filled: true, fillColor: AppColors.bg, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderMed)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderMed)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0EA5E9))),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1));
  }
}