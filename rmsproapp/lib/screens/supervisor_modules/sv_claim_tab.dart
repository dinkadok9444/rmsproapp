import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';
class SvClaimTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvClaimTab({required this.ownerID, required this.shopID});
  @override
  State<SvClaimTab> createState() => SvClaimTabState();
}

class SvClaimTabState extends State<SvClaimTab> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _branchId;
  final _searchCtrl = TextEditingController();
  String _filterStatus = 'ALL';
  List<Map<String, dynamic>> _claims = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
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

  Map<String, dynamic> _claimToUi(Map<String, dynamic> r) {
    Map<String, dynamic> extra = {};
    final c = r['catatan'];
    if (c is String && c.isNotEmpty) {
      try { extra = Map<String, dynamic>.from(jsonDecode(c) as Map); } catch (_) {}
    }
    return {
      'key': r['id'],
      'claimID': r['claim_code'] ?? '',
      'siri': r['siri'] ?? '',
      'nama': r['nama'] ?? extra['nama'] ?? '',
      'claimStatus': r['claim_status'] ?? 'CLAIM WAITING APPROVAL',
      'approvedBy': r['approved_by'] ?? extra['approvedBy'] ?? '',
      'approvedAt': _tsFromIso(r['approved_at']) != 0 ? _tsFromIso(r['approved_at']) : (extra['approvedAt'] ?? 0),
      'rejectedBy': extra['rejectedBy'] ?? '',
      'rejectReason': r['reject_reason'] ?? extra['rejectReason'] ?? '',
      'rejectedAt': extra['rejectedAt'] ?? 0,
      'timestamp': _tsFromIso(r['created_at']),
      ...extra,
    };
  }

  Future<void> _init() async {
    await _repairService.init();
    _branchId = _repairService.branchId;
    if (_branchId == null) return;
    _sub = _sb
        .from('claims')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>(_claimToUi).toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _claims = list);
    });
  }

  Future<void> _mergeCatatan(String docId, Map<String, dynamic> newFields) async {
    try {
      final existing = await _sb.from('claims').select('catatan').eq('id', docId).maybeSingle();
      Map<String, dynamic> extra = {};
      final c = existing?['catatan'];
      if (c is String && c.isNotEmpty) {
        try { extra = Map<String, dynamic>.from(jsonDecode(c) as Map); } catch (_) {}
      }
      extra.addAll(newFields);
      await _sb.from('claims').update({'catatan': jsonEncode(extra)}).eq('id', docId);
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_claims);
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list
          .where(
            (d) =>
                (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
                (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
                (d['claimID'] ?? '').toString().toLowerCase().contains(q),
          )
          .toList();
    }
    if (_filterStatus != 'ALL') {
      list = list
          .where(
            (d) =>
                (d['claimStatus'] ?? '').toString().toUpperCase() ==
                _filterStatus.toUpperCase(),
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

  Future<void> _approveClaim(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            FaIcon(FontAwesomeIcons.thumbsUp, size: 16, color: AppColors.blue),
            SizedBox(width: 8),
            Text(
              'Lulus Claim?',
              style: TextStyle(
                color: AppColors.blue,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: const Text(
          'Adakah anda pasti mahu meluluskan claim warranty ini?',
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('LULUS'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _sb.from('claims').update({
        'claim_status': 'CLAIM APPROVE',
        'approved_by': 'SUPERVISOR',
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', docId);
      await _mergeCatatan(docId, {'approvedBy': 'SUPERVISOR', 'approvedAt': DateTime.now().millisecondsSinceEpoch});
      _snack('Claim diluluskan');
    }
  }

  Future<void> _rejectClaim(String docId) async {
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
              'Tolak Claim?',
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
              'Nyatakan sebab penolakan:',
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
      await _sb.from('claims').update({
        'claim_status': 'CLAIM REJECTED',
        'reject_reason': reasonCtrl.text.trim(),
      }).eq('id', docId);
      await _mergeCatatan(docId, {
        'rejectedBy': 'SUPERVISOR',
        'rejectReason': reasonCtrl.text.trim(),
        'rejectedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _snack('Claim ditolak');
    }
  }

  String _fmt(dynamic ts) {
    if (ts is int && ts > 0)
      return DateFormat(
        'dd/MM/yy HH:mm',
      ).format(DateTime.fromMillisecondsSinceEpoch(ts));
    return '-';
  }

  Color _claimStatusColor(String s) {
    switch (s.toUpperCase()) {
      case 'CLAIM WAITING APPROVAL':
        return AppColors.yellow;
      case 'CLAIM APPROVE':
        return AppColors.blue;
      case 'CLAIM IN PROGRESS':
        return AppColors.orange;
      case 'CLAIM DONE':
        return AppColors.cyan;
      case 'CLAIM READY TO PICKUP':
        return const Color(0xFFA78BFA);
      case 'CLAIM COMPLETE':
        return AppColors.green;
      case 'CLAIM REJECTED':
        return AppColors.red;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pendingCount = _claims
        .where(
          (c) =>
              (c['claimStatus'] ?? '').toString().toUpperCase() ==
              'CLAIM WAITING APPROVAL',
        )
        .length;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: AppColors.blue, width: 2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.fileShield,
                    size: 14,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'KELULUSAN CLAIM WARRANTY',
                    style: TextStyle(
                      color: AppColors.blue,
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
                        '$pendingCount MENUNGGU',
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
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari siri / nama / claim ID...',
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in [
                      'ALL',
                      'CLAIM WAITING APPROVAL',
                      'CLAIM APPROVE',
                      'CLAIM IN PROGRESS',
                      'CLAIM COMPLETE',
                      'CLAIM REJECTED',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _filterStatus = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _filterStatus == s
                                  ? AppColors.blue
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _filterStatus == s
                                    ? AppColors.blue
                                    : AppColors.borderMed,
                              ),
                            ),
                            child: Text(
                              s == 'ALL' ? 'Semua' : s.replaceAll('CLAIM ', ''),
                              style: TextStyle(
                                color: _filterStatus == s
                                    ? Colors.white
                                    : AppColors.textMuted,
                                fontSize: 9,
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
                        FontAwesomeIcons.fileShield,
                        size: 40,
                        color: AppColors.textDim,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Tiada claim',
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
                    final c = filtered[i];
                    final status =
                        (c['claimStatus'] ?? 'CLAIM WAITING APPROVAL')
                            .toString()
                            .toUpperCase();
                    final col = _claimStatusColor(status);
                    final isWaiting = status == 'CLAIM WAITING APPROVAL';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border(left: BorderSide(color: col, width: 3)),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '#${c['siri'] ?? '-'}',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if ((c['claimID'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      c['claimID'],
                                      style: const TextStyle(
                                        color: AppColors.textDim,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
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
                                  status.replaceAll('CLAIM ', ''),
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
                          _infoRow(
                            'Pelanggan',
                            c['nama'] ?? '-',
                            FontAwesomeIcons.user,
                          ),
                          _infoRow(
                            'Model',
                            c['model'] ?? '-',
                            FontAwesomeIcons.mobileScreenButton,
                          ),
                          _infoRow(
                            'Kerosakan',
                            c['claimKerosakan'] ?? c['kerosakan'] ?? '-',
                            FontAwesomeIcons.screwdriverWrench,
                          ),
                          _infoRow(
                            'Warranty',
                            c['warranty'] ?? '-',
                            FontAwesomeIcons.shieldHalved,
                          ),
                          _infoRow(
                            'Tarikh',
                            _fmt(c['timestamp']),
                            FontAwesomeIcons.calendar,
                          ),
                          if (isWaiting) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                    onPressed: () => _approveClaim(c['key']),
                                    icon: const FaIcon(
                                      FontAwesomeIcons.thumbsUp,
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
                                    onPressed: () => _rejectClaim(c['key']),
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
                          if (status == 'CLAIM REJECTED' &&
                              (c['rejectReason'] ?? '')
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
                                      'Sebab: ${c['rejectReason']}',
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

  Widget _infoRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        FaIcon(icon, size: 10, color: AppColors.textDim),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textSub,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
