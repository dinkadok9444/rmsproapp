import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../services/printer_service.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  String _ownerID = 'admin', _shopID = 'MAIN';
  Map<String, dynamic> _settings = {};
  bool _isLoading = true;
  bool _singleStaffMode = false;

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notaInvCtrl = TextEditingController();
  final _notaQuoCtrl = TextEditingController();
  final _notaClaimCtrl = TextEditingController();
  final _notaBookingCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();
  final _adminTelCtrl = TextEditingController();

  String _selectedTemplate = 'tpl_1';
  String _staffBoxCount = '1';
  String? _logoBase64;
  bool _adminPassLocked = false;

  // Printer settings
  String _printerName80mm = '';
  String _printerNameNormal = '';
  String _printerNameLabel = '';
  String _labelWidth = '50';
  String _labelHeight = '30';
  String _labelLang = 'escpos'; // 'escpos' | 'tspl'
  bool _labelSizeSaved = false;

  // Header color
  String _selectedHeaderColor = '';

  // Booking payment QR & bank
  String _bookingQrImageUrl = '';
  final _bookingBankNameCtrl = TextEditingController();
  final _bookingBankAccCtrl = TextEditingController();

  // Language
  final _lang = AppLanguage();
  String _selectedLanguage = 'ms';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notaInvCtrl.dispose();
    _notaQuoCtrl.dispose();
    _notaClaimCtrl.dispose();
    _notaBookingCtrl.dispose();
    _adminPassCtrl.dispose();
    _adminTelCtrl.dispose();
    _bookingBankNameCtrl.dispose();
    _bookingBankAccCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;

    final prefs = await SharedPreferences.getInstance();

    // Load language
    await _lang.init();
    _selectedLanguage = _lang.lang;

    // Load printer names from local
    _printerName80mm = prefs.getString('printer_80mm_name') ?? '';
    _printerNameNormal = prefs.getString('printer_normal_name') ?? '';
    _printerNameLabel = prefs.getString('printer_label_name') ?? '';
    _labelWidth = prefs.getString('printer_label_width') ?? '50';
    _labelHeight = prefs.getString('printer_label_height') ?? '30';
    _labelLang = prefs.getString('printer_label_lang') ?? 'escpos';
    _labelSizeSaved = prefs.getString('printer_label_width') != null;

    // Load tenant data
    Map<String, dynamic> adminData = {};
    try {
      if (_tenantId != null) {
        final row = await _sb.from('tenants').select().eq('id', _tenantId!).maybeSingle();
        if (row != null) {
          final config = (row['config'] is Map) ? Map<String, dynamic>.from(row['config']) : <String, dynamic>{};
          adminData = {
            ...config,
            'namaKedai': row['nama_kedai'] ?? '',
            'ownerName': config['ownerName'] ?? row['nama_kedai'] ?? '',
            'email': config['email'] ?? '',
            'pass': row['password_hash'] ?? '',
          };
        }
      }
    } catch (_) {}

    // Load branch row + extras
    Map<String, dynamic>? branchRow;
    if (_branchId != null) {
      try {
        branchRow = await _sb.from('branches').select().eq('id', _branchId!).maybeSingle();
      } catch (_) {}
    }
    if (branchRow != null && mounted) {
      final extras = (branchRow['extras'] is Map) ? Map<String, dynamic>.from(branchRow['extras']) : <String, dynamic>{};
      final d = {
        ...adminData,
        ...extras,
        'phone': branchRow['phone'] ?? extras['phone'] ?? '',
        'email': branchRow['email'] ?? extras['email'] ?? adminData['email'] ?? '',
        'logoBase64': branchRow['logo_base64'] ?? extras['logoBase64'],
        'singleStaffMode': branchRow['single_staff_mode'] == true,
      };
      setState(() {
        _settings = d;
        _singleStaffMode = d['singleStaffMode'] == true;
        _phoneCtrl.text = d['phone'] ?? d['ownerContact'] ?? '';
        _emailCtrl.text = d['email'] ?? '';
        _notaInvCtrl.text =
            d['notaInvoice'] ??
            'Barang yang tidak dituntut selepas 30 hari adalah tanggungjawab pelanggan.';
        _notaQuoCtrl.text =
            d['notaQuotation'] ??
            'Sebut harga ini sah untuk tempoh 7 hari dari tarikh dikeluarkan.';
        _notaClaimCtrl.text =
            d['notaClaim'] ??
            'Waranti terbatal sekiranya terdapat kerosakan fizikal, cecair atau kecuaian pengguna.';
        _notaBookingCtrl.text =
            d['notaBooking'] ??
            'Wang pendahuluan (deposit) tidak akan dikembalikan sekiranya pembatalan dibuat oleh pelanggan.';
        _selectedTemplate = d['templatePdf'] ?? 'tpl_1';
        _staffBoxCount = (d['staffBoxCount'] ?? '1').toString();
        _logoBase64 = d['logoBase64'];
        if (d['svPass'] != null && d['svPass'].toString().isNotEmpty) {
          _adminPassCtrl.text = d['svPass'];
          _adminPassLocked = true;
        }
        _adminTelCtrl.text = d['svTel'] ?? '';
        _selectedHeaderColor = d['themeColor'] ?? '';
        _bookingQrImageUrl = d['bookingQrImageUrl'] ?? '';
        _bookingBankNameCtrl.text = d['bookingBankAccName'] ?? '';
        _bookingBankAccCtrl.text = d['bookingBankAccount'] ?? '';
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _settings = adminData;
        _isLoading = false;
      });
    }
  }

  // Merge-update helper: read branches.extras, merge fields, write back.
  // Column-level fields (phone, email, logo_base64, single_staff_mode) passed separately.
  Future<void> _saveBranchSettings({
    Map<String, dynamic>? columns,
    Map<String, dynamic>? extrasPatch,
  }) async {
    if (_branchId == null) return;
    final row = await _sb.from('branches').select('extras').eq('id', _branchId!).maybeSingle();
    final extras = (row?['extras'] is Map) ? Map<String, dynamic>.from(row!['extras']) : <String, dynamic>{};
    if (extrasPatch != null) extras.addAll(extrasPatch);
    final patch = <String, dynamic>{'extras': extras};
    if (columns != null) patch.addAll(columns);
    await _sb.from('branches').update(patch).eq('id', _branchId!);
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

  // ═══════════════════════════════════════
  // SAVE SETTINGS
  // ═══════════════════════════════════════
  Future<void> _saveSettings() async {
    final extrasPatch = <String, dynamic>{
      'staffBoxCount': _staffBoxCount,
      'templatePdf': _selectedTemplate,
      'notaInvoice': _notaInvCtrl.text,
      'notaQuotation': _notaQuoCtrl.text,
      'notaClaim': _notaClaimCtrl.text,
      'notaBooking': _notaBookingCtrl.text,
      'bookingQrImageUrl': _bookingQrImageUrl,
      'bookingBankAccName': _bookingBankNameCtrl.text.trim(),
      'bookingBankAccount': _bookingBankAccCtrl.text.trim(),
    };
    if (_selectedHeaderColor.isNotEmpty) extrasPatch['themeColor'] = _selectedHeaderColor;
    final columns = <String, dynamic>{
      'phone': _phoneCtrl.text.trim(),
      if (_logoBase64 != null) 'logo_base64': _logoBase64,
    };
    await _saveBranchSettings(columns: columns, extrasPatch: extrasPatch);
    _snack(_lang.get('settings_tetapan_disimpan'));
  }

  // ═══════════════════════════════════════
  // LOGO UPLOAD
  // ═══════════════════════════════════════
  Future<void> _uploadLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 60,
    );
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    if (bytes.length > 200 * 1024) {
      _snack(_lang.get('settings_logo_melebihi'), err: true);
      return;
    }
    setState(
      () => _logoBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}',
    );
    _snack(_lang.get('settings_logo_berjaya'));
  }

  // ═══════════════════════════════════════
  // ADMIN PASSWORD
  // ═══════════════════════════════════════
  Future<void> _saveAdminPass() async {
    final pass = _adminPassCtrl.text.trim();
    final tel = _adminTelCtrl.text.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (tel.isEmpty) {
      _snack(_lang.get('settings_sila_isi_tel_admin'), err: true);
      return;
    }
    if (pass.isEmpty || pass.length < 4) {
      _snack(_lang.get('settings_pass_min_4'), err: true);
      return;
    }

    // Check if phone already used by another branch
    try {
      final existing = await _sb.from('global_staff').select().eq('tel', tel).maybeSingle();
      if (existing != null) {
        final existOwner = (existing['owner_id'] ?? '').toString();
        final existShop = (existing['shop_id'] ?? '').toString();
        if (existOwner.isNotEmpty &&
            existShop.isNotEmpty &&
            (existOwner != _ownerID || existShop != _shopID)) {
          _snack(
            '${_lang.get('settings_tel_digunakan')} ($existShop)',
            err: true,
          );
          return;
        }
      }
    } catch (_) {}

    // Remove old admin phone from global_staff if changed
    final oldTel = (_settings['svTel'] ?? '').toString().replaceAll(
      RegExp(r'[\s\-()]'),
      '',
    );
    if (oldTel.isNotEmpty && oldTel != tel) {
      try {
        await _sb.from('global_staff').delete().eq('tel', oldTel);
      } catch (_) {}
    }

    await _saveBranchSettings(extrasPatch: {'svPass': pass, 'svTel': tel});
    await _sb.from('global_staff').upsert({
      'tel': tel,
      'tenant_id': _tenantId,
      'branch_id': _branchId,
      'owner_id': _ownerID,
      'shop_id': _shopID,
      'nama': 'ADMIN',
      'role': 'supervisor',
      'payload': {'pin': pass, 'status': 'active'},
    });
    setState(() {
      _adminPassLocked = true;
      _settings['svPass'] = pass;
      _settings['svTel'] = tel;
    });
    _snack(_lang.get('settings_admin_disimpan'));
  }

  void _editAdminPass() {
    _showPassDialog(_lang.get('settings_kemaskini_admin'), (input) {
      if (input == _adminPassCtrl.text) {
        setState(() => _adminPassLocked = false);
        _snack(_lang.get('settings_sila_kemaskini'));
      } else {
        _snack(_lang.get('settings_kata_laluan_salah'), err: true);
      }
    });
  }

  // ═══════════════════════════════════════
  // RESET PASSWORD AKAUN (SISTEM LOGIN)
  // Flow:
  //   1. Masukkan password lama
  //   2. Masukkan password baru + repeat
  //   3. Atau klik "Lupa password lama?" untuk jana password random
  //   4. Password baru di-hantar ke emel akaun
  // ═══════════════════════════════════════
  String _generateRandomPass() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = DateTime.now().millisecondsSinceEpoch;
    return List.generate(8, (i) => chars[(rand + i * 7) % chars.length]).join();
  }

  Future<void> _applyNewPassword(
    String newPass, {
    required bool sendEmail,
  }) async {
    if (_tenantId == null) {
      if (mounted) _snack('Tenant belum resolved', err: true);
      return;
    }
    final row = await _sb.from('tenants').select().eq('id', _tenantId!).maybeSingle();
    if (row == null) {
      if (mounted) _snack('System ID tidak dijumpai', err: true);
      return;
    }

    await _sb.from('tenants').update({'password_hash': newPass}).eq('id', _tenantId!);

    if (!sendEmail) {
      if (mounted) _snack('Password berjaya ditukar');
      return;
    }

    final config = (row['config'] is Map) ? Map<String, dynamic>.from(row['config']) : <String, dynamic>{};
    final dealerEmail = ((config['email'] ??
                config['emel'] ??
                config['ownerEmail'] ??
                '')
            .toString())
        .trim();
    final dealerName = (config['ownerName'] ??
            row['nama_kedai'] ??
            _ownerID)
        .toString();

    if (dealerEmail.isNotEmpty && dealerEmail.contains('@')) {
      await _sb.from('mail_queue').insert({
        'recipient': dealerEmail,
        'subject': 'RMS Pro - Password Baru Anda',
        'html': '''
<div style="font-family:Arial,sans-serif;max-width:500px;margin:0 auto;padding:20px;">
  <h2 style="color:#00C853;text-align:center;">RMS PRO</h2>
  <hr/>
  <p>Salam <b>$dealerName</b>,</p>
  <p>Password akaun anda telah ditetapkan semula. Berikut adalah maklumat log masuk baru anda:</p>
  <div style="background:#f5f5f5;padding:16px;border-radius:8px;text-align:center;margin:16px 0;">
    <p style="margin:4px 0;font-size:13px;color:#666;">System ID</p>
    <p style="margin:4px 0;font-size:18px;font-weight:bold;">$_ownerID</p>
    <br/>
    <p style="margin:4px 0;font-size:13px;color:#666;">Password Baru</p>
    <p style="margin:4px 0;font-size:24px;font-weight:bold;color:#00C853;letter-spacing:2px;">$newPass</p>
  </div>
  <p style="font-size:12px;color:#999;">Sila tukar password anda selepas log masuk di bahagian Settings.</p>
  <hr/>
  <p style="font-size:11px;color:#bbb;text-align:center;">&copy; RMS Pro - Repair Management System</p>
</div>
''',
      });
    }

    if (!mounted) return;
    _snack(
      dealerEmail.isNotEmpty
          ? 'Password baru telah dihantar ke $dealerEmail'
          : 'Password berjaya ditukar. Tiada emel pada akaun.',
    );
  }

  Future<void> _applyAdminPassword(
    String newPass, {
    required bool sendEmail,
  }) async {
    final svTel = (_settings['svTel'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[\s\-()]'), '');

    await _saveBranchSettings(extrasPatch: {'svPass': newPass});

    if (svTel.isNotEmpty) {
      try {
        final existing = await _sb.from('global_staff').select('payload').eq('tel', svTel).maybeSingle();
        final payload = (existing?['payload'] is Map) ? Map<String, dynamic>.from(existing!['payload']) : <String, dynamic>{};
        payload['pin'] = newPass;
        await _sb.from('global_staff').update({'payload': payload}).eq('tel', svTel);
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _settings['svPass'] = newPass;
        _adminPassCtrl.text = newPass;
        _adminPassLocked = true;
      });
    }

    if (!sendEmail) {
      if (mounted) _snack('Password admin berjaya ditukar');
      return;
    }

    if (_tenantId == null) return;
    final tRow = await _sb.from('tenants').select().eq('id', _tenantId!).maybeSingle();
    final config = (tRow?['config'] is Map) ? Map<String, dynamic>.from(tRow!['config']) : <String, dynamic>{};
    final dealerEmail = ((config['email'] ??
                config['emel'] ??
                config['ownerEmail'] ??
                '')
            .toString())
        .trim();
    final dealerName = (config['ownerName'] ??
            tRow?['nama_kedai'] ??
            _ownerID)
        .toString();

    if (dealerEmail.isNotEmpty && dealerEmail.contains('@')) {
      await _sb.from('mail_queue').insert({
        'recipient': dealerEmail,
        'subject': 'RMS Pro - Password Admin Sementara',
        'html': '''
<div style="font-family:Arial,sans-serif;max-width:500px;margin:0 auto;padding:20px;">
  <h2 style="color:#FFA000;text-align:center;">RMS PRO - ADMIN</h2>
  <hr/>
  <p>Salam <b>$dealerName</b>,</p>
  <p>Password admin (supervisor) telah ditetapkan semula. Berikut adalah password sementara:</p>
  <div style="background:#fff8e1;padding:16px;border-radius:8px;text-align:center;margin:16px 0;border:1px solid #FFA000;">
    <p style="margin:4px 0;font-size:13px;color:#666;">Cawangan</p>
    <p style="margin:4px 0;font-size:16px;font-weight:bold;">$_shopID</p>
    <br/>
    <p style="margin:4px 0;font-size:13px;color:#666;">Password Admin Sementara</p>
    <p style="margin:4px 0;font-size:24px;font-weight:bold;color:#FFA000;letter-spacing:2px;">$newPass</p>
  </div>
  <p style="font-size:12px;color:#999;">Sila tukar password admin di Settings &rarr; Keselamatan Admin selepas log masuk.</p>
  <hr/>
  <p style="font-size:11px;color:#bbb;text-align:center;">&copy; RMS Pro - Repair Management System</p>
</div>
''',
      });
    }

    if (!mounted) return;
    _snack(
      dealerEmail.isNotEmpty
          ? 'Password admin sementara dihantar ke $dealerEmail'
          : 'Password admin berjaya ditukar. Tiada emel pada akaun.',
    );
  }

  Future<void> _resetAccountPassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final repeatCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        bool isLoading = false;
        String? error;
        bool obscureOld = true;
        bool obscureNew = true;
        bool obscureRepeat = true;
        bool isAdminMode = false;

        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Column(
              children: [
                Icon(
                  isAdminMode ? Icons.shield_outlined : Icons.lock_reset,
                  size: 40,
                  color: isAdminMode ? AppColors.orange : AppColors.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  isAdminMode
                      ? 'TUKAR PASSWORD ADMIN'
                      : 'TUKAR PASSWORD AKAUN',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: isLoading
                                ? null
                                : () {
                                    oldCtrl.clear();
                                    newCtrl.clear();
                                    repeatCtrl.clear();
                                    setD(() {
                                      isAdminMode = false;
                                      error = null;
                                    });
                                  },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isAdminMode
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'MAIN',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: !isAdminMode
                                      ? Colors.black
                                      : AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: isLoading
                                ? null
                                : () {
                                    oldCtrl.clear();
                                    newCtrl.clear();
                                    repeatCtrl.clear();
                                    setD(() {
                                      isAdminMode = true;
                                      error = null;
                                    });
                                  },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isAdminMode
                                    ? AppColors.orange
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ADMIN',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isAdminMode
                                      ? Colors.black
                                      : AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isAdminMode
                        ? 'Cawangan: $_shopID'
                        : 'System ID: $_ownerID',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: oldCtrl,
                    obscureText: obscureOld,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: _inputDeco('Password lama').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureOld
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () =>
                            setD(() => obscureOld = !obscureOld),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newCtrl,
                    obscureText: obscureNew,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: _inputDeco('Password baru').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () =>
                            setD(() => obscureNew = !obscureNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: repeatCtrl,
                    obscureText: obscureRepeat,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: _inputDeco('Ulang password baru').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureRepeat
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () =>
                            setD(() => obscureRepeat = !obscureRepeat),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: isLoading
                          ? null
                          : () async {
                              setD(() {
                                isLoading = true;
                                error = null;
                              });
                              try {
                                final newPass = _generateRandomPass();
                                if (isAdminMode) {
                                  await _applyAdminPassword(newPass, sendEmail: true);
                                } else {
                                  await _applyNewPassword(newPass, sendEmail: true);
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                setD(() {
                                  isLoading = false;
                                  error = 'Ralat: $e';
                                });
                              }
                            },
                      child: const Text(
                        'Lupa password lama?',
                        style: TextStyle(
                          color: AppColors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text(
                  'BATAL',
                  style: TextStyle(color: AppColors.red),
                ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final oldPass = oldCtrl.text.trim();
                        final newPass = newCtrl.text.trim();
                        final repeatPass = repeatCtrl.text.trim();

                        if (oldPass.isEmpty ||
                            newPass.isEmpty ||
                            repeatPass.isEmpty) {
                          setD(() => error = 'Sila isi semua ruangan');
                          return;
                        }
                        if (newPass != repeatPass) {
                          setD(() => error = 'Password baru tidak sepadan');
                          return;
                        }
                        if (newPass.length < 6) {
                          setD(() => error =
                              'Password baru mesti 6 aksara atau lebih');
                          return;
                        }
                        if (newPass == oldPass) {
                          setD(() => error =
                              'Password baru sama dengan password lama');
                          return;
                        }

                        setD(() {
                          isLoading = true;
                          error = null;
                        });

                        try {
                          String currentPass;
                          if (isAdminMode) {
                            currentPass =
                                (_settings['svPass'] ?? '').toString();
                            if (currentPass.isEmpty) {
                              setD(() {
                                isLoading = false;
                                error =
                                    'Password admin belum ditetapkan. Guna "Lupa password lama?".';
                              });
                              return;
                            }
                          } else {
                            if (_tenantId == null) {
                              setD(() {
                                isLoading = false;
                                error = 'Tenant belum resolved';
                              });
                              return;
                            }
                            final tRow = await _sb
                                .from('tenants')
                                .select('password_hash, config')
                                .eq('id', _tenantId!)
                                .maybeSingle();
                            if (tRow == null) {
                              setD(() {
                                isLoading = false;
                                error = 'System ID tidak dijumpai';
                              });
                              return;
                            }
                            final cfg = (tRow['config'] is Map) ? Map<String, dynamic>.from(tRow['config']) : <String, dynamic>{};
                            currentPass = (tRow['password_hash'] ??
                                    cfg['password'] ??
                                    '')
                                .toString();
                          }

                          if (oldPass != currentPass) {
                            setD(() {
                              isLoading = false;
                              error = 'Password lama salah';
                            });
                            return;
                          }

                          if (isAdminMode) {
                            await _applyAdminPassword(newPass, sendEmail: false);
                          } else {
                            await _applyNewPassword(newPass, sendEmail: false);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setD(() {
                            isLoading = false;
                            error = 'Ralat: $e';
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('SIMPAN'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _forgotAdminPass() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Column(
          children: [
            Icon(Icons.shield_outlined, size: 40, color: AppColors.orange),
            SizedBox(height: 10),
            Text(
              'LUPA PASSWORD ADMIN',
              style: TextStyle(
                color: AppColors.orange,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        content: const Text(
          'Password admin sementara akan dijana dan dihantar ke emel akaun dealer.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL', style: TextStyle(color: AppColors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('HANTAR'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final tempPass = _generateRandomPass();
      await _applyAdminPassword(tempPass, sendEmail: true);
    } catch (e) {
      if (mounted) _snack('Ralat: $e', err: true);
    }
  }

  // ═══════════════════════════════════════
  // NOTA POPUP
  // ═══════════════════════════════════════
  void _showNotaPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.noteSticky,
                      size: 14,
                      color: AppColors.yellow,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _lang.get('settings_tetapan_nota'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _lang.get('settings_kemaskini_nota_desc'),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 14),
                _notaPopupField(
                  _lang.get('settings_nota_invoice_label'),
                  _notaInvCtrl,
                ),
                _notaPopupField(
                  _lang.get('settings_nota_quotation_label'),
                  _notaQuoCtrl,
                ),
                _notaPopupField(
                  _lang.get('settings_nota_claim_label'),
                  _notaClaimCtrl,
                ),
                _notaPopupField(
                  _lang.get('settings_nota_booking_label'),
                  _notaBookingCtrl,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _saveSettings();
                      Navigator.pop(ctx);
                    },
                    icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
                    label: Text(_lang.get('simpan')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════
  // TEMPLATE POPUP — guna gambar dari admin (Firestore)
  // ═══════════════════════════════════════
  Map<String, String> _tplImages = {}; // cache gambar template

  Future<void> _loadTemplateImages() async {
    try {
      final row = await _sb
          .from('platform_config')
          .select('value')
          .eq('id', 'pdf_templates')
          .maybeSingle();
      if (row != null) {
        final data = (row['value'] is Map) ? Map<String, dynamic>.from(row['value']) : <String, dynamic>{};
        _tplImages = {};
        for (int i = 0; i < 10; i++) {
          final key = 'tpl_${i + 1}';
          final v = data[key];
          if (v is String && v.isNotEmpty) {
            _tplImages[key] = v;
          }
        }
      }
    } catch (_) {}
  }

  void _showTemplatePopup() async {
    // Load gambar dulu kalau belum ada
    if (_tplImages.isEmpty) await _loadTemplateImages();

    if (!mounted) return;

    // Warna tema unik setiap template — matching dengan admin page
    const tplThemes = [
      Color(0xFFFF6600), // tpl_1 Standard
      Color(0xFF2563EB), // tpl_2 Moden
      Color(0xFF374151), // tpl_3 Klasik
      Color(0xFF64748B), // tpl_4 Minimalis
      Color(0xFFDC2626), // tpl_5 Komersial
      Color(0xFF92400E), // tpl_6 Elegan
      Color(0xFF7C3AED), // tpl_7 Tengah
      Color(0xFF0D9488), // tpl_8 Kompak
      Color(0xFF1E3A5F), // tpl_9 Korporat
      Color(0xFFEC4899), // tpl_10 Kreatif
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.fileLines,
                      size: 14,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _lang.get('settings_pilihan_template'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _lang.get('settings_pilih_template_desc'),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 190,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: List.generate(10, (i) {
                      final tplId = 'tpl_${i + 1}';
                      final imageUrl = _tplImages[tplId];
                      final themeColor = tplThemes[i];
                      final name = [
                        _lang.get('settings_tpl_standard'),
                        _lang.get('settings_tpl_moden'),
                        _lang.get('settings_tpl_klasik'),
                        _lang.get('settings_tpl_minimalis'),
                        _lang.get('settings_tpl_komersial'),
                        _lang.get('settings_tpl_elegan'),
                        _lang.get('settings_tpl_tengah'),
                        _lang.get('settings_tpl_kompak'),
                        _lang.get('settings_tpl_korporat'),
                        _lang.get('settings_tpl_kreatif'),
                      ][i];
                      final isActive = _selectedTemplate == tplId;
                      final hasImage = imageUrl != null;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedTemplate = tplId);
                          setS(() {});
                        },
                        child: Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isActive
                                  ? themeColor
                                  : AppColors.border,
                              width: isActive ? 2.5 : 1,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Column(
                            children: [
                              // Gambar template dari admin
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: themeColor.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: hasImage
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            loadingBuilder: (ctx, child, p) {
                                              if (p == null) return child;
                                              return Center(
                                                child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: themeColor,
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder: (_, __, ___) => Center(
                                              child: FaIcon(
                                                FontAwesomeIcons.image,
                                                size: 18,
                                                color: themeColor.withValues(alpha: 0.3),
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              FaIcon(
                                                FontAwesomeIcons.filePdf,
                                                size: 20,
                                                color: themeColor.withValues(alpha: 0.25),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'TIADA\nPREVIEW',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: themeColor.withValues(alpha: 0.3),
                                                  fontSize: 7,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                              // Label bar
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? themeColor.withValues(alpha: 0.1)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isActive)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: FaIcon(
                                          FontAwesomeIcons.circleCheck,
                                          size: 9,
                                          color: themeColor,
                                        ),
                                      ),
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          color: isActive
                                              ? themeColor
                                              : AppColors.textMuted,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                // Butang SIMPAN — terus simpan pilihan, tak perlu preview PDF
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _saveSettings();
                      _snack('Template $_selectedTemplate disimpan!');
                    },
                    icon: const FaIcon(FontAwesomeIcons.check, size: 12),
                    label: Text('SIMPAN $_selectedTemplate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _notaPopupField(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        TextField(
          controller: ctrl,
          maxLines: 2,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            height: 1.4,
          ),
          decoration: _inputDeco('...'),
        ),
      ],
    ),
  );

  void _showPassDialog(String title, Function(String) onConfirm) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.yellow,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            letterSpacing: 2,
          ),
          textAlign: TextAlign.center,
          decoration: _inputDeco('******'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _lang.get('batal'),
              style: const TextStyle(color: AppColors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm(ctrl.text.trim());
            },
            child: Text(_lang.get('settings_sahkan')),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // PRINTER MANAGEMENT
  // ═══════════════════════════════════════
  Future<void> _savePrinter(String type, String name, String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == '80mm') {
      await prefs.setString('printer_80mm_name', name);
      await prefs.setString('printer_80mm_id', id);
      setState(() => _printerName80mm = name);
    } else if (type == 'label') {
      await prefs.setString('printer_label_name', name);
      await prefs.setString('printer_label_id', id);
      setState(() => _printerNameLabel = name);
    } else {
      await prefs.setString('printer_normal_name', name);
      await prefs.setString('printer_normal_id', id);
      setState(() => _printerNameNormal = name);
    }
    _snack('${_lang.get('settings_printer_disimpan')}: $name');
  }

  Future<void> _removePrinter(String type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == '80mm') {
      await prefs.remove('printer_80mm_name');
      await prefs.remove('printer_80mm_id');
      setState(() => _printerName80mm = '');
    } else if (type == 'label') {
      await prefs.remove('printer_label_name');
      await prefs.remove('printer_label_id');
      setState(() => _printerNameLabel = '');
    } else {
      await prefs.remove('printer_normal_name');
      await prefs.remove('printer_normal_id');
      setState(() => _printerNameNormal = '');
    }
    _snack(_lang.get('settings_printer_dibuang'));
  }

  void _showPrinterSetupModal(String type) {
    final title = type == '80mm'
        ? _lang.get('settings_printer_resit_80mm')
        : type == 'label'
        ? _lang.get('settings_printer_label_sticker')
        : _lang.get('settings_printer_biasa_a4');
    final icon = type == '80mm'
        ? FontAwesomeIcons.receipt
        : type == 'label'
        ? FontAwesomeIcons.tag
        : FontAwesomeIcons.print;
    final color = type == '80mm'
        ? AppColors.blue
        : type == 'label'
        ? AppColors.orange
        : AppColors.green;
    final currentName = type == '80mm'
        ? _printerName80mm
        : type == 'label'
        ? _printerNameLabel
        : _printerNameNormal;
    final manualCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        List<ScanResult> scanResults = [];
        bool isScanning = false;
        return StatefulBuilder(
          builder: (ctx, setS) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    FaIcon(icon, size: 14, color: color),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        FlutterBluePlus.stopScan();
                        Navigator.pop(ctx);
                      },
                      child: const FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 16,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Current printer
                if (currentName.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        FaIcon(
                          FontAwesomeIcons.circleCheck,
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lang.get('settings_printer_aktif'),
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                currentName,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _removePrinter(type);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const FaIcon(
                              FontAwesomeIcons.trash,
                              size: 12,
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),

                // Label size settings (only for label printer)
                if (type == 'label') ...[
                  StatefulBuilder(builder: (ctx, setLocalState) {
                    double localW = double.tryParse(_labelWidth) ?? 50;
                    double localH = double.tryParse(_labelHeight) ?? 30;
                    final isLocked = _labelSizeSaved;

                    // Preset saiz popular
                    final presets = <Map<String, dynamic>>[
                      {'label': '30x20', 'w': 30.0, 'h': 20.0},
                      {'label': '40x20', 'w': 40.0, 'h': 20.0},
                      {'label': '40x30', 'w': 40.0, 'h': 30.0},
                      {'label': '50x30', 'w': 50.0, 'h': 30.0},
                      {'label': '50x40', 'w': 50.0, 'h': 40.0},
                      {'label': '60x40', 'w': 60.0, 'h': 40.0},
                      {'label': '70x40', 'w': 70.0, 'h': 40.0},
                      {'label': '80x50', 'w': 80.0, 'h': 50.0},
                    ];

                    // Stepper widget builder
                    Widget buildStepper(String title, double value, double min, double max, double step, ValueChanged<double> onChanged) {
                      return Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          InkWell(
                            onTap: isLocked ? null : () {
                              if (value - step >= min) onChanged(value - step);
                            },
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: isLocked ? Colors.grey.shade200 : AppColors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.remove, size: 16, color: isLocked ? Colors.grey : AppColors.orange),
                            ),
                          ),
                          Container(
                            width: 60,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isLocked ? Colors.grey.shade300 : AppColors.border),
                            ),
                            child: Text(
                              '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} mm',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isLocked ? Colors.grey : Colors.black87,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: isLocked ? null : () {
                              if (value + step <= max) onChanged(value + step);
                            },
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: isLocked ? Colors.grey.shade200 : AppColors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.add, size: 16, color: isLocked ? Colors.grey : AppColors.orange),
                            ),
                          ),
                        ],
                      );
                    }

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? Colors.grey.shade100
                            : AppColors.orange.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isLocked
                              ? Colors.grey.shade300
                              : AppColors.orange.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              FaIcon(
                                FontAwesomeIcons.ruler,
                                size: 10,
                                color: isLocked ? Colors.grey : AppColors.orange,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isLocked
                                    ? 'SAIZ LABEL: ${localW.toStringAsFixed(0)}mm x ${localH.toStringAsFixed(0)}mm'
                                    : 'SAIZ LABEL (mm)',
                                style: TextStyle(
                                  color: isLocked ? Colors.grey : AppColors.orange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          if (!isLocked) ...[
                          const SizedBox(height: 10),

                          // ── Preset buttons ──
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: presets.map((p) {
                              final isSelected = localW == p['w'] && localH == p['h'];
                              return InkWell(
                                onTap: () {
                                  localW = p['w'] as double;
                                  localH = p['h'] as double;
                                  _labelWidth = localW.toStringAsFixed(0);
                                  _labelHeight = localH.toStringAsFixed(0);
                                  setLocalState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.orange : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? AppColors.orange : AppColors.border,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    p['label'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 12),

                          // ── Stepper: Lebar ──
                          buildStepper('Lebar (W)', localW, 20, 100, 5, (v) {
                            localW = v;
                            _labelWidth = v.toStringAsFixed(0);
                            setLocalState(() {});
                          }),
                          const SizedBox(height: 8),

                          // ── Stepper: Tinggi ──
                          buildStepper('Tinggi (H)', localH, 10, 80, 5, (v) {
                            localH = v;
                            _labelHeight = v.toStringAsFixed(0);
                            setLocalState(() {});
                          }),
                          ],
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: isLocked
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _labelSizeSaved = false);
                                    setLocalState(() {});
                                  },
                                  icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 11),
                                  label: const Text('KEMASKINI SIZE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.orange,
                                    side: const BorderSide(color: AppColors.orange),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                )
                              : ElevatedButton.icon(
                              onPressed: () async {
                                _labelSizeSaved = true;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('printer_label_width', _labelWidth);
                                await prefs.setString('printer_label_height', _labelHeight);
                                if (!mounted) return;
                                setState(() {});
                                setLocalState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Saiz label disimpan: ${_labelWidth}mm x ${_labelHeight}mm', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    backgroundColor: AppColors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 11),
                              label: const Text('SIMPAN SAIZ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),

                  // ── Jenis printer label (ESC/POS vs TSPL) ──
                  StatefulBuilder(builder: (ctx2, setLang) {
                    Widget langBtn(String val, String title, String subtitle) {
                      final sel = _labelLang == val;
                      return Expanded(
                        child: InkWell(
                          onTap: () async {
                            _labelLang = val;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('printer_label_lang', val);
                            setLang(() {});
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.orange : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel ? AppColors.orange : AppColors.border,
                                width: sel ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(title, style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: sel ? Colors.white : Colors.black87,
                                )),
                                const SizedBox(height: 2),
                                Text(subtitle, style: TextStyle(
                                  fontSize: 8,
                                  color: sel ? Colors.white70 : Colors.grey.shade600,
                                )),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('JENIS PRINTER LABEL', style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey.shade700,
                        )),
                        const SizedBox(height: 6),
                        Row(children: [
                          langBtn('escpos', 'ESC/POS', 'Generik / default'),
                          langBtn('tspl', 'TSPL', 'Xprinter / Munbyn'),
                        ]),
                      ],
                    );
                  }),
                  const SizedBox(height: 10),

                  // ── CEK LABEL (test print) ──
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (_printerNameLabel.isEmpty) {
                          _snack('Sila pilih printer label dahulu', err: true);
                          return;
                        }
                        if (!_labelSizeSaved) {
                          _snack('Sila simpan saiz label dahulu', err: true);
                          return;
                        }
                        _snack('Menghantar cek label ke printer...');
                        final ok = await PrinterService().printTestLabel();
                        if (!mounted) return;
                        if (ok) {
                          _snack('Cek label berjaya — ${_labelWidth}mm x ${_labelHeight}mm');
                        } else {
                          _snack('Gagal cetak — pastikan printer hidup & Bluetooth aktif', err: true);
                        }
                      },
                      icon: const FaIcon(FontAwesomeIcons.print, size: 11),
                      label: const Text('CEK LABEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.orange,
                        side: const BorderSide(color: AppColors.orange, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Scan button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      setS(() => isScanning = true);
                      try {
                        if (!kIsWeb) {
                          // Mobile: check adapter state dulu
                          final isOn = await FlutterBluePlus.adapterState.first;
                          if (isOn != BluetoothAdapterState.on) {
                            _snack(
                              _lang.get('settings_sila_hidupkan_bt'),
                              err: true,
                            );
                            setS(() => isScanning = false);
                            return;
                          }
                        }
                        scanResults.clear();
                        FlutterBluePlus.startScan(
                          timeout: const Duration(seconds: 8),
                        );
                        FlutterBluePlus.scanResults.listen((results) {
                          setS(
                            () => scanResults = results
                                .where((r) => r.device.platformName.isNotEmpty)
                                .toList(),
                          );
                        });
                        await Future.delayed(const Duration(seconds: 8));
                        setS(() => isScanning = false);
                        if (scanResults.isEmpty && mounted) {
                          _snack(
                            kIsWeb
                                ? 'Tiada peranti dijumpai. Pastikan Bluetooth ON dan printer dalam pairing mode.'
                                : _lang.get('settings_sila_hidupkan_bt'),
                            err: true,
                          );
                        }
                      } catch (e) {
                        setS(() => isScanning = false);
                        if (kIsWeb && e.toString().contains('NotFoundError')) {
                          _snack('Bluetooth: Tiada peranti dipilih atau dibatalkan.', err: true);
                        } else if (kIsWeb && e.toString().contains('NotSupportedError')) {
                          _snack('Browser ini tidak menyokong Web Bluetooth. Sila guna Chrome/Edge.', err: true);
                        } else {
                          _snack(
                            '${_lang.get('settings_gagal_scan')}: $e',
                            err: true,
                          );
                        }
                      }
                    },
                    icon: isScanning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const FaIcon(FontAwesomeIcons.bluetooth, size: 14),
                    label: Text(
                      isScanning
                          ? _lang.get('settings_sedang_scan')
                          : _lang.get('settings_scan_bt'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Scan results
                if (scanResults.isNotEmpty) ...[
                  Text(
                    '${scanResults.length} ${_lang.get('settings_peranti_dijumpai')}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: scanResults.length,
                      itemBuilder: (_, i) {
                        final device = scanResults[i].device;
                        final name = device.platformName;
                        final rssi = scanResults[i].rssi;
                        final isSelected = name == currentName;
                        return GestureDetector(
                          onTap: () {
                            _savePrinter(type, name, device.remoteId.str);
                            FlutterBluePlus.stopScan();
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withValues(alpha: 0.1)
                                  : AppColors.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? color : AppColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                FaIcon(
                                  FontAwesomeIcons.bluetooth,
                                  size: 14,
                                  color: isSelected
                                      ? color
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          color: isSelected
                                              ? color
                                              : Colors.black87,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        device.remoteId.str,
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    Icon(
                                      rssi > -60
                                          ? Icons.signal_cellular_4_bar
                                          : rssi > -80
                                          ? Icons.signal_cellular_alt_2_bar
                                          : Icons.signal_cellular_alt_1_bar,
                                      size: 14,
                                      color: rssi > -60
                                          ? AppColors.green
                                          : rssi > -80
                                          ? AppColors.yellow
                                          : AppColors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${rssi}dBm',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // Manual input option
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    _lang.get('settings_taip_nama_manual'),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: [
                    TextField(
                      controller: manualCtrl,
                      style: _inputStyle,
                      decoration: _inputDeco(
                        _lang.get('settings_taip_nama_printer'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (manualCtrl.text.trim().isEmpty) return;
                          _savePrinter(type, manualCtrl.text.trim(), '');
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          _lang.get('settings_simpan_manual'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── A4/A5 CONNECTION CHOICE (WiFi / Bluetooth) ───
  void _showA4ConnectionChoice() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.print,
                  size: 14,
                  color: AppColors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_lang.get('settings_printer_a4a5')} — SAMBUNGAN',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(
                    FontAwesomeIcons.xmark,
                    size: 16,
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _addPrinterOption(
              ctx,
              'WiFi',
              'Sambung melalui rangkaian WiFi',
              FontAwesomeIcons.wifi,
              AppColors.green,
              () {
                Navigator.pop(ctx);
                _showWifiPrinterModal();
              },
            ),
            const SizedBox(height: 10),
            _addPrinterOption(
              ctx,
              'Bluetooth',
              'Sambung melalui Bluetooth',
              FontAwesomeIcons.bluetooth,
              AppColors.blue,
              () {
                Navigator.pop(ctx);
                _showPrinterSetupModal('normal');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── WIFI PRINTER (A4/A5) — AUTO SCAN NETWORK ───
  String _scanProgress = '';

  Future<List<Map<String, String>>> _scanNetworkPrinters({void Function(String)? onProgress}) async {
    if (kIsWeb) return []; // Web tak boleh scan network socket

    final printers = <Map<String, String>>[];
    final ports = [9100, 631, 515];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      if (interfaces.isEmpty) return printers;

      String subnet = '';
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.address.startsWith('127.')) {
            final parts = addr.address.split('.');
            subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            break;
          }
        }
        if (subnet.isNotEmpty) break;
      }
      if (subnet.isEmpty) return printers;

      // Scan dalam batch untuk lebih stabil & pantas
      // Prioriti: IP biasa printer (.100-.110, .200-.210, .1-.20, then rest)
      final priorityIps = <int>[
        ...List.generate(11, (i) => 100 + i),  // .100-.110
        ...List.generate(11, (i) => 200 + i),  // .200-.210
        ...List.generate(20, (i) => 1 + i),     // .1-.20
        ...List.generate(10, (i) => 50 + i),    // .50-.59
      ];
      final restIps = List.generate(254, (i) => i + 1)
          .where((i) => !priorityIps.contains(i))
          .toList();
      final allIps = [...priorityIps, ...restIps];

      const batchSize = 40;
      for (var b = 0; b < allIps.length; b += batchSize) {
        final batch = allIps.sublist(b, (b + batchSize).clamp(0, allIps.length));
        onProgress?.call('Scan $subnet.${batch.first}-${batch.last} ...');

        final futures = <Future>[];
        for (final i in batch) {
          final ip = '$subnet.$i';
          for (final port in ports) {
            futures.add(_checkPrinterPort(ip, port, printers));
          }
        }
        await Future.wait(futures)
            .timeout(const Duration(seconds: 4), onTimeout: () => []);

        // Kalau dah jumpa printer, teruskan scan tapi tak perlu tunggu lama
        if (printers.isNotEmpty && b > 80) break;
      }
    } catch (_) {}

    final seen = <String>{};
    printers.removeWhere((p) => !seen.add(p['ip']!));
    return printers;
  }

  Future<void> _checkPrinterPort(
    String ip,
    int port,
    List<Map<String, String>> results,
  ) async {
    if (kIsWeb) return;
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      final portName = port == 9100
          ? 'RAW'
          : port == 631
          ? 'IPP'
          : 'LPR';

      String name = 'Printer ($portName)';
      try {
        final hostResult = await InternetAddress(ip).reverse();
        if (hostResult.host != ip) name = hostResult.host;
      } catch (_) {}

      results.add({
        'ip': ip,
        'port': port.toString(),
        'name': name,
        'protocol': portName,
      });
      socket.destroy();
    } catch (_) {}
  }

  /// Test sambungan ke printer WiFi (ping port 9100)
  Future<bool> _testWifiPrinter(String ip) async {
    if (kIsWeb) return false;
    try {
      final socket = await Socket.connect(ip, 9100,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _showWifiPrinterModal() {
    final manualNameCtrl = TextEditingController();
    final manualIpCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        List<Map<String, String>> foundPrinters = [];
        bool isScanning = false;

        return StatefulBuilder(
          builder: (ctx, setS) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.wifi,
                        size: 14,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _lang.get('settings_printer_a4a5_wifi'),
                        style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const FaIcon(
                          FontAwesomeIcons.xmark,
                          size: 16,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Current printer
                  if (_printerNameNormal.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.circleCheck,
                            size: 14,
                            color: AppColors.green,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lang.get('settings_printer_aktif'),
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _printerNameNormal,
                                  style: const TextStyle(
                                    color: AppColors.green,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.remove('printer_normal_name');
                              await prefs.remove('printer_normal_ip');
                              setState(() => _printerNameNormal = '');
                              if (ctx.mounted) Navigator.pop(ctx);
                              _snack(
                                _lang.get('settings_printer_wifi_dibuang'),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const FaIcon(
                                FontAwesomeIcons.trash,
                                size: 12,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Auto scan button (mobile sahaja)
                  if (!kIsWeb)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isScanning
                            ? null
                            : () async {
                                setS(() {
                                  isScanning = true;
                                  foundPrinters.clear();
                                  _scanProgress = '';
                                });
                                final results = await _scanNetworkPrinters(
                                  onProgress: (msg) {
                                    setS(() => _scanProgress = msg);
                                  },
                                );
                                setS(() {
                                  foundPrinters = results;
                                  isScanning = false;
                                  _scanProgress = '';
                                });
                                if (results.isEmpty && mounted) {
                                  _snack(
                                    _lang.get('settings_tiada_printer_rangkaian'),
                                    err: true,
                                  );
                                }
                              },
                        icon: isScanning
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const FaIcon(
                                FontAwesomeIcons.magnifyingGlass,
                                size: 12,
                              ),
                        label: Text(
                          isScanning
                              ? _lang.get('settings_sedang_scan_rangkaian')
                              : _lang.get('settings_scan_auto_wifi'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: AppColors.green.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                  if (kIsWeb)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
                      ),
                      child: const Column(
                        children: [
                          FaIcon(FontAwesomeIcons.globe, size: 20, color: AppColors.blue),
                          SizedBox(height: 8),
                          Text(
                            'Web: Masukkan IP printer secara manual di bawah.\nAuto-scan hanya tersedia di app mobile.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  if (isScanning && _scanProgress.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _scanProgress,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  if (isScanning && _scanProgress.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _lang.get('settings_memeriksa_ip'),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),

                  // Scan results
                  if (foundPrinters.isNotEmpty) ...[
                    Text(
                      '${foundPrinters.length} ${_lang.get('settings_printer_dijumpai')}',
                      style: const TextStyle(
                        color: AppColors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...foundPrinters.map(
                      (p) => GestureDetector(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final displayName = '${p['name']} (${p['ip']})';
                          await prefs.setString(
                            'printer_normal_name',
                            displayName,
                          );
                          await prefs.setString('printer_normal_ip', p['ip']!);
                          setState(() => _printerNameNormal = displayName);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _snack(
                            '${_lang.get('settings_printer_wifi_disimpan')}: $displayName',
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.green.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: FaIcon(
                                    FontAwesomeIcons.print,
                                    size: 14,
                                    color: AppColors.green,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['name'] ?? 'Printer',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      '${p['ip']}:${p['port']} (${p['protocol']})',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const FaIcon(
                                FontAwesomeIcons.chevronRight,
                                size: 10,
                                color: AppColors.green,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Manual input
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      _lang.get('settings_masuk_ip_manual'),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      _fieldLabel(_lang.get('settings_nama_printer')),
                      TextField(
                        controller: manualNameCtrl,
                        style: _inputStyle,
                        decoration: _inputDeco(
                          _lang.get('settings_cth_printer'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _fieldLabel('IP Address'),
                      TextField(
                        controller: manualIpCtrl,
                        keyboardType: TextInputType.number,
                        style: _inputStyle,
                        decoration: _inputDeco(_lang.get('settings_cth_ip')),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (manualIpCtrl.text.trim().isEmpty) {
                              _snack(
                                _lang.get('settings_sila_masuk_ip'),
                                err: true,
                              );
                              return;
                            }
                            final prefs = await SharedPreferences.getInstance();
                            final name = manualNameCtrl.text.trim().isNotEmpty
                                ? manualNameCtrl.text.trim()
                                : 'Printer (${manualIpCtrl.text.trim()})';
                            await prefs.setString('printer_normal_name', name);
                            await prefs.setString(
                              'printer_normal_ip',
                              manualIpCtrl.text.trim(),
                            );
                            setState(() => _printerNameNormal = name);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack(
                              '${_lang.get('settings_printer_wifi_disimpan')}: $name',
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.border,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _lang.get('settings_simpan_manual'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════
  TextStyle get _inputStyle => const TextStyle(
    color: AppColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
    filled: true,
    fillColor: AppColors.bgDeep,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
  );
  Widget _fieldLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      t,
      style: const TextStyle(
        color: AppColors.textSub,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── ROW 1: Shop Info + Logo side by side on wide ───
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildShopInfoSection()),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildPrinterSection()),
                ],
              )
            else ...[
              _buildShopInfoSection(),
              const SizedBox(height: 16),
              _buildHeaderColorSection(),
              const SizedBox(height: 16),
              _buildLanguageSection(),
              const SizedBox(height: 16),
              _buildPrinterSection(),
            ],
            const SizedBox(height: 16),

            // ─── ROW 2: Form & Receipt settings ───
            _buildFormReceiptSection(),
            const SizedBox(height: 16),

            // ─── ROW 3: Admin (hide if singleStaffMode) ───
            if (!_singleStaffMode) ...[
              _buildAdminSecuritySection(),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // SECTION BUILDERS
  // ═══════════════════════════════════════

  Widget _buildShopInfoSection() {
    return _box(
      _lang.get('settings_maklumat_cawangan'),
      FontAwesomeIcons.store,
      AppColors.primary,
      children: [
        // Logo
        Row(
          children: [
            if (_logoBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(_logoBase64!.split(',').last),
                  height: 60,
                  fit: BoxFit.contain,
                ),
              ),
            if (_logoBase64 != null) const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _uploadLogo,
                icon: const FaIcon(FontAwesomeIcons.camera, size: 12),
                label: Text(
                  _logoBase64 != null
                      ? _lang.get('settings_tukar_logo')
                      : _lang.get('settings_upload_logo'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.border,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _readonlyField(
          _lang.get('settings_nama_kedai'),
          _settings['shopName'] ?? _settings['namaKedai'] ?? '-',
        ),
        _readonlyField(_lang.get('settings_no_ssm'), _settings['ssm'] ?? '-'),
        _readonlyField(
          _lang.get('settings_alamat'),
          _settings['address'] ?? _settings['alamat'] ?? '-',
        ),
        const SizedBox(height: 10),
        _fieldLabel(_lang.get('settings_no_telefon')),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: _inputStyle,
          decoration: _inputDeco('011...'),
        ),
        const SizedBox(height: 8),
        _readonlyField(
          _lang.get('settings_emel'),
          _emailCtrl.text.isNotEmpty ? _emailCtrl.text : '-',
        ),
        _readonlyField(_lang.get('settings_shop_id'), _shopID),
      ],
    );
  }

  Widget _buildPrinterSection() {
    final printers = <Map<String, dynamic>>[];
    if (_printerName80mm.isNotEmpty)
      printers.add({
        'type': '80mm',
        'name': _printerName80mm,
        'icon': FontAwesomeIcons.bluetooth,
        'color': AppColors.blue,
        'label': '80MM',
      });
    if (_printerNameNormal.isNotEmpty)
      printers.add({
        'type': 'normal',
        'name': _printerNameNormal,
        'icon': FontAwesomeIcons.wifi,
        'color': AppColors.green,
        'label': 'A4/A5',
      });
    if (_printerNameLabel.isNotEmpty)
      printers.add({
        'type': 'label',
        'name': _printerNameLabel,
        'icon': FontAwesomeIcons.tag,
        'color': AppColors.orange,
        'label': 'LABEL',
      });

    return _box(
      _lang.get('settings_tetapan_printer'),
      FontAwesomeIcons.print,
      AppColors.cyan,
      trailing: GestureDetector(
        onTap: _showAddPrinterPopup,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(
                FontAwesomeIcons.plus,
                size: 10,
                color: Colors.black,
              ),
              const SizedBox(width: 4),
              Text(
                _lang.get('tambah'),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
      children: [
        if (printers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                _lang.get('settings_tiada_printer'),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ...printers.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                if (p['type'] == 'normal') {
                  _showA4ConnectionChoice();
                } else {
                  _showPrinterSetupModal(p['type'] as String);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: (p['color'] as Color).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (p['color'] as Color).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    FaIcon(
                      p['icon'] as IconData,
                      size: 13,
                      color: p['color'] as Color,
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (p['color'] as Color).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p['label'] as String,
                        style: TextStyle(
                          color: p['color'] as Color,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p['name'] as String,
                        style: TextStyle(
                          color: p['color'] as Color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _removePrinter(p['type'] as String),
                      child: FaIcon(
                        FontAwesomeIcons.trash,
                        size: 11,
                        color: AppColors.red.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddPrinterPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.print,
                  size: 14,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 8),
                Text(
                  _lang.get('settings_pilih_jenis_printer'),
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(
                    FontAwesomeIcons.xmark,
                    size: 16,
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _addPrinterOption(
              ctx,
              _lang.get('settings_printer_80mm'),
              _lang.get('settings_resit_thermal_bt'),
              FontAwesomeIcons.bluetooth,
              AppColors.blue,
              () {
                Navigator.pop(ctx);
                _showPrinterSetupModal('80mm');
              },
            ),
            const SizedBox(height: 10),
            _addPrinterOption(
              ctx,
              _lang.get('settings_printer_a4a5'),
              'WiFi / Bluetooth',
              FontAwesomeIcons.print,
              AppColors.green,
              () {
                Navigator.pop(ctx);
                _showA4ConnectionChoice();
              },
            ),
            const SizedBox(height: 10),
            _addPrinterOption(
              ctx,
              _lang.get('settings_printer_label'),
              _lang.get('settings_label_sticker_bt'),
              FontAwesomeIcons.tag,
              AppColors.orange,
              () {
                Navigator.pop(ctx);
                _showPrinterSetupModal('label');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _addPrinterOption(
    BuildContext ctx,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.06), Colors.transparent],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: FaIcon(icon, size: 16, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            FaIcon(
              FontAwesomeIcons.chevronRight,
              size: 12,
              color: color.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormReceiptSection() {
    return _box(
      _lang.get('settings_tetapan_borang'),
      FontAwesomeIcons.sliders,
      AppColors.blue,
      children: [
        _fieldLabel(_lang.get('settings_bil_staff')),
        _dropdown(
          _staffBoxCount,
          ['1', '2', '3'],
          {
            '1': _lang.get('settings_1_kotak'),
            '2': _lang.get('settings_2_kotak'),
            '3': _lang.get('settings_3_kotak'),
          },
          (v) => setState(() => _staffBoxCount = v!),
        ),
        const SizedBox(height: 14),

        // Template — tap to open popup
        GestureDetector(
          onTap: _showTemplatePopup,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.fileLines,
                  size: 14,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_lang.get('settings_template_dokumen')} ($_selectedTemplate)',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const FaIcon(
                  FontAwesomeIcons.chevronRight,
                  size: 10,
                  color: AppColors.textDim,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Nota/Terms — tap to open popup
        GestureDetector(
          onTap: _showNotaPopup,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.noteSticky,
                  size: 14,
                  color: AppColors.yellow,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _lang.get('settings_nota_invoice'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const FaIcon(
                  FontAwesomeIcons.chevronRight,
                  size: 10,
                  color: AppColors.textDim,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // BOOKING PAYMENT (QR + BANK)
  // ═══════════════════════════════════════
  Widget _buildBookingPaymentSection() {
    return _box(
      'TETAPAN PEMBAYARAN BOOKING',
      FontAwesomeIcons.qrcode,
      AppColors.cyan,
      children: [
        const Text(
          'QR dan maklumat bank akan dipaparkan dalam borang booking untuk pelanggan.',
          style: TextStyle(color: AppColors.textDim, fontSize: 10),
        ),
        const SizedBox(height: 14),

        // QR Image Upload
        _fieldLabel('GAMBAR QR PAYMENT'),
        GestureDetector(
          onTap: _uploadBookingQr,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _bookingQrImageUrl.isNotEmpty ? AppColors.cyan : AppColors.border),
            ),
            child: _bookingQrImageUrl.isNotEmpty
                ? Column(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(_bookingQrImageUrl, height: 140, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: AppColors.textDim)),
                    ),
                    const SizedBox(height: 8),
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FaIcon(FontAwesomeIcons.penToSquare, size: 9, color: AppColors.cyan),
                      SizedBox(width: 4),
                      Text('Tekan untuk tukar', style: TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
                    ]),
                  ])
                : const Column(children: [
                    FaIcon(FontAwesomeIcons.cloudArrowUp, size: 24, color: AppColors.textDim),
                    SizedBox(height: 6),
                    Text('Upload Gambar QR', style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
        if (_bookingQrImageUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                setState(() => _bookingQrImageUrl = '');
                _saveSettings();
              },
              child: const Text('Padam QR', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        const SizedBox(height: 14),

        // Bank Name
        _fieldLabel('NAMA BANK'),
        TextField(
          controller: _bookingBankNameCtrl,
          style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
          decoration: _inputDeco('Cth: MAYBANK / CIMB / BANK ISLAM'),
        ),
        const SizedBox(height: 10),

        // Bank Account Number
        _fieldLabel('NO AKAUN BANK'),
        TextField(
          controller: _bookingBankAccCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1),
          decoration: _inputDeco('Cth: 1234567890'),
        ),
      ],
    );
  }

  Future<void> _uploadBookingQr() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
      if (picked == null) return;
      _snack('Uploading QR...');
      final url = await SupabaseStorageHelper().uploadFile(
        bucket: 'booking_settings',
        path: '$_ownerID/$_shopID/qr_${DateTime.now().millisecondsSinceEpoch}.jpg',
        file: File(picked.path),
      );
      setState(() => _bookingQrImageUrl = url);
      _saveSettings();
      _snack('QR berjaya dimuat naik');
    } catch (e) {
      _snack('Gagal upload QR: $e', err: true);
    }
  }

  Widget _buildAdminSecuritySection() {
    return _box(
      _lang.get('settings_keselamatan_admin'),
      FontAwesomeIcons.shieldHalved,
      AppColors.yellow,
      children: [
        _fieldLabel(_lang.get('settings_no_tel_admin')),
        TextField(
          controller: _adminTelCtrl,
          keyboardType: TextInputType.phone,
          enabled: !_adminPassLocked,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          decoration: _inputDeco('011...'),
        ),
        const SizedBox(height: 10),
        _fieldLabel(_lang.get('settings_kata_laluan_admin')),
        TextField(
          controller: _adminPassCtrl,
          obscureText: true,
          enabled: !_adminPassLocked,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
          decoration: _inputDeco(_lang.get('settings_masukkan_password')),
        ),
        if (_adminPassLocked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.lock,
                  size: 10,
                  color: AppColors.green,
                ),
                const SizedBox(width: 6),
                Text(
                  _lang.get('settings_admin_dikunci'),
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (!_adminPassLocked)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveAdminPass,
              icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
              label: Text(_lang.get('settings_simpan_kunci')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _editAdminPass,
                      icon: const FaIcon(
                        FontAwesomeIcons.penToSquare,
                        size: 12,
                      ),
                      label: Text(_lang.get('kemaskini')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _forgotAdminPass,
                      icon: const FaIcon(
                        FontAwesomeIcons.circleQuestion,
                        size: 12,
                      ),
                      label: Text(_lang.get('settings_lupa')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 12),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _resetAccountPassword,
            icon: const FaIcon(FontAwesomeIcons.key, size: 12),
            label: const Text('TUKAR PASSWORD AKAUN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // HEADER COLOR SECTION
  // ═══════════════════════════════════════

  static const _headerColorOptions = <Map<String, dynamic>>[
    {'name': 'Teal', 'hex': '#0D9488'},
    {'name': 'Hijau', 'hex': '#059669'},
    {'name': 'Biru', 'hex': '#2563EB'},
    {'name': 'Indigo', 'hex': '#6366F1'},
    {'name': 'Ungu', 'hex': '#7C3AED'},
    {'name': 'Merah', 'hex': '#DC2626'},
    {'name': 'Oren', 'hex': '#EA580C'},
    {'name': 'Kuning', 'hex': '#CA8A04'},
    {'name': 'Cyan', 'hex': '#0891B2'},
    {'name': 'Hitam', 'hex': '#1E293B'},
  ];

  Color _hexToColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  Widget _buildHeaderColorSection() {
    final currentColor = _selectedHeaderColor.isNotEmpty
        ? _hexToColor(_selectedHeaderColor)
        : const Color(0xFF0D9488);
    final currentName =
        _headerColorOptions
            .where((c) => c['hex'] == _selectedHeaderColor)
            .map((c) => c['name'] as String)
            .firstOrNull ??
        'Teal';

    return _box(
      _lang.get('settings_warna_header'),
      FontAwesomeIcons.palette,
      AppColors.primary,
      children: [
        GestureDetector(
          onTap: _showHeaderColorPopup,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: currentColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: currentColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    currentName.toUpperCase(),
                    style: TextStyle(
                      color: currentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const FaIcon(
                  FontAwesomeIcons.chevronRight,
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSection() {
    return _box(
      _lang.get('settings_bahasa'),
      FontAwesomeIcons.globe,
      AppColors.blue,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedLanguage,
              isExpanded: true,
              dropdownColor: Colors.white,
              icon: const FaIcon(
                FontAwesomeIcons.chevronDown,
                size: 12,
                color: AppColors.textMuted,
              ),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
              items: const [
                DropdownMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (val) {
                if (val != null) {
                  _lang.setLanguage(val);
                  setState(() => _selectedLanguage = val);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showHeaderColorPopup() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.palette,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _lang.get('settings_pilih_warna'),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 16,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: _headerColorOptions.length,
                  itemBuilder: (_, i) {
                    final opt = _headerColorOptions[i];
                    final hex = opt['hex'] as String;
                    final name = opt['name'] as String;
                    final color = _hexToColor(hex);
                    final isSelected = _selectedHeaderColor == hex;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedHeaderColor = hex);
                        _saveSettings();
                        Navigator.pop(ctx);
                        _snack('${_lang.get('settings_warna_ditukar')} $name');
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                            if (isSelected)
                              BoxShadow(
                                color: color,
                                blurRadius: 0,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: isSelected
                            ? const Center(
                                child: FaIcon(
                                  FontAwesomeIcons.check,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════
  // REUSABLE UI WIDGETS
  // ═══════════════════════════════════════

  Widget _box(
    String title,
    IconData icon,
    Color color, {
    List<Widget> children = const [],
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMed),
        boxShadow: [BoxShadow(color: AppColors.bg, blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(icon, size: 14, color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            height: 1,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _readonlyField(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const FaIcon(
                  FontAwesomeIcons.lock,
                  size: 8,
                  color: AppColors.red,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _dropdown(
    String val,
    List<String> opts,
    Map<String, String> labels,
    ValueChanged<String?> onC,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: opts.contains(val) ? val : opts.first,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
          items: opts
              .map(
                (o) => DropdownMenuItem(value: o, child: Text(labels[o] ?? o)),
              )
              .toList(),
          onChanged: onC,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
