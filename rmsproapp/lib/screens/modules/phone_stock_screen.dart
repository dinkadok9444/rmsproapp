import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';
import '../../services/app_language.dart';
import '../../services/repair_service.dart';
class PhoneStockScreen extends StatefulWidget {
  const PhoneStockScreen({super.key});
  @override
  State<PhoneStockScreen> createState() => _PhoneStockScreenState();
}

class _PhoneStockScreenState extends State<PhoneStockScreen> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _searchCtrl = TextEditingController();
  final _printer = PrinterService();
  final _picker = ImagePicker();
  final _lang = AppLanguage();
  final _repairService = RepairService();
  String _ownerID = 'admin', _shopID = 'MAIN';
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _staffList = [];
  StreamSubscription? _sub;
  StreamSubscription? _transferSub;
  List<Map<String, dynamic>> _incomingTransfers = [];
  String _selectedModel = 'SEMUA';
  String _selectedKategori = 'SEMUA';
  List<String> _categories = ['BARU', 'SECOND HAND'];
  List<String> _suppliers = [];
  // Auto print settings
  bool _autoPrintBarcode = false;
  bool _autoPrintDetail = false;
  // Form controllers
  final _kodCtrl = TextEditingController();
  final _namaCtrl = TextEditingController();
  final _jualCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _init(); }

  @override
  void dispose() {
    _sub?.cancel();
    _transferSub?.cancel();
    _searchCtrl.dispose();
    _kodCtrl.dispose();
    _namaCtrl.dispose();
    _jualCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0].toLowerCase();
      _shopID = branch.split('@')[1].toUpperCase();
    }
    await _repairService.init();
    _staffList = await _repairService.getStaffList();
    _autoPrintBarcode = prefs.getBool('ps_auto_print_barcode') ?? false;
    _autoPrintDetail = prefs.getBool('ps_auto_print_detail') ?? false;
    await _loadCategories();
    await _loadSuppliers();
    _sub = _db.collection('phone_stock_$_ownerID')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).where((d) =>
          (d['shopID'] ?? '').toString().toUpperCase() == _shopID &&
          (d['status'] ?? '').toString().toUpperCase() != 'SOLD').toList();
      if (mounted) setState(() { _inventory = list; _filter(); });
    });
    // Listen for incoming transfers to this shop
    _transferSub = _db.collection('phone_transfers_$_ownerID')
        .where('toShopID', isEqualTo: _shopID)
        .where('status', isEqualTo: 'PENDING')
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (mounted) setState(() { _incomingTransfers = list; });
    });
  }

  Future<void> _loadCategories() async {
    final snap = await _db.collection('phone_categories_$_ownerID').orderBy('name').get();
    final custom = snap.docs.map((d) => (d.data()['name'] ?? '').toString().toUpperCase()).where((n) => n.isNotEmpty).toList();
    if (mounted) {
      setState(() {
        _categories = ['BARU', 'SECOND HAND', ...custom.where((c) => c != 'BARU' && c != 'SECOND HAND')];
      });
    }
  }

  void _showAddCategoryDialog(void Function(void Function()) setModalState, String Function() getCurrent, void Function(String) setCurrent) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Kategori', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Nama kategori baru',
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
            filled: true, fillColor: AppColors.bgDeep, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal'))),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim().toUpperCase();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              if (!_categories.contains(name)) {
                await _db.collection('phone_categories_$_ownerID').add({'name': name, 'timestamp': DateTime.now().millisecondsSinceEpoch});
                setState(() => _categories.add(name));
              }
              setModalState(() => setCurrent(name));
            },
            child: const Text('SIMPAN', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSuppliers() async {
    final snap = await _db.collection('phone_suppliers_$_ownerID').orderBy('name').get();
    final list = snap.docs.map((d) => (d.data()['name'] ?? '').toString().toUpperCase()).where((n) => n.isNotEmpty).toList();
    if (mounted) {
      setState(() { _suppliers = list; });
    }
  }

  void _showAddSupplierDialog(void Function(void Function()) setModalState, void Function(String) onAdded) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Supplier', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Nama supplier baru',
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
            filled: true, fillColor: AppColors.bgDeep, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal'))),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim().toUpperCase();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              if (!_suppliers.contains(name)) {
                await _db.collection('phone_suppliers_$_ownerID').add({'name': name, 'timestamp': DateTime.now().millisecondsSinceEpoch});
                setState(() => _suppliers.add(name));
              }
              setModalState(() => onAdded(name));
            },
            child: const Text('SIMPAN', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Map<String, String> _parseBarcodeData(String raw) {
    final result = <String, String>{};
    final trimmed = raw.trim();

    try {
      final json = jsonDecode(trimmed);
      if (json is Map) {
        if (json.containsKey('imei')) result['imei'] = json['imei'].toString();
        if (json.containsKey('IMEI')) result['imei'] = json['IMEI'].toString();
        if (json.containsKey('model')) result['nama'] = json['model'].toString();
        if (json.containsKey('name')) result['nama'] = json['name'].toString();
        if (json.containsKey('storage')) result['storage'] = json['storage'].toString();
        if (json.containsKey('color')) result['warna'] = json['color'].toString();
        if (json.containsKey('colour')) result['warna'] = json['colour'].toString();
        return result;
      }
    } catch (_) {}

    for (final delim in [',', '|', ';']) {
      if (trimmed.contains(delim)) {
        final parts = trimmed.split(delim).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        for (final part in parts) {
          if (RegExp(r'^\d{15}$').hasMatch(part)) {
            result['imei'] = part;
          } else if (RegExp(r'^\d+\s*(GB|TB|gb|tb)$', caseSensitive: false).hasMatch(part)) {
            result['storage'] = part.toUpperCase();
          } else if (part.length > (result['nama']?.length ?? 0)) {
            result['nama'] = part;
          }
        }
        return result;
      }
    }

    if (RegExp(r'^\d{15}$').hasMatch(trimmed)) {
      result['imei'] = trimmed;
      return result;
    }

    final imeiMatch = RegExp(r'\b(\d{15})\b').firstMatch(trimmed);
    if (imeiMatch != null) result['imei'] = imeiMatch.group(1)!;

    final storageMatch = RegExp(r'\b(\d+\s*(GB|TB))\b', caseSensitive: false).firstMatch(trimmed);
    if (storageMatch != null) result['storage'] = storageMatch.group(1)!.toUpperCase();

    var remaining = trimmed;
    if (result['imei'] != null) remaining = remaining.replaceAll(result['imei']!, '');
    if (result['storage'] != null) remaining = remaining.replaceAllMapped(RegExp(r'\b\d+\s*(GB|TB)\b', caseSensitive: false), (_) => '');
    remaining = remaining.replaceAll(RegExp(r'[,|;\s]+'), ' ').trim();
    if (remaining.isNotEmpty && remaining.length > 2) result['nama'] = remaining;

    return result;
  }

  void _openAddScanner({
    required TextEditingController namaCtrl,
    required TextEditingController imeiCtrl,
    required TextEditingController storageCtrl,
    required TextEditingController warnaCtrl,
    required void Function(void Function()) setModalState,
  }) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _BarcodeScannerPage(
        onScanned: (String code) {
          Navigator.pop(context);
          final parsed = _parseBarcodeData(code);
          setModalState(() {
            if (parsed['imei'] != null && imeiCtrl.text.isEmpty) imeiCtrl.text = parsed['imei']!;
            if (parsed['nama'] != null && namaCtrl.text.isEmpty) namaCtrl.text = parsed['nama']!.toUpperCase();
            if (parsed['storage'] != null && storageCtrl.text.isEmpty) storageCtrl.text = parsed['storage']!.toUpperCase();
            if (parsed['warna'] != null && warnaCtrl.text.isEmpty) warnaCtrl.text = parsed['warna']!.toUpperCase();
          });
          if (parsed.isNotEmpty) {
            _snack('Auto-detect: ${parsed.keys.join(', ')}');
          } else {
            _snack('Barcode dikesan tetapi tiada maklumat dikenali', err: true);
          }
        },
      ),
    ));
  }

  List<String> get _modelList {
    final models = _inventory.map((d) => (d['nama'] ?? '').toString().toUpperCase()).where((n) => n.isNotEmpty).toSet().toList();
    models.sort();
    return ['SEMUA', ...models];
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    var data = List<Map<String, dynamic>>.from(_inventory);

    // Filter by model
    if (_selectedModel != 'SEMUA') {
      data = data.where((d) => (d['nama'] ?? '').toString().toUpperCase() == _selectedModel).toList();
    }

    // Filter by kategori
    if (_selectedKategori != 'SEMUA') {
      data = data.where((d) => (d['kategori'] ?? '').toString().toUpperCase() == _selectedKategori).toList();
    }

    // Filter by search
    if (q.isNotEmpty) {
      data = data.where((d) =>
          (d['kod'] ?? '').toString().toLowerCase().contains(q) ||
          (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
          (d['imei'] ?? '').toString().toLowerCase().contains(q)).toList();
    }

    _filtered = data;
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _generateKod() {
    final rand = Random();
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'PH-$code';
  }

  String _fmt(dynamic ts) {
    if (ts is int) return DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(ts));
    if (ts is Timestamp) return DateFormat('dd/MM/yy').format(ts.toDate());
    return '-';
  }

  void _openSearchScanner() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _BarcodeScannerPage(
        onScanned: (String code) {
          Navigator.pop(context);
          final cleanCode = code.trim().toUpperCase();
          if (cleanCode.isNotEmpty) {
            setState(() {
              _searchCtrl.text = cleanCode;
              _filter();
            });
          }
        },
      ),
    ));
  }

  // ═══════════════════════════════════════
  // IMAGE UPLOAD
  // ═══════════════════════════════════════

  Future<File?> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 40,
    );
    if (picked == null) return null;
    final file = File(picked.path);
    final size = await file.length();
    if (size > 100 * 1024) {
      _snack('Gambar melebihi 100KB. Sila pilih gambar lebih kecil.', err: true);
      return null;
    }
    return file;
  }

  Future<String?> _uploadImage(File file, String kod) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child('phone_stock/$_ownerID/${kod}_$ts.jpg');
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await task.ref.getDownloadURL();
  }

  // ═══════════════════════════════════════
  // ADD PHONE STOCK MODAL
  // ═══════════════════════════════════════

  void _showAddModal() {
    _kodCtrl.text = _generateKod();
    _namaCtrl.text = '';
    _jualCtrl.text = '';

    final imeiCtrl = TextEditingController();
    final warnaCtrl = TextEditingController();
    final storageCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    String selectedCategory = _categories.first;
    String selectedSupplier = _suppliers.isNotEmpty ? _suppliers.first : '';
    String selectedStaff = _staffList.isNotEmpty ? _staffList.first : '';
    File? pickedImage;
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(_lang.get('ps_tambah'), style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
                  ]),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red),
                  ),
                ]),
                const SizedBox(height: 16),

                // Image picker
                GestureDetector(
                  onTap: () async {
                    final file = await _pickImage();
                    if (file != null) setModalState(() => pickedImage = file);
                  },
                  child: Container(
                    width: double.infinity,
                    height: 150,
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderMed),
                    ),
                    child: pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(pickedImage!, fit: BoxFit.cover, width: double.infinity, height: 150))
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const FaIcon(FontAwesomeIcons.camera, size: 28, color: AppColors.textDim),
                            const SizedBox(height: 8),
                            Text(_lang.get('ps_tekan_gambar'), style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Kategori dropdown + butang tambah
                const Text('Kategori', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _categories.contains(selectedCategory) ? selectedCategory : _categories.first,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) => setModalState(() => selectedCategory = v ?? _categories.first),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: _actionBtn(FontAwesomeIcons.plus, 'CUSTOM', AppColors.green, () {
                      _showAddCategoryDialog(setModalState, () => selectedCategory, (v) => selectedCategory = v);
                    }),
                  ),
                ]),
                const SizedBox(height: 10),

                // Supplier dropdown + tambah
                const Text('Supplier', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _suppliers.contains(selectedSupplier) ? selectedSupplier : null,
                          hint: const Text('Pilih supplier', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          items: _suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setModalState(() => selectedSupplier = v ?? ''),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _actionBtn(FontAwesomeIcons.plus, 'TAMBAH', AppColors.green, () {
                    _showAddSupplierDialog(setModalState, (name) => selectedSupplier = name);
                  }),
                ]),
                const SizedBox(height: 10),

                // Kod with auto-generate + scan barcode
                Row(children: [
                  Expanded(child: _formField('Kod Item', _kodCtrl, 'Cth: PH-ABC123')),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _actionBtn(FontAwesomeIcons.rotate, 'AUTO', AppColors.cyan, () {
                      setModalState(() => _kodCtrl.text = _generateKod());
                    }),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _actionBtn(FontAwesomeIcons.qrcode, 'SCAN', AppColors.primary, () {
                      _openAddScanner(
                        namaCtrl: _namaCtrl,
                        imeiCtrl: imeiCtrl,
                        storageCtrl: storageCtrl,
                        warnaCtrl: warnaCtrl,
                        setModalState: setModalState,
                      );
                    }),
                  ),
                ]),

                // Staff dropdown
                const Text('Staff', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _staffList.contains(selectedStaff) ? selectedStaff : (_staffList.isNotEmpty ? _staffList.first : null),
                      hint: const Text('Pilih staff', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                      items: _staffList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setModalState(() => selectedStaff = v ?? ''),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                _formField('Nama Telefon', _namaCtrl, 'Cth: iPhone 13 Pro Max'),
                _formField('IMEI', imeiCtrl, 'No IMEI telefon', keyboard: TextInputType.number),

                Row(children: [
                  Expanded(child: _formField('Warna', warnaCtrl, 'Cth: Black')),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Storage', storageCtrl, 'Cth: 128GB')),
                ]),

                _formField('Harga Jual (RM)', _jualCtrl, '0.00', keyboard: TextInputType.number),
                _formField('Nota', notaCtrl, 'Nota tambahan (pilihan)'),

                const SizedBox(height: 10),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: uploading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _buildGlassButton(
                          icon: FontAwesomeIcons.floppyDisk,
                          label: _lang.get('simpan'),
                          color: AppColors.primary,
                          onTap: () async {
                            if (_namaCtrl.text.trim().isEmpty) {
                              _snack('Sila isi Nama Telefon', err: true);
                              return;
                            }
                            setModalState(() => uploading = true);

                            String? imageUrl;
                            if (pickedImage != null) {
                              imageUrl = await _uploadImage(pickedImage!, _kodCtrl.text.trim());
                            }

                            final savedData = {
                              'kod': _kodCtrl.text.trim().toUpperCase(),
                              'nama': _namaCtrl.text.trim().toUpperCase(),
                              'imei': imeiCtrl.text.trim(),
                              'warna': warnaCtrl.text.trim().toUpperCase(),
                              'storage': storageCtrl.text.trim().toUpperCase(),
                              'jual': double.tryParse(_jualCtrl.text) ?? 0,
                              'nota': notaCtrl.text.trim(),
                              'tarikh_masuk': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                              'masa_masuk': DateFormat('HH:mm').format(DateTime.now()),
                              'staffMasuk': selectedStaff,
                              'imageUrl': imageUrl ?? '',
                              'kategori': selectedCategory,
                              'supplier': selectedSupplier,
                              'status': 'AVAILABLE',
                              'timestamp': DateTime.now().millisecondsSinceEpoch,
                              'shopID': _shopID,
                            };
                            await _db.collection('phone_stock_$_ownerID').add(savedData);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('Stok telefon berjaya ditambah');

                            // Auto print lepas save
                            if (_autoPrintBarcode) {
                              _printBarcodeLabel(savedData);
                            } else if (_autoPrintDetail) {
                              _printDetailLabel(savedData);
                            }
                          },
                        ),
                ),
              ],
            )),
          ),
        );
      }),
    );
  }

  // ═══════════════════════════════════════
  // EDIT MODAL
  // ═══════════════════════════════════════

  void _showEditModal(Map<String, dynamic> item) {
    final kodCtrl = TextEditingController(text: item['kod'] ?? '');
    final namaCtrl = TextEditingController(text: item['nama'] ?? '');
    final imeiCtrl = TextEditingController(text: item['imei'] ?? '');
    final warnaCtrl = TextEditingController(text: item['warna'] ?? '');
    final storageCtrl = TextEditingController(text: item['storage'] ?? '');
    final jualCtrl = TextEditingController(text: (item['jual'] ?? 0).toString());
    final notaCtrl = TextEditingController(text: item['nota'] ?? '');
    String status = (item['status'] ?? 'AVAILABLE').toString().toUpperCase();
    String existingImageUrl = (item['imageUrl'] ?? '').toString();
    String selectedStaff = (item['staffJual'] ?? '').toString();
    if (selectedStaff.isEmpty && _staffList.isNotEmpty) selectedStaff = _staffList.first;
    String selectedCategory = (item['kategori'] ?? 'BARU').toString().toUpperCase();
    if (!_categories.contains(selectedCategory)) selectedCategory = _categories.first;
    File? pickedImage;
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: AppColors.yellow),
                    const SizedBox(width: 8),
                    Text(_lang.get('ps_edit'), style: const TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
                  ]),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red),
                  ),
                ]),
                const SizedBox(height: 16),

                // Image picker / preview
                GestureDetector(
                  onTap: () async {
                    final file = await _pickImage();
                    if (file != null) setModalState(() => pickedImage = file);
                  },
                  child: Container(
                    width: double.infinity,
                    height: 150,
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderMed),
                    ),
                    child: pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(pickedImage!, fit: BoxFit.cover, width: double.infinity, height: 150))
                        : existingImageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(existingImageUrl, fit: BoxFit.cover, width: double.infinity, height: 150,
                                    errorBuilder: (_, __, ___) => const Center(child: FaIcon(FontAwesomeIcons.image, size: 28, color: AppColors.textDim))))
                            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const FaIcon(FontAwesomeIcons.camera, size: 28, color: AppColors.textDim),
                                const SizedBox(height: 8),
                                Text(_lang.get('ps_tekan_gambar'), style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
                              ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Kategori dropdown + butang tambah
                const Text('Kategori', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _categories.contains(selectedCategory) ? selectedCategory : _categories.first,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) => setModalState(() => selectedCategory = v ?? _categories.first),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _actionBtn(FontAwesomeIcons.plus, 'CUSTOM', AppColors.green, () {
                    _showAddCategoryDialog(setModalState, () => selectedCategory, (v) => selectedCategory = v);
                  }),
                ]),
                const SizedBox(height: 10),

                _formField('Kod Item', kodCtrl, '', readOnly: true),
                _formField('Nama Telefon', namaCtrl, 'Nama telefon'),
                _formField('IMEI', imeiCtrl, 'No IMEI', keyboard: TextInputType.number),
                Row(children: [
                  Expanded(child: _formField('Warna', warnaCtrl, 'Warna')),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Storage', storageCtrl, 'Storage')),
                ]),
                _formField('Harga Jual (RM)', jualCtrl, '0.00', keyboard: TextInputType.number),
                _formField('Nota', notaCtrl, 'Nota tambahan'),

                // Status toggle
                const SizedBox(height: 6),
                Text(_lang.get('status'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(children: [
                  _statusChip('AVAILABLE', status, AppColors.green, () => setModalState(() => status = 'AVAILABLE')),
                  const SizedBox(width: 6),
                  _statusChip('SOLD', status, AppColors.red, () => setModalState(() => status = 'SOLD')),
                  const SizedBox(width: 6),
                  _statusChip('RESERVED', status, AppColors.yellow, () => setModalState(() => status = 'RESERVED')),
                ]),

                // Staff dropdown (visible when SOLD)
                if (status == 'SOLD' && _staffList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Staff Jual', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _staffList.contains(selectedStaff) ? selectedStaff : _staffList.first,
                        isExpanded: true,
                        dropdownColor: AppColors.bgDeep,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        items: _staffList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setModalState(() => selectedStaff = v ?? ''),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Update & Delete buttons
                Row(children: [
                  Expanded(
                    child: uploading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : _buildGlassButton(
                            icon: FontAwesomeIcons.check,
                            label: 'KEMASKINI',
                            color: AppColors.primary,
                            onTap: () async {
                              setModalState(() => uploading = true);

                              String? imageUrl;
                              if (pickedImage != null) {
                                imageUrl = await _uploadImage(pickedImage!, kodCtrl.text.trim());
                              }

                              final updateData = <String, dynamic>{
                                'kod': kodCtrl.text.trim().toUpperCase(),
                                'nama': namaCtrl.text.trim().toUpperCase(),
                                'imei': imeiCtrl.text.trim(),
                                'warna': warnaCtrl.text.trim().toUpperCase(),
                                'storage': storageCtrl.text.trim().toUpperCase(),
                                'jual': double.tryParse(jualCtrl.text) ?? 0,
                                'nota': notaCtrl.text.trim(),
                                'kategori': selectedCategory,
                                'status': status,
                                if (status == 'SOLD') 'staffJual': selectedStaff,
                              };
                              if (imageUrl != null) updateData['imageUrl'] = imageUrl;

                              await _db.collection('phone_stock_$_ownerID').doc(item['id']).update(updateData);

                              // Bila status SOLD, SELALU masuk history
                              if (status == 'SOLD') {
                                // Check kalau dah ada record utk stock ni, skip duplicate
                                final existing = await _db.collection('phone_sales_$_ownerID')
                                    .where('stockDocId', isEqualTo: item['id'])
                                    .limit(1).get();
                                if (existing.docs.isEmpty) {
                                  final saleRef = _db.collection('phone_sales_$_ownerID').doc();
                                  await saleRef.set({
                                    'kod': kodCtrl.text.trim().toUpperCase(),
                                    'nama': namaCtrl.text.trim().toUpperCase(),
                                    'imei': imeiCtrl.text.trim(),
                                    'warna': warnaCtrl.text.trim().toUpperCase(),
                                    'storage': storageCtrl.text.trim().toUpperCase(),
                                    'jual': double.tryParse(jualCtrl.text) ?? 0,
                                    'imageUrl': imageUrl ?? (item['imageUrl'] ?? ''),
                                    'tarikh_jual': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                                    'shopID': _shopID,
                                    'stockDocId': item['id'],
                                    'staffJual': selectedStaff,
                                    'siri': saleRef.id,
                                  });
                                }
                              }

                              if (ctx.mounted) Navigator.pop(ctx);
                              _snack(status == 'SOLD'
                                  ? 'Stok dikemaskini & direkod dalam jualan'
                                  : 'Stok dikemaskini');
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete(item);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                      ),
                      child: const FaIcon(FontAwesomeIcons.trash, size: 14, color: AppColors.red),
                    ),
                  ),
                ]),
              ],
            )),
          ),
        );
      }),
    );
  }

  void _confirmDelete(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_lang.get('ps_padam_stok'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text('${item['nama'] ?? item['kod']} akan dimasukkan ke tong sampah. Auto padam kekal selepas 30 hari.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal'))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Soft delete — move to trash
              final data = Map<String, dynamic>.from(item);
              data.remove('id');
              data['deletedAt'] = DateTime.now().millisecondsSinceEpoch;
              data['originalDocId'] = item['id'];
              await _db.collection('phone_trash_$_ownerID').add(data);
              await _db.collection('phone_stock_$_ownerID').doc(item['id']).delete();
              _snack('Stok dimasukkan ke tong sampah');
            },
            child: Text(_lang.get('padam'), style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // ═══════════════════════════════════════
  // INVENTORY SETTINGS (AUTO PRINT)
  // ═══════════════════════════════════════

  void _showInventorySettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    FaIcon(FontAwesomeIcons.gear, size: 14, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('TETAPAN INVENTORI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Auto print lepas simpan stok baru', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _settingToggle(
                        icon: FontAwesomeIcons.barcode,
                        color: AppColors.primary,
                        title: 'Auto Print Barcode',
                        subtitle: 'Cetak barcode IMEI selepas simpan',
                        value: _autoPrintBarcode,
                        onChanged: (v) async {
                          final prefs = await SharedPreferences.getInstance();
                          setState(() => _autoPrintBarcode = v);
                          setS(() {});
                          await prefs.setBool('ps_auto_print_barcode', v);
                          // Kalau on barcode, off detail (pilih satu je)
                          if (v && _autoPrintDetail) {
                            setState(() => _autoPrintDetail = false);
                            setS(() {});
                            await prefs.setBool('ps_auto_print_detail', false);
                          }
                        },
                      ),
                      const Divider(height: 16, color: AppColors.borderMed),
                      _settingToggle(
                        icon: FontAwesomeIcons.fileLines,
                        color: AppColors.orange,
                        title: 'Auto Print Detail',
                        subtitle: 'Cetak detail penuh selepas simpan',
                        value: _autoPrintDetail,
                        onChanged: (v) async {
                          final prefs = await SharedPreferences.getInstance();
                          setState(() => _autoPrintDetail = v);
                          setS(() {});
                          await prefs.setBool('ps_auto_print_detail', v);
                          // Kalau on detail, off barcode (pilih satu je)
                          if (v && _autoPrintBarcode) {
                            setState(() => _autoPrintBarcode = false);
                            setS(() {});
                            await prefs.setBool('ps_auto_print_barcode', false);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingToggle({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        FaIcon(icon, size: 14, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              Text(subtitle, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: color,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // GENERATE BARCODE (PRINT LABEL)
  // ═══════════════════════════════════════

  Future<void> _printLabel(Map<String, dynamic> item) async {
    // Popup pilih jenis label: Barcode atau Detail
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  FaIcon(FontAwesomeIcons.print, size: 14, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('CETAK LABEL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _printBarcodeLabel(item);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: const Column(
                          children: [
                            FaIcon(FontAwesomeIcons.barcode, size: 28, color: AppColors.primary),
                            SizedBox(height: 8),
                            Text('BARCODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primary)),
                            SizedBox(height: 2),
                            Text('Scan terus ke telefon', style: TextStyle(fontSize: 8, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _printDetailLabel(item);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
                        ),
                        child: const Column(
                          children: [
                            FaIcon(FontAwesomeIcons.fileLines, size: 28, color: AppColors.orange),
                            SizedBox(height: 8),
                            Text('DETAIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.orange)),
                            SizedBox(height: 2),
                            Text('Info penuh telefon', style: TextStyle(fontSize: 8, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Cetak barcode label guna IMEI — scan nanti terus tuju ke telefon ni
  Future<void> _printBarcodeLabel(Map<String, dynamic> item) async {
    final imei = (item['imei'] ?? '').toString();
    final kod = (item['kod'] ?? '-').toString();
    final nama = (item['nama'] ?? '-').toString();
    final jual = ((item['jual'] ?? 0) as num).toStringAsFixed(2);

    if (imei.isEmpty) {
      _snack('IMEI tiada — tidak boleh cetak barcode', err: true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final labelW = double.tryParse(prefs.getString('printer_label_width') ?? '50') ?? 50;

    const escInit = '\x1B\x40';
    const escCenter = '\x1B\x61\x01';
    const escBoldOn = '\x1B\x45\x01';
    const escBoldOff = '\x1B\x45\x00';
    const escFontB = '\x1B\x4D\x01';

    var r = escInit;
    r += escCenter;

    // Font kecil untuk label
    if (labelW <= 50) {
      r += escFontB;
      r += '\x1D\x21\x00';
      r += '\x1B\x20\x00';
      r += '\x1B\x33\x10';
    } else {
      r += '\x1B\x4D\x00$escBoldOn';
      r += '\x1D\x21\x00';
      r += '\x1B\x33\x1A';
    }

    r += '$escBoldOn$kod$escBoldOff\n';
    r += '$nama\n';
    r += 'RM $jual\n';

    // ── Barcode CODE128 guna IMEI ──
    // GS k m d1...dk NUL — Print barcode
    // Set barcode height: GS h n
    r += '\x1D\x68\x30';          // barcode height 48 dots
    // Set barcode width: GS w n
    r += '\x1D\x77\x02';          // barcode width 2
    // HRI position below: GS H n (2 = below)
    r += '\x1D\x48\x02';
    // HRI font: GS f n (1 = Font B kecil)
    r += '\x1D\x66\x01';
    // Print CODE128: GS k 73 n data
    final imeiBytes = utf8.encode(imei);
    r += '\x1D\x6B\x49${String.fromCharCode(imeiBytes.length)}';
    // Append IMEI bytes after
    final cmdBytes = utf8.encode(r);
    final fullBytes = [...cmdBytes, ...imeiBytes, ...utf8.encode('\n\x0C')];

    _snack('Mencetak barcode...');
    final ok = await _printer.writeLabelRaw(fullBytes);
    _snack(ok ? 'Barcode label berjaya dicetak' : 'Gagal cetak. Sila sambung printer label', err: !ok);
  }

  /// Cetak detail label — info penuh telefon macam repair label
  Future<void> _printDetailLabel(Map<String, dynamic> item) async {
    final job = {
      'siri': item['kod'] ?? '-',
      'nama': item['nama'] ?? '-',
      'tel': '-',
      'model': '${item['warna'] ?? ''} ${item['storage'] ?? ''}'.trim(),
      'kerosakan': 'IMEI: ${item['imei'] ?? '-'}',
      'harga': ((item['jual'] ?? 0) as num).toStringAsFixed(2),
    };

    _snack('Mencetak detail label...');
    final ok = await _printer.printLabel(job, {});
    _snack(ok ? 'Detail label berjaya dicetak' : 'Gagal cetak. Sila sambung printer label', err: !ok);
  }

  // ═══════════════════════════════════════
  // HISTORY JUALAN
  // ═══════════════════════════════════════

  void _showSalesHistoryAtTab(int tab) {
    int historySegment = tab;
    final searchCtrl = TextEditingController();
    String searchQuery = '';
    DateTime? selectedDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('HISTORY & REKOD', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: searchCtrl,
                onChanged: (v) => setModalState(() => searchQuery = v.toLowerCase().trim()),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Cari nama, IMEI, kod, supplier...',
                  hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 16),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () => setModalState(() { searchCtrl.clear(); searchQuery = ''; }),
                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.close, color: AppColors.textMuted, size: 14)),
                      ),
                    // Calendar button
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary)),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FaIcon(FontAwesomeIcons.calendarDay, size: 14,
                            color: selectedDate != null ? AppColors.primary : AppColors.textMuted),
                      ),
                    ),
                  ]),
                  filled: true, fillColor: AppColors.bgDeep, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
            // Date chip (jika selected)
            if (selectedDate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(DateFormat('dd/MM/yyyy').format(selectedDate!), style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setModalState(() => selectedDate = null),
                        child: const Icon(Icons.close, size: 12, color: AppColors.primary),
                      ),
                    ]),
                  ),
                ]),
              ),
            // 4 segments: History, Return, Transfer, Tong Sampah
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                _historySegBtn(0, 'HISTORY', FontAwesomeIcons.clockRotateLeft, AppColors.green, historySegment, (v) => setModalState(() => historySegment = v)),
                const SizedBox(width: 4),
                _historySegBtn(1, 'RETURN', FontAwesomeIcons.truckRampBox, AppColors.red, historySegment, (v) => setModalState(() => historySegment = v)),
                const SizedBox(width: 4),
                _historySegBtn(2, 'TRANSFER', FontAwesomeIcons.rightLeft, AppColors.blue, historySegment, (v) => setModalState(() => historySegment = v)),
                const SizedBox(width: 4),
                _historySegBtn(3, 'SAMPAH', FontAwesomeIcons.trashCan, AppColors.red, historySegment, (v) => setModalState(() => historySegment = v)),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(child: historySegment == 0
                ? _buildSalesTab(searchQuery: searchQuery, dateFilter: selectedDate)
                : historySegment == 1
                    ? _buildSalesTab(searchQuery: searchQuery, dateFilter: selectedDate, filterType: 'RETURN')
                    : historySegment == 2
                        ? _buildSalesTab(searchQuery: searchQuery, dateFilter: selectedDate, filterType: 'TRANSFER')
                        : _buildSalesTrashTab(searchQuery: searchQuery, dateFilter: selectedDate)),
          ]),
        );
      }),
    );
  }

  Widget _historySegBtn(int idx, String label, IconData icon, Color color, int current, void Function(int) onTap) {
    final active = current == idx;
    return Expanded(child: GestureDetector(
      onTap: () => onTap(idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? color : AppColors.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 9, color: active ? Colors.white : AppColors.textDim),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: active ? Colors.white : AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900)),
        ]),
      ),
    ));
  }

  Widget _buildSalesTab({String searchQuery = '', DateTime? dateFilter, String? filterType}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('phone_sales_$_ownerID').orderBy('timestamp', descending: true).limit(200).snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        var docs = snap.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (data['shopID']?.toString().toUpperCase() != _shopID) return false;
          // Filter by type
          if (filterType != null) {
            final action = (data['actionType'] ?? 'SOLD').toString().toUpperCase();
            if (filterType == 'RETURN' && !action.contains('RETURN') && !action.contains('REVERSE')) return false;
            if (filterType == 'TRANSFER' && !action.contains('TRANSFER') && !action.contains('TERIMA')) return false;
          }
          // Filter by search
          if (searchQuery.isNotEmpty) {
            final searchable = '${data['nama'] ?? ''} ${data['kod'] ?? ''} ${data['imei'] ?? ''} ${data['supplier'] ?? ''} ${data['staffJual'] ?? ''}'.toLowerCase();
            if (!searchable.contains(searchQuery)) return false;
          }
          // Filter by date
          if (dateFilter != null) {
            final ts = (data['timestamp'] as num?)?.toInt();
            if (ts != null) {
              final itemDate = DateTime.fromMillisecondsSinceEpoch(ts);
              if (itemDate.year != dateFilter.year || itemDate.month != dateFilter.month || itemDate.day != dateFilter.day) return false;
            }
          }
          return true;
        }).toList();
        if (docs.isEmpty) return Center(child: Text(_lang.get('ps_tiada_rekod_jual'), style: const TextStyle(color: AppColors.textMuted)));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            final nama = (d['nama'] ?? '-').toString();
            final jual = ((d['jual'] ?? 0) as num).toDouble();
            final warna = (d['warna'] ?? '-').toString();
            final storage = (d['storage'] ?? '-').toString();
            final imei = (d['imei'] ?? '-').toString();
            final staff = (d['staffJual'] ?? d['staffName'] ?? '-').toString();
            final siri = (d['siri'] ?? docId).toString();
            final ts = d['timestamp'];
            final tarikh = ts is int ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts)) : (d['tarikh_jual'] ?? '-').toString();
            final actionType = (d['actionType'] ?? 'SOLD').toString();
            final supplier = (d['supplier'] ?? '').toString();
            final actionColor = actionType.contains('RETURN') ? AppColors.red
                : actionType.contains('TRANSFER') || actionType.contains('TERIMA') ? AppColors.blue
                : actionType.contains('REVERSE') ? AppColors.yellow
                : AppColors.green;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Baris 1: Model + Harga + Action badge
                Row(children: [
                  Expanded(child: Text('$nama   RM${jual.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
                      overflow: TextOverflow.ellipsis, maxLines: 1)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(actionType, style: TextStyle(color: actionColor, fontSize: 7, fontWeight: FontWeight.w900)),
                  ),
                ]),
                const SizedBox(height: 3),
                // Baris 2: Warna • Storage • IMEI • Supplier
                Text('$warna  •  $storage  •  IMEI: $imei${supplier.isNotEmpty ? '  •  $supplier' : ''}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 3),
                // Baris 3: Tarikh • Staff • No Siri
                Row(children: [
                  Expanded(child: Text('$tarikh  •  $staff  •  #$siri',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis, maxLines: 1)),
                  GestureDetector(
                    onTap: () => _confirmDeleteSale(docId, d),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                      ),
                      child: const FaIcon(FontAwesomeIcons.trash, size: 10, color: AppColors.red),
                    ),
                  ),
                ]),
              ]),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════
  // DELETE SALE & TRASH TAB
  // ═══════════════════════════════════════

  void _confirmDeleteSale(String docId, Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padam Rekod Jualan?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text('${d['nama'] ?? '-'} akan dimasukkan ke tong sampah. Boleh recover dalam 30 hari.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal'))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final data = Map<String, dynamic>.from(d);
              data['deletedAt'] = DateTime.now().millisecondsSinceEpoch;
              data['originalSaleDocId'] = docId;
              await _db.collection('phone_sales_trash_$_ownerID').add(data);
              await _db.collection('phone_sales_$_ownerID').doc(docId).delete();
              _snack('Rekod dimasukkan ke tong sampah');
            },
            child: Text(_lang.get('padam'), style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTrashTab({String searchQuery = '', DateTime? dateFilter}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('phone_sales_trash_$_ownerID').orderBy('deletedAt', descending: true).limit(100).snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final now = DateTime.now().millisecondsSinceEpoch;
        final thirtyDays = 30 * 24 * 60 * 60 * 1000;
        final docs = snap.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if ((data['shopID'] ?? '').toString().toUpperCase() != _shopID) return false;
          final deletedAt = (data['deletedAt'] as num?)?.toInt() ?? 0;
          if ((now - deletedAt) >= thirtyDays) return false;
          // Filter by search
          if (searchQuery.isNotEmpty) {
            final searchable = '${data['nama'] ?? ''} ${data['kod'] ?? ''} ${data['imei'] ?? ''} ${data['supplier'] ?? ''}'.toLowerCase();
            if (!searchable.contains(searchQuery)) return false;
          }
          // Filter by date
          if (dateFilter != null) {
            final itemDate = DateTime.fromMillisecondsSinceEpoch(deletedAt);
            if (itemDate.year != dateFilter.year || itemDate.month != dateFilter.month || itemDate.day != dateFilter.day) return false;
          }
          return true;
        }).toList();
        if (docs.isEmpty) return const Center(child: Text('Tiada rekod dalam tong sampah', style: TextStyle(color: AppColors.textMuted)));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            final nama = (d['nama'] ?? '-').toString();
            final jual = ((d['jual'] ?? 0) as num).toDouble();
            final warna = (d['warna'] ?? '-').toString();
            final storage = (d['storage'] ?? '-').toString();
            final imei = (d['imei'] ?? '-').toString();
            final deletedAt = (d['deletedAt'] as num?)?.toInt() ?? 0;
            final daysLeft = 30 - ((now - deletedAt) / (24 * 60 * 60 * 1000)).floor();

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$nama   RM${jual.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 3),
                Text('$warna  •  $storage  •  IMEI: $imei',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: daysLeft <= 7 ? AppColors.red.withValues(alpha: 0.15) : AppColors.yellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('$daysLeft hari lagi', style: TextStyle(
                      color: daysLeft <= 7 ? AppColors.red : AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final data = Map<String, dynamic>.from(d);
                      data.remove('deletedAt');
                      data.remove('originalSaleDocId');
                      await _db.collection('phone_sales_$_ownerID').add(data);
                      await _db.collection('phone_sales_trash_$_ownerID').doc(docId).delete();
                      _snack('Rekod berjaya di-recover');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const FaIcon(FontAwesomeIcons.rotateLeft, size: 9, color: AppColors.green),
                        const SizedBox(width: 4),
                        const Text('RECOVER', style: TextStyle(color: AppColors.green, fontSize: 8, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ),
                ]),
              ]),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════

  Widget _formField(String label, TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text, bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          readOnly: readOnly,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
            filled: true,
            fillColor: readOnly ? AppColors.side : AppColors.bgDeep,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
          ),
        ),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _buildGlassButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, color.withValues(alpha: 0.7)]),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  Widget _statusChip(String label, String current, Color color, VoidCallback onTap) {
    final active = current == label;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color : AppColors.borderMed),
        ),
        child: Text(label, style: TextStyle(color: active ? color : AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900)),
      ),
    );
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.primary, width: 2)),
        ),
        child: Column(children: [
          // Title row: Return + Transfer + History + Tambah (sama besar)
          Row(children: [
            // Return Supplier button
            Expanded(child: GestureDetector(
              onTap: _showReturnSupplierList,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.truckRampBox, size: 10, color: AppColors.red),
                  SizedBox(width: 4),
                  Text('RETURN', style: TextStyle(color: AppColors.red, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
            const SizedBox(width: 4),
            // Transfer Cawangan button
            Expanded(child: GestureDetector(
              onTap: _showTransferCawanganList,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.blue.withValues(alpha: 0.4)),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.rightLeft, size: 10, color: AppColors.blue),
                  SizedBox(width: 4),
                  Text('TRANSFER', style: TextStyle(color: AppColors.blue, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
            const SizedBox(width: 4),
            // History button
            Expanded(child: GestureDetector(
              onTap: () => _showSalesHistoryAtTab(0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4)),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.clockRotateLeft, size: 10, color: AppColors.yellow),
                  SizedBox(width: 4),
                  Text('HISTORY', style: TextStyle(color: AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
            const SizedBox(width: 4),
            // Tambah button
            Expanded(child: GestureDetector(
              onTap: _showAddModal,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.blue]),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(_lang.get('tambah'), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
          ]),
          const SizedBox(height: 10),

          // Search
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(_filter),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: _lang.get('ps_cari_hint'),
              hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() { _searchCtrl.clear(); _filter(); }),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.close, color: AppColors.textMuted, size: 16),
                      ),
                    ),
                  GestureDetector(
                    onTap: _openSearchScanner,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: FaIcon(FontAwesomeIcons.barcode, size: 14, color: AppColors.primary),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showInventorySettings,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: FaIcon(FontAwesomeIcons.gear, size: 13,
                        color: (_autoPrintBarcode || _autoPrintDetail)
                          ? AppColors.orange : AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              filled: true, fillColor: AppColors.bgDeep, isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          // Model & Kategori filter dropdowns
          Row(children: [
            // Model filter dropdown
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const FaIcon(FontAwesomeIcons.filter, size: 9, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _modelList.contains(_selectedModel) ? _selectedModel : 'SEMUA',
                        isDense: true,
                        isExpanded: true,
                        icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 7, color: AppColors.primary),
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900),
                        items: _modelList.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900)))).toList(),
                        onChanged: (v) => setState(() { _selectedModel = v!; _filter(); }),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            // Kategori filter dropdown
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const FaIcon(FontAwesomeIcons.tag, size: 9, color: AppColors.yellow),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedKategori,
                        isDense: true,
                        isExpanded: true,
                        icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 7, color: AppColors.yellow),
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: AppColors.yellow, fontSize: 9, fontWeight: FontWeight.w900),
                        items: ['SEMUA', ..._categories].map((k) => DropdownMenuItem(value: k, child: Text(k, style: TextStyle(color: k == 'SECOND HAND' ? AppColors.yellow : AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900)))).toList(),
                        onChanged: (v) => setState(() { _selectedKategori = v!; _filter(); }),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ]),
      ),

      // Grid List
      Expanded(
        child: _inventory.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 40, color: AppColors.textDim),
                const SizedBox(height: 12),
                Text(_lang.get('ps_tiada_stok'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              ]))
            : _filtered.isEmpty
                ? Center(child: Text(_lang.get('ps_tiada_padanan'), style: const TextStyle(color: AppColors.textMuted)))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _filtered.length + _incomingTransfers.length,
                    itemBuilder: (_, i) {
                      // Show incoming transfers first (greyed out)
                      if (i < _incomingTransfers.length) {
                        return _incomingTransferCard(_incomingTransfers[i]);
                      }
                      return _phoneCard(_filtered[i - _incomingTransfers.length]);
                    },
                  ),
      ),

      // Footer
      _buildFooter(),
    ]);
  }

  Widget _phoneCard(Map<String, dynamic> d) {
    final nama = (d['nama'] ?? '-').toString();
    final jual = (d['jual'] as num?)?.toDouble() ?? 0;
    final status = (d['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final kategori = (d['kategori'] ?? '').toString().toUpperCase();
    final imageUrl = (d['imageUrl'] ?? '').toString();
    final statusColor = status == 'SOLD' ? AppColors.red : status == 'RESERVED' ? AppColors.yellow : AppColors.green;
    final kategoriColor = kategori == 'SECOND HAND' ? AppColors.yellow : AppColors.cyan;

    return GestureDetector(
      onLongPress: () => _showLongPressOptions(d),
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMed),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // Image — full display
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            child: Stack(children: [
              imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorBuilder: (_, __, ___) => Container(color: AppColors.bgDeep, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: AppColors.textDim))))
                  : Container(color: AppColors.bgDeep, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: AppColors.textDim))),
              // Status badge overlay
              Positioned(top: 6, right: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
                child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
              )),
              // Kategori badge
              if (kategori.isNotEmpty)
                Positioned(top: 6, left: 6, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: kategoriColor, borderRadius: BorderRadius.circular(4)),
                  child: Text(kategori, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
                )),
            ]),
          ),
        ),

        // Actions — icons only
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Row(children: [
            _miniBtn(FontAwesomeIcons.eye, AppColors.primary, () => _showDetailModal(d)),
            const SizedBox(width: 4),
            _miniBtn(FontAwesomeIcons.penToSquare, AppColors.blue, () => _showEditModal(d)),
            const SizedBox(width: 4),
            _miniBtn(FontAwesomeIcons.barcode, AppColors.yellow, () => _printLabel(d)),
          ]),
        ),
      ]),
    ));
  }

  Widget _miniBtn(IconData icon, Color color, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Center(child: FaIcon(icon, size: 10, color: color)),
      ),
    ));
  }

  // ═══════════════════════════════════════
  // DETAIL MODAL (eye icon)
  // ═══════════════════════════════════════

  void _showDetailModal(Map<String, dynamic> d) {
    final kod = (d['kod'] ?? '-').toString();
    final nama = (d['nama'] ?? '-').toString();
    final imei = (d['imei'] ?? '').toString();
    final warna = (d['warna'] ?? '').toString();
    final storage = (d['storage'] ?? '').toString();
    final jual = (d['jual'] as num?)?.toDouble() ?? 0;
    final status = (d['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final nota = (d['nota'] ?? '').toString();
    final kategori = (d['kategori'] ?? '').toString().toUpperCase();
    final imageUrl = (d['imageUrl'] ?? '').toString();
    final statusColor = status == 'SOLD' ? AppColors.red : status == 'RESERVED' ? AppColors.yellow : AppColors.green;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.only(top: 80),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image full
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              child: Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: 250,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 100, child: Center(child: FaIcon(FontAwesomeIcons.image, size: 32, color: AppColors.textDim)))),
            ),

          Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 8),

            // Status + Price
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Text('RM${jual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 18, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),

            // Details
            _detailRow('Kod', kod),
            if (kategori.isNotEmpty) _detailRow('Kategori', kategori),
            if (imei.isNotEmpty) _detailRow('IMEI', imei),
            if (warna.isNotEmpty) _detailRow('Warna', warna),
            if (storage.isNotEmpty) _detailRow('Storage', storage),
            _detailRow('Tarikh Masuk', d['tarikh_masuk'] ?? _fmt(d['timestamp'])),
            if (nota.isNotEmpty) _detailRow('Nota', nota),

            const SizedBox(height: 16),

            // Action buttons
            Row(children: [
              Expanded(child: _buildGlassButton(icon: FontAwesomeIcons.penToSquare, label: 'EDIT', color: AppColors.blue, onTap: () { Navigator.pop(ctx); _showEditModal(d); })),
              const SizedBox(width: 8),
              Expanded(child: _buildGlassButton(icon: FontAwesomeIcons.barcode, label: 'BARCODE', color: AppColors.primary, onTap: () { Navigator.pop(ctx); _printLabel(d); })),
            ]),
            const SizedBox(height: 16),
          ])),
        ])),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w900))),
        Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _infoBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800)),
    );
  }

  // ═══════════════════════════════════════
  // LONG PRESS OPTIONS (Return / Transfer)
  // ═══════════════════════════════════════

  void _showLongPressOptions(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text((item['nama'] ?? '-').toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 4),
          Text((item['kod'] ?? '').toString(), style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _buildGlassButton(
              icon: FontAwesomeIcons.truckRampBox,
              label: 'RETURN SUPPLIER',
              color: AppColors.red,
              onTap: () { Navigator.pop(ctx); _showReturnTypeDialog(item); },
            )),
            const SizedBox(width: 10),
            Expanded(child: _buildGlassButton(
              icon: FontAwesomeIcons.rightLeft,
              label: 'TRANSFER',
              color: AppColors.blue,
              onTap: () { Navigator.pop(ctx); _showTransferDialog(item); },
            )),
          ]),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════
  // RETURN SUPPLIER FLOW
  // ═══════════════════════════════════════

  void _showReturnTypeDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return Supplier', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${item['nama'] ?? '-'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Pilih jenis return:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BATAL')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _processReturn(item, 'PERMANENT'); },
            child: const Text('PERMANENT', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900)),
          ),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _processReturn(item, 'CLAIM'); },
            child: const Text('CLAIM', style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _processReturn(Map<String, dynamic> item, String type) async {
    final data = Map<String, dynamic>.from(item);
    final docId = data.remove('id');
    data['returnType'] = type; // PERMANENT or CLAIM
    data['returnStatus'] = 'RETURNED';
    data['returnDate'] = DateTime.now().millisecondsSinceEpoch;
    data['originalDocId'] = docId;
    data['fromShopID'] = _shopID;

    await _db.collection('phone_returns_$_ownerID').add(data);
    await _db.collection('phone_stock_$_ownerID').doc(docId).delete();

    // Rekod dalam history
    await _db.collection('phone_sales_$_ownerID').add({
      'nama': item['nama'] ?? '-',
      'kod': item['kod'] ?? '',
      'imei': item['imei'] ?? '',
      'warna': item['warna'] ?? '',
      'storage': item['storage'] ?? '',
      'jual': item['jual'] ?? 0,
      'shopID': _shopID,
      'actionType': 'RETURN $type',
      'supplier': item['supplier'] ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'staffJual': '-',
    });

    _snack(type == 'PERMANENT' ? 'Stok di-return permanent ke supplier' : 'Stok dihantar untuk claim');
  }

  // ═══════════════════════════════════════
  // RETURN SUPPLIER LIST
  // ═══════════════════════════════════════

  void _showReturnSupplierList() {
    final searchCtrl = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  FaIcon(FontAwesomeIcons.truckRampBox, size: 14, color: AppColors.red),
                  SizedBox(width: 8),
                  Text('RETURN SUPPLIER', style: TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: searchCtrl,
                onChanged: (v) => setModalState(() => searchQuery = v.toLowerCase().trim()),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Cari nama, IMEI, supplier...',
                  hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 16),
                  suffixIcon: searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () => setModalState(() { searchCtrl.clear(); searchQuery = ''; }),
                          child: const Icon(Icons.close, color: AppColors.textMuted, size: 14))
                      : null,
                  filled: true, fillColor: AppColors.bgDeep, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('phone_returns_$_ownerID')
                  .orderBy('returnDate', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                final docs = snap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  if (data['fromShopID']?.toString().toUpperCase() != _shopID) return false;
                  if (searchQuery.isNotEmpty) {
                    final searchable = '${data['nama'] ?? ''} ${data['imei'] ?? ''} ${data['kod'] ?? ''} ${data['supplier'] ?? ''}'.toLowerCase();
                    if (!searchable.contains(searchQuery)) return false;
                  }
                  return true;
                }).toList();
              if (docs.isEmpty) return const Center(child: Text('Tiada rekod return', style: TextStyle(color: AppColors.textMuted)));
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final docId = docs[i].id;
                  final nama = (d['nama'] ?? '-').toString();
                  final jual = ((d['jual'] ?? 0) as num).toDouble();
                  final type = (d['returnType'] ?? '-').toString();
                  final status = (d['returnStatus'] ?? '-').toString();
                  final imei = (d['imei'] ?? '').toString();
                  final returnDate = d['returnDate'] is int
                      ? DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(d['returnDate']))
                      : '-';
                  final typeColor = type == 'PERMANENT' ? AppColors.red : AppColors.yellow;
                  final isReversible = type == 'CLAIM' && status == 'RETURNED';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: typeColor.withValues(alpha: 0.25)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('$nama   RM${jual.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
                            overflow: TextOverflow.ellipsis, maxLines: 1)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(type, style: TextStyle(color: typeColor, fontSize: 8, fontWeight: FontWeight.w900)),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      if (imei.isNotEmpty) Text('IMEI: $imei', style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text('$returnDate  •  $status', style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (isReversible)
                          GestureDetector(
                            onTap: () async {
                              // Reverse claim — put back into stock
                              final stockData = Map<String, dynamic>.from(d);
                              stockData.remove('returnType');
                              stockData.remove('returnStatus');
                              stockData.remove('returnDate');
                              stockData.remove('originalDocId');
                              stockData.remove('fromShopID');
                              stockData['status'] = 'AVAILABLE';
                              stockData['shopID'] = _shopID;
                              stockData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
                              await _db.collection('phone_stock_$_ownerID').add(stockData);
                              await _db.collection('phone_returns_$_ownerID').doc(docId).delete();
                              // Rekod dalam history
                              await _db.collection('phone_sales_$_ownerID').add({
                                'nama': d['nama'] ?? '-',
                                'kod': d['kod'] ?? '',
                                'imei': d['imei'] ?? '',
                                'warna': d['warna'] ?? '',
                                'storage': d['storage'] ?? '',
                                'jual': d['jual'] ?? 0,
                                'shopID': _shopID,
                                'actionType': 'REVERSE CLAIM',
                                'supplier': d['supplier'] ?? '',
                                'timestamp': DateTime.now().millisecondsSinceEpoch,
                                'staffJual': '-',
                              });
                              if (mounted) _snack('Stok berjaya di-reverse masuk semula');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                FaIcon(FontAwesomeIcons.rotateLeft, size: 9, color: AppColors.green),
                                SizedBox(width: 4),
                                Text('REVERSE', style: TextStyle(color: AppColors.green, fontSize: 8, fontWeight: FontWeight.w900)),
                              ]),
                            ),
                          ),
                      ]),
                    ]),
                  );
                },
              );
            },
          )),
        ]),
      );
      }),
    );
  }

  // ═══════════════════════════════════════
  // TRANSFER CAWANGAN FLOW
  // ═══════════════════════════════════════

  void _showTransferDialog(Map<String, dynamic> item) {
    final idKedaiCtrl = TextEditingController();
    List<Map<String, dynamic>> savedBranches = [];
    bool loading = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        // Load saved branches
        if (loading) {
          _db.collection('saved_branches_$_ownerID')
              .where('fromShopID', isEqualTo: _shopID)
              .get()
              .then((snap) {
            final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
            if (ctx.mounted) setModalState(() { savedBranches = list; loading = false; });
          });
        }

        return Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Row(children: [
                FaIcon(FontAwesomeIcons.rightLeft, size: 14, color: AppColors.blue),
                SizedBox(width: 8),
                Text('TRANSFER CAWANGAN', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
              ]),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 8),
            Text('${item['nama'] ?? '-'}  •  ${item['kod'] ?? ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // Saved branches quick select
            if (savedBranches.isNotEmpty) ...[
              const Text('Cawangan Tersimpan:', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: savedBranches.map((b) {
                final shopId = (b['toShopID'] ?? '').toString();
                return GestureDetector(
                  onTap: () {
                    idKedaiCtrl.text = shopId;
                    setModalState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Text(shopId, style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 12),
            ],

            _formField('ID Kedai Destinasi', idKedaiCtrl, 'Masukkan ID kedai cawangan'),
            const SizedBox(height: 8),

            Row(children: [
              // Save branch checkbox area
              Expanded(child: _buildGlassButton(
                icon: FontAwesomeIcons.floppyDisk,
                label: 'SIMPAN & TRANSFER',
                color: AppColors.blue,
                onTap: () async {
                  final toShopID = idKedaiCtrl.text.trim().toUpperCase();
                  if (toShopID.isEmpty) { _snack('Sila masukkan ID kedai', err: true); return; }
                  if (toShopID == _shopID) { _snack('Tidak boleh transfer ke kedai sendiri', err: true); return; }
                  Navigator.pop(ctx);
                  await _processTransfer(item, toShopID, saveShop: true);
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildGlassButton(
                icon: FontAwesomeIcons.paperPlane,
                label: 'TRANSFER SAHAJA',
                color: AppColors.primary,
                onTap: () async {
                  final toShopID = idKedaiCtrl.text.trim().toUpperCase();
                  if (toShopID.isEmpty) { _snack('Sila masukkan ID kedai', err: true); return; }
                  if (toShopID == _shopID) { _snack('Tidak boleh transfer ke kedai sendiri', err: true); return; }
                  Navigator.pop(ctx);
                  await _processTransfer(item, toShopID, saveShop: false);
                },
              )),
            ]),
          ])),
        );
      }),
    );
  }

  Future<void> _processTransfer(Map<String, dynamic> item, String toShopID, {bool saveShop = false}) async {
    final data = Map<String, dynamic>.from(item);
    final docId = data.remove('id');

    // Save to transfer collection
    final transferData = <String, dynamic>{
      ...data,
      'fromShopID': _shopID,
      'toShopID': toShopID,
      'status': 'PENDING',
      'transferDate': DateTime.now().millisecondsSinceEpoch,
      'originalDocId': docId,
    };
    await _db.collection('phone_transfers_$_ownerID').add(transferData);

    // Remove from current stock
    await _db.collection('phone_stock_$_ownerID').doc(docId).delete();

    // Rekod dalam history
    await _db.collection('phone_sales_$_ownerID').add({
      'nama': item['nama'] ?? '-',
      'kod': item['kod'] ?? '',
      'imei': item['imei'] ?? '',
      'warna': item['warna'] ?? '',
      'storage': item['storage'] ?? '',
      'jual': item['jual'] ?? 0,
      'shopID': _shopID,
      'actionType': 'TRANSFER KE $toShopID',
      'supplier': item['supplier'] ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'staffJual': '-',
    });

    // Save branch for future use
    if (saveShop) {
      final existing = await _db.collection('saved_branches_$_ownerID')
          .where('fromShopID', isEqualTo: _shopID)
          .where('toShopID', isEqualTo: toShopID)
          .get();
      if (existing.docs.isEmpty) {
        await _db.collection('saved_branches_$_ownerID').add({
          'fromShopID': _shopID,
          'toShopID': toShopID,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    _snack('Stok berjaya ditransfer ke $toShopID');
  }

  // ═══════════════════════════════════════
  // TRANSFER CAWANGAN LIST
  // ═══════════════════════════════════════

  void _showTransferCawanganList() {
    final searchCtrl = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  FaIcon(FontAwesomeIcons.rightLeft, size: 14, color: AppColors.blue),
                  SizedBox(width: 8),
                  Text('TRANSFER CAWANGAN', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: searchCtrl,
                onChanged: (v) => setModalState(() => searchQuery = v.toLowerCase().trim()),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Cari nama, IMEI, cawangan...',
                  hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 16),
                  suffixIcon: searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () => setModalState(() { searchCtrl.clear(); searchQuery = ''; }),
                          child: const Icon(Icons.close, color: AppColors.textMuted, size: 14))
                      : null,
                  filled: true, fillColor: AppColors.bgDeep, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('phone_transfers_$_ownerID')
                  .orderBy('transferDate', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                final docs = snap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final matchShop = data['fromShopID']?.toString().toUpperCase() == _shopID ||
                         data['toShopID']?.toString().toUpperCase() == _shopID;
                  if (!matchShop) return false;
                  if (searchQuery.isNotEmpty) {
                    final searchable = '${data['nama'] ?? ''} ${data['imei'] ?? ''} ${data['kod'] ?? ''} ${data['fromShopID'] ?? ''} ${data['toShopID'] ?? ''}'.toLowerCase();
                    if (!searchable.contains(searchQuery)) return false;
                  }
                  return true;
                }).toList();
                if (docs.isEmpty) return const Center(child: Text('Tiada rekod transfer', style: TextStyle(color: AppColors.textMuted)));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final nama = (d['nama'] ?? '-').toString();
                    final jual = ((d['jual'] ?? 0) as num).toDouble();
                    final from = (d['fromShopID'] ?? '-').toString();
                    final to = (d['toShopID'] ?? '-').toString();
                    final status = (d['status'] ?? '-').toString();
                    final imei = (d['imei'] ?? '').toString();
                    final transferDate = d['transferDate'] is int
                        ? DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(d['transferDate']))
                        : '-';
                    final isFrom = from == _shopID;
                    final statusColor = status == 'PENDING' ? AppColors.yellow : AppColors.green;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isFrom ? AppColors.blue : AppColors.primary).withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: (isFrom ? AppColors.blue : AppColors.primary).withValues(alpha: 0.25)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('$nama   RM${jual.toStringAsFixed(0)}',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900),
                              overflow: TextOverflow.ellipsis, maxLines: 1)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                            child: Text(status, style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.w900)),
                          ),
                        ]),
                        const SizedBox(height: 3),
                        if (imei.isNotEmpty) Text('IMEI: $imei', style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Row(children: [
                          FaIcon(isFrom ? FontAwesomeIcons.arrowRight : FontAwesomeIcons.arrowLeft, size: 8, color: AppColors.textDim),
                          const SizedBox(width: 4),
                          Text(isFrom ? 'Ke: $to' : 'Dari: $from', style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Text(transferDate, style: const TextStyle(color: AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w600)),
                        ]),
                      ]),
                    );
                  },
                );
              },
            )),
          ]),
        );
      }),
    );
  }

  // ═══════════════════════════════════════
  // INCOMING TRANSFER CARD (greyed out)
  // ═══════════════════════════════════════

  Widget _incomingTransferCard(Map<String, dynamic> d) {
    final from = (d['fromShopID'] ?? '-').toString();
    final imageUrl = (d['imageUrl'] ?? '').toString();
    final docId = d['id'];

    return Opacity(
      opacity: 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Column(children: [
          // Image
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              child: Stack(children: [
                imageUrl.isNotEmpty
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
                        child: Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                            errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: Colors.grey)))))
                    : Container(color: Colors.grey.shade300, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: Colors.grey))),
                // Incoming badge
                Positioned(top: 6, right: 6, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(4)),
                  child: const Text('INCOMING', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
                )),
                // From badge
                Positioned(top: 6, left: 6, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                  child: Text('Dari: $from', style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700)),
                )),
              ]),
            ),
          ),
          // Accept button
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: GestureDetector(
              onTap: () => _acceptTransfer(d, docId),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FaIcon(FontAwesomeIcons.check, size: 10, color: Colors.white),
                  SizedBox(width: 4),
                  Text('TERIMA', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _acceptTransfer(Map<String, dynamic> transfer, String transferDocId) async {
    final data = Map<String, dynamic>.from(transfer);
    data.remove('id');
    data.remove('fromShopID');
    data.remove('toShopID');
    data.remove('status');
    data.remove('transferDate');
    data.remove('originalDocId');

    // Add to current shop stock
    data['shopID'] = _shopID;
    data['status'] = 'AVAILABLE';
    data['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    await _db.collection('phone_stock_$_ownerID').add(data);

    // Update transfer status
    await _db.collection('phone_transfers_$_ownerID').doc(transferDocId).update({'status': 'ACCEPTED'});

    // Rekod dalam history
    await _db.collection('phone_sales_$_ownerID').add({
      'nama': transfer['nama'] ?? '-',
      'kod': transfer['kod'] ?? '',
      'imei': transfer['imei'] ?? '',
      'warna': transfer['warna'] ?? '',
      'storage': transfer['storage'] ?? '',
      'jual': transfer['jual'] ?? 0,
      'shopID': _shopID,
      'actionType': 'TERIMA DARI ${transfer['fromShopID'] ?? '-'}',
      'supplier': transfer['supplier'] ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'staffJual': '-',
    });

    _snack('Stok berjaya diterima');
  }

  Widget _buildFooter() {
    final total = _filtered.length;
    final available = _filtered.where((d) => (d['status'] ?? '').toString().toUpperCase() == 'AVAILABLE').length;
    final reserved = _filtered.where((d) => (d['status'] ?? '').toString().toUpperCase() == 'RESERVED').length;
    double totalJual = 0;
    for (final d in _filtered) {
      totalJual += (d['jual'] as num?)?.toDouble() ?? 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.borderMed)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          _footerBadge('$total UNIT', AppColors.primary),
          const SizedBox(width: 6),
          _footerBadge('$available ADA', AppColors.green),
          if (reserved > 0) ...[
            const SizedBox(width: 6),
            _footerBadge('$reserved RESERVED', AppColors.yellow),
          ],
        ]),
        Text('Jumlah: RM${totalJual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _footerBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }
}

// ═══════════════════════════════════════
// BARCODE SCANNER PAGE
// ═══════════════════════════════════════

class _BarcodeScannerPage extends StatefulWidget {
  final void Function(String code) onScanned;
  const _BarcodeScannerPage({required this.onScanned});

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _scannerCtrl = MobileScannerController();
  final _lang = AppLanguage();
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
        title: Text(_lang.get('scan_qr_barcode'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _scannerCtrl.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch), onPressed: () => _scannerCtrl.switchCamera()),
        ],
      ),
      body: Stack(children: [
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
        Center(child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(border: Border.all(color: AppColors.primary, width: 2), borderRadius: BorderRadius.circular(16)),
        )),
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: Text(_lang.get('ps_halakan_kamera'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          )),
        ),
      ]),
    );
  }
}
