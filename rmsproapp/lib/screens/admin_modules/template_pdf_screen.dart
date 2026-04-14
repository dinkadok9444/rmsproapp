import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../utils/pdf_url_helper.dart';

class TemplatePdfScreen extends StatefulWidget {
  const TemplatePdfScreen({super.key});
  @override
  State<TemplatePdfScreen> createState() => _TemplatePdfScreenState();
}

class _TemplatePdfScreenState extends State<TemplatePdfScreen> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  bool _isLoading = true;

  static const _templates = [
    _TplInfo('Standard', Color(0xFFFF6600), Color(0xFFFFF7ED), FontAwesomeIcons.file),
    _TplInfo('Moden', Color(0xFF2563EB), Color(0xFFEFF6FF), FontAwesomeIcons.tableCellsLarge),
    _TplInfo('Klasik', Color(0xFF374151), Color(0xFFF3F4F6), FontAwesomeIcons.scroll),
    _TplInfo('Minimalis', Color(0xFF64748B), Color(0xFFF8FAFC), FontAwesomeIcons.minus),
    _TplInfo('Komersial', Color(0xFFDC2626), Color(0xFFFEF2F2), FontAwesomeIcons.tags),
    _TplInfo('Elegan', Color(0xFF92400E), Color(0xFFFFFBEB), FontAwesomeIcons.gem),
    _TplInfo('Tengah', Color(0xFF7C3AED), Color(0xFFF5F3FF), FontAwesomeIcons.alignCenter),
    _TplInfo('Kompak', Color(0xFF0D9488), Color(0xFFF0FDFA), FontAwesomeIcons.compress),
    _TplInfo('Korporat', Color(0xFF1E3A5F), Color(0xFFF0F4F8), FontAwesomeIcons.buildingColumns),
    _TplInfo('Kreatif', Color(0xFFEC4899), Color(0xFFFDF2F8), FontAwesomeIcons.paintbrush),
  ];

  final List<String?> _imageUrls = List.filled(10, null);
  final List<bool> _busy = List.filled(10, false);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _listenTemplates();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listenTemplates() {
    _sub?.cancel();
    _sub = _db.collection('config').doc('pdf_templates').snapshots().listen(
      (snap) {
        final data = snap.data() ?? {};
        for (int i = 0; i < 10; i++) {
          final v = data['tpl_${i + 1}'];
          _imageUrls[i] = (v is String && v.isNotEmpty) ? v : null;
        }
        if (kDebugMode) {
          debugPrint('[TemplatePDF] keys: ${data.keys.toList()}');
          debugPrint('[TemplatePDF] loaded: ${_imageUrls.where((u) => u != null).length}/10');
        }
        if (mounted) setState(() => _isLoading = false);
      },
      onError: (e) {
        _snack('Ralat load: $e', err: true);
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  Future<void> _manualRefresh() async {
    try {
      final snap = await _db.collection('config').doc('pdf_templates').get();
      final data = snap.data() ?? {};
      int count = 0;
      for (int i = 0; i < 10; i++) {
        final v = data['tpl_${i + 1}'];
        _imageUrls[i] = (v is String && v.isNotEmpty) ? v : null;
        if (_imageUrls[i] != null) count++;
      }
      if (mounted) setState(() {});
      _snack('Refresh: $count / 10 template dijumpai');
    } catch (e) {
      _snack('Ralat: $e', err: true);
    }
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: err ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════
  // BUKA PDF — generate sample PDF & buka dalam tab/viewer
  // ═══════════════════════════════════════
  Map<String, dynamic> _samplePayload(String tplId) => {
    'typePDF': 'INVOICE',
    'paperSize': 'A4',
    'templatePdf': tplId,
    'logoBase64': '',
    'namaKedai': 'KEDAI CONTOH SDN BHD',
    'alamatKedai': '12, Jalan Contoh 1, Taman Maju, 81100 Johor Bahru',
    'telKedai': '011-12345678',
    'noJob': 'SAMPLE-001',
    'namaCust': 'AHMAD BIN ALI (CONTOH)',
    'telCust': '012-3456789',
    'tarikhResit': DateTime.now().toIso8601String().split('T').first,
    'stafIncharge': 'Admin',
    'items': [
      {'nama': 'LCD IPHONE 13 PRO MAX (ORIGINAL)', 'harga': 450.00},
      {'nama': 'BATERI IPHONE 13 PRO MAX', 'harga': 120.00},
      {'nama': 'SERVIS CUCI & DIAGNOSIS', 'harga': 30.00},
    ],
    'model': 'IPHONE 13 PRO MAX',
    'kerosakan': 'LCD PECAH & BATERI LEMAH',
    'warranty': '30 HARI',
    'warranty_exp': '',
    'voucherAmt': 0,
    'diskaunAmt': 50.00,
    'tambahanAmt': 0,
    'depositAmt': 100.00,
    'totalDibayar': 450.00,
    'statusBayar': 'PAID',
    'nota': 'Barang yang tidak dituntut selepas 30 hari adalah tanggungjawab pelanggan.',
  };

  Future<void> _openPdfPreview(int index) async {
    final tplId = 'tpl_${index + 1}';
    setState(() => _busy[index] = true);

    try {
      final generateUrl = await PdfUrlHelper.getGeneratePdfUrl();
      final response = await http
          .post(
            Uri.parse(generateUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(_samplePayload(tplId)),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('[TemplatePDF] $tplId FAIL ${response.statusCode}: ${response.body}');
        final bodyPreview = response.body.length > 200
            ? '${response.body.substring(0, 200)}...'
            : response.body;
        _snack('Gagal $tplId (${response.statusCode}): $bodyPreview', err: true);
        return;
      }

      final result = jsonDecode(response.body);
      final pdfUrl = result['pdfUrl']?.toString() ?? '';
      if (pdfUrl.isEmpty) {
        debugPrint('[TemplatePDF] $tplId empty pdfUrl: ${response.body}');
        _snack('PDF URL kosong untuk $tplId: ${response.body}', err: true);
        return;
      }

      // Buka PDF dalam tab baru / viewer
      final uri = Uri.parse(pdfUrl);
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) {
          // Fallback: cuba in-app browser view
          final ok2 = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
          if (!ok2) {
            _snack('Tidak dapat buka PDF: $pdfUrl', err: true);
            return;
          }
        }
        _snack('PDF ${_templates[index].name} dibuka — screenshot & upload');
      } catch (e) {
        _snack('Gagal buka: $e', err: true);
      }
    } catch (e) {
      _snack('Gagal: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy[index] = false);
    }
  }

  // ═══════════════════════════════════════
  // UPLOAD MANUAL — pilih gambar dari gallery
  // ═══════════════════════════════════════
  Future<void> _pickAndUpload(int index) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _busy[index] = true);
    try {
      final tplId = 'tpl_${index + 1}';
      final bytes = await file.readAsBytes();
      final ref = _storage.ref('pdf_templates/$tplId.jpg');
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      await _db.collection('config').doc('pdf_templates').set(
        {tplId: url, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

      setState(() => _imageUrls[index] = url);
      _snack('${_templates[index].name} berjaya dimuat naik');
    } catch (e) {
      _snack('Gagal upload: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy[index] = false);
    }
  }

  Future<void> _removeImage(int index) async {
    final tplId = 'tpl_${index + 1}';
    setState(() => _busy[index] = true);
    try {
      try {
        await _storage.ref('pdf_templates/$tplId.jpg').delete();
      } catch (_) {}

      await _db.collection('config').doc('pdf_templates').set(
        {tplId: FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

      setState(() => _imageUrls[index] = null);
      _snack('${_templates[index].name} dipadam');
    } catch (e) {
      _snack('Gagal padam: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy[index] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final uploaded = _imageUrls.where((u) => u != null).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ═══ HEADER ═══
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const FaIcon(
                    FontAwesomeIcons.filePdf,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TEMPLATE PDF',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Buka PDF → Screenshot → Upload',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$uploaded / 10',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _manualRefresh,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.arrowsRotate,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ═══ 10 TEMPLATE CARDS ═══
          for (int i = 0; i < 10; i++) ...[
            _templateCard(i),
            if (i < 9) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _templateCard(int index) {
    final tpl = _templates[index];
    final url = _imageUrls[index];
    final isBusy = _busy[index];
    final tplId = 'TPL_${index + 1}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: url != null ? tpl.color.withValues(alpha: 0.4) : AppColors.border,
          width: url != null ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (url != null ? tpl.color : Colors.black).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── Header ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tpl.bgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(bottom: BorderSide(color: tpl.color.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: tpl.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FaIcon(tpl.icon, size: 12, color: tpl.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tplId, style: TextStyle(color: tpl.color.withValues(alpha: 0.6), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      Text(tpl.name, style: TextStyle(color: tpl.color, fontSize: 13, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (url != null ? AppColors.green : AppColors.textDim).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: (url != null ? AppColors.green : AppColors.textDim).withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(url != null ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleXmark, size: 8, color: url != null ? AppColors.green : AppColors.textDim),
                    const SizedBox(width: 4),
                    Text(url != null ? 'AKTIF' : 'KOSONG', style: TextStyle(color: url != null ? AppColors.green : AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ],
            ),
          ),

          // ─── Body: PREVIEW kiri | ACTION kanan ───
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // KOTAK PREVIEW
                Expanded(
                  child: Column(
                    children: [
                      Text('PREVIEW', style: TextStyle(color: tpl.color.withValues(alpha: 0.6), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: tpl.bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tpl.color.withValues(alpha: 0.15)),
                        ),
                        child: url != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  loadingBuilder: (ctx, child, p) {
                                    if (p == null) return child;
                                    return Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: tpl.color)));
                                  },
                                  errorBuilder: (_, __, ___) => Center(
                                    child: FaIcon(FontAwesomeIcons.triangleExclamation, size: 18, color: tpl.color.withValues(alpha: 0.4)),
                                  ),
                                ),
                              )
                            : Center(
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  FaIcon(FontAwesomeIcons.image, size: 24, color: tpl.color.withValues(alpha: 0.2)),
                                  const SizedBox(height: 6),
                                  Text('BELUM ADA\nGAMBAR', textAlign: TextAlign.center, style: TextStyle(color: tpl.color.withValues(alpha: 0.3), fontSize: 8, fontWeight: FontWeight.w800)),
                                ]),
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // KOTAK ACTION
                Expanded(
                  child: Column(
                    children: [
                      Text('TINDAKAN', style: TextStyle(color: tpl.color.withValues(alpha: 0.6), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tpl.color.withValues(alpha: 0.15)),
                        ),
                        child: isBusy
                            ? Center(
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: tpl.color)),
                                  const SizedBox(height: 8),
                                  Text('SEDANG\nPROSES...', textAlign: TextAlign.center, style: TextStyle(color: tpl.color, fontSize: 8, fontWeight: FontWeight.w900)),
                                ]),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // BUKA PDF — generate & open in browser
                                    _actionBtn(
                                      icon: FontAwesomeIcons.filePdf,
                                      label: 'BUKA PDF',
                                      color: tpl.color,
                                      onTap: () => _openPdfPreview(index),
                                    ),
                                    const SizedBox(height: 8),
                                    // UPLOAD SCREENSHOT
                                    _actionBtn(
                                      icon: FontAwesomeIcons.cloudArrowUp,
                                      label: 'UPLOAD GAMBAR',
                                      color: AppColors.blue,
                                      onTap: () => _pickAndUpload(index),
                                    ),
                                    if (url != null) ...[
                                      const SizedBox(height: 8),
                                      _actionBtn(
                                        icon: FontAwesomeIcons.trash,
                                        label: 'PADAM',
                                        color: AppColors.red,
                                        onTap: () => _removeImage(index),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, size: 10, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _TplInfo {
  final String name;
  final Color color;
  final Color bgColor;
  final IconData icon;
  const _TplInfo(this.name, this.color, this.bgColor, this.icon);
}
