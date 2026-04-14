import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';

class QuickSalesScreen extends StatefulWidget {
  final Map<String, dynamic>? enabledModules;
  const QuickSalesScreen({super.key, this.enabledModules});
  @override
  State<QuickSalesScreen> createState() => _QuickSalesScreenState();
}

class _QuickSalesScreenState extends State<QuickSalesScreen> {
  final _db = FirebaseFirestore.instance;
  String _ownerID = 'admin', _shopID = 'MAIN';

  String _staff = '';
  String _caraBayaran = 'CASH';
  bool _isSaving = false;

  // NFC / PayWave
  bool _nfcScanning = false;
  String _nfcTagId = '';
  String _nfcStatus = '';

  // POS Settings
  bool _autoPrint = true;
  bool _autoDrawer = true;
  String _qrImageUrl = '';
  String _bankAccount = '';
  String _bankName = '';
  String _bankOwnerName = '';
  String _notaKaki = 'Terima kasih atas sokongan anda.';
  String _custType = 'WALK-IN'; // WALK-IN or ONLINE

  // Shop info for receipt
  Map<String, dynamic> _shopInfo = {};

  // Products
  List<Map<String, dynamic>> _products = [];

  // Cart
  final List<Map<String, dynamic>> _cart = [];
  double get _cartTotal => _cart.fold(0.0, (s, item) {
        final harga = (item['harga'] as num?) ?? 0;
        final diskaun = (item['diskaun'] as num?) ?? 0;
        final qty = (item['qty'] as int?) ?? 1;
        return s + ((harga - diskaun) * qty);
      });
  int get _cartCount => _cart.fold<int>(0, (s, c) => s + (c['qty'] as int));

  // Customer
  final _custNameCtrl = TextEditingController();
  final _custTelCtrl = TextEditingController();
  final _custAlamatCtrl = TextEditingController();

  // Search
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Checkout step: 0 = cart list, 1 = payment
  int _checkoutStep = 0;

  List<String> _staffList = [];
  List<Map<String, dynamic>> _existingCustomers = [];
  final List<StreamSubscription> _subs = [];

  String _selectedCategory = 'SEMUA';
  List<String> get _categories {
    final cats = <String>{'SEMUA'};
    for (final p in _products) {
      final cat = (p['category'] ?? '').toString().toUpperCase();
      if (cat.isNotEmpty) cats.add(cat);
    }
    return cats.toList();
  }

  static const _paymentMethods = ['CASH', 'QR', 'TRANSFER', 'PAYWAVE', 'SPAYLATER'];
  static const Map<String, IconData> _paymentIcons = {
    'CASH': FontAwesomeIcons.moneyBill,
    'QR': FontAwesomeIcons.qrcode,
    'TRANSFER': FontAwesomeIcons.buildingColumns,
    'PAYWAVE': FontAwesomeIcons.wifi,
    'SPAYLATER': FontAwesomeIcons.clockRotateLeft,
  };
  static const Map<String, Color> _paymentColors = {
    'CASH': AppColors.green,
    'QR': AppColors.cyan,
    'TRANSFER': AppColors.yellow,
    'PAYWAVE': AppColors.blue,
    'SPAYLATER': AppColors.orange,
  };

  @override
  void initState() {
    super.initState();
    _init();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _custNameCtrl.dispose();
    _custTelCtrl.dispose();
    _custAlamatCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0];
      _shopID = branch.split('@')[1].toUpperCase();
    }
    _autoPrint = prefs.getBool('pos_auto_print') ?? true;
    _autoDrawer = prefs.getBool('pos_auto_drawer') ?? true;
    _qrImageUrl = prefs.getString('pos_qr_image_$_ownerID') ?? '';
    _bankAccount = prefs.getString('pos_bank_account_$_ownerID') ?? '';
    _bankName = prefs.getString('pos_bank_name_$_ownerID') ?? '';
    _bankOwnerName = prefs.getString('pos_bank_owner_$_ownerID') ?? '';
    _notaKaki = prefs.getString('pos_nota_kaki_$_ownerID') ?? 'Terima kasih atas sokongan anda.';
    _listenProducts();
    _listenCustomers();
    _loadStaff();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('pos_auto_print', _autoPrint);
    prefs.setBool('pos_auto_drawer', _autoDrawer);
    prefs.setString('pos_qr_image_$_ownerID', _qrImageUrl);
    prefs.setString('pos_bank_account_$_ownerID', _bankAccount);
    prefs.setString('pos_bank_name_$_ownerID', _bankName);
    prefs.setString('pos_bank_owner_$_ownerID', _bankOwnerName);
    prefs.setString('pos_nota_kaki_$_ownerID', _notaKaki);
  }

  void _listenProducts() {
    // Accessories
    _subs.add(_db.collection('accessories_$_ownerID').snapshots().listen((snap) {
      if (!mounted) return;
      final items = snap.docs
          .map((d) => {'id': d.id, 'source': 'accessories', 'category': 'ACCESSORIES', ...d.data()})
          .where((d) => (d['qty'] ?? 0) > 0)
          .toList();
      setState(() {
        _products = [..._products.where((d) => d['source'] != 'accessories'), ...items];
      });
    }));
    // Sparepart (inventory)
    _subs.add(_db.collection('inventory_$_ownerID').snapshots().listen((snap) {
      if (!mounted) return;
      final items = snap.docs
          .map((d) => {'id': d.id, 'source': 'sparepart', ...d.data()})
          .where((d) => (d['qty'] ?? 0) > 0)
          .toList();
      setState(() {
        _products = [..._products.where((d) => d['source'] != 'sparepart'), ...items];
      });
    }));
    // Telefon (phone stock) — only if JualTelefon enabled
    final em = widget.enabledModules;
    final phoneEnabled = em == null || em.isEmpty || em['JualTelefon'] != false;
    if (phoneEnabled) {
      _subs.add(_db.collection('phone_stock_$_ownerID').snapshots().listen((snap) {
        if (!mounted) return;
        final items = snap.docs
            .map((d) => {'id': d.id, 'source': 'telefon', 'category': 'TELEFON', ...d.data()})
            .where((d) {
              final shopId = (d['shopID'] ?? '').toString().toUpperCase();
              final status = (d['status'] ?? '').toString().toUpperCase();
              return shopId == _shopID && status != 'SOLD';
            })
            .toList();
        setState(() {
          _products = [..._products.where((d) => d['source'] != 'telefon'), ...items];
        });
      }));
    } else {
      // Ensure no telefon items are in list
      _products = _products.where((d) => d['source'] != 'telefon').toList();
    }
  }

  void _listenCustomers() {
    _subs.add(_db.collection('repairs_$_ownerID').snapshots().listen((snap) {
      final custSeen = <String>{};
      final custs = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) {
          final tel = (d['tel'] ?? '').toString();
          if (tel.isNotEmpty && tel != '-' && !custSeen.contains(tel)) {
            custSeen.add(tel);
            custs.add({'nama': d['nama'] ?? '', 'tel': tel});
          }
        }
      }
      if (mounted) setState(() => _existingCustomers = custs);
    }));
  }

  Future<void> _loadStaff() async {
    try {
      final snap = await _db.collection('shops_$_ownerID').doc(_shopID).get();
      if (snap.exists) {
        final data = snap.data() ?? {};
        // Staff list
        final staffRaw = data['staffList'];
        if (staffRaw is List) {
          _staffList = staffRaw
              .map((s) => s is String ? s : (s['name'] ?? s['nama'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList();
          if (_staffList.isNotEmpty && mounted) setState(() => _staff = _staffList.first);
        }
        // Shop info for receipt
        _shopInfo = {
          'shopName': data['shopName'] ?? data['namaKedai'] ?? 'RMS PRO',
          'address': data['address'] ?? data['alamat'] ?? '',
          'phone': data['phone'] ?? data['ownerContact'] ?? '-',
          'notaInvoice': _notaKaki,
        };
      }
    } catch (_) {}
  }

  void _snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── CART ───

  void _addToCart(Map<String, dynamic> product) {
    if (_staff.isEmpty) {
      _snack('Sila pilih staff dahulu!', err: true);
      _showStaffPicker();
      return;
    }
    setState(() {
      final idx = _cart.indexWhere((c) => c['id'] == product['id']);
      if (idx >= 0) {
        _cart[idx]['qty'] = (_cart[idx]['qty'] as int) + 1;
      } else {
        _cart.add({
          'id': product['id'],
          'nama': (product['nama'] ?? '').toString(),
          'kod': (product['kod'] ?? '').toString(),
          'harga': (product['jual'] as num?) ?? 0,
          'qty': 1,
          'source': product['source'],
        });
      }
      _checkoutStep = 0;
    });
  }

  void _updateQty(int idx, int delta) {
    setState(() {
      final newQty = (_cart[idx]['qty'] as int) + delta;
      if (newQty <= 0) {
        _cart.removeAt(idx);
        if (_cart.isEmpty) _checkoutStep = 0;
      } else {
        _cart[idx]['qty'] = newQty;
      }
    });
  }

  void _showDiscountDialog(int cartIndex) {
    final item = _cart[cartIndex];
    final ctrl = TextEditingController(text: ((item['diskaun'] as num?) ?? 0) > 0 ? (item['diskaun'] as num).toStringAsFixed(2) : '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Diskaun — ${item['nama']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: 'RM ', prefixStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.orange),
            hintText: '0.00', hintStyle: const TextStyle(color: AppColors.textDim),
            filled: true, fillColor: AppColors.bg, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () { setState(() => _cart[cartIndex]['diskaun'] = 0.0); Navigator.pop(ctx); },
              child: const Text('RESET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.red))),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text) ?? 0.0;
              setState(() => _cart[cartIndex]['diskaun'] = val);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('SIMPAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ─── PAYMENT SHEET ───

  void _showPaymentSheet() {
    if (_cart.isEmpty) return _snack('Cart kosong!', err: true);
    if (_staff.isEmpty) return _snack('Sila pilih staff', err: true);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              const FaIcon(FontAwesomeIcons.cashRegister, size: 14, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              const Text('CARA BAYARAN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('RM ${_cartTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.green)),
            ]),
            const SizedBox(height: 14),

            // Payment method grid
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                ..._paymentMethods.map((m) {
                  final color = _paymentColors[m] ?? AppColors.textDim;
                  final selected = _caraBayaran == m;
                  return GestureDetector(
                    onTap: () => setSheet(() => setState(() => _caraBayaran = m)),
                    child: Container(
                      width: (MediaQuery.of(ctx).size.width - 32 - 16) / 3,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected ? color.withValues(alpha: 0.12) : AppColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? color : AppColors.border, width: selected ? 2 : 1),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        FaIcon(_paymentIcons[m] ?? FontAwesomeIcons.moneyBill, size: 18, color: color),
                        const SizedBox(height: 6),
                        Text(m, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: selected ? color : AppColors.textSub)),
                      ]),
                    ),
                  );
                }),
                // SAVE BILL tile — simpan cart sebagai draf, bukan payment
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveBillAsDraft();
                  },
                  child: Container(
                    width: (MediaQuery.of(ctx).size.width - 32 - 16) / 3,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple, width: 1),
                    ),
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      FaIcon(FontAwesomeIcons.floppyDisk, size: 18, color: Colors.purple),
                      SizedBox(height: 6),
                      Text('SAVE BILL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.purple)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // QR details
            if (_caraBayaran == 'QR')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3))),
                child: Column(children: [
                  if (_qrImageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(_qrImageUrl, width: 180, height: 180, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const FaIcon(FontAwesomeIcons.imagePortrait, size: 40, color: AppColors.textDim)),
                    )
                  else
                    const Column(children: [
                      FaIcon(FontAwesomeIcons.qrcode, size: 36, color: AppColors.textDim),
                      SizedBox(height: 6),
                      Text('Tiada QR — Upload di Settings (gear)', style: TextStyle(fontSize: 9, color: AppColors.textDim)),
                    ]),
                ]),
              ),

            // PayWave (NFC) details
            if (_caraBayaran == 'PAYWAVE')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.blue.withValues(alpha: 0.3))),
                child: Column(children: [
                  const Text('NFC PAYWAVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.blue, letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  FaIcon(
                    _nfcScanning ? FontAwesomeIcons.wifi : FontAwesomeIcons.creditCard,
                    size: 40,
                    color: _nfcScanning ? AppColors.blue : AppColors.textDim,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _nfcScanning
                        ? 'Tap kad/telefon ke belakang peranti...'
                        : (_nfcTagId.isNotEmpty ? 'KAD DIKESAN' : 'Tekan butang untuk mula scan'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  if (_nfcTagId.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.blue.withValues(alpha: 0.4))),
                      child: Text('ID: $_nfcTagId',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                  ],
                  if (_nfcStatus.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(_nfcStatus, style: const TextStyle(fontSize: 9, color: AppColors.textDim)),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: OutlinedButton.icon(
                      onPressed: _nfcScanning
                          ? () => _stopNfcScan(setSheet)
                          : () => _startNfcScan(setSheet),
                      icon: FaIcon(
                        _nfcScanning ? FontAwesomeIcons.stop : FontAwesomeIcons.wifi,
                        size: 12,
                        color: AppColors.blue,
                      ),
                      label: Text(
                        _nfcScanning ? 'BERHENTI SCAN' : 'MULA SCAN NFC',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.blue, letterSpacing: 0.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.blue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),

            // Transfer details
            if (_caraBayaran == 'TRANSFER')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                child: Column(children: [
                  const Text('MAKLUMAT AKAUN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.yellow, letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  if (_bankName.isNotEmpty || _bankAccount.isNotEmpty) ...[
                    if (_bankName.isNotEmpty)
                      Text(_bankName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    if (_bankOwnerName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_bankOwnerName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    ],
                    const SizedBox(height: 8),
                    if (_bankAccount.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4))),
                        child: Text(_bankAccount,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      ),
                  ] else
                    const Column(children: [
                      FaIcon(FontAwesomeIcons.buildingColumns, size: 30, color: AppColors.textDim),
                      SizedBox(height: 6),
                      Text('Tiada akaun — Setup di Settings (gear)', style: TextStyle(fontSize: 9, color: AppColors.textDim)),
                    ]),
                ]),
              ),

            const SizedBox(height: 14),

            // Confirm button
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : () {
                  Navigator.pop(ctx);
                  _prosesBayaran();
                },
                icon: const FaIcon(FontAwesomeIcons.check, size: 13, color: Colors.white),
                label: Text('SAHKAN BAYARAN • $_caraBayaran',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _paymentColors[_caraBayaran] ?? AppColors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── NFC / PAYWAVE ───
  // Fungsi asas NFC — akan diintegrasi dengan payment gateway 3rd party kemudian.
  // Buat masa ini hanya kesan tag/kad dan simpan ID.

  Future<void> _startNfcScan(StateSetter setSheet) async {
    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        setSheet(() => setState(() {
              _nfcStatus = availability == NFCAvailability.disabled
                  ? 'NFC dimatikan — sila aktifkan di Settings'
                  : 'NFC tidak disokong pada peranti ini';
              _nfcScanning = false;
            }));
        return;
      }
      setSheet(() => setState(() {
            _nfcScanning = true;
            _nfcTagId = '';
            _nfcStatus = 'Tap kad / telefon...';
          }));

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'Terlalu banyak kad dikesan',
        iosAlertMessage: 'Tap kad PayWave',
      );
      final id = tag.id.isNotEmpty ? tag.id.toUpperCase() : DateTime.now().millisecondsSinceEpoch.toString();

      await FlutterNfcKit.finish(iosAlertMessage: 'Berjaya');
      setSheet(() => setState(() {
            _nfcTagId = id;
            _nfcStatus = 'Kad dikesan — sedia untuk bayar';
            _nfcScanning = false;
          }));
    } catch (e) {
      try { await FlutterNfcKit.finish(); } catch (_) {}
      setSheet(() => setState(() {
            _nfcScanning = false;
            _nfcStatus = 'Ralat NFC: $e';
          }));
    }
  }

  Future<void> _stopNfcScan(StateSetter setSheet) async {
    try {
      await FlutterNfcKit.finish();
    } catch (_) {}
    setSheet(() => setState(() {
          _nfcScanning = false;
          _nfcStatus = 'Scan dibatalkan';
        }));
  }

  // ─── SAVE BILL (DRAFT) ───
  // Simpan cart semasa sebagai bil tertangguh. Boleh dibuka semula dari history.

  Future<void> _saveBillAsDraft() async {
    if (_cart.isEmpty) return _snack('Cart kosong!', err: true);
    if (_staff.isEmpty) return _snack('Sila pilih staff', err: true);

    final siri = 'DRAFT${DateTime.now().millisecondsSinceEpoch}';
    final custName = _custNameCtrl.text.trim().isNotEmpty ? _custNameCtrl.text.trim().toUpperCase() : _custType;
    final custTel = _custTelCtrl.text.trim().isNotEmpty ? _custTelCtrl.text.trim() : '-';
    final custAlamat = _custAlamatCtrl.text.trim().isNotEmpty ? _custAlamatCtrl.text.trim() : '-';

    final data = {
      'siri': siri,
      'shopID': _shopID,
      'staff': _staff,
      'cart': _cart.map((c) => {
            'id': c['id'],
            'nama': c['nama'],
            'kod': c['kod'],
            'harga': (c['harga'] as num).toDouble(),
            'qty': c['qty'],
            'diskaun': ((c['diskaun'] as num?) ?? 0).toDouble(),
            'source': c['source'],
          }).toList(),
      'total': _cartTotal,
      'nama': custName,
      'tel': custTel,
      'alamat': custAlamat,
      'cust_type': _custType,
      'status': 'SAVED',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'tarikh': DateFormat("yyyy-MM-dd HH:mm").format(DateTime.now()),
    };

    try {
      await _db.collection('saved_bills_$_ownerID').doc(siri).set(data);
      _snack('Bil disimpan: $siri');
      _resetAll();
    } catch (e) {
      _snack('Gagal simpan: $e', err: true);
    }
  }

  void _showSavedBillsHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Row(children: [
              FaIcon(FontAwesomeIcons.clockRotateLeft, size: 14, color: Colors.purple),
              SizedBox(width: 8),
              Text('BIL TERSIMPAN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db.collection('saved_bills_$_ownerID')
                    .where('shopID', isEqualTo: _shopID)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.purple));
                  }
                  final docs = (snap.data?.docs ?? [])
                    ..sort((a, b) => ((b.data() as Map)['timestamp'] ?? 0).compareTo((a.data() as Map)['timestamp'] ?? 0));
                  if (docs.isEmpty) {
                    return const Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        FaIcon(FontAwesomeIcons.inbox, size: 36, color: AppColors.textDim),
                        SizedBox(height: 8),
                        Text('Tiada bil tersimpan', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                      ]),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      final total = (d['total'] as num?)?.toDouble() ?? 0;
                      final cart = (d['cart'] as List?) ?? [];
                      final itemCount = cart.fold<int>(0, (s, c) => s + ((c['qty'] as int?) ?? 1));
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text('${d['nama'] ?? '-'}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Text('RM ${total.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.green)),
                            ]),
                            const SizedBox(height: 4),
                            Text('${d['tarikh'] ?? '-'} • $itemCount item • ${d['staff'] ?? '-'}',
                                style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _loadSavedBill(d, docs[i].id);
                                  },
                                  icon: const FaIcon(FontAwesomeIcons.folderOpen, size: 11, color: Colors.purple),
                                  label: const Text('BUKA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.purple)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.purple),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 46, height: 36,
                                child: OutlinedButton(
                                  onPressed: () => _deleteSavedBill(docs[i].id),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.red),
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const FaIcon(FontAwesomeIcons.trash, size: 11, color: AppColors.red),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _loadSavedBill(Map<String, dynamic> d, String docId) {
    final cart = (d['cart'] as List?) ?? [];
    setState(() {
      _cart.clear();
      for (final c in cart) {
        _cart.add({
          'id': c['id'],
          'nama': c['nama'],
          'kod': c['kod'],
          'harga': (c['harga'] as num?) ?? 0,
          'qty': (c['qty'] as int?) ?? 1,
          'diskaun': ((c['diskaun'] as num?) ?? 0).toDouble(),
          'source': c['source'],
        });
      }
      _custNameCtrl.text = (d['nama'] ?? '').toString() == _custType ? '' : (d['nama'] ?? '').toString();
      _custTelCtrl.text = (d['tel'] ?? '').toString() == '-' ? '' : (d['tel'] ?? '').toString();
      _custAlamatCtrl.text = (d['alamat'] ?? '').toString() == '-' ? '' : (d['alamat'] ?? '').toString();
      _custType = (d['cust_type'] ?? 'WALK-IN').toString();
      if ((d['staff'] ?? '').toString().isNotEmpty) _staff = d['staff'];
      _checkoutStep = 0;
    });
    _db.collection('saved_bills_$_ownerID').doc(docId).delete().catchError((_) {});
    _snack('Bil dibuka semula');
  }

  Future<void> _deleteSavedBill(String docId) async {
    try {
      await _db.collection('saved_bills_$_ownerID').doc(docId).delete();
      _snack('Bil dipadam');
    } catch (e) {
      _snack('Gagal padam: $e', err: true);
    }
  }

  // ─── BAYAR ───

  Future<void> _prosesBayaran() async {
    if (_cart.isEmpty) return _snack('Cart kosong!', err: true);
    if (_staff.isEmpty) return _snack('Sila pilih staff', err: true);

    setState(() => _isSaving = true);
    final custName = _custNameCtrl.text.trim().isNotEmpty ? _custNameCtrl.text.trim().toUpperCase() : _custType;
    final custTel = _custTelCtrl.text.trim().isNotEmpty ? _custTelCtrl.text.trim() : '-';
    final custAlamat = _custAlamatCtrl.text.trim().isNotEmpty ? _custAlamatCtrl.text.trim() : '-';
    final siri = (10000000 + Random().nextInt(90000000)).toString();
    final tarikhNow = DateTime.now();

    final itemsArray = _cart.map((c) => {
      'nama': (c['nama'] as String).toUpperCase(),
      'qty': c['qty'],
      'harga': (c['harga'] as num).toDouble(),
    }).toList();
    final itemNames = itemsArray.map((i) => i['nama'] as String).join(', ');

    final data = {
      'siri': siri, 'receiptNo': siri, 'shopID': _shopID,
      'nama': custName, 'pelanggan': custName,
      'tel': custTel, 'telefon': custTel, 'tel_wasap': custTel, 'wasap': custTel,
      'alamat': custAlamat,
      'model': itemNames.length > 50 ? '${itemNames.substring(0, 50)}...' : itemNames,
      'kerosakan': '-', 'items_array': itemsArray,
      'tarikh': DateFormat("yyyy-MM-dd'T'HH:mm").format(tarikhNow),
      'harga': _cartTotal.toStringAsFixed(2),
      'deposit': '0', 'diskaun': '0', 'tambahan': '0',
      'total': _cartTotal.toStringAsFixed(2), 'baki': '0',
      'voucher_generated': '-', 'voucher_used': '-', 'voucher_used_amt': 0,
      'payment_status': 'PAID', 'cara_bayaran': _caraBayaran,
      'catatan': '-', 'jenis_servis': 'JUALAN',
      'staff_terima': _staff, 'staff_repair': _staff, 'staff_serah': _staff,
      'password': '-', 'cust_type': _custType == 'ONLINE' ? 'ONLINE' : (custName == _custType ? _custType : 'NEW CUST'),
      'status': 'COMPLETED', 'timestamp': tarikhNow.millisecondsSinceEpoch,
    };

    try {
      await Future.wait([
        _db.collection('jualan_pantas_$_ownerID').doc(siri).set(data),
        _db.collection('kewangan_$_ownerID').doc(siri).set({...data, 'jenis': 'JUALAN PANTAS', 'amount': _cartTotal}),
        _db.collection('repairs_$_ownerID').doc(siri).set(data),
      ]);

      if (_autoPrint) {
        final printer = PrinterService();
        final printed = await printer.printReceipt(data, _shopInfo);
        // Cash only → kick drawer
        if (printed && _autoDrawer && _caraBayaran == 'CASH') {
          await printer.kickCashDrawer();
        }
      }

      if (mounted) {
        _snack('Jualan #$siri Berjaya!');
        _showSuccessSheet(data, siri);
      }
    } catch (e) {
      _snack('Gagal: $e', err: true);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  void _resetAll() {
    setState(() {
      _cart.clear();
      _custNameCtrl.clear();
      _custTelCtrl.clear();
      _custAlamatCtrl.clear();
      _caraBayaran = 'CASH';
      _custType = 'WALK-IN';
      _checkoutStep = 0;
    });
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var list = _products;
    if (_selectedCategory != 'SEMUA') {
      list = list.where((p) => (p['category'] ?? '').toString().toUpperCase() == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((p) =>
          (p['nama'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
          (p['kod'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
    }
    return list;
  }

  // ══════════════════════════════════════
  // BUILD — VERTICAL LAYOUT (product atas, cart bawah)
  // ══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── TOP BAR ──
      _buildTopBar(),
      // ── PRODUCT AREA (expands to fill) ──
      Expanded(child: _buildProductPanel()),
      // ── BOTTOM: CART / PAYMENT ──
      _buildBottomPanel(),
    ]);
  }

  // ─── TOP BAR ───

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        // POS badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            FaIcon(FontAwesomeIcons.cashRegister, size: 11, color: AppColors.red),
            SizedBox(width: 6),
            Text('POS', style: TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ]),
        ),
        const SizedBox(width: 8),
        // Staff (dikecilkan)
        Flexible(
          child: GestureDetector(
            onTap: _showStaffPicker,
            child: Container(
              height: 30,
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.userTag, size: 8, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(_staff.isNotEmpty ? _staff : 'Pilih Staff',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _staff.isNotEmpty ? AppColors.textPrimary : AppColors.textDim),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 3),
                const FaIcon(FontAwesomeIcons.chevronDown, size: 6, color: AppColors.textDim),
              ]),
            ),
          ),
        ),
        const Spacer(),
        // Save Bill History button
        GestureDetector(
          onTap: _showSavedBillsHistory,
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.purple.withValues(alpha: 0.4)),
            ),
            child: const Center(child: FaIcon(FontAwesomeIcons.clockRotateLeft, size: 12, color: Colors.purple)),
          ),
        ),
        const SizedBox(width: 4),
        // Gear icon
        GestureDetector(
          onTap: _showSettingsSheet,
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
            child: const Center(child: FaIcon(FontAwesomeIcons.gear, size: 13, color: AppColors.textMuted)),
          ),
        ),
      ]),
    );
  }

  // ─── PRODUCT PANEL ───

  Widget _buildProductPanel() {
    final filtered = _filteredProducts;
    return Container(
      color: AppColors.bg,
      child: Column(children: [
        // Search + category
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          color: Colors.white,
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Cari produk...', hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
                  prefixIcon: const Padding(padding: EdgeInsets.only(left: 8, right: 6),
                      child: FaIcon(FontAwesomeIcons.magnifyingGlass, size: 11, color: AppColors.textMuted)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  filled: true, fillColor: AppColors.bg, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                ),
              )),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _QSBarcodeScannerPage(onScanned: (code) {
                    Navigator.pop(context);
                    _searchCtrl.text = code;
                  }),
                )),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary, borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: FaIcon(FontAwesomeIcons.barcode, size: 14, color: Colors.white)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _categories.map((cat) {
                  final sel = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.textPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.textPrimary : AppColors.border),
                        ),
                        child: Text(cat, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppColors.textMuted)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
        // Count
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Align(alignment: Alignment.centerLeft,
              child: Text('${filtered.length} PRODUK', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.textDim, letterSpacing: 1))),
        ),
        // Grid
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.boxOpen, size: 28, color: AppColors.textDim.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  const Text('Tiada produk', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
                ]))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, childAspectRatio: 0.9,
                    crossAxisSpacing: 6, mainAxisSpacing: 6,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildProductTile(filtered[i]),
                ),
        ),
      ]),
    );
  }

  Widget _buildProductTile(Map<String, dynamic> product) {
    final nama = (product['nama'] ?? '').toString();
    final kod = (product['kod'] ?? '').toString();
    final harga = ((product['jual'] as num?) ?? 0).toDouble();
    final stok = product['qty'] ?? 0;
    final isAcc = product['source'] == 'accessories';
    final cartIdx = _cart.indexWhere((c) => c['id'] == product['id']);
    final inCart = cartIdx >= 0;
    final cartQty = inCart ? _cart[cartIdx]['qty'] as int : 0;

    return GestureDetector(
      onTap: () => _addToCart(product),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: inCart ? AppColors.green.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: inCart ? AppColors.green.withValues(alpha: 0.4) : AppColors.border, width: inCart ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isAcc ? AppColors.blue.withValues(alpha: 0.1) : AppColors.yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(isAcc ? 'ACC' : 'SVC', style: TextStyle(fontSize: 6, fontWeight: FontWeight.w900, color: isAcc ? AppColors.blue : AppColors.yellow)),
            ),
            if (inCart)
              Container(width: 20, height: 20, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                  child: Center(child: Text('$cartQty', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)))),
          ]),
          if (kod.isNotEmpty)
            Text(kod, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(nama, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('RM${harga.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.green)),
            Text('$stok', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: AppColors.textDim)),
          ]),
        ]),
      ),
    );
  }

  // ─── BOTTOM PANEL (Cart → Payment) ───

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Tab header ──
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              FaIcon(_checkoutStep == 0 ? FontAwesomeIcons.cartShopping : FontAwesomeIcons.creditCard,
                  size: 11, color: AppColors.textPrimary),
              const SizedBox(width: 6),
              Text(_checkoutStep == 0 ? 'CART' : 'BAYARAN',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              if (_cart.isNotEmpty && _checkoutStep == 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(8)),
                  child: Text('$_cartCount', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
              ],
            ]),
            Row(children: [
              if (_checkoutStep == 1)
                GestureDetector(
                  onTap: () => setState(() => _checkoutStep = 0),
                  child: const Row(children: [
                    FaIcon(FontAwesomeIcons.arrowLeft, size: 8, color: AppColors.textMuted),
                    SizedBox(width: 4),
                    Text('KEMBALI', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
                  ]),
                ),
              if (_cart.isNotEmpty && _checkoutStep == 0)
                GestureDetector(
                  onTap: _resetAll,
                  child: const Text('KOSONG', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.red)),
                ),
            ]),
          ]),
        ),
        Container(margin: const EdgeInsets.only(top: 6), height: 1, color: AppColors.border),

        // ── Content ──
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: SizedBox(
            height: _cart.isEmpty ? 60 : (_checkoutStep == 0 ? _cartListHeight : _paymentHeight),
            child: _checkoutStep == 0 ? _buildCartList() : _buildPaymentSection(),
          ),
        ),

        // ── Customer + Total + Button ──
        _buildBottomBar(),
      ]),
    );
  }

  double get _cartListHeight {
    final h = (_cart.length * 62.0).clamp(60.0, 180.0);
    return h;
  }

  double get _paymentHeight => _caraBayaran == 'QR' || _caraBayaran == 'TRANSFER' ? 220.0 : 120.0;

  // ─── CART LIST ───

  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return const Center(child: Text('Tap produk untuk tambah', style: TextStyle(color: AppColors.textDim, fontSize: 10)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      itemCount: _cart.length,
      itemBuilder: (_, i) {
        final item = _cart[i];
        final nama = item['nama'] as String;
        final harga = (item['harga'] as num).toDouble();
        final qty = item['qty'] as int;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            // Name + price + discount
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nama, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Row(children: [
                Text('RM ${harga.toStringAsFixed(2)}', style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
                if ((item['diskaun'] as num?) != null && (item['diskaun'] as num) > 0) ...[
                  const SizedBox(width: 4),
                  Text('-RM ${(item['diskaun'] as num).toStringAsFixed(2)}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.orange)),
                ],
              ]),
            ])),
            // Discount button
            GestureDetector(
              onTap: () => _showDiscountDialog(i),
              child: Container(
                width: 24, height: 24, margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: (item['diskaun'] as num?) != null && (item['diskaun'] as num) > 0
                      ? AppColors.orange.withValues(alpha: 0.1) : AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: (item['diskaun'] as num?) != null && (item['diskaun'] as num) > 0
                      ? AppColors.orange.withValues(alpha: 0.3) : AppColors.border),
                ),
                child: Center(child: FaIcon(FontAwesomeIcons.percent, size: 8,
                    color: (item['diskaun'] as num?) != null && (item['diskaun'] as num) > 0
                        ? AppColors.orange : AppColors.textDim)),
              ),
            ),
            // Qty
            _qtyBtn(FontAwesomeIcons.minus, () => _updateQty(i, -1), AppColors.red),
            Container(width: 26, alignment: Alignment.center,
                child: Text('$qty', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
            _qtyBtn(FontAwesomeIcons.plus, () => _updateQty(i, 1), AppColors.green),
            const SizedBox(width: 8),
            // Subtotal
            SizedBox(width: 55, child: Text('RM ${(((harga - ((item['diskaun'] as num?) ?? 0).toDouble()) * qty)).toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.green))),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() { _cart.removeAt(i); if (_cart.isEmpty) _checkoutStep = 0; }),
              child: const FaIcon(FontAwesomeIcons.xmark, size: 9, color: AppColors.red),
            ),
          ]),
        );
      },
    );
  }

  // ─── PAYMENT SECTION ───

  Widget _buildPaymentSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Payment dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _caraBayaran,
              isExpanded: true,
              dropdownColor: Colors.white,
              icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 9, color: AppColors.textDim),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              items: _paymentMethods.map((m) => DropdownMenuItem(
                value: m,
                child: Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: (_paymentColors[m] ?? AppColors.textDim).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Center(child: FaIcon(_paymentIcons[m] ?? FontAwesomeIcons.moneyBill, size: 10, color: _paymentColors[m] ?? AppColors.textDim)),
                  ),
                  const SizedBox(width: 8),
                  Text(m, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _paymentColors[m] ?? AppColors.textSub)),
                ]),
              )).toList(),
              onChanged: (v) => setState(() => _caraBayaran = v ?? 'CASH'),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // QR display
        if (_caraBayaran == 'QR')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3))),
            child: Column(children: [
              if (_qrImageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(_qrImageUrl, width: 120, height: 120, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const FaIcon(FontAwesomeIcons.imagePortrait, size: 30, color: AppColors.textDim)),
                )
              else
                Column(children: [
                  const FaIcon(FontAwesomeIcons.qrcode, size: 24, color: AppColors.textDim),
                  const SizedBox(height: 4),
                  const Text('Tiada QR — Upload di Settings (gear)', style: TextStyle(fontSize: 8, color: AppColors.textDim)),
                ]),
              const SizedBox(height: 6),
              Text('RM ${_cartTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.cyan)),
            ]),
          ),

        // Transfer display
        if (_caraBayaran == 'TRANSFER')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
            child: Column(children: [
              const Text('MAKLUMAT AKAUN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.yellow)),
              const SizedBox(height: 8),
              if (_bankName.isNotEmpty || _bankAccount.isNotEmpty) ...[
                if (_bankName.isNotEmpty)
                  Text(_bankName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSub)),
                if (_bankOwnerName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_bankOwnerName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 6),
                if (_bankAccount.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                    child: Text(_bankAccount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
              ] else
                const Column(children: [
                  FaIcon(FontAwesomeIcons.buildingColumns, size: 20, color: AppColors.textDim),
                  SizedBox(height: 4),
                  Text('Tiada akaun — Setup di Settings (gear)', style: TextStyle(fontSize: 8, color: AppColors.textDim)),
                ]),
              const SizedBox(height: 6),
              Text('RM ${_cartTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.yellow)),
            ]),
          ),
      ]),
    );
  }

  // ─── BOTTOM BAR ───

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Total + buttons
        Row(children: [
          // Back button (when in payment step)
          if (_checkoutStep == 1) ...[
            GestureDetector(
              onTap: () => setState(() => _checkoutStep = 0),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: const Center(child: FaIcon(FontAwesomeIcons.arrowLeft, size: 13, color: AppColors.textMuted)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // + Customer button
          GestureDetector(
            onTap: _showCustomerSheet,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: const Center(child: FaIcon(FontAwesomeIcons.userPlus, size: 13, color: AppColors.textMuted)),
            ),
          ),
          const SizedBox(width: 8),
          // Total
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TOTAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.textDim)),
              Text('RM ${_cartTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.green)),
            ]),
          ),
          // Action button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
                    onPressed: (_cart.isEmpty || _isSaving) ? null : _showPaymentSheet,
                    icon: _isSaving
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const FaIcon(FontAwesomeIcons.cashRegister, size: 10),
                    label: Text(_isSaving ? 'PROSES...' : 'PAY',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green, foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.green.withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.white60,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
          ),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════
  // SHEETS & DIALOGS
  // ══════════════════════════════════════

  // ─── SETTINGS GEAR ───

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            const Row(children: [
              FaIcon(FontAwesomeIcons.gear, size: 14, color: AppColors.textPrimary),
              SizedBox(width: 8),
              Text('TETAPAN POS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 16),

            // Auto Print
            _settingToggle('Auto Print Resit 80mm', 'Cetak resit automatik selepas bayaran', FontAwesomeIcons.print, AppColors.blue, _autoPrint, (v) {
              setState(() => _autoPrint = v);
              setSheet(() {});
              _saveSettings();
            }),
            const SizedBox(height: 8),

            // Auto Cash Drawer
            _settingToggle('Auto Buka Cash Drawer', 'Buka drawer selepas cetak (CASH sahaja)', FontAwesomeIcons.cashRegister, AppColors.green, _autoDrawer, (v) {
              setState(() => _autoDrawer = v);
              setSheet(() {});
              _saveSettings();
            }),
            const SizedBox(height: 8),

            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final printer = PrinterService();
                  final ok = await printer.kickCashDrawer();
                  if (!mounted) return;
                  _snack(ok ? 'Cash drawer dibuka' : 'Gagal buka drawer — semak printer');
                },
                icon: const FaIcon(FontAwesomeIcons.cashRegister, size: 12, color: Colors.white),
                label: const Text('PUSH / BUKA DRAWER',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Nota Kaki Resit
            const Align(alignment: Alignment.centerLeft,
                child: Text('NOTA KAKI RESIT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textDim, letterSpacing: 0.5))),
            const SizedBox(height: 8),
            TextField(
              controller: TextEditingController(text: _notaKaki),
              onChanged: (v) { _notaKaki = v; _saveSettings(); _shopInfo['notaInvoice'] = v; },
              maxLines: 2,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Nota kaki untuk resit...', hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 10, right: 8, bottom: 14),
                    child: FaIcon(FontAwesomeIcons.noteSticky, size: 11, color: AppColors.textMuted)),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                filled: true, fillColor: AppColors.bg, isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),

            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),

            // QR Upload
            const Align(alignment: Alignment.centerLeft,
                child: Text('GAMBAR QR PAYMENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textDim, letterSpacing: 0.5))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _uploadImage(setSheet),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3))),
                child: _qrImageUrl.isNotEmpty
                    ? Column(children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8),
                            child: Image.network(_qrImageUrl, height: 100, fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const FaIcon(FontAwesomeIcons.imagePortrait, size: 30, color: AppColors.textDim))),
                        const SizedBox(height: 6),
                        const Text('Tap untuk tukar', style: TextStyle(fontSize: 8, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                      ])
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        FaIcon(FontAwesomeIcons.cloudArrowUp, size: 14, color: AppColors.cyan),
                        SizedBox(width: 8),
                        Text('Upload Gambar QR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                      ]),
              ),
            ),
            const SizedBox(height: 14),

            // Bank details
            const Align(alignment: Alignment.centerLeft,
                child: Text('MAKLUMAT BANK TRANSFER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textDim, letterSpacing: 0.5))),
            const SizedBox(height: 8),
            _settingInput(_bankName, 'Nama Bank (cth: Maybank)', FontAwesomeIcons.buildingColumns, AppColors.yellow, (v) {
              _bankName = v;
              _saveSettings();
            }),
            const SizedBox(height: 8),
            _settingInput(_bankOwnerName, 'Nama Pemilik Akaun', FontAwesomeIcons.user, AppColors.yellow, (v) {
              _bankOwnerName = v;
              _saveSettings();
            }),
            const SizedBox(height: 8),
            _settingInput(_bankAccount, 'No. Akaun Bank', FontAwesomeIcons.hashtag, AppColors.yellow, (v) {
              _bankAccount = v;
              _saveSettings();
            }, keyboard: TextInputType.number),
            const SizedBox(height: 6),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingToggle(String title, String sub, IconData icon, Color color, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Center(child: FaIcon(icon, size: 12, color: color))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          Text(sub, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
        ])),
        SizedBox(height: 24,
            child: Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: color)),
      ]),
    );
  }

  Widget _settingInput(String initialValue, String hint, IconData icon, Color color, ValueChanged<String> onChanged, {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: TextEditingController(text: initialValue),
      onChanged: onChanged, keyboardType: keyboard,
      style: const TextStyle(fontSize: 11),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
        prefixIcon: Padding(padding: const EdgeInsets.only(left: 10, right: 8), child: FaIcon(icon, size: 11, color: color)),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true, fillColor: AppColors.bg, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  Future<void> _uploadImage(StateSetter setSheet) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
      if (picked == null) return;
      _snack('Uploading...');
      final ref = FirebaseStorage.instance.ref().child('pos_settings/$_ownerID/qr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      setState(() => _qrImageUrl = url);
      setSheet(() {});
      _saveSettings();
      _snack('QR berjaya dimuat naik');
    } catch (e) {
      _snack('Gagal upload: $e', err: true);
    }
  }

  // ─── CUSTOMER SHEET ───

  void _showCustomerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: const [
            FaIcon(FontAwesomeIcons.userPlus, size: 14, color: AppColors.blue),
            SizedBox(width: 8),
            Text('MAKLUMAT PELANGGAN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            SizedBox(width: 6),
            Text('(Pilihan)', style: TextStyle(fontSize: 10, color: AppColors.textDim)),
          ]),
          const SizedBox(height: 14),
          // Name autocomplete
          Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (v) => v.text.isEmpty
                ? const Iterable.empty()
                : _existingCustomers
                    .where((c) => (c['nama'] ?? '').toString().toLowerCase().contains(v.text.toLowerCase()) ||
                        (c['tel'] ?? '').toString().contains(v.text))
                    .take(5),
            displayStringForOption: (o) => '${o['nama']} (${o['tel']})',
            onSelected: (o) {
              _custNameCtrl.text = (o['nama'] ?? '').toString();
              _custTelCtrl.text = (o['tel'] ?? '').toString();
            },
            fieldViewBuilder: (_, ctrl, fn, __) {
              if (ctrl.text.isEmpty && _custNameCtrl.text.isNotEmpty) ctrl.text = _custNameCtrl.text;
              return _sheetInput(ctrl, fn, 'Nama Pelanggan', FontAwesomeIcons.user, onChanged: (v) => _custNameCtrl.text = v);
            },
          ),
          const SizedBox(height: 8),
          _sheetInputSimple(_custTelCtrl, 'No. Telefon', FontAwesomeIcons.phone, keyboard: TextInputType.phone),
          const SizedBox(height: 8),
          _sheetInputSimple(_custAlamatCtrl, 'Alamat (Pilihan)', FontAwesomeIcons.locationDot),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: SizedBox(height: 42, child: OutlinedButton(
              onPressed: () { _custNameCtrl.clear(); _custTelCtrl.clear(); _custAlamatCtrl.clear();
                setState(() => _custType = 'WALK-IN'); Navigator.pop(ctx); },
              style: OutlinedButton.styleFrom(side: BorderSide(color: _custType == 'WALK-IN' ? AppColors.green : AppColors.border),
                  backgroundColor: _custType == 'WALK-IN' ? AppColors.green.withValues(alpha: 0.06) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FaIcon(FontAwesomeIcons.personWalking, size: 10, color: _custType == 'WALK-IN' ? AppColors.green : AppColors.textMuted),
                const SizedBox(width: 6),
                Text('WALK-IN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: _custType == 'WALK-IN' ? AppColors.green : AppColors.textMuted)),
              ]),
            ))),
            const SizedBox(width: 6),
            Expanded(child: SizedBox(height: 42, child: OutlinedButton(
              onPressed: () {
                setState(() => _custType = 'ONLINE'); Navigator.pop(ctx);
              },
              style: OutlinedButton.styleFrom(side: BorderSide(color: _custType == 'ONLINE' ? AppColors.cyan : AppColors.border),
                  backgroundColor: _custType == 'ONLINE' ? AppColors.cyan.withValues(alpha: 0.06) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FaIcon(FontAwesomeIcons.globe, size: 10, color: _custType == 'ONLINE' ? AppColors.cyan : AppColors.textMuted),
                const SizedBox(width: 6),
                Text('ONLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: _custType == 'ONLINE' ? AppColors.cyan : AppColors.textMuted)),
              ]),
            ))),
            const SizedBox(width: 6),
            Expanded(child: SizedBox(height: 42, child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); setState(() {}); },
              icon: const FaIcon(FontAwesomeIcons.check, size: 11),
              label: const Text('SIMPAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
          ]),
        ]),
      ),
    );
  }

  Widget _sheetInput(TextEditingController ctrl, FocusNode? fn, String hint, IconData icon, {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl, focusNode: fn, onChanged: onChanged,
      style: const TextStyle(fontSize: 11),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
        prefixIcon: Padding(padding: const EdgeInsets.only(left: 10, right: 8), child: FaIcon(icon, size: 11, color: AppColors.textMuted)),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true, fillColor: AppColors.bg, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  Widget _sheetInputSimple(TextEditingController ctrl, String hint, IconData icon, {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl, keyboardType: keyboard,
      style: const TextStyle(fontSize: 11),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 10),
        prefixIcon: Padding(padding: const EdgeInsets.only(left: 10, right: 8), child: FaIcon(icon, size: 11, color: AppColors.textMuted)),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true, fillColor: AppColors.bg, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  // ─── STAFF PICKER ───

  void _showStaffPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('PILIH STAFF', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ..._staffList.map((s) => InkWell(
                onTap: () { setState(() => _staff = s); Navigator.pop(ctx); },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: _staff == s ? AppColors.green.withValues(alpha: 0.1) : AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _staff == s ? AppColors.green.withValues(alpha: 0.4) : AppColors.border),
                  ),
                  child: Row(children: [
                    FaIcon(_staff == s ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circle,
                        size: 12, color: _staff == s ? AppColors.green : AppColors.textDim),
                    const SizedBox(width: 10),
                    Text(s, style: TextStyle(fontSize: 12, fontWeight: _staff == s ? FontWeight.w800 : FontWeight.w500,
                        color: _staff == s ? AppColors.green : AppColors.textPrimary)),
                  ]),
                ),
              )),
        ]),
      ),
    );
  }

  // ─── SUCCESS SHEET ───

  void _showSuccessSheet(Map<String, dynamic> data, String siri) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isDismissible: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Container(width: 56, height: 56,
              decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Center(child: FaIcon(FontAwesomeIcons.circleCheck, size: 28, color: AppColors.green))),
          const SizedBox(height: 10),
          const Text('JUALAN BERJAYA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          Text('#$siri', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Column(children: [
              _summaryRow('Pelanggan', data['nama'] ?? '-'),
              _summaryRow('Bayaran', _caraBayaran),
              _summaryRow('Item', '$_cartCount item'),
              Container(margin: const EdgeInsets.symmetric(vertical: 4), height: 1, color: AppColors.border),
              _summaryRow('TOTAL', 'RM ${_cartTotal.toStringAsFixed(2)}', bold: true),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: SizedBox(height: 44, child: ElevatedButton.icon(
              onPressed: () async {
                final printer = PrinterService();
                final ok = await printer.printReceipt(data, _shopInfo);
                if (ok && _autoDrawer && _caraBayaran == 'CASH') await printer.kickCashDrawer();
                if (ctx.mounted) _snack(ok ? 'Resit dicetak' : 'Gagal cetak', err: !ok);
              },
              icon: const FaIcon(FontAwesomeIcons.print, size: 11),
              label: const Text('CETAK', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 44, child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _resetAll(); },
              icon: const FaIcon(FontAwesomeIcons.cartPlus, size: 11),
              label: const Text('JUALAN BARU', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
          ]),
        ]),
      )
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: bold ? FontWeight.w900 : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: 10, color: bold ? AppColors.green : AppColors.textPrimary, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
      ]),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 24, height: 24,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Center(child: FaIcon(icon, size: 8, color: color))),
    );
  }
}

// ═══════════════════════════════════════
// BARCODE SCANNER PAGE
// ═══════════════════════════════════════

class _QSBarcodeScannerPage extends StatefulWidget {
  final void Function(String code) onScanned;
  const _QSBarcodeScannerPage({required this.onScanned});

  @override
  State<_QSBarcodeScannerPage> createState() => _QSBarcodeScannerPageState();
}

class _QSBarcodeScannerPageState extends State<_QSBarcodeScannerPage> {
  final MobileScannerController _scannerCtrl = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('SCAN BARCODE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerCtrl.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerCtrl.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerCtrl,
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _hasScanned = true;
                widget.onScanned(barcodes.first.rawValue!);
              }
            },
          ),
          Center(
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
