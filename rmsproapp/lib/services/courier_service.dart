import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class CourierService {
  static final CourierService _instance = CourierService._();
  factory CourierService() => _instance;
  CourierService._();

  final _db = FirebaseFirestore.instance;

  String _apiKey = '';
  String _customerId = '';
  String _companyId = '';
  bool _loaded = false;

  /// Load centralized Delyva config (admin level)
  Future<void> loadConfig() async {
    if (_loaded && _apiKey.isNotEmpty) return;
    try {
      final doc = await _db.collection('config').doc('courier').get();
      if (doc.exists) {
        final d = doc.data()!;
        _apiKey = (d['apiKey'] ?? '').toString();
        _customerId = (d['customerId'] ?? '').toString();
        _companyId = (d['companyId'] ?? '').toString();
      }
    } catch (_) {}
    _loaded = true;
  }

  bool get isConfigured => _apiKey.isNotEmpty && _customerId.isNotEmpty;

  /// Save config (admin only)
  Future<void> saveConfig({
    required String apiKey,
    required String customerId,
    required String companyId,
  }) async {
    await _db.collection('config').doc('courier').set({
      'provider': 'delyva',
      'apiKey': apiKey,
      'customerId': customerId,
      'companyId': companyId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _apiKey = apiKey;
    _customerId = customerId;
    _companyId = companyId;
    _loaded = true;
  }

  /// Load sender (pickup) address from seller settings
  Future<Map<String, String>> loadSenderAddress(String ownerID, String shopID) async {
    try {
      final doc = await _db.collection('marketplace_shops').doc('${ownerID}_$shopID').get();
      if (doc.exists) {
        final d = doc.data()!;
        return {
          'name': (d['shopName'] ?? shopID).toString(),
          'phone': (d['phone'] ?? '').toString(),
          'address': (d['pickupAlamat'] ?? '').toString(),
          'city': (d['pickupBandar'] ?? '').toString(),
          'postcode': (d['pickupPoskod'] ?? '').toString(),
          'state': (d['pickupNegeri'] ?? '').toString(),
        };
      }
    } catch (_) {}
    return {'name': '', 'phone': '', 'address': '', 'city': '', 'postcode': '', 'state': ''};
  }

  /// Get receiver address from order, fallback to buyer settings
  Future<Map<String, String>> getReceiverAddress(Map<String, dynamic> order) async {
    final fromOrder = {
      'name': (order['receiverName'] ?? '').toString(),
      'phone': (order['receiverPhone'] ?? '').toString(),
      'address': (order['receiverAlamat'] ?? '').toString(),
      'city': (order['receiverBandar'] ?? '').toString(),
      'postcode': (order['receiverPoskod'] ?? '').toString(),
      'state': (order['receiverNegeri'] ?? '').toString(),
    };
    if ((fromOrder['address'] ?? '').isNotEmpty) return fromOrder;

    final buyerOwnerID = (order['buyerOwnerID'] ?? '').toString();
    final buyerShopID = (order['buyerShopID'] ?? '').toString();
    if (buyerOwnerID.isEmpty || buyerShopID.isEmpty) return fromOrder;
    try {
      final doc = await _db.collection('marketplace_shops').doc('${buyerOwnerID}_$buyerShopID').get();
      if (doc.exists) {
        final d = doc.data()!;
        return {
          'name': (d['receiverName'] ?? order['buyerShopName'] ?? '').toString(),
          'phone': (d['receiverPhone'] ?? '').toString(),
          'address': (d['receiverAlamat'] ?? '').toString(),
          'city': (d['receiverBandar'] ?? '').toString(),
          'postcode': (d['receiverPoskod'] ?? '').toString(),
          'state': (d['receiverNegeri'] ?? '').toString(),
        };
      }
    } catch (_) {}
    return fromOrder;
  }

  /// Validate address
  String? validateAddress(Map<String, String> addr, String label) {
    if ((addr['address'] ?? '').isEmpty) return '$label: Sila isi alamat';
    if ((addr['postcode'] ?? '').isEmpty) return '$label: Sila isi poskod';
    if ((addr['phone'] ?? '').isEmpty) return '$label: Sila isi no telefon';
    return null;
  }

  // ═══════════════════════════════════════
  // GET SHIPPING QUOTE (for checkout)
  // ═══════════════════════════════════════

  /// Get shipping cost quote from Delyva
  /// Returns {'cost': 8.50, 'serviceName': 'J&T Express'} or null
  Future<Map<String, dynamic>?> getShippingQuote({
    required String senderPostcode,
    required String receiverPostcode,
    required double weight,
  }) async {
    await loadConfig();
    if (!isConfigured) return null;

    try {
      final response = await http.post(
        Uri.parse('https://api.delyva.app/v1.0/service/instantQuote'),
        headers: {
          'Content-Type': 'application/json',
          'X-Delyvax-Access-Token': _apiKey,
        },
        body: json.encode({
          'companyId': _companyId,
          'customerId': int.tryParse(_customerId) ?? 0,
          'weight': {'value': weight, 'unit': 'kg'},
          'origin': {'address': {'postcode': senderPostcode, 'country': 'MY'}},
          'destination': {'address': {'postcode': receiverPostcode, 'country': 'MY'}},
        }),
      );

      debugPrint('=== DELYVA QUOTE: ${response.statusCode} ===');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final services = data['data']?['services'] ?? data['data'] ?? [];
        if (services is List && services.isNotEmpty) {
          // Pick cheapest
          double cheapest = double.infinity;
          String serviceName = '';
          String serviceCode = '';

          for (final s in services) {
            final price = (s['price']?['amount'] ?? s['price'] ?? 999).toDouble();
            if (price < cheapest) {
              cheapest = price;
              serviceName = (s['service']?['name'] ?? s['serviceName'] ?? 'Courier').toString();
              serviceCode = (s['serviceCode'] ?? s['service']?['code'] ?? '').toString();
            }
          }

          if (cheapest < double.infinity) {
            return {
              'cost': cheapest,
              'serviceName': serviceName,
              'serviceCode': serviceCode,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('=== DELYVA QUOTE ERROR: $e ===');
    }
    return null;
  }

  // ═══════════════════════════════════════
  // CREATE SHIPMENT
  // ═══════════════════════════════════════

  /// Create shipment via centralized Delyva account
  /// Returns {'trackingNumber': '...', 'courierName': '...', 'orderId': '...'} or null
  Future<Map<String, String>?> createShipment({
    required Map<String, String> sender,
    required Map<String, String> receiver,
    required String itemDescription,
    required double itemValue,
    required double weight,
    String? serviceCode,
  }) async {
    await loadConfig();
    if (!isConfigured) return null;

    try {
      final desc = itemDescription.isNotEmpty ? itemDescription : 'Spare Part';

      final orderBody = <String, dynamic>{
        'process': true,
        'customerId': int.tryParse(_customerId) ?? 0,
        'companyId': _companyId,
        'source': 'rms-pro',
        'referenceNo': 'RMS-${DateTime.now().millisecondsSinceEpoch}',
        'origin': {
          'inventory': [
            {
              'name': desc,
              'type': 'PARCEL',
              'price': {'amount': itemValue.toString(), 'currency': 'MYR'},
              'weight': {'value': weight, 'unit': 'kg'},
              'dimension': {'unit': 'cm', 'width': 10, 'length': 10, 'height': 10},
              'quantity': 1,
            },
          ],
          'contact': {
            'name': sender['name'] ?? '',
            'phone': _formatPhone(sender['phone'] ?? ''),
            'address1': sender['address'] ?? '',
            'city': sender['city'] ?? '',
            'state': sender['state'] ?? '',
            'postcode': sender['postcode'] ?? '',
            'country': 'MY',
          },
        },
        'destination': {
          'inventory': [
            {
              'name': desc,
              'type': 'PARCEL',
              'price': {'amount': itemValue.toString(), 'currency': 'MYR'},
              'weight': {'value': weight, 'unit': 'kg'},
              'dimension': {'unit': 'cm', 'width': 10, 'length': 10, 'height': 10},
              'quantity': 1,
            },
          ],
          'contact': {
            'name': receiver['name'] ?? '',
            'phone': _formatPhone(receiver['phone'] ?? ''),
            'address1': receiver['address'] ?? '',
            'city': receiver['city'] ?? '',
            'state': receiver['state'] ?? '',
            'postcode': receiver['postcode'] ?? '',
            'country': 'MY',
          },
        },
      };

      if (serviceCode != null && serviceCode.isNotEmpty) {
        orderBody['serviceCode'] = serviceCode;
      }

      debugPrint('=== DELYVA CREATE ORDER ===');

      final response = await http.post(
        Uri.parse('https://api.delyva.app/v1.0/order'),
        headers: {
          'Content-Type': 'application/json',
          'X-Delyvax-Access-Token': _apiKey,
        },
        body: json.encode(orderBody),
      );

      debugPrint('=== DELYVA RESPONSE: ${response.statusCode} ===');
      debugPrint('=== DELYVA BODY: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)} ===');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final result = data['data'] ?? data;
        final orderId = (result['orderId'] ?? result['id'] ?? '').toString();

        if (orderId.isNotEmpty) {
          // Poll for consignmentNo (retry up to 5 times)
          String? tracking;
          for (int i = 0; i < 5; i++) {
            await Future.delayed(const Duration(seconds: 3));
            tracking = await _getTrackingNumber(orderId);
            if (tracking != null) break;
            debugPrint('=== DELYVA POLL $i: waiting for consignmentNo... ===');
          }

          return {
            'trackingNumber': tracking ?? orderId,
            'courierName': 'Delyva',
            'orderId': orderId,
          };
        }
      }
    } catch (e) {
      debugPrint('=== DELYVA CREATE ERROR: $e ===');
    }
    return null;
  }

  /// Fetch consignmentNo from order details
  Future<String?> _getTrackingNumber(String orderId) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.delyva.app/v1.0/order/$orderId'),
        headers: {'X-Delyvax-Access-Token': _apiKey},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final order = data['data'] ?? data;
        final consignment = (order['consignmentNo'] ?? '').toString();
        final trackingNo = (order['trackingNo'] ?? '').toString();
        debugPrint('=== DELYVA TRACKING: consignment=$consignment tracking=$trackingNo ===');
        if (consignment.isNotEmpty) return consignment;
        if (trackingNo.isNotEmpty) return trackingNo;
      }
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════
  // AIRWAY BILL
  // ═══════════════════════════════════════

  /// Get airway bill label URL (PDF)
  String getAirwayBillUrl(String orderId) {
    return 'https://api.delyva.app/v1.0/order/$orderId/label?apikey=$_apiKey';
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════
  String _formatPhone(String phone) {
    var p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.startsWith('0')) p = '60$p';
    if (!p.startsWith('60')) p = '60$p';
    return p;
  }
}
