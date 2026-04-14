import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class MarketplaceService {
  static final MarketplaceService _instance = MarketplaceService._();
  factory MarketplaceService() => _instance;
  MarketplaceService._();

  final _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════
  // PRODUCTS
  // ═══════════════════════════════════════

  Stream<QuerySnapshot> streamAllProducts() {
    return _db
        .collection('marketplace_global')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> streamMyProducts(String ownerID) {
    return _db
        .collection('marketplace_global')
        .where('ownerID', isEqualTo: ownerID)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> addProduct(Map<String, dynamic> data) async {
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['isActive'] = true;
    data['soldCount'] = 0;
    await _db.collection('marketplace_global').add(data);
  }

  Future<void> updateProduct(String docId, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('marketplace_global').doc(docId).update(data);
  }

  Future<void> deleteProduct(String docId) async {
    await _db.collection('marketplace_global').doc(docId).delete();
  }

  Future<void> toggleProductActive(String docId, bool isActive) async {
    await _db.collection('marketplace_global').doc(docId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════
  // ORDERS
  // ═══════════════════════════════════════

  /// Create order with pending_payment status
  Future<String> createOrder(Map<String, dynamic> data) async {
    data['status'] = 'pending_payment';
    data['paymentStatus'] = 'unpaid';
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    final doc = await _db.collection('marketplace_orders').add(data);
    return doc.id;
  }

  /// Update order with Billplz bill info
  Future<void> updateOrderBillplz(String orderId, String billId, String billUrl) async {
    await _db.collection('marketplace_orders').doc(orderId).update({
      'billplzBillId': billId,
      'billplzUrl': billUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mark order as paid (called after Billplz confirms payment)
  Future<void> markOrderPaid(String orderId) async {
    await _db.collection('marketplace_orders').doc(orderId).update({
      'status': 'paid',
      'paymentStatus': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Seller marks order as shipped
  Future<void> markOrderShipped(String orderId, String trackingNumber, String courierName) async {
    await _db.collection('marketplace_orders').doc(orderId).update({
      'status': 'shipped',
      'trackingNumber': trackingNumber,
      'courierName': courierName,
      'shippedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Buyer confirms received — order complete
  Future<void> markOrderCompleted(String orderId) async {
    await _db.collection('marketplace_orders').doc(orderId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Increment sold count for the product
    final order = await _db.collection('marketplace_orders').doc(orderId).get();
    final itemDocId = order.data()?['itemDocId'] ?? '';
    if (itemDocId.isNotEmpty) {
      await _db.collection('marketplace_global').doc(itemDocId).update({
        'soldCount': FieldValue.increment(1),
      });
    }
  }

  /// Cancel order
  Future<void> cancelOrder(String orderId) async {
    await _db.collection('marketplace_orders').doc(orderId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream buyer's orders
  Stream<QuerySnapshot> streamBuyerOrders(String buyerOwnerID) {
    return _db
        .collection('marketplace_orders')
        .where('buyerOwnerID', isEqualTo: buyerOwnerID)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream seller's incoming orders
  Stream<QuerySnapshot> streamSellerOrders(String sellerOwnerID) {
    return _db
        .collection('marketplace_orders')
        .where('sellerOwnerID', isEqualTo: sellerOwnerID)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream all orders (admin)
  Stream<QuerySnapshot> streamAllOrders() {
    return _db
        .collection('marketplace_orders')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ═══════════════════════════════════════
  // SHOP PROFILE
  // ═══════════════════════════════════════

  Future<Map<String, dynamic>?> getShopProfile(String ownerID, String shopID) async {
    final doc = await _db.collection('marketplace_shops').doc('${ownerID}_$shopID').get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> saveShopProfile(String ownerID, String shopID, Map<String, dynamic> data) async {
    data['ownerID'] = ownerID;
    data['shopID'] = shopID;
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('marketplace_shops').doc('${ownerID}_$shopID').set(
      data,
      SetOptions(merge: true),
    );
  }

  Stream<QuerySnapshot> streamShopProducts(String ownerID) {
    return _db
        .collection('marketplace_global')
        .where('ownerID', isEqualTo: ownerID)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ═══════════════════════════════════════
  // NOTIFICATIONS
  // ═══════════════════════════════════════

  Future<void> sendNotification({
    required String targetOwnerID,
    required String targetShopID,
    required String type,
    required String title,
    required String message,
    String? orderDocId,
  }) async {
    await _db.collection('marketplace_notifications').add({
      'targetOwnerID': targetOwnerID,
      'targetShopID': targetShopID,
      'type': type,
      'title': title,
      'message': message,
      'orderDocId': orderDocId ?? '',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════
  // ADMIN STATS
  // ═══════════════════════════════════════

  // Reads pre-aggregated stats maintained by Cloud Function
  // (functions/index.js: onMarketplaceOrderWrite trigger).
  // Falls back to zeroed stats if summary doc not yet created.
  Future<Map<String, dynamic>> getAdminStats() async {
    final summary = await _db
        .collection('marketplace_summary')
        .doc('stats')
        .get();
    final d = summary.data() ?? {};
    return {
      'totalGMV': (d['totalGMV'] as num?)?.toDouble() ?? 0.0,
      'totalCommission': (d['totalCommission'] as num?)?.toDouble() ?? 0.0,
      'completedOrders': d['completedOrders'] ?? 0,
      'activeOrders': d['activeOrders'] ?? 0,
      'activeListings': d['activeListings'] ?? 0,
      'activeSellers': d['activeSellers'] ?? 0,
    };
  }
}
