import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';
import '../../services/app_language.dart';

const String _cloudRunUrl =
    'https://rms-backend-94407896005.asia-southeast1.run.app';

class SenaraiJobScreen extends StatefulWidget {
  const SenaraiJobScreen({super.key});

  @override
  State<SenaraiJobScreen> createState() => _SenaraiJobScreenState();
}

class _SenaraiJobScreenState extends State<SenaraiJobScreen> {
  final _searchCtrl = TextEditingController();
  final _db = FirebaseFirestore.instance;
  final _lang = AppLanguage();

  String _ownerID = 'admin';
  String _shopID = 'MAIN';
  String _filterStatus = 'ALL';
  String _filterSort = 'TARIKH_DESC';
  String _filterTime = 'ALL';
  DateTime? _specificDate;
  int _rowsPerPage = 20;
  int _currentPage = 1;
  bool _hasLoadedOnce = false;

  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  List<Map<String, dynamic>> _inventory = [];
  List<String> _staffList = [];
  List<Map<String, dynamic>> _staffRawList = [];
  Map<String, dynamic> _branchSettings = {};
  List<Map<String, dynamic>> _warrantyRules = [];
  StreamSubscription? _repairsSub;
  StreamSubscription? _invSub;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _repairsSub?.cancel();
    _invSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase();
      _shopID = branch.split('@')[1].toUpperCase();
    }
    _listenRepairs();
    _listenInventory();
    _loadBranchSettings();
  }

  void _listenRepairs() {
    _repairsSub =
        _db.collection('repairs_$_ownerID').snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) {
          final nama = (d['nama'] ?? '').toString().toUpperCase();
          final jenis = (d['jenis_servis'] ?? '').toString().toUpperCase();
          if (nama != 'JUALAN PANTAS' && jenis != 'JUALAN') list.add(d);
        }
      }
      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      if (mounted) {
        setState(() {
          _allData = list;
          _hasLoadedOnce = true;
          _applyFilters();
        });
      }
    });
  }

  void _listenInventory() {
    _invSub =
        _db.collection('inventory_$_ownerID').snapshots().listen((snap) {
      _inventory = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where((d) => (d['qty'] ?? 0) > 0)
          .toList();
    });
  }

  Future<void> _loadBranchSettings() async {
    final snap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
    if (snap.exists) {
      _branchSettings = snap.data() ?? {};
      final staffRaw = _branchSettings['staffList'];
      if (staffRaw is List) {
        _staffRawList = staffRaw
            .map((s) => s is Map
                ? Map<String, dynamic>.from(s)
                : <String, dynamic>{'name': s.toString()})
            .toList();
        _staffList = _staffRawList
            .map((s) => (s['name'] ?? s['nama'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    // Load warranty rules
    final wr = _branchSettings['warranty_rules'];
    if (wr is List) {
      _warrantyRules = wr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    // Also load dealer-level settings for svPass etc.
    try {
      final dealerSnap =
          await _db.collection('saas_dealers').doc(_ownerID).get();
      if (dealerSnap.exists) {
        final dd = dealerSnap.data() ?? {};
        _branchSettings['svPass'] = dd['svPass'] ?? '';
        _branchSettings['hasGalleryAddon'] = dd['addonGallery'] == true;
        _branchSettings['domain'] =
            dd['domain'] ?? 'https://rmspro.net';
        _branchSettings['dealerCode'] =
            (dd['dealerCode'] ?? '').toString();
        _branchSettings['isCustomDomain'] =
            (dd['domain'] ?? '') != '' &&
            dd['domain'] != 'https://rmspro.net';
      }
    } catch (_) {}
  }

  // -------------------------------------------------------
  // FILTERS
  // -------------------------------------------------------
  void _applyFilters() {
    var data = List<Map<String, dynamic>>.from(_allData);
    final query = _searchCtrl.text.toLowerCase().trim();

    if (query.isNotEmpty) {
      data = data.where((d) {
        return (d['siri'] ?? '').toString().toLowerCase().contains(query) ||
            (d['nama'] ?? '').toString().toLowerCase().contains(query) ||
            (d['tel'] ?? '').toString().toLowerCase().contains(query);
      }).toList();
    }

    if (_filterStatus != 'ALL') {
      if (_filterStatus == 'OVERDUE') {
        final cutoff =
            DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
        data = data.where((d) {
          final ts = d['timestamp'] ?? 0;
          final s = (d['status'] ?? '').toString().toUpperCase();
          return ts < cutoff && s != 'COMPLETED' && s != 'CANCEL';
        }).toList();
      } else {
        data = data
            .where((d) =>
                (d['status'] ?? '').toString().toUpperCase() == _filterStatus)
            .toList();
      }
    }

    if (_specificDate != null) {
      final dayStart = DateTime(
          _specificDate!.year, _specificDate!.month, _specificDate!.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      data = data.where((d) {
        final ts = d['timestamp'] ?? 0;
        return ts >= dayStart.millisecondsSinceEpoch &&
            ts < dayEnd.millisecondsSinceEpoch;
      }).toList();
    } else if (_filterTime != 'ALL') {
      final now = DateTime.now();
      DateTime start;
      switch (_filterTime) {
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
        default:
          start = DateTime(2020);
      }
      data = data
          .where((d) => (d['timestamp'] ?? 0) >= start.millisecondsSinceEpoch)
          .toList();
    }

    switch (_filterSort) {
      case 'TARIKH_ASC':
        data.sort(
            (a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        break;
      case 'NAMA_ASC':
        data.sort((a, b) => (a['nama'] ?? '')
            .toString()
            .compareTo((b['nama'] ?? '').toString()));
        break;
      case 'NAMA_DESC':
        data.sort((a, b) => (b['nama'] ?? '')
            .toString()
            .compareTo((a['nama'] ?? '').toString()));
        break;
      default:
        data.sort(
            (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    }

    _filteredData = data;
    _currentPage = 1;
  }

  int get _totalPages =>
      (_filteredData.length / _rowsPerPage).ceil().clamp(1, 9999);

  List<Map<String, dynamic>> get _pageData {
    final s = (_currentPage - 1) * _rowsPerPage;
    return _filteredData.sublist(
        s, (s + _rowsPerPage).clamp(0, _filteredData.length));
  }

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN PROGRESS':
        return const Color(0xFF4CAF50);
      case 'WAITING PART':
        return AppColors.yellow;
      case 'READY TO PICKUP':
        return const Color(0xFFA78BFA);
      case 'COMPLETED':
        return const Color(0xFF4CAF50);
      case 'CANCEL':
      case 'CANCELLED':
        return const Color(0xFFFFC107);
      case 'REJECT':
        return AppColors.red;
      default:
        return AppColors.textMuted;
    }
  }

  int _overdueDays(Map<String, dynamic> job) {
    final ts = job['timestamp'];
    if (ts == null || ts == 0) return 0;
    final created = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : 0);
    final diff = DateTime.now().difference(created).inDays;
    return diff;
  }

  String _fmt(dynamic ts) {
    if (ts is int && ts > 0) {
      return DateFormat('dd/MM/yy HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(ts));
    }
    return ts?.toString().split('T').first ?? '-';
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // -------------------------------------------------------
  // WARRANTY AUTO-DETECT FROM ITEMS
  // -------------------------------------------------------
  int _warrantyRuleDays(Map<String, dynamic> rule) {
    final months = (rule['months'] ?? 0) as num;
    final days = (rule['customDays'] ?? 0) as num;
    if (days > 0) return days.toInt();
    return (months * 30).toInt();
  }

  String _warrantyRuleLabel(Map<String, dynamic> rule) {
    final months = (rule['months'] ?? 0) as num;
    final days = (rule['customDays'] ?? 0) as num;
    if (days > 0) return '$days Hari';
    if (months > 0) return '$months Bulan';
    return 'TIADA';
  }

  /// Get latest READY TO PICKUP timestamp from status_history
  String _getLatestReadyDate(List<Map<String, dynamic>> statusHistory) {
    String latest = '';
    for (final h in statusHistory) {
      if ((h['status'] ?? '').toString().toUpperCase() == 'READY TO PICKUP') {
        final ts = (h['timestamp'] ?? '').toString();
        if (ts.compareTo(latest) > 0) latest = ts;
      }
    }
    return latest;
  }

  /// Auto-detect warranty for each item based on warranty_rules
  /// Jika satu item mengandungi multiple keywords (cth: "lcd dan battery"),
  /// hasilkan warranty berasingan untuk setiap keyword yang match.
  List<Map<String, dynamic>> _calcWarrantyItems(
      List<Map<String, dynamic>> items, String readyDate) {
    final result = <Map<String, dynamic>>[];
    DateTime base;
    if (readyDate.isNotEmpty) {
      base = DateTime.tryParse(readyDate) ?? DateTime.now();
    } else {
      base = DateTime.now();
    }
    for (final item in items) {
      final nama = (item['nama'] ?? '').toString().toLowerCase();
      bool anyMatch = false;
      for (final rule in _warrantyRules) {
        final keyword = (rule['keyword'] ?? '').toString().toLowerCase();
        if (keyword.isNotEmpty && nama.contains(keyword)) {
          final days = _warrantyRuleDays(rule);
          if (days > 0) {
            final exp = base.add(Duration(days: days));
            result.add({
              'nama': (rule['keyword'] ?? '').toString().toUpperCase(),
              'warranty': _warrantyRuleLabel(rule),
              'warranty_exp': DateFormat('yyyy-MM-dd').format(exp),
            });
            anyMatch = true;
          }
        }
      }
      // Jika tiada keyword match, skip (tiada warranty untuk item ni)
      if (!anyMatch) continue;
    }
    return result;
  }

  // -------------------------------------------------------
  // WARRANTY SETTINGS MODAL
  // -------------------------------------------------------
  void _showWarrantySettings() {
    List<Map<String, dynamic>> rules = _warrantyRules
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.shieldHalved,
                          size: 14, color: AppColors.yellow),
                      const SizedBox(width: 8),
                      const Text('Tetapan Warranty',
                          style: TextStyle(
                              color: AppColors.yellow,
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                    ]),
                    GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const FaIcon(FontAwesomeIcons.xmark,
                            size: 16, color: AppColors.red)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                    'Set warranty mengikut kategori item. Warranty bermula dari tarikh READY TO PICKUP.',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                // Rules list
                ...rules.asMap().entries.map((e) {
                  final i = e.key;
                  final rule = e.value;
                  final kwCtrl = TextEditingController(
                      text: (rule['keyword'] ?? '').toString());
                  final customCtrl = TextEditingController(
                      text: (rule['customDays'] ?? 0) > 0
                          ? rule['customDays'].toString()
                          : '');
                  final months = (rule['months'] ?? 0) as num;
                  final isCustom = (rule['customDays'] ?? 0) > 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.yellow.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.yellow.withValues(alpha: 0.15))),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: kwCtrl,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: 'Kata Kunci (cth: LCD, BATTERY)',
                              labelStyle: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (v) => rules[i]['keyword'] = v.toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setS(() => rules.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: const FaIcon(FontAwesomeIcons.trash,
                                size: 10, color: AppColors.red),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: isCustom
                                    ? 'CUSTOM'
                                    : months > 0
                                        ? '${months.toInt()}'
                                        : '0',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                items: [
                                  const DropdownMenuItem(
                                      value: '0',
                                      child: Text('Tiada',
                                          style: TextStyle(fontSize: 11))),
                                  ...List.generate(
                                      12,
                                      (m) => DropdownMenuItem(
                                          value: '${m + 1}',
                                          child: Text('${m + 1} Bulan',
                                              style: const TextStyle(
                                                  fontSize: 11)))),
                                  const DropdownMenuItem(
                                      value: 'CUSTOM',
                                      child: Text('Custom (Hari)',
                                          style: TextStyle(fontSize: 11))),
                                ],
                                onChanged: (v) {
                                  setS(() {
                                    if (v == 'CUSTOM') {
                                      rules[i]['months'] = 0;
                                      rules[i]['customDays'] =
                                          int.tryParse(customCtrl.text) ?? 7;
                                    } else {
                                      rules[i]['months'] =
                                          int.tryParse(v ?? '0') ?? 0;
                                      rules[i]['customDays'] = 0;
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: customCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'Hari',
                                labelStyle: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (v) =>
                                  rules[i]['customDays'] =
                                      int.tryParse(v) ?? 0,
                            ),
                          ),
                        ],
                      ]),
                    ]),
                  );
                }),

                // Add button
                GestureDetector(
                  onTap: () => setS(() =>
                      rules.add({'keyword': '', 'months': 1, 'customDays': 0})),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        color: AppColors.yellow.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.yellow.withValues(alpha: 0.2),
                            style: BorderStyle.solid)),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FaIcon(FontAwesomeIcons.plus,
                              size: 10, color: AppColors.yellow),
                          SizedBox(width: 6),
                          Text('Tambah Kategori',
                              style: TextStyle(
                                  color: AppColors.yellow,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900)),
                        ]),
                  ),
                ),
                const SizedBox(height: 16),

                // Save button
                GestureDetector(
                  onTap: () async {
                    // Clean empty keywords
                    rules.removeWhere((r) =>
                        (r['keyword'] ?? '').toString().trim().isEmpty);
                    await _db
                        .collection('shops_$_ownerID')
                        .doc(_shopID)
                        .update({'warranty_rules': rules});
                    _warrantyRules = rules;
                    _branchSettings['warranty_rules'] = rules;
                    Navigator.pop(ctx);
                    _snack('Tetapan warranty disimpan');
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Center(
                        child: Text('Simpan',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // INVENTORY DEDUCTION & REVERSAL
  // -------------------------------------------------------
  Future<void> _deductInventory(List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final nama = (item['nama'] ?? '').toString().toLowerCase();
      final qty = (item['qty'] ?? 1) as num;
      if (nama.isEmpty) continue;
      final match = _inventory.where(
          (inv) => (inv['nama'] ?? '').toString().toLowerCase() == nama);
      if (match.isNotEmpty) {
        final invDoc = match.first;
        final docId = invDoc['id']?.toString() ?? '';
        if (docId.isNotEmpty) {
          final currentQty = (invDoc['qty'] ?? 0) as num;
          final newQty = (currentQty - qty).clamp(0, 999999);
          await _db
              .collection('inventory_$_ownerID')
              .doc(docId)
              .update({'qty': newQty});
        }
      }
    }
  }

  Future<void> _reverseInventory(List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final nama = (item['nama'] ?? '').toString().toLowerCase();
      final qty = (item['qty'] ?? 1) as num;
      if (nama.isEmpty) continue;
      // Search all inventory including zero-stock
      final snap = await _db.collection('inventory_$_ownerID').get();
      for (final doc in snap.docs) {
        if ((doc.data()['nama'] ?? '').toString().toLowerCase() == nama) {
          final currentQty = (doc.data()['qty'] ?? 0) as num;
          await doc.reference.update({'qty': currentQty + qty});
          break;
        }
      }
    }
  }

  // -------------------------------------------------------
  // KEWANGAN RECORD CREATION
  // -------------------------------------------------------
  Future<void> _createKewanganRecord(Map<String, dynamic> job) async {
    final siri = job['siri'] ?? '-';
    // Check if already exists
    final existing = await _db
        .collection('kewangan_$_ownerID')
        .where('siri', isEqualTo: siri)
        .get();
    if (existing.docs.isNotEmpty) return;

    await _db.collection('kewangan_$_ownerID').add({
      'siri': siri,
      'shopID': _shopID,
      'nama': job['nama'] ?? '-',
      'tel': job['tel'] ?? '-',
      'jumlah': double.tryParse(job['total']?.toString() ?? '0') ?? 0,
      'cara': job['cara_bayaran'] ?? 'CASH',
      'staff': job['staff_repair'] ?? job['staff_terima'] ?? '-',
      'jenis': 'REPAIR',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'tarikh': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
    });
  }

  // -------------------------------------------------------
  // CSV / EXCEL DOWNLOAD
  // -------------------------------------------------------
  Future<void> _downloadCSV() async {
    if (_filteredData.isEmpty) {
      _snack('Tiada data untuk dimuat turun', err: true);
      return;
    }

    final buf = StringBuffer();
    buf.writeln(
        'Siri,Tarikh,Nama,Telefon,Model,Kerosakan,Status,Bayaran,Jumlah,Staff Terima,Staff Baiki,Staff Serah,Warranty');
    for (final d in _filteredData) {
      final siri = d['siri'] ?? '';
      final tarikh = _fmt(d['timestamp']);
      final nama = (d['nama'] ?? '').toString().replaceAll(',', ' ');
      final tel = d['tel'] ?? '';
      final model = (d['model'] ?? '').toString().replaceAll(',', ' ');
      final kerosakan =
          (d['kerosakan'] ?? '').toString().replaceAll(',', ' ');
      final status = d['status'] ?? '';
      final payment = d['payment_status'] ?? 'UNPAID';
      final total = d['total'] ?? d['harga'] ?? '0';
      final staffT = d['staff_terima'] ?? '';
      final staffB = d['staff_repair'] ?? '';
      final staffS = d['staff_serah'] ?? '';
      final warranty = d['warranty'] ?? '';
      buf.writeln(
          '$siri,$tarikh,$nama,$tel,$model,$kerosakan,$status,$payment,$total,$staffT,$staffB,$staffS,$warranty');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'senarai_job_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buf.toString());
      _snack('CSV disimpan: $fileName');
      OpenFilex.open(file.path);
    } catch (e) {
      _snack('Gagal simpan CSV: $e', err: true);
    }
  }

  // -------------------------------------------------------
  // WHATSAPP MODAL - 2 STEPS
  // -------------------------------------------------------
  String _formatWaTel(String tel) {
    var n = tel.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('0')) n = '6$n';
    if (!n.startsWith('6')) n = '60$n';
    return n;
  }

  Future<void> _printLabel(Map<String, dynamic> job) async {
    final ps = PrinterService();
    final ok = await ps.printLabel(job, _branchSettings);
    if (ok) {
      _snack('Label berjaya dicetak');
    } else {
      _snack('Gagal cetak label — pastikan printer dihidupkan & Bluetooth aktif', err: true);
    }
  }

  void _showWhatsAppModal(Map<String, dynamic> job) {
    final tel1 = (job['tel'] ?? '').toString();
    final tel2 = (job['tel_wasap'] ?? '').toString();
    final nama = job['nama'] ?? '-';
    final siri = job['siri'] ?? '-';
    final domain =
        _branchSettings['domain'] ?? 'https://rmspro.net';
    final isCustomDomain =
        _branchSettings['isCustomDomain'] == true;
    final dealerCode =
        (_branchSettings['dealerCode'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        int step = 1;
        String selectedTel = '';
        return StatefulBuilder(
          builder: (ctx, setS) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Row(children: [
                const FaIcon(FontAwesomeIcons.whatsapp,
                    size: 16, color: Color(0xFF25D366)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        step == 1 ? 'Hubungi $nama' : 'Jenis Mesej',
                        style: const TextStyle(
                            color: Color(0xFF25D366),
                            fontSize: 13,
                            fontWeight: FontWeight.w900))),
                GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const FaIcon(FontAwesomeIcons.xmark,
                        size: 16, color: AppColors.red)),
              ]),
              const SizedBox(height: 6),
              Text(
                  step == 1
                      ? 'Pilih nombor untuk dihubungi:'
                      : 'Pilih format mesej untuk dihantar.',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),

              // STEP 1
              if (step == 1) ...[
                if (tel1.isNotEmpty)
                  _wasapNumBtn('No. Utama', tel1,
                      () => setS(() { selectedTel = tel1; step = 2; })),
                if (tel2.isNotEmpty && tel2 != '-')
                  _wasapNumBtn('No. Backup / Wasap', tel2,
                      () => setS(() { selectedTel = tel2; step = 2; })),
              ],

              // STEP 2
              if (step == 2) ...[
                _wasapOptionBtn(
                  'Hantar Link Tracking',
                  'Pelanggan boleh semak status repair secara live',
                  FontAwesomeIcons.link,
                  AppColors.primary,
                  () {
                    Navigator.pop(ctx);
                    final trackUrl = isCustomDomain
                        ? '$domain/tracking?track=$siri'
                        : '$domain/tracking/$dealerCode?track=$siri';
                    final msg = Uri.encodeComponent(
                        'Assalamualaikum $nama,\n\nTerima kasih kerana menggunakan perkhidmatan kami.\n\nSila klik pautan di bawah untuk semak status repair anda:\n$trackUrl\n\nNo Rujukan: #$siri');
                    final waUrl =
                        'https://wa.me/${_formatWaTel(selectedTel)}?text=$msg';
                    launchUrl(Uri.parse(waUrl),
                        mode: LaunchMode.externalApplication);
                  },
                ),
                const SizedBox(height: 8),
                _wasapOptionBtn(
                  'WhatsApp Biasa (Kosong)',
                  'Buka chat kosong dengan pelanggan',
                  FontAwesomeIcons.paperPlane,
                  AppColors.textMuted,
                  () {
                    Navigator.pop(ctx);
                    final waUrl =
                        'https://wa.me/${_formatWaTel(selectedTel)}';
                    launchUrl(Uri.parse(waUrl),
                        mode: LaunchMode.externalApplication);
                  },
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setS(() => step = 1),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(FontAwesomeIcons.arrowLeft,
                            size: 10, color: AppColors.red),
                        const SizedBox(width: 6),
                        Text(_lang.get('kembali'),
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline)),
                      ]),
                ),
              ],
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
  }

  Widget _wasapNumBtn(String label, String tel, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const FaIcon(FontAwesomeIcons.mobileScreenButton,
                        size: 12, color: AppColors.blue),
                    const SizedBox(width: 8),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
                  Text(tel,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                  const FaIcon(FontAwesomeIcons.whatsapp,
                      size: 18, color: Color(0xFF25D366)),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _wasapOptionBtn(String title, String desc, IconData icon, Color color,
      VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Row(children: [
            FaIcon(icon, size: 16, color: color),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                  Text(desc,
                      style: const TextStyle(
                          color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                ])),
            FaIcon(FontAwesomeIcons.chevronRight,
                size: 12, color: color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // HISTORY MODAL
  // -------------------------------------------------------
  void _showHistory(Map<String, dynamic> job) {
    final tel = (job['tel'] ?? '').toString();
    final nama = job['nama'] ?? '-';
    final history = _allData.where((d) => (d['tel'] ?? '') == tel).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scroll) => Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.clockRotateLeft,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(_lang.get('sj_sejarah_pelanggan'),
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                    ]),
                    GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const FaIcon(FontAwesomeIcons.xmark,
                            size: 16, color: AppColors.red)),
                  ]),
              const SizedBox(height: 8),
              Row(children: [
                const FaIcon(FontAwesomeIcons.user,
                    size: 10, color: AppColors.textDim),
                const SizedBox(width: 6),
                Text(nama.toString().toUpperCase(),
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
                const SizedBox(width: 12),
                const FaIcon(FontAwesomeIcons.phone,
                    size: 10, color: Colors.black54),
                const SizedBox(width: 6),
                Text(tel,
                    style: const TextStyle(
                        color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              Text('${history.length} rekod repair',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
              const Divider(color: AppColors.borderMed, height: 16),
            ]),
          ),
          Expanded(
              child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: history.length,
            itemBuilder: (_, i) {
              final h = history[i];
              final st = (h['status'] ?? '').toString().toUpperCase();
              final col = _statusColor(st);
              final payStatus =
                  (h['payment_status'] ?? 'UNPAID').toString().toUpperCase();
              final harga = double.tryParse(
                      h['total']?.toString() ?? h['harga']?.toString() ?? '0') ??
                  0;
              final staffTerima = (h['staff_terima'] ?? '-').toString();
              final staffRepair = (h['staff_repair'] ?? '-').toString();
              final staffSerah = (h['staff_serah'] ?? '-').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(left: BorderSide(color: col, width: 3)),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.bg,
                          blurRadius: 8)
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('#${h['siri'] ?? '-'}',
                                style: TextStyle(
                                    color: col,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900)),
                            Row(children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: col.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(st,
                                      style: TextStyle(
                                          color: col,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900))),
                              const SizedBox(width: 4),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: payStatus == 'PAID'
                                          ? AppColors.green
                                              .withValues(alpha: 0.15)
                                          : AppColors.red
                                              .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(payStatus,
                                      style: TextStyle(
                                          color: payStatus == 'PAID'
                                              ? AppColors.green
                                              : AppColors.red,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900))),
                            ]),
                          ]),
                      const SizedBox(height: 8),
                      _histRow(FontAwesomeIcons.mobileScreenButton, 'Model',
                          h['model'] ?? '-', AppColors.blue),
                      _histRow(FontAwesomeIcons.screwdriverWrench,
                          'Kerosakan', h['kerosakan'] ?? '-', AppColors.yellow),
                      _histRow(FontAwesomeIcons.moneyBill, 'Jumlah',
                          'RM ${harga.toStringAsFixed(2)}', AppColors.green),
                      _histRow(FontAwesomeIcons.calendarDay, 'Tarikh Masuk',
                          _fmt(h['timestamp']), AppColors.textMuted),
                      if (h['tarikh_siap'] != null &&
                          h['tarikh_siap'].toString().isNotEmpty)
                        _histRow(
                            FontAwesomeIcons.calendarCheck,
                            'Tarikh Siap',
                            h['tarikh_siap'].toString().replaceAll('T', ' '),
                            AppColors.primary),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.blue.withValues(alpha: 0.1))),
                        child: Row(children: [
                          _staffChip('Terima', staffTerima, AppColors.blue),
                          const SizedBox(width: 6),
                          _staffChip('Baiki', staffRepair, AppColors.primary),
                          const SizedBox(width: 6),
                          _staffChip('Serah', staffSerah, AppColors.yellow),
                        ]),
                      ),
                      // Per-item warranty display
                      if (h['warranty_items'] is List && (h['warranty_items'] as List).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...((h['warranty_items'] as List).map((w) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(children: [
                              const FaIcon(FontAwesomeIcons.shieldHalved,
                                  size: 8, color: AppColors.yellow),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(
                                      '${w['nama'] ?? '-'}: ${w['warranty'] ?? '-'}${w['warranty_exp'] != null ? ' (Tamat: ${w['warranty_exp']})' : ''}',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold))),
                            ])))),
                      ] else if (h['warranty'] != null &&
                          h['warranty'] != 'TIADA' &&
                          h['warranty'] != '') ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const FaIcon(FontAwesomeIcons.shieldHalved,
                              size: 9, color: AppColors.yellow),
                          const SizedBox(width: 6),
                          Text('Warranty: ${h['warranty']}',
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          if (h['warranty_exp'] != null) ...[
                            const SizedBox(width: 8),
                            Text('(Tamat: ${h['warranty_exp']})',
                                style: const TextStyle(
                                    color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ]),
                      ],
                      if (h['catatan'] != null &&
                          h['catatan'] != '' &&
                          h['catatan'] != '-') ...[
                        const SizedBox(height: 4),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FaIcon(FontAwesomeIcons.noteSticky,
                                  size: 9, color: AppColors.textDim),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text('Catatan: ${h['catatan']}',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          fontStyle: FontStyle.italic))),
                            ]),
                      ],
                    ]),
              );
            },
          )),
        ]),
      ),
    );
  }

  Widget _histRow(
      IconData icon, String label, String value, Color iconColor) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          FaIcon(icon, size: 9, color: iconColor),
          const SizedBox(width: 8),
          SizedBox(
              width: 75,
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w900))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis)),
        ]));
  }

  Widget _staffChip(String role, String name, Color color) {
    return Expanded(
        child: Column(children: [
      Text(role,
          style: TextStyle(
              color: Colors.black,
              fontSize: 8,
              fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(name.isNotEmpty && name != '-' ? name : '-',
          style: TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    ]));
  }

  // -------------------------------------------------------
  // PRINT MODAL - 80mm + Invoice + Quotation + Claim PDF
  // -------------------------------------------------------
  void _showPrintModal(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '-';
    final hasInvoice =
        (job['pdfUrl_INVOICE'] ?? '').toString().isNotEmpty;
    final hasQuote =
        (job['pdfUrl_QUOTATION'] ?? '').toString().isNotEmpty;


    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.print,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('${_lang.get('cetak')} #$siri',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: const FaIcon(FontAwesomeIcons.xmark,
                    size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          // Print Label
          _printBtn('PRINT LABEL', 'Cetak label ke printer Bluetooth',
              FontAwesomeIcons.tag, AppColors.orange, () async {
            Navigator.pop(ctx);
            _printLabel(job);
          }),
          const SizedBox(height: 8),
          // 80mm Receipt
          _printBtn('RESIT 80MM', 'Cetak ke printer Bluetooth',
              FontAwesomeIcons.receipt, AppColors.blue, () async {
            Navigator.pop(ctx);
            final ok =
                await PrinterService().printReceipt(job, _branchSettings);
            if (!ok) {
              _snack('Gagal cetak - pastikan printer dihidupkan & Bluetooth aktif', err: true);
            }
          }),
          const SizedBox(height: 8),
          // Invoice
          hasInvoice
              ? _printBtn(
                  'VIEW INVOICE',
                  'Sudah dijana - tekan untuk buka',
                  FontAwesomeIcons.eye,
                  AppColors.green,
                  () {
                    Navigator.pop(ctx);
                    _downloadAndOpenPDF(
                        job['pdfUrl_INVOICE'], 'INVOICE', siri);
                  })
              : _printBtn(
                  'GENERATE INVOICE',
                  'Jana invoice PDF sekali',
                  FontAwesomeIcons.filePdf,
                  AppColors.green,
                  () {
                    Navigator.pop(ctx);
                    _generatePDF(job, 'INVOICE');
                  }),
          const SizedBox(height: 8),
          // Quotation
          hasQuote
              ? _printBtn(
                  'VIEW QUOTATION',
                  'Sudah dijana - tekan untuk buka',
                  FontAwesomeIcons.eye,
                  AppColors.yellow,
                  () {
                    Navigator.pop(ctx);
                    _downloadAndOpenPDF(
                        job['pdfUrl_QUOTATION'], 'QUOTATION', siri);
                  })
              : _printBtn(
                  'GENERATE QUOTATION',
                  'Jana sebut harga PDF sekali',
                  FontAwesomeIcons.fileLines,
                  AppColors.yellow,
                  () {
                    Navigator.pop(ctx);
                    _generatePDF(job, 'QUOTATION');
                  }),


        ]),
      ),
    );
  }

  Widget _printBtn(String title, String desc, IconData icon, Color color,
      VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.25))),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(child: FaIcon(icon, size: 16, color: color))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                  Text(desc,
                      style: const TextStyle(
                          color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                ])),
            FaIcon(FontAwesomeIcons.chevronRight,
                size: 12, color: color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  Map<String, dynamic> _buildPdfPayload(
      Map<String, dynamic> job, String typePDF) {
    List<Map<String, dynamic>> itemPDF = [];
    if (job['items_array'] is List &&
        (job['items_array'] as List).isNotEmpty) {
      itemPDF = (job['items_array'] as List)
          .map((i) => Map<String, dynamic>.from(i as Map))
          .toList();
    } else {
      itemPDF = [
        {
          'nama': '${job['model'] ?? '-'} (${job['kerosakan'] ?? '-'})',
          'harga':
              double.tryParse(job['harga']?.toString() ?? '0') ?? 0
        }
      ];
    }
    return {
      'typePDF': typePDF,
      'paperSize': 'A4',
      'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
      'logoBase64': _branchSettings['logoBase64'] ?? '',
      'namaKedai':
          _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'RMS PRO',
      'alamatKedai':
          _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
      'telKedai':
          _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
      'noJob': job['siri'] ?? '-',
      'namaCust': job['nama'] ?? '-',
      'telCust': job['tel'] ?? '-',
      'tarikhResit': (job['tarikh'] ?? DateTime.now().toIso8601String())
          .toString()
          .split('T')
          .first,
      'stafIncharge':
          job['staff_repair'] ?? job['staff_terima'] ?? 'Admin',
      'items': itemPDF,
      'model': job['model'] ?? '-',
      'kerosakan': job['kerosakan'] ?? '-',
      'warranty': job['warranty'] ?? 'TIADA',
      'warranty_exp': job['warranty_exp'] ?? '',
      'warranty_items': job['warranty_items'] is List
          ? (job['warranty_items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [],
      'voucherAmt':
          double.tryParse(job['voucher_used_amt']?.toString() ?? '0') ?? 0,
      'diskaunAmt':
          double.tryParse(job['diskaun']?.toString() ?? '0') ?? 0,
      'tambahanAmt':
          double.tryParse(job['tambahan']?.toString() ?? '0') ?? 0,
      'depositAmt':
          double.tryParse(job['deposit']?.toString() ?? '0') ?? 0,
      'totalDibayar':
          double.tryParse(job['total']?.toString() ?? '0') ?? 0,
      'statusBayar':
          (job['payment_status'] ?? 'UNPAID').toString().toUpperCase(),
      'nota': typePDF == 'INVOICE'
          ? (_branchSettings['notaInvoice'] ??
              'Sila simpan dokumen ini untuk rujukan rasmi.')
          : typePDF == 'CLAIM'
              ? (_branchSettings['notaClaim'] ??
                  'Dokumen tuntutan warranty rasmi.')
              : (_branchSettings['notaQuotation'] ??
                  'Sebut harga ini sah untuk tempoh 7 hari sahaja.'),
    };
  }

  Future<void> _generatePDF(Map<String, dynamic> job, String typePDF) async {
    if (!mounted) return;
    final siri = job['siri'] ?? '-';

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
                child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 16),
                Text('${_lang.get('sj_menjana_pdf')} $typePDF...',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ]),
            )));

    try {
      final response = await http
          .post(
            Uri.parse('$_cloudRunUrl/generate-pdf'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(_buildPdfPayload(job, typePDF)),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          await _db
              .collection('repairs_$_ownerID')
              .doc(siri)
              .update({'pdfUrl_$typePDF': pdfUrl});
          _snack('$typePDF berjaya dijana!');
          _downloadAndOpenPDF(pdfUrl, typePDF, siri);
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

  Future<void> _downloadAndOpenPDF(
      String pdfUrl, String typePDF, String siri) async {
    if (kIsWeb) {
      // Web: papar PDF dalam app (bukan tab baru)
      if (!mounted) return;
      _showPdfBottomSheet(pdfUrl, typePDF, siri);
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = '${typePDF}_$siri.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (!file.existsSync()) {
        await Dio().download(pdfUrl, filePath);
      }

      if (!mounted) return;
      _showPdfBottomSheet(pdfUrl, typePDF, siri, filePath: filePath);
    } catch (e) {
      _snack('Gagal muat turun: $e', err: true);
    }
  }

  void _showPdfBottomSheet(String pdfUrl, String typePDF, String siri,
      {String? filePath}) {
    final fileName = '${typePDF}_$siri.pdf';
    final typeColor = typePDF == 'INVOICE'
        ? AppColors.green
        : typePDF == 'CLAIM'
            ? AppColors.orange
            : AppColors.yellow;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            FaIcon(FontAwesomeIcons.filePdf, size: 14, color: typeColor),
            const SizedBox(width: 8),
            Expanded(
                child: Text('$typePDF #$siri',
                    style: TextStyle(
                        color: typeColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900))),
            GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: const FaIcon(FontAwesomeIcons.xmark,
                    size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderMed)),
            child: Row(children: [
              FaIcon(FontAwesomeIcons.circleCheck,
                  size: 24, color: typeColor),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('$typePDF SEDIA',
                        style: TextStyle(
                            color: typeColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w900)),
                    Text(fileName,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ])),
            ]),
          ),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (kIsWeb) {
                    launchUrl(Uri.parse(pdfUrl),
                        mode: LaunchMode.externalApplication);
                  } else if (filePath != null) {
                    OpenFilex.open(filePath);
                  }
                },
                icon:
                    const FaIcon(FontAwesomeIcons.fileCircleCheck, size: 14),
                label: Text(_lang.get('buka_print_pdf')),
                style: ElevatedButton.styleFrom(
                    backgroundColor: typeColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13)),
              )),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pdfUrl));
                _snack('Link PDF disalin!');
              },
              icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
              label: Text(_lang.get('salin_link')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellow,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            )),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton.icon(
              onPressed: () {
                final msg =
                    Uri.encodeComponent('$typePDF #$siri\n$pdfUrl');
                launchUrl(Uri.parse('https://wa.me/?text=$msg'),
                    mode: LaunchMode.externalApplication);
              },
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 12),
              label: Text(_lang.get('hantar_wa')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            )),
          ]),
        ]),
      ),
    );
  }

  // -------------------------------------------------------
  // CAMERA - AFTER REPAIR PHOTOS
  // -------------------------------------------------------
  Future<void> _showCameraModal(Map<String, dynamic> job, StateSetter setS) async {
    final siri = job['siri'] ?? '';
    String? selepasDepan = job['img_selepas_depan']?.toString();
    String? selepasBelakang = job['img_selepas_belakang']?.toString();
    String? serahanCust = job['img_serahan_cust']?.toString();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setCam) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.camera,
                  size: 14, color: AppColors.cyan),
              const SizedBox(width: 8),
              Text(_lang.get('sj_gambar_selepas'),
                  style: const TextStyle(
                      color: AppColors.cyan,
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
                  child: _cameraCard('DEPAN', selepasDepan, () async {
                final img = await _captureAndUpload(siri, 'selepas_depan');
                if (img != null) setCam(() => selepasDepan = img);
              })),
              const SizedBox(width: 8),
              Expanded(
                  child: _cameraCard('BELAKANG', selepasBelakang, () async {
                final img = await _captureAndUpload(siri, 'selepas_belakang');
                if (img != null) setCam(() => selepasBelakang = img);
              })),
              const SizedBox(width: 8),
              Expanded(
                  child: _cameraCard('SERAHAN', serahanCust, () async {
                final img = await _captureAndUpload(siri, 'serahan_cust');
                if (img != null) setCam(() => serahanCust = img);
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
                )),
          ]),
        ),
      ),
    );
  }

  Widget _cameraCard(String label, String? imgUrl, VoidCallback onTap) {
    final hasImage = imgUrl != null && imgUrl.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasImage
                    ? AppColors.green.withValues(alpha: 0.5)
                    : AppColors.border)),
        child: hasImage
            ? Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: imgUrl.startsWith('data:')
                        ? Image.memory(
                            base64Decode(imgUrl.split(',').last),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity)
                        : Image.network(imgUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity)),
                Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(label,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 8,
                                fontWeight: FontWeight.w900)))),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const FaIcon(FontAwesomeIcons.camera,
                    size: 20, color: AppColors.textDim),
                const SizedBox(height: 6),
                Text(label,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ]),
      ),
    );
  }

  Future<String?> _captureAndUpload(String siri, String jenis) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 480,
          maxHeight: 480,
          imageQuality: 25);
      if (file == null) return null;

      _snack('Memuat naik gambar $jenis...');
      final bytes = await File(file.path).readAsBytes();
      final ref = FirebaseStorage.instance
          .ref('repairs/$_ownerID/$siri/img_$jenis.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      // Save URL to Firestore
      await _db
          .collection('repairs_$_ownerID')
          .doc(siri)
          .update({'img_$jenis': url});
      _snack('Gambar $jenis berjaya dimuat naik');
      return url;
    } catch (e) {
      _snack('Gagal muat naik: $e', err: true);
      return null;
    }
  }

  // -------------------------------------------------------
  // ADMIN UNLOCK
  // -------------------------------------------------------
  // -------------------------------------------------------
  // FULL EDIT MODAL (ACTION MODAL)
  // -------------------------------------------------------
  void _showEditModal(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '';
    final originalStatus = (job['status'] ?? 'IN PROGRESS').toString();
    String status = originalStatus;
    String paymentStatus = (job['payment_status'] ?? 'UNPAID').toString();
    String caraBayaran = (job['cara_bayaran'] ?? 'CASH').toString();
    String staffBaiki = (job['staff_repair'] ?? '').toString();
    String staffSerah = (job['staff_serah'] ?? '').toString();
    String catatan = (job['catatan'] ?? '').toString();
    double tambahan =
        double.tryParse(job['tambahan']?.toString() ?? '0') ?? 0;
    double diskaun =
        double.tryParse(job['diskaun']?.toString() ?? '0') ?? 0;
    double deposit =
        double.tryParse(job['deposit']?.toString() ?? '0') ?? 0;
    double voucherAmt =
        double.tryParse(job['voucher_used_amt']?.toString() ?? '0') ?? 0;
    String tSiap = (job['tarikh_siap'] ?? '').toString();
    String tPickup = (job['tarikh_pickup'] ?? '').toString();

    // Status history
    List<Map<String, dynamic>> statusHistory = [];
    if (job['status_history'] is List) {
      statusHistory = (job['status_history'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    // Fallback: jika status_history kosong, inject entry asal guna tarikh/timestamp job
    if (statusHistory.isEmpty) {
      String fallbackTs = '';
      if (job['tarikh'] != null && job['tarikh'].toString().isNotEmpty) {
        fallbackTs = job['tarikh'].toString();
      } else if (job['timestamp'] != null) {
        final ms = int.tryParse(job['timestamp'].toString());
        if (ms != null) {
          fallbackTs = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.fromMillisecondsSinceEpoch(ms));
        }
      }
      if (fallbackTs.isNotEmpty) {
        statusHistory.add({'status': job['status'] ?? 'IN PROGRESS', 'timestamp': fallbackTs});
      }
    }

    // Items
    List<Map<String, dynamic>> items = [];
    if (job['items_array'] is List &&
        (job['items_array'] as List).isNotEmpty) {
      items = (job['items_array'] as List)
          .map((i) => Map<String, dynamic>.from(i as Map))
          .toList();
    } else {
      items = [
        {
          'nama': job['kerosakan'] ?? '',
          'qty': 1,
          'harga':
              double.tryParse(job['harga']?.toString() ?? '0') ?? 0
        }
      ];
    }

    double calcHarga() => items.fold(
        0.0, (s, i) => s + ((i['qty'] ?? 1) as num) * ((i['harga'] ?? 0) as num));
    double calcTotal() =>
        calcHarga() + tambahan - diskaun - deposit - voucherAmt;

    final catatanCtrl = TextEditingController(text: catatan);
    final tambahanCtrl = TextEditingController(
        text: tambahan > 0 ? tambahan.toStringAsFixed(2) : '');
    final diskaunCtrl = TextEditingController(
        text: diskaun > 0 ? diskaun.toStringAsFixed(2) : '');
    final depositCtrl = TextEditingController(
        text: deposit > 0 ? deposit.toStringAsFixed(2) : '');
    final voucherCode = (job['voucher_used'] ?? '').toString();
    bool itemsEditing = false;
    bool catatanEditing = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          const editable = true;

          return DraggableScrollableSheet(
            initialChildSize: 0.92,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (_, scroll) => AbsorbPointer(
              absorbing: false,
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              const FaIcon(FontAwesomeIcons.penToSquare,
                                  size: 14, color: AppColors.blue),
                              const SizedBox(width: 8),
                              Text('${_lang.get('kemaskini')} ',
                                  style: const TextStyle(
                                      color: AppColors.blue,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900)),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color:
                                          AppColors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppColors.blue
                                              .withValues(alpha: 0.2))),
                                  child: Text('#$siri',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900))),
                            ]),
                            GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: const FaIcon(FontAwesomeIcons.xmark,
                                    size: 16, color: AppColors.red)),
                          ]),
                      const SizedBox(height: 4),
                      Text(
                          '${job['nama'] ?? '-'} | ${job['model'] ?? '-'}',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),

                      // Password/Pattern indicator — shown on Android/Web, hidden on iOS (Apple compliance)
                      if (job['password'] != null &&
                          job['password'].toString().isNotEmpty &&
                          job['password'].toString() != 'Tiada' &&
                          (kIsWeb || !Platform.isIOS))
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              const FaIcon(FontAwesomeIcons.lock,
                                  size: 9, color: AppColors.yellow),
                              const SizedBox(width: 4),
                              Text('Password: ${job['password']}',
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ])),

                      // Voucher info display
                      if (job['voucher_used'] != null &&
                          job['voucher_used'].toString().isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(children: [
                              const FaIcon(FontAwesomeIcons.ticket,
                                  size: 9, color: AppColors.textDim),
                              const SizedBox(width: 4),
                              Text(
                                  'Voucher: ${job['voucher_used']} (-RM${voucherAmt.toStringAsFixed(2)})',
                                  style: const TextStyle(
                                      color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                            ])),


                      const Divider(color: AppColors.borderMed, height: 20),

                      // --- STATUS & HISTORY ---
                      Opacity(
                        opacity: 1.0,
                        child: AbsorbPointer(
                          absorbing: false,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(child: _editLabel('Status Baiki')),
                                  GestureDetector(
                                    onTap: () => _showStatusHistory(job, liveHistory: statusHistory),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        margin: const EdgeInsets.only(bottom: 4),
                                        decoration: BoxDecoration(
                                            color: AppColors.blue.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                                color: AppColors.blue.withValues(alpha: 0.3))),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const FaIcon(FontAwesomeIcons.clockRotateLeft,
                                                  size: 9, color: AppColors.blue),
                                              const SizedBox(width: 4),
                                              Text(_lang.get('sj_history'),
                                                  style: const TextStyle(
                                                      color: AppColors.blue,
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.w900)),
                                            ])),
                                  ),
                                ]),
                                _editStatusDropdown(status, (v) {
                                  final newStatus = v!;
                                  final statusOrder = {
                                    'IN PROGRESS': 0, 'WAITING PART': 1,
                                    'READY TO PICKUP': 2, 'COMPLETED': 3,
                                    'CANCEL': 4, 'REJECT': 5
                                  };
                                  final oldLevel = statusOrder[status] ?? 0;
                                  final newLevel = statusOrder[newStatus] ?? 0;

                                  // Confirm with reason for IN PROGRESS (revert), CANCEL, REJECT
                                  final needsConfirm =
                                      (newStatus == 'IN PROGRESS' && oldLevel > newLevel) ||
                                      newStatus == 'CANCEL' ||
                                      newStatus == 'REJECT';

                                  if (needsConfirm) {
                                    _showRevertConfirm(
                                      newStatus,
                                      showStaffPicker: true,
                                      staffList: _staffList,
                                      onConfirm: (reason, staff) {
                                        setS(() {
                                          status = newStatus;
                                          final now = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now());
                                          final entry = <String, dynamic>{
                                            'status': status,
                                            'timestamp': now,
                                            'reason': reason,
                                          };
                                          if (staff != null && staff.isNotEmpty) {
                                            entry['staff'] = staff;
                                          }
                                          statusHistory.add(entry);
                                        });
                                      },
                                    );
                                    return;
                                  }

                                  setS(() {
                                    status = newStatus;
                                    final now = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now());
                                    statusHistory.add({'status': status, 'timestamp': now});
                                    if (status == 'READY TO PICKUP' && tSiap.isEmpty) {
                                      tSiap = now;
                                    }
                                    if (status == 'COMPLETED') {
                                      if (tSiap.isEmpty) tSiap = now;
                                      tPickup = now;
                                    }
                                  });
                                }),
                                const SizedBox(height: 14),

                                // --- ITEMS (readonly default, toggle edit) ---
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                      color: AppColors.blue.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppColors.blue.withValues(alpha: 0.1))),
                                  child: Column(children: [
                                    Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                      Row(children: [
                                        const FaIcon(FontAwesomeIcons.screwdriverWrench,
                                            size: 10, color: AppColors.blue),
                                        const SizedBox(width: 6),
                                        Text(_lang.get('sj_item_kerosakan'),
                                            style: const TextStyle(
                                                color: AppColors.blue,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900)),
                                      ]),
                                      Row(children: [
                                        GestureDetector(
                                          onTap: () => setS(() => itemsEditing = !itemsEditing),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: itemsEditing
                                                    ? AppColors.blue.withValues(alpha: 0.1)
                                                    : AppColors.border,
                                                borderRadius: BorderRadius.circular(6)),
                                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                                              FaIcon(
                                                  itemsEditing ? FontAwesomeIcons.xmark : FontAwesomeIcons.penToSquare,
                                                  size: 8,
                                                  color: itemsEditing ? AppColors.blue : AppColors.textDim),
                                              const SizedBox(width: 4),
                                              Text(itemsEditing ? 'Tutup' : 'Edit',
                                                  style: TextStyle(
                                                      color: itemsEditing ? AppColors.blue : AppColors.textDim,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w900)),
                                            ]),
                                          ),
                                        ),
                                        if (itemsEditing) ...[
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => setS(() => items.add({
                                                  'nama': '',
                                                  'qty': 1,
                                                  'harga': 0.0
                                                })),
                                            child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                    color: AppColors.blue,
                                                    borderRadius: BorderRadius.circular(6)),
                                                child: const Text('+',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w900))),
                                          ),
                                        ],
                                      ]),
                                    ]),
                                    const SizedBox(height: 8),
                                    if (itemsEditing)
                                      ...List.generate(items.length,
                                          (i) => _buildEditItem(items, i, setS))
                                    else
                                      ...items.map((item) => Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppColors.border)),
                                        child: Row(children: [
                                          Expanded(
                                              child: Text(
                                                  '${item['nama'] ?? '-'}  x${item['qty'] ?? 1}',
                                                  style: const TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold))),
                                          Text('RM ${((item['harga'] ?? 0) as num).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900)),
                                        ]),
                                      )),
                                  ]),
                                ),

                                // --- KEWANGAN ---
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                      color: AppColors.yellow
                                          .withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppColors.yellow
                                              .withValues(alpha: 0.1))),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          const FaIcon(FontAwesomeIcons.wallet,
                                              size: 10,
                                              color: AppColors.yellow),
                                          const SizedBox(width: 6),
                                          Text(_lang.get('sj_kewangan'),
                                              style: const TextStyle(
                                                  color: AppColors.yellow,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900)),
                                        ]),
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          Expanded(
                                              child: _editNumField(
                                                  'Asal (RM)',
                                                  calcHarga()
                                                      .toStringAsFixed(2),
                                                  readOnly: true)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                              child: _editNumFieldCtrl(
                                                  'Tambahan',
                                                  tambahanCtrl,
                                                  () => setS(() =>
                                                      tambahan =
                                                          double.tryParse(
                                                                  tambahanCtrl
                                                                      .text) ??
                                                              0))),
                                          const SizedBox(width: 6),
                                          Expanded(
                                              child: _editNumFieldCtrl(
                                                  'Diskaun',
                                                  diskaunCtrl,
                                                  () => setS(() =>
                                                      diskaun =
                                                          double.tryParse(
                                                                  diskaunCtrl
                                                                      .text) ??
                                                              0))),
                                          const SizedBox(width: 6),
                                          Expanded(
                                              child: _editNumFieldCtrl(
                                                  'Deposit',
                                                  depositCtrl,
                                                  () => setS(() =>
                                                      deposit =
                                                          double.tryParse(
                                                                  depositCtrl
                                                                      .text) ??
                                                              0))),
                                        ]),
                                        // Voucher display (readonly - key in di mod repair)
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                              color: AppColors.border,
                                              borderRadius: BorderRadius.circular(6)),
                                          child: Row(children: [
                                            const FaIcon(FontAwesomeIcons.ticket,
                                                size: 9, color: AppColors.textDim),
                                            const SizedBox(width: 6),
                                            Text(
                                                voucherCode.isNotEmpty ? voucherCode : 'Tiada voucher',
                                                style: TextStyle(
                                                    color: voucherCode.isNotEmpty ? Colors.black54 : Colors.black26,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold)),
                                            const Spacer(),
                                            if (voucherAmt > 0)
                                              Text('-RM${voucherAmt.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w900)),
                                          ]),
                                        ),
                                        const SizedBox(height: 10),
                                        // Total
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.05),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: AppColors.primary
                                                      .withValues(
                                                          alpha: 0.3))),
                                          child: Text(
                                              'RM ${calcTotal().toStringAsFixed(2)}',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900)),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                _editLabel('Status Bayaran'),
                                                _editDropdown(
                                                    paymentStatus,
                                                    [
                                                      'UNPAID',
                                                      'PAID',
                                                      'CREDIT'
                                                    ],
                                                    (v) => setS(() =>
                                                        paymentStatus = v!)),
                                              ])),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                _editLabel('Cara Bayaran'),
                                                _editDropdown(
                                                    caraBayaran,
                                                    [
                                                      'CASH',
                                                      'QR',
                                                      'PAYWAVE',
                                                      'TRANSFER'
                                                    ],
                                                    (v) => setS(() =>
                                                        caraBayaran = v!)),
                                              ])),
                                        ]),
                                      ]),
                                ),

                                // --- STAFF (1 baris: Terima | Baiki | Serah) ---
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                        _editLabel('Terima'),
                                        Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            height: 48,
                                            alignment: Alignment.centerLeft,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.grey.shade300)),
                                            child: Text(job['staff_terima'] ?? '-',
                                                style: const TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold))),
                                      ])),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                        _editLabel('Baiki'),
                                        _editDropdown(
                                            staffBaiki.isEmpty ? '' : staffBaiki,
                                            ['', ..._staffList],
                                            (v) => setS(() => staffBaiki = v ?? '')),
                                      ])),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                        _editLabel('Serah'),
                                        _editDropdown(
                                            staffSerah.isEmpty ? '' : staffSerah,
                                            ['', ..._staffList],
                                            (v) => setS(() => staffSerah = v ?? '')),
                                      ])),
                                ]),
                                const SizedBox(height: 12),

                                // --- CATATAN (readonly by default, edit toggle) ---
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    _editLabel('Catatan / Nota Staf'),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => setS(() => catatanEditing = !catatanEditing),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                            color: catatanEditing
                                                ? AppColors.cyan.withValues(alpha: 0.1)
                                                : AppColors.border,
                                            borderRadius: BorderRadius.circular(6)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          FaIcon(
                                              catatanEditing ? FontAwesomeIcons.xmark : FontAwesomeIcons.penToSquare,
                                              size: 8,
                                              color: catatanEditing ? AppColors.cyan : AppColors.textDim),
                                          const SizedBox(width: 4),
                                          Text(catatanEditing ? 'Tutup' : 'Edit',
                                              style: TextStyle(
                                                  color: catatanEditing ? AppColors.cyan : AppColors.textDim,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900)),
                                        ]),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 4),
                                  if (catatanEditing)
                                    Row(children: [
                                      Expanded(child: _editInput(catatanCtrl, 'Nota dalaman...')),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () async {
                                          await _db
                                              .collection('repairs_$_ownerID')
                                              .doc(siri)
                                              .update({'catatan': catatanCtrl.text});
                                          setS(() => catatanEditing = false);
                                          _snack('Catatan disimpan!');
                                        },
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                            decoration: BoxDecoration(
                                                color: AppColors.cyan,
                                                borderRadius: BorderRadius.circular(8)),
                                            child: const FaIcon(FontAwesomeIcons.floppyDisk,
                                                size: 14, color: Colors.white)),
                                      ),
                                    ])
                                  else
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                          color: AppColors.border,
                                          borderRadius: BorderRadius.circular(8)),
                                      child: Text(
                                          catatan.isNotEmpty ? catatan : 'Tiada catatan',
                                          style: TextStyle(
                                              color: catatan.isNotEmpty ? Colors.black : Colors.black38,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                ]),
                                const SizedBox(height: 10),

                                // --- WARRANTY (auto dari setting gear) ---
                                if (_warrantyRules.isNotEmpty) ...[
                                  Builder(builder: (_) {
                                    final readyDate = _getLatestReadyDate(statusHistory);
                                    final wItems = _calcWarrantyItems(items, readyDate);
                                    if (wItems.isEmpty) {
                                      return Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        margin: const EdgeInsets.only(bottom: 14),
                                        decoration: BoxDecoration(
                                            color: AppColors.border.withValues(alpha: 0.3),
                                            borderRadius: BorderRadius.circular(8)),
                                        child: Row(children: [
                                          const FaIcon(FontAwesomeIcons.shieldHalved,
                                              size: 10, color: AppColors.textDim),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                              child: Text('Warranty: Tiada item sepadan dengan tetapan warranty',
                                                  style: TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold))),
                                        ]),
                                      );
                                    }
                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      margin: const EdgeInsets.only(bottom: 14),
                                      decoration: BoxDecoration(
                                          color: AppColors.yellow.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                              color: AppColors.yellow.withValues(alpha: 0.15))),
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              const FaIcon(FontAwesomeIcons.shieldHalved,
                                                  size: 10, color: AppColors.yellow),
                                              const SizedBox(width: 6),
                                              const Text('Warranty (Auto)',
                                                  style: TextStyle(
                                                      color: AppColors.yellow,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w900)),
                                              const Spacer(),
                                              Text(
                                                  readyDate.isEmpty
                                                      ? 'Bermula dari READY TO PICKUP'
                                                      : 'Dari: ${readyDate.replaceAll('T', ' ')}',
                                                  style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold)),
                                            ]),
                                            const SizedBox(height: 6),
                                            ...wItems.map((w) => Padding(
                                                padding: const EdgeInsets.only(top: 3),
                                                child: Row(children: [
                                                  const FaIcon(FontAwesomeIcons.circleCheck,
                                                      size: 8, color: AppColors.green),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                      child: Text(
                                                          '${w['nama']}  →  ${w['warranty']}',
                                                          style: const TextStyle(
                                                              color: Colors.black,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold))),
                                                  Text(
                                                      readyDate.isNotEmpty
                                                          ? 'Tamat: ${w['warranty_exp']}'
                                                          : '-',
                                                      style: const TextStyle(
                                                          color: Colors.black54,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold)),
                                                ]))),
                                          ]),
                                    );
                                  }),
                                ],
                                const SizedBox(height: 14),

                                // --- CAMERA BUTTON ---
                                if (_branchSettings['hasGalleryAddon'] ==
                                    true) ...[
                                  GestureDetector(
                                    onTap: () =>
                                        _showCameraModal(job, setS),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      margin:
                                          const EdgeInsets.only(bottom: 14),
                                      decoration: BoxDecoration(
                                          color: AppColors.cyan
                                              .withValues(alpha: 0.05),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: AppColors.cyan
                                                  .withValues(alpha: 0.25))),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const FaIcon(
                                                FontAwesomeIcons.camera,
                                                size: 14,
                                                color: AppColors.cyan),
                                            const SizedBox(width: 10),
                                            Text(
                                                '${_lang.get('sj_gambar_selepas')}'
                                                    '${job['img_selepas_depan'] != null || job['img_selepas_belakang'] != null ? ' (ADA)' : ''}',
                                                style: const TextStyle(
                                                    color: AppColors.cyan,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w900)),
                                          ]),
                                    ),
                                  ),
                                ],
                              ]),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // --- SAVE BUTTON ---
                      SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (editable && !isSaving)
                                ? () async {
                                    setS(() => isSaving = true);
                                    try {
                                      final itemsArr = items
                                          .where((i) =>
                                              (i['nama'] ?? '')
                                                  .toString()
                                                  .isNotEmpty)
                                          .map((i) => {
                                                'nama': i['nama'],
                                                'qty': i['qty'] ?? 1,
                                                'harga': i['harga'] ?? 0
                                              })
                                          .toList();
                                      final kerosakan = itemsArr
                                          .map((i) =>
                                              '${i['nama']} (x${i['qty']})')
                                          .join(', ');
                                      // Auto-calc warranty from rules
                                      final readyDate = _getLatestReadyDate(statusHistory);
                                      final wItems = _calcWarrantyItems(items, readyDate);
                                      String warrantySummary = 'TIADA';
                                      String warrantyExp = '';
                                      if (wItems.isNotEmpty) {
                                        warrantySummary = wItems
                                            .map((w) => '${w['nama']}: ${w['warranty']}')
                                            .join(', ');
                                        // Latest expiry for backward compat
                                        warrantyExp = wItems
                                            .map((w) => (w['warranty_exp'] ?? '').toString())
                                            .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
                                      }

                                      final updateData = <String, dynamic>{
                                        'status': status,
                                        'payment_status': paymentStatus,
                                        'cara_bayaran': caraBayaran,
                                        'staff_repair': staffBaiki,
                                        'staff_serah': staffSerah,
                                        'catatan': catatanCtrl.text,
                                        'warranty': warrantySummary,
                                        'warranty_exp': warrantyExp,
                                        'warranty_items': wItems,
                                        'items_array': itemsArr,
                                        'kerosakan': kerosakan,
                                        'harga':
                                            calcHarga().toStringAsFixed(2),
                                        'tambahan':
                                            tambahan.toStringAsFixed(2),
                                        'diskaun':
                                            diskaun.toStringAsFixed(2),
                                        'deposit':
                                            deposit.toStringAsFixed(2),
                                        'total':
                                            calcTotal().toStringAsFixed(2),
                                        'baki':
                                            calcTotal().toStringAsFixed(2),
                                      };

                                      if (paymentStatus == 'PAID') {
                                        updateData['paid_at'] =
                                            DateTime.now().millisecondsSinceEpoch;
                                      }

                                      if (tSiap.isNotEmpty) {
                                        updateData['tarikh_siap'] = tSiap;
                                      }
                                      if (tPickup.isNotEmpty) {
                                        updateData['tarikh_pickup'] = tPickup;
                                      }
                                      updateData['status_history'] = statusHistory;

                                      await _db
                                          .collection('repairs_$_ownerID')
                                          .doc(siri)
                                          .update(updateData);

                                      // Inventory deduction on READY TO PICKUP / COMPLETED
                                      if ((status == 'READY TO PICKUP' ||
                                              status == 'COMPLETED') &&
                                          originalStatus != 'READY TO PICKUP' &&
                                          originalStatus != 'COMPLETED') {
                                        await _deductInventory(itemsArr);
                                      }

                                      // Inventory reversal on CANCEL
                                      if (status == 'CANCEL' &&
                                          originalStatus != 'CANCEL' &&
                                          (originalStatus ==
                                                  'READY TO PICKUP' ||
                                              originalStatus == 'COMPLETED')) {
                                        await _reverseInventory(itemsArr);
                                      }

                                      // Create kewangan record when PAID
                                      if (paymentStatus == 'PAID') {
                                        // Re-read job with updated total
                                        final updatedJob =
                                            Map<String, dynamic>.from(job);
                                        updatedJob['total'] =
                                            calcTotal().toStringAsFixed(2);
                                        updatedJob['cara_bayaran'] =
                                            caraBayaran;
                                        updatedJob['staff_repair'] =
                                            staffBaiki;
                                        await _createKewanganRecord(
                                            updatedJob);
                                      }

                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _snack(
                                          'Tiket #$siri berjaya dikemaskini');
                                    } catch (e) {
                                      _snack('Ralat: $e', err: true);
                                    } finally {
                                      if (ctx.mounted) {
                                        setS(() => isSaving = false);
                                      }
                                    }
                                  }
                                : null,
                            icon: isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const FaIcon(FontAwesomeIcons.floppyDisk,
                                    size: 14),
                            label: Text(isSaving
                                ? 'MENYIMPAN...'
                                : 'SIMPAN KEMASKINI'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.green,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16)),
                          )),



                      const SizedBox(height: 30),
                    ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditItem(
      List<Map<String, dynamic>> items, int i, StateSetter setS) {
    final item = items[i];
    final namaCtrl =
        TextEditingController(text: (item['nama'] ?? '').toString());
    final hargaCtrl = TextEditingController(
        text: ((item['harga'] ?? 0) as num).toDouble() > 0
            ? ((item['harga'] ?? 0) as num).toStringAsFixed(2)
            : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Expanded(
            flex: 3,
            child: Autocomplete<Map<String, dynamic>>(
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
              onSelected: (o) => setS(() {
                item['nama'] = o['nama'];
                item['harga'] = (o['jual'] as num?)?.toDouble() ?? 0;
              }),
              fieldViewBuilder: (_, ctrl2, fn, _) {
                if (ctrl2.text.isEmpty && namaCtrl.text.isNotEmpty) {
                  ctrl2.text = namaCtrl.text;
                }
                return _rawField(ctrl2, fn, 'Item...',
                    onChanged: (v) => item['nama'] = v);
              },
              optionsViewBuilder: (_, onSel, opts) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxHeight: 180, maxWidth: 280),
                          child: ListView(
                              shrinkWrap: true,
                              children: opts
                                  .map((o) => InkWell(
                                      onTap: () => onSel(o),
                                      child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    o['kod']?.toString() ?? '',
                                                    style: const TextStyle(
                                                        color:
                                                            Colors.black,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Text(
                                                    o['nama']?.toString() ?? '',
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold)),
                                                Text(
                                                    'RM ${(o['jual'] as num?)?.toStringAsFixed(2) ?? '0'} (Stok: ${o['qty']})',
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ]))))
                                  .toList())))),
            )),
        const SizedBox(width: 6),
        SizedBox(
            width: 45,
            child: _rawField(
                TextEditingController(text: '${item['qty'] ?? 1}'), null, 'Qty',
                keyboard: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) =>
                    setS(() => item['qty'] = int.tryParse(v) ?? 1))),
        const SizedBox(width: 6),
        SizedBox(
            width: 70,
            child: _rawField(hargaCtrl, null, 'RM',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) =>
                    setS(() => item['harga'] = double.tryParse(v) ?? 0))),
        const SizedBox(width: 6),
        GestureDetector(
          onTap:
              items.length > 1 ? () => setS(() => items.removeAt(i)) : null,
          child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6)),
              child: const Center(
                  child: FaIcon(FontAwesomeIcons.trash,
                      size: 10, color: AppColors.red))),
        ),
      ]),
    );
  }

  // -------------------------------------------------------
  // REVERT STATUS CONFIRM DIALOG
  void _showRevertConfirm(
    String newStatus, {
    bool showStaffPicker = false,
    List<String> staffList = const [],
    required void Function(String reason, String? staff) onConfirm,
  }) {
    final reasonCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String? selectedStaff;
    bool pinVerified = false;
    String pinError = '';
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade300)),
          title: Row(children: [
            const FaIcon(FontAwesomeIcons.triangleExclamation,
                size: 14, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${_lang.get('sj_tukar_status')} $newStatus?',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Adakah anda pasti ingin tukar kepada $newStatus?',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (showStaffPicker && staffList.isNotEmpty) ...[
              // Staff dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedStaff,
                    hint: Text(_lang.get('sj_pilih_staff'),
                        style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                    items: staffList
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setD(() {
                      selectedStaff = v;
                      pinVerified = false;
                      pinCtrl.clear();
                      pinError = '';
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // PIN field
              if (selectedStaff != null) ...[
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                      hintText: 'Masukkan PIN staff...',
                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      prefixIcon: Icon(
                          pinVerified ? Icons.check_circle : Icons.lock,
                          size: 16,
                          color: pinVerified ? Colors.green : Colors.grey),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: pinError.isNotEmpty ? Colors.red : Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: pinError.isNotEmpty ? Colors.red : Colors.grey.shade300))),
                  onChanged: (val) {
                    // Auto-verify PIN
                    final staffData = _staffRawList.firstWhere(
                        (s) => (s['name'] ?? s['nama'] ?? '').toString() == selectedStaff,
                        orElse: () => <String, dynamic>{});
                    final correctPin = (staffData['pin'] ?? '').toString();
                    if (correctPin.isNotEmpty && val == correctPin) {
                      setD(() {
                        pinVerified = true;
                        pinError = '';
                      });
                    } else {
                      setD(() {
                        pinVerified = false;
                        pinError = '';
                      });
                    }
                  },
                ),
                if (pinError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(pinError,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 10),
              ],
            ],
            // Reason field
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              style: const TextStyle(
                  color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                  hintText: 'Masukkan sebab / reason...',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300))),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_lang.get('batal'),
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
            ElevatedButton(
              onPressed: () {
                if (showStaffPicker && staffList.isNotEmpty && (selectedStaff == null || selectedStaff!.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_lang.get('sj_sila_pilih_staff')),
                      backgroundColor: Colors.red));
                  return;
                }
                if (showStaffPicker && staffList.isNotEmpty && !pinVerified) {
                  setD(() => pinError = 'PIN salah! Sila masukkan PIN yang betul.');
                  return;
                }
                if (reasonCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_lang.get('sj_sila_masuk_sebab')),
                      backgroundColor: Colors.red));
                  return;
                }
                Navigator.pop(ctx);
                onConfirm(reasonCtrl.text.trim(), selectedStaff);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
              child: Text(_lang.get('sj_ya_tukar')),
            ),
          ],
        ),
      ),
    );
  }

  // EDIT HELPER WIDGETS
  // -------------------------------------------------------
  Widget _editStatusDropdown(String current, ValueChanged<String?> onC) {
    final allStatuses = [
      'IN PROGRESS',
      'WAITING PART',
      'READY TO PICKUP',
      'COMPLETED',
      'CANCEL',
      'REJECT'
    ];
    final statusOrder = {
      'IN PROGRESS': 0,
      'WAITING PART': 1,
      'READY TO PICKUP': 2,
      'COMPLETED': 3,
      'CANCEL': 4,
      'REJECT': 5
    };
    final currentLevel = statusOrder[current] ?? 0;

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
                value: allStatuses.contains(current)
                    ? current
                    : allStatuses.first,
                isExpanded: true,
                dropdownColor: Colors.white,
                selectedItemBuilder: (context) {
                  return allStatuses.map((s) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(s,
                          style: TextStyle(
                              color: _statusColor(s),
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    );
                  }).toList();
                },
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
                items: allStatuses.map((s) {
                  final sLevel = statusOrder[s] ?? 0;
                  // Allow IN PROGRESS even if going backwards
                  final isPast = sLevel < currentLevel &&
                      s != 'CANCEL' &&
                      s != 'REJECT' &&
                      s != 'IN PROGRESS';
                  return DropdownMenuItem(
                      value: s,
                      enabled: !isPast,
                      child: Text(s,
                          style: TextStyle(
                              color: isPast
                                  ? AppColors.textDim
                                  : _statusColor(s),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              decoration: isPast
                                  ? TextDecoration.lineThrough
                                  : null)));
                }).toList(),
                onChanged: onC)));
  }

  Widget _editLabel(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(t,
          style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5)));

  Widget _editDropdown(
      String val, List<String> opts, ValueChanged<String?> onC) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
                value: opts.contains(val) ? val : opts.first,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
                items: opts
                    .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o.isEmpty ? '- PILIH -' : o)))
                    .toList(),
                onChanged: onC)));
  }

  Widget _editInput(TextEditingController c, String h) => TextField(
      controller: c,
      style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
          hintText: h,
          hintStyle:
              TextStyle(color: Colors.grey.shade600, fontSize: 11),
          filled: true,
          fillColor: Colors.grey.shade100,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300))));

  Widget _editNumField(String label, String val, {bool readOnly = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _editLabel(label),
        Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            width: double.infinity,
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)),
            child: Text(val,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)))
      ]);

  Widget _editNumFieldCtrl(
          String label, TextEditingController c, VoidCallback onC) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _editLabel(label),
        TextField(
            controller: c,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onC(),
            style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
                hintText: '0.00',
                hintStyle:
                    TextStyle(color: Colors.grey.shade600, fontSize: 11),
                filled: true,
                fillColor: Colors.grey.shade100,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.grey.shade300))))
      ]);

  Widget _rawField(TextEditingController c, FocusNode? fn, String h,
      {TextInputType keyboard = TextInputType.text,
      TextAlign textAlign = TextAlign.start,
      ValueChanged<String>? onChanged}) {
    return TextField(
        controller: c,
        focusNode: fn,
        keyboardType: keyboard,
        textAlign: textAlign,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
            hintText: h,
            hintStyle:
                TextStyle(color: Colors.grey.shade600, fontSize: 10),
            filled: true,
            fillColor: Colors.grey.shade100,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: Colors.grey.shade300))));
  }

  // -------------------------------------------------------
  // BUILD - MAIN UI
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        _buildHeader(),
        _buildFilterBar(),
        Expanded(child: _buildJobList()),
        _buildPagination(),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(color: AppColors.card),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.listCheck,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(_lang.get('sj_senarai_job'),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ]),
            Row(children: [
              // CSV Download
              GestureDetector(
                onTap: _downloadCSV,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.green.withValues(alpha: 0.3))),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FaIcon(FontAwesomeIcons.fileExcel,
                            size: 10, color: AppColors.green),
                        const SizedBox(width: 6),
                        Text(_lang.get('sj_csv'),
                            style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 9,
                                fontWeight: FontWeight.w900)),
                      ]),
                ),
              ),
              const SizedBox(width: 6),
              // Warranty Settings Gear
              GestureDetector(
                onTap: _showWarrantySettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.yellow.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                  child: const FaIcon(FontAwesomeIcons.gear, size: 10, color: AppColors.yellow),
                ),
              ),
              const SizedBox(width: 6),
              // Record count
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${_filteredData.length}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ),
            ]),
          ]),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.borderMed))),
      child: Column(children: [
        TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(_applyFilters),
            style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
                hintText: _lang.get('sj_cari_hint'),
                hintStyle:
                    const TextStyle(color: Colors.black54, fontSize: 12),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textMuted, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(() {
                              _searchCtrl.clear();
                              _applyFilters();
                            }),
                        child: const Icon(Icons.close,
                            color: AppColors.textDim, size: 18))
                    : null,
                filled: true,
                fillColor: AppColors.bgDeep,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _filterChip(
                  'Status',
                  _filterStatus,
                  {
                    'ALL': 'Semua',
                    'IN PROGRESS': 'Progress',
                    'WAITING PART': 'Wait Part',
                    'READY TO PICKUP': 'Ready',
                    'COMPLETED': 'Selesai',
                    'CANCEL': 'Batal',
                    'OVERDUE': 'Overdue 30+',
                  },
                  (v) => setState(() {
                        _filterStatus = v;
                        _applyFilters();
                      }))),
          const SizedBox(width: 6),
          Expanded(
              child: _filterChip(
                  'Masa',
                  _specificDate != null
                      ? DateFormat('dd/MM').format(_specificDate!)
                      : _filterTime,
                  {
                    'ALL': 'Semua',
                    'TODAY': 'Hari Ini',
                    'WEEK': 'Minggu',
                    'MONTH': 'Bulan',
                    'PICK': 'Pilih Tarikh',
                  },
                  (v) {
                    if (v == 'PICK') {
                      _pickSpecificDate();
                    } else {
                      setState(() {
                        _filterTime = v;
                        _specificDate = null;
                        _applyFilters();
                      });
                    }
                  })),
          const SizedBox(width: 6),
          Expanded(
              child: _filterChip(
                  'Susun',
                  _filterSort,
                  {
                    'TARIKH_DESC': 'Terbaru',
                    'TARIKH_ASC': 'Terdahulu',
                    'NAMA_ASC': 'Nama A-Z',
                    'NAMA_DESC': 'Nama Z-A',
                  },
                  (v) => setState(() {
                        _filterSort = v;
                        _applyFilters();
                      }))),
        ]),
      ]),
    );
  }

  Future<void> _pickSpecificDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _specificDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030));
    if (d != null) {
      setState(() {
        _specificDate = d;
        _filterTime = 'ALL';
        _applyFilters();
      });
    }
  }

  Widget _filterChip(String label, String sel, Map<String, String> opts,
      ValueChanged<String> onC) {
    return PopupMenuButton<String>(
        onSelected: onC,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderMed)),
            child: Row(children: [
              Expanded(
                  child: Text(opts[sel] ?? sel,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis)),
              const FaIcon(FontAwesomeIcons.chevronDown,
                  size: 8, color: AppColors.textDim),
            ])),
        itemBuilder: (_) => opts.entries
            .map((e) => PopupMenuItem(
                value: e.key,
                child: Text(e.value,
                    style: TextStyle(
                        color:
                            e.key == sel ? AppColors.primary : Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold))))
            .toList());
  }

  Widget _buildJobList() {
    if (!_hasLoadedOnce) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_filteredData.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(FontAwesomeIcons.folderOpen,
            size: 40, color: AppColors.textDim),
        const SizedBox(height: 12),
        Text(_lang.get('sj_tiada_rekod'),
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
      ]));
    }
    return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _pageData.length,
        itemBuilder: (_, i) => _buildJobCard(_pageData[i]));
  }

  void _showStatusHistory(Map<String, dynamic> job, {List<Map<String, dynamic>>? liveHistory}) {
    final siri = job['siri'] ?? '-';
    List<Map<String, dynamic>> history = [];
    if (liveHistory != null) {
      history = liveHistory;
    } else if (job['status_history'] is List) {
      history = (job['status_history'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    // Fallback: jika history kosong, inject entry asal guna tarikh/timestamp job
    if (history.isEmpty) {
      String fallbackTs = '';
      if (job['tarikh'] != null && job['tarikh'].toString().isNotEmpty) {
        fallbackTs = job['tarikh'].toString();
      } else if (job['timestamp'] != null) {
        final ms = int.tryParse(job['timestamp'].toString());
        if (ms != null) {
          fallbackTs = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.fromMillisecondsSinceEpoch(ms));
        }
      }
      if (fallbackTs.isNotEmpty) {
        history.add({'status': job['status'] ?? 'IN PROGRESS', 'timestamp': fallbackTs});
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.clockRotateLeft,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('${_lang.get('sj_status_history')} #$siri',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: const FaIcon(FontAwesomeIcons.xmark,
                    size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(_lang.get('sj_tiada_status'),
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            )
          else
            ...history.asMap().entries.map((e) {
              final i = e.key;
              final h = e.value;
              final st = (h['status'] ?? '').toString();
              final ts = (h['timestamp'] ?? '').toString().replaceAll('T', '  ');
              final reason = (h['reason'] ?? '').toString();
              final staff = (h['staff'] ?? '').toString();
              final color = _statusColor(st.toUpperCase());
              final isLast = i == history.length - 1;
              return IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(children: [
                        Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                        if (!isLast)
                          Expanded(
                              child: Container(
                                  width: 2, color: AppColors.border)),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(st,
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(ts,
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              if (staff.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(children: [
                                  const FaIcon(FontAwesomeIcons.user,
                                      size: 8, color: AppColors.textDim),
                                  const SizedBox(width: 4),
                                  Text(staff,
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ]),
                              ],
                              if (reason.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text('Sebab: $reason',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ]),
                      )),
                    ]),
              );
            }),
        ]),
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '-';
    final nama = job['nama'] ?? '-';
    final tel = job['tel'] ?? '-';
    final model = job['model'] ?? '-';
    final kerosakan = job['kerosakan'] ?? '-';
    final status = (job['status'] ?? 'IN PROGRESS').toString().toUpperCase();
    final payStatus =
        (job['payment_status'] ?? 'UNPAID').toString().toUpperCase();
    final tarikh = _fmt(job['timestamp']);
    final color = _statusColor(status);
    final harga = double.tryParse(
            job['total']?.toString() ?? job['harga']?.toString() ?? '0') ??
        0;
    final days = _overdueDays(job);
    final isOverdue =
        days >= 30 && status != 'COMPLETED' && status != 'CANCEL';

    // Days since READY TO PICKUP
    int readyDays = 0;
    if (status == 'READY TO PICKUP') {
      final tSiap = (job['tarikh_siap'] ?? '').toString();
      if (tSiap.isNotEmpty) {
        final dt = DateTime.tryParse(tSiap);
        if (dt != null) {
          readyDays = DateTime.now().difference(dt).inDays;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Colors.white, AppColors.bg]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderMed),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 12,
                offset: const Offset(5, 5))
          ]),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 3)),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14))),
          child: Column(children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Siri + overdue + print
                  Row(children: [
                    Text('#$siri',
                        style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.w900)),
                    if (isOverdue) ...[
                      const SizedBox(width: 6),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('${days}d',
                              style: const TextStyle(
                                  color: AppColors.red,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900))),
                    ],
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showPrintModal(job),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color:
                                      AppColors.blue.withValues(alpha: 0.3))),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const FaIcon(FontAwesomeIcons.print,
                                    size: 9, color: AppColors.blue),
                                const SizedBox(width: 4),
                                Text(_lang.get('cetak'),
                                    style: const TextStyle(
                                        color: AppColors.blue,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900)),
                              ])),
                    ),
                  ]),
                  // Status badges
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: color.withValues(alpha: 0.4))),
                        child: Text(status,
                            style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w900))),
                    if (status == 'READY TO PICKUP') ...[
                      const SizedBox(width: 4),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                              color: (readyDays >= 30
                                      ? Colors.red
                                      : readyDays >= 25
                                          ? Colors.orange
                                          : const Color(0xFF4CAF50))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: (readyDays >= 30
                                          ? Colors.red
                                          : readyDays >= 25
                                              ? Colors.orange
                                              : const Color(0xFF4CAF50))
                                      .withValues(alpha: 0.4))),
                          child: Text('${readyDays}d',
                              style: TextStyle(
                                  color: readyDays >= 30
                                      ? Colors.red
                                      : readyDays >= 25
                                          ? Colors.orange
                                          : const Color(0xFF4CAF50),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900))),
                    ],
                    const SizedBox(width: 6),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                            color: payStatus == 'PAID'
                                ? AppColors.green.withValues(alpha: 0.15)
                                : AppColors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(payStatus,
                            style: TextStyle(
                                color: payStatus == 'PAID'
                                    ? AppColors.green
                                    : AppColors.red,
                                fontSize: 9,
                                fontWeight: FontWeight.w900))),
                  ]),
                ]),
            const SizedBox(height: 4),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(tarikh,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold))),
          ]),
        ),
        // Body
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: Column(children: [
              _cardRow('Pelanggan', nama, FontAwesomeIcons.user),
              // Telefon with WhatsApp icon
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const FaIcon(FontAwesomeIcons.phone,
                        size: 10, color: AppColors.textDim),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 70,
                        child: Text(_lang.get('sj_telefon'),
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w900))),
                    Expanded(
                        child: Text(tel,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    GestureDetector(
                      onTap: () => _showWhatsAppModal(job),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: const FaIcon(FontAwesomeIcons.whatsapp,
                            size: 20, color: Color(0xFF25D366)),
                      ),
                    ),
                  ])),
              _cardRow('Model', model, FontAwesomeIcons.mobileScreenButton),
              _cardRow(
                  'Kerosakan', kerosakan, FontAwesomeIcons.screwdriverWrench),
              if ((job['password'] ?? '').toString().isNotEmpty &&
                  (job['password'] ?? '').toString() != 'Tiada' &&
                  (kIsWeb || !Platform.isIOS))
                _cardRow('Password', (job['password'] ?? '').toString(),
                    FontAwesomeIcons.lock),
              _cardRow('Jumlah', 'RM ${harga.toStringAsFixed(2)}',
                  FontAwesomeIcons.moneyBill),
            ])),
        // Actions
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(children: [
            _actBtn('Edit', FontAwesomeIcons.penToSquare, AppColors.blue,
                () => _showEditModal(job)),
            const SizedBox(width: 6),
            if (status == 'READY TO PICKUP')
              _actBtn('Selesai', FontAwesomeIcons.circleCheck, AppColors.green,
                  () async {
                final now = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now());
                final existingHistory = (job['status_history'] is List)
                    ? List<Map<String, dynamic>>.from(
                        (job['status_history'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                    : <Map<String, dynamic>>[];
                existingHistory.add({'status': 'COMPLETED', 'timestamp': now});
                await _db
                    .collection('repairs_$_ownerID')
                    .doc(siri)
                    .update({
                  'status': 'COMPLETED',
                  'tarikh_pickup': now,
                  'status_history': existingHistory,
                });
                _snack('Status #$siri -> COMPLETED');
              }),
            const Spacer(),
            _actBtn('Sejarah', FontAwesomeIcons.clockRotateLeft,
                AppColors.textDim, () => _showHistory(job)),
          ]),
        ),
      ]),
    );
  }

  Widget _cardRow(String label, String value, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        FaIcon(icon, size: 10, color: Colors.black54),
        const SizedBox(width: 8),
        SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w900))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis)),
      ]));

  Widget _actBtn(
          String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: color.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(icon, size: 11, color: color),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ])));

  Widget _buildPagination() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.borderMed))),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Page info
            Text(
                'Muka $_currentPage/$_totalPages (${_filteredData.length} rekod)',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            Row(children: [
              // Rows per page selector
              PopupMenuButton<int>(
                onSelected: (v) => setState(() {
                  _rowsPerPage = v;
                  _currentPage = 1;
                }),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderMed)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$_rowsPerPage',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const FaIcon(FontAwesomeIcons.chevronDown,
                          size: 7, color: AppColors.textDim),
                    ])),
                itemBuilder: (_) => [10, 20, 50, 100]
                    .map((n) => PopupMenuItem(
                        value: n,
                        child: Text('$n setiap muka',
                            style: TextStyle(
                                color: n == _rowsPerPage
                                    ? AppColors.primary
                                    : Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))))
                    .toList(),
              ),
              const SizedBox(width: 8),
              // Prev/Next
              IconButton(
                  icon: const FaIcon(FontAwesomeIcons.chevronLeft,
                      size: 12, color: AppColors.textMuted),
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30)),
              IconButton(
                  icon: const FaIcon(FontAwesomeIcons.chevronRight,
                      size: 12, color: AppColors.textMuted),
                  onPressed: _currentPage < _totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30)),
            ]),
          ]));
}
