import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';
import '../../services/app_language.dart';
import '../../utils/pdf_url_helper.dart';

class KewanganScreen extends StatefulWidget {
  final Map<String, dynamic>? enabledModules;
  const KewanganScreen({super.key, this.enabledModules});

  @override
  State<KewanganScreen> createState() => _KewanganScreenState();
}

class _KewanganScreenState extends State<KewanganScreen> {
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  final _printer = PrinterService();
  final _lang = AppLanguage();

  String _ownerID = 'admin';
  String _shopID = 'MAIN';
  String _filterTime = 'TODAY';
  String _filterSort = 'DESC';
  int _rowsPerPage = 30;
  int _currentPage = 1;

  // Segment
  int _segment = 0; // 0 = Kewangan, 1 = Jualan Telefon
  String _phoneSaleType = 'CUSTOMER'; // CUSTOMER / DEALER
  List<Map<String, dynamic>> _phoneSales = [];
  List<Map<String, dynamic>> _filteredPhoneSales = [];

  DateTime? _customStart;
  DateTime? _customEnd;

  List<Map<String, dynamic>> _allRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  final List<StreamSubscription> _subs = [];
  final Map<String, List<Map<String, dynamic>>> _recordSources = {};

  final _expPerkaraCtrl = TextEditingController();
  final _expAmountCtrl = TextEditingController();
  String _expStaff = '';
  List<String> _staffList = [];

  Map<String, dynamic> _branchSettings = {};
  bool _isLoading = true;
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _searchCtrl.dispose();
    _expPerkaraCtrl.dispose();
    _expAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase();
      _shopID = branch.split('@')[1].toUpperCase();
    }
    await _loadBranchSettings();
    _listenAll();
  }

  Future<void> _loadBranchSettings() async {
    final snap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
    if (snap.exists) {
      _branchSettings = snap.data() ?? {};
      final staffList = _branchSettings['staffList'];
      if (staffList is List) {
        _staffList = staffList
            .map(
              (s) =>
                  s is String ? s : (s['name'] ?? s['nama'] ?? '').toString(),
            )
            .where((s) => s.isNotEmpty)
            .toList();
        if (_staffList.isNotEmpty) _expStaff = _staffList.first;
      }
    }
    if (mounted) setState(() {});
  }

  void _listenAll() {
    _subs.add(
      _db.collection('repairs_$_ownerID').snapshots().listen((snap) {
        final records = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
          if ((d['payment_status'] ?? '').toString().toUpperCase() != 'PAID') {
            continue;
          }
          final nama = (d['nama'] ?? '').toString().toUpperCase();
          final jenis = (d['jenis_servis'] ?? '').toString().toUpperCase();
          if (nama == 'JUALAN PANTAS' || jenis == 'JUALAN') continue;
          records.add({
            'docId': doc.id,
            'siri': d['siri'] ?? doc.id,
            'jenis': 'RETAIL',
            'jenisLabel': 'SALES REPAIR',
            'nama': d['nama'] ?? '-',
            'tel': d['tel'] ?? '-',
            'item': d['model'] ?? d['kerosakan'] ?? '-',
            'jumlah': double.tryParse(d['total']?.toString() ?? '0') ?? 0,
            'cara': d['cara_bayaran'] ?? 'CASH',
            'staff': d['staff_repair'] ?? d['staff_terima'] ?? '-',
            'timestamp': _dapatkanMasaSah(d['paid_at'] ?? d['timestamp']),
            'isExpense': false,
            'rawData': d,
            'collection': 'repairs_$_ownerID',
          });
        }
        _mergeRecords('REPAIR', records);
      }),
    );

    final receiverCode = '$_ownerID@$_shopID'.toLowerCase();
    _subs.add(
      _db
          .collection('collab_global_network')
          .where('receiver', isEqualTo: receiverCode)
          .snapshots()
          .listen((snap) {
            final records = <Map<String, dynamic>>[];
            for (final doc in snap.docs) {
              final d = doc.data();
              if ((d['payment_status'] ?? '').toString().toUpperCase() !=
                  'PAID') {
                continue;
              }
              records.add({
                'docId': doc.id,
                'siri': d['siri'] ?? doc.id,
                'jenis': 'PRO_ONLINE',
                'jenisLabel': 'PRO DEALER',
                'nama': d['namaCust'] ?? d['nama'] ?? '-',
                'tel': d['telCust'] ?? d['tel'] ?? '-',
                'item': d['model'] ?? d['kerosakan'] ?? '-',
                'jumlah': double.tryParse(d['total']?.toString() ?? '0') ?? 0,
                'cara': d['cara_bayaran'] ?? 'ONLINE',
                'staff': d['staff_repair'] ?? d['sender'] ?? '-',
                'timestamp': _dapatkanMasaSah(d['timestamp']),
                'isExpense': false,
                'rawData': d,
                'collection': 'collab_global_network',
              });
            }
            _mergeRecords('COLLAB', records);
          }),
    );

    _subs.add(
      _db.collection('pro_walkin_$_ownerID').snapshots().listen((snap) {
        final records = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
          if ((d['payment_status'] ?? '').toString().toUpperCase() != 'PAID') {
            continue;
          }
          records.add({
            'docId': doc.id,
            'siri': d['siri'] ?? doc.id,
            'jenis': 'PRO_OFFLINE',
            'jenisLabel': 'PRO DEALER',
            'nama': d['namaCust'] ?? d['nama'] ?? '-',
            'tel': d['telCust'] ?? d['tel'] ?? '-',
            'item': d['model'] ?? d['kerosakan'] ?? '-',
            'jumlah': double.tryParse(d['total']?.toString() ?? '0') ?? 0,
            'cara': d['cara_bayaran'] ?? 'CASH',
            'staff': d['staff_repair'] ?? d['staff_terima'] ?? '-',
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'isExpense': false,
            'rawData': d,
            'collection': 'pro_walkin_$_ownerID',
          });
        }
        _mergeRecords('PRO_WALKIN', records);
      }),
    );

    _subs.add(
      _db.collection('expenses_$_ownerID').snapshots().listen((snap) {
        final records = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
          if (d['archived'] == true) continue;
          records.add({
            'docId': doc.id,
            'siri': doc.id,
            'jenis': 'EXPENSE',
            'jenisLabel': 'DUIT KELUAR',
            'nama': d['perkara'] ?? '-',
            'tel': '-',
            'item': d['perkara'] ?? '-',
            'jumlah':
                (d['jumlah'] as num?)?.toDouble() ??
                (d['amaun'] as num?)?.toDouble() ??
                0,
            'cara': '-',
            'staff': d['staff'] ?? d['staf'] ?? '-',
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'isExpense': true,
            'rawData': d,
            'collection': 'expenses_$_ownerID',
          });
        }
        _mergeRecords('EXPENSE', records);
      }),
    );

    _subs.add(
      _db.collection('jualan_pantas_$_ownerID').snapshots().listen((snap) {
        final records = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
          if ((d['payment_status'] ?? '').toString().toUpperCase() != 'PAID') {
            continue;
          }
          final nama = (d['nama'] ?? '').toString().toUpperCase();
          if (nama == 'JUALAN TELEFON') continue;
          records.add({
            'docId': doc.id,
            'siri': d['siri'] ?? doc.id,
            'jenis': 'PANTAS',
            'jenisLabel': 'QUICK SALES',
            'nama': d['nama'] ?? 'QUICK SALES',
            'tel': d['tel'] ?? '-',
            'item': d['item'] ?? d['model'] ?? d['perkara'] ?? '-',
            'jumlah': double.tryParse(d['total']?.toString() ?? '0') ?? 0,
            'cara': d['cara_bayaran'] ?? 'CASH',
            'staff': d['staff'] ?? d['staff_terima'] ?? '-',
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'isExpense': false,
            'rawData': d,
            'collection': 'jualan_pantas_$_ownerID',
          });
        }
        _mergeRecords('PANTAS', records);
      }),
    );

    // Phone sales listener
    _subs.add(
      _db.collection('phone_sales_$_ownerID').snapshots().listen((snap) {
        final records = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != _shopID) continue;
          records.add({
            'docId': doc.id,
            'kod': d['kod'] ?? '-',
            'nama': d['nama'] ?? '-',
            'imei': d['imei'] ?? '-',
            'warna': d['warna'] ?? '-',
            'storage': d['storage'] ?? '-',
            'jual': (d['jual'] as num?)?.toDouble() ?? 0,
            'imageUrl': d['imageUrl'] ?? '',
            'siri': d['siri'] ?? '-',
            'staffJual': d['staffJual'] ?? d['staffName'] ?? '-',
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'saleType': (d['saleType'] ?? 'CUSTOMER').toString().toUpperCase(),
            'custName': d['custName'] ?? '-',
            'custPhone': d['custPhone'] ?? '-',
            'dealerName': d['dealerName'] ?? '',
            'dealerKedai': d['dealerKedai'] ?? '',
          });
        }
        records.sort(
          (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0),
        );
        if (mounted)
          setState(() {
            _phoneSales = records;
            _applyPhoneSalesFilter();
          });
      }),
    );
  }

  void _applyPhoneSalesFilter() {
    var data = List<Map<String, dynamic>>.from(_phoneSales);

    // Filter by saleType (CUSTOMER / DEALER)
    data = data.where((d) => (d['saleType'] ?? 'CUSTOMER') == _phoneSaleType).toList();

    final query = _searchCtrl.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      data = data
          .where(
            (d) =>
                (d['nama'] ?? '').toString().toLowerCase().contains(query) ||
                (d['kod'] ?? '').toString().toLowerCase().contains(query) ||
                (d['imei'] ?? '').toString().toLowerCase().contains(query) ||
                (d['staffJual'] ?? '').toString().toLowerCase().contains(
                  query,
                ) ||
                (d['siri'] ?? '').toString().toLowerCase().contains(query) ||
                (d['custName'] ?? '').toString().toLowerCase().contains(query) ||
                (d['dealerName'] ?? '').toString().toLowerCase().contains(query),
          )
          .toList();
    }
    if (_filterTime == 'CUSTOM' && _customStart != null && _customEnd != null) {
      final s = _customStart!.millisecondsSinceEpoch;
      final e = _customEnd!
          .add(const Duration(hours: 23, minutes: 59, seconds: 59))
          .millisecondsSinceEpoch;
      data = data.where((d) {
        final ts = d['timestamp'] ?? 0;
        return ts >= s && ts <= e;
      }).toList();
    } else if (_filterTime != 'ALL') {
      final range = _getFilteredTimeRange(_filterTime);
      data = data.where((d) {
        final ts = d['timestamp'] ?? 0;
        return ts >= range.$1 && ts <= range.$2;
      }).toList();
    }
    _filteredPhoneSales = data;
  }

  int _dapatkanMasaSah(dynamic ts) {
    if (ts == null) return 0;
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is int) {
      if (ts > 0 && ts < 10000000000) return ts * 1000;
      return ts;
    }
    if (ts is double) return ts.toInt();
    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
      final asNum = int.tryParse(ts) ?? double.tryParse(ts)?.toInt();
      if (asNum != null) return _dapatkanMasaSah(asNum);
    }
    return 0;
  }

  void _mergeRecords(String source, List<Map<String, dynamic>> records) {
    _recordSources[source] = records;
    final all = <Map<String, dynamic>>[];
    for (final list in _recordSources.values) {
      all.addAll(list);
    }
    all.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    if (mounted) {
      setState(() {
        _allRecords = all;
        _hasLoadedOnce = true;
        _isLoading = false;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    var data = List<Map<String, dynamic>>.from(_allRecords);
    final query = _searchCtrl.text.toLowerCase().trim();

    if (query.isNotEmpty) {
      data = data.where((d) {
        return (d['nama'] ?? '').toString().toLowerCase().contains(query) ||
            (d['siri'] ?? '').toString().toLowerCase().contains(query) ||
            (d['item'] ?? '').toString().toLowerCase().contains(query) ||
            (d['staff'] ?? '').toString().toLowerCase().contains(query) ||
            (d['tel'] ?? '').toString().toLowerCase().contains(query) ||
            (d['jenisLabel'] ?? '').toString().toLowerCase().contains(query);
      }).toList();
    }

    if (_filterTime == 'CUSTOM' && _customStart != null && _customEnd != null) {
      final s = _customStart!.millisecondsSinceEpoch;
      final e = _customEnd!
          .add(const Duration(hours: 23, minutes: 59, seconds: 59))
          .millisecondsSinceEpoch;
      data = data.where((d) {
        final ts = d['timestamp'] ?? 0;
        return ts >= s && ts <= e;
      }).toList();
    } else if (_filterTime != 'ALL') {
      final range = _getFilteredTimeRange(_filterTime);
      data = data.where((d) {
        final ts = d['timestamp'] ?? 0;
        return ts >= range.$1 && ts <= range.$2;
      }).toList();
    }

    switch (_filterSort) {
      case 'ASC':
        data.sort(
          (a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0),
        );
        break;
      case 'SALES':
        data = data.where((d) => d['isExpense'] != true).toList();
        data.sort(
          (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0),
        );
        break;
      case 'EXPENSE':
        data = data.where((d) => d['isExpense'] == true).toList();
        data.sort(
          (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0),
        );
        break;
      default:
        data.sort(
          (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0),
        );
    }

    _filteredRecords = data;
    _currentPage = 1;
    _applyPhoneSalesFilter();
  }

  (int, int) _getFilteredTimeRange(String period) {
    final now = DateTime.now();
    DateTime start;
    switch (period) {
      case 'TODAY':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'WEEK':
        start = now.subtract(Duration(days: now.weekday % 7));
        start = DateTime(start.year, start.month, start.day);
        break;
      case 'MONTH':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'YEAR':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = DateTime(2020);
    }
    return (start.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  }

  int get _totalPages =>
      (_filteredRecords.length / _rowsPerPage).ceil().clamp(1, 99999);

  List<Map<String, dynamic>> get _pageData {
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, _filteredRecords.length);
    if (start >= _filteredRecords.length) return [];
    return _filteredRecords.sublist(start, end);
  }

  double get _totalJualanToday {
    final range = _getFilteredTimeRange('TODAY');
    return _allRecords
        .where(
          (d) =>
              d['isExpense'] != true &&
              (d['timestamp'] ?? 0) >= range.$1 &&
              (d['timestamp'] ?? 0) <= range.$2,
        )
        .fold(0.0, (s, d) => s + ((d['jumlah'] ?? 0) as num).toDouble());
  }

  double get _totalExpenseToday {
    final range = _getFilteredTimeRange('TODAY');
    return _allRecords
        .where(
          (d) =>
              d['isExpense'] == true &&
              (d['timestamp'] ?? 0) >= range.$1 &&
              (d['timestamp'] ?? 0) <= range.$2,
        )
        .fold(0.0, (s, d) => s + ((d['jumlah'] ?? 0) as num).toDouble());
  }

  double get _totalJualanPaparan {
    return _filteredRecords
        .where((d) => d['isExpense'] != true)
        .fold(0.0, (s, d) => s + ((d['jumlah'] ?? 0) as num).toDouble());
  }

  double get _totalExpensePaparan {
    return _filteredRecords
        .where((d) => d['isExpense'] == true)
        .fold(0.0, (s, d) => s + ((d['jumlah'] ?? 0) as num).toDouble());
  }

  String _formatDate(dynamic ts) {
    if (ts == null || ts == 0) return '-';
    if (ts is int) {
      return DateFormat(
        'dd/MM/yy HH:mm',
      ).format(DateTime.fromMillisecondsSinceEpoch(ts));
    }
    return ts.toString();
  }

  String _formatRM(double v) => 'RM ${v.toStringAsFixed(2)}';

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        backgroundColor: err ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool get _phoneEnabled {
    final m = widget.enabledModules;
    if (m == null || m.isEmpty) return true;
    return m['JualTelefon'] != false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_phoneEnabled && _segment == 1) _segment = 0;
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          if (_phoneEnabled) _buildSegmentToggle(),
          _buildFilterBar(),
          Expanded(
            child: _segment == 0 ? _buildRecordList() : _buildPhoneSalesList(),
          ),
          if (_segment == 0) _buildSummaryBar(),
          if (_segment == 1) _buildPhoneSalesSummary(),
        ],
      ),
    );
  }

  Widget _buildSegmentToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.card,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _segment = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _segment == 0
                          ? AppColors.textPrimary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _segment == 0
                            ? AppColors.textPrimary
                            : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _lang.get('kw_repair_aksesori'),
                        style: TextStyle(
                          color: _segment == 0 ? Colors.white : AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _segment = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _segment == 1
                          ? AppColors.textPrimary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _segment == 1
                            ? AppColors.textPrimary
                            : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _lang.get('kw_jualan_telefon'),
                        style: TextStyle(
                          color: _segment == 1 ? Colors.white : AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_segment == 1) ...[
            const SizedBox(height: 6),
            _buildPhoneSaleTypeToggle(),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneSaleTypeToggle() {
    return Row(
      children: [
        for (final type in ['CUSTOMER', 'DEALER']) ...[
          if (type == 'DEALER') const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _phoneSaleType = type;
                _applyPhoneSalesFilter();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _phoneSaleType == type
                      ? (type == 'DEALER'
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF0EA5E9))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _phoneSaleType == type
                        ? (type == 'DEALER'
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF0EA5E9))
                        : AppColors.border,
                  ),
                ),
                child: Center(
                  child: Text(
                    type,
                    style: TextStyle(
                      color: _phoneSaleType == type
                          ? Colors.white
                          : AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      decoration: const BoxDecoration(color: AppColors.card),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.wallet,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _lang.get('kw_title'),
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (_segment == 0)
            GestureDetector(
              onTap: _showExpenseModal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.minus,
                      size: 10,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _lang.get('kw_duit_keluar'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.borderMed)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(_applyFilters),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: _lang.get('kw_cari_hint'),
              hintStyle: const TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.textMuted,
                size: 18,
              ),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => setState(() {
                        _searchCtrl.clear();
                        _applyFilters();
                      }),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textDim,
                        size: 16,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.bgDeep,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _filterPopup(
                  _lang.get('kw_masa'),
                  _filterTime,
                  {
                    'ALL': _lang.get('kw_semua'),
                    'TODAY': _lang.get('kw_hari_ini'),
                    'WEEK': _lang.get('kw_minggu_ini'),
                    'MONTH': _lang.get('kw_bulan_ini'),
                    'YEAR': _lang.get('kw_tahun_ini'),
                    'CUSTOM': _lang.get('kw_pilih_tarikh'),
                  },
                  (v) {
                    if (v == 'CUSTOM') {
                      _showCustomDatePicker();
                    } else {
                      setState(() {
                        _filterTime = v;
                        _customStart = null;
                        _customEnd = null;
                        _applyFilters();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _filterPopup(
                  _lang.get('kw_susun'),
                  _filterSort,
                  {
                    'DESC': _lang.get('kw_terbaru'),
                    'ASC': _lang.get('kw_terdahulu'),
                    'SALES': _lang.get('kw_jualan_sahaja'),
                    'EXPENSE': _lang.get('kw_duit_keluar_filter'),
                  },
                  (v) => setState(() {
                    _filterSort = v;
                    _applyFilters();
                  }),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _filterPopup(
                  _lang.get('kw_baris'),
                  _rowsPerPage.toString(),
                  {'10': '10', '30': '30', '50': '50', '100': '100'},
                  (v) => setState(() {
                    _rowsPerPage = int.parse(v);
                    _currentPage = 1;
                  }),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _downloadCSV,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderMed),
                  ),
                  child: const FaIcon(
                    FontAwesomeIcons.fileExcel,
                    size: 12,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          if (_filterTime == 'CUSTOM' &&
              _customStart != null &&
              _customEnd != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.calendarDay,
                      size: 10,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${DateFormat('dd/MM/yy').format(_customStart!)} - ${DateFormat('dd/MM/yy').format(_customEnd!)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() {
                        _filterTime = 'TODAY';
                        _customStart = null;
                        _customEnd = null;
                        _applyFilters();
                      }),
                      child: const FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 10,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterPopup(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderMed),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                options[selected] ?? selected,
                style: const TextStyle(
                  color: AppColors.textSub,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const FaIcon(
              FontAwesomeIcons.chevronDown,
              size: 8,
              color: AppColors.textDim,
            ),
          ],
        ),
      ),
      itemBuilder: (_) => options.entries
          .map(
            (e) => PopupMenuItem(
              value: e.key,
              child: Text(
                e.value,
                style: TextStyle(
                  color: e.key == selected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _customStart ?? now.subtract(const Duration(days: 7)),
        end: _customEnd ?? now,
      ),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.black,
            surface: Colors.white,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _filterTime = 'CUSTOM';
        _customStart = picked.start;
        _customEnd = picked.end;
        _applyFilters();
      });
    }
  }

  Widget _buildRecordList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_allRecords.isEmpty && !_hasLoadedOnce) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              _lang.get('kw_memuatkan'),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_filteredRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(
              FontAwesomeIcons.folderOpen,
              size: 40,
              color: AppColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              _lang.get('kw_tiada_rekod'),
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pageData.length,
      itemBuilder: (_, i) => _buildRecordCard(_pageData[i]),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> rec) {
    final isExpense = rec['isExpense'] == true;
    final jumlah = ((rec['jumlah'] ?? 0) as num).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 44,
            decoration: BoxDecoration(
              color: isExpense ? AppColors.red : AppColors.textPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Baris 1: Nama + No Siri | RM
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${rec['nama'] ?? '-'}  #${rec['siri']}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      '${isExpense ? '-' : '+'}RM ${jumlah.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isExpense
                            ? AppColors.red
                            : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Baris 2: Item (jarak sikit)
                if (!isExpense)
                  Text(
                    rec['item'] ?? '-',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                const SizedBox(height: 4),
                // Baris 3: Tarikh • Staff | Cetak
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatDate(rec['timestamp'])}  •  ${rec['staff'] ?? '-'}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (isExpense)
                      GestureDetector(
                        onTap: () => _arkibExpense(rec),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: AppColors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.boxArchive,
                                size: 9,
                                color: AppColors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _lang.get('kw_arkib'),
                                style: const TextStyle(
                                  color: AppColors.orange,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!isExpense)
                      GestureDetector(
                        onTap: () => _showPrintOptionsModal(rec),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: AppColors.blue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.print,
                                size: 9,
                                color: AppColors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _lang.get('kw_cetak'),
                                style: const TextStyle(
                                  color: AppColors.blue,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── PHONE SALES LIST ───
  Widget _buildPhoneSalesList() {
    if (_filteredPhoneSales.isEmpty) {
      return Center(
        child: Text(
          _lang.get('kw_tiada_jualan_telefon'),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _filteredPhoneSales.length,
      itemBuilder: (_, i) => _buildPhoneSaleCard(_filteredPhoneSales[i]),
    );
  }

  Widget _buildPhoneSaleCard(Map<String, dynamic> rec) {
    final harga = (rec['jual'] as num?)?.toDouble() ?? 0;
    final isDealer = _phoneSaleType == 'DEALER';
    final buyerName = isDealer
        ? (rec['dealerName'] ?? '-')
        : (rec['custName'] ?? '-');
    final buyerSub = isDealer
        ? (rec['dealerKedai'] ?? '')
        : (rec['custPhone'] ?? '-');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris 1: Model + Harga
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${rec['nama'] ?? '-'}   RM${harga.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Baris 2: Buyer info
          Text(
            '$buyerName${buyerSub.isNotEmpty ? '  •  $buyerSub' : ''}',
            style: TextStyle(
              color: isDealer ? const Color(0xFFF59E0B) : const Color(0xFF0EA5E9),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 3),
          // Baris 3: Warna • Storage • IMEI
          Text(
            '${rec['warna'] ?? '-'}  •  ${rec['storage'] ?? '-'}  •  IMEI: ${rec['imei'] ?? '-'}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 3),
          // Baris 4: Tarikh • Staff • No Siri
          Text(
            '${_formatDate(rec['timestamp'])}  •  ${rec['staffJual'] ?? '-'}  •  No: ${rec['siri'] ?? '-'}',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSalesSummary() {
    final total = _filteredPhoneSales.fold(
      0.0,
      (s, d) => s + ((d['jual'] ?? 0) as num).toDouble(),
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.borderMed)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_filteredPhoneSales.length} ${_lang.get('kw_unit')}  •  $_phoneSaleType',
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'RM ${total.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.borderMed)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _summaryChip(
                    _lang.get('kw_jual'),
                    _formatRM(_totalJualanToday),
                    AppColors.green,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _summaryChip(
                    _lang.get('kw_keluar'),
                    _formatRM(_totalExpenseToday),
                    AppColors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _summaryChip(
                    _lang.get('kw_jual_p'),
                    _formatRM(_totalJualanPaparan),
                    AppColors.blue,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _summaryChip(
                    _lang.get('kw_klr_p'),
                    _formatRM(_totalExpensePaparan),
                    AppColors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredRecords.length} ${_lang.get('kw_rekod')}',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const FaIcon(
                        FontAwesomeIcons.anglesLeft,
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _currentPage > 1
                          ? () => setState(() => _currentPage = 1)
                          : null,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28),
                    ),
                    IconButton(
                      icon: const FaIcon(
                        FontAwesomeIcons.chevronLeft,
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _currentPage > 1
                          ? () => setState(() => _currentPage--)
                          : null,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_currentPage / $_totalPages',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const FaIcon(
                        FontAwesomeIcons.chevronRight,
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _currentPage < _totalPages
                          ? () => setState(() => _currentPage++)
                          : null,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28),
                    ),
                    IconButton(
                      icon: const FaIcon(
                        FontAwesomeIcons.anglesRight,
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _currentPage < _totalPages
                          ? () => setState(() => _currentPage = _totalPages)
                          : null,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 7,
              fontWeight: FontWeight.w900,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  void _arkibExpense(Map<String, dynamic> rec) {
    final docId = rec['docId']?.toString() ?? '';
    if (docId.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const FaIcon(FontAwesomeIcons.boxArchive, size: 16, color: AppColors.orange),
            const SizedBox(width: 8),
            Text(
              _lang.get('kw_arkib'),
              style: const TextStyle(
                color: AppColors.orange,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Text(
          _lang.get('kw_arkib_confirm'),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _lang.get('batal'),
              style: const TextStyle(color: AppColors.textDim),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _db
                    .collection('expenses_$_ownerID')
                    .doc(docId)
                    .update({'archived': true});
                _snack(_lang.get('kw_arkib_ok'));
              } catch (e) {
                _snack('${_lang.get('kw_arkib_gagal')}: $e', err: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(
              _lang.get('kw_arkib'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  void _showExpenseModal() {
    _expPerkaraCtrl.clear();
    _expAmountCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.arrowTrendDown,
                        size: 14,
                        color: AppColors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _lang.get('kw_rekod_duit_keluar'),
                        style: TextStyle(
                          color: AppColors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const FaIcon(
                      FontAwesomeIcons.xmark,
                      size: 16,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ),
              const Divider(color: AppColors.borderMed, height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.clock,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                      style: const TextStyle(
                        color: AppColors.textSub,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _expLabel(_lang.get('kw_perkara')),
              _expInput(_expPerkaraCtrl, _lang.get('kw_cth_spare')),
              const SizedBox(height: 12),
              _expLabel(_lang.get('kw_jumlah_rm')),
              _expInput(
                _expAmountCtrl,
                '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              if (_staffList.isNotEmpty) ...[
                _expLabel(_lang.get('kw_staff')),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _staffList.contains(_expStaff)
                          ? _expStaff
                          : _staffList.first,
                      isExpanded: true,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      items: _staffList
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) => setModalState(() => _expStaff = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final perkara = _expPerkaraCtrl.text.trim();
                    final jumlah = double.tryParse(_expAmountCtrl.text) ?? 0;
                    if (perkara.isEmpty || jumlah <= 0) {
                      _snack(_lang.get('kw_sila_isi'), err: true);
                      return;
                    }
                    await _db.collection('expenses_$_ownerID').add({
                      'perkara': perkara.toUpperCase(),
                      'jumlah': jumlah,
                      'amaun': jumlah,
                      'staf': _expStaff,
                      'staff': _expStaff,
                      'shopID': _shopID,
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                      'tarikh': DateFormat(
                        "yyyy-MM-dd'T'HH:mm",
                      ).format(DateTime.now()),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack(
                      '${_lang.get('kw_berjaya_simpan')} RM${jumlah.toStringAsFixed(2)}',
                    );
                  },
                  icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
                  label: Text(_lang.get('simpan')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textSub,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  Widget _expInput(
    TextEditingController ctrl,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        filled: true,
        fillColor: AppColors.bgDeep,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }

  void _showPrintOptionsModal(Map<String, dynamic> rec) {
    final siri = rec['siri'] ?? '-';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.print,
                      size: 14,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_lang.get('kw_cetak_siri')} #$siri',
                      style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(
                    FontAwesomeIcons.xmark,
                    size: 16,
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
            const Divider(color: AppColors.borderMed, height: 24),
            _printOptionBtn(
              _lang.get('kw_cetak_80mm_bt'),
              _lang.get('kw_cetak_resit_desc'),
              FontAwesomeIcons.bluetooth,
              AppColors.blue,
              () {
                Navigator.pop(ctx);
                _print80mm(rec);
              },
            ),
            const SizedBox(height: 8),
            _printOptionBtn(
              _lang.get('kw_jana_pdf_a4'),
              _lang.get('kw_jana_pdf_desc'),
              FontAwesomeIcons.filePdf,
              AppColors.green,
              () {
                Navigator.pop(ctx);
                _generateSalesPDF(rec);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _printOptionBtn(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: FaIcon(icon, size: 18, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _print80mm(Map<String, dynamic> rec) async {
    _snack(_lang.get('kw_sambung_printer'));

    const lebar = 48;
    final garis = '${'=' * 48}\n';
    final garis2 = '${'-' * 48}\n';
    const escInit = '\x1B\x40';
    const escCenter = '\x1B\x61\x01';
    const escLeft = '\x1B\x61\x00';
    const escBoldOn = '\x1B\x45\x01';
    const escBoldOff = '\x1B\x45\x00';
    const escDblHeight = '\x1B\x21\x10';
    const escDblSize = '\x1B\x21\x30';
    const escNormal = '\x1B\x21\x00';

    String tengah(String t, [int w = lebar]) {
      int pad = ((w - t.length) / 2).floor().clamp(0, w);
      return '${' ' * pad}$t\n';
    }

    String baris(String label, String nilai, [int lebarLabel = 18]) {
      final l = label.padRight(lebarLabel);
      final gap = lebar - l.length - nilai.length;
      return '$l${' ' * (gap > 0 ? gap : 1)}$nilai\n';
    }

    final s = _branchSettings;
    final namaKedai = (s['shopName'] ?? s['namaKedai'] ?? 'RMS PRO')
        .toString()
        .toUpperCase();
    final telKedai = s['phone'] ?? s['ownerContact'] ?? '-';
    final alamat = s['address'] ?? s['alamat'] ?? '';

    final siri = rec['siri'] ?? '-';
    final jenisLabel = rec['jenisLabel'] ?? '-';
    final jumlah = ((rec['jumlah'] ?? 0) as num).toDouble();
    final tsMs = rec['timestamp'] ?? 0;
    final tarikhStr = tsMs > 0
        ? DateFormat(
            'dd/MM/yyyy',
          ).format(DateTime.fromMillisecondsSinceEpoch(tsMs))
        : '-';
    final masaStr = tsMs > 0
        ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(tsMs))
        : '-';

    var r = escInit;
    r += escCenter + escDblSize + escBoldOn;
    r += tengah(
      namaKedai.length > 24 ? namaKedai.substring(0, 24) : namaKedai,
      (lebar / 2).floor(),
    );
    r += escNormal + escBoldOff;
    if (alamat.isNotEmpty) {
      r += tengah(alamat.length > lebar ? alamat.substring(0, lebar) : alamat);
    }
    r += tengah('Tel: $telKedai');
    r += garis;

    r += escCenter + escDblHeight + escBoldOn;
    r += tengah(_lang.get('kw_resit_jualan'));
    r += escNormal + escBoldOff + escLeft;
    r += garis2;
    r += baris(_lang.get('kw_no_rujukan'), ': $siri');
    r += baris(_lang.get('kw_jenis'), ': $jenisLabel');
    r += baris(_lang.get('kw_tarikh'), ': $tarikhStr');
    r += baris(_lang.get('kw_masa_print'), ': $masaStr');
    r += baris(
      _lang.get('kw_staf'),
      ': ${(rec['staff'] ?? '-').toString().length > 28 ? (rec['staff'] ?? '-').toString().substring(0, 28) : rec['staff'] ?? '-'}',
    );
    r += garis2;

    r += '$escBoldOn ${_lang.get('kw_pelanggan')}\n$escBoldOff';
    r += garis2;
    r += baris(
      _lang.get('kw_nama'),
      ': ${(rec['nama'] ?? '-').toString().length > 28 ? (rec['nama'] ?? '-').toString().substring(0, 28) : rec['nama'] ?? '-'}',
    );
    r += baris(_lang.get('kw_no_tel'), ': ${rec['tel'] ?? '-'}');
    r += garis2;

    r += '$escBoldOn ${_lang.get('kw_butiran')}\n$escBoldOff';
    r += garis2;
    r += baris(
      _lang.get('kw_item'),
      ': ${(rec['item'] ?? '-').toString().length > 28 ? (rec['item'] ?? '-').toString().substring(0, 28) : rec['item'] ?? '-'}',
    );
    r += baris(_lang.get('kw_cara_bayar'), ': ${rec['cara'] ?? 'CASH'}');
    r += garis2;

    r += escCenter + escDblHeight + escBoldOn;
    r += baris(_lang.get('kw_jumlah'), 'RM ${jumlah.toStringAsFixed(2)}', 22);
    r += escNormal + escBoldOff + escLeft;
    r += garis;
    r += '$escCenter$escBoldOn${_lang.get('kw_terima_kasih')}\n$escBoldOff';
    r += tengah('~ Powered by RMS Pro ~');
    r += garis;
    r += '\x0A\x0A\x0A\x1D\x56\x00';

    final bytes = utf8.encode(r);
    final ok = await _printer.printRaw(bytes);
    if (ok) {
      _snack(_lang.get('kw_berjaya_cetak'));
    } else {
      _snack(_lang.get('kw_gagal_cetak'), err: true);
    }
  }

  Future<void> _generateSalesPDF(Map<String, dynamic> rec) async {
    if (!mounted) return;
    final siri = rec['siri'] ?? '-';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                _lang.get('kw_menjana_pdf'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final rawData = rec['rawData'] as Map<String, dynamic>? ?? {};

      List<Map<String, dynamic>> itemPDF = [];
      if (rawData['items_array'] is List &&
          (rawData['items_array'] as List).isNotEmpty) {
        itemPDF = (rawData['items_array'] as List)
            .map((i) => Map<String, dynamic>.from(i as Map))
            .toList();
      } else {
        itemPDF = [
          {
            'nama': rec['item'] ?? '-',
            'harga': ((rec['jumlah'] ?? 0) as num).toDouble(),
            'qty': 1,
          },
        ];
      }

      final payload = {
        'typePDF': 'INVOICE',
        'paperSize': 'A4',
        'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
        'logoBase64': _branchSettings['logoBase64'] ?? '',
        'namaKedai':
            _branchSettings['shopName'] ??
            _branchSettings['namaKedai'] ??
            'RMS PRO',
        'alamatKedai':
            _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
        'telKedai':
            _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
        'noJob': siri,
        'namaCust': rec['nama'] ?? '-',
        'tarikhResit': rec['timestamp'] is int
            ? DateFormat(
                'yyyy-MM-dd',
              ).format(DateTime.fromMillisecondsSinceEpoch(rec['timestamp']))
            : DateTime.now().toIso8601String().split('T').first,
        'stafIncharge': rec['staff'] ?? 'Admin',
        'items': itemPDF,
        'voucherAmt':
            double.tryParse(rawData['voucher_used_amt']?.toString() ?? '0') ??
            0,
        'diskaunAmt':
            double.tryParse(rawData['diskaun']?.toString() ?? '0') ?? 0,
        'tambahanAmt':
            double.tryParse(rawData['tambahan']?.toString() ?? '0') ?? 0,
        'depositAmt':
            double.tryParse(rawData['deposit']?.toString() ?? '0') ?? 0,
        'totalDibayar': ((rec['jumlah'] ?? 0) as num).toDouble(),
        'statusBayar': 'PAID',
        'nota':
            _branchSettings['notaInvoice'] ??
            _lang.get('kw_nota_invoice'),
      };

      final pdfUrl = await PdfUrlHelper.getGeneratePdfUrl();
      final response = await http
          .post(
            Uri.parse(pdfUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          if (rec['collection'] == 'repairs_$_ownerID') {
            await _db
                .collection('repairs_$_ownerID')
                .doc(siri)
                .update({'pdfUrl_INVOICE': pdfUrl})
                .catchError((_) {});
          }
          _snack(_lang.get('kw_pdf_berjaya'));
          _downloadAndOpenPDF(pdfUrl, siri);
        } else {
          _snack(_lang.get('kw_pdf_tiada'), err: true);
        }
      } else {
        _snack('${_lang.get('kw_gagal_pdf')}: ${response.statusCode}', err: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _snack('${_lang.get('ralat')}: $e', err: true);
    }
  }

  Future<void> _downloadAndOpenPDF(String pdfUrl, String siri) async {
    try {
      if (kIsWeb) {
        if (!mounted) return;
        _showPdfBottomSheet(pdfUrl, siri);
        return;
      }

      // Mobile: download & simpan local
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'INVOICE_$siri.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (!file.existsSync()) {
        await Dio().download(pdfUrl, filePath);
      }

      if (!mounted) return;
      _showPdfBottomSheet(pdfUrl, siri, filePath: filePath, fileName: fileName);
    } catch (e) {
      _snack('${_lang.get('kw_gagal_muat_turun')}: $e', err: true);
    }
  }

  void _showPdfBottomSheet(String pdfUrl, String siri, {String? filePath, String? fileName}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.filePdf, size: 14, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'INVOICE #$siri',
                    style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!kIsWeb && filePath != null)
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
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: pdfUrl));
                      _snack(_lang.get('kw_link_disalin'));
                    },
                    icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
                    label: Text(_lang.get('salin_link')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.border,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final msg = Uri.encodeComponent('INVOICE #$siri\n$pdfUrl');
                      launchUrl(
                        Uri.parse('https://wa.me/?text=$msg'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 12),
                    label: Text(_lang.get('hantar_wa')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _promptLaporanPrestasi() {
    final svPass = (_branchSettings['svPass'] ?? '').toString();
    if (svPass.isEmpty) {
      _showLaporanPrestasiModal();
      return;
    }

    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const FaIcon(FontAwesomeIcons.lock, size: 16, color: AppColors.yellow),
            const SizedBox(width: 8),
            Text(
              _lang.get('kw_kata_laluan_admin'),
              style: TextStyle(
                color: AppColors.yellow,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _lang.get('kw_masuk_kata_laluan'),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: _lang.get('kw_kata_laluan_hint'),
                hintStyle: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: AppColors.bgDeep,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _lang.get('batal'),
              style: const TextStyle(color: AppColors.textDim),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (passCtrl.text.trim() == svPass) {
                Navigator.pop(ctx);
                _showLaporanPrestasiModal();
              } else {
                _snack(_lang.get('kw_kata_laluan_salah'), err: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellow,
              foregroundColor: Colors.black,
            ),
            child: Text(
              _lang.get('kw_sahkan'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  void _showLaporanPrestasiModal() {
    String rptTime = 'TODAY';
    String rptKategori = 'ALL';
    String rptStaff = 'ALL';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final range = _getFilteredTimeRange(rptTime);
          var reportData = List<Map<String, dynamic>>.from(_allRecords);

          if (rptTime != 'ALL') {
            reportData = reportData.where((d) {
              final ts = d['timestamp'] ?? 0;
              return ts >= range.$1 && ts <= range.$2;
            }).toList();
          }

          if (rptKategori != 'ALL') {
            reportData = reportData
                .where((d) => d['jenis'] == rptKategori)
                .toList();
          }

          if (rptStaff != 'ALL') {
            reportData = reportData
                .where(
                  (d) =>
                      (d['staff'] ?? '').toString().toUpperCase() ==
                      rptStaff.toUpperCase(),
                )
                .toList();
          }

          final totalSales = reportData
              .where((d) => d['isExpense'] != true)
              .fold(0.0, (s, d) => s + ((d['jumlah'] ?? 0) as num).toDouble());
          final totalExpenses = reportData
              .where((d) => d['isExpense'] == true)
              .fold(0.0, (s, d) => s + ((d['jumlah'] ?? 0) as num).toDouble());
          final net = totalSales - totalExpenses;
          final salesCount = reportData
              .where((d) => d['isExpense'] != true)
              .length;
          final expCount = reportData
              .where((d) => d['isExpense'] == true)
              .length;

          final staffMap = <String, double>{};
          for (final d in reportData.where((d) => d['isExpense'] != true)) {
            final staff = (d['staff'] ?? 'Lain').toString();
            staffMap[staff] =
                (staffMap[staff] ?? 0) + ((d['jumlah'] ?? 0) as num).toDouble();
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollCtrl,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.chartLine,
                            size: 14,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _lang.get('kw_laporan_prestasi'),
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const FaIcon(
                          FontAwesomeIcons.xmark,
                          size: 16,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.borderMed, height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _rptDropdown(_lang.get('kw_masa'), rptTime, {
                          'ALL': _lang.get('kw_semua'),
                          'TODAY': _lang.get('kw_hari_ini'),
                          'WEEK': _lang.get('kw_minggu_ini'),
                          'MONTH': _lang.get('kw_bulan_ini'),
                          'YEAR': _lang.get('kw_tahun_ini'),
                        }, (v) => setS(() => rptTime = v)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _rptDropdown(_lang.get('kw_kategori'), rptKategori, {
                          'ALL': _lang.get('kw_semua'),
                          'RETAIL': _lang.get('kw_sales_repair'),
                          'PANTAS': _lang.get('kw_quick_sales'),
                          'PRO_ONLINE': _lang.get('kw_pro_online'),
                          'PRO_OFFLINE': _lang.get('kw_pro_offline'),
                          'EXPENSE': _lang.get('kw_duit_keluar_filter'),
                        }, (v) => setS(() => rptKategori = v)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _rptDropdown(_lang.get('kw_staff'), rptStaff, {
                          'ALL': _lang.get('kw_semua'),
                          ..._staffList.asMap().map((_, v) => MapEntry(v, v)),
                        }, (v) => setS(() => rptStaff = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _rptCard(
                          _lang.get('kw_jualan'),
                          _formatRM(totalSales),
                          '$salesCount ${_lang.get('kw_transaksi')}',
                          AppColors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _rptCard(
                          _lang.get('kw_perbelanjaan'),
                          _formatRM(totalExpenses),
                          '$expCount ${_lang.get('kw_transaksi')}',
                          AppColors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _rptCard(
                    _lang.get('kw_margin_bersih'),
                    _formatRM(net),
                    net >= 0 ? _lang.get('kw_untung') : _lang.get('kw_rugi'),
                    net >= 0 ? AppColors.primary : AppColors.red,
                  ),
                  const SizedBox(height: 16),

                  if (staffMap.isNotEmpty) ...[
                    Text(
                      _lang.get('kw_pecahan_staf'),
                      style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...staffMap.entries.map(
                      (e) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderMed),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const FaIcon(
                                  FontAwesomeIcons.user,
                                  size: 10,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  e.key,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _formatRM(e.value),
                              style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _downloadReportCSV(reportData);
                      },
                      icon: const FaIcon(FontAwesomeIcons.fileExcel, size: 14),
                      label: Text(_lang.get('kw_muat_turun_excel')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _printSalesSummary80mm(
                          rptTime,
                          totalSales,
                          totalExpenses,
                          net,
                          salesCount,
                          expCount,
                          staffMap,
                        );
                      },
                      icon: const FaIcon(FontAwesomeIcons.print, size: 14),
                      label: Text(_lang.get('kw_cetak_80mm')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generateSalesReportPDF(
                          rptTime,
                          totalSales,
                          totalExpenses,
                          net,
                          salesCount,
                          expCount,
                          reportData,
                        );
                      },
                      icon: const FaIcon(FontAwesomeIcons.filePdf, size: 14),
                      label: Text(_lang.get('kw_jana_laporan')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rptDropdown(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderMed),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(selected) ? selected : options.keys.first,
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ),
    );
  }

  Widget _rptCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCSV() async {
    await _downloadReportCSV(_filteredRecords);
  }

  Future<void> _downloadReportCSV(List<Map<String, dynamic>> data) async {
    if (data.isEmpty) {
      _snack(_lang.get('kw_tiada_data_csv'), err: true);
      return;
    }

    try {
      final buf = StringBuffer();
      buf.write('\uFEFF');
      buf.writeln(
        'Tarikh,Masa,Siri,Jenis,Pelanggan,Telefon,Item,Jumlah(RM),Cara Bayar,Staff',
      );

      for (final rec in data) {
        final tsMs = rec['timestamp'] ?? 0;
        final tarikh = tsMs > 0
            ? DateFormat(
                'dd/MM/yyyy',
              ).format(DateTime.fromMillisecondsSinceEpoch(tsMs))
            : '-';
        final masa = tsMs > 0
            ? DateFormat(
                'HH:mm',
              ).format(DateTime.fromMillisecondsSinceEpoch(tsMs))
            : '-';
        final isExp = rec['isExpense'] == true;
        final jumlah = ((rec['jumlah'] ?? 0) as num).toDouble();

        String esc(String s) => '"${s.replaceAll('"', '""')}"';

        buf.writeln(
          [
            esc(tarikh),
            esc(masa),
            esc((rec['siri'] ?? '-').toString()),
            esc(rec['jenisLabel'] ?? rec['jenis'] ?? '-'),
            esc((rec['nama'] ?? '-').toString()),
            esc((rec['tel'] ?? '-').toString()),
            esc((rec['item'] ?? '-').toString()),
            isExp ? '-${jumlah.toStringAsFixed(2)}' : jumlah.toStringAsFixed(2),
            esc((rec['cara'] ?? '-').toString()),
            esc((rec['staff'] ?? '-').toString()),
          ].join(','),
        );
      }

      final fileName =
          'Kewangan_${_shopID}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

      if (kIsWeb) {
        // Web: download via data URI
        final bytes = utf8.encode(buf.toString());
        final b64 = base64Encode(bytes);
        final uri = Uri.parse('data:text/csv;base64,$b64');
        await launchUrl(uri);
        _snack('${_lang.get('kw_csv_dimuat')}: $fileName');
      } else {
        // Mobile: simpan ke documents
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(buf.toString());
        _snack('${_lang.get('kw_csv_disimpan')}: $fileName');
        OpenFilex.open(file.path);
      }
    } catch (e) {
      _snack('${_lang.get('kw_gagal_csv')}: $e', err: true);
    }
  }

  Future<void> _printSalesSummary80mm(
    String period,
    double totalSales,
    double totalExpenses,
    double net,
    int salesCount,
    int expCount,
    Map<String, double> staffMap,
  ) async {
    _snack(_lang.get('kw_sambung_printer'));

    const lebar = 48;
    final garis = '${'=' * 48}\n';
    final garis2 = '${'-' * 48}\n';
    const escInit = '\x1B\x40';
    const escCenter = '\x1B\x61\x01';
    const escLeft = '\x1B\x61\x00';
    const escBoldOn = '\x1B\x45\x01';
    const escBoldOff = '\x1B\x45\x00';
    const escDblHeight = '\x1B\x21\x10';
    const escDblSize = '\x1B\x21\x30';
    const escNormal = '\x1B\x21\x00';

    String tengah(String t, [int w = lebar]) {
      int pad = ((w - t.length) / 2).floor().clamp(0, w);
      return '${' ' * pad}$t\n';
    }

    String baris(String label, String nilai, [int lebarLabel = 22]) {
      final l = label.padRight(lebarLabel);
      final gap = lebar - l.length - nilai.length;
      return '$l${' ' * (gap > 0 ? gap : 1)}$nilai\n';
    }

    final s = _branchSettings;
    final namaKedai = (s['shopName'] ?? s['namaKedai'] ?? 'RMS PRO')
        .toString()
        .toUpperCase();
    final periodLabel =
        {
          'ALL': _lang.get('kw_semua').toUpperCase(),
          'TODAY': _lang.get('kw_hari_ini').toUpperCase(),
          'WEEK': _lang.get('kw_minggu_ini').toUpperCase(),
          'MONTH': _lang.get('kw_bulan_ini').toUpperCase(),
          'YEAR': _lang.get('kw_tahun_ini').toUpperCase(),
        }[period] ??
        period;

    var r = escInit;
    r += escCenter + escDblSize + escBoldOn;
    r += tengah(
      namaKedai.length > 24 ? namaKedai.substring(0, 24) : namaKedai,
      (lebar / 2).floor(),
    );
    r += escNormal + escBoldOff;
    r += garis;

    r += escCenter + escDblHeight + escBoldOn;
    r += tengah(_lang.get('kw_laporan_kewangan'));
    r += escNormal + escBoldOff + escLeft;
    r += garis2;
    r += baris(_lang.get('kw_tempoh'), ': $periodLabel');
    r += baris(
      _lang.get('kw_tarikh_cetak'),
      ': ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
    );
    r += garis;

    r += '$escBoldOn${_lang.get('kw_ringkasan_jualan')}\n$escBoldOff$garis2';
    r += baris(_lang.get('kw_jumlah_jualan'), 'RM ${totalSales.toStringAsFixed(2)}');
    r += baris(_lang.get('kw_bil_transaksi'), '$salesCount');
    r += garis2;
    r += '$escBoldOn${_lang.get('kw_perbelanjaan')}\n$escBoldOff$garis2';
    r += baris(_lang.get('kw_jumlah_keluar'), 'RM ${totalExpenses.toStringAsFixed(2)}');
    r += baris(_lang.get('kw_bil_transaksi'), '$expCount');
    r += garis;

    r += escCenter + escDblHeight + escBoldOn;
    r += baris(_lang.get('kw_margin_bersih'), 'RM ${net.toStringAsFixed(2)}');
    r += escNormal + escBoldOff + escLeft;
    r += garis;

    if (staffMap.isNotEmpty) {
      r += '$escBoldOn${_lang.get('kw_pecahan_staf_print')}\n$escBoldOff$garis2';
      for (final e in staffMap.entries) {
        final staffName = e.key.length > 20 ? e.key.substring(0, 20) : e.key;
        r += baris(staffName, 'RM ${e.value.toStringAsFixed(2)}');
      }
      r += garis2;
    }

    r += tengah('~ Powered by RMS Pro ~');
    r += garis;
    r += '\x0A\x0A\x0A\x1D\x56\x00';

    final bytes = utf8.encode(r);
    final ok = await _printer.printRaw(bytes);
    if (ok) {
      _snack(_lang.get('kw_laporan_cetak_ok'));
    } else {
      _snack(_lang.get('kw_gagal_cetak'), err: true);
    }
  }

  Future<void> _generateSalesReportPDF(
    String period,
    double totalSales,
    double totalExpenses,
    double net,
    int salesCount,
    int expCount,
    List<Map<String, dynamic>> reportData,
  ) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                _lang.get('kw_menjana_laporan'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final periodLabel =
          {
            'ALL': _lang.get('kw_semua'),
            'TODAY': _lang.get('kw_hari_ini'),
            'WEEK': _lang.get('kw_minggu_ini'),
            'MONTH': _lang.get('kw_bulan_ini'),
            'YEAR': _lang.get('kw_tahun_ini'),
          }[period] ??
          period;

      final items = reportData.map((rec) {
        final isExp = rec['isExpense'] == true;
        return {
          'tarikh': rec['timestamp'] is int
              ? DateFormat(
                  'dd/MM/yy HH:mm',
                ).format(DateTime.fromMillisecondsSinceEpoch(rec['timestamp']))
              : '-',
          'siri': rec['siri'] ?? '-',
          'jenis': rec['jenisLabel'] ?? rec['jenis'] ?? '-',
          'nama': rec['nama'] ?? '-',
          'item': rec['item'] ?? '-',
          'jumlah': isExp
              ? -((rec['jumlah'] ?? 0) as num).toDouble()
              : ((rec['jumlah'] ?? 0) as num).toDouble(),
          'staff': rec['staff'] ?? '-',
        };
      }).toList();

      final payload = {
        'typePDF': 'SALES_REPORT',
        'paperSize': 'A4',
        'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
        'logoBase64': _branchSettings['logoBase64'] ?? '',
        'namaKedai':
            _branchSettings['shopName'] ??
            _branchSettings['namaKedai'] ??
            'RMS PRO',
        'alamatKedai':
            _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
        'telKedai':
            _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
        'shopID': _shopID,
        'period': periodLabel,
        'tarikhCetak': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        'totalSales': totalSales,
        'totalExpenses': totalExpenses,
        'netMargin': net,
        'salesCount': salesCount,
        'expenseCount': expCount,
        'items': items,
      };

      final pdfUrl = await PdfUrlHelper.getGeneratePdfUrl();
      final response = await http
          .post(
            Uri.parse(pdfUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          _snack(_lang.get('kw_laporan_pdf_ok'));
          _downloadAndOpenPDF(pdfUrl, 'LAPORAN_$_shopID');
        } else {
          _snack(_lang.get('kw_pdf_tiada'), err: true);
        }
      } else {
        _snack('${_lang.get('kw_gagal_laporan')}: ${response.statusCode}', err: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _snack('${_lang.get('ralat')}: $e', err: true);
    }
  }
}
