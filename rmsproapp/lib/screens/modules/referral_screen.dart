import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _lang = AppLanguage();
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  final _custSearchCtrl = TextEditingController();

  String _ownerID = 'admin', _shopID = 'MAIN';
  String _svPass = '';

  // Referral list
  List<Map<String, dynamic>> _referrals = [];
  List<Map<String, dynamic>> _filtered = [];
  StreamSubscription? _refSub;

  // Repairs data for customer search
  List<Map<String, dynamic>> _rawDataArr = [];
  StreamSubscription? _repairsSub;

  // Customer search results
  List<Map<String, dynamic>> _custSearchResults = [];

  @override
  void initState() { super.initState(); _init(); }

  @override
  void dispose() {
    _refSub?.cancel();
    _repairsSub?.cancel();
    _searchCtrl.dispose();
    _custSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase();
      _shopID = branch.split('@')[1].toUpperCase();
    }
    _loadBranchSettings();
    _listenReferrals();
    _listenRepairs();
  }

  Future<void> _loadBranchSettings() async {
    final snap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
    if (snap.exists && mounted) {
      final d = snap.data() ?? {};
      _svPass = (d['svPass'] ?? d['branchAdminPass'] ?? '').toString();
    }
  }

  // ═══════════════════════════════════════
  // LISTEN REFERRALS
  // ═══════════════════════════════════════
  void _listenReferrals() {
    _refSub = _db.collection('referrals_$_ownerID')
        .orderBy('timestamp', descending: true)
        .snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data(); d['id'] = doc.id;
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) list.add(d);
      }
      if (mounted) setState(() { _referrals = list; _filterReferrals(); });
    });
  }

  void _filterReferrals() {
    final q = _searchCtrl.text.toLowerCase().trim();
    _filtered = q.isEmpty ? List.from(_referrals) : _referrals.where((d) =>
      (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
      (d['tel'] ?? '').toString().toLowerCase().contains(q) ||
      (d['refCode'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  // ═══════════════════════════════════════
  // LISTEN REPAIRS (rawDataArr) for customer search
  // ═══════════════════════════════════════
  void _listenRepairs() {
    _repairsSub = _db.collection('repairs_$_ownerID').snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data(); d['id'] = doc.id;
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) list.add(d);
      }
      if (mounted) setState(() => _rawDataArr = list);
    });
  }

  // ═══════════════════════════════════════
  // GENERATE REFERRAL CODE
  // ═══════════════════════════════════════
  String _generateRefCode() {
    final rng = Random();
    final code = rng.nextInt(900000) + 100000;
    return 'REF-$code';
  }

  // ═══════════════════════════════════════
  // SEARCH CUSTOMER & CREATE REFERRAL
  // ═══════════════════════════════════════
  void _showSearchCustomerModal() {
    _custSearchCtrl.clear();
    _custSearchResults = [];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.userPlus, size: 14, color: AppColors.green),
                const SizedBox(width: 8),
                Text(_lang.get('rf_cari_pelanggan'), style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
              ]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const Divider(color: AppColors.borderMed, height: 20),
            Text(_lang.get('rf_cari_desc'), style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
            const SizedBox(height: 10),
            TextField(
              controller: _custSearchCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: _lang.get('rf_cari_hint'), hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                suffixIcon: GestureDetector(
                  onTap: () {
                    final q = _custSearchCtrl.text.toLowerCase().trim();
                    if (q.isEmpty) return;
                    final results = _rawDataArr.where((d) =>
                      (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
                      (d['tel'] ?? '').toString().toLowerCase().contains(q)).toList();
                    setS(() => _custSearchResults = results);
                  },
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(6)),
                    child: Text(_lang.get('cari'), style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                ),
                filled: true, fillColor: AppColors.bgDeep, isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
              onSubmitted: (_) {
                final q = _custSearchCtrl.text.toLowerCase().trim();
                if (q.isEmpty) return;
                final results = _rawDataArr.where((d) =>
                  (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
                  (d['tel'] ?? '').toString().toLowerCase().contains(q)).toList();
                setS(() => _custSearchResults = results);
              },
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _custSearchResults.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_lang.get('rf_tiada_hasil'), style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
                    ))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _custSearchResults.length,
                      itemBuilder: (_, i) {
                        final c = _custSearchResults[i];
                        final alreadyExists = _referrals.any((r) =>
                          (r['tel'] ?? '').toString() == (c['tel'] ?? '').toString() &&
                          (r['tel'] ?? '').toString().isNotEmpty);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderMed),
                          ),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['nama'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                              Text('${c['tel'] ?? '-'}  |  #${c['siri'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                            ])),
                            if (alreadyExists)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.textDim.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                child: Text(_lang.get('rf_sudah_ada'), style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900)),
                              )
                            else
                              GestureDetector(
                                onTap: () async {
                                  final refCode = _generateRefCode();
                                  // Ensure unique code
                                  final existing = await _db.collection('referrals_$_ownerID').doc(refCode).get();
                                  final finalCode = existing.exists ? _generateRefCode() : refCode;
                                  await _db.collection('referrals_$_ownerID').doc(finalCode).set({
                                    'refCode': finalCode,
                                    'nama': (c['nama'] ?? '').toString().toUpperCase(),
                                    'tel': c['tel'] ?? '',
                                    'siriAsal': c['siri'] ?? '',
                                    'shopID': _shopID,
                                    'ownerID': _ownerID,
                                    'status': 'ACTIVE',
                                    'bank': '',
                                    'accNo': '',
                                    'commission': 0,
                                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _snack('Referral $finalCode dijana');
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(6)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const FaIcon(FontAwesomeIcons.plus, size: 9, color: Colors.black), const SizedBox(width: 4),
                                    Text(_lang.get('rf_jana_kod'), style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                                  ]),
                                ),
                              ),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      )),
    );
  }

  // ═══════════════════════════════════════
  // WHATSAPP SEND CODE
  // ═══════════════════════════════════════
  Future<void> _sendWhatsApp(String tel, String refCode, String nama) async {
    final phone = tel.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = phone.startsWith('0') ? '6$phone' : phone;
    final msg = Uri.encodeComponent(
      'Salam $nama! Kod referral anda: *$refCode*\n\nKongsikan kod ini kepada rakan/keluarga anda. Setiap pembaikan menggunakan kod ini, anda layak menerima komisyen!\n\nTerima kasih.');
    final url = 'https://wa.me/$formatted?text=$msg';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  // ═══════════════════════════════════════
  // EDIT REFERRAL MODAL
  // ═══════════════════════════════════════
  void _showEditReferralModal(Map<String, dynamic> ref) {
    final bankCtrl = TextEditingController(text: ref['bank'] ?? '');
    final accNoCtrl = TextEditingController(text: ref['accNo'] ?? '');
    final commCtrl = TextEditingController(text: (ref['commission'] ?? '').toString());
    String refStatus = (ref['status'] ?? 'ACTIVE').toString().toUpperCase();
    List<Map<String, dynamic>> claims = [];
    bool loadingClaims = true;

    // Load claims
    _db.collection('referral_claims_$_ownerID')
        .where('refCode', isEqualTo: ref['refCode'])
        .orderBy('timestamp', descending: true)
        .get().then((snap) {
      claims = snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
      loadingClaims = false;
    }).catchError((_) {
      loadingClaims = false;
    });

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        // Reload claims on first build if still loading
        if (loadingClaims) {
          _db.collection('referral_claims_$_ownerID')
              .where('refCode', isEqualTo: ref['refCode'])
              .orderBy('timestamp', descending: true)
              .get().then((snap) {
            if (ctx.mounted) {
              setS(() {
                claims = snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
                loadingClaims = false;
              });
            }
          }).catchError((_) {
            if (ctx.mounted) setS(() => loadingClaims = false);
          });
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Row(children: [
                  const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: Color(0xFFA78BFA)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_lang.get('rf_edit_referral'), style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 13, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
              const Divider(color: AppColors.borderMed, height: 20),

              // Info
              _infoRow('Kod', ref['refCode'] ?? '-'),
              _infoRow('Nama', ref['nama'] ?? '-'),
              _infoRow('Tel', ref['tel'] ?? '-'),
              _infoRow('Status', refStatus),
              const Divider(color: AppColors.borderMed, height: 16),

              // Bank info
              _modalField('NAMA BANK', bankCtrl, 'Maybank, CIMB...'),
              _modalField('NO AKAUN', accNoCtrl, '1234567890'),
              _modalField('KOMISYEN (RM)', commCtrl, '0.00', keyboard: TextInputType.number),

              const SizedBox(height: 12),
              // Action buttons
              Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: () async {
                    await _db.collection('referrals_$_ownerID').doc(ref['id']).update({
                      'bank': bankCtrl.text.trim().toUpperCase(),
                      'accNo': accNoCtrl.text.trim(),
                      'commission': double.tryParse(commCtrl.text) ?? 0,
                      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('Referral dikemaskini');
                  },
                  icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
                  label: Text(_lang.get('simpan'), style: const TextStyle(fontSize: 11)),
                )),
                const SizedBox(width: 6),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: refStatus == 'ACTIVE' ? AppColors.yellow : AppColors.green,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final newStatus = refStatus == 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE';
                    await _db.collection('referrals_$_ownerID').doc(ref['id']).update({
                      'status': newStatus,
                      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                    });
                    setS(() => refStatus = newStatus);
                    _snack(newStatus == 'ACTIVE' ? 'Referral diaktifkan' : 'Referral digantung');
                  },
                  icon: FaIcon(refStatus == 'ACTIVE' ? FontAwesomeIcons.pause : FontAwesomeIcons.play, size: 12),
                  label: Text(refStatus == 'ACTIVE' ? 'GANTUNG' : 'AKTIF', style: const TextStyle(fontSize: 11)),
                )),
                const SizedBox(width: 6),
                SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: () => _confirmDeleteReferral(ctx, ref),
                    child: const FaIcon(FontAwesomeIcons.trashCan, size: 14),
                  ),
                ),
              ]),

              // Claim history
              const SizedBox(height: 20),
              const Divider(color: AppColors.borderMed),
              const SizedBox(height: 8),
              Row(children: [
                const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 12, color: AppColors.cyan),
                const SizedBox(width: 6),
                Text('${_lang.get('rf_sejarah_tuntutan')} (${claims.length})', style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 8),
              if (loadingClaims)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)))
              else if (claims.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Center(child: Text(_lang.get('rf_tiada_sejarah'), style: const TextStyle(color: AppColors.textDim, fontSize: 11))))
              else
                ...claims.map((cl) {
                  final isPaid = (cl['paymentStatus'] ?? '').toString().toUpperCase() == 'PAID';
                  final clColor = isPaid ? AppColors.green : AppColors.yellow;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: clColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cl['redeemerName'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                        Text(cl['perkara'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                        Text(_fmt(cl['timestamp']), style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('RM${((cl['amount'] ?? 0) as num).toStringAsFixed(2)}', style: TextStyle(color: clColor, fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () async {
                            final newPayStatus = isPaid ? 'UNPAID' : 'PAID';
                            await _db.collection('referral_claims_$_ownerID').doc(cl['id']).update({
                              'paymentStatus': newPayStatus,
                              'paidAt': newPayStatus == 'PAID' ? DateTime.now().millisecondsSinceEpoch : null,
                            });
                            // Reload claims
                            final snap = await _db.collection('referral_claims_$_ownerID')
                                .where('refCode', isEqualTo: ref['refCode'])
                                .orderBy('timestamp', descending: true).get();
                            if (ctx.mounted) {
                              setS(() {
                                claims = snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: clColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: clColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              isPaid ? 'PAID' : 'UNPAID',
                              style: TextStyle(color: clColor, fontSize: 8, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  );
                }),
              const SizedBox(height: 8),
            ])),
          ),
        );
      }),
    );
  }

  // ═══════════════════════════════════════
  // DELETE WITH PIN VERIFICATION
  // ═══════════════════════════════════════
  void _confirmDeleteReferral(BuildContext parentCtx, Map<String, dynamic> ref) {
    final pinCtrl = TextEditingController();

    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const FaIcon(FontAwesomeIcons.triangleExclamation, size: 16, color: AppColors.red), const SizedBox(width: 8),
          Text(_lang.get('rf_padam_referral'), style: const TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Adakah anda pasti mahu memadam referral ${ref['refCode']}?', style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: Text(_lang.get('rf_masukkan_pin'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900))),
          const SizedBox(height: 4),
          TextField(
            controller: pinCtrl, obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, letterSpacing: 4, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '****', hintStyle: const TextStyle(color: AppColors.textDim),
              filled: true, fillColor: AppColors.bgDeep, isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal'), style: const TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final pin = pinCtrl.text.trim();
              if (pin.isEmpty) {
                _snack('Sila masukkan PIN', color: AppColors.red);
                return;
              }
              if (pin != _svPass) {
                _snack('PIN tidak sah!', color: AppColors.red);
                return;
              }
              await _db.collection('referrals_$_ownerID').doc(ref['id']).delete();
              if (ctx.mounted) Navigator.pop(ctx); // Close PIN dialog
              if (parentCtx.mounted) Navigator.pop(parentCtx); // Close edit modal
              _snack('Referral dipadam');
            },
            child: Text(_lang.get('padam')),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════
  String _fmt(dynamic ts) => ts is int ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '-';

  Widget _infoRow(String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800))),
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
      // Header
      Container(
        padding: const EdgeInsets.all(12), color: AppColors.card,
        child: Column(children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.userGroup, size: 14, color: Color(0xFF34D399)),
            const SizedBox(width: 8),
            Expanded(child: Text(_lang.get('rf_referral'), style: const TextStyle(color: Color(0xFF34D399), fontSize: 14, fontWeight: FontWeight.w900))),
            Text('${_filtered.length} rekod', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showSearchCustomerModal,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.black), const SizedBox(width: 6),
                  Text(_lang.get('rf_jana_kod'), style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl, onChanged: (_) => setState(_filterReferrals),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Cari nama, telefon, kod...', hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18), filled: true, fillColor: AppColors.bgDeep,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10), isDense: true,
            ),
          ),
        ]),
      ),

      // List
      Expanded(
        child: _referrals.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.userGroup, size: 40, color: AppColors.textDim),
                const SizedBox(height: 12),
                Text(_lang.get('rf_tiada_rekod'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Tekan "JANA KOD" untuk menambah\nreferral baru dari rekod pembaikan', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 10)),
              ]))
            : _filtered.isEmpty
                ? Center(child: Text(_lang.get('rf_tiada_padanan'), style: const TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final r = _filtered[i];
                      final isActive = (r['status'] ?? '').toString().toUpperCase() == 'ACTIVE';
                      final badgeColor = isActive ? AppColors.green : AppColors.red;
                      final commission = (r['commission'] ?? 0) is num ? (r['commission'] as num) : 0;

                      return GestureDetector(
                        onTap: () => _showEditReferralModal(r),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            // Row 1: Name + status badge
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Expanded(child: Text(r['nama'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text(isActive ? 'ACTIVE' : 'SUSPENDED', style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.w900)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            // Row 2: Tel
                            Text(r['tel'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                            const SizedBox(height: 6),
                            // Row 3: Referral code + WhatsApp button + bank/commission
                            Row(children: [
                              // Referral code
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA78BFA).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3)),
                                ),
                                child: Text(r['refCode'] ?? '-', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 6),
                              // WhatsApp button
                              GestureDetector(
                                onTap: () => _sendWhatsApp(r['tel'] ?? '', r['refCode'] ?? '', r['nama'] ?? ''),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: const Color(0xFF25D366).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3))),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const FaIcon(FontAwesomeIcons.whatsapp, size: 12, color: Color(0xFF25D366)),
                                    const SizedBox(width: 4),
                                    Text(_lang.get('rf_hantar'), style: const TextStyle(color: Color(0xFF25D366), fontSize: 8, fontWeight: FontWeight.w900)),
                                  ]),
                                ),
                              ),
                              const Spacer(),
                              // Bank & commission
                              if ((r['bank'] ?? '').toString().isNotEmpty || commission > 0)
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  if ((r['bank'] ?? '').toString().isNotEmpty)
                                    Text(r['bank'], style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                                  if (commission > 0)
                                    Text('RM${commission.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
                                ]),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
