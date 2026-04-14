import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

class DatabaseUserScreen extends StatefulWidget {
  const DatabaseUserScreen({super.key});

  @override
  State<DatabaseUserScreen> createState() => _DatabaseUserScreenState();
}

class _DatabaseUserScreenState extends State<DatabaseUserScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  String _sortMode = 'newest'; // 'newest' | 'oldest'

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _db
          .collection('saas_dealers')
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      _users = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'namaKedai': data['namaKedai'] ?? data['shopName'] ?? '-',
          'ownerName': data['ownerName'] ?? '-',
          'phone': data['ownerContact'] ?? data['phone'] ?? '',
          'negeri': data['negeri'] ?? '',
          'createdAt': _toMillis(data['createdAt']),
        };
      }).toList();
      _applyFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _toMillis(dynamic ts) {
    if (ts == null) return 0;
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is int) return ts;
    if (ts is double) return ts.toInt();
    return 0;
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    _filtered = _users.where((u) {
      if (q.isEmpty) return true;
      return (u['namaKedai'] as String).toLowerCase().contains(q) ||
          (u['ownerName'] as String).toLowerCase().contains(q) ||
          (u['phone'] as String).toLowerCase().contains(q);
    }).toList();
    _filtered.sort((a, b) {
      final ta = a['createdAt'] as int;
      final tb = b['createdAt'] as int;
      return _sortMode == 'newest' ? tb.compareTo(ta) : ta.compareTo(tb);
    });
    setState(() {});
  }

  String _normalizePhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.isEmpty) return '';
    if (p.startsWith('0')) p = '6$p';
    if (!p.startsWith('6') && p.length >= 9) p = '6$p';
    return p;
  }

  Future<void> _openWhatsapp(String raw) async {
    final phone = _normalizePhone(raw);
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No telefon tidak sah'), backgroundColor: AppColors.red),
      );
      return;
    }
    final uri = Uri.parse('https://wa.me/$phone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal buka WhatsApp: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.database, size: 16, color: AppColors.primary),
            const SizedBox(width: 10),
            const Text('Database User',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('${_filtered.length} / ${_users.length}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _load,
              icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14, color: AppColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _sortChip('Terbaru', 'newest', FontAwesomeIcons.arrowDownWideShort),
            const SizedBox(width: 8),
            _sortChip('Terlama', 'oldest', FontAwesomeIcons.arrowUpWideShort),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _applyFilter(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cari nama kedai / owner / no telefon',
              hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _filtered.isEmpty
                ? const Center(
                    child: Text('Tiada data', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _buildUserCard(_filtered[i]),
                  ),
      ),
    ]);
  }

  Widget _sortChip(String label, String mode, IconData icon) {
    final active = _sortMode == mode;
    return GestureDetector(
      onTap: () {
        if (_sortMode == mode) return;
        _sortMode = mode;
        _applyFilter();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.15) : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(icon, size: 10, color: active ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> u) {
    final nama = u['namaKedai'] as String;
    final owner = u['ownerName'] as String;
    final phone = u['phone'] as String;
    final negeri = u['negeri'] as String;
    final hasPhone = phone.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMed),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                nama,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                owner,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              if (negeri.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  negeri,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: hasPhone ? () => _openWhatsapp(phone) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: hasPhone
                  ? const Color(0xFF25D366).withValues(alpha: 0.1)
                  : AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasPhone
                    ? const Color(0xFF25D366).withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
            child: Row(children: [
              FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 14,
                color: hasPhone ? const Color(0xFF25D366) : AppColors.textDim,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasPhone ? phone : 'Tiada no telefon',
                  style: TextStyle(
                    color: hasPhone ? const Color(0xFF25D366) : AppColors.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (hasPhone)
                const FaIcon(FontAwesomeIcons.arrowUpRightFromSquare,
                    size: 11, color: Color(0xFF25D366)),
            ]),
          ),
        ),
      ]),
    );
  }
}
