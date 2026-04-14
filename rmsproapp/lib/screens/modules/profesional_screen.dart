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

const String _cloudRunUrl =
    'https://rms-backend-94407896005.asia-southeast1.run.app';

class ProfesionalScreen extends StatefulWidget {
  final VoidCallback? onSwitchToCollab;
  const ProfesionalScreen({super.key, this.onSwitchToCollab});
  @override
  State<ProfesionalScreen> createState() => _ProfesionalScreenState();
}

class _ProfesionalScreenState extends State<ProfesionalScreen> with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  final _lang = AppLanguage();
  late TabController _tabCtrl;

  String _ownerID = 'admin', _shopID = 'MAIN';
  bool _proMode = false;
  int _proModeExpire = 0;

  // Online (Auto) tab
  List<Map<String, dynamic>> _onlineTasks = [];
  List<Map<String, dynamic>> _onlineFiltered = [];
  StreamSubscription? _onlineSub;

  // Offline (Manual) tab
  List<Map<String, dynamic>> _offlineTasks = [];
  List<Map<String, dynamic>> _offlineFiltered = [];
  StreamSubscription? _offlineSub;

  // Archive toggle
  bool _showArchived = false;

  // Branch settings for printing
  Map<String, dynamic> _branchSettings = {};

  // Dealer book
  List<Map<String, dynamic>> _savedDealers = [];
  StreamSubscription? _dealerSub;

  // Pro mode watcher
  StreamSubscription? _proSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() { if (!_tabCtrl.indexIsChanging) setState(() {}); });
    _init();
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _offlineSub?.cancel();
    _proSub?.cancel();
    _dealerSub?.cancel();
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase();
      _shopID = branch.split('@')[1].toUpperCase();
    }
    _watchProMode();
    _listenOnline();
    _listenOffline();
    _listenDealers();
    _loadBranchSettings();
  }

  // ═══════════════════════════════════════
  // PRO MODE WATCHER
  // ═══════════════════════════════════════
  void _watchProMode() {
    _proSub = _db.collection('shops_$_ownerID').doc(_shopID).snapshots().listen((snap) {
      if (!snap.exists || !mounted) return;
      final d = snap.data() ?? {};
      setState(() {
        _proMode = d['proMode'] == true;
        _proModeExpire = d['proModeExpire'] is int ? d['proModeExpire'] : 0;
      });
    });
  }

  bool get _isProActive {
    if (!_proMode) return false;
    if (_proModeExpire <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch < _proModeExpire;
  }

  String get _proExpireStr {
    if (_proModeExpire <= 0) return 'Tiada had';
    return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_proModeExpire));
  }

  // ═══════════════════════════════════════
  // ONLINE TASKS (collab_global_network where receiver == shopID)
  // ═══════════════════════════════════════
  void _listenOnline() {
    _onlineSub = _db.collection('collab_global_network').snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        d['id'] = doc.id;
        if ((d['receiver'] ?? '').toString().toUpperCase() == _shopID) list.add(d);
      }
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() { _onlineTasks = list; _filterOnline(); _filterByArchive(); });
    }, onError: (e) {
      debugPrint('COLLAB LISTEN ERROR: $e');
    });
  }

  void _filterOnline() {
    final q = _searchCtrl.text.toLowerCase().trim();
    _onlineFiltered = q.isEmpty ? List.from(_onlineTasks) : _onlineTasks.where((d) =>
      (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
      (d['namaCust'] ?? '').toString().toLowerCase().contains(q) ||
      (d['model'] ?? '').toString().toLowerCase().contains(q) ||
      (d['sender'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  // ═══════════════════════════════════════
  // OFFLINE TASKS (pro_walkin_{ownerID} filtered by shopID)
  // ═══════════════════════════════════════
  void _listenOffline() {
    _offlineSub = _db.collection('pro_walkin_$_ownerID')
        .orderBy('timestamp', descending: true)
        .snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data(); d['id'] = doc.id;
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) list.add(d);
      }
      if (mounted) setState(() { _offlineTasks = list; _filterOffline(); _filterByArchive(); });
    });
  }

  void _filterOffline() {
    final q = _searchCtrl.text.toLowerCase().trim();
    _offlineFiltered = q.isEmpty ? List.from(_offlineTasks) : _offlineTasks.where((d) =>
      (d['namaKedai'] ?? '').toString().toLowerCase().contains(q) ||
      (d['model'] ?? '').toString().toLowerCase().contains(q) ||
      (d['namaCust'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  void _filter() {
    _filterOnline();
    _filterOffline();
    _filterByArchive();
  }

  void _filterByArchive() {
    if (!_showArchived) {
      _onlineFiltered = _onlineFiltered.where((d) => d['archived'] != true).toList();
      _offlineFiltered = _offlineFiltered.where((d) => d['archived'] != true).toList();
    }
  }

  // ═══════════════════════════════════════
  // ARCHIVE / UNDO
  // ═══════════════════════════════════════
  Future<void> _archiveOnline(Map<String, dynamic> task) async {
    await _db.collection('collab_global_network').doc(task['id']).update({'archived': true});
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_lang.get('pf_tugasan_diarkib')),
      backgroundColor: const Color(0xFFA78BFA),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'UNDO',
        textColor: Colors.white,
        onPressed: () async {
          await _db.collection('collab_global_network').doc(task['id']).update({'archived': false});
        },
      ),
    ));
  }

  Future<void> _archiveOffline(Map<String, dynamic> task) async {
    await _db.collection('pro_walkin_$_ownerID').doc(task['id']).update({'archived': true});
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_lang.get('pf_job_diarkib')),
      backgroundColor: const Color(0xFFA78BFA),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'UNDO',
        textColor: Colors.white,
        onPressed: () async {
          await _db.collection('pro_walkin_$_ownerID').doc(task['id']).update({'archived': false});
        },
      ),
    ));
  }

  // ═══════════════════════════════════════
  // DEALER BOOK
  // ═══════════════════════════════════════
  void _listenDealers() {
    _dealerSub = _db.collection('pro_dealers_$_ownerID')
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

  Future<void> _saveDealer(Map<String, dynamic> dealerData, StateSetter setS) async {
    final nama = (dealerData['namaPemilik'] ?? '').toString().trim();
    final existing = _savedDealers.where((d) => (d['namaPemilik'] ?? '').toString().toUpperCase() == nama.toUpperCase()).toList();
    if (existing.isNotEmpty) {
      await _db.collection('pro_dealers_$_ownerID').doc(existing.first['_id']).update(dealerData);
      _snack('Dealer dikemaskini');
    } else {
      dealerData['shopID'] = _shopID;
      dealerData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      dealerData['cawangan'] = dealerData['cawangan'] ?? [];
      await _db.collection('pro_dealers_$_ownerID').add(dealerData);
      _snack('Dealer disimpan');
    }
  }

  void _showDealerBook() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.addressBook, size: 12, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text(_lang.get('pf_buku_dealer'), style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w900)),
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
                    decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(10)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white),
                      SizedBox(width: 6),
                      Text('TAMBAH DEALER', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                if (_savedDealers.isEmpty)
                  Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_lang.get('pf_tiada_dealer'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ))
                else
                  ..._savedDealers.map((d) {
                    final cawangan = (d['cawangan'] is List) ? List<Map<String, dynamic>>.from((d['cawangan'] as List).map((c) => Map<String, dynamic>.from(c as Map))) : <Map<String, dynamic>>[];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderMed),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Center(child: FaIcon(FontAwesomeIcons.userTie, size: 14, color: AppColors.cyan)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((d['namaPemilik'] ?? d['nama'] ?? '-').toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
                            if ((d['namaKedai'] ?? '').toString().isNotEmpty)
                              Text((d['namaKedai'] ?? '').toString(), style: const TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
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
                                await _db.collection('pro_dealers_$_ownerID').doc(d['_id']).delete();
                                _snack('Dealer dipadam');
                                if (ctx.mounted) setS(() {});
                              }
                            },
                          ),
                        ]),
                        if (cawangan.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...cawangan.map((c) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                            child: Row(children: [
                              const FaIcon(FontAwesomeIcons.store, size: 9, color: AppColors.textDim),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text((c['namaKedai'] ?? '-').toString(), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w700)),
                                Text('${c['alamatKedai'] ?? '-'}', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                              ])),
                            ]),
                          )),
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) => Container(
        margin: const EdgeInsets.only(top: 80),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(dCtx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.userPlus, size: 14, color: AppColors.cyan),
              const SizedBox(width: 8),
              const Text('TAMBAH DEALER BARU', style: TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pop(dCtx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const Divider(height: 20, color: AppColors.borderMed),
            _modalField('NAMA PEMILIK', namaPemilikCtrl, 'cth: Ahmad bin Ali'),
            _modalField('NO. TELEFON PEMILIK', telPemilikCtrl, '01x-xxxxxxx', keyboard: TextInputType.phone),
            _modalField('NAMA KEDAI', namaKedaiCtrl, 'cth: Ali Phone Enterprise'),
            _modalField('ALAMAT KEDAI', alamatKedaiCtrl, 'Alamat penuh kedai'),
            Row(children: [
              Expanded(child: _modalField('TEL KEDAI', telKedaiCtrl, '0x-xxxxxxx', keyboard: TextInputType.phone)),
              const SizedBox(width: 6),
              Expanded(child: _modalField('NO. SSM', ssmCtrl, 'No. SSM')),
            ]),
            const SizedBox(height: 4),
            const Text('TETAPAN JUALAN', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
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
                if (namaPemilikCtrl.text.trim().isEmpty) { _snack('Sila isi nama pemilik', color: AppColors.red); return; }
                if (namaKedaiCtrl.text.trim().isEmpty) { _snack('Sila isi nama kedai', color: AppColors.red); return; }
                _saveDealer({
                  'namaPemilik': namaPemilikCtrl.text.trim().toUpperCase(),
                  'telPemilik': telPemilikCtrl.text.trim(),
                  'namaKedai': namaKedaiCtrl.text.trim().toUpperCase(),
                  'alamatKedai': alamatKedaiCtrl.text.trim(),
                  'telKedai': telKedaiCtrl.text.trim(),
                  'noSSM': ssmCtrl.text.trim().toUpperCase(),
                  'bayaran': bayaran, 'term': term, 'warranty': warranty,
                  'cawangan': [],
                }, parentSetS);
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white), SizedBox(width: 6),
                  Text('SIMPAN DEALER', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ])),
        ),
      )),
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (dCtx) => Container(
        margin: const EdgeInsets.only(top: 80),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(dCtx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: AppColors.cyan),
              const SizedBox(width: 8),
              const Text('EDIT DEALER', style: TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pop(dCtx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const Divider(height: 20, color: AppColors.borderMed),
            _modalField('NAMA PEMILIK', namaPCtrl, 'Nama pemilik'),
            _modalField('NO. TELEFON PEMILIK', telPCtrl, '01x-xxxxxxx', keyboard: TextInputType.phone),
            _modalField('NAMA KEDAI', namaKCtrl, 'Nama kedai'),
            _modalField('ALAMAT KEDAI', alamatKCtrl, 'Alamat kedai'),
            Row(children: [
              Expanded(child: _modalField('TEL KEDAI', telKCtrl, '0x-xxxxxxx', keyboard: TextInputType.phone)),
              const SizedBox(width: 6),
              Expanded(child: _modalField('NO. SSM', ssmCtrl, 'No. SSM')),
            ]),
            const SizedBox(height: 4),
            const Text('TETAPAN JUALAN', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
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
                if (namaPCtrl.text.trim().isEmpty) { _snack('Sila isi nama pemilik', color: AppColors.red); return; }
                await _db.collection('pro_dealers_$_ownerID').doc(dealer['_id']).update({
                  'namaPemilik': namaPCtrl.text.trim().toUpperCase(),
                  'telPemilik': telPCtrl.text.trim(),
                  'namaKedai': namaKCtrl.text.trim().toUpperCase(),
                  'alamatKedai': alamatKCtrl.text.trim(),
                  'telKedai': telKCtrl.text.trim(),
                  'noSSM': ssmCtrl.text.trim().toUpperCase(),
                  'bayaran': editBayaran, 'term': editTerm, 'warranty': editWarranty,
                });
                _snack('Dealer dikemaskini');
                if (dCtx.mounted) Navigator.pop(dCtx);
                parentSetS(() {});
              },
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white), SizedBox(width: 6),
                  Text('KEMASKINI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ])),
        ),
      ),
    );
  }

  void _showDealerHistory(Map<String, dynamic> dealer) {
    final dealerId = (dealer['_id'] ?? '').toString();
    final dealerName = (dealer['namaPemilik'] ?? dealer['nama'] ?? '-').toString();
    final searchCtrl = TextEditingController();
    String filterTime = 'SEMUA';
    String searchQuery = '';
    DateTimeRange? customRange;

    // Get offline tasks for this dealer
    final allDealerTasks = _offlineTasks.where((s) => (s['dealerId'] ?? '').toString() == dealerId).toList()
      ..sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        var filtered = List<Map<String, dynamic>>.from(allDealerTasks);

        if (searchQuery.isNotEmpty) {
          filtered = filtered.where((s) =>
            (s['model'] ?? '').toString().toLowerCase().contains(searchQuery) ||
            (s['siri'] ?? '').toString().toLowerCase().contains(searchQuery) ||
            (s['namaKedai'] ?? '').toString().toLowerCase().contains(searchQuery)
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

        final totalBelian = filtered.fold<double>(0, (s, e) => s + ((e['harga'] ?? 0) as num).toDouble());

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
                  Expanded(child: Text('HISTORY · $dealerName', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim)),
                ]),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2))),
                  child: Row(children: [
                    const FaIcon(FontAwesomeIcons.sackDollar, size: 12, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    const Text('JUMLAH', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('RM ${totalBelian.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    Text('(${filtered.length} job)', style: const TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: searchCtrl,
                  onChanged: (v) => setS(() => searchQuery = v.toLowerCase().trim()),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Cari model / no. siri...', hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFFF59E0B)),
                    filled: true, fillColor: AppColors.bgDeep, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                      value: filterTime, isExpanded: true, dropdownColor: AppColors.bgDeep, isDense: true,
                      icon: const FaIcon(FontAwesomeIcons.caretDown, size: 10, color: AppColors.textMuted),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                      items: ['SEMUA', 'HARI INI', 'MINGGU INI', 'BULAN INI', 'TAHUN INI'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setS(() { filterTime = v ?? 'SEMUA'; customRange = null; }),
                    )),
                  )),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: ctx, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: customRange,
                        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFF59E0B))), child: child!),
                      );
                      if (picked != null) setS(() { filterTime = 'TARIKH'; customRange = picked; });
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
                          Text('${DateFormat('dd/MM').format(customRange!.start)} - ${DateFormat('dd/MM').format(customRange!.end)}',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                        ],
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: filtered.isEmpty
              ? const Center(child: Text('Tiada rekod', style: TextStyle(color: AppColors.textDim, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    final siri = (s['siri'] ?? '-').toString();
                    final model = (s['model'] ?? '-').toString();
                    final harga = ((s['harga'] ?? 0) as num).toDouble();
                    final ts = (s['timestamp'] ?? 0) as num;
                    final date = ts.toInt() > 0 ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts.toInt())) : '-';
                    final status = (s['status'] ?? '-').toString();
                    final payStatus = (s['paymentStatus'] ?? '-').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderMed)),
                      child: Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF0EA5E9), fontSize: 10, fontWeight: FontWeight.w900))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(model, style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                          Text('#$siri · $date', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
                              child: Text(status, style: TextStyle(color: _statusColor(status), fontSize: 7, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: (payStatus == 'PAID' ? AppColors.green : AppColors.yellow).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
                              child: Text(payStatus, style: TextStyle(color: payStatus == 'PAID' ? AppColors.green : AppColors.yellow, fontSize: 7, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ])),
                        Text('RM ${harga.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w900)),
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

  void _showAddCawangan(Map<String, dynamic> dealer, StateSetter parentSetS) {
    final namaCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    final telCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          FaIcon(FontAwesomeIcons.store, size: 14, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Text('TAMBAH CAWANGAN', style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _modalField('Nama Kedai', namaCtrl, 'cth: Ali Phone Cawangan 2'),
          _modalField('Alamat Kedai', alamatCtrl, 'Alamat cawangan'),
          _modalField('No. Telefon', telCtrl, '0x-xxxxxxx', keyboard: TextInputType.phone),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800))),
          ElevatedButton(
            onPressed: () async {
              if (namaCtrl.text.trim().isEmpty) { _snack('Sila isi nama kedai cawangan', color: AppColors.red); return; }
              final cawangan = (dealer['cawangan'] is List) ? List<Map<String, dynamic>>.from((dealer['cawangan'] as List).map((c) => Map<String, dynamic>.from(c as Map))) : <Map<String, dynamic>>[];
              cawangan.add({
                'namaKedai': namaCtrl.text.trim().toUpperCase(),
                'alamatKedai': alamatCtrl.text.trim(),
                'telKedai': telCtrl.text.trim(),
              });
              await _db.collection('pro_dealers_$_ownerID').doc(dealer['_id']).update({'cawangan': cawangan});
              _snack('Cawangan ditambah');
              if (dCtx.mounted) Navigator.pop(dCtx);
              parentSetS(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('SIMPAN', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // UPDATE ONLINE TASK MODAL
  // ═══════════════════════════════════════
  void _showUpdateOnlineModal(Map<String, dynamic> task) {
    String status = (task['status'] ?? 'PENDING').toString().toUpperCase();
    final kosCtrl = TextEditingController(text: (task['kos'] ?? '').toString());
    final hargaCtrl = TextEditingController(text: (task['harga'] ?? '').toString());
    String paymentStatus = (task['paymentStatus'] ?? 'UNPAID').toString().toUpperCase();
    String paymentMethod = (task['paymentMethod'] ?? '').toString();
    final kurierReturnCtrl = TextEditingController(text: (task['kurier_return'] ?? '').toString());
    final trackingReturnCtrl = TextEditingController(text: (task['tracking_return'] ?? '').toString());
    final notaCtrl = TextEditingController(text: (task['catatan_pro'] ?? '').toString());

    final statuses = ['INCOMING', 'TERIMA', 'IN PROGRESS', 'RETURN SIAP', 'RETURN REJECT', 'COMPLETED', 'REJECT'];
    final payStatuses = ['UNPAID', 'PAID'];
    final payMethods = ['', 'CASH', 'BANK TRANSFER', 'ONLINE BANKING', 'EWALLET', 'QR PAY'];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: AppColors.blue),
              const SizedBox(width: 8),
              Text(_lang.get('pf_kemaskini_tugasan'), style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const Divider(color: AppColors.borderMed, height: 20),
          _infoRow('Siri', '#${task['siri'] ?? '-'}'),
          _infoRow('Pelanggan', task['namaCust'] ?? '-'),
          _infoRow('Model', task['model'] ?? '-'),
          _infoRow('Kerosakan', task['kerosakan'] ?? '-'),
          _infoRow('Penghantar', task['sender'] ?? '-'),
          _infoRow('Kurier', task['kurier'] ?? '-'),
          if ((task['tracking'] ?? '').toString().isNotEmpty)
            _infoRow('Tracking Dealer', task['tracking'] ?? '-'),
          if ((task['trackingNo'] ?? '').toString().isNotEmpty)
            _infoRow('Tracking No.', task['trackingNo'] ?? '-'),
          const Divider(color: AppColors.borderMed, height: 16),

          // Timeline from status changes
          if (task['statusTimeline'] is List && (task['statusTimeline'] as List).isNotEmpty) ...[
            _buildTimeline(task['statusTimeline'] as List),
            const Divider(color: AppColors.borderMed, height: 16),
          ],

          // Status dropdown
          Text(_lang.get('status'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: statuses.contains(status) ? status : statuses.first,
              isExpanded: true, dropdownColor: AppColors.bgDeep,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: _statusColor(s))))).toList(),
              onChanged: (v) => setS(() => status = v ?? status),
            )),
          ),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: _modalField('KOS (RM)', kosCtrl, '0.00', keyboard: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _modalField('HARGA JUAL (RM)', hargaCtrl, '0.00', keyboard: TextInputType.number)),
          ]),

          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_lang.get('pf_bayaran'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: paymentStatus, isExpanded: true, dropdownColor: AppColors.bgDeep,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  items: payStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: s == 'PAID' ? AppColors.green : AppColors.yellow)))).toList(),
                  onChanged: (v) => setS(() => paymentStatus = v ?? paymentStatus),
                )),
              ),
              const SizedBox(height: 10),
            ])),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_lang.get('pf_kaedah'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: payMethods.contains(paymentMethod) ? paymentMethod : '',
                  isExpanded: true, dropdownColor: AppColors.bgDeep,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  items: payMethods.map((s) => DropdownMenuItem(value: s, child: Text(s.isEmpty ? '-- Pilih --' : s))).toList(),
                  onChanged: (v) => setS(() => paymentMethod = v ?? ''),
                )),
              ),
              const SizedBox(height: 10),
            ])),
          ]),

          _modalField('KURIER RETURN', kurierReturnCtrl, 'Nama kurier...'),
          _modalField('TRACKING RETURN', trackingReturnCtrl, 'Tracking number...'),
          _modalField('NOTA / CATATAN', notaCtrl, 'Catatan untuk penghantar...'),

          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () async {
              final now = DateTime.now().millisecondsSinceEpoch;
              final updateData = <String, dynamic>{
                'status': status,
                'kos': double.tryParse(kosCtrl.text) ?? 0,
                'harga': double.tryParse(hargaCtrl.text) ?? 0,
                'paymentStatus': paymentStatus,
                'paymentMethod': paymentMethod,
                'kurier_return': kurierReturnCtrl.text.trim(),
                'tracking_return': trackingReturnCtrl.text.trim(),
                'catatan_pro': notaCtrl.text.trim(),
                'lastUpdated': now,
              };
              final oldStatus = (task['status'] ?? '').toString().toUpperCase();
              if (status != oldStatus) {
                final existing = (task['statusTimeline'] is List) ? List<Map<String, dynamic>>.from((task['statusTimeline'] as List).map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[];
                existing.add({'status': status, 'timestamp': now, 'by': _shopID});
                updateData['statusTimeline'] = existing;
              }
              await _db.collection('collab_global_network').doc(task['id']).update(updateData);
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Tugasan dikemaskini');
            },
            icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
            label: Text(_lang.get('simpan')),
          )),
          const SizedBox(height: 8),
        ])),
      )),
    );
  }

  // ═══════════════════════════════════════
  // INFO MODAL (password & nota from sender)
  // ═══════════════════════════════════════
  void _showInfoModal(Map<String, dynamic> task) {
    final col = _statusColor((task['status'] ?? 'PENDING').toString().toUpperCase());
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              FaIcon(FontAwesomeIcons.circleInfo, size: 14, color: col), const SizedBox(width: 8),
              Text(_lang.get('pf_info_tugasan'), style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const Divider(color: AppColors.borderMed, height: 24),
          _infoRow('Siri', '#${task['siri'] ?? '-'}'),
          _infoRow('Pelanggan', task['namaCust'] ?? '-'),
          _infoRow('Model', task['model'] ?? '-'),
          _infoRow('Kerosakan', task['kerosakan'] ?? '-'),
          _infoRow('Penghantar', task['sender'] ?? '-'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_lang.get('pf_password_device'), style: const TextStyle(color: AppColors.yellow, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text((task['password'] ?? task['devicePassword'] ?? '-').toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ]),
          ),
          const SizedBox(height: 10),
          if ((task['catatan'] ?? task['nota_sender'] ?? '').toString().isNotEmpty)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.blue.withValues(alpha: 0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_lang.get('pf_nota_penghantar'), style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text((task['catatan'] ?? task['nota_sender'] ?? '').toString(), style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
              ]),
            ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════
  // OFFLINE JOB ADD/EDIT MODAL
  // ═══════════════════════════════════════
  void _showOfflineJobModal({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String selectedDealer = '';
    final namaKedaiCtrl = TextEditingController(text: existing?['namaKedai'] ?? '');
    final telCtrl = TextEditingController(text: existing?['tel'] ?? '');
    final modelCtrl = TextEditingController(text: existing?['model'] ?? '');
    final kerosakanCtrl = TextEditingController(text: existing?['kerosakan'] ?? '');
    final passwordCtrl = TextEditingController(text: existing?['password'] ?? '');
    String status = (existing?['status'] ?? 'TERIMA').toString().toUpperCase();
    final kosCtrl = TextEditingController(text: (existing?['kos'] ?? '').toString());
    final hargaCtrl = TextEditingController(text: (existing?['harga'] ?? '').toString());
    String paymentStatus = (existing?['paymentStatus'] ?? 'UNPAID').toString().toUpperCase();
    final namaCustCtrl = TextEditingController(text: existing?['namaCust'] ?? '');

    final statuses = ['INCOMING', 'TERIMA', 'IN PROGRESS', 'RETURN SIAP', 'RETURN REJECT', 'COMPLETED', 'REJECT'];
    final payStatuses = ['UNPAID', 'PAID'];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              FaIcon(isEdit ? FontAwesomeIcons.penToSquare : FontAwesomeIcons.plus, size: 14, color: AppColors.orange),
              const SizedBox(width: 8),
              Text(isEdit ? 'EDIT JOB' : '${_lang.get('pf_job_baru')} (MANUAL)', style: const TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const Divider(color: AppColors.borderMed, height: 20),

          if (_savedDealers.isNotEmpty && !isEdit) ...[
            Text(_lang.get('pf_pilih_dealer'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: selectedDealer.isEmpty ? null : selectedDealer,
                hint: Text(_lang.get('pf_pilih_dari_buku'), style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                isExpanded: true, dropdownColor: AppColors.bgDeep,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                items: _savedDealers.map((d) => DropdownMenuItem<String>(value: d['_id'] ?? '', child: Text('${d['namaKedai'] ?? d['kedai'] ?? '-'} - ${d['namaPemilik'] ?? d['nama'] ?? '-'}'))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final dealer = _savedDealers.firstWhere((d) => d['_id'] == v, orElse: () => {});
                  setS(() {
                    selectedDealer = v;
                    namaKedaiCtrl.text = (dealer['namaKedai'] ?? dealer['kedai'] ?? '').toString();
                    telCtrl.text = (dealer['telPemilik'] ?? dealer['tel'] ?? '').toString();
                  });
                },
              )),
            ),
            const SizedBox(height: 10),
          ],

          _modalField('NAMA KEDAI / DEALER', namaKedaiCtrl, 'Nama kedai...'),
          _modalField('NAMA PELANGGAN', namaCustCtrl, 'Nama pelanggan...'),
          _modalField('NO TELEFON', telCtrl, '011...', keyboard: TextInputType.phone),
          _modalField('MODEL', modelCtrl, 'iPhone 15 Pro Max'),
          _modalField('KEROSAKAN', kerosakanCtrl, 'Tukar LCD, bateri...'),
          _modalField(_lang.get('pf_password_device'), passwordCtrl, '****'),

          if (isEdit && existing['statusTimeline'] is List && (existing['statusTimeline'] as List).isNotEmpty) ...[
            _buildTimeline(existing['statusTimeline'] as List),
            const Divider(color: AppColors.borderMed, height: 16),
          ],

          Text(_lang.get('status'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: statuses.contains(status) ? status : statuses.first,
              isExpanded: true, dropdownColor: AppColors.bgDeep,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: _statusColor(s))))).toList(),
              onChanged: (v) => setS(() => status = v ?? status),
            )),
          ),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: _modalField('KOS (RM)', kosCtrl, '0.00', keyboard: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _modalField('HARGA (RM)', hargaCtrl, '0.00', keyboard: TextInputType.number)),
          ]),

          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_lang.get('pf_bayaran'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: paymentStatus, isExpanded: true, dropdownColor: AppColors.bgDeep,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  items: payStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: s == 'PAID' ? AppColors.green : AppColors.yellow)))).toList(),
                  onChanged: (v) => setS(() => paymentStatus = v ?? paymentStatus),
                )),
              ),
            ])),
            const SizedBox(width: 8),
            Expanded(child: Container()),
          ]),
          const SizedBox(height: 16),

          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () async {
              if (namaKedaiCtrl.text.trim().isEmpty || modelCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('pf_sila_isi_nama')), backgroundColor: AppColors.red));
                return;
              }
              final data = <String, dynamic>{
                'namaKedai': namaKedaiCtrl.text.trim().toUpperCase(),
                'namaCust': namaCustCtrl.text.trim().toUpperCase(),
                'tel': telCtrl.text.trim(),
                'model': modelCtrl.text.trim().toUpperCase(),
                'kerosakan': kerosakanCtrl.text.trim(),
                'password': passwordCtrl.text.trim(),
                'status': status,
                'kos': double.tryParse(kosCtrl.text) ?? 0,
                'harga': double.tryParse(hargaCtrl.text) ?? 0,
                'paymentStatus': paymentStatus,
                'shopID': _shopID,
                'ownerID': _ownerID,
              };
              if (selectedDealer.isNotEmpty) data['dealerId'] = selectedDealer;
              if (isEdit) {
                final now = DateTime.now().millisecondsSinceEpoch;
                data['lastUpdated'] = now;
                final oldStatus = (existing['status'] ?? '').toString().toUpperCase();
                if (status != oldStatus) {
                  final tl = (existing['statusTimeline'] is List) ? List<Map<String, dynamic>>.from((existing['statusTimeline'] as List).map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[];
                  tl.add({'status': status, 'timestamp': now, 'by': _shopID});
                  data['statusTimeline'] = tl;
                }
                await _db.collection('pro_walkin_$_ownerID').doc(existing['id']).update(data);
              } else {
                final now = DateTime.now().millisecondsSinceEpoch;
                data['timestamp'] = now;
                final siri = 'PW${now.toString().substring(5)}';
                data['siri'] = siri;
                data['statusTimeline'] = [{'status': status, 'timestamp': now, 'by': _shopID}];
                await _db.collection('pro_walkin_$_ownerID').doc(siri).set(data);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _snack(isEdit ? 'Job dikemaskini' : 'Job baru ditambah');
            },
            icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
            label: Text(isEdit ? _lang.get('pf_kemaskini_tugasan') : '${_lang.get('simpan')} JOB'),
          )),
          const SizedBox(height: 8),
        ])),
      )),
    );
  }

  // ═══════════════════════════════════════
  // SWITCH TO NORMAL MODE
  // ═══════════════════════════════════════
  void _switchToNormalMode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const FaIcon(FontAwesomeIcons.toggleOff, size: 16, color: AppColors.yellow), const SizedBox(width: 8),
          Text(_lang.get('pf_tukar_normal'), style: const TextStyle(color: AppColors.yellow, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
        content: Text(_lang.get('pf_tukar_normal_desc'), style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal'), style: const TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(ctx);
              if (widget.onSwitchToCollab != null) {
                widget.onSwitchToCollab!();
              }
            },
            child: Text(_lang.get('pf_ya_tukar')),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // BRANCH SETTINGS
  // ═══════════════════════════════════════
  Future<void> _loadBranchSettings() async {
    final snap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
    if (snap.exists && mounted) {
      setState(() { _branchSettings = snap.data() ?? {}; });
    }
  }

  // ═══════════════════════════════════════
  // PRINT MODAL
  // ═══════════════════════════════════════
  void _showPrintModal(Map<String, dynamic> task, {required bool isOnline}) {
    final siri = task['siri'] ?? '-';
    final hasInvoice = (task['pdfUrl_INVOICE'] ?? '').toString().isNotEmpty;
    final hasQuote = (task['pdfUrl_QUOTATION'] ?? '').toString().isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.print, size: 14, color: Color(0xFFA78BFA)),
            const SizedBox(width: 8),
            Text('${_lang.get('cetak')} #$siri', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          _printBtn('PRINT LABEL', 'Cetak label ke printer Bluetooth', FontAwesomeIcons.tag, AppColors.orange, () async {
            Navigator.pop(ctx);
            _snack('Menyambung printer label...');
            final ok = await PrinterService().printLabel(task, _branchSettings);
            _snack(ok ? 'Label berjaya dicetak!' : 'Gagal cetak label — pastikan printer dihidupkan & Bluetooth aktif', color: ok ? AppColors.green : AppColors.red);
          }),
          const SizedBox(height: 8),
          _printBtn('RESIT 80MM', 'Cetak ke printer Bluetooth', FontAwesomeIcons.receipt, AppColors.blue, () async {
            Navigator.pop(ctx);
            _snack('Menyambung printer...');
            final ok = await PrinterService().printReceipt(task, _branchSettings);
            _snack(ok ? 'Cetak berjaya!' : 'Gagal cetak — pastikan printer dihidupkan & Bluetooth aktif', color: ok ? AppColors.green : AppColors.red);
          }),
          const SizedBox(height: 8),
          hasInvoice
              ? _printBtn('VIEW INVOICE', 'Sudah dijana - tekan untuk buka', FontAwesomeIcons.eye, AppColors.green, () {
                  Navigator.pop(ctx);
                  _downloadAndOpenPDF(task['pdfUrl_INVOICE'], 'INVOICE', siri);
                })
              : _printBtn('GENERATE INVOICE', 'Jana invoice A4 PDF', FontAwesomeIcons.filePdf, AppColors.green, () {
                  Navigator.pop(ctx);
                  _generatePDF(task, 'INVOICE', isOnline: isOnline);
                }),
          const SizedBox(height: 8),
          hasQuote
              ? _printBtn('VIEW QUOTATION', 'Sudah dijana - tekan untuk buka', FontAwesomeIcons.eye, AppColors.yellow, () {
                  Navigator.pop(ctx);
                  _downloadAndOpenPDF(task['pdfUrl_QUOTATION'], 'QUOTATION', siri);
                })
              : _printBtn('GENERATE QUOTATION', 'Jana sebut harga A4 PDF', FontAwesomeIcons.fileLines, AppColors.yellow, () {
                  Navigator.pop(ctx);
                  _generatePDF(task, 'QUOTATION', isOnline: isOnline);
                }),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════
  // PDF GENERATION (A4 - Cloud Run)
  // ═══════════════════════════════════════
  Map<String, dynamic> _buildPdfPayload(Map<String, dynamic> task, String typePDF) {
    return {
      'typePDF': typePDF,
      'paperSize': 'A4',
      'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
      'logoBase64': _branchSettings['logoBase64'] ?? '',
      'namaKedai': _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'RMS PRO',
      'alamatKedai': _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
      'telKedai': _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
      'noJob': task['siri'] ?? '-',
      'namaCust': task['namaCust'] ?? '-',
      'telCust': task['tel'] ?? '-',
      'tarikhResit': DateFormat('yyyy-MM-dd').format(
        task['timestamp'] is int
            ? DateTime.fromMillisecondsSinceEpoch(task['timestamp'])
            : DateTime.now(),
      ),
      'stafIncharge': task['sender'] ?? task['namaKedai'] ?? 'Pro Mode',
      'items': [
        {
          'nama': '${task['model'] ?? '-'} (${task['kerosakan'] ?? '-'})',
          'harga': double.tryParse(task['harga']?.toString() ?? '0') ?? 0,
        }
      ],
      'model': task['model'] ?? '-',
      'kerosakan': task['kerosakan'] ?? '-',
      'warranty': task['warranty'] ?? 'TIADA',
      'warranty_exp': task['warranty_exp'] ?? '',
      'voucherAmt': 0,
      'diskaunAmt': 0,
      'tambahanAmt': 0,
      'depositAmt': 0,
      'totalDibayar': double.tryParse(task['harga']?.toString() ?? '0') ?? 0,
      'statusBayar': (task['paymentStatus'] ?? 'UNPAID').toString().toUpperCase(),
      'nota': typePDF == 'INVOICE'
          ? (_branchSettings['notaInvoice'] ?? 'Sila simpan dokumen ini untuk rujukan rasmi.')
          : (_branchSettings['notaQuotation'] ?? 'Sebut harga ini sah untuk tempoh 7 hari sahaja.'),
    };
  }

  Future<void> _generatePDF(Map<String, dynamic> task, String typePDF, {required bool isOnline}) async {
    if (!mounted) return;
    final siri = task['siri'] ?? '-';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Color(0xFFA78BFA)),
            const SizedBox(height: 16),
            Text(_lang.get('menjana_pdf'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse('$_cloudRunUrl/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_buildPdfPayload(task, typePDF)),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          final collection = isOnline ? 'collab_global_network' : 'pro_walkin_$_ownerID';
          await _db.collection(collection).doc(task['id']).update({'pdfUrl_$typePDF': pdfUrl});
          _snack('$typePDF berjaya dijana!');
          _downloadAndOpenPDF(pdfUrl, typePDF, siri);
        } else {
          _snack('Pautan PDF tidak ditemui', color: AppColors.red);
        }
      } else {
        _snack('Gagal menjana: ${response.statusCode}', color: AppColors.red);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Gagal sambung server: $e', color: AppColors.red);
    }
  }

  Future<void> _downloadAndOpenPDF(String pdfUrl, String typePDF, String siri) async {
    _snack('Memuat turun $typePDF...');
    try {
      if (kIsWeb) {
        if (!mounted) return;
        launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final fileName = '${typePDF}_PRO_$siri.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (!file.existsSync()) {
        await Dio().download(pdfUrl, filePath);
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              FaIcon(FontAwesomeIcons.filePdf, size: 14, color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow),
              const SizedBox(width: 8),
              Expanded(child: Text('$typePDF #$siri', style: TextStyle(color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
              child: Row(children: [
                FaIcon(FontAwesomeIcons.circleCheck, size: 24, color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$typePDF SEDIA', style: TextStyle(color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
                  Text(fileName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ])),
              ]),
            ),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); OpenFilex.open(filePath); },
              icon: const FaIcon(FontAwesomeIcons.fileCircleCheck, size: 14),
              label: Text(_lang.get('buka_print_pdf')),
              style: ElevatedButton.styleFrom(
                backgroundColor: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            )),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () { Clipboard.setData(ClipboardData(text: pdfUrl)); _snack('Link PDF disalin!'); },
                icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
                label: Text(_lang.get('salin_link')),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.border, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                onPressed: () {
                  final msg = Uri.encodeComponent('$typePDF #$siri\n$pdfUrl');
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
    } catch (e) {
      _snack('Gagal muat turun: $e', color: AppColors.red);
    }
  }

  Widget _printBtn(String title, String desc, IconData icon, Color color, VoidCallback onTap) {
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
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Center(child: FaIcon(icon, size: 16, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
              Text(desc, style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
            ])),
            FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // STATUS TIMELINE WIDGET
  // ═══════════════════════════════════════
  Widget _buildTimeline(List<dynamic>? timeline, {bool compact = false}) {
    if (timeline == null || timeline.isEmpty) return const SizedBox.shrink();
    final items = List<Map<String, dynamic>>.from(timeline.map((e) => Map<String, dynamic>.from(e as Map)));
    items.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          const SizedBox(height: 8),
          Row(children: [
            const FaIcon(FontAwesomeIcons.timeline, size: 10, color: Color(0xFFA78BFA)),
            const SizedBox(width: 6),
            const Text('TIMELINE', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 9, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
        ],
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final st = (item['status'] ?? '-').toString();
          final ts = item['timestamp'] is int ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item['timestamp'])) : '-';
          final by = (item['by'] ?? '').toString();
          final col = _statusColor(st);
          final isLast = i == items.length - 1;
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 20,
                child: Column(children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: isLast ? col : col.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                      border: Border.all(color: col, width: 1.5),
                    ),
                  ),
                  if (!isLast) Expanded(child: Container(width: 1.5, color: AppColors.border)),
                ]),
              ),
              const SizedBox(width: 6),
              Expanded(child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                    child: Text(st, style: TextStyle(color: col, fontSize: compact ? 7 : 8, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  Text(ts, style: TextStyle(color: AppColors.textDim, fontSize: compact ? 7 : 8)),
                  if (by.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text('· $by', style: TextStyle(color: AppColors.textMuted, fontSize: compact ? 6 : 7)),
                  ],
                ]),
              )),
            ]),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════
  String _fmt(dynamic ts) => ts is int ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '-';

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'INCOMING': return const Color(0xFFE879F9);
      case 'TERIMA': return AppColors.blue;
      case 'IN PROGRESS': return AppColors.cyan;
      case 'RETURN SIAP': return const Color(0xFFA78BFA);
      case 'COMPLETED': case 'COMPLETE': return AppColors.green;
      case 'REJECT': case 'RETURN REJECT': return AppColors.red;
      case 'PENDING': return AppColors.yellow;
      default: return AppColors.textMuted;
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800))),
      Expanded(child: Text(value, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _modalField(String label, TextEditingController ctrl, String hint, {TextInputType keyboard = TextInputType.text}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      TextField(controller: ctrl, keyboardType: keyboard, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
          filled: true, fillColor: AppColors.bgDeep, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)))),
    ]));
  }

  void _snack(String msg, {Color color = AppColors.green}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.white, AppColors.card]),
        ),
        child: Column(children: [
          Row(children: [
            const Expanded(child: SizedBox()),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            if (_proModeExpire > 0) Text('${_lang.get('pf_tamat')}: $_proExpireStr', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() { _showArchived = !_showArchived; _filter(); }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (_showArchived ? const Color(0xFFA78BFA) : AppColors.textMuted).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: (_showArchived ? const Color(0xFFA78BFA) : AppColors.textMuted).withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.boxArchive, size: 9, color: _showArchived ? const Color(0xFFA78BFA) : AppColors.textMuted), const SizedBox(width: 4),
                  Text(_lang.get('pf_arkib'), style: TextStyle(color: _showArchived ? const Color(0xFFA78BFA) : AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _showDealerBook,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.addressBook, size: 9, color: AppColors.cyan), const SizedBox(width: 4),
                  Text(_lang.get('pf_dealer_book'), style: const TextStyle(color: AppColors.cyan, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _switchToNormalMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.toggleOff, size: 9, color: AppColors.yellow), const SizedBox(width: 4),
                  Text(_lang.get('pf_normal_mode'), style: const TextStyle(color: AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl, onChanged: (_) => setState(_filter),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: _lang.get('pf_cari_hint'), hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18), filled: true, fillColor: AppColors.bgDeep,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10), isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabCtrl,
            indicatorColor: const Color(0xFFA78BFA),
            indicatorWeight: 3,
            labelColor: const Color(0xFFA78BFA),
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.wifi, size: 10), const SizedBox(width: 6),
                Text('${_lang.get('online')} (${_onlineFiltered.length})'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.handPointer, size: 10), const SizedBox(width: 6),
                Text('${_lang.get('offline')} (${_offlineFiltered.length})'),
              ])),
            ],
          ),
        ]),
      ),

      Expanded(
        child: TabBarView(controller: _tabCtrl, children: [
          _buildOnlineTab(),
          _buildOfflineTab(),
        ]),
      ),
    ]);
  }

  // ═══════════════════════════════════════
  // ONLINE TAB
  // ═══════════════════════════════════════
  Widget _buildOnlineTab() {
    if (_onlineTasks.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(FontAwesomeIcons.wifi, size: 40, color: AppColors.textDim),
        const SizedBox(height: 12),
        Text(_lang.get('pf_tiada_tugasan'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(_lang.get('pf_tugasan_collab'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
      ]));
    }
    if (_onlineFiltered.isEmpty) {
      return Center(child: Text(_lang.get('pf_tiada_padanan'), style: const TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _onlineFiltered.length,
      itemBuilder: (_, i) {
        final t = _onlineFiltered[i];
        final status = (t['status'] ?? 'PENDING').toString().toUpperCase();
        final col = _statusColor(status);
        final isArchived = t['archived'] == true;
        return Dismissible(
          key: Key('online_${t['id']}'),
          direction: isArchived ? DismissDirection.endToStart : DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            if (isArchived) {
              await _db.collection('collab_global_network').doc(t['id']).update({'archived': false});
              _snack('Tugasan dipulihkan');
            } else {
              await _archiveOnline(t);
            }
            return false;
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFA78BFA),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const FaIcon(FontAwesomeIcons.boxArchive, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(_lang.get('pf_arkib'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            ]),
          ),
          secondaryBackground: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_lang.get('pulihkan'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              const FaIcon(FontAwesomeIcons.arrowRotateLeft, size: 16, color: Colors.white),
            ]),
          ),
          child: GestureDetector(
          onTap: () => _showUpdateOnlineModal(t),
          onLongPress: () => _showInfoModal(t),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: isArchived ? [const Color(0xFFA78BFA).withValues(alpha: 0.05), AppColors.bg] : [Colors.white, AppColors.bg]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: isArchived ? const Color(0xFFA78BFA).withValues(alpha: 0.2) : col.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  FaIcon(FontAwesomeIcons.wifi, size: 9, color: col),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _showPrintModal(t, isOnline: true),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('#${t['siri'] ?? '-'}', style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 4),
                      FaIcon(FontAwesomeIcons.print, size: 9, color: col.withValues(alpha: 0.5)),
                    ]),
                  ),
                ]),
                Row(children: [
                  if (isArchived)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFA78BFA).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                      child: Text(_lang.get('pf_arkib'), style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 7, fontWeight: FontWeight.w900)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(status, style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ]),
              ]),
              const SizedBox(height: 6),
              Text(t['namaCust'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(child: Text('${t['model'] ?? '-'}  |  ${t['kerosakan'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const FaIcon(FontAwesomeIcons.arrowRight, size: 8, color: AppColors.textDim),
                const SizedBox(width: 4),
                Text('Dari: ${t['sender'] ?? '-'}', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
              ]),
              if ((t['kurier'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const FaIcon(FontAwesomeIcons.truck, size: 8, color: AppColors.textDim),
                  const SizedBox(width: 4),
                  Text('Kurier: ${t['kurier']}', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                ]),
              ],
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_fmt(t['timestamp']), style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                Row(children: [
                  if ((t['kos'] ?? 0) is num && (t['kos'] as num) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('Kos: RM${(t['kos'] as num).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.orange, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  if ((t['harga'] ?? 0) is num && (t['harga'] as num) > 0)
                    Text('RM${(t['harga'] as num).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
                ]),
              ]),
              if ((t['paymentStatus'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: ((t['paymentStatus'] ?? '').toString().toUpperCase() == 'PAID' ? AppColors.green : AppColors.yellow).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      (t['paymentStatus'] ?? '').toString().toUpperCase(),
                      style: TextStyle(
                        color: (t['paymentStatus'] ?? '').toString().toUpperCase() == 'PAID' ? AppColors.green : AppColors.yellow,
                        fontSize: 8, fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if ((t['paymentMethod'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(t['paymentMethod'].toString(), style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                  ],
                ]),
              ],
              if (t['statusTimeline'] is List && (t['statusTimeline'] as List).isNotEmpty)
                _buildTimeline(t['statusTimeline'] as List, compact: true),
            ]),
          ),
        ));
      },
    );
  }

  // ═══════════════════════════════════════
  // OFFLINE TAB
  // ═══════════════════════════════════════
  Widget _buildOfflineTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          GestureDetector(
            onTap: () => _showOfflineJobModal(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.black), const SizedBox(width: 6),
                Text(_lang.get('pf_job_baru'), style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _offlineTasks.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.handPointer, size: 40, color: AppColors.textDim),
                const SizedBox(height: 12),
                Text(_lang.get('pf_tiada_job_offline'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_lang.get('pf_tambah_manual'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
              ]))
            : _offlineFiltered.isEmpty
                ? Center(child: Text(_lang.get('pf_tiada_padanan'), style: const TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _offlineFiltered.length,
                    itemBuilder: (_, i) {
                      final t = _offlineFiltered[i];
                      final status = (t['status'] ?? 'TERIMA').toString().toUpperCase();
                      final col = _statusColor(status);
                      final isArchived = t['archived'] == true;
                      return Dismissible(
                        key: Key('offline_${t['id']}'),
                        direction: isArchived ? DismissDirection.endToStart : DismissDirection.startToEnd,
                        confirmDismiss: (_) async {
                          if (isArchived) {
                            await _db.collection('pro_walkin_$_ownerID').doc(t['id']).update({'archived': false});
                            _snack('Job dipulihkan');
                          } else {
                            await _archiveOffline(t);
                          }
                          return false;
                        },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(color: const Color(0xFFA78BFA), borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const FaIcon(FontAwesomeIcons.boxArchive, size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(_lang.get('pf_arkib'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                          ]),
                        ),
                        secondaryBackground: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_lang.get('pulihkan'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                            const SizedBox(width: 8),
                            const FaIcon(FontAwesomeIcons.arrowRotateLeft, size: 16, color: Colors.white),
                          ]),
                        ),
                        child: GestureDetector(
                        onTap: () => _showOfflineJobModal(existing: t),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: isArchived ? [const Color(0xFFA78BFA).withValues(alpha: 0.05), AppColors.bg] : [Colors.white, AppColors.bg]),
                            borderRadius: BorderRadius.circular(12), border: Border.all(color: isArchived ? const Color(0xFFA78BFA).withValues(alpha: 0.2) : col.withValues(alpha: 0.2)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Row(children: [
                                FaIcon(FontAwesomeIcons.handPointer, size: 9, color: col),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _showPrintModal(t, isOnline: false),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text('#${t['siri'] ?? '-'}', style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w900)),
                                    const SizedBox(width: 4),
                                    FaIcon(FontAwesomeIcons.print, size: 9, color: col.withValues(alpha: 0.5)),
                                  ]),
                                ),
                              ]),
                              Row(children: [
                                if (isArchived)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(color: const Color(0xFFA78BFA).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                                    child: Text(_lang.get('pf_arkib'), style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 7, fontWeight: FontWeight.w900)),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                  child: Text(status, style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w900)),
                                ),
                              ]),
                            ]),
                            const SizedBox(height: 6),
                            Text(t['namaKedai'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                            if ((t['namaCust'] ?? '').toString().isNotEmpty)
                              Text(t['namaCust'], style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('${t['model'] ?? '-'}  |  ${t['kerosakan'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10), overflow: TextOverflow.ellipsis),
                            if ((t['tel'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(t['tel'], style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                            ],
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(_fmt(t['timestamp']), style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                              Row(children: [
                                if ((t['paymentStatus'] ?? '').toString().isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: ((t['paymentStatus'] ?? '').toString().toUpperCase() == 'PAID' ? AppColors.green : AppColors.yellow).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      (t['paymentStatus'] ?? '').toString().toUpperCase(),
                                      style: TextStyle(
                                        color: (t['paymentStatus'] ?? '').toString().toUpperCase() == 'PAID' ? AppColors.green : AppColors.yellow,
                                        fontSize: 8, fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                if ((t['harga'] ?? 0) is num && (t['harga'] as num) > 0)
                                  Text('RM${(t['harga'] as num).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
                              ]),
                            ]),
                            if (t['statusTimeline'] is List && (t['statusTimeline'] as List).isNotEmpty)
                              _buildTimeline(t['statusTimeline'] as List, compact: true),
                          ]),
                        ),
                      ));
                    },
                  ),
      ),
    ]);
  }
}
