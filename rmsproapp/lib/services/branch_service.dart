import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/marketplace_models.dart';

class BranchService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _ownerID;
  String? _shopID;
  Map<String, dynamic> _branchSettings = {};
  BranchPdfSettings? _pdfSettings;

  String? get ownerID => _ownerID;
  String? get shopID => _shopID;
  Map<String, dynamic> get branchSettings => _branchSettings;
  BranchPdfSettings? get pdfSettings => _pdfSettings;

  String get shopName =>
      _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'RMS PRO';
  String get address =>
      _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-';
  String get phone =>
      _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-';
  String get email =>
      _branchSettings['email'] ?? _branchSettings['emel'] ?? '-';
  String? get logoBase64 => _branchSettings['logoBase64'];

  bool isModuleEnabled(String id) {
    final raw = _branchSettings['enabledModules'];
    if (raw is! Map || raw.isEmpty) return true;
    return raw[id] != false;
  }

  // Get effective PDF URL untuk branch ini
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
    if (currentBranch == null) {
      dev.log('[BranchService] rms_current_branch is NULL — skip initialize');
      return;
    }

    dev.log('[BranchService] Initializing for branch: $currentBranch');

    _branchSettings = {};
    _pdfSettings = null;

    final parts = currentBranch.split('@');
    _ownerID = parts[0];
    _shopID = parts.length > 1 ? parts[1] : '';

    // 1. Baca dari saas_dealers (data owner)
    try {
      final dealerSnap = await _db
          .collection('saas_dealers')
          .doc(_ownerID)
          .get();
      if (dealerSnap.exists) _branchSettings.addAll(dealerSnap.data() ?? {});
    } catch (e) {
      dev.log('[BranchService] Gagal baca saas_dealers: $e');
    }

    // 2. Baca dari shops_{ownerID}/{shopID} (data kedai)
    try {
      final shopSnap = await _db
          .collection('shops_$_ownerID')
          .doc(_shopID)
          .get();
      if (shopSnap.exists) _branchSettings.addAll(shopSnap.data() ?? {});
    } catch (e) {
      dev.log('[BranchService] Gagal baca shops_$_ownerID: $e');
    }

    // 3. Baca dari global_branches (jika ada data tambahan)
    try {
      final branchSnap = await _db
          .collection('global_branches')
          .doc(currentBranch)
          .get();
      if (branchSnap.exists) _branchSettings.addAll(branchSnap.data() ?? {});
    } catch (e) {
      dev.log('[BranchService] Gagal baca global_branches: $e');
    }

    // 4. Load PDF settings dari branch_pdf_settings
    try {
      final pdfSnap = await _db
          .collection('branch_pdf_settings')
          .doc(currentBranch)
          .get();
      if (pdfSnap.exists) {
        _pdfSettings = BranchPdfSettings.fromMap(pdfSnap.data() ?? {});
      }
    } catch (e) {
      dev.log('[BranchService] Gagal baca branch_pdf_settings: $e');
    }

    dev.log('[BranchService] PDF URL: $pdfCloudRunUrl');
  }

  // Simpan tetapan PDF untuk branch ini
  Future<void> savePdfSettings({
    required String pdfCloudRunUrl,
    required bool useCustomPdfUrl,
    String? updatedBy,
  }) async {
    final currentBranch = '$_ownerID@$_shopID';
    if (currentBranch.isEmpty) return;

    final settings = BranchPdfSettings(
      branchId: currentBranch,
      pdfCloudRunUrl: pdfCloudRunUrl,
      useCustomPdfUrl: useCustomPdfUrl,
      updatedBy: updatedBy,
    );

    try {
      await _db
          .collection('branch_pdf_settings')
          .doc(currentBranch)
          .set(settings.toMap());
      _pdfSettings = settings;
    } catch (e) {
      throw Exception('Gagal menyimpan tetapan PDF: $e');
    }
  }

  // Dapatkan tetapan PDF untuk branch ini
  Future<BranchPdfSettings?> getPdfSettings() async {
    final currentBranch = '$_ownerID@$_shopID';
    if (currentBranch.isEmpty) return null;

    try {
      final snap = await _db
          .collection('branch_pdf_settings')
          .doc(currentBranch)
          .get();
      if (snap.exists) {
        return BranchPdfSettings.fromMap(snap.data() ?? {});
      }
    } catch (_) {}
    return null;
  }
}
