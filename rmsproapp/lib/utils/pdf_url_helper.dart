import 'package:shared_preferences/shared_preferences.dart';
import '../services/branch_service.dart';

class PdfUrlHelper {
  static final BranchService _branchService = BranchService();
  static bool _initialized = false;
  static String? _lastBranch;

  // Initialize branch service jika belum atau branch dah bertukar
  static Future<void> _ensureInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBranch = prefs.getString('rms_current_branch');

    if (!_initialized || currentBranch != _lastBranch) {
      await _branchService.initialize();
      _lastBranch = currentBranch;
      _initialized = true;
    }
  }

  // Force re-initialize (guna bila tukar branch)
  static void reset() {
    _initialized = false;
    _lastBranch = null;
  }

  // Get PDF URL untuk branch semasa
  static Future<String> getPdfUrl() async {
    await _ensureInitialized();
    return _branchService.pdfCloudRunUrl;
  }

  // Get PDF URL untuk generate-pdf endpoint
  static Future<String> getGeneratePdfUrl() async {
    final baseUrl = await getPdfUrl();
    return '$baseUrl/generate-pdf';
  }

  // Get PDF URL untuk generate-quote-pdf endpoint
  static Future<String> getGenerateQuotePdfUrl() async {
    final baseUrl = await getPdfUrl();
    return '$baseUrl/generate-quote-pdf';
  }

  // Check jika menggunakan URL custom
  static Future<bool> isUsingCustomUrl() async {
    await _ensureInitialized();
    return _branchService.pdfSettings?.useCustomPdfUrl ?? false;
  }

  // Get current branch info
  static Future<Map<String, String>> getBranchInfo() async {
    await _ensureInitialized();
    return {
      'ownerID': _branchService.ownerID ?? 'admin',
      'shopID': _branchService.shopID ?? 'MAIN',
      'pdfUrl': _branchService.pdfCloudRunUrl,
    };
  }
}
