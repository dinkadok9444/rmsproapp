import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../services/supabase_client.dart';
import '../../services/repair_service.dart';

class LostScreen extends StatefulWidget {
  const LostScreen({super.key});
  @override
  State<LostScreen> createState() => _LostScreenState();
}

class _LostScreenState extends State<LostScreen> {
  final _lang = AppLanguage();
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  final _searchCtrl = TextEditingController();
  String _ownerID = 'admin', _shopID = 'MAIN';
  String? _tenantId;
  String? _branchId;
  String _sortOrder = 'ZA';
  String _filterJenis = 'SEMUA';
  List<Map<String, dynamic>> _losses = [];
  StreamSubscription? _sub;

  List<String> get _jenisKerugian => [_lang.get('ls_pecah_masa'), _lang.get('ls_cn_tak_approve'), _lang.get('ls_rosak_defect'), _lang.get('ls_hilang'), _lang.get('ls_lain_lain')];

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _sub?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    await _repairService.init();
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    if (_branchId == null) return;
    _sub = _sb
        .from('losses')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .order('created_at', ascending: false)
        .listen((rows) {
      final list = rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        m['key'] = r['id'];
        m['jenis'] = r['item_type'] ?? '';
        m['jumlah'] = r['estimated_value'] ?? 0;
        m['keterangan'] = r['reason'] ?? '';
        // Extract siri from notes (format "siri:XXX")
        final notes = (r['notes'] ?? '').toString();
        m['siri'] = notes.startsWith('siri:') ? notes.substring(5) : '';
        final c = r['created_at']?.toString();
        m['timestamp'] = c == null ? 0 : (DateTime.tryParse(c)?.millisecondsSinceEpoch ?? 0);
        return m;
      }).toList();
      if (mounted) setState(() => _losses = list);
    });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_losses);
    // Filter jenis
    if (_filterJenis != 'SEMUA') {
      list = list.where((d) => (d['jenis'] ?? '').toString().toUpperCase() == _filterJenis.toUpperCase()).toList();
    }
    // Search
    final q = _searchCtrl.text.toUpperCase().trim();
    if (q.isNotEmpty) {
      list = list.where((d) =>
        (d['keterangan'] ?? '').toString().toUpperCase().contains(q) ||
        (d['jenis'] ?? '').toString().toUpperCase().contains(q) ||
        (d['siri'] ?? '').toString().toUpperCase().contains(q)
      ).toList();
    }
    if (_sortOrder == 'AZ') list.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));
    else list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    return list;
  }

  double get _totalKerugian => _filtered.fold(0.0, (sum, d) => sum + ((d['jumlah'] ?? 0) as num).toDouble());

  String _fmt(dynamic ts) => ts is int ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '-';

  Color _jenisColor(String jenis) {
    final j = jenis.toUpperCase();
    if (j.contains('PECAH')) return AppColors.red;
    if (j.contains('CN')) return AppColors.yellow;
    if (j.contains('ROSAK') || j.contains('DEFECT')) return const Color(0xFFF97316);
    if (j.contains('HILANG')) return const Color(0xFF8B5CF6);
    return AppColors.textMuted;
  }

  IconData _jenisIcon(String jenis) {
    final j = jenis.toUpperCase();
    if (j.contains('PECAH')) return FontAwesomeIcons.heartCrack;
    if (j.contains('CN')) return FontAwesomeIcons.fileCircleXmark;
    if (j.contains('ROSAK') || j.contains('DEFECT')) return FontAwesomeIcons.screwdriverWrench;
    if (j.contains('HILANG')) return FontAwesomeIcons.circleQuestion;
    return FontAwesomeIcons.triangleExclamation;
  }

  void _showAddForm({Map<String, dynamic>? existing}) {
    final keteranganCtrl = TextEditingController(text: existing?['keterangan'] ?? '');
    final jumlahCtrl = TextEditingController(text: existing != null ? ((existing['jumlah'] ?? 0) as num).toStringAsFixed(2) : '');
    final siriCtrl = TextEditingController(text: existing?['siri'] ?? '');
    String jenis = existing?['jenis'] ?? _jenisKerugian[0];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: AppColors.red, width: 2)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const FaIcon(FontAwesomeIcons.triangleExclamation, size: 14, color: AppColors.red),
                  const SizedBox(width: 8),
                  Text(existing != null ? 'KEMASKINI KERUGIAN' : _lang.get('ls_rekod_kerugian'), style: const TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
              const SizedBox(height: 20),

              // Jenis Kerugian
              Text(_lang.get('ls_jenis_kerugian'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
                child: DropdownButton<String>(value: jenis, isExpanded: true, dropdownColor: Colors.white,
                  underline: const SizedBox(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                  items: _jenisKerugian.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setS(() => jenis = v!)),
              ),
              const SizedBox(height: 14),

              // No Siri (optional)
              Text(_lang.get('ls_no_siri'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              _input(siriCtrl, _lang.get('ls_cth_siri'), caps: true),
              const SizedBox(height: 14),

              // Jumlah
              Text(_lang.get('ls_jumlah_rm'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              _input(jumlahCtrl, '0.00', keyboard: TextInputType.number),
              const SizedBox(height: 14),

              // Keterangan
              Text(_lang.get('ls_keterangan'), style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              TextField(controller: keteranganCtrl, maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(hintText: _lang.get('ls_cth_keterangan'),
                  hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  filled: true, fillColor: AppColors.bg, isDense: true, contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.red))),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () async {
                  if (jumlahCtrl.text.isEmpty || keteranganCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('ls_isi_jumlah')), backgroundColor: AppColors.red));
                    return;
                  }
                  if (_tenantId == null) return;
                  final siriText = siriCtrl.text.trim().toUpperCase();
                  final data = {
                    'tenant_id': _tenantId,
                    'branch_id': _branchId,
                    'item_type': jenis,
                    'estimated_value': double.tryParse(jumlahCtrl.text) ?? 0,
                    'reason': keteranganCtrl.text.trim(),
                    'notes': siriText.isEmpty ? null : 'siri:$siriText',
                  };
                  if (existing != null && existing['key'] != null) {
                    await _sb.from('losses').update(data).eq('id', existing['key']);
                  } else {
                    await _sb.from('losses').insert(data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(existing != null ? 'Rekod dikemaskini!' : 'Kerugian direkodkan!'),
                    backgroundColor: AppColors.green,
                  ));
                },
                icon: FaIcon(existing != null ? FontAwesomeIcons.penToSquare : FontAwesomeIcons.floppyDisk, size: 12),
                label: Text(existing != null ? 'KEMASKINI' : _lang.get('simpan')),
              )),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _deleteRecord(String docId) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(_lang.get('ls_padam_rekod'), style: const TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
      content: Text(_lang.get('ls_padam_kekal'), style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_lang.get('batal'), style: const TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(_lang.get('padam')),
        ),
      ],
    ));
    if (confirmed == true) {
      await _sb.from('losses').delete().eq('id', docId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('ls_rekod_dipadam')), backgroundColor: AppColors.green));
    }
  }

  Widget _input(TextEditingController ctrl, String hint, {TextInputType keyboard = TextInputType.text, bool caps = false}) {
    return TextField(controller: ctrl, keyboardType: keyboard, textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        filled: true, fillColor: AppColors.bg, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.red))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.red, width: 2))),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const FaIcon(FontAwesomeIcons.triangleExclamation, size: 14, color: AppColors.red),
              const SizedBox(width: 8),
              Text(_lang.get('ls_rekod_kerugian'), style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(
              onTap: () => _showAddForm(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white), const SizedBox(width: 6),
                  Text(_lang.get('ls_rekod_baru'), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Summary box
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFEE2E2), Color(0xFFFEF2F2)]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_lang.get('ls_jumlah_kerugian'), style: const TextStyle(color: AppColors.red, fontSize: 9, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('${filtered.length} rekod', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ]),
              Text('RM ${_totalKerugian.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.red, fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 10),

          // Search + Filter
          Row(children: [
            Expanded(child: TextField(controller: _searchCtrl, onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(hintText: _lang.get('ls_cari_hint'), hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textMuted), filled: true, fillColor: AppColors.bgDeep, isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
            )),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(10)),
              child: DropdownButton<String>(value: _sortOrder, underline: const SizedBox(), dropdownColor: Colors.white,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                items: [
                  DropdownMenuItem(value: 'ZA', child: Text(_lang.get('terbaru'))),
                  DropdownMenuItem(value: 'AZ', child: Text(_lang.get('terlama'))),
                ],
                onChanged: (v) => setState(() => _sortOrder = v!)),
            ),
          ]),
          const SizedBox(height: 8),

          // Filter jenis chips
          SizedBox(height: 30, child: ListView(scrollDirection: Axis.horizontal, children: [
            _filterChip('SEMUA'),
            ..._jenisKerugian.map((j) => _filterChip(j)),
          ])),
        ]),
      ),

      // List
      Expanded(
        child: _losses.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const FaIcon(FontAwesomeIcons.shieldHeart, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              Text(_lang.get('ls_tiada_rekod'), style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_lang.get('ls_semoga_selamat'), style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
            ]))
          : filtered.isEmpty
            ? Center(child: Text(_lang.get('tiada_padanan'), style: const TextStyle(color: AppColors.textMuted)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final jenis = (r['jenis'] ?? 'Lain-lain').toString();
                  final col = _jenisColor(jenis);
                  final jumlah = ((r['jumlah'] ?? 0) as num).toStringAsFixed(2);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderMed),
                      boxShadow: [BoxShadow(color: AppColors.bg, blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Header: jenis + badge
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: col.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: FaIcon(_jenisIcon(jenis), size: 10, color: col),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(jenis, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w900))),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: col.withValues(alpha: 0.1), border: Border.all(color: col.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                          child: Text('- RM $jumlah', style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      // Keterangan
                      Text(r['keterangan'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.4)),
                      const SizedBox(height: 6),
                      // Footer: siri + date + actions
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if ((r['siri'] ?? '').toString().isNotEmpty)
                            Text('#${r['siri']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
                          Text(_fmt(r['timestamp']), style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                        ]),
                        Row(children: [
                          GestureDetector(
                            onTap: () => _showAddForm(existing: r),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderMed)),
                              child: const FaIcon(FontAwesomeIcons.penToSquare, size: 10, color: AppColors.textMuted),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _deleteRecord(r['key']),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
                              child: const FaIcon(FontAwesomeIcons.trashCan, size: 10, color: AppColors.red),
                            ),
                          ),
                        ]),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _filterChip(String label) {
    final isActive = _filterJenis == label;
    return GestureDetector(
      onTap: () => setState(() => _filterJenis = label),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.red : AppColors.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppColors.red : AppColors.borderMed),
        ),
        child: Text(label, style: TextStyle(color: isActive ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
