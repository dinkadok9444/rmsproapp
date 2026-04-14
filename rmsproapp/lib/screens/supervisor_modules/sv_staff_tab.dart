import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
class SvStaffTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvStaffTab({required this.ownerID, required this.shopID});
  @override
  State<SvStaffTab> createState() => SvStaffTabState();
}

class SvStaffTabState extends State<SvStaffTab> {
  final _db = FirebaseFirestore.instance;
  List<dynamic> _staffList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await _db
        .collection('shops_${widget.ownerID}')
        .doc(widget.shopID)
        .get();
    if (snap.exists && mounted) {
      setState(() {
        _staffList = List<dynamic>.from(snap.data()?['staffList'] ?? []);
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
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

  void _showAddStaffModal() {
    final namaCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.userPlus,
                  size: 14,
                  color: AppColors.blue,
                ),
                SizedBox(width: 8),
                Text(
                  'DAFTAR STAF BARU',
                  style: TextStyle(
                    color: AppColors.blue,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('Nama Penuh'),
            TextField(
              controller: namaCtrl,
              style: _inputStyle,
              decoration: _inputDeco('Cth: Ahmad Ali'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('No Telefon'),
                      TextField(
                        controller: telCtrl,
                        keyboardType: TextInputType.phone,
                        style: _inputStyle,
                        decoration: _inputDeco('011...'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Passcode (PIN)'),
                      TextField(
                        controller: pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        style: _inputStyle,
                        decoration: _inputDeco('123456'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (namaCtrl.text.trim().isEmpty) {
                    _snack('Sila isi nama', err: true);
                    return;
                  }
                  final phone = telCtrl.text.trim().replaceAll(
                    RegExp(r'[\s\-()]'),
                    '',
                  );
                  final pin = pinCtrl.text.trim();
                  final name = namaCtrl.text.trim().toUpperCase();
                  if (phone.isEmpty) {
                    _snack('Sila isi no telefon', err: true);
                    return;
                  }
                  if (pin.isEmpty) {
                    _snack('Sila isi PIN', err: true);
                    return;
                  }
                  // Check if phone already used
                  try {
                    final existing = await _db
                        .collection('global_staff')
                        .doc(phone)
                        .get();
                    if (existing.exists) {
                      final data = existing.data()!;
                      final existOwner = (data['ownerID'] ?? '').toString();
                      final existShop = (data['shopID'] ?? '').toString();
                      if (existOwner.isNotEmpty &&
                          existShop.isNotEmpty &&
                          (existOwner != widget.ownerID ||
                              existShop != widget.shopID)) {
                        _snack(
                          'No telefon sudah digunakan oleh cawangan lain ($existShop)',
                          err: true,
                        );
                        return;
                      }
                    }
                  } catch (_) {}
                  _staffList.add({
                    'name': name,
                    'phone': phone,
                    'pin': pin,
                    'status': 'active',
                  });
                  await _db
                      .collection('shops_${widget.ownerID}')
                      .doc(widget.shopID)
                      .set({'staffList': _staffList}, SetOptions(merge: true));
                  await _db.collection('global_staff').doc(phone).set({
                    'name': name,
                    'phone': phone,
                    'pin': pin,
                    'status': 'active',
                    'ownerID': widget.ownerID,
                    'shopID': widget.shopID,
                  }, SetOptions(merge: true));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {});
                    _snack('Staff berjaya ditambah');
                  }
                },
                icon: const FaIcon(FontAwesomeIcons.plus, size: 12),
                label: const Text('TAMBAH STAF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStaff(int index) async {
    final s = _staffList[index];
    if (s is Map) {
      final current = (s['status'] ?? 'active').toString();
      s['status'] = current == 'active' ? 'suspended' : 'active';
      await _db.collection('shops_${widget.ownerID}').doc(widget.shopID).set({
        'staffList': _staffList,
      }, SetOptions(merge: true));
      final phone = (s['phone'] ?? '').toString().replaceAll(
        RegExp(r'[\s\-()]'),
        '',
      );
      if (phone.isNotEmpty) {
        await _db.collection('global_staff').doc(phone).set({
          'status': s['status'],
        }, SetOptions(merge: true));
      }
      setState(() {});
      _snack('Staff ${s['name']} → ${s['status']}');
    }
  }

  Future<void> _deleteStaff(int index) async {
    final s = _staffList[index];
    final name = s is String ? s : (s['name'] ?? '-');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Padam $name?',
          style: const TextStyle(
            color: AppColors.red,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Staff ini akan dibuang dari senarai.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('PADAM'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final phone = s is Map
          ? (s['phone'] ?? '').toString().replaceAll(RegExp(r'[\s\-()]'), '')
          : '';
      _staffList.removeAt(index);
      await _db.collection('shops_${widget.ownerID}').doc(widget.shopID).set({
        'staffList': _staffList,
      }, SetOptions(merge: true));
      if (phone.isNotEmpty) {
        await _db.collection('global_staff').doc(phone).delete();
        // Padam semua log aktiviti staff ini
        final logSnap = await _db
            .collection('staff_logs_${widget.ownerID}')
            .where('staffPhone', isEqualTo: phone)
            .get();
        final batch = _db.batch();
        for (final doc in logSnap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      setState(() {});
      _snack('Staff $name dipadam');
    }
  }

  Future<void> _resetStaffPin(int index) async {
    final s = _staffList[index];
    if (s is! Map) return;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Reset PIN: ${s['name']}',
          style: const TextStyle(
            color: AppColors.yellow,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          style: _inputStyle,
          decoration: _inputDeco('PIN baru...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) {
                _snack('Sila masukkan PIN baru', err: true);
                return;
              }
              Navigator.pop(ctx);
              final newPin = ctrl.text.trim();
              s['pin'] = newPin;
              await _db
                  .collection('shops_${widget.ownerID}')
                  .doc(widget.shopID)
                  .set({'staffList': _staffList}, SetOptions(merge: true));
              final phone = (s['phone'] ?? '').toString().replaceAll(
                RegExp(r'[\s\-()]'),
                '',
              );
              if (phone.isNotEmpty) {
                await _db.collection('global_staff').doc(phone).set({
                  'pin': newPin,
                }, SetOptions(merge: true));
              }
              setState(() {});
              _snack('PIN ${s['name']} berjaya direset');
            },
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProfileImage(int index) async {
    final s = _staffList[index];
    if (s is! Map) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 70,
    );
    if (picked == null) return;

    final phone = (s['phone'] ?? '').toString().replaceAll(
      RegExp(r'[\s\-()]'),
      '',
    );
    if (phone.isEmpty) return;

    try {
      _snack('Sedang muat naik gambar...');
      final ref = FirebaseStorage.instance.ref(
        'staff_profiles/${widget.ownerID}/${widget.shopID}/$phone.jpg',
      );
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();

      s['profileUrl'] = url;
      await _db.collection('shops_${widget.ownerID}').doc(widget.shopID).set({
        'staffList': _staffList,
      }, SetOptions(merge: true));
      await _db.collection('global_staff').doc(phone).set({
        'profileUrl': url,
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() {});
        _snack('Gambar profil berjaya dikemaskini');
      }
    } catch (e) {
      _snack('Gagal muat naik: $e', err: true);
    }
  }

  TextStyle get _inputStyle =>
      const TextStyle(color: AppColors.textPrimary, fontSize: 12);

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
    filled: true,
    fillColor: AppColors.bg,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.borderMed),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.borderMed),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      t,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: AppColors.blue, width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.users,
                    size: 14,
                    color: AppColors.blue,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'SENARAI STAF',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    '${_staffList.length} staf',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _showAddStaffModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(
                            FontAwesomeIcons.plus,
                            size: 10,
                            color: Colors.black,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'TAMBAH',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _staffList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.userSlash,
                        size: 40,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tiada staff didaftarkan',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tekan TAMBAH untuk daftar staf baru',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _staffList.length,
                  itemBuilder: (_, i) {
                    final s = _staffList[i];
                    final name = s is String
                        ? s
                        : (s['name'] ?? s['nama'] ?? '-');
                    final phone = s is Map ? (s['phone'] ?? '-') : '-';
                    final status = s is Map
                        ? (s['status'] ?? 'active')
                        : 'active';
                    final isActive =
                        status.toString().toLowerCase() == 'active';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.borderLight,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => _pickProfileImage(i),
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color:
                                        (isActive
                                                ? AppColors.green
                                                : AppColors.red)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          (isActive
                                                  ? AppColors.green
                                                  : AppColors.red)
                                              .withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    image:
                                        (s is Map &&
                                            (s['profileUrl'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                        ? DecorationImage(
                                            image: NetworkImage(
                                              s['profileUrl'].toString(),
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child:
                                      (s is Map &&
                                          (s['profileUrl'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                      ? Align(
                                          alignment: Alignment.bottomRight,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.15),
                                                  blurRadius: 3,
                                                ),
                                              ],
                                            ),
                                            child: const FaIcon(
                                              FontAwesomeIcons.camera,
                                              size: 8,
                                              color: AppColors.textDim,
                                            ),
                                          ),
                                        )
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            FaIcon(
                                              FontAwesomeIcons.user,
                                              size: 14,
                                              color: isActive
                                                  ? AppColors.green
                                                  : AppColors.red,
                                            ),
                                            const SizedBox(height: 2),
                                            const FaIcon(
                                              FontAwesomeIcons.camera,
                                              size: 7,
                                              color: AppColors.textDim,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.toString().toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      phone.toString(),
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (isActive
                                              ? AppColors.green
                                              : AppColors.red)
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        (isActive
                                                ? AppColors.green
                                                : AppColors.red)
                                            .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  isActive ? 'AKTIF' : 'GANTUNG',
                                  style: TextStyle(
                                    color: isActive
                                        ? AppColors.green
                                        : AppColors.red,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _actionBtn(
                                'Reset PIN',
                                FontAwesomeIcons.key,
                                AppColors.yellow,
                                () => _resetStaffPin(i),
                              ),
                              const SizedBox(width: 6),
                              _actionBtn(
                                isActive ? 'Gantung' : 'Aktifkan',
                                FontAwesomeIcons.userSlash,
                                isActive ? AppColors.orange : AppColors.green,
                                () => _toggleStaff(i),
                              ),
                              const SizedBox(width: 6),
                              _actionBtn(
                                'Padam',
                                FontAwesomeIcons.trash,
                                AppColors.red,
                                () => _deleteStaff(i),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(icon, size: 10, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
