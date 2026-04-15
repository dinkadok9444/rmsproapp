import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/supabase_client.dart';

class DaftarManualScreen extends StatefulWidget {
  const DaftarManualScreen({super.key});

  @override
  State<DaftarManualScreen> createState() => _DaftarManualScreenState();
}

class _DaftarManualScreenState extends State<DaftarManualScreen> {
  final _sb = SupabaseService.client;
  List<Map<String, dynamic>> _dealers = [];
  bool _isLoading = true;

  static const _negeriList = [
    'Johor', 'Kedah', 'Kelantan', 'Melaka', 'Negeri Sembilan',
    'Pahang', 'Perak', 'Perlis', 'Pulau Pinang', 'Sabah',
    'Sarawak', 'Selangor', 'Terengganu',
    'WP Kuala Lumpur', 'WP Putrajaya', 'WP Labuan',
  ];

  static const _durationList = ['1 bulan', '6 bulan', '12 bulan'];

  static const _durationMonths = {
    '1 bulan': 1,
    '6 bulan': 6,
    '12 bulan': 12,
  };

  static const _stateCode = {
    'Johor': 'JHR', 'Kedah': 'KDH', 'Kelantan': 'KTN',
    'Melaka': 'MLK', 'Negeri Sembilan': 'NSN', 'Pahang': 'PHG',
    'Perak': 'PRK', 'Perlis': 'PLS', 'Pulau Pinang': 'PNG',
    'Sabah': 'SBH', 'Sarawak': 'SWK', 'Selangor': 'SGR',
    'Terengganu': 'TRG', 'WP Kuala Lumpur': 'KUL',
    'WP Putrajaya': 'PJY', 'WP Labuan': 'LBN',
  };

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    setState(() => _isLoading = true);
    try {
      final rows = await _sb
          .from('tenants')
          .select()
          .order('created_at', ascending: false)
          .limit(500);
      _dealers = rows.map<Map<String, dynamic>>((r) {
        final config = (r['config'] is Map) ? Map<String, dynamic>.from(r['config']) : <String, dynamic>{};
        return {
          'id': r['id'],
          'ownerID': r['owner_id'],
          'namaKedai': r['nama_kedai'] ?? '',
          'ownerName': config['ownerName'] ?? '',
          'phone': config['ownerContact'] ?? '',
          'negeri': config['negeri'] ?? '',
          'status': r['status'] ?? 'Aktif',
        };
      }).toList();

      _dealers.sort((a, b) {
        final nameA = (a['namaKedai'] ?? '').toString().toLowerCase();
        final nameB = (b['namaKedai'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    } catch (e) {
      debugPrint('loadDealers error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _generateShopID(String negeri) {
    final code = _stateCode[negeri] ?? 'XXX';
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    final suffix = List.generate(5, (_) => chars[rand.nextInt(chars.length)]).join();
    return '$code-$suffix';
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _showAddDialog() async {
    final formKey = GlobalKey<FormState>();
    final systemIdCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final ownerNameCtrl = TextEditingController();
    final ownerPhoneCtrl = TextEditingController();
    final shopNameCtrl = TextEditingController();
    final shopEmailCtrl = TextEditingController();
    final shopPhoneCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String selectedNegeri = 'Selangor';
    String selectedDuration = '1 bulan';
    String? idError;
    bool isSubmitting = false;

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
            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                return SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.only(
                    left: 20, right: 20, top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Handle bar
                        Center(
                          child: Container(
                            width: 40, height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const Text('DAFTAR DEALER BARU',
                            style: TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(height: 20),

                        // ─── MAKLUMAT AKAUN ───
                        _sectionTitle('MAKLUMAT AKAUN', FontAwesomeIcons.key),
                        const SizedBox(height: 14),
                        _label('SYSTEM ID'),
                        const SizedBox(height: 6),
                        _input(systemIdCtrl, 'cth: kedaiali123',
                            errorText: idError,
                            onChanged: (_) {
                              if (idError != null) setModalState(() => idError = null);
                            }),
                        const SizedBox(height: 4),
                        const Text('Huruf kecil dan nombor sahaja. Tidak boleh ditukar selepas pendaftaran.',
                            style: TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 14),
                        _label('PASSWORD'),
                        const SizedBox(height: 6),
                        _input(passwordCtrl, 'Kata laluan dealer'),
                        const SizedBox(height: 20),

                        // ─── MAKLUMAT PEMILIK ───
                        _sectionTitle('MAKLUMAT PEMILIK', FontAwesomeIcons.solidUser),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('NAMA PEMILIK'),
                              const SizedBox(height: 6),
                              _input(ownerNameCtrl, 'Nama penuh pemilik'),
                            ],
                          )),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('NO TELEFON PEMILIK'),
                              const SizedBox(height: 6),
                              _input(ownerPhoneCtrl, '012-3456789', keyboard: TextInputType.phone),
                            ],
                          )),
                        ]),
                        const SizedBox(height: 20),

                        // ─── MAKLUMAT KEDAI ───
                        _sectionTitle('MAKLUMAT KEDAI', FontAwesomeIcons.store),
                        const SizedBox(height: 14),
                        _label('NAMA KEDAI'),
                        const SizedBox(height: 6),
                        _input(shopNameCtrl, 'Cth: Ali Phone Repair'),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('EMAIL KEDAI'),
                              const SizedBox(height: 6),
                              _input(shopEmailCtrl, 'email@contoh.com', keyboard: TextInputType.emailAddress),
                            ],
                          )),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('NO TELEFON KEDAI'),
                              const SizedBox(height: 6),
                              _input(shopPhoneCtrl, '03-12345678', keyboard: TextInputType.phone),
                            ],
                          )),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('DAERAH'),
                              const SizedBox(height: 6),
                              _input(districtCtrl, 'Cth: Petaling Jaya'),
                            ],
                          )),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('NEGERI'),
                              const SizedBox(height: 6),
                              _buildDropdown(selectedNegeri, _negeriList, (v) {
                                setModalState(() => selectedNegeri = v ?? selectedNegeri);
                              }),
                            ],
                          )),
                        ]),
                        const SizedBox(height: 14),
                        _label('ALAMAT PENUH'),
                        const SizedBox(height: 6),
                        _input(addressCtrl, 'No. lot, jalan, poskod, bandar...', maxLines: 3),
                        const SizedBox(height: 20),

                        // ─── LANGGANAN ───
                        _sectionTitle('LANGGANAN', FontAwesomeIcons.calendarCheck),
                        const SizedBox(height: 14),
                        _label('TEMPOH LANGGANAN'),
                        const SizedBox(height: 6),
                        _buildDropdown(selectedDuration, _durationList, (v) {
                          setModalState(() => selectedDuration = v ?? selectedDuration);
                        }),
                        const SizedBox(height: 30),

                        // ─── SUBMIT ───
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              // Validate
                              final systemId = systemIdCtrl.text.trim().toLowerCase();
                              if (systemId.isEmpty || passwordCtrl.text.trim().isEmpty ||
                                  ownerNameCtrl.text.trim().isEmpty || shopNameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content: const Text('Sila isi semua maklumat wajib'),
                                  backgroundColor: AppColors.orange,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ));
                                return;
                              }
                              if (!RegExp(r'^[a-z0-9]+$').hasMatch(systemId)) {
                                setModalState(() => idError = 'Hanya huruf kecil dan nombor sahaja');
                                return;
                              }

                              setModalState(() => isSubmitting = true);

                              try {
                                final existing = await _sb.from('tenants').select('id').eq('owner_id', systemId).maybeSingle();
                                if (existing != null) {
                                  setModalState(() {
                                    idError = 'System ID ini sudah wujud';
                                    isSubmitting = false;
                                  });
                                  return;
                                }

                                final months = _durationMonths[selectedDuration] ?? 1;
                                final expiryDate = DateTime.now().add(Duration(days: months * 30));
                                final shopID = _generateShopID(selectedNegeri);
                                final ownerID = systemId;

                                final defaultEnabledModules = <String, bool>{
                                  'widget': true, 'Stock': true, 'DB_Cust': true, 'Booking': true,
                                  'Claim_warranty': true, 'Collab': true, 'Profesional': true, 'Refund': true,
                                  'Lost': true, 'MaklumBalas': true, 'Link': true, 'Fungsi_lain': true, 'Settings': true,
                                };

                                // 1. Create tenants row
                                final t = await _sb.from('tenants').insert({
                                  'owner_id': ownerID,
                                  'nama_kedai': shopNameCtrl.text.trim(),
                                  'password_hash': passwordCtrl.text.trim(),
                                  'status': 'Aktif',
                                  'active': true,
                                  'expire_date': expiryDate.toIso8601String(),
                                  'config': {
                                    'enabledModules': defaultEnabledModules,
                                    'ownerName': ownerNameCtrl.text.trim(),
                                    'ownerContact': ownerPhoneCtrl.text.trim(),
                                    'email': shopEmailCtrl.text.trim(),
                                    'daerah': districtCtrl.text.trim(),
                                    'negeri': selectedNegeri,
                                    'alamat': addressCtrl.text.trim(),
                                    'duration': selectedDuration,
                                  },
                                }).select('id').single();
                                final tenantId = t['id'] as String;

                                // 2. Create branches row
                                await _sb.from('branches').insert({
                                  'tenant_id': tenantId,
                                  'shop_code': shopID,
                                  'nama_kedai': shopNameCtrl.text.trim(),
                                  'email': shopEmailCtrl.text.trim(),
                                  'phone': shopPhoneCtrl.text.trim(),
                                  'alamat': addressCtrl.text.trim(),
                                  'enabled_modules': defaultEnabledModules,
                                  'extras': {
                                    'daerah': districtCtrl.text.trim(),
                                    'negeri': selectedNegeri,
                                  },
                                  'active': true,
                                });

                                if (!ctx.mounted) return;
                                Navigator.pop(ctx, true);
                                _snack('Pendaftaran berjaya! ID: $ownerID / Shop: $shopID');
                              } catch (e) {
                                setModalState(() => isSubmitting = false);
                                _snack('Ralat: $e', err: true);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                              shadowColor: AppColors.primary.withValues(alpha: 0.3),
                            ),
                            child: isSubmitting
                                ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FaIcon(FontAwesomeIcons.floppyDisk, size: 14, color: Colors.white),
                                      SizedBox(width: 10),
                                      Text('DAFTAR DEALER',
                                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ).then((result) {
      if (result == true) _loadDealers();
    });
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
                colors: [AppColors.primary, AppColors.blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
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
                child: const FaIcon(FontAwesomeIcons.userPlus, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Daftar Dealer',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  Text('${_dealers.length} dealer berdaftar',
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
                    FaIcon(FontAwesomeIcons.plus, size: 11, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Tambah', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // List
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_dealers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  FaIcon(FontAwesomeIcons.userPlus, size: 30, color: AppColors.textDim.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('Belum ada dealer', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Tekan "Tambah" untuk daftar dealer baru', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                ]),
              ),
            )
          else
            ..._dealers.map((d) => _buildDealerCard(d)),
        ],
      ),
    );
  }

  Widget _buildDealerCard(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString();
    final isActive = status == 'Aktif';
    final expiryRaw = item['expiry'];
    DateTime? expiry;
    if (expiryRaw is String && expiryRaw.isNotEmpty) expiry = DateTime.tryParse(expiryRaw);
    final expiryStr = expiry != null
        ? '${expiry.day}/${expiry.month}/${expiry.year}'
        : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.green.withValues(alpha: 0.3)
              : AppColors.red.withValues(alpha: 0.3),
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
                Text((item['namaKedai'] ?? '').toString(),
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text((item['id'] ?? '').toString(),
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.primary, fontWeight: FontWeight.w600)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? AppColors.green.withValues(alpha: 0.1) : AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isActive ? 'Aktif' : 'Tidak Aktif',
                style: TextStyle(
                  color: isActive ? AppColors.green : AppColors.red,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            FaIcon(FontAwesomeIcons.solidUser, size: 9, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text((item['ownerName'] ?? '').toString(), style: TextStyle(fontSize: 10, color: AppColors.textSub)),
            const SizedBox(width: 14),
            FaIcon(FontAwesomeIcons.phone, size: 9, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text((item['ownerContact'] ?? '').toString(), style: TextStyle(fontSize: 10, color: AppColors.textSub)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            FaIcon(FontAwesomeIcons.locationDot, size: 9, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text('${item['daerah'] ?? ''}, ${item['negeri'] ?? ''}',
                style: TextStyle(fontSize: 10, color: AppColors.textSub)),
            const Spacer(),
            FaIcon(FontAwesomeIcons.calendarCheck, size: 9, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text('Tamat: $expiryStr', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ]),
        ],
      ),
    );
  }

  // ─── SECTION TITLE ───
  Widget _sectionTitle(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        FaIcon(icon, size: 12, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(
            color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
      ]),
    );
  }

  // ─── HELPERS ───
  Widget _label(String t) => Text(t,
      style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5));

  Widget _input(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text,
      int maxLines = 1,
      String? errorText,
      ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        errorText: errorText,
        filled: true,
        fillColor: AppColors.bgDeep,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.red)),
      ),
    );
  }

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
