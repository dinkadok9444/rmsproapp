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
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_theme.dart';
import '../../services/printer_service.dart';

class SvStockTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvStockTab({required this.ownerID, required this.shopID});
  @override
  State<SvStockTab> createState() => SvStockTabState();
}

class SvStockTabState extends State<SvStockTab> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _searchCtrl = TextEditingController();
  final _printer = PrinterService();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _filtered = [];
  StreamSubscription? _sub;

  // Add stock form controllers
  final _kodCtrl = TextEditingController();
  final _namaCtrl = TextEditingController();
  final _kosCtrl = TextEditingController();
  final _jualCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _tarikhMasukCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
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
    _qtyCtrl.dispose();
    _tarikhMasukCtrl.dispose();
    super.dispose();
  }

  void _listen() {
    _sub = _db
        .collection('inventory_${widget.ownerID}')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (mounted) setState(() { _inventory = list; _filter(); });
    });
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    _filtered = q.isEmpty
        ? List.from(_inventory)
        : _inventory.where((d) {
            return (d['kod'] ?? '').toString().toLowerCase().contains(q) ||
                (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
                (d['no_siri_jual'] ?? '').toString().toLowerCase().contains(q);
          }).toList();
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ═══════════════════════════════════════
  // AUTO-GENERATE KOD
  // ═══════════════════════════════════════

  String _generateKod() {
    final rand = Random();
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'STK-$code';
  }

  // ═══════════════════════════════════════
  // BARCODE / QR SCANNER
  // ═══════════════════════════════════════

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

  void _openScanner() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _BarcodeScannerPage(
        onScanned: (String code) {
          Navigator.pop(context);
          _handleScannedCode(code);
        },
      ),
    ));
  }

  Future<void> _handleScannedCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;

    final existing = _inventory.where((d) =>
      (d['kod'] ?? '').toString().toUpperCase() == cleanCode
    ).toList();

    _showAddStockModal(
      prefillKod: cleanCode,
      prefillNama: existing.isNotEmpty ? (existing.first['nama'] ?? '').toString() : null,
      prefillKos: existing.isNotEmpty ? ((existing.first['kos'] ?? 0) as num).toDouble() : null,
      prefillJual: existing.isNotEmpty ? ((existing.first['jual'] ?? 0) as num).toDouble() : null,
    );
  }

  // ═══════════════════════════════════════
  // IMAGE UPLOAD (max 100KB)
  // ═══════════════════════════════════════

  Future<File?> _pickStockImage() async {
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

  Future<String?> _uploadStockImage(File file, String kod) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child('inventory/${widget.ownerID}/${kod}_$ts.jpg');
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await task.ref.getDownloadURL();
  }

  // ═══════════════════════════════════════
  // ADD STOCK MODAL
  // ═══════════════════════════════════════

  void _showAddStockModal({String? prefillKod, String? prefillNama, double? prefillKos, double? prefillJual}) {
    _kodCtrl.text = prefillKod ?? _generateKod();
    _namaCtrl.text = prefillNama ?? '';
    _kosCtrl.text = prefillKos != null ? prefillKos.toStringAsFixed(2) : '';
    _jualCtrl.text = prefillJual != null ? prefillJual.toStringAsFixed(2) : '';
    _qtyCtrl.text = '1';
    _tarikhMasukCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    File? pickedImage;
    bool uploading = false;
    String selectedCategory = 'SPAREPART';

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
                    const FaIcon(FontAwesomeIcons.boxOpen, size: 14, color: AppColors.yellow),
                    const SizedBox(width: 8),
                    const Text('TAMBAH STOK', style: TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900)),
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
                    final file = await _pickStockImage();
                    if (file != null) setModalState(() => pickedImage = file);
                  },
                  child: Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderMed),
                    ),
                    child: pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(pickedImage!, fit: BoxFit.cover, width: double.infinity, height: 120))
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            FaIcon(FontAwesomeIcons.camera, size: 24, color: AppColors.textDim),
                            SizedBox(height: 6),
                            Text('TAMBAH GAMBAR', style: TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Kod with copy, auto-generate & scan buttons
                Row(children: [
                  Expanded(child: _formField('Kod Item', _kodCtrl, 'Cth: LCD-IP13')),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _actionBtn(FontAwesomeIcons.copy, 'SALIN', AppColors.textMuted, () {
                      final kod = _kodCtrl.text.trim();
                      if (kod.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: kod));
                        _snack('Kod "$kod" disalin');
                      }
                    }),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _actionBtn(FontAwesomeIcons.rotate, 'AUTO', AppColors.cyan, () {
                      setModalState(() => _kodCtrl.text = _generateKod());
                    }),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _actionBtn(FontAwesomeIcons.barcode, 'SCAN', AppColors.blue, () {
                      Navigator.pop(ctx);
                      _openScanner();
                    }),
                  ),
                ]),

                // Tarikh masuk
                _formField('Tarikh Masuk', _tarikhMasukCtrl, 'yyyy-mm-dd'),

                // Nama item
                _formField('Nama Item', _namaCtrl, 'Cth: LCD iPhone 13'),

                // Category dropdown
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Kategori', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          dropdownColor: Colors.white,
                          items: const [
                            DropdownMenuItem(value: 'SPAREPART', child: Text('SPAREPART')),
                            DropdownMenuItem(value: 'FAST SERVICE', child: Text('FAST SERVICE')),
                          ],
                          onChanged: (v) => setModalState(() => selectedCategory = v!),
                        ),
                      ),
                    ),
                  ]),
                ),

                // Kos & Harga Jual
                Row(children: [
                  Expanded(child: _formField('Kos (RM)', _kosCtrl, '0.00', keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Harga Jual (RM)', _jualCtrl, '0.00', keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 10),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: uploading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
                      : _buildGlassButton(
                    icon: FontAwesomeIcons.floppyDisk,
                    label: 'SIMPAN STOK',
                    color: AppColors.yellow,
                    onTap: () async {
                      if (_kodCtrl.text.trim().isEmpty) {
                        _snack('Sila isi Kod Item', err: true);
                        return;
                      }
                      setModalState(() => uploading = true);

                      String? imageUrl;
                      if (pickedImage != null) {
                        imageUrl = await _uploadStockImage(pickedImage!, _kodCtrl.text.trim());
                      }

                      await _db.collection('inventory_${widget.ownerID}').add({
                        'kod': _kodCtrl.text.trim().toUpperCase(),
                        'nama': _namaCtrl.text.trim().toUpperCase(),
                        'category': selectedCategory,
                        'kos': double.tryParse(_kosCtrl.text) ?? 0,
                        'jual': double.tryParse(_jualCtrl.text) ?? 0,
                        'qty': 1,
                        'supplier': '',
                        'tarikh_masuk': _tarikhMasukCtrl.text.trim(),
                        'tkh_jual': '',
                        'no_siri_jual': '',
                        'imageUrl': imageUrl ?? '',
                        'status': 'AVAILABLE',
                        'timestamp': DateTime.now().millisecondsSinceEpoch,
                        'shopID': widget.shopID,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Stok berjaya ditambah');
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
  // EDIT / MORE MODAL
  // ═══════════════════════════════════════

  void _showEditModal(Map<String, dynamic> item) {
    final docId = item['id'];
    final namaCtrl = TextEditingController(text: item['nama'] ?? '');
    final kosCtrl = TextEditingController(text: (item['kos'] ?? 0).toString());
    final jualCtrl = TextEditingController(text: (item['jual'] ?? 0).toString());
    final reverseSiriCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        final qty = item['qty'] ?? 0;
        final isSold = (item['status'] ?? '').toString().toUpperCase() == 'TERJUAL';
        final kod = item['kod'] ?? '-';

        return Container(
          margin: const EdgeInsets.only(top: 40),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppColors.border, width: 2)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Row(children: [
                    const FaIcon(FontAwesomeIcons.penToSquare, size: 14, color: AppColors.yellow),
                    const SizedBox(width: 8),
                    Flexible(child: Text('EDIT: $kod', style: const TextStyle(color: AppColors.yellow, fontSize: 13, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
                ]),
                const SizedBox(height: 12),

                // Status badge + qty
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSold ? AppColors.red.withValues(alpha: 0.15) : AppColors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isSold ? AppColors.red.withValues(alpha: 0.3) : AppColors.green.withValues(alpha: 0.3)),
                    ),
                    child: Text(isSold ? 'TERJUAL' : 'AVAILABLE',
                      style: TextStyle(color: isSold ? AppColors.red : AppColors.green, fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 8),
                  Text('QTY: $qty', style: TextStyle(color: qty <= 2 ? AppColors.red : AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w900)),
                  if (item['no_siri_jual'] != null && item['no_siri_jual'].toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('Siri Jual: ${item['no_siri_jual']}', style: const TextStyle(color: AppColors.blue, fontSize: 9, fontWeight: FontWeight.w700)),
                  ],
                ]),
                const SizedBox(height: 12),

                // Edit fields
                _formField('Nama Item', namaCtrl, 'Nama'),
                Row(children: [
                  Expanded(child: _formField('Kos (RM)', kosCtrl, '0.00', keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: _formField('Harga Jual (RM)', jualCtrl, '0.00', keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 8),

                // Update & Print label
                Row(children: [
                  Expanded(
                    child: _buildGlassButton(
                      icon: FontAwesomeIcons.floppyDisk,
                      label: 'KEMASKINI',
                      color: AppColors.yellow,
                      onTap: () async {
                        await _db.collection('inventory_${widget.ownerID}').doc(docId).update({
                          'nama': namaCtrl.text.trim().toUpperCase(),
                          'kos': double.tryParse(kosCtrl.text) ?? 0,
                          'jual': double.tryParse(jualCtrl.text) ?? 0,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Stok berjaya dikemaskini');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildGlassButton(
                      icon: FontAwesomeIcons.print,
                      label: 'CETAK LABEL',
                      color: AppColors.blue,
                      onTap: () => _printLabel(item),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // Reverse stock by job siri
                Row(children: [
                  const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 12, color: AppColors.red),
                  const SizedBox(width: 6),
                  const Text('REVERSE STOK', style: TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _formField('No. Siri Job', reverseSiriCtrl, 'Cth: RMS-00001')),
                  const SizedBox(width: 8),
                  _actionBtn(FontAwesomeIcons.arrowsRotate, 'REVERSE', AppColors.red, () async {
                    final siri = reverseSiriCtrl.text.trim().toUpperCase();
                    if (siri.isEmpty) { _snack('Sila isi No. Siri', err: true); return; }
                    if ((item['no_siri_jual'] ?? '').toString().toUpperCase() == siri) {
                      final currentQty = (item['qty'] ?? 0) as int;
                      await _db.collection('inventory_${widget.ownerID}').doc(docId).update({
                        'qty': currentQty + 1,
                        'status': 'AVAILABLE',
                        'no_siri_jual': '',
                        'tkh_jual': '',
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Stok berjaya di-reverse dari job $siri');
                    } else {
                      _snack('No. Siri tidak sepadan dengan item ini', err: true);
                    }
                  }),
                ]),
                const SizedBox(height: 16),

                // Delete
                SizedBox(
                  width: double.infinity,
                  child: _buildGlassButton(
                    icon: FontAwesomeIcons.trashCan,
                    label: 'PADAM ITEM',
                    color: AppColors.red,
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
                          title: const Text('PADAM ITEM?', style: TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
                          content: Text('Adakah anda pasti mahu padam "$kod"?', style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted))),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dCtx, true),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                              child: const Text('PADAM', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _db.collection('inventory_${widget.ownerID}').doc(docId).delete();
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Item berjaya dipadam');
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
  // PRINT LABEL VIA BLUETOOTH
  // ═══════════════════════════════════════

  Future<void> _printLabel(Map<String, dynamic> item) async {
    final kod = item['kod'] ?? '-';
    final nama = item['nama'] ?? '-';
    final jual = ((item['jual'] ?? 0) as num).toStringAsFixed(2);

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
    r += '$escBoldOn${escDblSize}LABEL STOK\n$escNormal$escBoldOff';
    r += '${'=' * 32}\n';
    r += escBoldOn + tengah(kod) + escBoldOff;
    r += tengah(nama.toString().length > 30 ? nama.toString().substring(0, 30) : nama.toString());
    r += '${'─' * 32}\n';
    r += '${escBoldOn}RM $jual\n$escBoldOff';
    r += '${'=' * 32}\n';
    r += tengah('~ RMS Pro ~');
    r += '\x0A\x0A\x0A\x1D\x56\x00';

    final bytes = utf8.encode(r);
    final ok = await _printer.printRaw(bytes);
    if (ok) {
      _snack('Label berjaya dicetak');
    } else {
      _snack('Gagal cetak. Sila sambung printer Bluetooth', err: true);
    }
  }

  // ═══════════════════════════════════════
  // HISTORY USED
  // ═══════════════════════════════════════

  Future<List<Map<String, dynamic>>> _loadUsedHistory() async {
    final snap = await _db.collection('stock_usage_${widget.ownerID}')
        .where('status', isEqualTo: 'USED')
        .get();
    final list = snap.docs.map((d) => {'_id': d.id, ...d.data()}).toList();
    list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    return list.take(50).toList();
  }

  void _showUsedHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        List<Map<String, dynamic>>? usedList;
        bool fetched = false;

        return StatefulBuilder(builder: (ctx, setModalState) {
          if (!fetched) {
            fetched = true;
            _loadUsedHistory().then((data) => setModalState(() => usedList = data));
          }
          return Container(
            margin: const EdgeInsets.only(top: 60),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: AppColors.border, width: 2)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Row(children: [
                    FaIcon(FontAwesomeIcons.clockRotateLeft, size: 14, color: AppColors.orange),
                    SizedBox(width: 8),
                    Text('SEJARAH GUNA', style: TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w900)),
                  ]),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
                ]),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: usedList == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
                    : usedList!.isEmpty
                        ? const Center(child: Text('Tiada rekod penggunaan', style: TextStyle(color: AppColors.textDim, fontSize: 12)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: usedList!.length,
                            itemBuilder: (_, i) {
                              final d = usedList![i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.orange.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
                                ),
                                child: Row(children: [
                                  const FaIcon(FontAwesomeIcons.boxOpen, size: 14, color: AppColors.orange),
                                  const SizedBox(width: 10),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(d['kod'] ?? '', style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900)),
                                    Text(d['nama'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                                    Text('RM ${((d['jual'] ?? 0) as num).toStringAsFixed(2)} • ${d['tarikh'] ?? ''}',
                                        style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                                  ])),
                                  GestureDetector(
                                    onTap: () async {
                                      final stockDocId = d['stock_doc_id'] ?? '';
                                      final usageId = d['_id'] ?? '';
                                      await _db.collection('inventory_${widget.ownerID}').doc(stockDocId).update({
                                        'status': 'AVAILABLE',
                                        'tkh_guna': '',
                                      });
                                      await _db.collection('stock_usage_${widget.ownerID}').doc(usageId).update({
                                        'status': 'REVERSED',
                                        'reversed_at': DateTime.now().millisecondsSinceEpoch,
                                      });
                                      setModalState(() => usedList!.removeAt(i));
                                      _snack('Stok "${d['nama']}" di-reverse');
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.blue.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        FaIcon(FontAwesomeIcons.arrowsRotate, size: 9, color: AppColors.blue),
                                        SizedBox(width: 4),
                                        Text('REVERSE', style: TextStyle(color: AppColors.blue, fontSize: 8, fontWeight: FontWeight.w900)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              );
                            },
                          ),
              ),
            ]),
          );
        });
      },
    );
  }

  // ═══════════════════════════════════════
  // HISTORY RETURN
  // ═══════════════════════════════════════

  void _showReturnHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        List<Map<String, dynamic>>? returnList;
        bool fetched = false;

        return StatefulBuilder(builder: (ctx, setModalState) {
          if (!fetched) {
            fetched = true;
            _loadReturnHistory().then((data) => setModalState(() => returnList = data));
          }
          return Container(
            margin: const EdgeInsets.only(top: 60),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: AppColors.border, width: 2)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Row(children: [
                    FaIcon(FontAwesomeIcons.rotateLeft, size: 14, color: AppColors.red),
                    SizedBox(width: 8),
                    Text('SEJARAH RETURN', style: TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
                  ]),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
                ]),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: returnList == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
                    : returnList!.isEmpty
                        ? const Center(child: Text('Tiada rekod return', style: TextStyle(color: AppColors.textDim, fontSize: 12)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: returnList!.length,
                            itemBuilder: (_, i) {
                              final r = returnList![i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.red.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
                                ),
                                child: Row(children: [
                                  const FaIcon(FontAwesomeIcons.rotateLeft, size: 14, color: AppColors.red),
                                  const SizedBox(width: 10),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r['kod'] ?? '', style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900)),
                                    Text(r['nama'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                                    Text('QTY: ${r['qty']} • ${r['reason'] ?? '-'}',
                                        style: const TextStyle(color: AppColors.orange, fontSize: 9, fontWeight: FontWeight.w600)),
                                    Text(r['tarikh'] ?? '', style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                                  ])),
                                  GestureDetector(
                                    onTap: () async {
                                      final stockDocId = r['stock_doc_id'] ?? '';
                                      final returnDocId = r['_id'] ?? '';
                                      final rQty = (r['qty'] ?? 0) as int;

                                      final stockSnap = await _db.collection('inventory_${widget.ownerID}').doc(stockDocId).get();
                                      if (stockSnap.exists) {
                                        final currentQty = (stockSnap.data()?['qty'] ?? 0) as int;
                                        await _db.collection('inventory_${widget.ownerID}').doc(stockDocId).update({
                                          'qty': currentQty + rQty,
                                          'status': 'AVAILABLE',
                                        });
                                      }

                                      await _db.collection('inventory_${widget.ownerID}').doc(stockDocId).collection('returns').doc(returnDocId).delete();

                                      setModalState(() => returnList!.removeAt(i));
                                      _snack('Return "${r['nama']}" di-reverse, +$rQty unit');
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.blue.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        FaIcon(FontAwesomeIcons.arrowsRotate, size: 9, color: AppColors.blue),
                                        SizedBox(width: 4),
                                        Text('REVERSE', style: TextStyle(color: AppColors.blue, fontSize: 8, fontWeight: FontWeight.w900)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              );
                            },
                          ),
              ),
            ]),
          );
        });
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadReturnHistory() async {
    final List<Map<String, dynamic>> allReturns = [];
    for (final item in _inventory) {
      final docId = item['id'];
      final kod = item['kod'] ?? '';
      final nama = item['nama'] ?? '';
      final snap = await _db
          .collection('inventory_${widget.ownerID}')
          .doc(docId)
          .collection('returns')
          .orderBy('timestamp', descending: true)
          .get();
      for (final d in snap.docs) {
        allReturns.add({
          ...d.data(),
          '_id': d.id,
          'kod': kod,
          'nama': nama,
          'stock_doc_id': docId,
        });
      }
    }
    allReturns.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    return allReturns.take(50).toList();
  }

  // ═══════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════

  Widget _formField(String label, TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text, VoidCallback? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          onChanged: onChanged != null ? (_) => onChanged() : null,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
            filled: true,
            fillColor: AppColors.bgDeep,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.yellow)),
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
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 3))],
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
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.7)],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      _buildSearchBar(),
      Expanded(child: _buildInventoryList()),
      _buildFooter(),
    ]);
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.yellow, width: 2)),
      ),
      child: Row(children: [
        const FaIcon(FontAwesomeIcons.boxesStacked, size: 14, color: AppColors.yellow),
        const SizedBox(width: 8),
        const Text('STOK & CN', style: TextStyle(color: AppColors.yellow, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const Spacer(),
        GestureDetector(
          onTap: _showUsedHistory,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.clockRotateLeft, size: 10, color: AppColors.orange),
              SizedBox(width: 5),
              Text('H.USED', style: TextStyle(color: AppColors.orange, fontSize: 9, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _showReturnHistory,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.rotateLeft, size: 10, color: AppColors.red),
              SizedBox(width: 5),
              Text('H.RETURN', style: TextStyle(color: AppColors.red, fontSize: 9, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => _showAddStockModal(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: AppColors.yellow.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.black),
              SizedBox(width: 5),
              Text('TAMBAH', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.card,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(_filter),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Cari kod / nama item...',
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
                onTap: () => _openSearchScanner(),
                child: const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: FaIcon(FontAwesomeIcons.barcode, size: 14, color: AppColors.yellow),
                ),
              ),
            ],
          ),
          filled: true,
          fillColor: AppColors.bgDeep,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildInventoryList() {
    if (_inventory.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.yellow),
          SizedBox(height: 16),
          Text('Memuatkan stok...', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    if (_filtered.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(FontAwesomeIcons.boxOpen, size: 40, color: AppColors.textDim),
        SizedBox(height: 12),
        Text('Tiada item ditemui', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _stockCard(_filtered[i]),
    );
  }

  Widget _stockCard(Map<String, dynamic> d) {
    final qty = (d['qty'] ?? 0) as int;
    final status = (d['status'] ?? '').toString().toUpperCase();
    final isSold = status == 'TERJUAL';
    final isReturned = status == 'RETURNED';
    final isUsed = status == 'USED';
    final kod = d['kod'] ?? '-';
    final nama = d['nama'] ?? '-';
    final kos = ((d['kos'] ?? 0) as num).toDouble();
    final jual = ((d['jual'] ?? 0) as num).toDouble();
    final profit = jual - kos;
    final tarikhMasuk = d['tarikh_masuk'] ?? '';
    final tkhJual = d['tkh_jual'] ?? '';
    final siriJual = d['no_siri_jual'] ?? '';
    final supplier = d['supplier'] ?? '';
    final category = (d['category'] ?? '').toString();

    Color statusColor = AppColors.green;
    String statusText = 'AVAILABLE';
    if (isSold) { statusColor = AppColors.red; statusText = 'TERJUAL'; }
    else if (isReturned) { statusColor = AppColors.orange; statusText = 'RETURNED'; }
    else if (isUsed) { statusColor = AppColors.blue; statusText = 'USED'; }

    return GestureDetector(
      onTap: () => _showEditModal(d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: qty <= 2 ? AppColors.red.withValues(alpha: 0.2) : AppColors.borderMed),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          // QTY box
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: qty <= 2 ? AppColors.red.withValues(alpha: 0.12) : AppColors.yellow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: qty <= 2 ? AppColors.red.withValues(alpha: 0.3) : AppColors.yellow.withValues(alpha: 0.2)),
            ),
            child: Center(child: Text('$qty', style: TextStyle(
              color: qty <= 2 ? AppColors.red : AppColors.yellow, fontSize: 16, fontWeight: FontWeight.w900))),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(kod, style: const TextStyle(color: AppColors.yellow, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
              if (category.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(category, style: const TextStyle(color: AppColors.cyan, fontSize: 7, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 7, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(nama, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Row(children: [
              Text('Kos: RM ${kos.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              const SizedBox(width: 8),
              Text('Jual: RM ${jual.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.green, fontSize: 9, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: profit >= 0 ? AppColors.green.withValues(alpha: 0.12) : AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'P: RM ${profit.toStringAsFixed(2)}',
                  style: TextStyle(color: profit >= 0 ? AppColors.green : AppColors.red, fontSize: 8, fontWeight: FontWeight.w900),
                ),
              ),
              if (supplier.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(child: Text(supplier, style: const TextStyle(color: AppColors.yellow, fontSize: 8, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ]),
            if (tarikhMasuk.isNotEmpty || tkhJual.isNotEmpty || siriJual.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  if (tarikhMasuk.isNotEmpty) Text('Masuk: $tarikhMasuk', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                  if (tkhJual.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('Jual: $tkhJual', style: const TextStyle(color: AppColors.textDim, fontSize: 8)),
                  ],
                  if (siriJual.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('#$siriJual', style: const TextStyle(color: AppColors.blue, fontSize: 8, fontWeight: FontWeight.w700)),
                  ],
                ]),
              ),
          ])),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: AppColors.textDim),
          ),
        ]),
      ),
    );
  }

  Widget _buildFooter() {
    final totalQty = _filtered.fold(0, (s, d) => s + ((d['qty'] ?? 0) as int));
    final totalKos = _filtered.fold(0.0, (s, d) => s + ((d['kos'] ?? 0) as num).toDouble() * ((d['qty'] ?? 0) as num).toDouble());
    final totalJual = _filtered.fold(0.0, (s, d) => s + ((d['jual'] ?? 0) as num).toDouble() * ((d['qty'] ?? 0) as num).toDouble());
    final totalProfit = totalJual - totalKos;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.borderMed)),
      ),
      child: Row(children: [
        _footerChip('${_filtered.length} item', AppColors.textMuted),
        const SizedBox(width: 6),
        _footerChip('QTY: $totalQty', AppColors.blue),
        const SizedBox(width: 6),
        _footerChip('Kos: RM ${totalKos.toStringAsFixed(0)}', AppColors.textMuted),
        const SizedBox(width: 6),
        _footerChip('Jual: RM ${totalJual.toStringAsFixed(0)}', AppColors.green),
        const SizedBox(width: 6),
        Expanded(child: _footerChip('Profit: RM ${totalProfit.toStringAsFixed(0)}', totalProfit >= 0 ? AppColors.green : AppColors.red)),
      ]),
    );
  }

  Widget _footerChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
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
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SCAN BARCODE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        backgroundColor: AppColors.yellow,
        foregroundColor: Colors.black,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_scanned) return;
          final barcode = capture.barcodes.firstOrNull;
          if (barcode?.rawValue != null) {
            _scanned = true;
            widget.onScanned(barcode!.rawValue!);
          }
        },
      ),
    );
  }
}
