import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';

class SvExpenseTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvExpenseTab({super.key, required this.ownerID, required this.shopID});
  @override
  State<SvExpenseTab> createState() => _SvExpenseTabState();
}

class _SvExpenseTabState extends State<SvExpenseTab> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  final _searchCtrl = TextEditingController();
  String _sortOrder = 'ZA';
  String _filterKategori = 'SEMUA';
  String _filterTime = 'THIS_MONTH';
  DateTime? _customStart, _customEnd;
  List<Map<String, dynamic>> _expenses = [];
  StreamSubscription? _sub;

  final _kategoriList = [
    'Gaji Staff',
    'Bil TNB',
    'Bil Air',
    'Sewa',
    'Internet',
    'Alat Ganti',
    'Pengangkutan',
    'Makan/Minum',
    'Lain-lain',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    if (_branchId == null) return;
    _sub = _sb
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>((r) => {
        'key': r['id'],
        'shopID': widget.shopID,
        'kategori': r['category'] ?? '',
        'perkara': r['description'] ?? '',
        'jumlah': r['amount'] ?? 0,
        'catatan': r['notes'] ?? '',
        'staff': r['paid_by'] ?? '',
        'timestamp': _tsFromIso(r['created_at']),
      }).toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _expenses = list);
    });
  }

  int _tsFromIso(dynamic v) {
    if (v is int) return v;
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  int _dapatkanMasaSah(dynamic ts) {
    if (ts == null) return 0;
    if (ts is int) {
      if (ts > 0 && ts < 10000000000) return ts * 1000;
      return ts;
    }
    if (ts is double) return ts.toInt();
    if (ts is String) {
      final p = DateTime.tryParse(ts);
      if (p != null) return p.millisecondsSinceEpoch;
    }
    return 0;
  }

  bool _isInRange(int ts) {
    if (ts == 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (_filterTime) {
      case 'TODAY':
        return date.isAfter(todayStart);
      case 'THIS_WEEK':
        return date.isAfter(todayStart.subtract(Duration(days: now.weekday - 1)));
      case 'THIS_MONTH':
        return date.isAfter(DateTime(now.year, now.month, 1));
      case 'CUSTOM':
        if (_customStart != null && _customEnd != null) {
          return date.isAfter(_customStart!) && date.isBefore(_customEnd!.add(const Duration(days: 1)));
        }
        return true;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_expenses);
    // Filter by time
    list = list.where((d) => _isInRange(_dapatkanMasaSah(d['timestamp']))).toList();
    // Filter kategori
    if (_filterKategori != 'SEMUA') {
      list = list.where((d) => (d['kategori'] ?? d['perkara'] ?? '').toString().toUpperCase() == _filterKategori.toUpperCase()).toList();
    }
    // Search
    final q = _searchCtrl.text.toUpperCase().trim();
    if (q.isNotEmpty) {
      list = list.where((d) =>
        (d['perkara'] ?? '').toString().toUpperCase().contains(q) ||
        (d['kategori'] ?? '').toString().toUpperCase().contains(q) ||
        (d['catatan'] ?? '').toString().toUpperCase().contains(q) ||
        (d['staff'] ?? '').toString().toUpperCase().contains(q)
      ).toList();
    }
    if (_sortOrder == 'AZ') {
      list.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));
    } else {
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    }
    return list;
  }

  double get _totalExpense => _filtered.fold(0.0, (sum, d) => sum + ((d['jumlah'] ?? 0) as num).toDouble());

  String _fmt(dynamic ts) {
    final ms = _dapatkanMasaSah(ts);
    return ms > 0 ? DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms)) : '-';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFF59E0B))),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _filterTime = 'CUSTOM';
      });
    }
  }

  Color _kategoriColor(String kategori) {
    final k = kategori.toUpperCase();
    if (k.contains('GAJI')) return const Color(0xFF3B82F6);
    if (k.contains('TNB')) return const Color(0xFFF59E0B);
    if (k.contains('AIR')) return const Color(0xFF06B6D4);
    if (k.contains('SEWA')) return const Color(0xFF8B5CF6);
    if (k.contains('INTERNET')) return const Color(0xFF6366F1);
    if (k.contains('ALAT')) return const Color(0xFFEF4444);
    if (k.contains('PENGANGKUTAN')) return const Color(0xFF10B981);
    if (k.contains('MAKAN')) return const Color(0xFFF97316);
    return AppColors.textMuted;
  }

  IconData _kategoriIcon(String kategori) {
    final k = kategori.toUpperCase();
    if (k.contains('GAJI')) return FontAwesomeIcons.userGroup;
    if (k.contains('TNB')) return FontAwesomeIcons.bolt;
    if (k.contains('AIR')) return FontAwesomeIcons.droplet;
    if (k.contains('SEWA')) return FontAwesomeIcons.houseChimney;
    if (k.contains('INTERNET')) return FontAwesomeIcons.wifi;
    if (k.contains('ALAT')) return FontAwesomeIcons.screwdriverWrench;
    if (k.contains('PENGANGKUTAN')) return FontAwesomeIcons.truck;
    if (k.contains('MAKAN')) return FontAwesomeIcons.utensils;
    return FontAwesomeIcons.receipt;
  }

  void _showAddForm({Map<String, dynamic>? existing}) {
    final perkaraCtrl = TextEditingController(text: existing?['perkara'] ?? '');
    final jumlahCtrl = TextEditingController(text: existing != null ? ((existing['jumlah'] ?? 0) as num).toStringAsFixed(2) : '');
    final catatanCtrl = TextEditingController(text: existing?['catatan'] ?? '');
    String kategori = existing?['kategori'] ?? _kategoriList[0];
    // Ensure kategori is in list
    if (!_kategoriList.contains(kategori)) kategori = 'Lain-lain';

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0xFFF59E0B), width: 2)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const FaIcon(FontAwesomeIcons.receipt, size: 14, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Text(existing != null ? 'KEMASKINI PERBELANJAAN' : 'REKOD PERBELANJAAN BARU',
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 14, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx),
                  child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: Color(0xFFF59E0B))),
              ]),
              const SizedBox(height: 20),

              // Kategori
              const Text('Kategori', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
                child: DropdownButton<String>(value: kategori, isExpanded: true, dropdownColor: Colors.white,
                  underline: const SizedBox(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                  items: _kategoriList.map((e) => DropdownMenuItem(value: e, child: Row(children: [
                    FaIcon(_kategoriIcon(e), size: 12, color: _kategoriColor(e)),
                    const SizedBox(width: 8),
                    Text(e),
                  ]))).toList(),
                  onChanged: (v) => setS(() => kategori = v!)),
              ),
              const SizedBox(height: 14),

              // Perkara
              const Text('Perkara / Keterangan', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              _input(perkaraCtrl, 'Cth: Gaji bulan Mac, Bil TNB Mac...'),
              const SizedBox(height: 14),

              // Jumlah
              const Text('Jumlah (RM)', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              _input(jumlahCtrl, '0.00', keyboard: TextInputType.number),
              const SizedBox(height: 14),

              // Catatan
              const Text('Catatan (Opsional)', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              TextField(controller: catatanCtrl, maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(hintText: 'Nota tambahan...',
                  hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  filled: true, fillColor: AppColors.bg, isDense: true, contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF59E0B)))),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  if (jumlahCtrl.text.isEmpty || perkaraCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi perkara & jumlah'), backgroundColor: AppColors.red));
                    return;
                  }
                  if (_tenantId == null || _branchId == null) return;
                  final data = {
                    'tenant_id': _tenantId,
                    'branch_id': _branchId,
                    'category': kategori,
                    'description': perkaraCtrl.text.trim(),
                    'amount': double.tryParse(jumlahCtrl.text) ?? 0,
                    'notes': catatanCtrl.text.trim(),
                    'paid_by': existing?['staff'] ?? '',
                  };
                  if (existing != null && existing['key'] != null) {
                    await _sb.from('expenses').update(data).eq('id', existing['key']);
                  } else {
                    await _sb.from('expenses').insert(data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(existing != null ? 'Perbelanjaan dikemaskini!' : 'Perbelanjaan direkodkan!'),
                    backgroundColor: AppColors.green,
                  ));
                },
                icon: FaIcon(existing != null ? FontAwesomeIcons.penToSquare : FontAwesomeIcons.floppyDisk, size: 12),
                label: Text(existing != null ? 'KEMASKINI' : 'SIMPAN'),
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
      title: const Text('Padam Rekod?', style: TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
      content: const Text('Rekod perbelanjaan ini akan dipadam secara kekal.', style: TextStyle(color: AppColors.textSub, fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('PADAM'),
        ),
      ],
    ));
    if (confirmed == true) {
      await _sb.from('expenses').delete().eq('id', docId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rekod dipadam'), backgroundColor: AppColors.green));
    }
  }

  Widget _input(TextEditingController ctrl, String hint, {TextInputType keyboard = TextInputType.text}) {
    return TextField(controller: ctrl, keyboardType: keyboard,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        filled: true, fillColor: AppColors.bg, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderMed)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF59E0B)))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: Color(0xFFF59E0B), width: 2))),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Row(children: [
              FaIcon(FontAwesomeIcons.receipt, size: 14, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('PERBELANJAAN', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(
              onTap: () => _showAddForm(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white), SizedBox(width: 6),
                  Text('REKOD BARU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Summary box
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFEF3C7), Color(0xFFFFFBEB)]),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('JUMLAH PERBELANJAAN', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('${filtered.length} rekod', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ]),
              Text('RM ${_totalExpense.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 10),

          // Time filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in [
                {'key': 'TODAY', 'label': 'Hari Ini'},
                {'key': 'THIS_WEEK', 'label': 'Minggu Ini'},
                {'key': 'THIS_MONTH', 'label': 'Bulan Ini'},
                {'key': 'ALL', 'label': 'Semua'},
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterTime = f['key']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _filterTime == f['key'] ? const Color(0xFFF59E0B) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _filterTime == f['key'] ? const Color(0xFFF59E0B) : AppColors.borderMed),
                      ),
                      child: Text(f['label']!, style: TextStyle(
                        color: _filterTime == f['key'] ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filterTime == 'CUSTOM' ? const Color(0xFFF59E0B) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filterTime == 'CUSTOM' ? const Color(0xFFF59E0B) : AppColors.borderMed),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(FontAwesomeIcons.calendar, size: 10,
                      color: _filterTime == 'CUSTOM' ? Colors.white : AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text('Pilih Tarikh', style: TextStyle(
                      color: _filterTime == 'CUSTOM' ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // Search + Sort
          Row(children: [
            Expanded(child: TextField(controller: _searchCtrl, onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(hintText: 'Cari perkara / kategori...', hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
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
                items: const [
                  DropdownMenuItem(value: 'ZA', child: Text('Terbaru')),
                  DropdownMenuItem(value: 'AZ', child: Text('Terlama')),
                ],
                onChanged: (v) => setState(() => _sortOrder = v!)),
            ),
          ]),
          const SizedBox(height: 8),

          // Filter kategori chips
          SizedBox(height: 30, child: ListView(scrollDirection: Axis.horizontal, children: [
            _filterChip('SEMUA'),
            ..._kategoriList.map((j) => _filterChip(j)),
          ])),
        ]),
      ),

      // List
      Expanded(
        child: _expenses.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const FaIcon(FontAwesomeIcons.wallet, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              const Text('Tiada rekod perbelanjaan', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Tekan + untuk rekod perbelanjaan baru', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
            ]))
          : filtered.isEmpty
            ? const Center(child: Text('Tiada padanan', style: TextStyle(color: AppColors.textMuted)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final kategori = (r['kategori'] ?? r['perkara'] ?? 'Lain-lain').toString();
                  final col = _kategoriColor(kategori);
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
                      // Header: kategori + amount
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: col.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: FaIcon(_kategoriIcon(kategori), size: 10, color: col),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(kategori, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w900))),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: col.withValues(alpha: 0.1), border: Border.all(color: col.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                          child: Text('- RM $jumlah', style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      // Perkara
                      Text(r['perkara'] ?? '-', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.4)),
                      if ((r['catatan'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(r['catatan'], style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 6),
                      // Footer: staff + date + actions
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if ((r['staff'] ?? '').toString().isNotEmpty)
                            Text(r['staff'], style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
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
    final isActive = _filterKategori == label;
    return GestureDetector(
      onTap: () => setState(() => _filterKategori = label),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFF59E0B) : AppColors.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? const Color(0xFFF59E0B) : AppColors.borderMed),
        ),
        child: Text(label, style: TextStyle(color: isActive ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
