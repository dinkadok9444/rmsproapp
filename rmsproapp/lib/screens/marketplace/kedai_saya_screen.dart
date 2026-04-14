import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';

const _purple = Color(0xFF8B5CF6);
const _purpleLight = Color(0xFFEDE9FE);

const List<String> _categories = [
  'LCD',
  'Bateri',
  'Casing',
  'Spare Part',
  'Aksesori',
  'Lain-lain',
];

class KedaiSayaScreen extends StatefulWidget {
  final String ownerID, shopID;
  const KedaiSayaScreen({
    super.key,
    required this.ownerID,
    required this.shopID,
  });

  @override
  State<KedaiSayaScreen> createState() => _KedaiSayaScreenState();
}

class _KedaiSayaScreenState extends State<KedaiSayaScreen> {
  final _firestore = FirebaseFirestore.instance;
  String _shopName = '';

  // Bank detail controllers
  final _bankNameCtrl = TextEditingController();
  final _bankAccNoCtrl = TextEditingController();
  final _bankAccNameCtrl = TextEditingController();
  bool _bankSaving = false;

  String get _shopDocId => '${widget.ownerID}_${widget.shopID}';

  @override
  void initState() {
    super.initState();
    _loadShopName();
    _loadBankDetails();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankAccNoCtrl.dispose();
    _bankAccNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShopName() async {
    // Try SharedPreferences first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('rms_shop_name');
    if (cached != null && cached.isNotEmpty) {
      setState(() => _shopName = cached);
      return;
    }
    // Fallback to Firestore
    try {
      final doc = await _firestore
          .collection('shops_${widget.ownerID}')
          .doc(widget.shopID)
          .get();
      if (doc.exists) {
        final name = doc.data()?['shopName'] ?? 'Kedai Saya';
        setState(() => _shopName = name);
      } else {
        setState(() => _shopName = 'Kedai Saya');
      }
    } catch (_) {
      setState(() => _shopName = 'Kedai Saya');
    }
  }

  Future<void> _loadBankDetails() async {
    try {
      final doc = await _firestore
          .collection('marketplace_shops')
          .doc(_shopDocId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _bankNameCtrl.text = data['bankName'] ?? '';
        _bankAccNoCtrl.text = data['bankAccountNo'] ?? '';
        _bankAccNameCtrl.text = data['bankAccountName'] ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveBankDetails() async {
    setState(() => _bankSaving = true);
    try {
      await _firestore
          .collection('marketplace_shops')
          .doc(_shopDocId)
          .set({
        'bankName': _bankNameCtrl.text.trim(),
        'bankAccountNo': _bankAccNoCtrl.text.trim(),
        'bankAccountName': _bankAccNameCtrl.text.trim(),
        'ownerID': widget.ownerID,
        'shopID': widget.shopID,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maklumat bank berjaya disimpan'),
            backgroundColor: _purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal simpan: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _bankSaving = false);
  }

  Future<void> _toggleActive(String docId, bool currentActive) async {
    await _firestore
        .collection('marketplace_global')
        .doc(docId)
        .update({'isActive': !currentActive});
  }

  Future<void> _deleteProduct(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padam Produk'),
        content: const Text('Adakah anda pasti mahu padam produk ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Padam'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('marketplace_global').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk berjaya dipadam'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  void _openProductModal({Map<String, dynamic>? existing, String? docId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductFormSheet(
        ownerID: widget.ownerID,
        shopID: widget.shopID,
        shopName: _shopName,
        existing: existing,
        docId: docId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _purple,
        onPressed: () => _openProductModal(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShopHeader(),
            const SizedBox(height: 14),
            _buildProductsSection(),
          ],
        ),
      ),
    );
  }

  // ───────── Settings Popup ─────────
  void _showSettingsPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.gear, size: 14, color: _purple),
                  const SizedBox(width: 8),
                  const Text(
                    'TETAPAN KEDAI',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.textDim),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _settingsTile(
                    'Maklumat Bank',
                    'Tetapan akaun bank untuk terima bayaran',
                    FontAwesomeIcons.buildingColumns,
                    const Color(0xFF3B82F6),
                    () {
                      Navigator.pop(ctx);
                      _showBankPopup();
                    },
                  ),
                  const SizedBox(height: 10),
                  _settingsTile(
                    'Alamat Pickup',
                    'Tetapan alamat untuk pembeli pickup barang',
                    FontAwesomeIcons.locationDot,
                    const Color(0xFF10B981),
                    () {
                      Navigator.pop(ctx);
                      _showAlamatPickupPopup();
                    },
                  ),
                  const SizedBox(height: 10),
                  _settingsTile(
                    'Alamat Penerima',
                    'Alamat tetap untuk terima barang dari marketplace',
                    FontAwesomeIcons.mapLocationDot,
                    const Color(0xFF3B82F6),
                    () {
                      Navigator.pop(ctx);
                      _showAlamatPenerimaPopup();
                    },
                  ),
                  const SizedBox(height: 10),
                  _settingsTile(
                    'Pengesahan Seller',
                    'Upload IC depan & belakang untuk pengesahan',
                    FontAwesomeIcons.idCard,
                    const Color(0xFFF59E0B),
                    () {
                      Navigator.pop(ctx);
                      _showVerificationPopup();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: FaIcon(icon, size: 16, color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800,
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10,
                  )),
                ],
              ),
            ),
            const FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }

  // ───────── Bank Popup ─────────
  void _showBankPopup() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.buildingColumns, size: 14, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  const Text('MAKLUMAT BANK', style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900,
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim),
                  ),
                ],
              ),
              const Divider(height: 20, color: AppColors.border),
              _bankField('Nama Bank', _bankNameCtrl, 'cth: Maybank'),
              const SizedBox(height: 10),
              _bankField('No. Akaun', _bankAccNoCtrl, 'cth: 1234567890'),
              const SizedBox(height: 10),
              _bankField('Nama Pemilik Akaun', _bankAccNameCtrl, 'cth: Ali bin Abu'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _bankSaving ? null : () async {
                    await _saveBankDetails();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: _bankSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const FaIcon(FontAwesomeIcons.floppyDisk, size: 12, color: Colors.white),
                  label: Text(_bankSaving ? 'Menyimpan...' : 'Simpan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── Alamat Pickup Popup ─────────
  void _showAlamatPickupPopup() async {
    final phoneCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    final negeriCtrl = TextEditingController();
    final bandarCtrl = TextEditingController();
    final poskodCtrl = TextEditingController();
    bool saving = false;

    // Load existing BEFORE showing dialog
    try {
      final doc = await _firestore.collection('marketplace_shops').doc(_shopDocId).get();
      if (doc.exists) {
        final d = doc.data()!;
        phoneCtrl.text = d['phone'] ?? '';
        alamatCtrl.text = d['pickupAlamat'] ?? '';
        negeriCtrl.text = d['pickupNegeri'] ?? '';
        bandarCtrl.text = d['pickupBandar'] ?? '';
        poskodCtrl.text = d['pickupPoskod'] ?? '';
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.locationDot, size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    const Text('ALAMAT PICKUP', style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900,
                    )),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim),
                    ),
                  ],
                ),
                const Divider(height: 20, color: AppColors.border),
                _bankField('No. Telefon', phoneCtrl, 'cth: 0123456789'),
                const SizedBox(height: 10),
                _bankField('Alamat Penuh', alamatCtrl, 'No. 1, Jalan ABC...'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _bankField('Bandar', bandarCtrl, 'cth: Puchong')),
                    const SizedBox(width: 8),
                    SizedBox(width: 90, child: _bankField('Poskod', poskodCtrl, 'cth: 47100')),
                  ],
                ),
                const SizedBox(height: 10),
                _bankField('Negeri', negeriCtrl, 'cth: Selangor'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: saving ? null : () async {
                      setS(() => saving = true);
                      await _firestore.collection('marketplace_shops').doc(_shopDocId).set({
                        'phone': phoneCtrl.text.trim(),
                        'pickupAlamat': alamatCtrl.text.trim(),
                        'pickupNegeri': negeriCtrl.text.trim(),
                        'pickupBandar': bandarCtrl.text.trim(),
                        'pickupPoskod': poskodCtrl.text.trim(),
                        'ownerID': widget.ownerID,
                        'shopID': widget.shopID,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      setS(() => saving = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Alamat pickup disimpan'), backgroundColor: Color(0xFF10B981)),
                        );
                      }
                    },
                    icon: saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const FaIcon(FontAwesomeIcons.floppyDisk, size: 12, color: Colors.white),
                    label: Text(saving ? 'Menyimpan...' : 'Simpan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────── Alamat Penerima Popup ─────────
  void _showAlamatPenerimaPopup() async {
    final namaCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    final negeriCtrl = TextEditingController();
    final bandarCtrl = TextEditingController();
    final poskodCtrl = TextEditingController();
    bool saving = false;

    try {
      final doc = await _firestore.collection('marketplace_shops').doc(_shopDocId).get();
      if (doc.exists) {
        final d = doc.data()!;
        namaCtrl.text = d['receiverName'] ?? '';
        phoneCtrl.text = d['receiverPhone'] ?? '';
        alamatCtrl.text = d['receiverAlamat'] ?? '';
        negeriCtrl.text = d['receiverNegeri'] ?? '';
        bandarCtrl.text = d['receiverBandar'] ?? '';
        poskodCtrl.text = d['receiverPoskod'] ?? '';
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.mapLocationDot, size: 14, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 8),
                      const Text('ALAMAT PENERIMA', style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900,
                      )),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: AppColors.border),
                  const Text(
                    'Alamat tetap untuk terima barang. Akan auto-isi masa checkout.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                  const SizedBox(height: 12),
                  _bankField('Nama Penerima', namaCtrl, 'cth: Ahmad bin Ali'),
                  const SizedBox(height: 10),
                  _bankField('No. Telefon', phoneCtrl, 'cth: 0123456789'),
                  const SizedBox(height: 10),
                  _bankField('Alamat Penuh', alamatCtrl, 'No. 1, Jalan ABC...'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _bankField('Bandar', bandarCtrl, 'cth: Puchong')),
                      const SizedBox(width: 8),
                      SizedBox(width: 90, child: _bankField('Poskod', poskodCtrl, 'cth: 47100')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _bankField('Negeri', negeriCtrl, 'cth: Selangor'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : () async {
                        setS(() => saving = true);
                        debugPrint('=== SAVE RECEIVER === docId: $_shopDocId');
                        debugPrint('=== SAVE DATA === name: ${namaCtrl.text}, alamat: ${alamatCtrl.text}');
                        await _firestore.collection('marketplace_shops').doc(_shopDocId).set({
                          'receiverName': namaCtrl.text.trim(),
                          'receiverPhone': phoneCtrl.text.trim(),
                          'receiverAlamat': alamatCtrl.text.trim(),
                          'receiverNegeri': negeriCtrl.text.trim(),
                          'receiverBandar': bandarCtrl.text.trim(),
                          'receiverPoskod': poskodCtrl.text.trim(),
                          'ownerID': widget.ownerID,
                          'shopID': widget.shopID,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        setS(() => saving = false);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Alamat penerima disimpan'), backgroundColor: Color(0xFF3B82F6)),
                          );
                        }
                      },
                      icon: saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const FaIcon(FontAwesomeIcons.floppyDisk, size: 12, color: Colors.white),
                      label: Text(saving ? 'Menyimpan...' : 'Simpan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────── Pengesahan Seller Popup ─────────
  void _showVerificationPopup() async {
    String? icFrontUrl;
    String? icBackUrl;
    String verifyStatus = 'belum';
    bool uploading = false;

    try {
      final doc = await _firestore.collection('marketplace_shops').doc(_shopDocId).get();
      if (doc.exists) {
        final d = doc.data()!;
        icFrontUrl = d['icFrontUrl'] as String?;
        icBackUrl = d['icBackUrl'] as String?;
        verifyStatus = d['verifyStatus'] ?? 'belum';
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.idCard, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    const Text('PENGESAHAN SELLER', style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900,
                    )),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: AppColors.textDim),
                    ),
                  ],
                ),
                const Divider(height: 20, color: AppColors.border),
                // Status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: verifyStatus == 'verified'
                        ? AppColors.green.withValues(alpha: 0.1)
                        : verifyStatus == 'pending'
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                            : AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: verifyStatus == 'verified'
                          ? AppColors.green.withValues(alpha: 0.3)
                          : verifyStatus == 'pending'
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                              : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      FaIcon(
                        verifyStatus == 'verified' ? FontAwesomeIcons.circleCheck
                            : verifyStatus == 'pending' ? FontAwesomeIcons.clock
                            : FontAwesomeIcons.circleExclamation,
                        size: 14,
                        color: verifyStatus == 'verified' ? AppColors.green
                            : verifyStatus == 'pending' ? const Color(0xFFF59E0B)
                            : AppColors.textDim,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        verifyStatus == 'verified' ? 'Disahkan'
                            : verifyStatus == 'pending' ? 'Menunggu Pengesahan'
                            : 'Belum Disahkan',
                        style: TextStyle(
                          color: verifyStatus == 'verified' ? AppColors.green
                              : verifyStatus == 'pending' ? const Color(0xFFF59E0B)
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // IC Front
                _icUploadCard(
                  'IC Depan',
                  icFrontUrl,
                  uploading,
                  () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);
                    if (picked == null) return;
                    setS(() => uploading = true);
                    try {
                      final ref = FirebaseStorage.instance.ref('seller_verification/${widget.ownerID}/ic_front.jpg');
                      await ref.putFile(File(picked.path));
                      final url = await ref.getDownloadURL();
                      await _firestore.collection('marketplace_shops').doc(_shopDocId).set({
                        'icFrontUrl': url,
                        'verifyStatus': 'pending',
                        'ownerID': widget.ownerID,
                        'shopID': widget.shopID,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      setS(() { icFrontUrl = url; verifyStatus = 'pending'; uploading = false; });
                    } catch (e) {
                      setS(() => uploading = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal upload: $e'), backgroundColor: AppColors.red),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                // IC Back
                _icUploadCard(
                  'IC Belakang',
                  icBackUrl,
                  uploading,
                  () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);
                    if (picked == null) return;
                    setS(() => uploading = true);
                    try {
                      final ref = FirebaseStorage.instance.ref('seller_verification/${widget.ownerID}/ic_back.jpg');
                      await ref.putFile(File(picked.path));
                      final url = await ref.getDownloadURL();
                      await _firestore.collection('marketplace_shops').doc(_shopDocId).set({
                        'icBackUrl': url,
                        'verifyStatus': 'pending',
                        'ownerID': widget.ownerID,
                        'shopID': widget.shopID,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      setS(() { icBackUrl = url; verifyStatus = 'pending'; uploading = false; });
                    } catch (e) {
                      setS(() => uploading = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal upload: $e'), backgroundColor: AppColors.red),
                        );
                      }
                    }
                  },
                ),
                if (uploading) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icUploadCard(String label, String? url, bool uploading, VoidCallback onTap) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: url != null ? AppColors.green.withValues(alpha: 0.3) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: url != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: FaIcon(FontAwesomeIcons.image, size: 14, color: AppColors.textDim),
                        ),
                      ),
                    )
                  : const Center(
                      child: FaIcon(FontAwesomeIcons.idCard, size: 14, color: AppColors.textDim),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700,
                  )),
                  Text(
                    url != null ? 'Sudah dimuat naik' : 'Tekan untuk upload',
                    style: TextStyle(
                      color: url != null ? AppColors.green : AppColors.textDim,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            FaIcon(
              url != null ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.upload,
              size: 14,
              color: url != null ? AppColors.green : AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }

  // ───────── Shop Profile Header ─────────
  Widget _buildShopHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('marketplace_global')
          .where('ownerID', isEqualTo: widget.ownerID)
          .snapshots(),
      builder: (context, snapshot) {
        int totalProducts = 0;
        int totalSold = 0;
        if (snapshot.hasData) {
          totalProducts = snapshot.data!.docs.length;
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            totalSold += (data['soldCount'] as num?)?.toInt() ?? 0;
          }
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_purple, Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _purple.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: FaIcon(
                        FontAwesomeIcons.shop,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shopName.isEmpty ? 'Kedai Saya' : _shopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${widget.shopID}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _showSettingsPopup,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: FaIcon(
                          FontAwesomeIcons.gear,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _headerStat(
                    FontAwesomeIcons.boxOpen,
                    '$totalProducts',
                    'Produk',
                  ),
                  const SizedBox(width: 24),
                  _headerStat(
                    FontAwesomeIcons.cartShopping,
                    '$totalSold',
                    'Terjual',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _headerStat(IconData icon, String value, String label) {
    return Row(
      children: [
        FaIcon(icon, color: Colors.white70, size: 13),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _bankField(
    String label,
    TextEditingController controller,
    String hint,
  ) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ───────── My Products ─────────
  Widget _buildProductsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _purpleLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const FaIcon(
                FontAwesomeIcons.boxesPacking,
                color: _purple,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Produk Saya',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('marketplace_global')
              .where('ownerID', isEqualTo: widget.ownerID)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: _purple),
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    'Ralat: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.boxOpen,
                        color: AppColors.textDim,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tiada produk lagi.\nTekan + untuk tambah produk.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                return _productCard(doc.id, data);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _productCard(String docId, Map<String, dynamic> data) {
    final name = data['itemName'] ?? 'Tiada Nama';
    final price = (data['price'] as num?)?.toDouble() ?? 0;
    final qty = (data['quantity'] as num?)?.toInt() ?? 0;
    final imageUrl = data['imageUrl'] as String?;
    final isActive = data['isActive'] ?? true;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppColors.border : AppColors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 70,
                height: 70,
                color: AppColors.bg,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: FaIcon(
                            FontAwesomeIcons.image,
                            color: AppColors.textDim,
                            size: 24,
                          ),
                        ),
                      )
                    : const Center(
                        child: FaIcon(
                          FontAwesomeIcons.image,
                          color: AppColors.textDim,
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RM ${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _purple,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Stok: $qty',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (!isActive)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.redLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Tidak Aktif',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Action buttons
            Column(
              children: [
                _actionBtn(
                  icon: isActive
                      ? FontAwesomeIcons.toggleOn
                      : FontAwesomeIcons.toggleOff,
                  color: isActive ? AppColors.green : AppColors.textDim,
                  onTap: () => _toggleActive(docId, isActive),
                ),
                const SizedBox(height: 6),
                _actionBtn(
                  icon: FontAwesomeIcons.penToSquare,
                  color: _purple,
                  onTap: () =>
                      _openProductModal(existing: data, docId: docId),
                ),
                const SizedBox(height: 6),
                _actionBtn(
                  icon: FontAwesomeIcons.trashCan,
                  color: AppColors.red,
                  onTap: () => _deleteProduct(docId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: FaIcon(icon, size: 13, color: color)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Product Add / Edit Bottom Sheet
// ═══════════════════════════════════════════════════════════

class _ProductFormSheet extends StatefulWidget {
  final String ownerID, shopID, shopName;
  final Map<String, dynamic>? existing;
  final String? docId;

  const _ProductFormSheet({
    required this.ownerID,
    required this.shopID,
    required this.shopName,
    this.existing,
    this.docId,
  });

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;

  String _selectedCategory = _categories.first;
  File? _pickedImage;
  String? _existingImageUrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['itemName'] ?? '');
    _descCtrl = TextEditingController(text: e?['description'] ?? '');
    _priceCtrl = TextEditingController(
      text: e != null ? (e['price'] as num?)?.toString() ?? '' : '',
    );
    _qtyCtrl = TextEditingController(
      text: e != null ? (e['quantity'] as num?)?.toString() ?? '' : '',
    );
    if (e != null) {
      final cat = e['category'] as String?;
      if (cat != null && _categories.contains(cat)) {
        _selectedCategory = cat;
      }
      _existingImageUrl = e['imageUrl'] as String?;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return _existingImageUrl;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage
        .ref()
        .child('marketplace/${widget.ownerID}/$timestamp.jpg');

    // Compress image: resize to max 512px
    final bytes = await _pickedImage!.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final compressed = byteData!.buffer.asUint8List();

    final uploadTask = await ref.putData(
      compressed,
      SettableMetadata(contentType: 'image/png'),
    );
    return await uploadTask.ref.getDownloadURL();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final imageUrl = await _uploadImage();
      final data = {
        'itemName': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _selectedCategory,
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0,
        'quantity': int.tryParse(_qtyCtrl.text.trim()) ?? 0,
        'imageUrl': imageUrl ?? '',
        'ownerID': widget.ownerID,
        'shopID': widget.shopID,
        'shopName': widget.shopName,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdit && widget.docId != null) {
        await _firestore
            .collection('marketplace_global')
            .doc(widget.docId)
            .update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['soldCount'] = 0;
        await _firestore.collection('marketplace_global').add(data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Produk berjaya dikemaskini'
                  : 'Produk berjaya ditambah',
            ),
            backgroundColor: _purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal simpan: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'Kemaskini Produk' : 'Tambah Produk Baru',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // Image Picker
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _pickedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            _pickedImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : _existingImageUrl != null &&
                              _existingImageUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                _existingImageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) =>
                                    _imagePlaceholder(),
                              ),
                            )
                          : _imagePlaceholder(),
                ),
              ),
              const SizedBox(height: 16),

              // Item Name
              _formField(
                controller: _nameCtrl,
                label: 'Nama Produk',
                hint: 'cth: LCD iPhone 13 Pro',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Sila masukkan nama' : null,
              ),
              const SizedBox(height: 12),

              // Description
              _formField(
                controller: _descCtrl,
                label: 'Penerangan',
                hint: 'Terangkan produk anda...',
                maxLines: 3,
              ),
              const SizedBox(height: 12),

              // Category Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: _inputDecoration('Kategori'),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedCategory = v);
                },
              ),
              const SizedBox(height: 12),

              // Price + Quantity row
              Row(
                children: [
                  Expanded(
                    child: _formField(
                      controller: _priceCtrl,
                      label: 'Harga (RM)',
                      hint: '0.00',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Masukkan harga';
                        }
                        if (double.tryParse(v.trim()) == null) {
                          return 'Harga tidak sah';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _formField(
                      controller: _qtyCtrl,
                      label: 'Kuantiti',
                      hint: '0',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Masukkan kuantiti';
                        }
                        if (int.tryParse(v.trim()) == null) {
                          return 'Kuantiti tidak sah';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveProduct,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const FaIcon(
                          FontAwesomeIcons.floppyDisk,
                          size: 15,
                          color: Colors.white,
                        ),
                  label: Text(
                    _saving
                        ? 'Menyimpan...'
                        : _isEdit
                            ? 'Kemaskini Produk'
                            : 'Simpan Produk',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: _purple.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(
          FontAwesomeIcons.camera,
          size: 28,
          color: AppColors.textDim,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tekan untuk pilih gambar',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: _inputDecoration(label, hint: hint),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _purple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
