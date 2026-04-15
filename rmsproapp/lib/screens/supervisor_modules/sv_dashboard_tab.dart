import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';

class SvDashboardTab extends StatefulWidget {
  final String ownerID;
  final String shopID;
  final bool phoneEnabled;

  const SvDashboardTab({
    super.key,
    required this.ownerID,
    required this.shopID,
    this.phoneEnabled = true,
  });

  @override
  State<SvDashboardTab> createState() => _SvDashboardTabState();
}

class _SvDashboardTabState extends State<SvDashboardTab> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _branchId;
  List<Map<String, dynamic>> _repairRows = [];
  List<Map<String, dynamic>> _phoneSalesRows = [];
  StreamSubscription? _repairSub;
  StreamSubscription? _phoneSub;

  int _segment = 0; // 0 = Job Repair, 1 = Jualan Telefon
  String _filter = 'SEMUA';
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _repairSub?.cancel();
    _phoneSub?.cancel();
    super.dispose();
  }

  int _tsFromIso(dynamic v) {
    if (v is int) return v;
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  Future<void> _init() async {
    await _repairService.init();
    _branchId = _repairService.branchId;
    if (_branchId == null) return;
    _repairSub = _sb
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>((r) => {
        ...Map<String, dynamic>.from(r),
        'timestamp': _tsFromIso(r['created_at']),
      }).toList();
      if (mounted) setState(() => _repairRows = list);
    });
    _phoneSub = _sb
        .from('phone_sales')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>((r) {
        final notes = (r['notes'] is Map) ? Map<String, dynamic>.from(r['notes']) : <String, dynamic>{};
        return {
          ...Map<String, dynamic>.from(r),
          'jual': r['sold_price'] ?? notes['jual'] ?? 0,
          'kos': notes['kos'] ?? 0,
          'shopID': widget.shopID,
          'timestamp': _tsFromIso(r['sold_at'] ?? r['created_at']),
        };
      }).toList();
      if (mounted) setState(() => _phoneSalesRows = list);
    });
  }

  bool _isInRange(Map<String, dynamic> data) {
    if (_filter == 'SEMUA') return true;

    DateTime? date;

    // Use timestamp field (milliseconds since epoch) as primary
    final ts = data['timestamp'];
    if (ts != null && ts is int && ts > 0) {
      date = DateTime.fromMillisecondsSinceEpoch(ts);
    }

    // Fallback to tarikh field (yyyy-MM-ddTHH:mm string)
    if (date == null) {
      final tarikh = data['tarikh'];
      if (tarikh != null && tarikh is String && tarikh.isNotEmpty) {
        try {
          date = DateTime.parse(tarikh);
        } catch (_) {}
      }
    }

    if (date == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_filter) {
      case 'HARI_INI':
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      case 'MINGGU_INI':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return !date.isBefore(weekStart) && date.isBefore(weekEnd);
      case 'BULAN_INI':
        return date.year == now.year && date.month == now.month;
      case 'TAHUN_INI':
        return date.year == now.year;
      case 'CUSTOM':
        if (_customStart == null || _customEnd == null) return true;
        final start = DateTime(
            _customStart!.year, _customStart!.month, _customStart!.day);
        final end = DateTime(
            _customEnd!.year, _customEnd!.month, _customEnd!.day, 23, 59, 59);
        return !date.isBefore(start) && !date.isAfter(end);
      default:
        return true;
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF6366F1),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _filter = 'CUSTOM';
        _customStart = picked.start;
        _customEnd = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ownerID.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!widget.phoneEnabled && _segment == 1) _segment = 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DASHBOARD',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Statistik jualan & job',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // Segment toggle
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              _segmentBtn(0, 'Job Repair', FontAwesomeIcons.screwdriverWrench),
              if (widget.phoneEnabled) ...[
                const SizedBox(width: 4),
                _segmentBtn(1, 'Jualan Telefon', FontAwesomeIcons.mobileScreenButton),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // Filter dropdown
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filter,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 10, color: Color(0xFF6366F1)),
                    style: const TextStyle(color: Color(0xFF6366F1), fontSize: 11, fontWeight: FontWeight.w900),
                    items: const [
                      DropdownMenuItem(value: 'SEMUA', child: Text('Semua')),
                      DropdownMenuItem(value: 'HARI_INI', child: Text('Hari Ini')),
                      DropdownMenuItem(value: 'MINGGU_INI', child: Text('Minggu Ini')),
                      DropdownMenuItem(value: 'BULAN_INI', child: Text('Bulan Ini')),
                      DropdownMenuItem(value: 'TAHUN_INI', child: Text('Tahun Ini')),
                      DropdownMenuItem(value: 'CUSTOM', child: Text('Pilih Tarikh')),
                    ],
                    onChanged: (val) {
                      if (val == 'CUSTOM') {
                        _pickDateRange();
                      } else if (val != null) {
                        setState(() => _filter = val);
                      }
                    },
                  ),
                ),
              ),
            ),
          ]),

          if (_filter == 'CUSTOM' &&
              _customStart != null &&
              _customEnd != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FaIcon(FontAwesomeIcons.calendarDay,
                      size: 10, color: Color(0xFF6366F1)),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(_customStart!)} - ${DateFormat('dd/MM/yyyy').format(_customEnd!)}',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Content based on segment
          if (_segment == 0) _buildRepairSegment(),
          if (_segment == 1) _buildPhoneSalesSegment(),
        ],
      ),
    );
  }

  Widget _segmentBtn(int index, String label, IconData icon) {
    final isActive = _segment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _segment = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive ? [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FaIcon(icon, size: 10, color: isActive ? Colors.white : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isActive ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w900)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // SEGMENT 1: JOB REPAIR
  // ═══════════════════════════════════════

  Widget _buildRepairSegment() {
    int totalJobs = 0;
    int inProgress = 0;
    int waitingPart = 0;
    int readyToPickup = 0;
    int completed = 0;
    int cancel = 0;
    int reject = 0;

    for (final data in _repairRows) {
      if (!_isInRange(data)) continue;
      totalJobs++;
      final status = (data['status'] ?? '').toString().toUpperCase();
      switch (status) {
        case 'IN PROGRESS': inProgress++; break;
        case 'WAITING PART': waitingPart++; break;
        case 'READY TO PICKUP': readyToPickup++; break;
        case 'COMPLETED': completed++; break;
        case 'CANCEL':
        case 'CANCELLED': cancel++; break;
        case 'REJECT': reject++; break;
      }
    }

    return Column(children: [
          _buildTotalCard(totalJobs, 'JUMLAH JOB', FontAwesomeIcons.screwdriverWrench,
              const Color(0xFF6366F1), const Color(0xFF8B5CF6)),
          const SizedBox(height: 14),
          Row(children: [
            _buildStatCard('In Progress', inProgress, FontAwesomeIcons.spinner, const Color(0xFF4CAF50), const Color(0xFFE8F5E9)),
            const SizedBox(width: 12),
            _buildStatCard('Waiting Part', waitingPart, FontAwesomeIcons.clockRotateLeft, AppColors.yellow, const Color(0xFFFFF8E1)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _buildStatCard('Ready To Pickup', readyToPickup, FontAwesomeIcons.handHoldingHeart, const Color(0xFFA78BFA), const Color(0xFFEDE9FE)),
            const SizedBox(width: 12),
            _buildStatCard('Completed', completed, FontAwesomeIcons.circleCheck, const Color(0xFF4CAF50), const Color(0xFFE8F5E9)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _buildStatCard('Cancel', cancel, FontAwesomeIcons.ban, const Color(0xFFFFC107), const Color(0xFFFFF8E1)),
            const SizedBox(width: 12),
            _buildStatCard('Reject', reject, FontAwesomeIcons.circleXmark, AppColors.red, const Color(0xFFFEE2E2)),
          ]),
        ]);
  }

  // ═══════════════════════════════════════
  // SEGMENT 2: JUALAN TELEFON
  // ═══════════════════════════════════════

  Widget _buildPhoneSalesSegment() {
    int totalSales = 0;
    int salesToday = 0;
    double totalJual = 0;
    double totalKos = 0;
    double jualToday = 0;
    double kosToday = 0;

    final now = DateTime.now();

    for (final data in _phoneSalesRows) {
      if (!_isInRange(data)) continue;

      totalSales++;
      final jual = ((data['jual'] ?? 0) as num).toDouble();
      final kos = ((data['kos'] ?? 0) as num).toDouble();
      totalJual += jual;
      totalKos += kos;

      final ts = data['timestamp'];
      if (ts is int) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts);
        if (d.year == now.year && d.month == now.month && d.day == now.day) {
          salesToday++;
          jualToday += jual;
          kosToday += kos;
        }
      }
    }

    final totalProfit = totalJual - totalKos;
    final profitToday = jualToday - kosToday;

    return Column(children: [
          // Sales today highlight card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF059669), Color(0xFF10B981)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 24, color: Colors.white)),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('JUALAN HARI INI', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('$salesToday unit', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('RM${jualToday.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: Text('Profit: RM${profitToday.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          // Summary cards
          Row(children: [
            _buildStatCard('Jumlah Jualan', totalSales, FontAwesomeIcons.cartShopping, const Color(0xFF6366F1), const Color(0xFFEDE9FE)),
            const SizedBox(width: 12),
            _buildAmountCard('Jumlah Jual', totalJual, FontAwesomeIcons.moneyBill, const Color(0xFF059669), const Color(0xFFD1FAE5)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _buildAmountCard('Jumlah Kos', totalKos, FontAwesomeIcons.coins, const Color(0xFFEA580C), const Color(0xFFFFF7ED)),
            const SizedBox(width: 12),
            _buildAmountCard('Jumlah Profit', totalProfit, FontAwesomeIcons.chartLine,
                totalProfit >= 0 ? const Color(0xFF059669) : AppColors.red,
                totalProfit >= 0 ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2)),
          ]),
        ]);
  }



  Widget _buildTotalCard(int total, String label, IconData icon, Color color1, Color color2) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: color1.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: Center(child: FaIcon(icon, size: 24, color: Colors.white)),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text('$total', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }

  Widget _buildAmountCard(String label, double amount, IconData icon, Color color, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Center(child: FaIcon(icon, size: 16, color: color)),
          ),
          const SizedBox(height: 12),
          Text('RM${amount.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
        ]),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    int count,
    IconData icon,
    Color color,
    Color bgColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Center(child: FaIcon(icon, size: 16, color: color)),
            ),
            const SizedBox(height: 12),
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
