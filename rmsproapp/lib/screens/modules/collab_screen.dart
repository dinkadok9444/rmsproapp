import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

class CollabScreen extends StatefulWidget {
  const CollabScreen({super.key});
  @override
  State<CollabScreen> createState() => _CollabScreenState();
}

class _CollabScreenState extends State<CollabScreen> {
  final _lang = AppLanguage();
  final _db = FirebaseFirestore.instance;
  String _ownerID = 'admin', _shopID = 'MAIN';
  List<Map<String, dynamic>> _sentArr = [];
  List<Map<String, dynamic>> _repairs = [];
  List<Map<String, dynamic>> _savedDealers = [];
  StreamSubscription? _collabSub, _repairSub;
  String _filterStatus = 'SEMUA';
  bool _showArchive = false;
  final List<String> _statusOptions = ['SEMUA', 'PENDING', 'TERIMA', 'IN PROGRESS', 'COMPLETED', 'REJECT', 'RETURN REJECT', 'DELIVERED'];

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _collabSub?.cancel(); _repairSub?.cancel(); super.dispose(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) { _ownerID = branch.split('@')[0]; _shopID = branch.split('@')[1].toUpperCase(); }
    try {
      final shopDoc = await _db.collection('shops_$_ownerID').doc(_shopID).get();
      if (shopDoc.exists) {
        final raw = shopDoc.data()?['savedDealers'];
        if (raw is List) _savedDealers = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    _collabSub = _db.collection('collab_global_network').snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) { final d = doc.data(); d['key'] = doc.id; if (d['sender'] == _shopID) list.add(d); }
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _sentArr = list);
    });
    _repairSub = _db.collection('repairs_$_ownerID').snapshots().listen((snap) {
      _repairs = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    });
  }

  Future<void> _saveDealerToBook(String code, String name, String phone) async {
    if (_savedDealers.any((d) => d['code'] == code)) return;
    _savedDealers.add({'code': code, 'name': name, 'phone': phone, 'timestamp': DateTime.now().millisecondsSinceEpoch});
    try {
      await _db.collection('shops_$_ownerID').doc(_shopID).set({'savedDealers': _savedDealers}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _removeSavedDealer(String code) async {
    _savedDealers.removeWhere((d) => d['code'] == code);
    try {
      await _db.collection('shops_$_ownerID').doc(_shopID).set({'savedDealers': _savedDealers}, SetOptions(merge: true));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Color _statusColor(String s) {
    if (s == 'COMPLETE' || s == 'DELIVERED') return AppColors.primary;
    if (s == 'REJECT' || s == 'RETURN REJECT') return AppColors.red;
    if (s == 'TERIMA' || s == 'IN PROGRESS') return AppColors.blue;
    return AppColors.yellow;
  }

  String _fmtDate(dynamic ts) => ts is int ? DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '-';

  void _showStatusModal(Map<String, dynamic> d) {
    final col = _statusColor(d['status'] ?? 'PENDING');
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [const FaIcon(FontAwesomeIcons.circleInfo, size: 14, color: AppColors.primary), const SizedBox(width: 8),
          Text(_lang.get('cl_maklumat_tugasan'), style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(20), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(_lang.get('cl_status_terkini'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(d['status'] ?? 'PENDING', style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.w900)),
          ])),
        const SizedBox(height: 16),
        _infoBox(_lang.get('cl_nota_dealer'), d['catatan_pro'] ?? _lang.get('cl_tiada_nota')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _infoBox(_lang.get('cl_kurier_return'), d['kurier_return'] ?? _lang.get('cl_tiada'))),
          const SizedBox(width: 8),
          Expanded(child: _infoBox(_lang.get('cl_tracking_return'), d['terima'] ?? _lang.get('cl_tiada'))),
        ]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('tutup')))),
      ])),
    ));
  }

  Widget _infoBox(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
    const SizedBox(height: 4),
    Container(padding: const EdgeInsets.all(10), width: double.infinity,
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderMed)),
      child: Text(value, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700))),
  ]);

  void _showSendTask() {
    final searchCtrl = TextEditingController();
    final dealerCodeCtrl = TextEditingController();
    final kurierCtrl = TextEditingController();
    final trackCtrl = TextEditingController();
    final catatanCtrl = TextEditingController();
    Map<String, dynamic>? foundTicket;
    Map<String, dynamic>? foundDealer;
    String dealerStatus = '';
    bool canSend = false;
    bool isSending = false;
    bool isChecking = false;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {

        // Function to check dealer
        Future<void> semakDealer(String code) async {
          if (code.isEmpty) return;
          setS(() { isChecking = true; dealerStatus = 'Sedang semak...'; foundDealer = null; canSend = false; });
          try {
            final snap = await _db.collection('saas_dealers').get();
            Map<String, dynamic>? dealer;
            for (final doc in snap.docs) {
              final d = doc.data();
              final sid = (d['shopID'] ?? '').toString().toUpperCase();
              if (sid == code) { dealer = d; break; }
            }
            if (dealer != null) {
              final now = DateTime.now().millisecondsSinceEpoch;
              final isPro = dealer['proMode'] == true && ((dealer['proModeExpire'] ?? 0) as num) > now;
              setS(() { foundDealer = dealer; canSend = isPro; isChecking = false; dealerStatus = isPro ? _lang.get('cl_pro_aktif') : _lang.get('cl_tiada_pro'); });
            } else {
              setS(() { foundDealer = null; canSend = false; isChecking = false; dealerStatus = _lang.get('cl_kod_tiada'); });
            }
          } catch (e) {
            setS(() { dealerStatus = 'Ralat semak: $e'; canSend = false; isChecking = false; });
          }
        }

        return Container(
        margin: const EdgeInsets.only(top: 50),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [const FaIcon(FontAwesomeIcons.handshake, size: 14, color: AppColors.blue), const SizedBox(width: 8),
                Text(_lang.get('cl_hantar_tugasan'), style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900))]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 16),

            // ── STEP 1: Cari Tiket ──
            Text(_lang.get('cl_cari_siri_hint'), style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            TextField(controller: searchCtrl, textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700), decoration: _inputDeco(_lang.get('cl_cth_dealer')),
              onSubmitted: (val) {
                final v = val.trim().toUpperCase();
                if (v.isEmpty) return;
                final found = _repairs.firstWhere((r) => (r['siri'] ?? '').toString().toUpperCase() == v, orElse: () => <String, dynamic>{});
                if (found.isEmpty) {
                  setS(() => foundTicket = null);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[$v] ${_lang.get('cl_tidak_dijumpai')}'), backgroundColor: AppColors.red));
                } else {
                  setS(() => foundTicket = found);
                }
              }),
            if (foundTicket != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
                child: Column(children: [
                  Row(children: [Expanded(child: _mini('Nama', foundTicket!['nama'] ?? '-')), Expanded(child: _mini('Model', foundTicket!['model'] ?? '-'))]),
                  const SizedBox(height: 6),
                  Row(children: [Expanded(child: _mini('Tel', foundTicket!['tel'] ?? '-')), Expanded(child: _mini('Kerosakan', foundTicket!['kerosakan'] ?? '-'))]),
                  const SizedBox(height: 6),
                  _mini('Password/Pattern', foundTicket!['password'] ?? 'TIADA', color: AppColors.orange),
                ])),
            ],
            const SizedBox(height: 16),

            // ── STEP 2: Kod Dealer ──
            Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.blue.withValues(alpha: 0.15))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_lang.get('cl_kod_dealer'), style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: TextField(controller: dealerCodeCtrl, textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700), decoration: _inputDeco(_lang.get('cl_cari_kod_hint')),
                    onSubmitted: (val) => semakDealer(val.trim().toUpperCase()),
                  )),
                  const SizedBox(width: 8),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                    onPressed: isChecking ? null : () => semakDealer(dealerCodeCtrl.text.trim().toUpperCase()),
                    child: isChecking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: [const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 10), const SizedBox(width: 4), Text(_lang.get('cl_semak'))])),
                ]),
                if (dealerStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(dealerStatus, style: TextStyle(color: canSend ? AppColors.green : AppColors.red, fontSize: 10, fontWeight: FontWeight.w900))),
                if (foundDealer != null) ...[const SizedBox(height: 8), _mini('Kedai', foundDealer!['namaKedai'] ?? '-'), _mini('Tel', foundDealer!['phone'] ?? '-')],

                // ── Senarai Kedai Tersimpan ──
                if (_savedDealers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_lang.get('cl_kedai_tersimpan'), style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: _savedDealers.map((d) => GestureDetector(
                    onTap: () {
                      dealerCodeCtrl.text = d['code'] ?? '';
                      semakDealer((d['code'] ?? '').toString().toUpperCase());
                    },
                    onLongPress: () async {
                      final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text('${_lang.get('cl_buang')} ${d['name'] ?? d['code']}?', style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
                        content: Text(_lang.get('cl_kedai_buang'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_lang.get('batal'))),
                          ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.red), child: Text(_lang.get('cl_buang'))),
                        ],
                      ));
                      if (confirm == true) {
                        await _removeSavedDealer(d['code'] ?? '');
                        setS(() {});
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.blue.withValues(alpha: 0.2))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const FaIcon(FontAwesomeIcons.store, size: 9, color: AppColors.blue),
                        const SizedBox(width: 6),
                        Text(d['code'] ?? '-', style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w900)),
                        if ((d['name'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text('(${d['name']})', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                        ],
                      ]),
                    ),
                  )).toList()),
                ],
              ])),
            const SizedBox(height: 12),

            // ── STEP 3: Kurier & Catatan ──
            Row(children: [Expanded(child: _lbl('Kurier', kurierCtrl, 'Cth: J&T')), const SizedBox(width: 8), Expanded(child: _lbl('Tracking No', trackCtrl, 'No Track'))]),
            _lbl('Catatan / Arahan Kerja', catatanCtrl, 'Cth: Tolong repair board...'),
            const SizedBox(height: 16),

            // ── SUBMIT BUTTON ──
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: (canSend && foundTicket != null && !isSending) ? AppColors.primary : AppColors.textDim,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: isSending ? null : () async {
                // Validation
                if (foundTicket == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('cl_sila_cari_siri')), backgroundColor: AppColors.red));
                  return;
                }
                if (!canSend || foundDealer == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('cl_sila_semak_kod')), backgroundColor: AppColors.red));
                  return;
                }
                final siri = (foundTicket!['siri'] ?? '').toString();
                if (siri.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('cl_tiket_tiada_siri')), backgroundColor: AppColors.red));
                  return;
                }
                final rx = dealerCodeCtrl.text.trim().toUpperCase();
                if (rx == _shopID) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('cl_tak_boleh_hantar')), backgroundColor: AppColors.red));
                  return;
                }

                setS(() => isSending = true);
                try {
                  String shopName = _shopID;
                  try { final sDoc = await _db.collection('shops_$_ownerID').doc(_shopID).get(); if (sDoc.exists) shopName = sDoc.data()?['shopName'] ?? _shopID; } catch (_) {}

                  final payload = {
                    'siri': siri,
                    'sender': _shopID,
                    'sender_name': shopName,
                    'receiver': rx,
                    'kurier': kurierCtrl.text.trim(),
                    'hantar': trackCtrl.text.trim(),
                    'terima': '',
                    'catatan': catatanCtrl.text.trim(),
                    'namaCust': foundTicket!['nama'] ?? '',
                    'model': foundTicket!['model'] ?? '',
                    'kerosakan': foundTicket!['kerosakan'] ?? '',
                    'password': foundTicket!['password'] ?? '',
                    'catatan_pro': '',
                    'kurier_return': '',
                    'harga': 0,
                    'kos': 0,
                    'payment_status': 'UNPAID',
                    'cara_bayaran': 'CASH',
                    'status': 'PENDING',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'timestamp_update': DateTime.now().millisecondsSinceEpoch,
                  };

                  await _db.collection('collab_global_network').doc(siri).set(payload);

                  // Auto simpan kedai ke buku jika belum ada
                  await _saveDealerToBook(rx, foundDealer!['namaKedai'] ?? '', foundDealer!['phone'] ?? '');

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tugasan [$siri] ${_lang.get('cl_tugasan_berjaya')} [$rx]'), backgroundColor: AppColors.green));
                  }
                } catch (e) {
                  setS(() => isSending = false);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal hantar: $e'), backgroundColor: AppColors.red));
                }
              },
              icon: isSending
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const FaIcon(FontAwesomeIcons.paperPlane, size: 12),
              label: Text(isSending ? 'MENGHANTAR...' : _lang.get('cl_hantar_tugasan'), style: const TextStyle(fontWeight: FontWeight.w900)),
            )),
          ]),
        ),
      );
      }),
    );
  }

  Widget _mini(String label, String value, {Color color = AppColors.textPrimary}) => Padding(padding: const EdgeInsets.only(bottom: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
      Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    ]));

  Widget _lbl(String label, TextEditingController ctrl, String hint) => Padding(padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w900)), const SizedBox(height: 4),
      TextField(controller: ctrl, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700), decoration: _inputDeco(hint)),
    ]));

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
    filled: true, fillColor: AppColors.bg, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.borderMed)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.borderMed)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.blue)));

  List<Map<String, dynamic>> get _filteredSent {
    final active = _sentArr.where((d) => d['archived'] != true).toList();
    if (_filterStatus == 'SEMUA') return active;
    return active.where((d) => (d['status'] ?? 'PENDING') == _filterStatus).toList();
  }

  List<Map<String, dynamic>> get _archivedSent {
    return _sentArr.where((d) => d['archived'] == true).toList();
  }

  Future<void> _archiveItem(Map<String, dynamic> d) async {
    try {
      await _db.collection('collab_global_network').doc(d['key']).update({'archived': true});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('cl_arkib_berjaya')), backgroundColor: AppColors.primary));
    } catch (_) {}
  }

  Future<void> _restoreItem(Map<String, dynamic> d) async {
    try {
      await _db.collection('collab_global_network').doc(d['key']).update({'archived': false});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('cl_pulih_berjaya')), backgroundColor: AppColors.blue));
    } catch (_) {}
  }

  Widget _buildCard(Map<String, dynamic> d, {bool isArchive = false}) {
    final col = _statusColor(d['status'] ?? 'PENDING');
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: isArchive ? [AppColors.bg, AppColors.bg] : [Colors.white, AppColors.bg]),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: isArchive ? AppColors.textDim : AppColors.borderMed)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.blue.withValues(alpha: 0.3))),
            child: Text(d['receiver'] ?? '-', style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w900))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: col), borderRadius: BorderRadius.circular(6)),
            child: Text(d['status'] ?? 'PENDING', style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 8),
        Text(d['namaCust'] ?? 'TIADA NAMA', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Row(children: [
          Text(d['siri'] ?? '-', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          Text('${_fmtDate(d['timestamp'])} | ${d['model'] ?? '-'}', style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text('Kemaskini: ${_fmtDate(d['timestamp_update'])}', style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => _showStatusModal(d),
            child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const FaIcon(FontAwesomeIcons.eye, size: 10, color: AppColors.primary), const SizedBox(width: 6),
                Text(_lang.get('cl_lihat_status'), style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900))])))),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => isArchive ? _restoreItem(d) : _archiveItem(d),
            child: Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: isArchive ? AppColors.blue.withValues(alpha: 0.15) : AppColors.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isArchive ? AppColors.blue.withValues(alpha: 0.3) : AppColors.yellow.withValues(alpha: 0.3))),
              child: FaIcon(isArchive ? FontAwesomeIcons.rotateLeft : FontAwesomeIcons.boxArchive, size: 10,
                color: isArchive ? AppColors.blue : AppColors.yellow))),
        ]),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _showArchive ? _archivedSent : _filteredSent;
    return Stack(children: [
      Column(children: [
        Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.blue, width: 1))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                FaIcon(_showArchive ? FontAwesomeIcons.boxArchive : FontAwesomeIcons.paperPlane, size: 14, color: _showArchive ? AppColors.yellow : AppColors.blue),
                const SizedBox(width: 8),
                Text(_showArchive ? _lang.get('cl_arkib') : _lang.get('cl_outbox'),
                  style: TextStyle(color: _showArchive ? AppColors.yellow : AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900))]),
              Text('${displayList.length}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              // ── Dropdown Status Filter ──
              if (!_showArchive) ...[
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderMed)),
                  child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                    value: _filterStatus, isExpanded: true, isDense: true,
                    style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900),
                    icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 8, color: AppColors.textMuted),
                    items: _statusOptions.map((s) => DropdownMenuItem(value: s,
                      child: Row(children: [
                        if (s != 'SEMUA') Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(color: _statusColor(s), shape: BoxShape.circle)),
                        Text(s == 'SEMUA' ? _lang.get('cl_semua_status') : s, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                      ]))).toList(),
                    onChanged: (v) { if (v != null) setState(() => _filterStatus = v); },
                  )))),
                const SizedBox(width: 8),
              ],
              // ── Butang Arkib / Kembali ──
              GestureDetector(
                onTap: () => setState(() { _showArchive = !_showArchive; }),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: _showArchive ? AppColors.blue.withValues(alpha: 0.8) : AppColors.yellow.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(_showArchive ? FontAwesomeIcons.arrowLeft : FontAwesomeIcons.boxArchive, size: 10, color: Colors.black),
                    const SizedBox(width: 6),
                    Text(_showArchive ? _lang.get('cl_outbox') : _lang.get('cl_arkib'),
                      style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900))]))),
              if (!_showArchive) ...[
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(onTap: _showSendTask, child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.black), const SizedBox(width: 6),
                    Text(_lang.get('cl_hantar_tugasan_baru'), style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900))])))),
              ],
            ]),
          ])),
        Expanded(child: displayList.isEmpty
          ? Center(child: Text(_showArchive ? _lang.get('cl_tiada_arkib') : _lang.get('cl_tiada_rekod_hantar'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)))
          : ListView.builder(padding: const EdgeInsets.all(12), itemCount: displayList.length, itemBuilder: (_, i) {
              final d = displayList[i];
              if (_showArchive) return _buildCard(d, isArchive: true);
              // ── Slide to archive ──
              return Dismissible(
                key: Key(d['key'] ?? '$i'),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.only(right: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_lang.get('cl_arkib'), style: const TextStyle(color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    const FaIcon(FontAwesomeIcons.boxArchive, size: 14, color: AppColors.yellow),
                  ])),
                confirmDismiss: (_) async { await _archiveItem(d); return false; },
                child: _buildCard(d),
              );
            })),
      ]),
    ]);
  }
}
