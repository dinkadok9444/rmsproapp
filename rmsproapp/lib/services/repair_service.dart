import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RepairService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _ownerID;
  String? _shopID;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      final parts = branch.split('@');
      _ownerID = parts[0].toLowerCase();
      _shopID = parts[1].toUpperCase();
    } else {
      _ownerID = 'admin';
      _shopID = 'MAIN';
    }
  }

  String get ownerID => _ownerID ?? 'admin';
  String get shopID => _shopID ?? 'MAIN';

  String _generateVoucherCode() {
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final code = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
    return 'V-$code';
  }

  Future<String> _getNextSiri() async {
    final counterRef = _db.collection('counters_$ownerID').doc('${shopID}_global');

    final newCount = await _db.runTransaction<int>((transaction) async {
      final snap = await transaction.get(counterRef);
      int count = 1;
      if (snap.exists) {
        count = ((snap.data()?['count'] ?? 0) as int) + 1;
      }
      transaction.set(counterRef, {'count': count}, SetOptions(merge: true));
      return count;
    });

    String pureShopID = shopID;
    if (pureShopID.contains('-')) {
      pureShopID = pureShopID.split('-')[1];
    }
    return '$pureShopID${newCount.toString().padLeft(5, '0')}';
  }

  Future<String> simpanTiket({
    required String nama,
    required String tel,
    String telWasap = '',
    required String model,
    required String jenisServis,
    String catatan = '',
    required List<RepairItem> items,
    required String tarikh,
    required double harga,
    required double deposit,
    required String paymentStatus,
    required String caraBayaran,
    String staffTerima = '',
    String phonePass = '',
    String patternResult = '',
    String custType = 'NEW CUST',
    String kodVoucher = '',
    double voucherAmt = 0,
  }) async {
    await init();
    final siri = await _getNextSiri();
    final newVoucherGen = _generateVoucherCode();

    String finalPass = phonePass.isNotEmpty ? phonePass : 'Tiada';
    if (patternResult.isNotEmpty && finalPass == 'Tiada') {
      finalPass = 'Pattern: $patternResult';
    } else if (patternResult.isNotEmpty) {
      finalPass += ' (Pattern: $patternResult)';
    }

    final kerosakan = items.map((i) => '${i.nama} (x${i.qty})').join(', ');
    final itemsArray = items.map((i) => {'nama': i.nama, 'qty': i.qty, 'harga': i.harga}).toList();
    final total = harga - voucherAmt - deposit;

    final data = {
      'siri': siri,
      'receiptNo': siri,
      'shopID': shopID,
      'nama': nama.toUpperCase(),
      'pelanggan': nama.toUpperCase(),
      'tel': tel,
      'telefon': tel,
      'tel_wasap': telWasap.isNotEmpty ? telWasap : '-',
      'wasap': telWasap.isNotEmpty ? telWasap : '-',
      'model': model.toUpperCase(),
      'kerosakan': kerosakan,
      'items_array': itemsArray,
      'tarikh': tarikh,
      'harga': harga.toStringAsFixed(2),
      'deposit': deposit.toStringAsFixed(2),
      'diskaun': '0',
      'tambahan': '0',
      'total': total.toStringAsFixed(2),
      'baki': total.toStringAsFixed(2),
      'voucher_generated': newVoucherGen,
      'voucher_used': kodVoucher,
      'voucher_used_amt': voucherAmt,
      'payment_status': paymentStatus,
      'cara_bayaran': caraBayaran,
      'catatan': catatan,
      'jenis_servis': jenisServis,
      'staff_terima': staffTerima,
      'staff_repair': '',
      'staff_serah': '',
      'password': finalPass,
      'cust_type': custType,
      'status': 'IN PROGRESS',
      'status_history': [
        {
          'status': 'IN PROGRESS',
          'timestamp': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
        }
      ],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _db.collection('repairs_$ownerID').doc(siri).set(data);
    return siri;
  }

  Future<List<Map<String, dynamic>>> getDrafts() async {
    await init();
    final snap = await _db
        .collection('drafts_$ownerID')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();

    return snap.docs
        .where((d) => d.data()['shopID'] == shopID && d.data()['status'] != 'PULLED')
        .map((d) => {'id': d.id, ...d.data()})
        .toList();
  }

  Future<void> deleteDraft(String draftId) async {
    await init();
    try {
      await _db.collection('drafts_$ownerID').doc(draftId).delete();
    } catch (_) {
      try {
        await _db.collection('drafts_$ownerID').doc(draftId).set(
          {'shopID': 'DELETED', 'status': 'PULLED'},
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> getInventory() async {
    await init();
    final snap = await _db.collection('inventory_$ownerID').get();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((d) => (d['qty'] ?? 0) > 0 && (d['status'] ?? 'AVAILABLE').toString().toUpperCase() == 'AVAILABLE')
        .toList();
  }

  Future<Map<String, dynamic>?> getBranchSettings() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch');
    if (branch == null) return null;

    // Gabung data dari saas_dealers + shops
    Map<String, dynamic> merged = {};

    // 1. Baca dari saas_dealers (addonGallery, singleStaffMode, etc)
    try {
      final dealerSnap = await _db.collection('saas_dealers').doc(ownerID).get();
      if (dealerSnap.exists) merged.addAll(dealerSnap.data() ?? {});
    } catch (_) {}

    // 2. Baca dari shops (settings kedai)
    try {
      final shopSnap = await _db.collection('shops_$ownerID').doc(shopID).get();
      if (shopSnap.exists) merged.addAll(shopSnap.data() ?? {});
    } catch (_) {}

    // Semak gallery addon + expiry
    bool hasGallery = merged['addonGallery'] == true;
    if (hasGallery && merged['galleryExpire'] != null) {
      if (DateTime.now().millisecondsSinceEpoch > (merged['galleryExpire'] as num)) {
        hasGallery = false;
      }
    }
    merged['hasGalleryAddon'] = hasGallery;
    merged['singleStaffMode'] = merged['singleStaffMode'] == true;

    return merged;
  }

  Future<List<String>> getStaffList() async {
    final settings = await getBranchSettings();
    if (settings == null) return [];
    final staffList = settings['staffList'];
    if (staffList is List) {
      return staffList.map((s) {
        if (s is String) return s;
        if (s is Map) return (s['name'] ?? s['nama'] ?? '').toString();
        return '';
      }).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }
}

class RepairItem {
  String nama;
  int qty;
  double harga;

  RepairItem({required this.nama, this.qty = 1, this.harga = 0});
}
