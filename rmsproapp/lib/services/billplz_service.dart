import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// ToyyibPay Payment Gateway Service
class ToyyibpayService {
  static final ToyyibpayService _instance = ToyyibpayService._();
  factory ToyyibpayService() => _instance;
  ToyyibpayService._();

  final _db = FirebaseFirestore.instance;

  String _secretKey = '';
  String _categoryCode = '';
  bool _isSandbox = true;

  String get _baseUrl => _isSandbox
      ? 'https://dev.toyyibpay.com'
      : 'https://toyyibpay.com';

  /// Load config from Firestore
  Future<void> loadConfig() async {
    try {
      final doc = await _db.collection('config').doc('toyyibpay').get();
      if (doc.exists) {
        final data = doc.data()!;
        _secretKey = data['secretKey'] ?? '';
        _categoryCode = data['categoryCode'] ?? '';
        _isSandbox = data['isSandbox'] ?? true;
      }
    } catch (_) {}
  }

  bool get isConfigured => _secretKey.isNotEmpty && _categoryCode.isNotEmpty;

  /// Save config (admin)
  Future<void> saveConfig({
    required String secretKey,
    required String categoryCode,
    required bool isSandbox,
  }) async {
    await _db.collection('config').doc('toyyibpay').set({
      'secretKey': secretKey,
      'categoryCode': categoryCode,
      'isSandbox': isSandbox,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _secretKey = secretKey;
    _categoryCode = categoryCode;
    _isSandbox = isSandbox;
  }

  /// Create a bill for marketplace order
  /// Returns {'billCode': '...', 'url': '...'} or null
  Future<Map<String, String>?> createBill({
    required String orderId,
    required String buyerName,
    required String buyerEmail,
    required String buyerPhone,
    required double amount,
    required String description,
    required String callbackUrl,
    required String redirectUrl,
  }) async {
    if (!isConfigured) await loadConfig();
    if (!isConfigured) return null;

    try {
      // Amount in cents
      final amountCents = (amount * 100).round();

      final response = await http.post(
        Uri.parse('$_baseUrl/index.php/api/createBill'),
        body: {
          'userSecretKey': _secretKey,
          'categoryCode': _categoryCode,
          'billName': description.length > 30 ? description.substring(0, 30) : description,
          'billDescription': description,
          'billPriceSetting': '1', // 1 = fixed amount
          'billPayorInfo': '1', // 1 = required
          'billAmount': amountCents.toString(),
          'billReturnUrl': redirectUrl,
          'billCallbackUrl': callbackUrl,
          'billExternalReferenceNo': orderId,
          'billTo': buyerName,
          'billEmail': buyerEmail,
          'billPhone': buyerPhone.replaceAll(RegExp(r'\D'), ''),
          'billSplitPayment': '0',
          'billPaymentChannel': '2', // 0=FPX+CC, 1=FPX, 2=CC+FPX
          'billChargeToCustomer': '2', // 0=owner, 1=customer FPX, 2=customer both
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final billCode = data[0]['BillCode']?.toString() ?? '';
          if (billCode.isNotEmpty) {
            return {
              'billCode': billCode,
              'url': '$_baseUrl/$billCode',
            };
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Check bill payment status
  /// Returns 'paid', 'pending', or 'failed'
  Future<String> checkBillStatus(String billCode) async {
    if (!isConfigured) await loadConfig();
    if (!isConfigured) return 'failed';

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/index.php/api/getBillTransactions'),
        body: {
          'billCode': billCode,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final status = data[0]['billpaymentStatus']?.toString() ?? '';
          if (status == '1') return 'paid';
          if (status == '3') return 'pending';
        }
      }
    } catch (_) {}
    return 'failed';
  }
}
