import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/supabase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';

class SvPhoneStockTab extends StatefulWidget {
  final String ownerID;
  final String shopID;
  const SvPhoneStockTab({super.key, required this.ownerID, required this.shopID});
  @override
  State<SvPhoneStockTab> createState() => _SvPhoneStockTabState();
}

class _SvPhoneStockTabState extends State<SvPhoneStockTab> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  final _storage = SupabaseStorageHelper();
  final _searchCtrl = TextEditingController();
  final _printer = PrinterService();
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _filtered = [];
  StreamSubscription? _sub;
  String _selectedModel = 'SEMUA';

  // Form controllers
  final _kodCtrl = TextEditingController();
  final _namaCtrl = TextEditingController();
  final _kosCtrl = TextEditingController();
  final _jualCtrl = TextEditingController();
  final _tarikhMasukCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _init(); }

  int _tsFromIso(dynamic v) {
    if (v is int) return v;
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  Map<String, dynamic> _phoneStockToUi(Map<String, dynamic> r) {
    final notes = (r['notes'] is Map) ? Map<String, dynamic>.from(r['notes']) : <String, dynamic>{};
    return {
      'id': r['id'],
      'kod': notes['kod'] ?? '',
      'nama': r['device_name'] ?? notes['nama'] ?? '',
      'imei': notes['imei'] ?? '',
      'warna': notes['warna'] ?? '',
      'storage': notes['storage'] ?? '',
      'kos': r['cost'] ?? 0,
      'jual': r['price'] ?? 0,
      'jualDealer': notes['jualDealer'] ?? 0,
      'nota': notes['nota'] ?? '',
      'imageUrl': notes['imageUrl'] ?? '',
      'tarikh_masuk': notes['tarikh_masuk'] ?? '',
      'status': r['status'] ?? 'AVAILABLE',
      'shopID': widget.shopID,
      'timestamp': _tsFromIso(r['created_at']),
    };
  }

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    _kodCtrl.dispose();
    _namaCtrl.dispose();
    _kosCtrl.dispose();
    _jualCtrl.dispose();
    _tarikhMasukCtrl.dispose();
    super.dispose();
  }

  void _listen() {
    if (_branchId == null) return;
    _sub = _sb
        .from('phone_stock')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows
          .where((r) => r['deleted_at'] == null && (r['status'] ?? '').toString().toUpperCase() != 'SOLD')
          .map<Map<String, dynamic>>(_phoneStockToUi)
          .toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() { _inventory = list; _filter(); });
    });
  }

  List<String> get _modelList {
    final models = _inventory.map((d) => (d['nama'] ?? '').toString().toUpperCase()).where((n) => n.isNotEmpty).toSet().toList();
    models.sort();
    return ['SEMUA', ...models];
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    var data = List<Map<String, dynamic>>.from(_inventory);
    if (_selectedModel != 'SEMUA') {
      data = data.where((d) => (d['nama'] ?? '').toString().toUpperCase() == _selectedModel).toList();
    }
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
    if (ts is String && ts.isNotEmpty) {
      final dt = DateTime.tryParse(ts);
      if (dt != null) return DateFormat('dd/MM/yy').format(dt);
    }
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
    return await _storage.uploadFile(
      bucket: 'phone_stock',
      path: '${widget.ownerID}/${kod}_$ts.jpg',
      file: file,
    );
  }

  // ═══════════════════════════════════════
  // ADD PHONE STOCK MODAL
  // ═══════════════════════════════════════

  void _showAddModal() {
    _kodCtrl.text = _generateKod();
    _namaCtrl.text = '';
    _kosCtrl.text = '';
    _jualCtrl.text = '';
    _tarikhMasukCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final imeiCtrl = TextEditingController();
    final warnaCtrl = TextEditingController();
    final storageCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    final jualDealerCtrl = TextEditingController();
    File? pickedImage;
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        final kos = double.tryParse(_kosCtrl.text) ?? 0;
        final jual = double.tryParse(_jualCtrl.text) ?? 0;
        final profit = jual - kos;

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
                  const Row(children: [
                    FaIcon(FontAwesomeIcons.mobileScreenButton, size: 14, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('TAMBAH STOK TELEFON', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
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
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            FaIcon(FontAwesomeIcons.camera, size: 28, color: AppColors.textDim),
                            SizedBox(height: 8),
                            Text('Tekan untuk tambah gambar', style: TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Kod with auto-generate
                Row(children: [
                  Expanded(child: _formField('Kod Item', _kodCtrl, 'Cth: PH-ABC123')),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _actionBtn(FontAwesomeIcons.rotate, 'AUTO', AppColors.cyan, () {
                      setModalState(() => _kodCtrl.text = _generateKod());
                    }),
                  ),
                ]),

                _formField('Tarikh Masuk', _tarikhMasukCtrl, 'yyyy-mm-dd'),
                _formField('Nama Telefon', _namaCtrl, 'Cth: iPhone 13 Pro Max'),
                _formField('IMEI', imeiCtrl, 'No IMEI telefon', keyboard: TextInputType.number),

                Row(children: [
                  Expanded(child: _formField('Warna', warnaCtrl, 'Cth: Black')),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Storage', storageCtrl, 'Cth: 128GB')),
                ]),

                // Kos & Jual side by side
                Row(children: [
                  Expanded(child: _formField('Kos (RM)', _kosCtrl, '0.00', keyboard: TextInputType.number, onChanged: (_) => setModalState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Harga Jual (RM)', _jualCtrl, '0.00', keyboard: TextInputType.number, onChanged: (_) => setModalState(() {}))),
                ]),
                _formField('Harga Dealer (RM)', jualDealerCtrl, '0.00', keyboard: TextInputType.number, onChanged: (_) => setModalState(() {})),

                // Profit display
                if (_kosCtrl.text.isNotEmpty || _jualCtrl.text.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: profit >= 0 ? AppColors.green.withValues(alpha: 0.1) : AppColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: profit >= 0 ? AppColors.green.withValues(alpha: 0.3) : AppColors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('PROFIT', style: TextStyle(color: profit >= 0 ? AppColors.green : AppColors.red, fontSize: 10, fontWeight: FontWeight.w900)),
                      Text('RM${profit.toStringAsFixed(2)}', style: TextStyle(color: profit >= 0 ? AppColors.green : AppColors.red, fontSize: 12, fontWeight: FontWeight.w900)),
                    ]),
                  ),

                _formField('Nota', notaCtrl, 'Nota tambahan (pilihan)'),

                const SizedBox(height: 10),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: uploading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _buildGlassButton(
                          icon: FontAwesomeIcons.floppyDisk,
                          label: 'SIMPAN STOK TELEFON',
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

                            if (_tenantId == null || _branchId == null) return;
                            await _sb.from('phone_stock').insert({
                              'tenant_id': _tenantId,
                              'branch_id': _branchId,
                              'device_name': _namaCtrl.text.trim().toUpperCase(),
                              'cost': double.tryParse(_kosCtrl.text) ?? 0,
                              'price': double.tryParse(_jualCtrl.text) ?? 0,
                              'status': 'AVAILABLE',
                              'notes': {
                                'kod': _kodCtrl.text.trim().toUpperCase(),
                                'nama': _namaCtrl.text.trim().toUpperCase(),
                                'imei': imeiCtrl.text.trim(),
                                'warna': warnaCtrl.text.trim().toUpperCase(),
                                'storage': storageCtrl.text.trim().toUpperCase(),
                                'jualDealer': double.tryParse(jualDealerCtrl.text) ?? 0,
                                'nota': notaCtrl.text.trim(),
                                'tarikh_masuk': _tarikhMasukCtrl.text.trim(),
                                'imageUrl': imageUrl ?? '',
                              },
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('Stok telefon berjaya ditambah');
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
    final kosCtrl = TextEditingController(text: (item['kos'] ?? 0).toString());
    final jualCtrl = TextEditingController(text: (item['jual'] ?? 0).toString());
    final jualDealerCtrl = TextEditingController(text: (item['jualDealer'] ?? 0).toString());
    final notaCtrl = TextEditingController(text: item['nota'] ?? '');
    String status = (item['status'] ?? 'AVAILABLE').toString().toUpperCase();
    String existingImageUrl = (item['imageUrl'] ?? '').toString();
    File? pickedImage;
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        final kos = double.tryParse(kosCtrl.text) ?? 0;
        final jual = double.tryParse(jualCtrl.text) ?? 0;
        final profit = jual - kos;

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
                  const Row(children: [
                    FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: AppColors.yellow),
                    SizedBox(width: 8),
                    Text('EDIT STOK TELEFON', style: TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
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
                            : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                FaIcon(FontAwesomeIcons.camera, size: 28, color: AppColors.textDim),
                                SizedBox(height: 8),
                                Text('Tekan untuk tambah gambar', style: TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
                              ]),
                  ),
                ),
                const SizedBox(height: 12),

                _formField('Kod Item', kodCtrl, '', readOnly: true),
                _formField('Nama Telefon', namaCtrl, 'Nama telefon'),
                _formField('IMEI', imeiCtrl, 'No IMEI', keyboard: TextInputType.number),
                Row(children: [
                  Expanded(child: _formField('Warna', warnaCtrl, 'Warna')),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Storage', storageCtrl, 'Storage')),
                ]),

                // Kos & Jual side by side
                Row(children: [
                  Expanded(child: _formField('Kos (RM)', kosCtrl, '0.00', keyboard: TextInputType.number, onChanged: (_) => setModalState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Harga Jual (RM)', jualCtrl, '0.00', keyboard: TextInputType.number, onChanged: (_) => setModalState(() {}))),
                ]),
                _formField('Harga Dealer (RM)', jualDealerCtrl, '0.00', keyboard: TextInputType.number, onChanged: (_) => setModalState(() {})),

                // Profit display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: profit >= 0 ? AppColors.green.withValues(alpha: 0.1) : AppColors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: profit >= 0 ? AppColors.green.withValues(alpha: 0.3) : AppColors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('PROFIT', style: TextStyle(color: profit >= 0 ? AppColors.green : AppColors.red, fontSize: 10, fontWeight: FontWeight.w900)),
                    Text('RM${profit.toStringAsFixed(2)}', style: TextStyle(color: profit >= 0 ? AppColors.green : AppColors.red, fontSize: 12, fontWeight: FontWeight.w900)),
                  ]),
                ),

                _formField('Nota', notaCtrl, 'Nota tambahan'),

                // Status toggle
                const SizedBox(height: 6),
                const Text('Status', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(children: [
                  _statusChip('AVAILABLE', status, AppColors.green, () => setModalState(() => status = 'AVAILABLE')),
                  const SizedBox(width: 6),
                  _statusChip('SOLD', status, AppColors.red, () => setModalState(() => status = 'SOLD')),
                  const SizedBox(width: 6),
                  _statusChip('RESERVED', status, AppColors.yellow, () => setModalState(() => status = 'RESERVED')),
                ]),
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

                              final newNotes = {
                                'kod': kodCtrl.text.trim().toUpperCase(),
                                'nama': namaCtrl.text.trim().toUpperCase(),
                                'imei': imeiCtrl.text.trim(),
                                'warna': warnaCtrl.text.trim().toUpperCase(),
                                'storage': storageCtrl.text.trim().toUpperCase(),
                                'jualDealer': double.tryParse(jualDealerCtrl.text) ?? 0,
                                'nota': notaCtrl.text.trim(),
                                'imageUrl': imageUrl ?? (item['imageUrl'] ?? ''),
                              };
                              final updateData = <String, dynamic>{
                                'device_name': namaCtrl.text.trim().toUpperCase(),
                                'cost': double.tryParse(kosCtrl.text) ?? 0,
                                'price': double.tryParse(jualCtrl.text) ?? 0,
                                'status': status,
                                'notes': newNotes,
                              };

                              await _sb.from('phone_stock').update(updateData).eq('id', item['id']);

                              // Bila status SOLD, SELALU masuk history
                              if (status == 'SOLD') {
                                final existing = await _sb.from('phone_sales')
                                    .select()
                                    .eq('phone_stock_id', item['id'])
                                    .limit(1);
                                if (existing.isEmpty) {
                                  await _sb.from('phone_sales').insert({
                                    'tenant_id': _tenantId,
                                    'branch_id': _branchId,
                                    'phone_stock_id': item['id'],
                                    'device_name': namaCtrl.text.trim().toUpperCase(),
                                    'sold_price': double.tryParse(jualCtrl.text) ?? 0,
                                    'sold_at': DateTime.now().toIso8601String(),
                                    'notes': {
                                      ...newNotes,
                                      'kos': double.tryParse(kosCtrl.text) ?? 0,
                                      'jual': double.tryParse(jualCtrl.text) ?? 0,
                                      'tarikh_jual': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                    },
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
        title: const Text('Padam Stok?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text('${item['nama'] ?? item['kod']} akan dimasukkan ke tong sampah. Auto padam kekal selepas 30 hari.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BATAL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Soft-delete: set deleted_at (tong sampah = deleted_at != null)
              await _sb.from('phone_stock').update({
                'deleted_at': DateTime.now().toIso8601String(),
                'deleted_by': widget.shopID,
              }).eq('id', item['id']);
              _snack('Stok dimasukkan ke tong sampah');
            },
            child: const Text('PADAM', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // GENERATE BARCODE (PRINT LABEL)
  // ═══════════════════════════════════════

  Future<void> _printLabel(Map<String, dynamic> item) async {
    final kod = item['kod'] ?? '-';
    final nama = item['nama'] ?? '-';
    final jual = ((item['jual'] ?? 0) as num).toStringAsFixed(2);
    final imei = (item['imei'] ?? '').toString();
    final warna = (item['warna'] ?? '').toString();
    final storage = (item['storage'] ?? '').toString();

    const escInit = '\x1B\x40';
    const escCenter = '\x1B\x61\x01';
    const escBoldOn = '\x1B\x45\x01';
    const escBoldOff = '\x1B\x45\x00';
    const escDblSize = '\x1B\x21\x30';
    const escNormal = '\x1B\x21\x00';

    String tengah(String t, [int w = 32]) {
      int pad = ((w - t.length) / 2).floor().clamp(0, w);
      return '${' ' * pad}$t\n';
    }

    var r = escInit;
    r += escCenter;
    r += '$escBoldOn${escDblSize}STOK TELEFON\n$escNormal$escBoldOff';
    r += '${'=' * 32}\n';
    r += escBoldOn + tengah(kod) + escBoldOff;
    r += tengah(nama.toString().length > 30 ? nama.toString().substring(0, 30) : nama.toString());
    if (imei.isNotEmpty) r += tengah('IMEI: $imei');
    if (warna.isNotEmpty || storage.isNotEmpty) r += tengah('$warna ${storage.isNotEmpty ? "| $storage" : ""}'.trim());
    r += '${'─' * 32}\n';
    r += '${escBoldOn}RM $jual\n$escBoldOff';
    r += '${'=' * 32}\n';
    r += tengah('~ RMS Pro ~');
    r += '\x0A\x0A\x0A\x1D\x56\x00';

    _snack('Menyambung printer...');
    final bytes = utf8.encode(r);
    final ok = await _printer.printRaw(bytes);
    _snack(ok ? 'Label berjaya dicetak' : 'Gagal cetak. Sila sambung printer Bluetooth', err: !ok);
  }

  // ═══════════════════════════════════════
  // HISTORY JUALAN
  // ═══════════════════════════════════════

  void _showSalesHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  FaIcon(FontAwesomeIcons.clockRotateLeft, size: 14, color: AppColors.red),
                  SizedBox(width: 8),
                  Text('HISTORY & DELETE', style: TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
            ),
            const TabBar(
              labelColor: AppColors.red, unselectedLabelColor: AppColors.textDim, indicatorColor: AppColors.red,
              labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              tabs: [Tab(text: 'JUALAN'), Tab(text: 'DELETE')],
            ),
            Expanded(child: TabBarView(children: [_buildSalesTab(), _buildTrashTab()])),
          ]),
        ),
      ),
    );
  }

  Widget _buildSalesTab() {
    if (_branchId == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sb.from('phone_sales').stream(primaryKey: ['id']).eq('branch_id', _branchId!),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final docs = snap.data!.where((d) => d['deleted_at'] == null).toList()
          ..sort((a, b) => _tsFromIso(b['sold_at'] ?? b['created_at']).compareTo(_tsFromIso(a['sold_at'] ?? a['created_at'])));
        if (docs.isEmpty) return const Center(child: Text('Tiada rekod jualan', style: TextStyle(color: AppColors.textMuted)));
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.75,
          ),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final raw = docs[i];
            final notes = (raw['notes'] is Map) ? Map<String, dynamic>.from(raw['notes']) : <String, dynamic>{};
            final d = {...notes, ...raw};
            final saleDocId = raw['id'].toString();
            final stockDocId = (raw['phone_stock_id'] ?? '').toString();
            final nama = (raw['device_name'] ?? notes['nama'] ?? '-').toString();
            final kos = ((notes['kos'] ?? 0) as num).toDouble();
            final jual = ((raw['sold_price'] ?? notes['jual'] ?? 0) as num).toDouble();
            final profit = jual - kos;
            final tarikh = (notes['tarikh_jual'] ?? '').toString();
            final imageUrl = (notes['imageUrl'] ?? '').toString();
            // ignore d unused
            d.length;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderMed),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                    child: Stack(children: [
                      imageUrl.isNotEmpty
                          ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                              errorBuilder: (_, __, ___) => Container(color: AppColors.bgDeep, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: AppColors.textDim))))
                          : Container(color: AppColors.bgDeep, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: AppColors.textDim))),
                      Positioned(top: 6, right: 6, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(4)),
                        child: const Text('SOLD', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
                      )),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('RM${jual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900)),
                      Text(tarikh, style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                    ]),
                    Text('Profit: RM${profit.toStringAsFixed(2)}', style: TextStyle(color: profit >= 0 ? AppColors.green : AppColors.red, fontSize: 8, fontWeight: FontWeight.w700)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                  child: Row(children: [
                    if (stockDocId.isNotEmpty)
                      Expanded(child: GestureDetector(
                        onTap: () => _reverseStock(saleDocId, stockDocId, nama, context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.orange.withValues(alpha: 0.3))),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [FaIcon(FontAwesomeIcons.rotateLeft, size: 8, color: AppColors.orange), SizedBox(width: 4), Text('REVERSE', style: TextStyle(color: AppColors.orange, fontSize: 7, fontWeight: FontWeight.w900))]),
                        ),
                      )),
                    if (stockDocId.isNotEmpty) const SizedBox(width: 4),
                    Expanded(child: GestureDetector(
                      onTap: () => _deleteSaleRecord(saleDocId, nama),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [FaIcon(FontAwesomeIcons.trash, size: 8, color: AppColors.red), SizedBox(width: 4), Text('DELETE', style: TextStyle(color: AppColors.red, fontSize: 7, fontWeight: FontWeight.w900))]),
                      ),
                    )),
                  ]),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _buildTrashTab() {
    if (_branchId == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sb.from('phone_sales').stream(primaryKey: ['id']).eq('branch_id', _branchId!),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final docs = snap.data!.where((d) => d['deleted_at'] != null).toList();

        // Auto delete kekal selepas 30 hari
        for (final doc in docs) {
          final deletedAt = _tsFromIso(doc['deleted_at']);
          if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(deletedAt)).inDays >= 30) {
            _sb.from('phone_sales').delete().eq('id', doc['id']);
          }
        }
        final validDocs = docs.where((d) {
          final deletedAt = _tsFromIso(d['deleted_at']);
          return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(deletedAt)).inDays < 30;
        }).toList()
          ..sort((a, b) => _tsFromIso(b['deleted_at']).compareTo(_tsFromIso(a['deleted_at'])));

        if (validDocs.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(FontAwesomeIcons.trash, size: 32, color: AppColors.textDim), SizedBox(height: 8),
          Text('Tiada item deleted', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          SizedBox(height: 4), Text('Item auto padam kekal selepas 30 hari', style: TextStyle(color: AppColors.textDim, fontSize: 9)),
        ]));
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.75,
          ),
          itemCount: validDocs.length,
          itemBuilder: (_, i) {
            final raw = validDocs[i];
            final notes = (raw['notes'] is Map) ? Map<String, dynamic>.from(raw['notes']) : <String, dynamic>{};
            final docId = raw['id'].toString();
            final nama = (raw['device_name'] ?? notes['nama'] ?? '-').toString();
            final jual = ((raw['sold_price'] ?? notes['jual'] ?? 0) as num).toDouble();
            final tarikh = (notes['tarikh_jual'] ?? '').toString();
            final imageUrl = (notes['imageUrl'] ?? '').toString();
            final deletedAt = _tsFromIso(raw['deleted_at']);
            final daysLeft = 30 - DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(deletedAt)).inDays;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderMed),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                    child: Stack(children: [
                      imageUrl.isNotEmpty
                          ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                              errorBuilder: (_, __, ___) => Container(color: AppColors.bgDeep, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: AppColors.textDim))))
                          : Container(color: AppColors.bgDeep, child: const Center(child: FaIcon(FontAwesomeIcons.mobileScreenButton, size: 28, color: AppColors.textDim))),
                      Positioned(top: 6, right: 6, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(4)),
                        child: Text('${daysLeft}d', style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
                      )),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('RM${jual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900)),
                      Text(tarikh, style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                    ]),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                  child: GestureDetector(
                    onTap: () async {
                      try {
                        await _sb.from('phone_sales').update({'deleted_at': null}).eq('id', docId);
                        _snack('Rekod "$nama" dipulihkan ke history');
                      } catch (e) {
                        _snack('Gagal recover: $e', err: true);
                      }
                    },
                    child: Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.green.withValues(alpha: 0.3))),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [FaIcon(FontAwesomeIcons.rotateLeft, size: 8, color: AppColors.green), SizedBox(width: 4), Text('RECOVER', style: TextStyle(color: AppColors.green, fontSize: 7, fontWeight: FontWeight.w900))]),
                    ),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }


  // ═══════════════════════════════════════
  // REVERSE STOCK
  // ═══════════════════════════════════════

  void _reverseStock(String saleDocId, String stockDocId, String nama, BuildContext parentCtx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse Stock?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text('$nama akan dikembalikan ke status AVAILABLE dan dipadam dari history jualan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BATAL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _sb.from('phone_stock').update({'status': 'AVAILABLE'}).eq('id', stockDocId);
                await _sb.from('phone_sales').delete().eq('id', saleDocId);
                _snack('Stok "$nama" berjaya di-reverse ke AVAILABLE');
              } catch (e) {
                _snack('Gagal reverse: $e', err: true);
              }
            },
            child: const Text('REVERSE', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _deleteSaleRecord(String saleDocId, String nama) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Record?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text('Rekod jualan "$nama" akan dipindah ke tab DELETE.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BATAL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _sb.from('phone_sales').update({
                  'deleted_at': DateTime.now().toIso8601String(),
                }).eq('id', saleDocId);
                _snack('Rekod "$nama" dipindah ke DELETE');
              } catch (e) {
                _snack('Gagal delete: $e', err: true);
              }
            },
            child: const Text('DELETE', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // BULK UPLOAD CSV
  // ═══════════════════════════════════════

  Future<void> _downloadSampleCsv() async {
    const headers = ['nama', 'imei', 'warna', 'storage', 'kos', 'harga_jual', 'nota'];
    const sample = [
      ['IPHONE 13 PRO MAX', '123456789012345', 'BLACK', '128GB', '2000', '2500', 'Unit cantik'],
      ['SAMSUNG S24 ULTRA', '987654321098765', 'GREEN', '256GB', '3200', '3800', ''],
      ['IPHONE 15', '', 'BLUE', '64GB', '2800', '3200', 'Ada calar sikit'],
    ];

    final csvData = const ListToCsvConverter().convert([headers, ...sample]);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/sample_phone_stock.csv');
    await file.writeAsString(csvData);

    _snack('Sample CSV disimpan di ${file.path}');

    await Clipboard.setData(ClipboardData(text: csvData));
    _snack('Sample CSV disalin ke clipboard! Paste ke spreadsheet.');
  }

  Future<void> _bulkUploadCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    final csvString = await file.readAsString();
    final rows = const CsvToListConverter().convert(csvString);

    if (rows.length < 2) {
      _snack('CSV kosong atau tiada data', err: true);
      return;
    }

    final headers = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
    final namaIdx = headers.indexOf('nama');
    final imeiIdx = headers.indexOf('imei');
    final warnaIdx = headers.indexOf('warna');
    final storageIdx = headers.indexOf('storage');
    final kosIdx = headers.indexOf('kos');
    final jualIdx = headers.indexOf('harga_jual');
    final notaIdx = headers.indexOf('nota');

    if (namaIdx == -1) {
      _snack('Header "nama" tidak dijumpai dalam CSV', err: true);
      return;
    }

    if (_tenantId == null || _branchId == null) {
      _snack('Tenant/branch belum resolved', err: true);
      return;
    }
    final inserts = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final tarikhMasuk = DateFormat('yyyy-MM-dd').format(now);

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      final nama = (namaIdx < row.length ? row[namaIdx] : '').toString().trim().toUpperCase();
      if (nama.isEmpty) continue;

      inserts.add({
        'tenant_id': _tenantId,
        'branch_id': _branchId,
        'device_name': nama,
        'cost': kosIdx >= 0 && kosIdx < row.length ? (double.tryParse(row[kosIdx].toString()) ?? 0) : 0,
        'price': jualIdx >= 0 && jualIdx < row.length ? (double.tryParse(row[jualIdx].toString()) ?? 0) : 0,
        'status': 'AVAILABLE',
        'notes': {
          'kod': _generateKod(),
          'nama': nama,
          'imei': imeiIdx >= 0 && imeiIdx < row.length ? row[imeiIdx].toString().trim() : '',
          'warna': warnaIdx >= 0 && warnaIdx < row.length ? row[warnaIdx].toString().trim().toUpperCase() : '',
          'storage': storageIdx >= 0 && storageIdx < row.length ? row[storageIdx].toString().trim().toUpperCase() : '',
          'nota': notaIdx >= 0 && notaIdx < row.length ? row[notaIdx].toString().trim() : '',
          'imageUrl': '',
          'tarikh_masuk': tarikhMasuk,
        },
      });
    }

    if (inserts.isEmpty) {
      _snack('Tiada data sah dalam CSV', err: true);
      return;
    }

    await _sb.from('phone_stock').insert(inserts);
    _snack('${inserts.length} stok telefon berjaya diimport!');
  }

  // ═══════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════

  Widget _formField(String label, TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text, bool readOnly = false, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          readOnly: readOnly,
          onChanged: onChanged,
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
          // Bulk upload & Download CSV row
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _bulkUploadCsv,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    FaIcon(FontAwesomeIcons.fileArrowUp, size: 10, color: AppColors.yellow),
                    SizedBox(width: 6),
                    Text('BULK UPLOAD CSV', style: TextStyle(color: AppColors.yellow, fontSize: 9, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _downloadSampleCsv,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    FaIcon(FontAwesomeIcons.fileArrowDown, size: 10, color: AppColors.cyan),
                    SizedBox(width: 6),
                    Text('SAMPLE CSV', style: TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.borderMed),
          const SizedBox(height: 8),

          // Title + Tambah button
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.mobileScreenButton, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('STOK TELEFON (${_filtered.length})', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ]),
            Row(children: [
              // History icon
              GestureDetector(
                onTap: _showSalesHistory,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                  ),
                  child: const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 14, color: AppColors.red),
                ),
              ),
              const SizedBox(width: 8),
              // Tambah button
              GestureDetector(
                onTap: _showAddModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.blue]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white),
                    SizedBox(width: 6),
                    Text('TAMBAH', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 10),

          // Search
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(_filter),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Cari nama, kod atau IMEI...',
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
                      padding: EdgeInsets.only(right: 10),
                      child: FaIcon(FontAwesomeIcons.barcode, size: 14, color: AppColors.primary),
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
          // Model filter dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const FaIcon(FontAwesomeIcons.filter, size: 10, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _modelList.contains(_selectedModel) ? _selectedModel : 'SEMUA',
                    isDense: true,
                    isExpanded: true,
                    icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 8, color: AppColors.primary),
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900),
                    items: _modelList.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)))).toList(),
                    onChanged: (v) => setState(() { _selectedModel = v!; _filter(); }),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),

      // Grid List
      Expanded(
        child: _inventory.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(FontAwesomeIcons.mobileScreenButton, size: 40, color: AppColors.textDim),
                SizedBox(height: 12),
                Text('Tiada stok telefon', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              ]))
            : _filtered.isEmpty
                ? const Center(child: Text('Tiada padanan carian', style: TextStyle(color: AppColors.textMuted)))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _phoneCard(_filtered[i]),
                  ),
      ),

      // Footer
      _buildFooter(),
    ]);
  }

  Widget _phoneCard(Map<String, dynamic> d) {
    final status = (d['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final imageUrl = (d['imageUrl'] ?? '').toString();
    final statusColor = status == 'SOLD' ? AppColors.red : status == 'RESERVED' ? AppColors.yellow : AppColors.green;

    return Container(
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
              Positioned(top: 6, right: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
                child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
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
    );
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

  void _showDetailModal(Map<String, dynamic> d) {
    final kod = (d['kod'] ?? '-').toString();
    final nama = (d['nama'] ?? '-').toString();
    final imei = (d['imei'] ?? '').toString();
    final warna = (d['warna'] ?? '').toString();
    final storage = (d['storage'] ?? '').toString();
    final kos = (d['kos'] as num?)?.toDouble() ?? 0;
    final jual = (d['jual'] as num?)?.toDouble() ?? 0;
    final profit = jual - kos;
    final status = (d['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final nota = (d['nota'] ?? '').toString();
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
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              child: Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: 250,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 100, child: Center(child: FaIcon(FontAwesomeIcons.image, size: 32, color: AppColors.textDim)))),
            ),
          Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
            ]),
            const SizedBox(height: 8),
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
            _detailRow('Kod', kod),
            if (imei.isNotEmpty) _detailRow('IMEI', imei),
            if (warna.isNotEmpty) _detailRow('Warna', warna),
            if (storage.isNotEmpty) _detailRow('Storage', storage),
            _detailRow('Kos', 'RM${kos.toStringAsFixed(2)}'),
            _detailRow('Profit', 'RM${profit.toStringAsFixed(2)}'),
            _detailRow('Tarikh Masuk', d['tarikh_masuk'] ?? _fmt(d['timestamp'])),
            if (nota.isNotEmpty) _detailRow('Nota', nota),
            const SizedBox(height: 16),
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

  Widget _buildFooter() {
    final total = _filtered.length;
    final available = _filtered.where((d) => (d['status'] ?? '').toString().toUpperCase() == 'AVAILABLE').length;
    final reserved = _filtered.where((d) => (d['status'] ?? '').toString().toUpperCase() == 'RESERVED').length;
    double totalKos = 0;
    double totalJual = 0;
    double totalProfit = 0;
    for (final d in _filtered) {
      final kos = (d['kos'] as num?)?.toDouble() ?? 0;
      final jual = (d['jual'] as num?)?.toDouble() ?? 0;
      totalKos += kos;
      totalJual += jual;
      totalProfit += (jual - kos);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.borderMed)),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            _footerBadge('$total UNIT', AppColors.primary),
            const SizedBox(width: 6),
            _footerBadge('$available ADA', AppColors.green),
            if (reserved > 0) ...[
              const SizedBox(width: 6),
              _footerBadge('$reserved RESERVED', AppColors.yellow),
            ],
          ]),
          Text('Jual: RM${totalJual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Kos: RM${totalKos.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: totalProfit >= 0 ? AppColors.green.withValues(alpha: 0.15) : AppColors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Profit: RM${totalProfit.toStringAsFixed(2)}', style: TextStyle(color: totalProfit >= 0 ? AppColors.green : AppColors.red, fontSize: 10, fontWeight: FontWeight.w900)),
          ),
        ]),
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
  final ValueChanged<String> onScanned;
  const _BarcodeScannerPage({required this.onScanned});
  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode / QR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_scanned) return;
          final barcode = capture.barcodes.firstOrNull;
          if (barcode != null && barcode.rawValue != null) {
            _scanned = true;
            widget.onScanned(barcode.rawValue!);
          }
        },
      ),
    );
  }
}
