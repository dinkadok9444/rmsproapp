import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';
import '../../services/app_language.dart';

const String _cloudRunUrl =
    'https://rms-backend-94407896005.asia-southeast1.run.app';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _lang = AppLanguage();
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  String _ownerID = 'admin', _shopID = 'MAIN';
  String _sortOrder = 'desc';
  String _viewMode = 'ACTIVE';
  String? _filterDate;
  List<Map<String, dynamic>> _bookings = [];
  List<String> _courierList = ['TIADA', 'J&T EXPRESS', 'POSLAJU', 'NINJAVAN', 'LALAMOVE'];
  List<String> _staffList = [];
  String _domain = 'https://rmspro.net';
  Map<String, dynamic> _branchSettings = {};
  StreamSubscription? _sub;

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _sub?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0];
      _shopID = branch.split('@')[1].toUpperCase();
    }
    // Load courier list & staff from shop settings
    try {
      final shopDoc = await _db.collection('shops_$_ownerID').doc(_shopID).get();
      if (shopDoc.exists) {
        final d = shopDoc.data()!;
        _branchSettings = d;
        if (d['courierList'] != null) {
          _courierList = List<String>.from(d['courierList']);
        }
        if (d['staffList'] != null) {
          _staffList = (d['staffList'] as List).map((s) => (s is Map ? s['name'] ?? s['nama'] ?? '' : s).toString()).toList();
        }
      }
    } catch (_) {}
    // Load domain
    try {
      final dealerSnap = await _db.collection('saas_dealers').doc(_ownerID).get();
      if (dealerSnap.exists) _domain = dealerSnap.data()?['domain'] ?? _domain;
    } catch (_) {}
    // Listen bookings
    _sub = _db.collection('bookings_$_ownerID').snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data(); d['key'] = doc.id;
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) list.add(d);
      }
      if (mounted) setState(() => _bookings = list);
    });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_bookings);
    // View mode filter
    list = list.where((b) {
      final s = (b['status'] ?? 'ACTIVE').toString();
      if (_viewMode == 'ACTIVE') return s != 'ARCHIVED' && s != 'DELETED';
      return s == _viewMode;
    }).toList();
    // Date filter
    if (_filterDate != null && _filterDate!.isNotEmpty) {
      list = list.where((b) => (b['tarikhBooking'] ?? '').toString().contains(_filterDate!)).toList();
    }
    // Search
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((b) =>
        (b['nama'] ?? '').toString().toLowerCase().contains(q) ||
        (b['tel'] ?? '').toString().contains(q) ||
        (b['siriBooking'] ?? '').toString().toLowerCase().contains(q)
      ).toList();
    }
    // Sort
    switch (_sortOrder) {
      case 'asc': list.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));
      case 'az': list.sort((a, b) => (a['nama'] ?? '').toString().compareTo(b['nama'] ?? ''));
      case 'za': list.sort((a, b) => (b['nama'] ?? '').toString().compareTo(a['nama'] ?? ''));
      default: list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    }
    return list;
  }

  String _fmtDate(dynamic d) {
    if (d is String && d.contains('T')) return d.replaceFirst('T', ' ');
    if (d is String) return d;
    return '-';
  }

  void _kiraBaki(TextEditingController hargaC, TextEditingController depositC, TextEditingController bakiC) {
    final h = double.tryParse(hargaC.text) ?? 0;
    final d = double.tryParse(depositC.text) ?? 0;
    bakiC.text = (h - d < 0 ? 0 : h - d).toStringAsFixed(2);
  }

  // ========== PAYMENT SETTINGS (GEAR ICON) ==========
  void _showPaymentSettingsModal() {
    final qrUrl = (_branchSettings['bookingQrImageUrl'] ?? '').toString();
    final bankTypeCtrl = TextEditingController(text: (_branchSettings['bookingBankType'] ?? '').toString());
    final accNameCtrl = TextEditingController(text: (_branchSettings['bookingBankAccName'] ?? '').toString());
    final accNoCtrl = TextEditingController(text: (_branchSettings['bookingBankAccount'] ?? '').toString());
    String currentQr = qrUrl;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppColors.cyan, width: 2)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  FaIcon(FontAwesomeIcons.buildingColumns, size: 14, color: AppColors.cyan),
                  SizedBox(width: 8),
                  Text('TETAPAN PEMBAYARAN BOOKING', style: TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
              const SizedBox(height: 6),
              const Text('Maklumat ini akan dipaparkan dalam borang booking untuk pelanggan.', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
              const SizedBox(height: 16),

              // QR Image Upload
              _label('GAMBAR QR PAYMENT'),
              GestureDetector(
                onTap: () async {
                  try {
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
                    if (picked == null) return;
                    _snack('Uploading QR...');
                    final ref = FirebaseStorage.instance.ref().child('booking_settings/$_ownerID/$_shopID/qr_${DateTime.now().millisecondsSinceEpoch}.jpg');
                    await ref.putFile(File(picked.path));
                    final url = await ref.getDownloadURL();
                    setS(() => currentQr = url);
                    _snack('QR berjaya dimuat naik');
                  } catch (e) {
                    _snack('Gagal upload: $e', err: true);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: currentQr.isNotEmpty ? AppColors.cyan : AppColors.borderMed),
                  ),
                  child: currentQr.isNotEmpty
                    ? Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(currentQr, height: 160, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: AppColors.textDim)),
                        ),
                        const SizedBox(height: 6),
                        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          FaIcon(FontAwesomeIcons.penToSquare, size: 9, color: AppColors.cyan),
                          SizedBox(width: 4),
                          Text('Tekan untuk tukar', style: TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
                        ]),
                      ])
                    : const Column(children: [
                        FaIcon(FontAwesomeIcons.cloudArrowUp, size: 24, color: AppColors.textDim),
                        SizedBox(height: 6),
                        Text('Upload Gambar QR', style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                ),
              ),
              if (currentQr.isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => setS(() => currentQr = ''),
                    child: const Text('Padam QR', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              _labelInput('Jenis Bank', bankTypeCtrl, 'Cth: MAYBANK / CIMB / BANK ISLAM'),
              _labelInput('Nama Pemegang Akaun', accNameCtrl, 'Cth: ALI BIN ABU'),
              _labelInput('No Akaun', accNoCtrl, 'Cth: 1234567890', keyboard: TextInputType.number),

              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  await _db.collection('shops_$_ownerID').doc(_shopID).set({
                    'bookingQrImageUrl': currentQr,
                    'bookingBankType': bankTypeCtrl.text.trim().toUpperCase(),
                    'bookingBankAccName': accNameCtrl.text.trim().toUpperCase(),
                    'bookingBankAccount': accNoCtrl.text.trim(),
                  }, SetOptions(merge: true));
                  // Update local cache
                  _branchSettings['bookingQrImageUrl'] = currentQr;
                  _branchSettings['bookingBankType'] = bankTypeCtrl.text.trim().toUpperCase();
                  _branchSettings['bookingBankAccName'] = accNameCtrl.text.trim().toUpperCase();
                  _branchSettings['bookingBankAccount'] = accNoCtrl.text.trim();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('Tetapan pembayaran disimpan');
                },
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
                label: const Text('SIMPAN TETAPAN', style: TextStyle(fontWeight: FontWeight.w900)),
              )),
            ]),
          ),
        );
      }),
    );
  }

  // ========== UPLOAD RESIT ==========
  Future<String?> _uploadResit() async {
    try {
      // maxWidth 400 + imageQuality 25 = ~30-50KB output
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 400, imageQuality: 25);
      if (picked == null) return null;

      final fileBytes = await File(picked.path).readAsBytes();
      _snack('Uploading resit (${(fileBytes.length / 1024).toStringAsFixed(0)}KB)...');

      final ref = FirebaseStorage.instance.ref().child('booking_resit/$_ownerID/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(fileBytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e) {
      _snack('Gagal upload resit: $e', err: true);
      return null;
    }
  }

  // ========== ADD BOOKING ==========
  void _showAddBooking() {
    final namaCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final itemCtrl = TextEditingController();
    final hargaCtrl = TextEditingController(text: '0');
    final depositCtrl = TextEditingController(text: '0');
    final bakiCtrl = TextEditingController(text: '0');
    final tarikhRepairCtrl = TextEditingController();
    String selectedStaff = '';
    String resitUrl = '';

    // QR & bank info from branch settings
    final qrImageUrl = (_branchSettings['bookingQrImageUrl'] ?? '').toString();
    final bankType = (_branchSettings['bookingBankType'] ?? '').toString();
    final bankAccName = (_branchSettings['bookingBankAccName'] ?? '').toString();
    final bankAccount = (_branchSettings['bookingBankAccount'] ?? '').toString();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppColors.primary, width: 2)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const FaIcon(FontAwesomeIcons.calendarPlus, size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(_lang.get('bk_daftar_booking'), style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
              const SizedBox(height: 16),
              // Staff
              if (_staffList.isNotEmpty) ...[
                _label('Pilih Staff Bertugas'),
                _dropdownField(
                  items: ['', ..._staffList],
                  value: selectedStaff,
                  onChanged: (v) => setS(() => selectedStaff = v ?? ''),
                  hint: '-- PILIH STAFF --',
                ),
                const SizedBox(height: 12),
              ],
              _labelInput('Nama Pelanggan', namaCtrl, 'Nama Penuh'),
              _labelInput('No Telefon (WhatsApp)', telCtrl, '011...', keyboard: TextInputType.phone),
              Row(children: [
                Expanded(flex: 2, child: _labelInput('Item / Model & Servis', itemCtrl, 'Cth: iPhone 11 - Tukar Bateri', caps: true)),
                const SizedBox(width: 8),
                Expanded(child: _labelInput('Harga (RM)', hargaCtrl, '0', keyboard: TextInputType.number, onChanged: () => _kiraBaki(hargaCtrl, depositCtrl, bakiCtrl))),
              ]),
              // Tarikh Jangka Cust Datang
              _labelInput('Tarikh Jangka Cust Datang', tarikhRepairCtrl, 'yyyy-mm-dd'),
              // Pricing
              Row(children: [
                Expanded(child: _labelInput('Deposit (RM)', depositCtrl, '0', keyboard: TextInputType.number, onChanged: () => _kiraBaki(hargaCtrl, depositCtrl, bakiCtrl))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Baki (RM)'),
                  TextField(controller: bakiCtrl, enabled: false, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: _inputDeco('0')),
                  const SizedBox(height: 12),
                ])),
              ]),

              // ── QR Payment & Bank Info ──
              const Divider(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                ),
                child: Column(children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    FaIcon(FontAwesomeIcons.qrcode, size: 12, color: AppColors.cyan),
                    SizedBox(width: 6),
                    Text('MAKLUMAT PEMBAYARAN', style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ]),
                  const SizedBox(height: 10),
                  if (qrImageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(qrImageUrl, width: 160, height: 160, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: AppColors.textDim)),
                    ),
                  if (qrImageUrl.isEmpty && bankAccount.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Belum ditetapkan — Sila set di icon gear (⚙)', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                    ),
                  if (qrImageUrl.isNotEmpty || bankAccount.isNotEmpty) const SizedBox(height: 10),
                  if (bankType.isNotEmpty)
                    Text(bankType, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                  if (bankAccName.isNotEmpty)
                    Text(bankAccName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w900)),
                  if (bankAccount.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () { Clipboard.setData(ClipboardData(text: bankAccount)); _snack('No akaun disalin!'); },
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(bankAccount, style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(width: 6),
                        const FaIcon(FontAwesomeIcons.copy, size: 10, color: AppColors.primary),
                      ]),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),

              // ── Upload Resit Booking ──
              _label('Resit Pembayaran (Pilihan)'),
              GestureDetector(
                onTap: () async {
                  final url = await _uploadResit();
                  if (url != null) setS(() => resitUrl = url);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: resitUrl.isEmpty ? AppColors.bg : AppColors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: resitUrl.isEmpty ? AppColors.borderMed : AppColors.green),
                  ),
                  child: resitUrl.isEmpty
                    ? const Column(children: [
                        FaIcon(FontAwesomeIcons.cloudArrowUp, size: 20, color: AppColors.textDim),
                        SizedBox(height: 6),
                        Text('Tekan untuk upload resit', style: TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
                      ])
                    : Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(resitUrl, height: 100, fit: BoxFit.contain),
                        ),
                        const SizedBox(height: 6),
                        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          FaIcon(FontAwesomeIcons.circleCheck, size: 10, color: AppColors.green),
                          SizedBox(width: 4),
                          Text('Resit berjaya dimuat naik', style: TextStyle(color: AppColors.green, fontSize: 9, fontWeight: FontWeight.w700)),
                        ]),
                      ]),
                ),
              ),

              const SizedBox(height: 20),
              // Save
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  if (namaCtrl.text.trim().isEmpty || telCtrl.text.trim().isEmpty || itemCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('bk_sila_isi')), backgroundColor: AppColors.red));
                    return;
                  }
                  final siri = 'BKG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                  final custName = namaCtrl.text.trim().toUpperCase();
                  final itemName = itemCtrl.text.trim().toUpperCase();
                  await _db.collection('bookings_$_ownerID').add({
                    'shopID': _shopID, 'siriBooking': siri,
                    'nama': custName, 'tel': telCtrl.text.trim(),
                    'item': itemName, 'staff': selectedStaff,
                    'tarikhBooking': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
                    'tarikhCustDatang': tarikhRepairCtrl.text.trim(),
                    'harga': double.tryParse(hargaCtrl.text) ?? 0,
                    'deposit': double.tryParse(depositCtrl.text) ?? 0,
                    'baki': double.tryParse(bakiCtrl.text) ?? 0,
                    'status': 'ACTIVE', 'kurier': 'TIADA', 'tracking_no': '', 'tracking_status': 'MENUNGGU PROSES',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'resitUrl': resitUrl,
                    'pdfUrl_INVOICE': '',
                    'pdfUrl_QUOTATION': '',
                  });
                  // Send push notification to branch devices
                  try {
                    await http.post(Uri.parse('https://us-central1-rmspro-2f454.cloudfunctions.net/sendBookingNotification'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'ownerID': _ownerID, 'shopID': _shopID, 'customerName': custName, 'item': itemName, 'siriBooking': siri}),
                    );
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking #$siri ${_lang.get('bk_booking_berjaya')}'), backgroundColor: AppColors.green));
                },
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
                label: Text(_lang.get('bk_simpan_rekod'), style: const TextStyle(fontWeight: FontWeight.w900)),
              )),
            ]),
          ),
        );
      }),
    );
  }

  // ========== DETAIL MODAL ==========
  void _showDetail(Map<String, dynamic> b) {
    String kurier = b['kurier'] ?? 'TIADA';
    String trackNo = b['tracking_no'] ?? '';
    String trackStatus = b['tracking_status'] ?? 'MENUNGGU PROSES';
    String currentResitUrl = (b['resitUrl'] ?? '').toString();
    final trackCtrl = TextEditingController(text: trackNo);
    final hargaCtrl = TextEditingController(text: ((b['harga'] ?? 0) as num).toStringAsFixed(2));
    final depositCtrl = TextEditingController(text: ((b['deposit'] ?? 0) as num).toStringAsFixed(2));
    final bakiCtrl = TextEditingController(text: ((b['baki'] ?? 0) as num).toStringAsFixed(2));

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
            child: Column(children: [
              // Close button
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(FontAwesomeIcons.xmark, size: 18, color: AppColors.red),
                ),
              ),
              // Customer info
              CircleAvatar(radius: 30, backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: const FaIcon(FontAwesomeIcons.userAstronaut, size: 24, color: AppColors.primary)),
              const SizedBox(height: 10),
              Text((b['nama'] ?? '-').toString().toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
              Text(b['siriBooking'] ?? '-', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),

              // ── Harga / Deposit / Baki ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    FaIcon(FontAwesomeIcons.moneyBill, size: 11, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('MAKLUMAT BAYARAN', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Harga (RM)'),
                      TextField(controller: hargaCtrl, keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                        onChanged: (_) => _kiraBaki(hargaCtrl, depositCtrl, bakiCtrl),
                        decoration: _inputDeco('0')),
                    ])),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Deposit (RM)'),
                      TextField(controller: depositCtrl, keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                        onChanged: (_) => _kiraBaki(hargaCtrl, depositCtrl, bakiCtrl),
                        decoration: _inputDeco('0')),
                    ])),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Baki (RM)'),
                      TextField(controller: bakiCtrl, enabled: false,
                        style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w900),
                        decoration: _inputDeco('0')),
                    ])),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 10)),
                    onPressed: () async {
                      await _db.collection('bookings_$_ownerID').doc(b['key']).update({
                        'harga': double.tryParse(hargaCtrl.text) ?? 0,
                        'deposit': double.tryParse(depositCtrl.text) ?? 0,
                        'baki': double.tryParse(bakiCtrl.text) ?? 0,
                      });
                      _snack('Bayaran dikemaskini');
                    },
                    icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 10),
                    label: const Text('Simpan Bayaran', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  )),
                ]),
              ),

              // ── Resit Pembayaran ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: currentResitUrl.isNotEmpty ? AppColors.green.withValues(alpha: 0.06) : AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: currentResitUrl.isNotEmpty ? AppColors.green.withValues(alpha: 0.3) : AppColors.borderMed),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    FaIcon(FontAwesomeIcons.receipt, size: 11, color: currentResitUrl.isNotEmpty ? AppColors.green : AppColors.textDim),
                    const SizedBox(width: 6),
                    Text('RESIT PEMBAYARAN', style: TextStyle(color: currentResitUrl.isNotEmpty ? AppColors.green : AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        final url = await _uploadResit();
                        if (url != null) {
                          await _db.collection('bookings_$_ownerID').doc(b['key']).update({'resitUrl': url});
                          setS(() => currentResitUrl = url);
                          _snack('Resit berjaya dimuat naik');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const FaIcon(FontAwesomeIcons.cloudArrowUp, size: 9, color: AppColors.cyan),
                          const SizedBox(width: 4),
                          Text(currentResitUrl.isNotEmpty ? 'Tukar' : 'Upload', style: const TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                  if (currentResitUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: GestureDetector(
                        onTap: () => _showFullImage(currentResitUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(currentResitUrl, height: 140, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: AppColors.textDim)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(child: Text('Tekan gambar untuk lihat penuh', style: TextStyle(color: AppColors.textDim, fontSize: 9))),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Customer belum upload resit', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                    ),
                ]),
              ),

              // Tracking section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderMed)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('bk_pengurusan_tracking'), style: const TextStyle(color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  _label('Jenis Kurier'),
                  _dropdownField(items: _courierList, value: kurier, onChanged: (v) => setS(() => kurier = v ?? 'TIADA')),
                  const SizedBox(height: 10),
                  _label('No Tracking'),
                  TextField(controller: trackCtrl, textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), decoration: _inputDeco('Isi no tracking...')),
                  const SizedBox(height: 10),
                  _label('Status Semasa'),
                  _dropdownField(
                    items: ['MENUNGGU PROSES', 'DALAM PERJALANAN', 'BARANG SAMPAI', 'COMPLETED'],
                    value: trackStatus, onChanged: (v) => setS(() => trackStatus = v ?? 'MENUNGGU PROSES'), color: AppColors.yellow,
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              // Update tracking
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary.withValues(alpha: 0.2), foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                onPressed: () async {
                  await _db.collection('bookings_$_ownerID').doc(b['key']).update({
                    'kurier': kurier, 'tracking_no': trackCtrl.text.trim().toUpperCase(), 'tracking_status': trackStatus,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('bk_tracking_dikemaskini')), backgroundColor: AppColors.green));
                },
                icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 12), label: Text(_lang.get('bk_kemaskini_tracking')),
              )),
              const SizedBox(height: 12),
              // Action buttons
              Row(children: [
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
                  onPressed: () => _sendWhatsApp(b),
                  icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 14), label: Text(_lang.get('whatsapp'), style: const TextStyle(fontSize: 10)),
                )),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(context: ctx, builder: (c) => AlertDialog(
                      backgroundColor: Colors.white,
                      title: Text('Padam ${b['nama']}?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_lang.get('batal'))),
                        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                          onPressed: () => Navigator.pop(c, true), child: Text(_lang.get('padam'))),
                      ],
                    ));
                    if (confirm == true) {
                      await _db.collection('bookings_$_ownerID').doc(b['key']).delete();
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.trashCan, size: 12), label: Text(_lang.get('bk_delete'), style: const TextStyle(fontSize: 10)),
                )),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _sendWhatsApp(Map<String, dynamic> b) {
    String waNum = (b['tel'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (waNum.startsWith('0')) waNum = '6$waNum';
    final harga = (double.tryParse(b['harga']?.toString() ?? '0') ?? 0).toStringAsFixed(2);
    final deposit = (double.tryParse(b['deposit']?.toString() ?? '0') ?? 0).toStringAsFixed(2);
    final baki = (double.tryParse(b['baki']?.toString() ?? '0') ?? 0).toStringAsFixed(2);
    final msg = 'Salam ${b['nama']},\n\n*No Tempahan:* ${b['siriBooking']}\n*Item:* ${b['item']}\n*Harga:* RM$harga\n*Deposit:* RM$deposit\n*Baki:* RM$baki\n\nTerima Kasih.';
    launchUrl(Uri.parse('https://wa.me/$waNum?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
  }

  // ========== COURIER MODAL ==========
  void _showCourierModal() {
    final newCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          margin: const EdgeInsets.only(top: 120),
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_lang.get('bk_kurier'), style: const TextStyle(color: AppColors.yellow, fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(controller: newCtrl, textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), decoration: _inputDeco('Nama Kurier'))),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, padding: const EdgeInsets.all(14)),
                onPressed: () async {
                  final v = newCtrl.text.trim().toUpperCase();
                  if (v.isEmpty || _courierList.contains(v)) return;
                  _courierList.add(v); newCtrl.clear();
                  await _db.collection('shops_$_ownerID').doc(_shopID).set({'courierList': _courierList}, SetOptions(merge: true));
                  setS(() {});
                },
                child: const FaIcon(FontAwesomeIcons.plus, size: 12),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
              child: ListView(shrinkWrap: true, children: _courierList.where((k) => k != 'TIADA').map((k) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(k, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                  GestureDetector(
                    onTap: () async {
                      _courierList.remove(k);
                      await _db.collection('shops_$_ownerID').doc(_shopID).set({'courierList': _courierList}, SetOptions(merge: true));
                      setS(() {});
                    },
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(6)),
                      child: const FaIcon(FontAwesomeIcons.trash, size: 10, color: Colors.white)),
                  ),
                ]),
              )).toList()),
            ),
          ]),
        );
      }),
    );
  }

  // ========== HELPERS ==========
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
  );

  Widget _labelInput(String label, TextEditingController ctrl, String hint, {TextInputType keyboard = TextInputType.text, bool caps = false, Color? color, VoidCallback? onChanged}) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      TextField(controller: ctrl, keyboardType: keyboard, textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
        style: TextStyle(color: color ?? Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
        onChanged: onChanged != null ? (_) => onChanged() : null,
        decoration: _inputDeco(hint)),
    ]));
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
    filled: true, fillColor: AppColors.bg, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderMed)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderMed)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
  );

  Widget _dropdownField({required List<String> items, required String value, required ValueChanged<String?> onChanged, String? hint, Color? color}) {
    if (!items.contains(value)) value = items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.borderMed)),
      child: DropdownButton<String>(
        value: value, isExpanded: true, underline: const SizedBox(), dropdownColor: Colors.white,
        style: TextStyle(color: color ?? Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
        hint: hint != null ? Text(hint, style: const TextStyle(color: AppColors.textDim, fontSize: 12)) : null,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.primary, width: 1))),
        child: Column(children: [
          Row(children: [
              _tabBtn('AKTIF', 'ACTIVE', FontAwesomeIcons.list, AppColors.primary),
              const SizedBox(width: 6),
              _tabBtn('ARKIB', 'ARCHIVED', FontAwesomeIcons.boxArchive, AppColors.yellow),
              const SizedBox(width: 6),
              _tabBtn('SAMPAH', 'DELETED', FontAwesomeIcons.trashCan, AppColors.red),
              const Spacer(),
              // Payment Settings (QR + Bank)
              _headerBtn(FontAwesomeIcons.gear, AppColors.cyan, _showPaymentSettingsModal),
              const SizedBox(width: 6),
              // Courier
              _headerBtn(FontAwesomeIcons.truck, AppColors.yellow, _showCourierModal),
              const SizedBox(width: 6),
              // New Booking
              GestureDetector(
                onTap: _showAddBooking,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF00CC82)]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 10)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.black), const SizedBox(width: 6),
                    Text(_lang.get('bk_new_booking'), style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ]),
          const SizedBox(height: 10),
          // Filters
          Row(children: [
            Expanded(child: TextField(controller: _searchCtrl, onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
              decoration: InputDecoration(hintText: 'Cari...', hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textMuted), filled: true, fillColor: AppColors.bgDeep, isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
            )),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10)),
              child: DropdownButton<String>(value: _sortOrder, underline: const SizedBox(), dropdownColor: Colors.white, isDense: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                items: [
                  DropdownMenuItem(value: 'desc', child: Text(_lang.get('terbaru'))),
                  DropdownMenuItem(value: 'asc', child: Text(_lang.get('bk_lama'))),
                  DropdownMenuItem(value: 'az', child: Text(_lang.get('bk_az'))),
                  DropdownMenuItem(value: 'za', child: Text(_lang.get('bk_za'))),
                ],
                onChanged: (v) => setState(() => _sortOrder = v!)),
            ),
          ]),
        ]),
      ),
      // List
      Expanded(
        child: filtered.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.calendarXmark, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              Text(_lang.get('bk_tiada_rekod'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final b = filtered[i];
                final deposit = (b['deposit'] ?? 0) as num;
                final hasPaid = deposit > 0;
                final staff = b['staff'] ?? '';
                return GestureDetector(
                  onTap: () => _showDetail(b),
                  onLongPress: () => _showCardPopup(b),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Colors.white, AppColors.bg]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderMed),
                      boxShadow: [BoxShadow(color: AppColors.bg, blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Siri (tekan untuk print)
                      GestureDetector(
                        onTap: () => _showPrintModal(b),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(b['siriBooking'] ?? '-', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          const SizedBox(width: 4),
                          FaIcon(FontAwesomeIcons.print, size: 9, color: AppColors.primary.withValues(alpha: 0.5)),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      // Nama + Harga
                      Row(children: [
                        Expanded(child: Text((b['nama'] ?? '-').toString().toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800))),
                        Text('RM ${((b['harga'] ?? 0) as num).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900)),
                        if (hasPaid) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                            child: Text(_lang.get('bk_paid'), style: const TextStyle(color: Colors.black, fontSize: 7, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 3),
                      // Telefon (tekan untuk call/wa)
                      GestureDetector(
                        onTap: () => _showPhoneOptions(b),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const FaIcon(FontAwesomeIcons.phone, size: 9, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(b['tel'] ?? '-', style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(height: 3),
                      // Item
                      Text(b['item'] ?? '-', style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      // Tarikh + Staff + Resit
                      Row(children: [
                        Text(_fmtDate(b['tarikhBooking']), style: const TextStyle(color: AppColors.textSub, fontSize: 9)),
                        if (staff.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const FaIcon(FontAwesomeIcons.userTag, size: 8, color: AppColors.yellow),
                              const SizedBox(width: 4),
                              Text(staff, style: const TextStyle(color: AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        ],
                        if ((b['resitUrl'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              FaIcon(FontAwesomeIcons.receipt, size: 8, color: AppColors.green),
                              SizedBox(width: 4),
                              Text('RESIT', style: TextStyle(color: AppColors.green, fontSize: 8, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        ],
                      ]),
                      // Resit thumbnail
                      if ((b['resitUrl'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showFullImage((b['resitUrl']).toString()),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              (b['resitUrl']).toString(),
                              height: 60, width: 80, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                );
              },
            ),
      ),
    ]);
  }

  // ═══════════════════════════════════════
  // PRINT MODAL
  // ═══════════════════════════════════════
  void _showPrintModal(Map<String, dynamic> b) {
    final siri = b['siriBooking'] ?? '-';
    final hasInvoice = (b['pdfUrl_INVOICE'] ?? '').toString().isNotEmpty;
    final hasQuote = (b['pdfUrl_QUOTATION'] ?? '').toString().isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.print, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('${_lang.get('cetak')} #$siri', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          _printBtn('RESIT 80MM', 'Cetak ke printer Bluetooth', FontAwesomeIcons.receipt, AppColors.blue, () async {
            Navigator.pop(ctx);
            final ok = await PrinterService().printReceipt(_bookingToJob(b), _branchSettings);
            if (!ok) {
              _snack('Gagal cetak — pastikan printer dihidupkan & Bluetooth aktif', err: true);
            }
          }),
          const SizedBox(height: 8),
          hasInvoice
              ? _printBtn('VIEW BOOKING', 'Sudah dijana - tekan untuk buka', FontAwesomeIcons.eye, AppColors.green, () {
                  Navigator.pop(ctx);
                  _downloadAndOpenPDF(b['pdfUrl_INVOICE'], 'INVOICE', siri);
                })
              : _printBtn('GENERATE BOOKING', 'Jana booking A4 PDF', FontAwesomeIcons.filePdf, AppColors.green, () {
                  Navigator.pop(ctx);
                  _generatePDF(b, 'INVOICE');
                }),
          const SizedBox(height: 8),
          hasQuote
              ? _printBtn('VIEW QUOTATION', 'Sudah dijana - tekan untuk buka', FontAwesomeIcons.eye, AppColors.yellow, () {
                  Navigator.pop(ctx);
                  _downloadAndOpenPDF(b['pdfUrl_QUOTATION'], 'QUOTATION', siri);
                })
              : _printBtn('GENERATE QUOTATION', 'Jana sebut harga A4 PDF', FontAwesomeIcons.fileLines, AppColors.yellow, () {
                  Navigator.pop(ctx);
                  _generatePDF(b, 'QUOTATION');
                }),
        ]),
      ),
    );
  }

  Map<String, dynamic> _bookingToJob(Map<String, dynamic> b) {
    return {
      'siri': b['siriBooking'] ?? '-',
      'nama': b['nama'] ?? '-',
      'tel': b['tel'] ?? '-',
      'model': b['item'] ?? '-',
      'kerosakan': b['item'] ?? '-',
      'harga': b['harga']?.toString() ?? '0',
      'total': b['harga']?.toString() ?? '0',
      'payment_status': (b['deposit'] ?? 0) as num > 0 ? 'PAID' : 'UNPAID',
      'staff_terima': b['staff'] ?? '',
      'tarikh': b['tarikhBooking'] ?? '',
    };
  }

  Widget _printBtn(String title, String desc, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Center(child: FaIcon(icon, size: 16, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
              Text(desc, style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
            ])),
            FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // PDF GENERATION (A4 - Cloud Run)
  // ═══════════════════════════════════════
  Map<String, dynamic> _buildPdfPayload(Map<String, dynamic> b, String typePDF) {
    return {
      'typePDF': typePDF,
      'paperSize': 'A4',
      'templatePdf': _branchSettings['templatePdf'] ?? 'tpl_1',
      'logoBase64': _branchSettings['logoBase64'] ?? '',
      'namaKedai': _branchSettings['shopName'] ?? _branchSettings['namaKedai'] ?? 'RMS PRO',
      'alamatKedai': _branchSettings['address'] ?? _branchSettings['alamat'] ?? '-',
      'telKedai': _branchSettings['phone'] ?? _branchSettings['ownerContact'] ?? '-',
      'noJob': b['siriBooking'] ?? '-',
      'namaCust': b['nama'] ?? '-',
      'telCust': b['tel'] ?? '-',
      'tarikhResit': (b['tarikhBooking'] ?? DateTime.now().toIso8601String()).toString().split('T').first,
      'stafIncharge': b['staff'] ?? 'Admin',
      'items': [
        {
          'nama': b['item'] ?? '-',
          'harga': double.tryParse(b['harga']?.toString() ?? '0') ?? 0,
        }
      ],
      'model': b['item'] ?? '-',
      'kerosakan': b['item'] ?? '-',
      'warranty': 'TIADA',
      'warranty_exp': '',
      'voucherAmt': 0,
      'diskaunAmt': 0,
      'tambahanAmt': 0,
      'depositAmt': double.tryParse(b['deposit']?.toString() ?? '0') ?? 0,
      'totalDibayar': double.tryParse(b['harga']?.toString() ?? '0') ?? 0,
      'statusBayar': (b['deposit'] ?? 0) as num > 0 ? 'PAID' : 'UNPAID',
      'nota': typePDF == 'INVOICE'
          ? (_branchSettings['notaInvoice'] ?? 'Sila simpan dokumen ini untuk rujukan rasmi.')
          : (_branchSettings['notaQuotation'] ?? 'Sebut harga ini sah untuk tempoh 7 hari sahaja.'),
    };
  }

  Future<void> _generatePDF(Map<String, dynamic> b, String typePDF) async {
    if (!mounted) return;
    final siri = b['siriBooking'] ?? '-';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Menjana $typePDF...', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse('$_cloudRunUrl/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_buildPdfPayload(b, typePDF)),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final pdfUrl = result['pdfUrl']?.toString() ?? '';
        if (pdfUrl.isNotEmpty) {
          await _db.collection('bookings_$_ownerID').doc(b['key']).update({'pdfUrl_$typePDF': pdfUrl});
          _snack('$typePDF berjaya dijana!');
          _downloadAndOpenPDF(pdfUrl, typePDF, siri);
        } else {
          _snack('Pautan PDF tidak ditemui', err: true);
        }
      } else {
        _snack('Gagal menjana: ${response.statusCode}', err: true);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Gagal sambung server: $e', err: true);
    }
  }

  Future<void> _downloadAndOpenPDF(String pdfUrl, String typePDF, String siri) async {
    try {
      if (kIsWeb) {
        if (!mounted) return;
        launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final fileName = '${typePDF}_BKG_$siri.pdf';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (!file.existsSync()) {
        await Dio().download(pdfUrl, filePath);
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              FaIcon(FontAwesomeIcons.filePdf, size: 14, color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow),
              const SizedBox(width: 8),
              Expanded(child: Text('$typePDF #$siri', style: TextStyle(color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
              child: Row(children: [
                FaIcon(FontAwesomeIcons.circleCheck, size: 24, color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$typePDF SEDIA', style: TextStyle(color: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
                  Text(fileName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ])),
              ]),
            ),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); OpenFilex.open(filePath); },
              icon: const FaIcon(FontAwesomeIcons.fileCircleCheck, size: 14),
              label: Text(_lang.get('buka_print_pdf')),
              style: ElevatedButton.styleFrom(
                backgroundColor: typePDF == 'INVOICE' ? AppColors.green : AppColors.yellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            )),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () async { await Clipboard.setData(ClipboardData(text: pdfUrl)); _snack('Link PDF disalin!'); },
                icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
                label: Text(_lang.get('salin_link')),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                onPressed: () {
                  final msg = Uri.encodeComponent('$typePDF #$siri\n$pdfUrl');
                  launchUrl(Uri.parse('https://wa.me/?text=$msg'), mode: LaunchMode.externalApplication);
                },
                icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 12),
                label: Text(_lang.get('hantar_wa')),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              )),
            ]),
          ]),
        ),
      );
    } catch (e) {
      _snack('Gagal muat turun: $e', err: true);
    }
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _tabBtn(String label, String mode, IconData icon, Color color) {
    final active = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(icon, size: 9, color: active ? Colors.white : color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: active ? Colors.white : color, fontSize: 8, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  void _showPhoneOptions(Map<String, dynamic> b) {
    final tel = (b['tel'] ?? '').toString();
    if (tel.isEmpty) return;
    String waNum = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (waNum.startsWith('0')) waNum = '6$waNum';
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () { Navigator.pop(ctx); launchUrl(Uri.parse('tel:$tel')); },
              icon: const FaIcon(FontAwesomeIcons.phone, size: 14),
              label: const Text('CALL', style: TextStyle(fontWeight: FontWeight.w900)),
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () { Navigator.pop(ctx); launchUrl(Uri.parse('https://wa.me/$waNum'), mode: LaunchMode.externalApplication); },
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 14),
              label: const Text('WHATSAPP', style: TextStyle(fontWeight: FontWeight.w900)),
            )),
          ]),
        ]),
      ),
    );
  }

  void _showCardPopup(Map<String, dynamic> b) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text((b['nama'] ?? '-').toString().toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          if (_viewMode == 'ACTIVE') ...[
            _actionTile(ctx, FontAwesomeIcons.boxArchive, 'Arkib', AppColors.yellow, () async {
              Navigator.pop(ctx);
              await _db.collection('bookings_$_ownerID').doc(b['key']).update({'status': 'ARCHIVED'});
              _snack('Booking diarkibkan');
            }),
            _actionTile(ctx, FontAwesomeIcons.trashCan, 'Padam', AppColors.red, () async {
              Navigator.pop(ctx);
              await _db.collection('bookings_$_ownerID').doc(b['key']).update({'status': 'DELETED'});
              _snack('Booking dialih ke sampah');
            }),
          ],
          if (_viewMode == 'ARCHIVED')
            _actionTile(ctx, FontAwesomeIcons.arrowRotateLeft, 'Pulihkan', AppColors.primary, () async {
              Navigator.pop(ctx);
              await _db.collection('bookings_$_ownerID').doc(b['key']).update({'status': 'ACTIVE'});
              _snack('Booking dipulihkan');
            }),
          if (_viewMode == 'DELETED') ...[
            _actionTile(ctx, FontAwesomeIcons.arrowRotateLeft, 'Pulihkan', AppColors.primary, () async {
              Navigator.pop(ctx);
              await _db.collection('bookings_$_ownerID').doc(b['key']).update({'status': 'ACTIVE'});
              _snack('Booking dipulihkan');
            }),
            _actionTile(ctx, FontAwesomeIcons.trashCan, 'Padam Kekal', AppColors.red, () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                backgroundColor: Colors.white,
                title: Text('Padam kekal ${b['nama']}?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_lang.get('batal'))),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                    onPressed: () => Navigator.pop(c, true), child: Text(_lang.get('padam'))),
                ],
              ));
              if (confirm == true) {
                await _db.collection('bookings_$_ownerID').doc(b['key']).delete();
                _snack('Booking dipadam kekal');
              }
            }),
          ],
        ]),
      ),
    );
  }

  Widget _actionTile(BuildContext ctx, IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: FaIcon(icon, size: 16, color: color),
      title: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _headerBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: FaIcon(icon, size: 12, color: color),
      ),
    );
  }
}
