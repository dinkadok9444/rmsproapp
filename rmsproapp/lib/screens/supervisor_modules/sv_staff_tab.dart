import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/supabase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';
class SvStaffTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvStaffTab({required this.ownerID, required this.shopID});
  @override
  State<SvStaffTab> createState() => SvStaffTabState();
}

class SvStaffTabState extends State<SvStaffTab> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  List<dynamic> _staffList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    await _load();
  }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final rows = await _sb
          .from('branch_staff')
          .select()
          .eq('branch_id', _branchId!)
          .order('created_at');
      final list = rows.map((r) => {
        'id': r['id'],
        'name': r['nama'] ?? '',
        'phone': r['phone'] ?? '',
        'pin': r['pin'] ?? '',
        'status': r['status'] ?? 'active',
        'profileUrl': (r['payload'] is Map ? (r['payload']['profileUrl'] ?? '') : ''),
      }).toList();
      if (mounted) {
        setState(() {
          _staffList = list;
          _isLoading = false;
        });
      }
    } catch (_) {
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
                    final existing = await _sb.from('global_staff').select().eq('tel', phone).maybeSingle();
                    if (existing != null) {
                      final existOwner = (existing['owner_id'] ?? '').toString();
                      final existShop = (existing['shop_id'] ?? '').toString();
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
                  if (_tenantId == null || _branchId == null) return;
                  try {
                    final inserted = await _sb.from('branch_staff').insert({
                      'tenant_id': _tenantId,
                      'branch_id': _branchId,
                      'nama': name,
                      'phone': phone,
                      'pin': pin,
                      'status': 'active',
                      'role': 'staff',
                    }).select('id').single();
                    _staffList.add({
                      'id': inserted['id'],
                      'name': name,
                      'phone': phone,
                      'pin': pin,
                      'status': 'active',
                    });
                    await _sb.from('global_staff').upsert({
                      'tel': phone,
                      'tenant_id': _tenantId,
                      'branch_id': _branchId,
                      'owner_id': widget.ownerID,
                      'shop_id': widget.shopID,
                      'nama': name,
                      'role': 'staff',
                      'payload': {'pin': pin, 'status': 'active'},
                    });
                  } catch (e) {
                    _snack('Gagal tambah: $e', err: true);
                    return;
                  }
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
      final newStatus = current == 'active' ? 'suspended' : 'active';
      s['status'] = newStatus;
      final staffId = s['id'];
      if (staffId != null) {
        await _sb.from('branch_staff').update({'status': newStatus}).eq('id', staffId);
      }
      final phone = (s['phone'] ?? '').toString().replaceAll(RegExp(r'[\s\-()]'), '');
      if (phone.isNotEmpty) {
        try {
          final existing = await _sb.from('global_staff').select('payload').eq('tel', phone).maybeSingle();
          final payload = (existing?['payload'] is Map) ? Map<String, dynamic>.from(existing!['payload']) : <String, dynamic>{};
          payload['status'] = newStatus;
          await _sb.from('global_staff').update({'payload': payload}).eq('tel', phone);
        } catch (_) {}
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
      final staffId = s is Map ? s['id'] : null;
      _staffList.removeAt(index);
      if (staffId != null) {
        await _sb.from('branch_staff').delete().eq('id', staffId);
      }
      if (phone.isNotEmpty) {
        await _sb.from('global_staff').delete().eq('tel', phone);
        // Padam log aktiviti staff ini
        try {
          await _sb.from('staff_logs').delete().eq('staff_phone', phone);
        } catch (_) {}
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
              final staffId = s['id'];
              if (staffId != null) {
                await _sb.from('branch_staff').update({'pin': newPin}).eq('id', staffId);
              }
              final phone = (s['phone'] ?? '').toString().replaceAll(RegExp(r'[\s\-()]'), '');
              if (phone.isNotEmpty) {
                try {
                  final existing = await _sb.from('global_staff').select('payload').eq('tel', phone).maybeSingle();
                  final payload = (existing?['payload'] is Map) ? Map<String, dynamic>.from(existing!['payload']) : <String, dynamic>{};
                  payload['pin'] = newPin;
                  await _sb.from('global_staff').update({'payload': payload}).eq('tel', phone);
                } catch (_) {}
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
      final url = await SupabaseStorageHelper().uploadFile(
        bucket: 'staff_avatars',
        path: '${widget.ownerID}/${widget.shopID}/$phone.jpg',
        file: File(picked.path),
      );

      s['profileUrl'] = url;
      final staffId = s['id'];
      if (staffId != null) {
        final existing = await _sb.from('branch_staff').select('payload').eq('id', staffId).maybeSingle();
        final payload = (existing?['payload'] is Map) ? Map<String, dynamic>.from(existing!['payload']) : <String, dynamic>{};
        payload['profileUrl'] = url;
        await _sb.from('branch_staff').update({'payload': payload}).eq('id', staffId);
      }
      try {
        final existing = await _sb.from('global_staff').select('payload').eq('tel', phone).maybeSingle();
        final payload = (existing?['payload'] is Map) ? Map<String, dynamic>.from(existing!['payload']) : <String, dynamic>{};
        payload['profileUrl'] = url;
        await _sb.from('global_staff').update({'payload': payload}).eq('tel', phone);
      } catch (_) {}
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
