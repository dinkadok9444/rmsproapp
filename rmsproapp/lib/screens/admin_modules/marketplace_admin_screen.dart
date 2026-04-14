import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class MarketplaceAdminScreen extends StatefulWidget {
  const MarketplaceAdminScreen({super.key});
  @override
  State<MarketplaceAdminScreen> createState() => _MarketplaceAdminScreenState();
}

class _MarketplaceAdminScreenState extends State<MarketplaceAdminScreen>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  late TabController _tabCtrl;

  List<Map<String, dynamic>> _orders = [];
  StreamSubscription? _ordersSub;
  bool _loading = true;
  String _filterStatus = 'Semua';

  // Stats
  double _totalGMV = 0;
  double _totalCommission = 0;
  int _completedCount = 0;
  int _activeCount = 0;
  int _activeListings = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _listen();
    _loadStats();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _listen() {
    _ordersSub = _db
        .collection('marketplace_orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) {
        final data = d.data();
        data['_docId'] = d.id;
        return data;
      }).toList();

      double gmv = 0, comm = 0;
      int completed = 0, active = 0;
      for (final o in list) {
        final total =
            (o['totalPrice'] is num) ? (o['totalPrice'] as num).toDouble() : 0.0;
        final c =
            (o['commission'] is num) ? (o['commission'] as num).toDouble() : 0.0;
        final status = o['status'] ?? '';
        if (status == 'completed') {
          gmv += total;
          comm += c;
          completed++;
        }
        if (status == 'paid' || status == 'shipped') active++;
      }

      if (mounted) {
        setState(() {
          _orders = list;
          _totalGMV = gmv;
          _totalCommission = comm;
          _completedCount = completed;
          _activeCount = active;
          _loading = false;
        });
      }
    });
  }

  Future<void> _loadStats() async {
    final snap = await _db
        .collection('marketplace_global')
        .where('isActive', isEqualTo: true)
        .get();
    if (mounted) setState(() => _activeListings = snap.docs.length);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterStatus == 'Semua') return _orders;
    return _orders.where((o) => o['status'] == _filterStatus).toList();
  }

  String _fmtDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yy HH:mm').format(ts.toDate());
    }
    return '-';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending_payment':
        return const Color(0xFFF59E0B);
      case 'paid':
        return const Color(0xFF3B82F6);
      case 'shipped':
        return const Color(0xFF8B5CF6);
      case 'completed':
        return AppColors.green;
      case 'cancelled':
        return AppColors.red;
      default:
        return AppColors.textMuted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending_payment':
        return 'BELUM BAYAR';
      case 'paid':
        return 'DIBAYAR';
      case 'shipped':
        return 'DIHANTAR';
      case 'completed':
        return 'SELESAI';
      case 'cancelled':
        return 'DIBATALKAN';
      default:
        return s.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5CF6),
        foregroundColor: Colors.white,
        title: const Text(
          'MARKETPLACE ADMIN',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Stats
          _buildStats(),
          // Tabs
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                color: const Color(0xFF8B5CF6),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textDim,
              labelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'TRANSAKSI'),
                Tab(text: 'ANALITIK'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildTransactionTab(),
                _buildAnalyticsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _statCard('JUMLAH JUALAN', 'RM ${_totalGMV.toStringAsFixed(2)}',
              AppColors.green, FontAwesomeIcons.moneyBillTrendUp),
          const SizedBox(width: 8),
          _statCard('KOMISYEN 2%', 'RM ${_totalCommission.toStringAsFixed(2)}',
              const Color(0xFF8B5CF6), FontAwesomeIcons.percent),
          const SizedBox(width: 8),
          _statCard('AKTIF', '$_activeCount', const Color(0xFF3B82F6),
              FontAwesomeIcons.spinner),
          const SizedBox(width: 8),
          _statCard('SELESAI', '$_completedCount', AppColors.green,
              FontAwesomeIcons.circleCheck),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaIcon(icon, size: 12, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 7,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // TRANSAKSI TAB
  // ═══════════════════════════════════════
  Widget _buildTransactionTab() {
    return Column(
      children: [
        // Filter
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in [
                  'Semua',
                  'pending_payment',
                  'paid',
                  'shipped',
                  'completed',
                  'cancelled',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterStatus = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _filterStatus == f
                              ? const Color(0xFF8B5CF6)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _filterStatus == f
                                ? const Color(0xFF8B5CF6)
                                : AppColors.borderMed,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          f == 'Semua' ? 'Semua' : _statusLabel(f),
                          style: TextStyle(
                            color: _filterStatus == f
                                ? Colors.white
                                : AppColors.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Orders list
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(FontAwesomeIcons.inbox,
                              size: 36,
                              color: AppColors.textDim.withValues(alpha: 0.3)),
                          const SizedBox(height: 10),
                          const Text('Tiada transaksi',
                              style: TextStyle(
                                  color: AppColors.textDim, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _buildOrderCard(_filtered[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o) {
    final status = o['status'] ?? '';
    final col = _statusColor(status);
    final total =
        (o['totalPrice'] is num) ? (o['totalPrice'] as num).toDouble() : 0.0;
    final comm =
        (o['commission'] is num) ? (o['commission'] as num).toDouble() : 0.0;
    final payout =
        (o['sellerPayout'] is num) ? (o['sellerPayout'] as num).toDouble() : 0.0;
    final qty =
        (o['quantity'] is num) ? (o['quantity'] as num).toInt() : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                      color: col, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              Text(_fmtDate(o['createdAt']),
                  style:
                      const TextStyle(color: AppColors.textDim, fontSize: 9)),
            ],
          ),
          const SizedBox(height: 8),
          // Item
          Text(
            (o['itemName'] ?? '-').toString().toUpperCase(),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          // Buyer → Seller
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.shop,
                    size: 10, color: AppColors.textDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${(o['buyerShopName'] ?? '-').toString().toUpperCase()} → ${(o['sellerShopName'] ?? '-').toString().toUpperCase()}',
                    style: const TextStyle(
                        color: AppColors.textSub,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Price breakdown
          Row(
            children: [
              _chip('$qty unit', AppColors.textDim),
              const SizedBox(width: 6),
              _chip('RM ${total.toStringAsFixed(2)}', const Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              _chip('Kom: RM ${comm.toStringAsFixed(2)}',
                  const Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              _chip(
                  'Seller: RM ${payout.toStringAsFixed(2)}', AppColors.green),
            ],
          ),
          // Tracking
          if ((o['trackingNumber'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.truck,
                    size: 10, color: Color(0xFF3B82F6)),
                const SizedBox(width: 6),
                Text(
                  '${o['courierName'] ?? ''} ${o['trackingNumber']}',
                  style: const TextStyle(
                      color: Color(0xFF3B82F6),
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800),
      ),
    );
  }

  // ═══════════════════════════════════════
  // ANALITIK TAB
  // ═══════════════════════════════════════
  Widget _buildAnalyticsTab() {
    // Category breakdown
    final catCount = <String, int>{};
    final catRevenue = <String, double>{};
    for (final o in _orders) {
      if (o['status'] != 'completed') continue;
      final cat = (o['category'] ?? 'Lain-lain').toString();
      catCount[cat] = (catCount[cat] ?? 0) + 1;
      catRevenue[cat] = (catRevenue[cat] ?? 0) +
          ((o['totalPrice'] is num)
              ? (o['totalPrice'] as num).toDouble()
              : 0);
    }

    // Top sellers
    final sellerSales = <String, double>{};
    for (final o in _orders) {
      if (o['status'] != 'completed') continue;
      final name = (o['sellerShopName'] ?? '-').toString();
      sellerSales[name] = (sellerSales[name] ?? 0) +
          ((o['totalPrice'] is num)
              ? (o['totalPrice'] as num).toDouble()
              : 0);
    }
    final sortedSellers = sellerSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Row(
            children: [
              _analyticBox('Jumlah GMV', 'RM ${_totalGMV.toStringAsFixed(2)}',
                  AppColors.green),
              const SizedBox(width: 8),
              _analyticBox(
                  'Pendapatan Komisyen',
                  'RM ${_totalCommission.toStringAsFixed(2)}',
                  const Color(0xFF8B5CF6)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _analyticBox(
                  'Listing Aktif', '$_activeListings', const Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              _analyticBox(
                  'Jumlah Transaksi', '${_orders.length}', AppColors.textSub),
            ],
          ),
          const SizedBox(height: 16),

          // Category breakdown
          const Text('JUALAN MENGIKUT KATEGORI',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (catCount.isEmpty)
            const Text('Tiada data',
                style: TextStyle(color: AppColors.textDim, fontSize: 11))
          else
            ...catCount.entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Text(e.key,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('${e.value} unit',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 10)),
                      const SizedBox(width: 12),
                      Text(
                          'RM ${(catRevenue[e.key] ?? 0).toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: AppColors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                )),
          const SizedBox(height: 16),

          // Top sellers
          const Text('PENJUAL TERTINGGI',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (sortedSellers.isEmpty)
            const Text('Tiada data',
                style: TextStyle(color: AppColors.textDim, fontSize: 11))
          else
            ...sortedSellers.take(10).toList().asMap().entries.map((e) {
              final idx = e.key + 1;
              final seller = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: idx <= 3
                            ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                            : AppColors.bgDeep,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$idx',
                          style: TextStyle(
                            color: idx <= 3
                                ? const Color(0xFF8B5CF6)
                                : AppColors.textDim,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(seller.key.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    Text('RM ${seller.value.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _analyticBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

}
