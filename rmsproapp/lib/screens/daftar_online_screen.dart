import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/app_theme.dart';
import '../services/supabase_client.dart';

class DaftarOnlineScreen extends StatefulWidget {
  const DaftarOnlineScreen({super.key});

  @override
  State<DaftarOnlineScreen> createState() => _DaftarOnlineScreenState();
}

class _DaftarOnlineScreenState extends State<DaftarOnlineScreen> {
  final _sb = SupabaseService.client;
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _idError;

  final _systemIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerPhoneCtrl = TextEditingController();
  final _shopNameCtrl = TextEditingController();
  final _shopEmailCtrl = TextEditingController();
  final _shopPhoneCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _selectedNegeri = 'Selangor';

  static const _negeriList = [
    'Johor', 'Kedah', 'Kelantan', 'Melaka', 'Negeri Sembilan',
    'Pahang', 'Perak', 'Perlis', 'Pulau Pinang', 'Sabah',
    'Sarawak', 'Selangor', 'Terengganu',
    'WP Kuala Lumpur', 'WP Putrajaya', 'WP Labuan',
  ];

  static const _stateCode = {
    'Johor': 'JHR', 'Kedah': 'KDH', 'Kelantan': 'KTN', 'Melaka': 'MLK',
    'Negeri Sembilan': 'NSN', 'Pahang': 'PHG', 'Perak': 'PRK', 'Perlis': 'PLS',
    'Pulau Pinang': 'PNG', 'Sabah': 'SBH', 'Sarawak': 'SWK', 'Selangor': 'SGR',
    'Terengganu': 'TRG', 'WP Kuala Lumpur': 'KUL', 'WP Putrajaya': 'PJY', 'WP Labuan': 'LBN',
  };

  @override
  void dispose() {
    _systemIdCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _shopNameCtrl.dispose();
    _shopEmailCtrl.dispose();
    _shopPhoneCtrl.dispose();
    _districtCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
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
    ));
  }

  Future<void> _submit() async {
    setState(() => _idError = null);

    if (!_formKey.currentState!.validate()) return;

    final systemId = _systemIdCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();
    final confirmPassword = _confirmPasswordCtrl.text.trim();
    final shopEmail = _shopEmailCtrl.text.trim();

    if (!RegExp(r'^[a-z0-9]+$').hasMatch(systemId)) {
      setState(() => _idError = 'Hanya huruf kecil dan nombor sahaja');
      return;
    }

    if (password != confirmPassword) {
      _snack('Password tidak sepadan', err: true);
      return;
    }

    if (password.length < 6) {
      _snack('Password mestilah sekurang-kurangnya 6 aksara', err: true);
      return;
    }

    if (shopEmail.isEmpty) {
      _snack('Email kedai wajib diisi (untuk reset password)', err: true);
      return;
    }

    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(shopEmail)) {
      _snack('Format email tidak sah', err: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Check duplicate ownerId
      final existing = await _sb.from('tenants').select('id').eq('owner_id', systemId).maybeSingle();
      if (existing != null) {
        setState(() {
          _idError = 'System ID ini sudah wujud. Sila pilih ID lain.';
          _isSubmitting = false;
        });
        return;
      }

      final shopID = _generateShopID(_selectedNegeri);
      final ownerID = systemId;

      final defaultEnabledModules = <String, bool>{
        'widget': true, 'Stock': true, 'DB_Cust': true, 'Booking': true,
        'Claim_warranty': true, 'Collab': true, 'Profesional': true, 'Refund': true,
        'Lost': true, 'MaklumBalas': true, 'Link': true, 'Fungsi_lain': true, 'Settings': true,
      };

      // 1. Create tenants row
      final tenantRow = await _sb.from('tenants').insert({
        'owner_id': ownerID,
        'nama_kedai': _shopNameCtrl.text.trim(),
        'password_hash': password,
        'status': 'Aktif',
        'active': true,
        'config': {
          'ownerName': _ownerNameCtrl.text.trim(),
          'ownerContact': _ownerPhoneCtrl.text.trim(),
          'email': _shopEmailCtrl.text.trim(),
          'daerah': _districtCtrl.text.trim(),
          'negeri': _selectedNegeri,
          'alamat': _addressCtrl.text.trim(),
          'daftarVia': 'online',
          'enabledModules': defaultEnabledModules,
        },
      }).select('id').single();
      final tenantId = tenantRow['id'] as String;

      // 2. Create branches row (ganti shops_{ownerID})
      await _sb.from('branches').insert({
        'tenant_id': tenantId,
        'shop_code': shopID,
        'nama_kedai': _shopNameCtrl.text.trim(),
        'email': _shopEmailCtrl.text.trim(),
        'phone': _shopPhoneCtrl.text.trim(),
        'alamat': _addressCtrl.text.trim(),
        'enabled_modules': defaultEnabledModules,
        'extras': {
          'daerah': _districtCtrl.text.trim(),
          'negeri': _selectedNegeri,
        },
        'active': true,
      });

      // 3. global_branches tak perlu — discovery guna tenants + branches join

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 60, color: AppColors.green),
              const SizedBox(height: 16),
              const Text('PENDAFTARAN BERJAYA!',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(children: [
                  _infoRow('System ID', ownerID),
                  const SizedBox(height: 6),
                  _infoRow('Shop ID', shopID),
                ]),
              ),
              const SizedBox(height: 12),
              const Text('Sila log masuk menggunakan System ID dan password yang telah didaftarkan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.5)),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('LOG MASUK SEKARANG'),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('Ralat: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(children: [
      Text('$label: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      Text(value, style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 16, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('DAFTAR AKAUN BARU',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── MAKLUMAT AKAUN ───
              _sectionTitle('MAKLUMAT AKAUN', FontAwesomeIcons.key),
              const SizedBox(height: 14),

              _label('SYSTEM ID'),
              const SizedBox(height: 6),
              _input(_systemIdCtrl, 'cth: kedaiali123',
                  errorText: _idError,
                  onChanged: (_) {
                    if (_idError != null) setState(() => _idError = null);
                  }),
              const SizedBox(height: 4),
              const Text('Huruf kecil dan nombor sahaja. Tidak boleh ditukar selepas pendaftaran.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),

              _label('PASSWORD'),
              const SizedBox(height: 6),
              _input(_passwordCtrl, 'Minimum 6 aksara', obscure: true),
              const SizedBox(height: 14),

              _label('SAHKAN PASSWORD'),
              const SizedBox(height: 6),
              _input(_confirmPasswordCtrl, 'Taip semula password', obscure: true),
              const SizedBox(height: 20),

              // ─── MAKLUMAT PEMILIK ───
              _sectionTitle('MAKLUMAT PEMILIK', FontAwesomeIcons.solidUser),
              const SizedBox(height: 14),

              _label('NAMA PEMILIK'),
              const SizedBox(height: 6),
              _input(_ownerNameCtrl, 'Nama penuh pemilik'),
              const SizedBox(height: 14),

              _label('NO TELEFON PEMILIK'),
              const SizedBox(height: 6),
              _input(_ownerPhoneCtrl, '012-3456789', keyboard: TextInputType.phone),
              const SizedBox(height: 20),

              // ─── MAKLUMAT KEDAI ───
              _sectionTitle('MAKLUMAT KEDAI', FontAwesomeIcons.store),
              const SizedBox(height: 14),

              _label('NAMA KEDAI'),
              const SizedBox(height: 6),
              _input(_shopNameCtrl, 'Cth: Ali Phone Repair'),
              const SizedBox(height: 14),

              _label('EMAIL KEDAI *'),
              const SizedBox(height: 6),
              _input(_shopEmailCtrl, 'email@contoh.com', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 4),
              const Text('Wajib — digunakan untuk hantar reset password jika terlupa.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),

              _label('NO TELEFON KEDAI'),
              const SizedBox(height: 6),
              _input(_shopPhoneCtrl, '03-12345678', keyboard: TextInputType.phone),
              const SizedBox(height: 14),

              _label('DAERAH'),
              const SizedBox(height: 6),
              _input(_districtCtrl, 'Cth: Petaling Jaya'),
              const SizedBox(height: 14),

              _label('NEGERI'),
              const SizedBox(height: 6),
              _buildDropdown(
                _selectedNegeri,
                _negeriList,
                (v) => setState(() => _selectedNegeri = v ?? _selectedNegeri),
              ),
              const SizedBox(height: 14),

              _label('ALAMAT PENUH'),
              const SizedBox(height: 6),
              _input(_addressCtrl, 'No. lot, jalan, poskod, bandar...', maxLines: 3),
              const SizedBox(height: 30),

              // ─── SUBMIT ───
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    shadowColor: AppColors.primary.withValues(alpha: 0.3),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FaIcon(FontAwesomeIcons.userPlus, size: 14, color: Colors.white),
                            SizedBox(width: 10),
                            Text('DAFTAR SEKARANG',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _label(String t) => Text(t,
      style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5));

  Widget _input(TextEditingController ctrl, String hint, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String? errorText,
    ValueChanged<String>? onChanged,
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      obscureText: obscure,
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
