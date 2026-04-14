import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class SvKewanganTab extends StatefulWidget {
  final String ownerID, shopID;
  final bool phoneEnabled;
  const SvKewanganTab({
    required this.ownerID,
    required this.shopID,
    this.phoneEnabled = true,
  });
  @override
  State<SvKewanganTab> createState() => _SvKewanganTabState();
}

class _SvKewanganTabState extends State<SvKewanganTab> {
  final _db = FirebaseFirestore.instance;
  String _filterTime = 'TODAY';
  DateTime? _customStart, _customEnd;
  String _activeSection = ''; // '', 'JUALAN', 'EXPENSE', 'KASAR', 'BERSIH'

  // Data lists
  List<Map<String, dynamic>> _repairRecords = [];
  List<Map<String, dynamic>> _jualanPantasRecords = [];
  List<Map<String, dynamic>> _phoneSalesRecords = [];
  List<Map<String, dynamic>> _expenseRecords = [];
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _listenAll();
  }

  @override
  void dispose() {
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
    // Repairs (PAID, bukan jualan)
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
        if (mounted) setState(() => _repairRecords = list);
      }),
    );

    // Jualan Pantas (PAID)
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

    // Phone Sales (SOLD)
    _subs.add(
      _db.collection('phone_sales_${widget.ownerID}').snapshots().listen((snap) {
        final list = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['shopID'] ?? '').toString().toUpperCase() != widget.shopID) continue;
          list.add({
            'label': d['nama'] ?? 'TELEFON',
            'sublabel': d['imei'] ?? '-',
            'jumlah': (d['jual'] as num?)?.toDouble() ?? 0,
            'kos': (d['kos'] as num?)?.toDouble() ?? 0,
            'timestamp': _dapatkanMasaSah(d['timestamp']),
            'jenis': 'TELEFON',
          });
        }
        if (mounted) setState(() => _phoneSalesRecords = list);
      }),
    );

    // Expenses
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
          return date.isAfter(_customStart!) &&
              date.isBefore(_customEnd!.add(const Duration(days: 1)));
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.green),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _filterTime = 'CUSTOM';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter semua data
    final fRepair = _repairRecords.where((r) => _isInRange(r['timestamp'] as int)).toList();
    final fJualanPantas = _jualanPantasRecords.where((r) => _isInRange(r['timestamp'] as int)).toList();
    final fPhoneSales = _phoneSalesRecords.where((r) => _isInRange(r['timestamp'] as int)).toList();
    final fExpense = _expenseRecords.where((r) => _isInRange(r['timestamp'] as int)).toList();

    // Kira jumlah
    final totalRepair = fRepair.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalJualanPantas = fJualanPantas.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalPhoneSales = fPhoneSales.fold<double>(0, (s, r) => s + (r['jumlah'] as double));
    final totalPhoneCost = fPhoneSales.fold<double>(0, (s, r) => s + ((r['kos'] as double?) ?? 0));

    final totalJualan = totalRepair + totalJualanPantas + totalPhoneSales;
    final totalExpense = fExpense.fold<double>(0, (s, r) => s + (r['jumlah'] as double));

    // Untung Kasar = Jualan - Kos Barang (hanya phone ada kos)
    final untungKasar = totalJualan - totalPhoneCost;
    // Untung Bersih = Untung Kasar - Perbelanjaan
    final untungBersih = untungKasar - totalExpense;

    // Gabung semua jualan records untuk detail view
    final allJualan = [...fRepair, ...fJualanPantas, ...fPhoneSales];
    allJualan.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    fExpense.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

    return Column(
      children: [
        // Header + filter
        _buildHeader(),
        // Summary cards
        _buildSummaryCards(totalJualan, totalExpense, untungKasar, untungBersih),
        // Detail section
        Expanded(
          child: _activeSection.isEmpty
              ? _buildOverview(totalRepair, totalJualanPantas, totalPhoneSales, totalPhoneCost, totalExpense, untungKasar, untungBersih)
              : _activeSection == 'JUALAN'
                  ? _buildDetailList('SENARAI JUALAN', allJualan, false)
                  : _activeSection == 'EXPENSE'
                      ? _buildDetailList('SENARAI PERBELANJAAN', fExpense, true)
                      : _buildOverview(totalRepair, totalJualanPantas, totalPhoneSales, totalPhoneCost, totalExpense, untungKasar, untungBersih),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.green, width: 2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.chartPie, size: 14, color: AppColors.green),
              const SizedBox(width: 8),
              const Text(
                'LAPORAN KEWANGAN',
                style: TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (_activeSection.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _activeSection = ''),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.side,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(FontAwesomeIcons.arrowLeft, size: 9, color: AppColors.textMuted),
                        SizedBox(width: 4),
                        Text('Ringkasan', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Time filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in [
                  {'key': 'TODAY', 'label': 'Hari Ini'},
                  {'key': 'THIS_WEEK', 'label': 'Minggu Ini'},
                  {'key': 'THIS_MONTH', 'label': 'Bulan Ini'},
                  {'key': 'ALL', 'label': 'Semua'},
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterTime = f['key']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _filterTime == f['key'] ? AppColors.green : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _filterTime == f['key'] ? AppColors.green : AppColors.borderMed,
                          ),
                        ),
                        child: Text(
                          f['label']!,
                          style: TextStyle(
                            color: _filterTime == f['key'] ? Colors.white : AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: _pickDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _filterTime == 'CUSTOM' ? AppColors.green : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _filterTime == 'CUSTOM' ? AppColors.green : AppColors.borderMed,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(FontAwesomeIcons.calendar, size: 10,
                            color: _filterTime == 'CUSTOM' ? Colors.white : AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('Pilih Tarikh',
                            style: TextStyle(
                              color: _filterTime == 'CUSTOM' ? Colors.white : AppColors.textMuted,
                              fontSize: 10, fontWeight: FontWeight.w800,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(double jualan, double expense, double kasar, double bersih) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'JUALAN',
                  jualan,
                  AppColors.blue,
                  FontAwesomeIcons.cartShopping,
                  onTap: () => setState(() => _activeSection = 'JUALAN'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'PERBELANJAAN',
                  expense,
                  AppColors.red,
                  FontAwesomeIcons.fileInvoiceDollar,
                  onTap: () => setState(() => _activeSection = 'EXPENSE'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'UNTUNG KASAR',
                  kasar,
                  kasar >= 0 ? AppColors.green : AppColors.red,
                  FontAwesomeIcons.scaleBalanced,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'UNTUNG BERSIH',
                  bersih,
                  bersih >= 0 ? AppColors.green : AppColors.red,
                  bersih >= 0 ? FontAwesomeIcons.faceSmile : FontAwesomeIcons.faceFrown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double amount, Color color, IconData icon, {VoidCallback? onTap}) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FaIcon(icon, size: 13, color: color),
                const Spacer(),
                if (onTap != null)
                  FaIcon(FontAwesomeIcons.chevronRight, size: 9, color: color.withValues(alpha: 0.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
            const SizedBox(height: 2),
            Text(
              '${isNeg ? "-" : ""}RM ${amount.abs().toStringAsFixed(2)}',
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview(
    double repair, double jualanPantas, double phoneSales, double phoneCost,
    double expense, double kasar, double bersih,
  ) {
    final totalJualan = repair + jualanPantas + phoneSales;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // Pecahan Jualan
          _sectionTitle('PECAHAN JUALAN', FontAwesomeIcons.chartBar, AppColors.blue),
          const SizedBox(height: 8),
          _breakdownRow('Servis / Repair', repair, totalJualan, AppColors.cyan),
          _breakdownRow('Jualan Pantas', jualanPantas, totalJualan, AppColors.blue),
          if (widget.phoneEnabled)
            _breakdownRow('Jualan Telefon', phoneSales, totalJualan, const Color(0xFF8B5CF6)),
          const SizedBox(height: 16),
          // Formula Untung Kasar
          _sectionTitle('UNTUNG KASAR', FontAwesomeIcons.calculator, AppColors.green),
          const SizedBox(height: 8),
          _formulaBox([
            _formulaLine('Jumlah Jualan', totalJualan, false),
            _formulaLine('Kos Barang (Telefon)', phoneCost, true),
          ], 'UNTUNG KASAR', kasar),
          const SizedBox(height: 16),
          // Formula Untung Bersih
          _sectionTitle('UNTUNG BERSIH', FontAwesomeIcons.calculator, bersih >= 0 ? AppColors.green : AppColors.red),
          const SizedBox(height: 8),
          _formulaBox([
            _formulaLine('Untung Kasar', kasar, false),
            _formulaLine('Perbelanjaan', expense, true),
          ], 'UNTUNG BERSIH', bersih),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        FaIcon(icon, size: 11, color: color),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _breakdownRow(String label, double amount, double total, Color color) {
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
        child: Column(
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                Text('RM ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: AppColors.side,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulaBox(List<Widget> lines, String resultLabel, double resultValue) {
    final isPos = resultValue >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ...lines,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.borderMed),
          ),
          Row(
            children: [
              Text(resultLabel, style: TextStyle(
                color: isPos ? AppColors.green : AppColors.red,
                fontSize: 11, fontWeight: FontWeight.w900,
              )),
              const Spacer(),
              Text(
                '${isPos ? "" : "-"}RM ${resultValue.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  color: isPos ? AppColors.green : AppColors.red,
                  fontSize: 16, fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formulaLine(String label, double amount, bool isMinus) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(isMinus ? '(-)' : '', style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
          if (isMinus) const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('RM ${amount.toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildDetailList(String title, List<Map<String, dynamic>> records, bool isExpense) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              isExpense ? FontAwesomeIcons.fileInvoice : FontAwesomeIcons.coins,
              size: 36, color: AppColors.textDim,
            ),
            const SizedBox(height: 10),
            Text(
              'Tiada rekod',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: records.length,
      itemBuilder: (_, i) {
        final r = records[i];
        final ts = r['timestamp'] as int;
        final dateStr = ts > 0
            ? DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts))
            : '-';
        final jenis = r['jenis'] ?? '';
        final jenisColor = jenis == 'REPAIR'
            ? AppColors.cyan
            : jenis == 'JUALAN PANTAS'
                ? AppColors.blue
                : jenis == 'TELEFON'
                    ? const Color(0xFF8B5CF6)
                    : AppColors.red;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderMed),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: jenisColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isExpense ? 'EXPENSE' : jenis,
                  style: TextStyle(color: jenisColor, fontSize: 7, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (r['label'] ?? '-').toString(),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${r['sublabel'] ?? '-'} | $dateStr',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 9),
                    ),
                  ],
                ),
              ),
              Text(
                '${isExpense ? "-" : "+"}RM ${(r['jumlah'] as double).toStringAsFixed(2)}',
                style: TextStyle(
                  color: isExpense ? AppColors.red : AppColors.green,
                  fontSize: 13, fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
