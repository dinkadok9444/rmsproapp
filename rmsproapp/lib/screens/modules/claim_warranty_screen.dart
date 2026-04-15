import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../services/supabase_client.dart';
import '../../services/repair_service.dart';

const String _cloudRunUrl = 'https://rms-backend-94407896005.asia-southeast1.run.app';

class ClaimWarrantyScreen extends StatefulWidget {
  const ClaimWarrantyScreen({super.key});
  @override
  State<ClaimWarrantyScreen> createState() => _ClaimWarrantyScreenState();
}

class _ClaimWarrantyScreenState extends State<ClaimWarrantyScreen> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  final _lang = AppLanguage();
  final _searchCtrl = TextEditingController();
  final _repairSearchCtrl = TextEditingController();

  String _ownerID = 'admin';
  String _shopID = 'MAIN';
  String? _tenantId;
  String? _branchId;
  String _filterStatus = 'ALL';

  List<Map<String, dynamic>> _claims = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _repairs = [];
  List<Map<String, dynamic>> _repairSearchResults = [];
  List<String> _staffList = [];
  Map<String, dynamic> _branchSettings = {};

  StreamSubscription? _claimsSub;
  StreamSubscription? _repairsSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _claimsSub?.cancel();
    _repairsSub?.cancel();
    _searchCtrl.dispose();
    _repairSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _repairService.init();
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _listenClaims();
    _listenRepairs();
    _loadBranchSettings();
  }

  Map<String, dynamic> _claimRowToUi(Map r) {
    final m = Map<String, dynamic>.from(r);
    m['id'] = r['id'];
    m['claimID'] = r['claim_code'] ?? r['id'];
    m['siri'] = r['siri'] ?? '';
    m['nama'] = r['nama'] ?? '';
    m['claimStatus'] = r['claim_status'] ?? '';
    // Unpack catatan jsonb — stashed extra fields
    final catatan = r['catatan'];
    if (catatan is String && catatan.isNotEmpty) {
      try {
        final parsed = jsonDecode(catatan);
        if (parsed is Map) m.addAll(Map<String, dynamic>.from(parsed));
      } catch (_) {}
    }
    final c = r['created_at']?.toString();
    m['timestamp'] = c == null ? 0 : (DateTime.tryParse(c)?.millisecondsSinceEpoch ?? 0);
    return m;
  }

  void _listenClaims() {
    if (_branchId == null) return;
    _claimsSub = _sb
        .from('claims')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .order('created_at', ascending: false)
        .listen((rows) {
      final list = rows.map(_claimRowToUi).toList();
      if (mounted) setState(() { _claims = list; _applyFilter(); });
    });
  }

  void _listenRepairs() {
    if (_branchId == null) return;
    _repairsSub = _sb
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .order('created_at', ascending: false)
        .listen((rows) {
      final list = <Map<String, dynamic>>[];
      for (final r in rows) {
        final nama = (r['nama'] ?? '').toString().toUpperCase();
        final jenis = (r['jenis_servis'] ?? '').toString().toUpperCase();
        if (nama == 'JUALAN PANTAS' || jenis == 'JUALAN') continue;
        final m = Map<String, dynamic>.from(r);
        final c = r['created_at']?.toString();
        m['timestamp'] = c == null ? 0 : (DateTime.tryParse(c)?.millisecondsSinceEpoch ?? 0);
        list.add(m);
      }
      if (mounted) setState(() => _repairs = list);
    });
  }

  Future<void> _loadBranchSettings() async {
    if (_branchId == null) return;
    final row = await _sb
        .from('branches')
        .select('*, branch_staff(nama, status)')
        .eq('id', _branchId!)
        .maybeSingle();
    if (row == null) return;
    _branchSettings = Map<String, dynamic>.from(row);
    final staffRaw = row['branch_staff'];
    if (staffRaw is List) {
      _staffList = staffRaw
          .where((s) => s is Map && (s['status'] ?? 'active') == 'active')
          .map((s) => (s['nama'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (mounted) setState(() {});
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    var data = List<Map<String, dynamic>>.from(_claims);
    if (_filterStatus == 'ALL') {
      // Semua view: sembunyikan claim yang sudah approve
      data = data.where((d) => (d['claimStatus'] ?? '').toString().toUpperCase() != 'CLAIM APPROVE').toList();
    } else {
      data = data.where((d) => (d['claimStatus'] ?? '').toString().toUpperCase() == _filterStatus.toUpperCase()).toList();
    }
    if (q.isNotEmpty) {
      data = data.where((d) =>
        (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
        (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
        (d['tel'] ?? '').toString().toLowerCase().contains(q) ||
        (d['model'] ?? '').toString().toLowerCase().contains(q) ||
        (d['claimID'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    _filtered = data;
  }

  // ════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════
  String _fmt(dynamic ts) {
    if (ts is int) return DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts));
    if (ts is String && ts.isNotEmpty) return ts.replaceAll('T', ' ');
    return '-';
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Color _claimStatusColor(String s) {
    switch (s.toUpperCase()) {
      case 'CLAIM WAITING APPROVAL': return AppColors.yellow;
      case 'CLAIM APPROVE': return AppColors.blue;
      case 'CLAIM IN PROGRESS': return AppColors.orange;
      case 'CLAIM DONE': return AppColors.cyan;
      case 'CLAIM READY TO PICKUP': return const Color(0xFFA78BFA);
      case 'CLAIM COMPLETE': return AppColors.green;
      default: return AppColors.textMuted;
    }
  }

  IconData _claimStatusIcon(String s) {
    switch (s.toUpperCase()) {
      case 'CLAIM WAITING APPROVAL': return FontAwesomeIcons.hourglassHalf;
      case 'CLAIM APPROVE': return FontAwesomeIcons.thumbsUp;
      case 'CLAIM IN PROGRESS': return FontAwesomeIcons.screwdriverWrench;
      case 'CLAIM DONE': return FontAwesomeIcons.circleCheck;
      case 'CLAIM READY TO PICKUP': return FontAwesomeIcons.handHoldingHand;
      case 'CLAIM COMPLETE': return FontAwesomeIcons.flagCheckered;
      default: return FontAwesomeIcons.clock;
    }
  }

  String _calcWarrantyExpiry(String warrantyType, int tempohDays, dynamic baseTimestamp) {
    if (warrantyType == 'TIADA' || tempohDays <= 0) return '';
    DateTime base;
    if (baseTimestamp is int) {
      base = DateTime.fromMillisecondsSinceEpoch(baseTimestamp);
    } else {
      base = DateTime.now();
    }
    final expiry = base.add(Duration(days: tempohDays));
    return DateFormat('dd/MM/yyyy').format(expiry);
  }

  bool _isWarrantyExpired(String expiryStr) {
    if (expiryStr.isEmpty) return false;
    try {
      final expiry = DateFormat('dd/MM/yyyy').parse(expiryStr);
      return DateTime.now().isAfter(expiry);
    } catch (_) {
      return false;
    }
  }

  String _generateClaimID() {
    final now = DateTime.now();
    return 'CLM${DateFormat('yyyyMMddHHmmss').format(now)}';
  }

  // ════════════════════════════════════════
  // SEARCH REPAIRS & REGISTER NEW CLAIM
  // ════════════════════════════════════════
  void _showRegisterClaimModal() {
    _repairSearchCtrl.clear();
    _repairSearchResults.clear();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.4, expand: false,
          builder: (_, scroll) => Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(_lang.get('cw_cari_repair'), style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
                  ]),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
                ]),
                const SizedBox(height: 4),
                Text(_lang.get('cw_cari_desc'), style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                const SizedBox(height: 12),
                TextField(
                  controller: _repairSearchCtrl,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  onChanged: (val) {
                    final q = val.toLowerCase().trim();
                    if (q.isEmpty) {
                      setS(() => _repairSearchResults.clear());
                      return;
                    }
                    setS(() {
                      _repairSearchResults = _repairs.where((r) =>
                        (r['siri'] ?? '').toString().toLowerCase().contains(q) ||
                        (r['tel'] ?? '').toString().toLowerCase().contains(q)).take(20).toList();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: _lang.get('cw_masukkan_siri'),
                    hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                    suffixIcon: _repairSearchCtrl.text.isNotEmpty
                      ? GestureDetector(onTap: () { _repairSearchCtrl.clear(); setS(() => _repairSearchResults.clear()); },
                          child: const Icon(Icons.close, color: AppColors.red, size: 18))
                      : null,
                    filled: true, fillColor: AppColors.bgDeep,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10), isDense: true,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${_repairSearchResults.length} keputusan', style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: _repairSearchResults.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(FontAwesomeIcons.fileCircleQuestion, size: 40, color: AppColors.textDim),
                    const SizedBox(height: 12),
                    Text(_lang.get('cw_cari_repair_daftar'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _repairSearchResults.length,
                    itemBuilder: (_, i) {
                      final r = _repairSearchResults[i];
                      final siri = r['siri'] ?? '-';
                      final status = (r['status'] ?? '').toString().toUpperCase();
                      final warranty = (r['warranty'] ?? 'TIADA').toString();
                      final hasWarranty = warranty != 'TIADA' && warranty.isNotEmpty;
                      final alreadyClaimed = _claims.any((c) => (c['siri'] ?? '') == siri);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12),
                          border: Border(left: BorderSide(color: hasWarranty ? AppColors.yellow : AppColors.textDim, width: 3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Row(children: [
                              Text('#$siri', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 8),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.textDim.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text(status, style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w900))),
                            ]),
                            if (hasWarranty)
                              Row(children: [
                                const FaIcon(FontAwesomeIcons.shieldHalved, size: 9, color: AppColors.yellow),
                                const SizedBox(width: 4),
                                Text(warranty, style: const TextStyle(color: AppColors.yellow, fontSize: 9, fontWeight: FontWeight.w800)),
                              ]),
                          ]),
                          const SizedBox(height: 6),
                          Text((r['nama'] ?? '-').toString().toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                          Text('${r['model'] ?? '-'}  |  ${r['tel'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                          Text('Kerosakan: ${r['kerosakan'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                          Text('Tarikh: ${_fmt(r['timestamp'])}', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                          if (r['warranty_exp'] != null && r['warranty_exp'].toString().isNotEmpty)
                            Text('Warranty Tamat: ${r['warranty_exp']}', style: TextStyle(
                              color: _isWarrantyExpired(r['warranty_exp'].toString()) ? AppColors.red : AppColors.green,
                              fontSize: 9, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          SizedBox(width: double.infinity, child: alreadyClaimed
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(color: AppColors.textMuted.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const FaIcon(FontAwesomeIcons.circleCheck, size: 10, color: AppColors.textMuted),
                                  const SizedBox(width: 6),
                                  Text(_lang.get('cw_sudah_didaftarkan'), style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w900)),
                                ]),
                              )
                            : ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _registerClaim(r);
                                },
                                icon: const FaIcon(FontAwesomeIcons.plus, size: 10),
                                label: Text(_lang.get('cw_daftar_claim')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.blue, foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                                ),
                              ),
                          ),
                        ]),
                      );
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _registerClaim(Map<String, dynamic> repair) async {
    if (_tenantId == null || _branchId == null) return;
    final claimID = _generateClaimID();
    final now = DateTime.now();

    // Extra fields stashed dalam catatan jsonb
    final extra = {
      'claimID': claimID,
      'tel': repair['tel'] ?? '-',
      'tel_wasap': repair['tel_wasap'] ?? '',
      'model': repair['model'] ?? '-',
      'kerosakan': repair['kerosakan'] ?? '-',
      'harga': repair['harga'] ?? '0',
      'total': repair['total'] ?? '0',
      'items_array': repair['items_array'] ?? [],
      'originalWarranty': repair['warranty'] ?? 'TIADA',
      'originalWarrantyExp': repair['warranty_exp'] ?? '',
      'claimWarranty': 'TIADA',
      'claimWarrantyTempoh': 0,
      'claimWarrantyExp': '',
      'nota': '',
      'staffTerima': '',
      'staffRepair': '',
      'staffSerah': '',
      'tarikhHantar': DateFormat("yyyy-MM-dd'T'HH:mm").format(now),
      'tarikhSiap': '',
      'tarikhPickup': '',
    };

    try {
      await _sb.from('claims').insert({
        'tenant_id': _tenantId,
        'branch_id': _branchId,
        'job_id': repair['id'],
        'siri': repair['siri'] ?? '-',
        'claim_code': claimID,
        'nama': repair['nama'] ?? '-',
        'claim_status': 'Claim Waiting Approval',
        'catatan': jsonEncode(extra),
      });
      _snack('Claim #$claimID berjaya didaftarkan!');
    } catch (e) {
      _snack('Ralat: $e', err: true);
    }
  }

  // ════════════════════════════════════════
  // UPDATE CLAIM MODAL
  // ════════════════════════════════════════
  void _showUpdateClaimModal(Map<String, dynamic> claim) {
    final docID = claim['id'] ?? claim['claimID'] ?? '';
    final claimID = claim['claimID'] ?? docID;
    String claimStatus = (claim['claimStatus'] ?? 'Claim Waiting Approval').toString();
    String nota = (claim['nota'] ?? '').toString();
    String staffTerima = (claim['staffTerima'] ?? '').toString();
    String staffRepair = (claim['staffRepair'] ?? '').toString();
    String staffSerah = (claim['staffSerah'] ?? '').toString();
    String tarikhHantar = (claim['tarikhHantar'] ?? '').toString();
    String tarikhSiap = (claim['tarikhSiap'] ?? '').toString();
    String tarikhPickup = (claim['tarikhPickup'] ?? '').toString();
    String claimWarranty = (claim['claimWarranty'] ?? 'TIADA').toString();
    int claimWarrantyTempoh = claim['claimWarrantyTempoh'] is int ? claim['claimWarrantyTempoh'] : 0;
    String claimWarrantyExp = (claim['claimWarrantyExp'] ?? '').toString();

    final notaCtrl = TextEditingController(text: nota);

    final allStatuses = [
      'Claim Waiting Approval',
      'Claim Approve',
      'Claim In Progress',
      'Claim Done',
      'Claim Ready to Pickup',
      'Claim Complete',
    ];

    final warrantyOptions = ['TIADA', 'ASAL', 'TAMBAH'];
    final tempohOptions = [7, 14, 30, 90];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void recalcWarrantyExp() {
            if (claimWarranty == 'TIADA') {
              claimWarrantyExp = '';
            } else if (claimWarranty == 'ASAL') {
              claimWarrantyExp = (claim['originalWarrantyExp'] ?? '').toString();
            } else if (claimWarranty == 'TAMBAH' && claimWarrantyTempoh > 0) {
              claimWarrantyExp = _calcWarrantyExpiry('TAMBAH', claimWarrantyTempoh, claim['timestamp']);
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.92, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
            builder: (_, scroll) => SingleChildScrollView(
              controller: scroll, padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // HEADER
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Row(children: [
                    const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: AppColors.blue),
                    const SizedBox(width: 8),
                    Text('${_lang.get('kemaskini')} ', style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
                    Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.blue.withValues(alpha: 0.2))),
                      child: Text('#$claimID', style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis))),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
                ]),
                const SizedBox(height: 6),

                // CUSTOMER INFO
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderMed)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.user, size: 10, color: AppColors.textDim), const SizedBox(width: 6),
                      Expanded(child: Text((claim['nama'] ?? '-').toString().toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w900))),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.phone, size: 9, color: AppColors.textDim), const SizedBox(width: 6),
                      Text(claim['tel'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      const SizedBox(width: 12),
                      const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 9, color: AppColors.textDim), const SizedBox(width: 6),
                      Expanded(child: Text(claim['model'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.screwdriverWrench, size: 9, color: AppColors.textDim), const SizedBox(width: 6),
                      Expanded(child: Text('Asal: ${claim['kerosakan'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10))),
                    ]),
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.hashtag, size: 9, color: AppColors.textMuted), const SizedBox(width: 6),
                      Text('Siri Repair: #${claim['siri'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ]),
                    if ((claim['originalWarranty'] ?? 'TIADA') != 'TIADA') ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const FaIcon(FontAwesomeIcons.shieldHalved, size: 9, color: AppColors.yellow), const SizedBox(width: 6),
                        Text('Warranty Asal: ${claim['originalWarranty']}', style: const TextStyle(color: AppColors.yellow, fontSize: 10, fontWeight: FontWeight.w700)),
                        if ((claim['originalWarrantyExp'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('(Tamat: ${claim['originalWarrantyExp']})', style: TextStyle(
                            color: _isWarrantyExpired(claim['originalWarrantyExp'].toString()) ? AppColors.red : AppColors.green,
                            fontSize: 9, fontWeight: FontWeight.w700)),
                        ],
                      ]),
                    ],
                  ]),
                ),

                // STATUS
                _editLabel('STATUS CLAIM'),
                _buildClaimStatusDropdown(claimStatus, allStatuses, (v) {
                  setS(() {
                    claimStatus = v!;
                    final nowStr = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now());
                    if (claimStatus == 'Claim In Progress' && tarikhHantar.isEmpty) {
                      tarikhHantar = nowStr;
                    }
                    if (claimStatus == 'Claim Done' || claimStatus == 'Claim Ready to Pickup') {
                      if (tarikhSiap.isEmpty) tarikhSiap = nowStr;
                    }
                    if (claimStatus == 'Claim Complete') {
                      if (tarikhSiap.isEmpty) tarikhSiap = nowStr;
                      if (tarikhPickup.isEmpty) tarikhPickup = nowStr;
                    }
                  });
                }),
                const SizedBox(height: 14),

                // DATES
                Container(
                  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cyan.withValues(alpha: 0.1))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.calendarDays, size: 10, color: AppColors.cyan), const SizedBox(width: 6),
                      Text(_lang.get('tarikh'), style: const TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Tarikh Hantar'),
                        _editDateField(tarikhHantar, (v) => setS(() => tarikhHantar = v)),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Tarikh Siap'),
                        _editDateField(tarikhSiap, (v) => setS(() => tarikhSiap = v)),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Tarikh Pickup'),
                        _editDateField(tarikhPickup, (v) => setS(() => tarikhPickup = v)),
                      ])),
                    ]),
                  ]),
                ),

                // STAFF
                Container(
                  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.blue.withValues(alpha: 0.1))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.userGear, size: 10, color: AppColors.blue), const SizedBox(width: 6),
                      Text(_lang.get('staf'), style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Staf Terima'),
                        _editDropdown(staffTerima, ['', ..._staffList], (v) => setS(() => staffTerima = v ?? '')),
                      ])),
                      const SizedBox(width: 6),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Staf Repair'),
                        _editDropdown(staffRepair, ['', ..._staffList], (v) => setS(() => staffRepair = v ?? '')),
                      ])),
                      const SizedBox(width: 6),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Staf Serah'),
                        _editDropdown(staffSerah, ['', ..._staffList], (v) => setS(() => staffSerah = v ?? '')),
                      ])),
                    ]),
                  ]),
                ),

                // WARRANTY
                Container(
                  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.1))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const FaIcon(FontAwesomeIcons.shieldHalved, size: 10, color: AppColors.yellow), const SizedBox(width: 6),
                      Text(_lang.get('cw_claim_warranty'), style: const TextStyle(color: AppColors.yellow, fontSize: 10, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _editLabel('Jenis Warranty'),
                        _editDropdown(claimWarranty, warrantyOptions, (v) {
                          setS(() {
                            claimWarranty = v ?? 'TIADA';
                            if (claimWarranty == 'TIADA') claimWarrantyTempoh = 0;
                            if (claimWarranty == 'ASAL') claimWarrantyTempoh = 0;
                            if (claimWarranty == 'TAMBAH' && claimWarrantyTempoh == 0) claimWarrantyTempoh = 7;
                            recalcWarrantyExp();
                          });
                        }),
                      ])),
                      if (claimWarranty == 'TAMBAH') ...[
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _editLabel('Tempoh (Hari)'),
                          _editDropdown('$claimWarrantyTempoh', tempohOptions.map((e) => '$e').toList(), (v) {
                            setS(() {
                              claimWarrantyTempoh = int.tryParse(v ?? '7') ?? 7;
                              recalcWarrantyExp();
                            });
                          }),
                        ])),
                      ],
                    ]),
                    if (claimWarrantyExp.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity, padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isWarrantyExpired(claimWarrantyExp) ? AppColors.red.withValues(alpha: 0.1) : AppColors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _isWarrantyExpired(claimWarrantyExp) ? AppColors.red.withValues(alpha: 0.3) : AppColors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          FaIcon(
                            _isWarrantyExpired(claimWarrantyExp) ? FontAwesomeIcons.triangleExclamation : FontAwesomeIcons.shieldHalved,
                            size: 10, color: _isWarrantyExpired(claimWarrantyExp) ? AppColors.red : AppColors.green),
                          const SizedBox(width: 6),
                          Text(
                            'WARRANTY TAMAT: $claimWarrantyExp',
                            style: TextStyle(
                              color: _isWarrantyExpired(claimWarrantyExp) ? AppColors.red : AppColors.green,
                              fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),

                // NOTA
                _editLabel('NOTA / CATATAN'),
                TextField(
                  controller: notaCtrl, maxLines: 3,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: _lang.get('cw_tulis_nota'),
                    hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                    filled: true, fillColor: AppColors.bgDeep, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),

                // ACTION BUTTONS
                Row(children: [
                  Expanded(flex: 2, child: ElevatedButton.icon(
                    onPressed: () async {
                      final updateData = {
                        'claimStatus': claimStatus,
                        'nota': notaCtrl.text.trim(),
                        'staffTerima': staffTerima,
                        'staffRepair': staffRepair,
                        'staffSerah': staffSerah,
                        'tarikhHantar': tarikhHantar,
                        'tarikhSiap': tarikhSiap,
                        'tarikhPickup': tarikhPickup,
                        'claimWarranty': claimWarranty,
                        'claimWarrantyTempoh': claimWarrantyTempoh,
                        'claimWarrantyExp': claimWarrantyExp,
                        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                      };
                      try {
                        // Merge updateData (UI keys) ke catatan jsonb + map status ke claim_status
                        await _sb.from('claims').update({
                          'claim_status': updateData['claimStatus'],
                          'catatan': jsonEncode(updateData),
                        }).eq('id', docID);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Claim #$claimID berjaya dikemaskini');
                      } catch (e) {
                        _snack('Ralat: $e', err: true);
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
                    label: Text(_lang.get('simpan')),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showPrintClaimModal(claim, claimStatus: claimStatus, nota: notaCtrl.text.trim(),
                        staffTerima: staffTerima, staffRepair: staffRepair, staffSerah: staffSerah,
                        tarikhHantar: tarikhHantar, tarikhSiap: tarikhSiap, tarikhPickup: tarikhPickup,
                        claimWarranty: claimWarranty, claimWarrantyTempoh: claimWarrantyTempoh, claimWarrantyExp: claimWarrantyExp);
                    },
                    icon: const FaIcon(FontAwesomeIcons.print, size: 12),
                    label: Text(_lang.get('cetak')),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                  )),
                ]),
                const SizedBox(height: 10),

                // DELETE BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Row(children: [
                            const FaIcon(FontAwesomeIcons.triangleExclamation, size: 18, color: AppColors.red),
                            const SizedBox(width: 8),
                            Text(_lang.get('cw_padam_claim'), style: const TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
                          ]),
                          content: Text('${_lang.get('cw_pasti_padam')} #$claimID?\n\n${_lang.get('cw_tidak_boleh_batal')}',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: Text(_lang.get('batal'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(dCtx);
                                try {
                                  await _sb.from('claims').delete().eq('id', docID);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _snack('Claim #$claimID berjaya dipadam');
                                } catch (e) {
                                  _snack('Ralat padam: $e', err: true);
                                }
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
                              child: Text(_lang.get('padam'), style: const TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const FaIcon(FontAwesomeIcons.trashCan, size: 12),
                    label: Text(_lang.get('cw_padam_claim')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red.withValues(alpha: 0.1),
                      foregroundColor: AppColors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.red, width: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════
  // PRINT / PDF MODAL
  // ════════════════════════════════════════
  void _showPrintClaimModal(Map<String, dynamic> claim, {
    String? claimStatus, String? nota, String? staffTerima, String? staffRepair, String? staffSerah,
    String? tarikhHantar, String? tarikhSiap, String? tarikhPickup,
    String? claimWarranty, int? claimWarrantyTempoh, String? claimWarrantyExp,
  }) {
    final claimID = claim['claimID'] ?? claim['id'] ?? '-';
    final hasPdf = (claim['pdfUrl_CLAIM'] ?? '').toString().isNotEmpty;

    final merged = Map<String, dynamic>.from(claim);
    if (claimStatus != null) merged['claimStatus'] = claimStatus;
    if (nota != null) merged['nota'] = nota;
    if (staffTerima != null) merged['staffTerima'] = staffTerima;
    if (staffRepair != null) merged['staffRepair'] = staffRepair;
    if (staffSerah != null) merged['staffSerah'] = staffSerah;
    if (tarikhHantar != null) merged['tarikhHantar'] = tarikhHantar;
    if (tarikhSiap != null) merged['tarikhSiap'] = tarikhSiap;
    if (tarikhPickup != null) merged['tarikhPickup'] = tarikhPickup;
    if (claimWarranty != null) merged['claimWarranty'] = claimWarranty;
    if (claimWarrantyTempoh != null) merged['claimWarrantyTempoh'] = claimWarrantyTempoh;
    if (claimWarrantyExp != null) merged['claimWarrantyExp'] = claimWarrantyExp;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.print, size: 14, color: AppColors.primary), const SizedBox(width: 8),
            Expanded(child: Text('CETAK CLAIM #$claimID', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900))),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          _printBtn('PRINT LABEL', 'Cetak label ke printer Bluetooth', FontAwesomeIcons.tag, AppColors.orange, () async {
            Navigator.pop(ctx);
            _printClaimLabel(merged);
          }),
          const SizedBox(height: 8),
          _printBtn('RESIT 80MM', 'Cetak resit claim ke printer Bluetooth', FontAwesomeIcons.receipt, AppColors.blue, () async {
            Navigator.pop(ctx);
            _snack('Menyambung printer...');
            final ok = await _printClaimReceipt(merged);
            _snack(ok ? 'Cetak berjaya!' : 'Gagal cetak - sila sambung printer di Settings', err: !ok);
          }),
          const SizedBox(height: 8),
          hasPdf
            ? _printBtn('VIEW CLAIM PDF', 'Sudah dijana - tekan untuk buka', FontAwesomeIcons.eye, AppColors.green, () {
                Navigator.pop(ctx);
                _downloadAndOpenPDF(claim['pdfUrl_CLAIM'], 'CLAIM', claimID);
              })
            : _printBtn('GENERATE CLAIM PDF', 'Jana dokumen claim PDF', FontAwesomeIcons.filePdf, AppColors.green, () {
                Navigator.pop(ctx);
                _generateClaimPDF(merged);
              }),
        ]),
      ),
    );
  }

  Widget _printBtn(String title, String desc, IconData icon, Color color, VoidCallback onTap) {
    return Material(color: Colors.transparent, child: InkWell(
      borderRadius: BorderRadius.circular(10), onTap: onTap,
      child: Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Center(child: FaIcon(icon, size: 16, color: color))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
            Text(desc, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
          ])),
          FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: color.withValues(alpha: 0.5)),
        ])),
    ));
  }

  // ════════════════════════════════════════
  // 80MM THERMAL PRINT
  // ════════════════════════════════════════
  Future<bool> _printClaimReceipt(Map<String, dynamic> claim) async {
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
    final namaKedai = (s['shopName'] ?? s['namaKedai'] ?? 'RMS PRO').toString().toUpperCase();
    final telKedai = s['phone'] ?? s['ownerContact'] ?? '-';
    final alamat = s['address'] ?? s['alamat'] ?? '';

    final cID = claim['claimID'] ?? '-';
    final siriRepair = claim['siri'] ?? '-';
    final nama = claim['nama'] ?? '-';
    final tel = claim['tel'] ?? '-';
    final model = claim['model'] ?? '-';
    final kerosakan = claim['kerosakan'] ?? '-';
    final cStatus = claim['claimStatus'] ?? '-';
    final tHantar = (claim['tarikhHantar'] ?? '').toString().replaceAll('T', ' ');
    final tSiap = (claim['tarikhSiap'] ?? '').toString().replaceAll('T', ' ');
    final tPickup = (claim['tarikhPickup'] ?? '').toString().replaceAll('T', ' ');
    final sTerima = claim['staffTerima'] ?? '-';
    final sRepair = claim['staffRepair'] ?? '-';
    final sSerah = claim['staffSerah'] ?? '-';
    final cWarranty = claim['claimWarranty'] ?? 'TIADA';
    final cWarrantyExp = claim['claimWarrantyExp'] ?? '';
    final cNota = claim['nota'] ?? '';

    var r = escInit;
    r += escCenter + escDblSize + escBoldOn;
    r += tengah(namaKedai.length > 24 ? namaKedai.substring(0, 24) : namaKedai, (lebar / 2).floor());
    r += escNormal + escBoldOff;
    if (alamat.isNotEmpty) r += tengah(alamat.length > lebar ? alamat.substring(0, lebar) : alamat);
    r += tengah('Tel: $telKedai');
    r += garis;

    r += escCenter + escDblHeight + escBoldOn;
    r += tengah('*** RESIT CLAIM WARRANTY ***');
    r += escNormal + escBoldOff + escLeft;
    r += garis2;

    r += baris('No. Claim', ': $cID');
    r += baris('No. Repair', ': $siriRepair');
    r += baris('Status', ': $cStatus');
    r += garis2;

    r += '$escBoldOn MAKLUMAT PELANGGAN\n$escBoldOff';
    r += garis2;
    r += baris('Nama', ': ${nama.toString().length > 28 ? nama.toString().substring(0, 28) : nama}');
    r += baris('No. Tel', ': $tel');
    r += garis2;

    r += '$escBoldOn MAKLUMAT PERANTI\n$escBoldOff';
    r += garis2;
    r += baris('Model', ': ${model.toString().length > 28 ? model.toString().substring(0, 28) : model}');
    r += baris('Kerosakan', ': ${kerosakan.toString().length > 28 ? kerosakan.toString().substring(0, 28) : kerosakan}');
    r += garis2;

    r += '$escBoldOn TARIKH\n$escBoldOff';
    r += garis2;
    if (tHantar.isNotEmpty) r += baris('Hantar', ': $tHantar');
    if (tSiap.isNotEmpty) r += baris('Siap', ': $tSiap');
    if (tPickup.isNotEmpty) r += baris('Pickup', ': $tPickup');
    r += garis2;

    r += '$escBoldOn STAF\n$escBoldOff';
    r += garis2;
    r += baris('Terima', ': $sTerima');
    r += baris('Repair', ': $sRepair');
    r += baris('Serah', ': $sSerah');
    r += garis2;

    if (cWarranty != 'TIADA') {
      r += '$escBoldOn WARRANTY CLAIM\n$escBoldOff';
      r += garis2;
      r += baris('Jenis', ': $cWarranty');
      if (cWarrantyExp.isNotEmpty) r += baris('Tamat', ': $cWarrantyExp');
      r += garis2;
    }

    if (cNota.isNotEmpty) {
      r += '$escBoldOn NOTA\n$escBoldOff';
      r += garis2;
      r += '${cNota.toString().length > lebar ? cNota.toString().substring(0, lebar) : cNota}\n';
      r += garis2;
    }

    r += garis;
    r += '${escCenter}${escBoldOn}Terima Kasih / Thank You!\n$escBoldOff';
    final notaFooter = s['notaClaim'] ?? s['notaQuotation'] ?? 'Sila simpan resit ini untuk rujukan.';
    r += tengah(notaFooter.toString().length > lebar ? notaFooter.toString().substring(0, lebar) : notaFooter.toString());
    r += garis2;
    r += tengah('~ Powered by RMS Pro ~');
    r += garis;
    r += '\x0A\x0A\x0A\x1D\x56\x00';

    final bytes = utf8.encode(r);
    return await PrinterService().printRaw(bytes);
  }

  // ════════════════════════════════════════
  // LABEL PRINT (claim warranty)
  // ════════════════════════════════════════
  Future<void> _printClaimLabel(Map<String, dynamic> claim) async {
    final ps = PrinterService();
    final job = Map<String, dynamic>.from(claim);
    // Map claim fields to label fields
    job['siri'] = claim['claimID'] ?? claim['siri'] ?? '-';
    job['nama'] = claim['nama'] ?? '-';
    job['tel'] = claim['tel'] ?? '-';
    job['model'] = claim['model'] ?? '-';
    job['kerosakan'] = claim['kerosakan'] ?? '-';
    job['harga'] = claim['harga'] ?? '0';
    job['password'] = claim['password'] ?? '';
    final ok = await ps.printLabel(job, _branchSettings);
    if (ok) {
      _snack('Label berjaya dicetak');
    } else {
      _snack('Gagal cetak label — pastikan printer dihidupkan & Bluetooth aktif', err: true);
    }
  }

  // ════════════════════════════════════════
  // PDF GENERATION VIA CLOUD RUN
  // ════════════════════════════════════════
  Map<String, dynamic> _buildClaimPdfPayload(Map<String, dynamic> claim) {
    List<Map<String, dynamic>> itemPDF = [];
    if (claim['items_array'] is List && (claim['items_array'] as List).isNotEmpty) {
      itemPDF = (claim['items_array'] as List).map((i) => Map<String, dynamic>.from(i as Map)).toList();
    } else {
      itemPDF = [{'nama': '${claim['model'] ?? '-'} (${claim['kerosakan'] ?? '-'})', 'harga': double.tryParse(claim['harga']?.toString() ?? '0') ?? 0}];
    }
    return {
      'typePDF': 'CLAIM',
      'paperSize': 'A4',
      'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
      'logoBase64': _branchSettings['logoBase64'] ?? '',
      'namaKedai': _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'RMS PRO',
      'alamatKedai': _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
      'telKedai': _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
      'noJob': claim['siri'] ?? '-',
      'claimID': claim['claimID'] ?? '-',
      'claimStatus': claim['claimStatus'] ?? '-',
      'namaCust': claim['nama'] ?? '-',
      'telCust': claim['tel'] ?? '-',
      'model': claim['model'] ?? '-',
      'kerosakan': claim['kerosakan'] ?? '-',
      'tarikhHantar': (claim['tarikhHantar'] ?? '').toString().split('T').first,
      'tarikhSiap': (claim['tarikhSiap'] ?? '').toString().split('T').first,
      'tarikhPickup': (claim['tarikhPickup'] ?? '').toString().split('T').first,
      'staffTerima': claim['staffTerima'] ?? '-',
      'staffRepair': claim['staffRepair'] ?? '-',
      'staffSerah': claim['staffSerah'] ?? '-',
      'claimWarranty': claim['claimWarranty'] ?? 'TIADA',
      'claimWarrantyExp': claim['claimWarrantyExp'] ?? '',
      'nota': claim['nota'] ?? '',
      'items': itemPDF,
      'totalDibayar': double.tryParse(claim['total']?.toString() ?? '0') ?? 0,
    };
  }

  Future<void> _generateClaimPDF(Map<String, dynamic> claim) async {
    if (!mounted) return;
    final claimID = claim['claimID'] ?? claim['id'] ?? '-';

    showDialog(context: context, barrierDismissible: false, builder: (_) => Center(
      child: Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppColors.primary), const SizedBox(height: 16),
          Text(_lang.get('cw_menjana_pdf_claim'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
        ]))));

    try {
      final response = await http.post(
        Uri.parse('$_cloudRunUrl/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_buildClaimPdfPayload(claim)),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          // Store pdfUrl dalam catatan jsonb (schema takde pdfUrl column)
          final cur = await _sb.from('claims').select('catatan').eq('claim_code', claimID).maybeSingle();
          Map<String, dynamic> extra = {};
          final c = cur?['catatan'];
          if (c is String && c.isNotEmpty) {
            try { extra = Map<String, dynamic>.from(jsonDecode(c) as Map); } catch (_) {}
          }
          extra['pdfUrl_CLAIM'] = pdfUrl;
          await _sb.from('claims').update({'catatan': jsonEncode(extra)}).eq('claim_code', claimID);
          _snack('PDF Claim berjaya dijana!');
          _downloadAndOpenPDF(pdfUrl, 'CLAIM', claimID);
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

  Future<void> _downloadAndOpenPDF(String pdfUrl, String typePDF, String docID) async {
    _snack('Memuat turun $typePDF...');
    try {
      if (kIsWeb) {
        if (!mounted) return;
        launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final fileName = '${typePDF}_$docID.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (!file.existsSync()) {
        await Dio().download(pdfUrl, filePath);
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context, backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.filePdf, size: 14, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('$typePDF #$docID', style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.circleCheck, size: 24, color: AppColors.green),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('cw_pdf_sedia'), style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
                  Text(fileName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ])),
              ]),
            ),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); OpenFilex.open(filePath); },
              icon: const FaIcon(FontAwesomeIcons.fileCircleCheck, size: 14),
              label: Text(_lang.get('buka_print_pdf')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            )),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () { Clipboard.setData(ClipboardData(text: pdfUrl)); _snack('Link PDF disalin!'); },
                icon: const FaIcon(FontAwesomeIcons.copy, size: 12), label: Text(_lang.get('salin_link')),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.border, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                onPressed: () {
                  final msg = Uri.encodeComponent('$typePDF CLAIM #$docID\n$pdfUrl');
                  launchUrl(Uri.parse('https://wa.me/?text=$msg'), mode: LaunchMode.externalApplication);
                },
                icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 12), label: Text(_lang.get('hantar_wa')),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              )),
            ]),
          ]),
        ),
      );
    } catch (e) {
      _snack('Gagal muat turun: $e', err: true);
    }
  }

  // ════════════════════════════════════════
  // EDIT HELPER WIDGETS
  // ════════════════════════════════════════
  Widget _buildClaimStatusDropdown(String current, List<String> allStatuses, ValueChanged<String?> onC) {
    final statusOrder = <String, int>{};
    for (var i = 0; i < allStatuses.length; i++) statusOrder[allStatuses[i]] = i;
    final currentLevel = statusOrder[current] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: allStatuses.contains(current) ? current : allStatuses.first,
        isExpanded: true, dropdownColor: Colors.white,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
        items: allStatuses.map((s) {
          final sLevel = statusOrder[s] ?? 0;
          final isPast = sLevel < currentLevel;
          final col = _claimStatusColor(s);
          return DropdownMenuItem(value: s, enabled: !isPast,
            child: Row(children: [
              FaIcon(_claimStatusIcon(s), size: 10, color: isPast ? AppColors.textDim : col),
              const SizedBox(width: 8),
              Flexible(child: Text(s, style: TextStyle(
                color: isPast ? AppColors.textDim : col, fontSize: 11, fontWeight: FontWeight.bold,
                decoration: isPast ? TextDecoration.lineThrough : null), overflow: TextOverflow.ellipsis)),
            ]));
        }).toList(),
        onChanged: onC,
      )),
    );
  }

  Widget _editLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(t, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
  );

  Widget _editDropdown(String val, List<String> opts, ValueChanged<String?> onC) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: opts.contains(val) ? val : opts.first, isExpanded: true, dropdownColor: Colors.white,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
        items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o.isEmpty ? '- PILIH -' : o))).toList(),
        onChanged: onC,
      )),
    );
  }

  Widget _editDateField(String val, ValueChanged<String> onC) => GestureDetector(
    onTap: () async {
      final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
      if (d != null && mounted) {
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
        if (t != null) onC(DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime(d.year, d.month, d.day, t.hour, t.minute)));
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Expanded(child: Text(
          val.isNotEmpty ? val.replaceAll('T', ' ') : '- Pilih -',
          style: TextStyle(color: val.isNotEmpty ? AppColors.textPrimary : AppColors.textDim, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        )),
        const FaIcon(FontAwesomeIcons.calendarDay, size: 9, color: AppColors.textDim),
      ]),
    ),
  );

  // ════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      _buildSearchAndFilter(),
      Expanded(child: _buildClaimList()),
    ]);
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      color: AppColors.card,
      child: Row(children: [
        const FaIcon(FontAwesomeIcons.shieldHalved, size: 14, color: AppColors.blue),
        const SizedBox(width: 8),
        Expanded(child: Text(_lang.get('cw_claim_warranty'), style: const TextStyle(color: AppColors.blue, fontSize: 14, fontWeight: FontWeight.w900))),
        Text('${_filtered.length} rekod', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _showRegisterClaimModal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.black),
              const SizedBox(width: 4),
              Text(_lang.get('cw_daftar'), style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      color: AppColors.card,
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(_applyFilter),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: _lang.get('cw_cari_hint'),
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
            suffixIcon: _searchCtrl.text.isNotEmpty
              ? GestureDetector(onTap: () { _searchCtrl.clear(); setState(_applyFilter); },
                  child: const Icon(Icons.close, color: AppColors.red, size: 18))
              : null,
            filled: true, fillColor: AppColors.bgDeep,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10), isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderMed),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterStatus,
              isExpanded: true,
              isDense: true,
              dropdownColor: AppColors.card,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('Semua Status')),
                DropdownMenuItem(value: 'CLAIM WAITING APPROVAL', child: Text('Menunggu Kelulusan')),
                DropdownMenuItem(value: 'CLAIM APPROVE', child: Text('Approve')),
                DropdownMenuItem(value: 'CLAIM IN PROGRESS', child: Text('Dalam Proses')),
                DropdownMenuItem(value: 'CLAIM DONE', child: Text('Siap')),
                DropdownMenuItem(value: 'CLAIM READY TO PICKUP', child: Text('Sedia Pickup')),
                DropdownMenuItem(value: 'CLAIM COMPLETE', child: Text('Selesai')),
              ],
              onChanged: (v) => setState(() { _filterStatus = v ?? 'ALL'; _applyFilter(); }),
            ),
          ),
        ),
      ]),
    );
  }


  String _formatWaTel(String tel) {
    var n = tel.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('0')) n = '6$n';
    if (!n.startsWith('6')) n = '60$n';
    return n;
  }

  void _makeCall(String tel) {
    final formatted = tel.replaceAll(RegExp(r'\D'), '');
    if (formatted.isEmpty) return;
    launchUrl(Uri.parse('tel:$formatted'), mode: LaunchMode.externalApplication);
  }

  void _showContactModal(Map<String, dynamic> c) {
    final tel = (c['tel'] ?? '').toString();
    final nama = (c['nama'] ?? '-').toString();
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.addressBook, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(nama, style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900))),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          _printBtn('CALL', tel, FontAwesomeIcons.phone, AppColors.blue, () {
            Navigator.pop(ctx);
            _showCallModal(c);
          }),
          const SizedBox(height: 8),
          _printBtn('WHATSAPP', tel, FontAwesomeIcons.whatsapp, const Color(0xFF25D366), () {
            Navigator.pop(ctx);
            _showWaModal(c);
          }),
        ]),
      ),
    );
  }

  void _showCallModal(Map<String, dynamic> c) {
    final tel1 = (c['tel'] ?? '').toString();
    final tel2 = (c['tel_wasap'] ?? '').toString();
    final nama = (c['nama'] ?? '-').toString();

    // Jika tiada backup number, terus call
    if (tel2.isEmpty || tel2 == '-' || tel2 == tel1) {
      _makeCall(tel1);
      return;
    }

    // Pop up pilih nombor
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.phone, size: 14, color: AppColors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text('${_lang.get('cw_hubungi')} $nama', style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900))),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 6),
          Text(_lang.get('cw_pilih_nombor'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _callNumBtn('No. Utama', tel1, () { Navigator.pop(ctx); _makeCall(tel1); }),
          const SizedBox(height: 8),
          _callNumBtn('No. Backup / Wasap', tel2, () { Navigator.pop(ctx); _makeCall(tel2); }),
        ]),
      ),
    );
  }

  Widget _callNumBtn(String label, String tel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          const FaIcon(FontAwesomeIcons.phone, size: 12, color: AppColors.blue),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
            Text(tel, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ])),
          const FaIcon(FontAwesomeIcons.arrowRight, size: 10, color: AppColors.blue),
        ]),
      ),
    );
  }

  void _showWaModal(Map<String, dynamic> c) {
    final tel1 = (c['tel'] ?? '').toString();
    final tel2 = (c['tel_wasap'] ?? '').toString();
    final nama = (c['nama'] ?? '-').toString();

    // Jika tiada backup number, terus WhatsApp
    if (tel2.isEmpty || tel2 == '-' || tel2 == tel1) {
      final waUrl = 'https://wa.me/${_formatWaTel(tel1)}';
      launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
      return;
    }

    // Pop up pilih nombor
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.whatsapp, size: 16, color: Color(0xFF25D366)),
            const SizedBox(width: 8),
            Expanded(child: Text('${_lang.get('cw_whatsapp')} $nama', style: const TextStyle(color: Color(0xFF25D366), fontSize: 13, fontWeight: FontWeight.w900))),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 6),
          Text(_lang.get('cw_pilih_nombor'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _waNumBtn('No. Utama', tel1, () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse('https://wa.me/${_formatWaTel(tel1)}'), mode: LaunchMode.externalApplication);
          }),
          const SizedBox(height: 8),
          _waNumBtn('No. Backup / Wasap', tel2, () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse('https://wa.me/${_formatWaTel(tel2)}'), mode: LaunchMode.externalApplication);
          }),
        ]),
      ),
    );
  }

  Widget _waNumBtn(String label, String tel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF25D366).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          const FaIcon(FontAwesomeIcons.whatsapp, size: 12, color: Color(0xFF25D366)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
            Text(tel, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ])),
          const FaIcon(FontAwesomeIcons.arrowRight, size: 10, color: Color(0xFF25D366)),
        ]),
      ),
    );
  }

  Widget _buildClaimList() {
    if (_claims.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const FaIcon(FontAwesomeIcons.shieldHalved, size: 40, color: AppColors.textDim),
        const SizedBox(height: 12),
        Text(_lang.get('cw_tiada_claim'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(_lang.get('cw_tekan_daftar'), style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ]));
    }

    if (_filtered.isEmpty) {
      return Center(child: Text(_lang.get('cw_tiada_claim_ditemui'), style: const TextStyle(color: AppColors.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _buildClaimCard(_filtered[i]),
    );
  }

  Widget _buildClaimCard(Map<String, dynamic> c) {
    final claimID = c['claimID'] ?? c['id'] ?? '-';
    final claimStatus = (c['claimStatus'] ?? 'Claim Waiting Approval').toString();
    final col = _claimStatusColor(claimStatus);
    final nama = (c['nama'] ?? '-').toString();
    final model = (c['model'] ?? '-').toString();
    final siri = (c['siri'] ?? '-').toString();
    final tel = (c['tel'] ?? '-').toString();
    final kerosakan = (c['kerosakan'] ?? '-').toString();
    final claimWarranty = (c['claimWarranty'] ?? 'TIADA').toString();
    final claimWarrantyExp = (c['claimWarrantyExp'] ?? '').toString();
    final originalWarranty = (c['originalWarranty'] ?? 'TIADA').toString();
    final originalWarrantyExp = (c['originalWarrantyExp'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMed),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 12, offset: const Offset(5, 5))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: col, width: 3)),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // Claim ID + CETAK badge
              Row(children: [
                FaIcon(_claimStatusIcon(claimStatus), size: 10, color: col),
                const SizedBox(width: 6),
                Text('#$claimID', style: TextStyle(color: col, fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showPrintClaimModal(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const FaIcon(FontAwesomeIcons.print, size: 9, color: AppColors.blue),
                      const SizedBox(width: 4),
                      Text(_lang.get('cetak'), style: const TextStyle(color: AppColors.blue, fontSize: 8, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              ]),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(claimStatus.toUpperCase(), style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Repair: #$siri', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Customer name + WhatsApp
            Row(children: [
              Expanded(child: Text(nama.toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700))),
              GestureDetector(
                onTap: () => _showContactModal(c),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const FaIcon(FontAwesomeIcons.whatsapp, size: 20, color: Color(0xFF25D366)),
                ),
              ),
            ]),
            // Tel
            Row(children: [
              const FaIcon(FontAwesomeIcons.phone, size: 8, color: AppColors.textDim),
              const SizedBox(width: 4),
              Text(tel, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
            ]),
            Text('$model  |  $kerosakan', style: const TextStyle(color: AppColors.textMuted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),

            const SizedBox(height: 6),

            // Warranty badges
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (originalWarranty != 'TIADA' && originalWarranty.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const FaIcon(FontAwesomeIcons.shieldHalved, size: 7, color: AppColors.yellow),
                    const SizedBox(width: 4),
                    Text('Asal: $originalWarranty', style: const TextStyle(color: AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w800)),
                    if (originalWarrantyExp.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('(${_isWarrantyExpired(originalWarrantyExp) ? "TAMAT" : originalWarrantyExp})',
                        style: TextStyle(color: _isWarrantyExpired(originalWarrantyExp) ? AppColors.red : AppColors.green, fontSize: 7, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
              if (claimWarranty != 'TIADA' && claimWarranty.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.green.withValues(alpha: 0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const FaIcon(FontAwesomeIcons.shield, size: 7, color: AppColors.green),
                    const SizedBox(width: 4),
                    Text('Claim: $claimWarranty', style: const TextStyle(color: AppColors.green, fontSize: 8, fontWeight: FontWeight.w800)),
                    if (claimWarrantyExp.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('(${_isWarrantyExpired(claimWarrantyExp) ? "TAMAT" : claimWarrantyExp})',
                        style: TextStyle(color: _isWarrantyExpired(claimWarrantyExp) ? AppColors.red : AppColors.green, fontSize: 7, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
            ]),

            const SizedBox(height: 6),

            // Dates + Staff
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.calendarDay, size: 8, color: AppColors.textDim),
                const SizedBox(width: 4),
                Text(_fmt(c['timestamp']), style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              ]),
              if ((c['staffRepair'] ?? '').toString().isNotEmpty)
                Row(children: [
                  const FaIcon(FontAwesomeIcons.userGear, size: 8, color: AppColors.textDim),
                  const SizedBox(width: 4),
                  Text(c['staffRepair'].toString(), style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                ]),
            ]),
          ]),
        ),

        // Actions
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(children: [
            _actBtn('Kemaskini', FontAwesomeIcons.penToSquare, AppColors.blue, () => _showUpdateClaimModal(c)),
          ]),
        ),
      ]),
    );
  }

  Widget _actBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}
