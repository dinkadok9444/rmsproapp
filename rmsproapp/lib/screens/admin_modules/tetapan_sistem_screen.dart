import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/branch_service.dart';

class TetapanSistemScreen extends StatefulWidget {
  const TetapanSistemScreen({super.key});
  @override
  State<TetapanSistemScreen> createState() => _TetapanSistemScreenState();
}

class _TetapanSistemScreenState extends State<TetapanSistemScreen> {
  final _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  bool _isSaving = false;

  // Delyva Courier
  final _delyvaApiKeyCtrl = TextEditingController();
  final _delyvaCustomerIdCtrl = TextEditingController();
  final _delyvaCompanyIdCtrl = TextEditingController();
  bool _showDelyvaKey = false;

  // ToyyibPay
  final _toyyibSecretCtrl = TextEditingController();
  final _toyyibCategoryCtrl = TextEditingController();
  bool _toyyibSandbox = true;
  bool _showToyyibKey = false;

  // Branch PDF Settings
  final _pdfCloudRunUrlCtrl = TextEditingController();
  bool _useCustomPdfUrl = false;
  final BranchService _branchService = BranchService();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _delyvaApiKeyCtrl.dispose();
    _delyvaCustomerIdCtrl.dispose();
    _delyvaCompanyIdCtrl.dispose();
    _toyyibSecretCtrl.dispose();
    _toyyibCategoryCtrl.dispose();
    _pdfCloudRunUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      // Initialize branch service
      await _branchService.initialize();

      // Load Delyva config
      final courierSnap = await _db.collection('config').doc('courier').get();
      if (courierSnap.exists) {
        final d = courierSnap.data() ?? {};
        _delyvaApiKeyCtrl.text = d['apiKey'] ?? '';
        _delyvaCustomerIdCtrl.text = d['customerId'] ?? '';
        _delyvaCompanyIdCtrl.text = d['companyId'] ?? '';
      }

      // Load ToyyibPay config
      final toyyibSnap = await _db.collection('config').doc('toyyibpay').get();
      if (toyyibSnap.exists) {
        final d = toyyibSnap.data() ?? {};
        _toyyibSecretCtrl.text = d['secretKey'] ?? '';
        _toyyibCategoryCtrl.text = d['categoryCode'] ?? '';
        _toyyibSandbox = d['isSandbox'] ?? true;
      }

      // Load PDF settings
      final pdfSettings = await _branchService.getPdfSettings();
      if (pdfSettings != null) {
        _pdfCloudRunUrlCtrl.text = pdfSettings.pdfCloudRunUrl ?? '';
        _useCustomPdfUrl = pdfSettings.useCustomPdfUrl;
      } else {
        _pdfCloudRunUrlCtrl.text =
            'https://rms-backend-94407896005.asia-southeast1.run.app';
        _useCustomPdfUrl = false;
      }
    } catch (e) {
      if (mounted) _snack('Ralat: $e', err: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      // Save Delyva
      if (_delyvaApiKeyCtrl.text.trim().isNotEmpty) {
        await _db.collection('config').doc('courier').set({
          'provider': 'delyva',
          'apiKey': _delyvaApiKeyCtrl.text.trim(),
          'customerId': _delyvaCustomerIdCtrl.text.trim(),
          'companyId': _delyvaCompanyIdCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Save ToyyibPay
      if (_toyyibSecretCtrl.text.trim().isNotEmpty) {
        await _db.collection('config').doc('toyyibpay').set({
          'secretKey': _toyyibSecretCtrl.text.trim(),
          'categoryCode': _toyyibCategoryCtrl.text.trim(),
          'isSandbox': _toyyibSandbox,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Save PDF settings
      try {
        await _branchService.savePdfSettings(
          pdfCloudRunUrl: _pdfCloudRunUrlCtrl.text.trim(),
          useCustomPdfUrl: _useCustomPdfUrl,
          updatedBy: 'admin',
        );
      } catch (e) {
        _snack('Tetapan PDF: $e', err: true);
      }

      _snack('Semua tetapan berjaya disimpan');
    } catch (e) {
      _snack('Ralat: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDeco(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
      filled: true,
      fillColor: AppColors.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    IconData icon,
    Color color,
    Color bgColor, {
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          FaIcon(icon, size: 14, color: color),
          const SizedBox(width: 10),
          Expanded(
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
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _eyeToggle(bool show, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FaIcon(
          show ? FontAwesomeIcons.eyeSlash : FontAwesomeIcons.eye,
          size: 14,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ═══ DELYVA COURIER ═══
                _sectionHeader(
                  'DELYVA COURIER',
                  FontAwesomeIcons.truck,
                  const Color(0xFF8B5CF6),
                  const Color(0xFFEDE9FE),
                  trailing: _delyvaApiKeyCtrl.text.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AKTIF',
                            style: TextStyle(
                              color: AppColors.green,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _delyvaApiKeyCtrl,
                  obscureText: !_showDelyvaKey,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: _inputDeco(
                    'API Key (Access Token)',
                    suffix: _eyeToggle(
                      _showDelyvaKey,
                      () => setState(() => _showDelyvaKey = !_showDelyvaKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _delyvaCustomerIdCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: _inputDeco('Customer ID'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _delyvaCompanyIdCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: _inputDeco('Company ID'),
                ),
                const SizedBox(height: 24),

                // ═══ TOYYIBPAY ═══
                _sectionHeader(
                  'TOYYIBPAY',
                  FontAwesomeIcons.creditCard,
                  const Color(0xFF3B82F6),
                  AppColors.blueLight,
                  trailing: _toyyibSecretCtrl.text.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (_toyyibSandbox
                                        ? Colors.orange
                                        : AppColors.green)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _toyyibSandbox ? 'SANDBOX' : 'LIVE',
                            style: TextStyle(
                              color: _toyyibSandbox
                                  ? Colors.orange
                                  : AppColors.green,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sandbox: daftar di dev.toyyibpay.com\nLive: daftar di toyyibpay.com',
                  style: TextStyle(color: AppColors.textDim, fontSize: 9),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _toyyibSecretCtrl,
                  obscureText: !_showToyyibKey,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: _inputDeco(
                    'User Secret Key',
                    suffix: _eyeToggle(
                      _showToyyibKey,
                      () => setState(() => _showToyyibKey = !_showToyyibKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _toyyibCategoryCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: _inputDeco('Category Code'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Switch(
                      value: _toyyibSandbox,
                      activeColor: const Color(0xFF3B82F6),
                      onChanged: (v) => setState(() => _toyyibSandbox = v),
                    ),
                    Text(
                      _toyyibSandbox ? 'Sandbox Mode' : 'Live Mode',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _toyyibSandbox ? Colors.orange : AppColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ═══ BRANCH PDF SETTINGS ═══
                _sectionHeader(
                  'BRANCH PDF SETTINGS',
                  FontAwesomeIcons.filePdf,
                  const Color(0xFFDC2626),
                  const Color(0xFFFEE2E2),
                  trailing: _useCustomPdfUrl
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CUSTOM',
                            style: TextStyle(
                              color: AppColors.green,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              color: AppColors.blue,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tetapkan URL Cloud Run untuk generate PDF. Kosongkan untuk guna default.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 9),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pdfCloudRunUrlCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: _inputDeco('Cloud Run PDF URL'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Switch(
                      value: _useCustomPdfUrl,
                      activeColor: const Color(0xFFDC2626),
                      onChanged: (v) => setState(() => _useCustomPdfUrl = v),
                    ),
                    Text(
                      _useCustomPdfUrl ? 'Guna URL Custom' : 'Guna URL Default',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _useCustomPdfUrl
                            ? AppColors.green
                            : AppColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ═══ SAVE BUTTON ═══
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor: AppColors.primary.withValues(alpha: 0.3),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FaIcon(
                                FontAwesomeIcons.floppyDisk,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'SIMPAN SEMUA TETAPAN',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
  }
}
