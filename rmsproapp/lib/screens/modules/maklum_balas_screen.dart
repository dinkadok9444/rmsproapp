import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

class MaklumBalasScreen extends StatefulWidget {
  const MaklumBalasScreen({super.key});
  @override
  State<MaklumBalasScreen> createState() => _MaklumBalasScreenState();
}

class _MaklumBalasScreenState extends State<MaklumBalasScreen> {
  final _db = FirebaseFirestore.instance;
  final _lang = AppLanguage();
  final _searchCtrl = TextEditingController();
  final _staffSearchCtrl = TextEditingController();
  String _ownerID = 'admin', _shopID = 'MAIN';
  List<Map<String, dynamic>> _feedbacks = [];
  StreamSubscription? _sub;
  String _filterStar = 'Semua';
  String _sortOrder = 'Terbaru';
  String _dropdownValue = 'Semua_Terbaru';
  bool _showSearch = false;

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _sub?.cancel(); _searchCtrl.dispose(); _staffSearchCtrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) { _ownerID = branch.split('@')[0]; _shopID = branch.split('@')[1].toUpperCase(); }
    _sub = _db.collection('feedback_$_ownerID').snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['shopID'] ?? '').toString().toUpperCase() == _shopID) list.add(d);
      }
      if (mounted) setState(() => _feedbacks = list);
    });
  }

  double get _avgRating {
    if (_feedbacks.isEmpty) return 0;
    final total = _feedbacks.fold(0.0, (s, d) => s + ((d['rating'] ?? 0) as num).toDouble());
    return total / _feedbacks.length;
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_feedbacks);
    // Star filter
    if (_filterStar != 'Semua') {
      final star = int.tryParse(_filterStar) ?? 0;
      list = list.where((d) => (d['rating'] ?? 0) == star).toList();
    }
    // Search filter
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((d) =>
        (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
        (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
        (d['tel'] ?? '').toString().toLowerCase().contains(q)
      ).toList();
    }
    // Sort
    if (_sortOrder == 'Terbaru') {
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    } else {
      list.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));
    }
    return list;
  }

  Future<Map<String, String>> _lookupStaff(String siri) async {
    if (siri.isEmpty || siri == '-') return {'terima': '-', 'repair': '-', 'serah': '-'};
    try {
      final snap = await _db.collection('repairs_$_ownerID').where('siri', isEqualTo: siri).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        return {
          'terima': d['staff_terima'] ?? d['staffTerima'] ?? '-',
          'repair': d['staff_repair'] ?? d['staffRepair'] ?? '-',
          'serah': d['staff_serah'] ?? d['staffSerah'] ?? '-',
        };
      }
    } catch (_) {}
    return {'terima': '-', 'repair': '-', 'serah': '-'};
  }

  void _showStaffModal(Map<String, String> staff) {
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.yellow.withValues(alpha: 0.5))),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.idBadge, size: 14, color: AppColors.yellow),
            const SizedBox(width: 8),
            Text(_lang.get('mb_maklumat_staf'), style: const TextStyle(color: AppColors.yellow, fontSize: 14, fontWeight: FontWeight.w900)),
          ]),
          GestureDetector(onTap: () => Navigator.pop(ctx), child: const Text('X', style: TextStyle(color: AppColors.textMuted, fontSize: 16, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 20),
        _staffRow(_lang.get('mb_terima'), staff['terima'] ?? '-', AppColors.blue),
        const SizedBox(height: 12),
        _staffRow(_lang.get('mb_repair'), staff['repair'] ?? '-', AppColors.green),
        const SizedBox(height: 12),
        _staffRow(_lang.get('mb_serah'), staff['serah'] ?? '-', const Color(0xFFF472B6)),
      ])),
    ));
  }

  Widget _staffRow(String label, String value, Color color) {
    return Row(children: [
      SizedBox(width: 65, child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700))),
      const Text(': ', style: TextStyle(color: AppColors.textMuted)),
      Text(value.toUpperCase(), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(children: [
      // Header with score
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.borderMed),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const FaIcon(FontAwesomeIcons.star, size: 16, color: AppColors.yellow),
            const SizedBox(width: 8),
            Text(_lang.get('mb_prestasi'), style: const TextStyle(color: AppColors.yellow, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ]),
          const SizedBox(height: 16),
          // Score
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_avgRating.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 48, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('/ 5.0', style: TextStyle(color: AppColors.textSub, fontSize: 18)),
              Text('${_feedbacks.length} Maklum Balas', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ]),
          const SizedBox(height: 16),
          // Filter dropdown + search button
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.yellow.withValues(alpha: 0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _dropdownValue,
                  dropdownColor: Colors.white,
                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.yellow),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800),
                  items: [
                    DropdownMenuItem(value: 'Semua_Terbaru', child: Text('${_lang.get('semua')} ${_lang.get('terbaru')}')),
                    DropdownMenuItem(value: 'Semua_Terdahulu', child: Text('${_lang.get('semua')} ${_lang.get('mb_terdahulu')}')),
                    DropdownMenuItem(value: '5', child: Text(_lang.get('mb_5_bintang'))),
                    DropdownMenuItem(value: '4', child: Text(_lang.get('mb_4_bintang'))),
                    DropdownMenuItem(value: '3', child: Text(_lang.get('mb_3_bintang'))),
                    DropdownMenuItem(value: '2', child: Text(_lang.get('mb_2_bintang'))),
                    DropdownMenuItem(value: '1', child: Text(_lang.get('mb_1_bintang'))),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _dropdownValue = val;
                      if (val == 'Semua_Terbaru') { _filterStar = 'Semua'; _sortOrder = 'Terbaru'; }
                      else if (val == 'Semua_Terdahulu') { _filterStar = 'Semua'; _sortOrder = 'Terdahulu'; }
                      else { _filterStar = val; }
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _showSearch = !_showSearch),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _showSearch ? AppColors.yellow : AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.yellow),
                ),
                child: Icon(Icons.search, size: 20, color: _showSearch ? Colors.black : AppColors.yellow),
              ),
            ),
          ]),
        ]),
      ),
      // Search bar (toggle)
      if (_showSearch)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _searchCtrl, onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: _lang.get('mb_cari_hint'), hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
              prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textMuted),
              filled: true, fillColor: AppColors.bgDeep, isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
      // Count
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Align(alignment: Alignment.centerLeft, child: Text(
          '${_lang.get('mb_menunjukkan')} ${filtered.length} ${_lang.get('mb_rekod')}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        )),
      ),
      // List
      Expanded(
        child: _feedbacks.isEmpty
          ? Center(child: Text(_lang.get('mb_tiada_maklum'), style: const TextStyle(color: AppColors.textMuted)))
          : filtered.isEmpty
            ? Center(child: Text(_lang.get('tiada_padanan'), style: const TextStyle(color: AppColors.textMuted)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final f = filtered[i];
                  final rating = ((f['rating'] ?? 0) as num).toInt();
                  final siri = f['siri'] ?? '-';
                  final tarikh = f['timestamp'] is int ? DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(f['timestamp'])) : '-';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderMed),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Top row: siri + stars
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('#$siri', style: const TextStyle(color: AppColors.yellow, fontSize: 12, fontWeight: FontWeight.w900)),
                        Row(children: List.generate(5, (j) => Icon(
                          j < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: AppColors.yellow, size: 16,
                        ))),
                      ]),
                      const SizedBox(height: 8),
                      // Nama + Tel
                      Text((f['nama'] ?? 'Pelanggan').toString().toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800)),
                      Text(f['tel'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                      // Komen
                      if (f['komen'] != null && f['komen'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
                          child: Text('"${f['komen']}"', style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontStyle: FontStyle.italic)),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Date + Staff button
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(tarikh, style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                        GestureDetector(
                          onTap: () async {
                            final staff = await _lookupStaff(siri.toString());
                            if (mounted) _showStaffModal(staff);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.yellow.withValues(alpha: 0.15),
                              border: Border.all(color: AppColors.yellow),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const FaIcon(FontAwesomeIcons.users, size: 10, color: AppColors.yellow),
                              const SizedBox(width: 6),
                              Text(_lang.get('mb_lihat_staf'), style: const TextStyle(color: AppColors.yellow, fontSize: 10, fontWeight: FontWeight.w900)),
                            ]),
                          ),
                        ),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

}
