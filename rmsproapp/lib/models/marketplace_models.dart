import 'package:cloud_firestore/cloud_firestore.dart';

class MarketplaceProduct {
  final String docId;
  final String ownerID, shopID, shopName;
  final String itemName, description, category;
  final double price;
  final int quantity;
  final String? imageUrl;
  final bool isActive;
  final int soldCount;
  final Timestamp? createdAt;

  MarketplaceProduct({
    required this.docId,
    required this.ownerID,
    required this.shopID,
    required this.shopName,
    required this.itemName,
    required this.description,
    required this.category,
    required this.price,
    required this.quantity,
    this.imageUrl,
    this.isActive = true,
    this.soldCount = 0,
    this.createdAt,
  });

  factory MarketplaceProduct.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MarketplaceProduct(
      docId: doc.id,
      ownerID: d['ownerID'] ?? '',
      shopID: d['shopID'] ?? '',
      shopName: d['shopName'] ?? '',
      itemName: d['itemName'] ?? '',
      description: d['description'] ?? '',
      category: d['category'] ?? 'Lain-lain',
      price: (d['price'] is num) ? (d['price'] as num).toDouble() : 0,
      quantity: (d['quantity'] is num) ? (d['quantity'] as num).toInt() : 0,
      imageUrl: d['imageUrl'] as String?,
      isActive: d['isActive'] ?? true,
      soldCount: (d['soldCount'] is num) ? (d['soldCount'] as num).toInt() : 0,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

class MarketplaceOrder {
  final String docId;
  final String itemDocId, itemName, category;
  final double pricePerUnit, totalPrice, commission, sellerPayout;
  final int quantity;
  // Seller
  final String sellerOwnerID, sellerShopID, sellerShopName;
  // Buyer
  final String buyerOwnerID, buyerShopID, buyerShopName;
  // Payment
  final String billplzBillId, billplzUrl;
  final String paymentStatus;
  // Status: pending_payment → paid → shipped → completed / cancelled
  final String status;
  final String trackingNumber, courierName;
  final Timestamp? createdAt, paidAt, shippedAt, completedAt;

  MarketplaceOrder({
    required this.docId,
    required this.itemDocId,
    required this.itemName,
    required this.category,
    required this.pricePerUnit,
    required this.totalPrice,
    required this.commission,
    required this.sellerPayout,
    required this.quantity,
    required this.sellerOwnerID,
    required this.sellerShopID,
    required this.sellerShopName,
    required this.buyerOwnerID,
    required this.buyerShopID,
    required this.buyerShopName,
    this.billplzBillId = '',
    this.billplzUrl = '',
    this.paymentStatus = 'unpaid',
    this.status = 'pending_payment',
    this.trackingNumber = '',
    this.courierName = '',
    this.createdAt,
    this.paidAt,
    this.shippedAt,
    this.completedAt,
  });

  factory MarketplaceOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MarketplaceOrder(
      docId: doc.id,
      itemDocId: d['itemDocId'] ?? '',
      itemName: d['itemName'] ?? '',
      category: d['category'] ?? '',
      pricePerUnit: (d['pricePerUnit'] is num)
          ? (d['pricePerUnit'] as num).toDouble()
          : 0,
      totalPrice: (d['totalPrice'] is num)
          ? (d['totalPrice'] as num).toDouble()
          : 0,
      commission: (d['commission'] is num)
          ? (d['commission'] as num).toDouble()
          : 0,
      sellerPayout: (d['sellerPayout'] is num)
          ? (d['sellerPayout'] as num).toDouble()
          : 0,
      quantity: (d['quantity'] is num) ? (d['quantity'] as num).toInt() : 0,
      sellerOwnerID: d['sellerOwnerID'] ?? '',
      sellerShopID: d['sellerShopID'] ?? '',
      sellerShopName: d['sellerShopName'] ?? '',
      buyerOwnerID: d['buyerOwnerID'] ?? '',
      buyerShopID: d['buyerShopID'] ?? '',
      buyerShopName: d['buyerShopName'] ?? '',
      billplzBillId: d['billplzBillId'] ?? '',
      billplzUrl: d['billplzUrl'] ?? '',
      paymentStatus: d['paymentStatus'] ?? 'unpaid',
      status: d['status'] ?? 'pending_payment',
      trackingNumber: d['trackingNumber'] ?? '',
      courierName: d['courierName'] ?? '',
      createdAt: d['createdAt'] as Timestamp?,
      paidAt: d['paidAt'] as Timestamp?,
      shippedAt: d['shippedAt'] as Timestamp?,
      completedAt: d['completedAt'] as Timestamp?,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending_payment':
        return 'BELUM BAYAR';
      case 'paid':
        return 'DIBAYAR';
      case 'shipped':
        return 'DIHANTAR';
      case 'completed':
        return 'SELESAI';
      case 'cancelled':
        return 'DIBATALKAN';
      default:
        return status.toUpperCase();
    }
  }
}

// Model untuk tetapan branch PDF
class BranchPdfSettings {
  final String branchId; // Format: ownerID@shopID
  final String? pdfCloudRunUrl; // URL custom untuk cloud run PDF
  final bool useCustomPdfUrl; // Gunakan URL custom atau default
  final Timestamp? updatedAt;
  final String? updatedBy;

  BranchPdfSettings({
    required this.branchId,
    this.pdfCloudRunUrl,
    this.useCustomPdfUrl = false,
    this.updatedAt,
    this.updatedBy,
  });

  factory BranchPdfSettings.fromMap(Map<String, dynamic> data) {
    return BranchPdfSettings(
      branchId: data['branchId'] ?? '',
      pdfCloudRunUrl: data['pdfCloudRunUrl'] as String?,
      useCustomPdfUrl: data['useCustomPdfUrl'] ?? false,
      updatedAt: data['updatedAt'] as Timestamp?,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branchId': branchId,
      'pdfCloudRunUrl': pdfCloudRunUrl,
      'useCustomPdfUrl': useCustomPdfUrl,
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }

  // Helper untuk mendapatkan URL PDF yang betul
  String get effectivePdfUrl {
    if (useCustomPdfUrl &&
        pdfCloudRunUrl != null &&
        pdfCloudRunUrl!.isNotEmpty) {
      return pdfCloudRunUrl!;
    }
    return 'https://rms-backend-94407896005.asia-southeast1.run.app';
  }
}
