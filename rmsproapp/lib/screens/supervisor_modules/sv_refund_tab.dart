import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
class SvRefundTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvRefundTab({required this.ownerID, required this.shopID});
  @override
  State<SvRefundTab> createState() => SvRefundTabState();
}

class SvRefundTabState extends State<SvRefundTab> {
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  String _filterStatus = 'ALL';
  List<Map<String, dynamic>> _refunds = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _listen() {
    _sub = _db.collection('refunds_${widget.ownerID}').snapshots().listen((
      snap,
    ) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        d['key'] = doc.id;
        if ((d['shopID'] ?? '').toString().toUpperCase() == widget.shopID)
          list.add(d);
      }
      list.sort(
        (a, b) => ((b['timestamp'] ?? 0) as num).compareTo(
          (a['timestamp'] ?? 0) as num,
        ),
      );
      if (mounted) setState(() => _refunds = list);
    });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_refunds);
    final q = _searchCtrl.text.toUpperCase().trim();
    if (q.isNotEmpty) {
      list = list
          .where(
            (d) =>
                (d['siri'] ?? '').toString().toUpperCase().contains(q) ||
                (d['namaCust'] ?? '').toString().toUpperCase().contains(q),
          )
          .toList();
    }
    if (_filterStatus != 'ALL') {
      list = list
          .where(
            (d) =>
                (d['status'] ?? '').toString().toUpperCase() == _filterStatus,
          )
          .toList();
    }
    return list;
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

  Future<void> _approveRefund(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            FaIcon(
              FontAwesomeIcons.circleCheck,
              size: 16,
              color: AppColors.green,
            ),
            SizedBox(width: 8),
            Text(
              'Lulus Refund?',
              style: TextStyle(
                color: AppColors.green,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: const Text(
          'Adakah anda pasti mahu meluluskan refund ini?',
          style: TextStyle(color: AppColors.textSub, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('LULUS'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.collection('refunds_${widget.ownerID}').doc(docId).update({
        'status': 'APPROVED',
        'approvedBy': 'SUPERVISOR',
        'approvedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _snack('Refund diluluskan');
    }
  }

  Future<void> _rejectRefund(String docId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            FaIcon(
              FontAwesomeIcons.circleXmark,
              size: 16,
              color: AppColors.red,
            ),
            SizedBox(width: 8),
            Text(
              'Tolak Refund?',
              style: TextStyle(
                color: AppColors.red,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sila nyatakan sebab penolakan:',
              style: TextStyle(color: AppColors.textSub, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: 'Sebab...',
                hintStyle: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('TOLAK'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.collection('refunds_${widget.ownerID}').doc(docId).update({
        'status': 'REJECTED',
        'rejectedBy': 'SUPERVISOR',
        'rejectReason': reasonCtrl.text.trim(),
        'rejectedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _snack('Refund ditolak');
    }
  }

  String _fmt(dynamic ts) => ts is int
      ? DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(ts))
      : '-';

  Color _statusColor(String s) {
    final su = s.toUpperCase();
    if (su == 'APPROVED' || su == 'COMPLETED') return AppColors.green;
    if (su == 'REJECTED') return AppColors.red;
    return AppColors.yellow;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pendingCount = _refunds
        .where((r) => (r['status'] ?? '').toString().toUpperCase() == 'PENDING')
        .length;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: AppColors.red, width: 2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.moneyBillTransfer,
                        size: 14,
                        color: AppColors.red,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'KELULUSAN REFUND',
                        style: TextStyle(
                          color: AppColors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.yellow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$pendingCount PENDING',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Cari siri / nama...',
                        hintStyle: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        filled: true,
                        fillColor: AppColors.bgDeep,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in [
                      'ALL',
                      'PENDING',
                      'APPROVED',
                      'REJECTED',
                      'COMPLETED',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _filterStatus = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _filterStatus == s
                                  ? AppColors.red
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _filterStatus == s
                                    ? AppColors.red
                                    : AppColors.borderMed,
                              ),
                            ),
                            child: Text(
                              s == 'ALL' ? 'Semua' : s,
                              style: TextStyle(
                                color: _filterStatus == s
                                    ? Colors.white
                                    : AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.receipt,
                        size: 40,
                        color: AppColors.textDim,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Tiada permohonan refund',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    final status = (r['status'] ?? 'PENDING')
                        .toString()
                        .toUpperCase();
                    final col = _statusColor(status);
                    final amtRefund = ((r['amount'] ?? 0) as num)
                        .toStringAsFixed(2);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderMed),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.bg,
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '#${r['siri'] ?? '-'}',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.15),
                                  border: Border.all(color: col),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: col,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            r['namaCust'] ?? '-',
                            style: const TextStyle(
                              color: AppColors.yellow,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${r['model'] ?? '-'}  |  ${r['reason'] ?? '-'}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(r['timestamp']),
                                style: const TextStyle(
                                  color: AppColors.textDim,
                                  fontSize: 9,
                                ),
                              ),
                              Text(
                                'RM $amtRefund',
                                style: const TextStyle(
                                  color: AppColors.red,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          if (status == 'PENDING') ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                    onPressed: () => _approveRefund(r['key']),
                                    icon: const FaIcon(
                                      FontAwesomeIcons.check,
                                      size: 10,
                                    ),
                                    label: const Text(
                                      'LULUS',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                    onPressed: () => _rejectRefund(r['key']),
                                    icon: const FaIcon(
                                      FontAwesomeIcons.xmark,
                                      size: 10,
                                    ),
                                    label: const Text(
                                      'TOLAK',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (status == 'REJECTED' &&
                              (r['rejectReason'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const FaIcon(
                                    FontAwesomeIcons.circleInfo,
                                    size: 10,
                                    color: AppColors.red,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Sebab: ${r['rejectReason']}',
                                      style: const TextStyle(
                                        color: AppColors.red,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
