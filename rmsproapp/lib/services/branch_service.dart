import 'dart:developer' as dev;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/branch_pdf_settings.dart';
import 'supabase_client.dart';

class BranchService {
  String? _ownerID;
  String? _shopID;
  String? _tenantId;
  String? _branchId;
  Map<String, dynamic> _branchSettings = {};
  BranchPdfSettings? _pdfSettings;

  String? get ownerID => _ownerID;
  String? get shopID => _shopID;
  String? get tenantId => _tenantId;
  String? get branchId => _branchId;
  Map<String, dynamic> get branchSettings => _branchSettings;
  BranchPdfSettings? get pdfSettings => _pdfSettings;

  String get shopName =>
      (_branchSettings['nama_kedai'] ?? _branchSettings['shopName'] ?? 'RMS PRO').toString();
  String get address => (_branchSettings['alamat'] ?? '-').toString();
  String get phone => (_branchSettings['phone'] ?? '-').toString();
  String get email => (_branchSettings['email'] ?? '-').toString();
  String? get logoBase64 => _branchSettings['logo_base64'] as String?;

  bool isModuleEnabled(String id) {
    final raw = _branchSettings['enabled_modules'];
    if (raw is! Map || raw.isEmpty) return true;
    return raw[id] != false;
  }

  String get pdfCloudRunUrl {
    if (_pdfSettings != null &&
        _pdfSettings!.useCustomPdfUrl &&
        _pdfSettings!.pdfCloudRunUrl != null &&
        _pdfSettings!.pdfCloudRunUrl!.isNotEmpty) {
      return _pdfSettings!.pdfCloudRunUrl!;
    }
    return 'https://rms-backend-94407896005.asia-southeast1.run.app';
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBranch = prefs.getString('rms_current_branch');
    if (currentBranch == null || !currentBranch.contains('@')) {
      dev.log('[BranchService] rms_current_branch missing — skip initialize');
      return;
    }

    final parts = currentBranch.split('@');
    _ownerID = parts[0];
    _shopID = parts[1];
    _branchSettings = {};
    _pdfSettings = null;

    final sb = SupabaseService.client;

    // Resolve tenant + branch via joined query
    try {
      final row = await sb
          .from('branches')
          .select(
              'id, tenant_id, nama_kedai, alamat, phone, email, logo_base64, enabled_modules, single_staff_mode, expire_date, pdf_cloud_run_url, use_custom_pdf_url, tenants!inner(owner_id, nama_kedai, addon_gallery, gallery_expire, single_staff_mode, config, status)')
          .eq('shop_code', _shopID!)
          .eq('tenants.owner_id', _ownerID!)
          .maybeSingle();

      if (row != null) {
        _branchId = row['id'] as String;
        _tenantId = row['tenant_id'] as String;

        // Merge tenant fields first (lower priority)
        final tenant = row['tenants'] as Map?;
        if (tenant != null) _branchSettings.addAll(Map<String, dynamic>.from(tenant));

        // Branch overrides
        final branchFields = Map<String, dynamic>.from(row)..remove('tenants');
        _branchSettings.addAll(branchFields);

        // PDF settings
        _pdfSettings = BranchPdfSettings.fromMap({
          'branch_id': currentBranch,
          'pdf_cloud_run_url': row['pdf_cloud_run_url'],
          'use_custom_pdf_url': row['use_custom_pdf_url'],
        });

        // Cache branch UUID in prefs untuk service lain (job_counters etc.)
        await prefs.setString('rms_branch_id', _branchId!);
        await prefs.setString('rms_tenant_id', _tenantId!);
      }
    } catch (e) {
      dev.log('[BranchService] initialize error: $e');
    }

    dev.log('[BranchService] PDF URL: $pdfCloudRunUrl');
  }

  Future<void> savePdfSettings({
    required String pdfCloudRunUrl,
    required bool useCustomPdfUrl,
    String? updatedBy,
  }) async {
    if (_branchId == null) throw Exception('Branch belum initialized');
    final sb = SupabaseService.client;
    try {
      await sb.from('branches').update({
        'pdf_cloud_run_url': pdfCloudRunUrl,
        'use_custom_pdf_url': useCustomPdfUrl,
      }).eq('id', _branchId!);
      _pdfSettings = BranchPdfSettings(
        branchId: '$_ownerID@$_shopID',
        pdfCloudRunUrl: pdfCloudRunUrl,
        useCustomPdfUrl: useCustomPdfUrl,
        updatedBy: updatedBy,
      );
    } catch (e) {
      throw Exception('Gagal menyimpan tetapan PDF: $e');
    }
  }

  Future<BranchPdfSettings?> getPdfSettings() async {
    if (_branchId == null) return null;
    final sb = SupabaseService.client;
    try {
      final row = await sb
          .from('branches')
          .select('pdf_cloud_run_url, use_custom_pdf_url')
          .eq('id', _branchId!)
          .maybeSingle();
      if (row != null) {
        return BranchPdfSettings.fromMap({
          'branch_id': '$_ownerID@$_shopID',
          ...Map<String, dynamic>.from(row),
        });
      }
    } catch (_) {}
    return null;
  }
}
