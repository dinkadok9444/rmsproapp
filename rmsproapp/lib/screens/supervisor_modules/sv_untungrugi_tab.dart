import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../services/printer_service.dart';

const String _cloudRunUrl = 'https://rms-backend-94407896005.asia-southeast1.run.app';

class SvUntungRugiTab extends StatefulWidget {
  final String ownerID, shopID;
  final bool phoneEnabled;
  const SvUntungRugiTab({
    required this.ownerID,
    required this.shopID,
    this.phoneEnabled = true,
  });
  @override
  State<SvUntungRugiTab> createState() => SvUntungRugiTabState();
}

class SvUntungRugiTabState extends State<SvUntungRugiTab> with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _lang = AppLanguage();
  String _filterTime = 'TODAY';
  DateTime? _customStart, _customEnd;

  // === DATA ===
  // Repair & Sparepart
  List<Map<String, dynamic>> _repairIncome = [];
  List<Map<String, dynamic>> _stockUsage = [];
  List<Map<String, dynamic>> _expenseRecords = [];

  // Jualan Telefon
  List<Map<String, dynamic>> _phoneSales = [];

  // Losses (shared)
  List<Map<String, dynamic>> _lossRecords = [];

  // Kewangan - Jualan Pantas
  List<Map<String, dynamic>> _jualanPantasRecords = [];

  // Kewangan detail view
  String _kewanganSection = ''; // '', 'JUALAN', 'EXPENSE'

  final List<StreamSubscription> _subs = [];
  late TabController _segmentCtrl;
  final _printer = PrinterService();
  Map<String, dynamic> _branchSettings = {};

  @override
  void initState() {
    super.initState();
    _segmentCtrl = TabController(length: widget.phoneEnabled ? 3 : 2, vsync: this);
    _segmentCtrl.addListener(() { if (mounted) setState(() {}); });
    _lang.addListener(_onLangChanged);
    _listenAll();
    _loadBranchSettings();
  }

  Future<void> _loadBranchSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    String ownerID = '', shopID = '';
    if (branch.contains('@')) {
      ownerID = branch.split('@')[0];
      shopID = branch.split('@')[1].toUpperCase();
    }
    if (ownerID.isEmpty) return;
    try {
      final doc = await _db.collection('shops_$ownerID').doc(shopID).get();
      if (doc.exists && mounted) {
        setState(() => _branchSettings = doc.data() ?? {});
      }
    } catch (_) {}
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lang.removeListener(_onLangChanged);
    _segmentCtrl.dispose();
    for (final s in _subs) s.cancel();
    super.dispose();
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
      final p = DateTime.tryParse(ts);
      if (p != null) return p.millisecondsSinceEpoch;
    }
    return 0;
  }

  void _listenAll() {
    // 1. Repair income (PAID, bukan JUALAN)
    _subs.add(
      _db.collection('repairs_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          if ((d['payment_status'] ?? '').toString().toUpperCase() != 'PAID') continue;
          final nama = (d['nama'] ?? '').toString().toUpperCase();
          final jenis = (d['jenis_servis'] ?? '').toString().toUpperCase();
          if (nama == 'JUALAN PANTAS' || jenis == 'JUALAN') continue;
          list.add({
            'label': d['nama'] ?? '-',
            'sublabel': '#${d['siri'] ?? '-'}',
            'jumlah': double.tryParse(d['total']?.toString() ?? '0') ?? 0,
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'jenis': 'REPAIR',
          });
        }
        if (mounted) setState(() => _repairIncome = list);
      }),
    );

    // 2. Stock usage (modal sparepart)
    _subs.add(
      _db.collection('stock_usage_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          if ((d['status'] ?? '').toString().toUpperCase() != 'USED') continue;
          list.add({
            'label': d['nama'] ?? d['kod'] ?? '-',
            'sublabel': d['kod'] ?? '-',
            'kos': ((d['kos'] ?? 0) as num).toDouble(),
            'jual': ((d['jual'] ?? 0) as num).toDouble(),
            'timestamp': _dapatkanMasaSah(d['timestamp']),
          });
        }
        if (mounted) setState(() => _stockUsage = list);
      }),
    );

    // 3. Expenses
    _subs.add(
      _db.collection('expenses_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          list.add({
            'label': d['perkara'] ?? '-',
            'sublabel': d['staff'] ?? '-',
            'jumlah': (d['jumlah'] as num?)?.toDouble() ?? 0,
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'jenis': 'EXPENSE',
          });
        }
        if (mounted) setState(() => _expenseRecords = list);
      }),
    );

    // 4. Phone sales
    _subs.add(
      _db.collection('phone_sales_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          list.add({
            'label': d['nama'] ?? d['kod'] ?? '-',
            'sublabel': '#${d['siri'] ?? '-'}',
            'kos': ((d['kos'] ?? 0) as num).toDouble(),
            'jual': ((d['jual'] ?? 0) as num).toDouble(),
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'jenis': 'TELEFON',
          });
        }
        if (mounted) setState(() => _phoneSales = list);
      }),
    );

    // 5. Losses
    _subs.add(
      _db.collection('losses_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          list.add({
            'label': d['keterangan'] ?? '-',
            'sublabel': d['jenis'] ?? '-',
            'jumlah': ((d['jumlah'] ?? 0) as num).toDouble(),
            'timestamp': _dapatkanMasaSah(d['timestamp']),
          });
        }
        if (mounted) setState(() => _lossRecords = list);
      }),
    );

    // 6. Jualan Pantas (PAID)
    _subs.add(
      _db.collection('jualan_pantas_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          if ((d['payment_status'] ?? '').toString().toUpperCase() != 'PAID') continue;
          list.add({
            'label': d['nama'] ?? 'JUALAN PANTAS',
            'sublabel': '#${d['siri'] ?? '-'}',
            'jumlah': double.tryParse(d['total']?.toString() ?? '0') ?? 0,
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'jenis': 'JUALAN PANTAS',
          });
        }
        if (mounted) setState(() => _jualanPantasRecords = list);
      }),
    );
  }

  bool _isInRange(int ts) {
    if (ts == 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (_filterTime) {
      case 'TODAY':
        return date.isAfter(todayStart);
      case 'THIS_WEEK':
        return date.isAfter(todayStart.subtract(Duration(days: now.weekday - 1)));
      case 'THIS_MONTH':
        return date.isAfter(DateTime(now.year, now.month, 1));
      case 'CUSTOM':
        if (_customStart != null && _customEnd != null) {
          return date.isAfter(_customStart!) && date.isBefore(_customEnd!.add(const Duration(days: 1)));
        }
        return true;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filterList(List<Map<String, dynamic>> list) {
    return list.where((r) => _isInRange(r['timestamp'] as int)).toList();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.green)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _customStart = picked.start; _customEnd = picked.end; _filterTime = 'CUSTOM'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      _buildSegmentTabs(),
      Expanded(
        child: _buildCurrentSegment(),
      ),
    ]);
  }

  Widget _buildCurrentSegment() {
    final idx = _segmentCtrl.index;
    if (widget.phoneEnabled) {
      if (idx == 0) return _buildRepairSegment();
      if (idx == 1) return _buildPhoneSegment();
      return _buildKewanganSegment();
    }
    // Phone disabled: 0=Repair, 1=Kewangan
    if (idx == 0) return _buildRepairSegment();
    return _buildKewanganSegment();
  }

  // ═══════════════════════════════════════
  // HEADER + TIME FILTER
  // ═══════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.green, width: 2)),
      ),
      child: Column(children: [
        Row(children: [
          const FaIcon(FontAwesomeIcons.chartLine, size: 14, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(_lang.get('sv_ur_title'), style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900))),
          GestureDetector(
            onTap: _showReportModal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.download, size: 10, color: Colors.white),
                const SizedBox(width: 5),
                Text(_lang.get('sv_ur_download'), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterTime,
                  isExpanded: true,
                  icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 10, color: AppColors.green),
                  style: const TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w800),
                  dropdownColor: Colors.white,
                  items: [
                    DropdownMenuItem(value: 'TODAY', child: Text(_lang.get('sv_ur_today'))),
                    DropdownMenuItem(value: 'THIS_WEEK', child: Text(_lang.get('sv_ur_this_week'))),
                    DropdownMenuItem(value: 'THIS_MONTH', child: Text(_lang.get('sv_ur_this_month'))),
                    DropdownMenuItem(value: 'ALL', child: Text(_lang.get('sv_ur_all'))),
                    DropdownMenuItem(value: 'CUSTOM', child: Text(_lang.get('sv_ur_pick_date'))),
                  ],
                  onChanged: (val) {
                    if (val == 'CUSTOM') {
                      _pickDateRange();
                    } else if (val != null) {
                      setState(() => _filterTime = val);
                    }
                  },
                ),
              ),
            ),
          ),
          if (_filterTime == 'CUSTOM' && _customStart != null && _customEnd != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.calendar, size: 10, color: AppColors.green),
                  const SizedBox(width: 4),
                  Text(
                    '${_customStart!.day}/${_customStart!.month} - ${_customEnd!.day}/${_customEnd!.month}',
                    style: const TextStyle(color: AppColors.green, fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════
  // SEGMENT TABS (3 tabs)
  // ═══════════════════════════════════════

  Widget _buildSegmentTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.side,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _segmentCtrl,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        dividerHeight: 0,
        tabs: [
          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const FaIcon(FontAwesomeIcons.screwdriverWrench, size: 9),
            const SizedBox(width: 4),
            Text(_lang.get('sv_ur_tab_repair')),
          ])),
          if (widget.phoneEnabled)
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 9),
              const SizedBox(width: 4),
              Text(_lang.get('sv_ur_tab_phone')),
            ])),
          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const FaIcon(FontAwesomeIcons.chartPie, size: 9),
            const SizedBox(width: 4),
            Text(_lang.get('sv_ur_tab_finance')),
          ])),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // REPAIR & SPAREPART SEGMENT
  // ═══════════════════════════════════════

  Widget _buildRepairSegment() {
    final filteredIncome = _filterList(_repairIncome);
    final filteredUsage = _filterList(_stockUsage);
    final filteredExpense = _filterList(_expenseRecords);
    final filteredLoss = _filterList(_lossRecords);

    final totalIncome = filteredIncome.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalModal = filteredUsage.fold<double>(0, (s, r) => s + (r['kos'] as double));
    final totalExpense = filteredExpense.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalLost = filteredLoss.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalProfit = totalIncome - totalModal - totalExpense - totalLost;
    final count = filteredIncome.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: _gridCard('COUNT', '$count', _lang.get('sv_ur_job_done'), AppColors.blue, FontAwesomeIcons.clipboardCheck)),
          const SizedBox(width: 10),
          Expanded(child: _gridCard(_lang.get('sv_ur_cost'), 'RM ${totalModal.toStringAsFixed(2)}', '${filteredUsage.length} sparepart', AppColors.yellow, FontAwesomeIcons.coins)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _gridCard(_lang.get('sv_ur_profit'), 'RM ${totalProfit.toStringAsFixed(2)}', '${_lang.get('sv_ur_income')}: RM ${totalIncome.toStringAsFixed(0)}', totalProfit >= 0 ? AppColors.green : AppColors.red, totalProfit >= 0 ? FontAwesomeIcons.arrowTrendUp : FontAwesomeIcons.arrowTrendDown)),
          const SizedBox(width: 10),
          Expanded(child: _gridCard(_lang.get('sv_ur_loss'), 'RM ${totalLost.toStringAsFixed(2)}', '${filteredLoss.length} ${_lang.get('sv_ur_records')}', AppColors.red, FontAwesomeIcons.triangleExclamation)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _miniChip('${_lang.get('sv_ur_expense')}: RM ${totalExpense.toStringAsFixed(0)}', AppColors.red),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════
  // JUALAN TELEFON SEGMENT
  // ═══════════════════════════════════════

  Widget _buildPhoneSegment() {
    final filteredSales = _filterList(_phoneSales);
    final filteredLoss = _filterList(_lossRecords);

    final totalModal = filteredSales.fold<double>(0, (s, r) => s + (r['kos'] as double));
    final totalJual = filteredSales.fold<double>(0, (s, r) => s + (r['jual'] as double));
    final totalLost = filteredLoss.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalProfit = totalJual - totalModal - totalLost;
    final count = filteredSales.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: _gridCard('COUNT', '$count', _lang.get('sv_ur_unit_sold'), AppColors.blue, FontAwesomeIcons.mobileScreenButton)),
          const SizedBox(width: 10),
          Expanded(child: _gridCard(_lang.get('sv_ur_cost'), 'RM ${totalModal.toStringAsFixed(2)}', _lang.get('sv_ur_phone_modal'), AppColors.yellow, FontAwesomeIcons.coins)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _gridCard(_lang.get('sv_ur_profit'), 'RM ${totalProfit.toStringAsFixed(2)}', '${_lang.get('sv_ur_sales')}: RM ${totalJual.toStringAsFixed(0)}', totalProfit >= 0 ? AppColors.green : AppColors.red, totalProfit >= 0 ? FontAwesomeIcons.arrowTrendUp : FontAwesomeIcons.arrowTrendDown)),
          const SizedBox(width: 10),
          Expanded(child: _gridCard(_lang.get('sv_ur_loss'), 'RM ${totalLost.toStringAsFixed(2)}', '${filteredLoss.length} ${_lang.get('sv_ur_records')}', AppColors.red, FontAwesomeIcons.triangleExclamation)),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════
  // KEWANGAN SEGMENT (dari sv_kewangan_tab)
  // ═══════════════════════════════════════

  Widget _buildKewanganSegment() {
    final fRepair = _repairIncome.where((r) => _isInRange(r['timestamp'] as int)).toList();
    final fJualanPantas = _jualanPantasRecords.where((r) => _isInRange(r['timestamp'] as int)).toList();
    final fPhoneSales = _phoneSales.where((r) => _isInRange(r['timestamp'] as int)).toList();
    final fExpense = _expenseRecords.where((r) => _isInRange(r['timestamp'] as int)).toList();

    final totalRepair = fRepair.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalJualanPantas = fJualanPantas.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalPhoneSales = fPhoneSales.fold<double>(0, (s, r) => s + (r['jual'] as double));
    final totalPhoneCost = fPhoneSales.fold<double>(0, (s, r) => s + (r['kos'] as double));

    final totalJualan = totalRepair + totalJualanPantas + totalPhoneSales;
    final totalExpense = fExpense.fold<double>(0, (s, r) => s + (r['jumlah'] as double));

    final untungKasar = totalJualan - totalPhoneCost;
    final untungBersih = untungKasar - totalExpense;

    final allJualan = [...fRepair, ...fJualanPantas, ...fPhoneSales];
    allJualan.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    fExpense.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

    return Column(
      children: [
        _buildKewanganSummary(totalJualan, totalExpense, untungKasar, untungBersih),
        Expanded(
          child: _kewanganSection.isEmpty
              ? _buildKewanganOverview(totalRepair, totalJualanPantas, totalPhoneSales, totalPhoneCost, totalExpense, untungKasar, untungBersih)
              : _kewanganSection == 'JUALAN'
                  ? _buildKewanganDetailList(_lang.get('sv_ur_kw_sales_list'), allJualan, false)
                  : _buildKewanganDetailList(_lang.get('sv_ur_kw_expense_list'), fExpense, true),
        ),
      ],
    );
  }

  Widget _buildKewanganSummary(double jualan, double expense, double kasar, double bersih) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        if (_kewanganSection.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => setState(() => _kewanganSection = ''),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.side, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const FaIcon(FontAwesomeIcons.arrowLeft, size: 9, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(_lang.get('sv_ur_kw_summary'), style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        Row(children: [
          Expanded(child: _kwSummaryCard(_lang.get('sv_ur_kw_sales'), jualan, AppColors.blue, FontAwesomeIcons.cartShopping, onTap: () => setState(() => _kewanganSection = 'JUALAN'))),
          const SizedBox(width: 8),
          Expanded(child: _kwSummaryCard(_lang.get('sv_ur_kw_expenses'), expense, AppColors.red, FontAwesomeIcons.fileInvoiceDollar, onTap: () => setState(() => _kewanganSection = 'EXPENSE'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _kwSummaryCard(_lang.get('sv_ur_kw_gross'), kasar, kasar >= 0 ? AppColors.green : AppColors.red, FontAwesomeIcons.scaleBalanced)),
          const SizedBox(width: 8),
          Expanded(child: _kwSummaryCard(_lang.get('sv_ur_kw_net'), bersih, bersih >= 0 ? AppColors.green : AppColors.red, bersih >= 0 ? FontAwesomeIcons.faceSmile : FontAwesomeIcons.faceFrown)),
        ]),
      ]),
    );
  }

  Widget _kwSummaryCard(String label, double amount, Color color, IconData icon, {VoidCallback? onTap}) {
    final isNeg = amount < 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            FaIcon(icon, size: 13, color: color),
            const Spacer(),
            if (onTap != null) FaIcon(FontAwesomeIcons.chevronRight, size: 9, color: color.withValues(alpha: 0.5)),
          ]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text('${isNeg ? "-" : ""}RM ${amount.abs().toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _buildKewanganOverview(double repair, double jualanPantas, double phoneSales, double phoneCost, double expense, double kasar, double bersih) {
    final totalJualan = repair + jualanPantas + phoneSales;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        _kwSectionTitle(_lang.get('sv_ur_kw_breakdown'), FontAwesomeIcons.chartBar, AppColors.blue),
        const SizedBox(height: 8),
        _kwBreakdownRow(_lang.get('sv_ur_kw_servis'), repair, totalJualan, AppColors.cyan),
        _kwBreakdownRow(_lang.get('sv_ur_kw_jualan_pantas'), jualanPantas, totalJualan, AppColors.blue),
        _kwBreakdownRow(_lang.get('sv_ur_kw_phone_sales'), phoneSales, totalJualan, const Color(0xFF8B5CF6)),
        const SizedBox(height: 16),
        _kwSectionTitle(_lang.get('sv_ur_kw_gross'), FontAwesomeIcons.calculator, AppColors.green),
        const SizedBox(height: 8),
        _kwFormulaBox([
          _kwFormulaLine(_lang.get('sv_ur_kw_total_sales'), totalJualan, false),
          _kwFormulaLine(_lang.get('sv_ur_kw_cogs'), phoneCost, true),
        ], _lang.get('sv_ur_kw_gross'), kasar),
        const SizedBox(height: 16),
        _kwSectionTitle(_lang.get('sv_ur_kw_net'), FontAwesomeIcons.calculator, bersih >= 0 ? AppColors.green : AppColors.red),
        const SizedBox(height: 8),
        _kwFormulaBox([
          _kwFormulaLine(_lang.get('sv_ur_kw_gross'), kasar, false),
          _kwFormulaLine(_lang.get('sv_ur_kw_expenses'), expense, true),
        ], _lang.get('sv_ur_kw_net'), bersih),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _kwSectionTitle(String title, IconData icon, Color color) {
    return Row(children: [
      FaIcon(icon, size: 11, color: color),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    ]);
  }

  Widget _kwBreakdownRow(String label, double amount, double total, Color color) {
    final pct = total > 0 ? (amount / total) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600))),
            Text('RM ${amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct, minHeight: 4, backgroundColor: AppColors.side, valueColor: AlwaysStoppedAnimation(color)),
          ),
        ]),
      ),
    );
  }

  Widget _kwFormulaBox(List<Widget> lines, String resultLabel, double resultValue) {
    final isPos = resultValue >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        ...lines,
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.borderMed)),
        Row(children: [
          Text(resultLabel, style: TextStyle(color: isPos ? AppColors.green : AppColors.red, fontSize: 11, fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('${isPos ? "" : "-"}RM ${resultValue.abs().toStringAsFixed(2)}', style: TextStyle(color: isPos ? AppColors.green : AppColors.red, fontSize: 16, fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }

  Widget _kwFormulaLine(String label, double amount, bool isMinus) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(isMinus ? '(-)' : '', style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
        if (isMinus) const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('RM ${amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildKewanganDetailList(String title, List<Map<String, dynamic>> records, bool isExpense) {
    if (records.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(isExpense ? FontAwesomeIcons.fileInvoice : FontAwesomeIcons.coins, size: 36, color: AppColors.textDim),
          const SizedBox(height: 10),
          Text(_lang.get('sv_ur_no_records'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: records.length,
      itemBuilder: (_, i) {
        final r = records[i];
        final ts = r['timestamp'] as int;
        final dateStr = ts > 0 ? DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '-';
        final jenis = r['jenis'] ?? '';
        final jenisColor = jenis == 'REPAIR' ? AppColors.cyan : jenis == 'JUALAN PANTAS' ? AppColors.blue : jenis == 'TELEFON' ? const Color(0xFF8B5CF6) : AppColors.red;
        final amount = isExpense ? (r['jumlah'] as double) : (r['jumlah'] as double?) ?? (r['jual'] as double?) ?? 0.0;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderMed)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: jenisColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(isExpense ? 'EXPENSE' : jenis, style: TextStyle(color: jenisColor, fontSize: 7, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((r['label'] ?? '-').toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${r['sublabel'] ?? '-'} | $dateStr', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
              ]),
            ),
            Text('${isExpense ? "-" : "+"}RM ${amount.toStringAsFixed(2)}', style: TextStyle(color: isExpense ? AppColors.red : AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
        );
      },
    );
  }

  // ═══════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════

  Widget _gridCard(String title, String value, String subtitle, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: FaIcon(icon, size: 14, color: color),
          ),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: err ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════
  // REPORT MODAL (Download CSV, Print 80mm, PDF)
  // ═══════════════════════════════════════

  void _showReportModal() {
    // Gather all filtered data
    final fRepair = _filterList(_repairIncome);
    final fJualanPantas = _filterList(_jualanPantasRecords);
    final fPhoneSales = _filterList(_phoneSales);
    final fExpense = _filterList(_expenseRecords);

    final totalRepair = fRepair.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalJualanPantas = fJualanPantas.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalPhoneSales = fPhoneSales.fold<double>(0, (s, r) => s + (r['jual'] as double));
    final totalPhoneCost = fPhoneSales.fold<double>(0, (s, r) => s + (r['kos'] as double));
    final totalJualan = totalRepair + totalJualanPantas + totalPhoneSales;
    final totalExpense = fExpense.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final untungKasar = totalJualan - totalPhoneCost;
    final untungBersih = untungKasar - totalExpense;

    final salesCount = fRepair.length + fJualanPantas.length + fPhoneSales.length;
    final expCount = fExpense.length;

    // Build combined list for CSV/PDF
    final allRecords = <Map<String, dynamic>>[];
    for (final r in fRepair) {
      allRecords.add({...r, 'isExpense': false});
    }
    for (final r in fJualanPantas) {
      allRecords.add({...r, 'isExpense': false});
    }
    for (final r in fPhoneSales) {
      allRecords.add({
        'label': r['label'],
        'sublabel': r['sublabel'],
        'jumlah': (r['jual'] as double),
        'timestamp': r['timestamp'],
        'jenis': r['jenis'] ?? 'TELEFON',
        'isExpense': false,
      });
    }
    for (final r in fExpense) {
      allRecords.add({...r, 'isExpense': true});
    }
    allRecords.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

    // Staff map
    final staffMap = <String, double>{};
    for (final d in allRecords.where((d) => d['isExpense'] != true)) {
      final staff = (d['sublabel'] ?? '-').toString();
      staffMap[staff] = (staffMap[staff] ?? 0) + ((d['jumlah'] ?? 0) as num).toDouble();
    }

    final periodLabel = {
      'TODAY': _lang.get('sv_ur_today'),
      'THIS_WEEK': _lang.get('sv_ur_this_week'),
      'THIS_MONTH': _lang.get('sv_ur_this_month'),
      'ALL': _lang.get('sv_ur_all'),
      'CUSTOM': _lang.get('sv_ur_pick_date'),
    }[_filterTime] ?? _filterTime;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.chartLine, size: 14, color: AppColors.cyan),
              const SizedBox(width: 8),
              Text(_lang.get('sv_ur_report_title'), style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 6),
          Text('${_lang.get('sv_ur_period')}: $periodLabel', style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
          const SizedBox(height: 16),
          // Summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              _reportRow(_lang.get('sv_ur_kw_total_sales'), 'RM ${totalJualan.toStringAsFixed(2)}', AppColors.green),
              _reportRow(_lang.get('sv_ur_kw_expenses'), 'RM ${totalExpense.toStringAsFixed(2)}', AppColors.red),
              const Divider(height: 16, color: AppColors.borderMed),
              _reportRow(_lang.get('sv_ur_kw_net'), 'RM ${untungBersih.toStringAsFixed(2)}', untungBersih >= 0 ? AppColors.green : AppColors.red),
            ]),
          ),
          const SizedBox(height: 16),
          // CSV
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _downloadReportCSV(allRecords); },
              icon: const FaIcon(FontAwesomeIcons.fileExcel, size: 14),
              label: Text(_lang.get('sv_ur_dl_csv')),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 8),
          // 80mm
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _printSalesSummary80mm(periodLabel, totalJualan, totalExpense, untungBersih, salesCount, expCount, staffMap); },
              icon: const FaIcon(FontAwesomeIcons.print, size: 14),
              label: Text(_lang.get('sv_ur_dl_80mm')),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 8),
          // PDF
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _generateSalesReportPDF(periodLabel, totalJualan, totalExpense, untungBersih, salesCount, expCount, allRecords); },
              icon: const FaIcon(FontAwesomeIcons.filePdf, size: 14),
              label: Text(_lang.get('sv_ur_dl_pdf')),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _reportRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Future<void> _downloadReportCSV(List<Map<String, dynamic>> data) async {
    if (data.isEmpty) { _snack(_lang.get('sv_ur_no_data'), err: true); return; }
    try {
      final buf = StringBuffer();
      buf.write('\uFEFF');
      buf.writeln('Tarikh,Masa,Jenis,Nama,Jumlah(RM)');
      for (final rec in data) {
        final tsMs = rec['timestamp'] ?? 0;
        final tarikh = tsMs > 0 ? DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(tsMs)) : '-';
        final masa = tsMs > 0 ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(tsMs)) : '-';
        final isExp = rec['isExpense'] == true;
        final jumlah = ((rec['jumlah'] ?? 0) as num).toDouble();
        String esc(String s) => '"${s.replaceAll('"', '""')}"';
        buf.writeln([
          esc(tarikh), esc(masa),
          esc((rec['jenis'] ?? '-').toString()),
          esc((rec['label'] ?? '-').toString()),
          isExp ? '-${jumlah.toStringAsFixed(2)}' : jumlah.toStringAsFixed(2),
        ].join(','));
      }
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'UntungRugi_${widget.shopID}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buf.toString());
      _snack('CSV: $fileName');
      OpenFilex.open(file.path);
    } catch (e) {
      _snack('CSV error: $e', err: true);
    }
  }

  Future<void> _printSalesSummary80mm(String period, double totalSales, double totalExpenses, double net, int salesCount, int expCount, Map<String, double> staffMap) async {
    _snack(_lang.get('sv_ur_connecting_printer'));
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
    final namaKedai = (s['shopName'] ?? s['namaKedai'] ?? 'RMS PRO').toString().toUpperCase();

    var r = escInit;
    r += escCenter + escDblSize + escBoldOn;
    r += tengah(namaKedai.length > 24 ? namaKedai.substring(0, 24) : namaKedai, (lebar / 2).floor());
    r += escNormal + escBoldOff;
    r += garis;
    r += escCenter + escDblHeight + escBoldOn;
    r += tengah(_lang.get('sv_ur_title'));
    r += escNormal + escBoldOff + escLeft;
    r += garis2;
    r += baris(_lang.get('sv_ur_period'), ': $period');
    r += baris(_lang.get('sv_ur_print_date'), ': ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
    r += garis;
    r += '${escBoldOn}${_lang.get('sv_ur_kw_sales')}\n$escBoldOff$garis2';
    r += baris(_lang.get('sv_ur_kw_total_sales'), 'RM ${totalSales.toStringAsFixed(2)}');
    r += baris(_lang.get('sv_ur_total_trans'), '$salesCount');
    r += garis2;
    r += '${escBoldOn}${_lang.get('sv_ur_kw_expenses')}\n$escBoldOff$garis2';
    r += baris(_lang.get('sv_ur_total_out'), 'RM ${totalExpenses.toStringAsFixed(2)}');
    r += baris(_lang.get('sv_ur_total_trans'), '$expCount');
    r += garis;
    r += escCenter + escDblHeight + escBoldOn;
    r += baris(_lang.get('sv_ur_kw_net'), 'RM ${net.toStringAsFixed(2)}');
    r += escNormal + escBoldOff + escLeft;
    r += garis;
    r += tengah('~ Powered by RMS Pro ~');
    r += garis;
    r += '\x0A\x0A\x0A\x1D\x56\x00';

    final bytes = utf8.encode(r);
    final ok = await _printer.printRaw(bytes);
    if (ok) {
      _snack(_lang.get('sv_ur_print_success'));
    } else {
      _snack(_lang.get('sv_ur_print_fail'), err: true);
    }
  }

  Future<void> _generateSalesReportPDF(String period, double totalSales, double totalExpenses, double net, int salesCount, int expCount, List<Map<String, dynamic>> reportData) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(_lang.get('sv_ur_generating_pdf'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );

    try {
      final items = reportData.map((rec) {
        final isExp = rec['isExpense'] == true;
        return {
          'tarikh': rec['timestamp'] is int ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(rec['timestamp'])) : '-',
          'siri': rec['sublabel'] ?? '-',
          'jenis': rec['jenis'] ?? '-',
          'nama': rec['label'] ?? '-',
          'item': rec['label'] ?? '-',
          'jumlah': isExp ? -((rec['jumlah'] ?? 0) as num).toDouble() : ((rec['jumlah'] ?? 0) as num).toDouble(),
          'staff': '-',
        };
      }).toList();

      final payload = {
        'typePDF': 'SALES_REPORT',
        'paperSize': 'A4',
        'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
        'logoBase64': _branchSettings['logoBase64'] ?? '',
        'namaKedai': _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'RMS PRO',
        'alamatKedai': _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
        'telKedai': _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
        'shopID': widget.shopID,
        'period': period,
        'tarikhCetak': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        'totalSales': totalSales,
        'totalExpenses': totalExpenses,
        'netMargin': net,
        'salesCount': salesCount,
        'expenseCount': expCount,
        'items': items,
      };

      final response = await http.post(
        Uri.parse('$_cloudRunUrl/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          _snack(_lang.get('sv_ur_pdf_success'));
          _downloadAndOpenPDF(pdfUrl, 'LAPORAN_${widget.shopID}');
        } else {
          _snack(_lang.get('sv_ur_pdf_no_link'), err: true);
        }
      } else {
        _snack('${_lang.get('sv_ur_pdf_fail')}: ${response.statusCode}', err: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _snack('${_lang.get('sv_ur_error')}: $e', err: true);
    }
  }

  Future<void> _downloadAndOpenPDF(String pdfUrl, String name) async {
    if (kIsWeb) {
      launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication);
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$name.pdf';
      await Dio().download(pdfUrl, filePath);
      OpenFilex.open(filePath);
    } catch (e) {
      _snack('${_lang.get('sv_ur_error')}: $e', err: true);
    }
  }
}
