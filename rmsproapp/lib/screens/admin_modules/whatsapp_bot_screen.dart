import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';

const _functionsBase = 'https://us-central1-rmspro-2f454.cloudfunctions.net';

class WhatsappBotScreen extends StatefulWidget {
  const WhatsappBotScreen({super.key});
  @override
  State<WhatsappBotScreen> createState() => _WhatsappBotScreenState();
}

class _WhatsappBotScreenState extends State<WhatsappBotScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _botList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _db.collection('saas_dealers').where('botWhatsapp', isNotEqualTo: null).get();
      _botList = snap.docs.map((doc) {
        final d = doc.data();
        d['id'] = doc.id;
        return d;
      }).toList();

      _botList.sort((a, b) {
        final nameA = (a['namaKedai'] ?? '').toString().toLowerCase();
        final nameB = (b['namaKedai'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    } catch (e) {
      debugPrint('loadBots error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showAddDialog() async {
    final waController = TextEditingController();
    final phoneIdCtrl = TextEditingController();
    final accessTokenCtrl = TextEditingController();
    final wabaIdCtrl = TextEditingController();
    final verifyTokenCtrl = TextEditingController();
    final searchController = TextEditingController();
    List<Map<String, dynamic>> allDealers = [];
    List<Map<String, dynamic>> filtered = [];
    Map<String, dynamic>? selected;
    bool loading = true;

    try {
      final resp = await http.get(Uri.parse('$_functionsBase/getDealers'));
      final data = jsonDecode(resp.body) as Map?;
      final rawDealers = data?['dealers'] as List? ?? [];

      allDealers = rawDealers
          .whereType<Map>()
          .map((d) => Map<String, dynamic>.from(d))
          .toList();

      allDealers.sort((a, b) {
        final nameA = (a['namaKedai'] ?? '').toString().toLowerCase();
        final nameB = (b['namaKedai'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });

      filtered = List.from(allDealers);
      loading = false;
    } catch (e) {
      loading = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal load dealer: $e'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SETUP BOT WHATSAPP',
                      style: TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: 16),
                  if (selected == null) ...[
                    Text('Pilih kedai:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: searchController,
                      onChanged: (v) {
                        setModalState(() {
                          final q = v.toLowerCase();
                          filtered = allDealers.where((d) {
                            final dName = (d['namaKedai'] ?? '').toString().toLowerCase();
                            final dId = (d['id'] ?? '').toString().toLowerCase();
                            return dName.contains(q) || dId.contains(q);
                          }).toList();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Cari nama atau ID kedai...',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            return GestureDetector(
                              onTap: () => setModalState(() => selected = d),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(children: [
                                  const FaIcon(FontAwesomeIcons.store, size: 11, color: Color(0xFF25D366)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((d['namaKedai'] ?? '').toString(),
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                      Text((d['id'] ?? '').toString(),
                                          style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                                    ],
                                  )),
                                  const FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: AppColors.textDim),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const FaIcon(FontAwesomeIcons.store, size: 12, color: Color(0xFF25D366)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          (selected!['namaKedai'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF25D366)),
                        )),
                        GestureDetector(
                          onTap: () => setModalState(() => selected = null),
                          child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Text('No. WhatsApp kedai:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: waController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'contoh: 60123456789',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 12, right: 8),
                          child: FaIcon(FontAwesomeIcons.whatsapp, size: 16, color: Color(0xFF25D366)),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 6),
                    Text('Format: 60xxxxxxxxx (tanpa + atau -)',
                        style: TextStyle(color: AppColors.textDim, fontSize: 9)),
                    const SizedBox(height: 16),
                    // Meta API Section
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F2).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1877F2).withValues(alpha: 0.15)),
                      ),
                      child: Row(children: [
                        const FaIcon(FontAwesomeIcons.meta, size: 12, color: Color(0xFF1877F2)),
                        const SizedBox(width: 8),
                        Text('META WHATSAPP CLOUD API', style: TextStyle(color: const Color(0xFF1877F2), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _apiField('Phone Number ID', phoneIdCtrl, 'Dari Meta Business Suite > WhatsApp > API Setup'),
                    const SizedBox(height: 10),
                    _apiField('Access Token', accessTokenCtrl, 'Permanent token / System User token'),
                    const SizedBox(height: 10),
                    _apiField('WABA ID', wabaIdCtrl, 'WhatsApp Business Account ID'),
                    const SizedBox(height: 10),
                    _apiField('Verify Token', verifyTokenCtrl, 'Token untuk webhook verification (set sendiri)'),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.15)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const FaIcon(FontAwesomeIcons.circleInfo, size: 12, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Guna WhatsApp Cloud API (official dari Meta). '
                          'Free 1000 conversation/bulan. Tak kena ban.',
                          style: TextStyle(color: const Color(0xFF3B82F6).withValues(alpha: 0.8), fontSize: 10, height: 1.4),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final wa = waController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                          if (wa.isEmpty || phoneIdCtrl.text.trim().isEmpty || accessTokenCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: const Text('Sila isi No. WhatsApp, Phone Number ID & Access Token'),
                              backgroundColor: AppColors.orange,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ));
                            return;
                          }
                          Navigator.pop(ctx, {
                            'ownerID': (selected!['id'] ?? '').toString(),
                            'namaKedai': (selected!['namaKedai'] ?? '').toString(),
                            'noWhatsapp': wa,
                            'phoneNumberId': phoneIdCtrl.text.trim(),
                            'accessToken': accessTokenCtrl.text.trim(),
                            'wabaId': wabaIdCtrl.text.trim(),
                            'verifyToken': verifyTokenCtrl.text.trim(),
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text('Aktifkan Bot',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result != null && result is Map) {
        _setupBot(result);
      }
    });
  }

  Widget _apiField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 10, color: AppColors.textDim),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Future<void> _setupBot(Map result) async {
    final ownerID = (result['ownerID'] ?? '').toString();
    final namaKedai = (result['namaKedai'] ?? '').toString();
    final noWhatsapp = (result['noWhatsapp'] ?? '').toString();

    _showLoading('Mengaktifkan bot...');
    try {
      await _db.collection('saas_dealers').doc(ownerID).update({
        'botWhatsapp': {
          'noWhatsapp': noWhatsapp,
          'status': 'AKTIF',
          'createdAt': FieldValue.serverTimestamp(),
          'phoneNumberId': (result['phoneNumberId'] ?? '').toString(),
          'accessToken': (result['accessToken'] ?? '').toString(),
          'wabaId': (result['wabaId'] ?? '').toString(),
          'verifyToken': (result['verifyToken'] ?? '').toString(),
          'greeting': 'Terima kasih kerana menghubungi $namaKedai. Sila hantar nombor telefon anda untuk semak status repair.',
          'notFound': 'Maaf, tiada rekod repair dijumpai untuk nombor ini. Sila semak semula atau hubungi kedai.',
        },
      });

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bot WhatsApp untuk $namaKedai berjaya diaktifkan!'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _loadBots();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _toggleBot(Map<String, dynamic> item) async {
    final bot = item['botWhatsapp'] as Map<String, dynamic>? ?? {};
    final currentStatus = (bot['status'] ?? '').toString();
    final newStatus = currentStatus == 'AKTIF' ? 'TIDAK_AKTIF' : 'AKTIF';
    final id = (item['id'] ?? '').toString();

    try {
      await _db.collection('saas_dealers').doc(id).update({
        'botWhatsapp.status': newStatus,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bot ${newStatus == 'AKTIF' ? 'diaktifkan' : 'dinyahaktifkan'}'),
        backgroundColor: newStatus == 'AKTIF' ? AppColors.green : AppColors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _loadBots();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _deleteBot(Map<String, dynamic> item) async {
    final kedaiName = (item['namaKedai'] ?? '').toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padam Bot?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        content: Text('Bot WhatsApp untuk $kedaiName akan dipadam.',
            style: TextStyle(color: AppColors.textSub, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
            child: const Text('Padam', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
      ),
    );
    if (confirm != true) return;

    try {
      final id = (item['id'] ?? '').toString();
      await _db.collection('saas_dealers').doc(id).update({
        'botWhatsapp': FieldValue.delete(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Bot telah dipadam'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _loadBots();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal padam: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _showSettingsDialog(Map<String, dynamic> item) {
    final bot = item['botWhatsapp'] as Map<String, dynamic>? ?? {};
    final greetingCtrl = TextEditingController(text: (bot['greeting'] ?? '').toString());
    final notFoundCtrl = TextEditingController(text: (bot['notFound'] ?? '').toString());
    final noWaCtrl = TextEditingController(text: (bot['noWhatsapp'] ?? '').toString());
    final phoneIdCtrl = TextEditingController(text: (bot['phoneNumberId'] ?? '').toString());
    final accessTokenCtrl = TextEditingController(text: (bot['accessToken'] ?? '').toString());
    final wabaIdCtrl = TextEditingController(text: (bot['wabaId'] ?? '').toString());
    final verifyTokenCtrl = TextEditingController(text: (bot['verifyToken'] ?? '').toString());
    final id = (item['id'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TETAPAN BOT',
                  style: TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 16),
              Text('No. WhatsApp:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: noWaCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '60123456789',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 14),
              // Meta API Section
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1877F2).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1877F2).withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  const FaIcon(FontAwesomeIcons.meta, size: 12, color: Color(0xFF1877F2)),
                  const SizedBox(width: 8),
                  Text('META WHATSAPP CLOUD API', style: TextStyle(color: const Color(0xFF1877F2), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ]),
              ),
              const SizedBox(height: 12),
              _apiField('Phone Number ID', phoneIdCtrl, 'Dari Meta > WhatsApp > API Setup'),
              const SizedBox(height: 10),
              _apiField('Access Token', accessTokenCtrl, 'Permanent / System User token'),
              const SizedBox(height: 10),
              _apiField('WABA ID', wabaIdCtrl, 'WhatsApp Business Account ID'),
              const SizedBox(height: 10),
              _apiField('Verify Token', verifyTokenCtrl, 'Token untuk webhook verification'),
              const SizedBox(height: 16),
              // Mesej Section
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  const FaIcon(FontAwesomeIcons.commentDots, size: 12, color: Color(0xFF25D366)),
                  const SizedBox(width: 8),
                  Text('MESEJ BOT', style: TextStyle(color: const Color(0xFF25D366), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ]),
              ),
              const SizedBox(height: 12),
              Text('Mesej Greeting:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: greetingCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Mesej pertama bot hantar...',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                  contentPadding: const EdgeInsets.all(12),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Text('Mesej Tidak Dijumpai:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: notFoundCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Mesej bila tiada rekod...',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                  contentPadding: const EdgeInsets.all(12),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await _db.collection('saas_dealers').doc(id).update({
                        'botWhatsapp.noWhatsapp': noWaCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), ''),
                        'botWhatsapp.phoneNumberId': phoneIdCtrl.text.trim(),
                        'botWhatsapp.accessToken': accessTokenCtrl.text.trim(),
                        'botWhatsapp.wabaId': wabaIdCtrl.text.trim(),
                        'botWhatsapp.verifyToken': verifyTokenCtrl.text.trim(),
                        'botWhatsapp.greeting': greetingCtrl.text.trim(),
                        'botWhatsapp.notFound': notFoundCtrl.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Tetapan bot dikemaskini!'),
                        backgroundColor: AppColors.green,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ));
                      _loadBots();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Gagal: $e'),
                        backgroundColor: AppColors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Simpan Tetapan',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Text(msg, style: const TextStyle(fontSize: 12)),
        ]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF25D366).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const FaIcon(FontAwesomeIcons.whatsapp, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bot WhatsApp',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  Text('${_botList.length} bot aktif',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
                ],
              )),
              GestureDetector(
                onTap: _showAddDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    FaIcon(FontAwesomeIcons.plus, size: 11, color: Color(0xFF25D366)),
                    SizedBox(width: 6),
                    Text('Tambah', style: TextStyle(color: Color(0xFF25D366), fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 12),
          // Info card - flow explanation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CARA BOT BERFUNGSI', style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                _flowStep('1', 'Customer WhatsApp ke nombor kedai'),
                _flowStep('2', 'Bot auto reply greeting & minta no telefon'),
                _flowStep('3', 'Bot cari rekod repair berdasarkan no telefon / no backup'),
                _flowStep('4', 'Bot reply status repair secara automatik'),
              ],
            ),
          ),

          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_botList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  FaIcon(FontAwesomeIcons.whatsapp, size: 30, color: AppColors.textDim.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('Belum ada bot', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Tekan "Tambah" untuk setup bot', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                ]),
              ),
            )
          else
            ..._botList.map((item) => _buildBotCard(item)),
        ],
      ),
    );
  }

  Widget _flowStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF25D366),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: AppColors.textSub, fontSize: 10, height: 1.3))),
      ]),
    );
  }

  Widget _buildBotCard(Map<String, dynamic> item) {
    final bot = item['botWhatsapp'] as Map<String, dynamic>? ?? {};
    final noWa = (bot['noWhatsapp'] ?? '').toString();
    final status = (bot['status'] ?? '').toString();
    final isActive = status == 'AKTIF';
    final kedai = (item['namaKedai'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFF25D366).withValues(alpha: 0.3)
              : AppColors.orange.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kedai, style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Row(children: [
                  const FaIcon(FontAwesomeIcons.whatsapp, size: 10, color: Color(0xFF25D366)),
                  const SizedBox(width: 4),
                  Text(noWa, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF25D366), fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: (bot['phoneNumberId'] ?? '').toString().isNotEmpty
                          ? const Color(0xFF1877F2).withValues(alpha: 0.1)
                          : AppColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (bot['phoneNumberId'] ?? '').toString().isNotEmpty ? 'API OK' : 'API -',
                      style: TextStyle(
                        color: (bot['phoneNumberId'] ?? '').toString().isNotEmpty
                            ? const Color(0xFF1877F2)
                            : AppColors.red,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ]),
              ],
            )),
            GestureDetector(
              onTap: () => _toggleBot(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF25D366).withValues(alpha: 0.1) : AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isActive ? 'Aktif' : 'Tidak Aktif',
                  style: TextStyle(
                    color: isActive ? const Color(0xFF25D366) : AppColors.orange,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _actionBtn(FontAwesomeIcons.gear, 'Tetapan', const Color(0xFF3B82F6), () => _showSettingsDialog(item))),
            const SizedBox(width: 8),
            Expanded(child: _actionBtn(FontAwesomeIcons.trash, 'Padam', AppColors.red, () => _deleteBot(item))),
          ]),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
