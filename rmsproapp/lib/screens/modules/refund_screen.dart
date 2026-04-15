import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../services/supabase_client.dart';
import '../../services/repair_service.dart';

class RefundScreen extends StatefulWidget {
  const RefundScreen({super.key});
  @override
  State<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends State<RefundScreen> {
  final _lang = AppLanguage();
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  final _searchCtrl = TextEditingController();
  String _ownerID = 'admin', _shopID = 'MAIN';
  String? _tenantId;
  String? _branchId;
  String _sortOrder = 'ZA'; // ZA=terbaru
  String _adminPass = '';
  List<Map<String, dynamic>> _refunds = [];
  List<Map<String, dynamic>> _repairs = [];
  StreamSubscription? _sub;
  StreamSubscription? _repairSub;

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _sub?.cancel(); _repairSub?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    await _repairService.init();
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    if (_tenantId == null || _branchId == null) return;
    // Load admin pass from tenants.config.svPass
    try {
      final row = await _sb.from('tenants').select('config').eq('id', _tenantId!).maybeSingle();
      final cfg = row?['config'];
      if (cfg is Map) _adminPass = (cfg['svPass'] ?? '').toString();
    } catch (_) {}
    _sub = _sb
        .from('refunds')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .order('created_at', ascending: false)
        .listen((rows) {
      final list = rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        m['key'] = r['id'];
        m['siri'] = r['siri'] ?? '';
        m['namaCust'] = r['nama'] ?? '';
        m['reason'] = r['reason'] ?? '';
        m['amount'] = r['refund_amount'] ?? 0;
        m['status'] = r['refund_status'] ?? 'PENDING';
        final c = r['created_at']?.toString();
        m['timestamp'] = c == null ? 0 : (DateTime.tryParse(c)?.millisecondsSinceEpoch ?? 0);
        return m;
      }).toList();
      if (mounted) setState(() => _refunds = list);
    });
    _repairSub = _sb
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      _repairs = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_refunds);
    final q = _searchCtrl.text.toUpperCase().trim();
    if (q.isNotEmpty) {
      list = list.where((d) =>
        (d['siri'] ?? '').toString().toUpperCase().contains(q) ||
        (d['reason'] ?? '').toString().toUpperCase().contains(q) ||
        (d['namaCust'] ?? '').toString().toUpperCase().contains(q)
      ).toList();
    }
    if (_sortOrder == 'AZ') list.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));
    else list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    return list;
  }

  String _fmt(dynamic ts) => ts is int ? DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '-';

  Color _statusColor(String s) {
    final su = s.toUpperCase();
    if (su == 'APPROVED' || su == 'COMPLETED') return AppColors.green;
    if (su == 'REJECTED') return AppColors.red;
    return AppColors.yellow;
  }

  IconData _statusIcon(String s) {
    final su = s.toUpperCase();
    if (su == 'APPROVED' || su == 'COMPLETED') return FontAwesomeIcons.circleCheck;
    if (su == 'REJECTED') return FontAwesomeIcons.circleXmark;
    return FontAwesomeIcons.clock;
  }

  void _showRefundForm() {
    final siriCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final accNameCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final accNoCtrl = TextEditingController();
    String method = 'TRANSFER', speed = 'SEGERA';
    Map<String, dynamic>? foundRepair;

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
                  FaIcon(FontAwesomeIcons.fileInvoiceDollar, size: 14, color: AppColors.red),
                  SizedBox(width: 8),
                  Text(_lang.get('rd_mohon_refund_hq'), style: TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
                ]),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
              ]),
              const SizedBox(height: 20),
              // Search siri
              Text(_lang.get('rd_cari_siri'), style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _input(siriCtrl, 'Cth: RMS2024...', caps: true)),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  onPressed: () {
                    final val = siriCtrl.text.trim().toUpperCase();
                    if (val.isEmpty) return;
                    final found = _repairs.firstWhere((r) => r['siri'] == val, orElse: () => {});
                    if (found.isNotEmpty) {
                      setS(() => foundRepair = found);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Siri [$val] ${_lang.get('rd_siri_tidak_dijumpai')}'), backgroundColor: AppColors.red));
                    }
                  },
                  child: const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 12),
                ),
              ]),
              if (foundRepair != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.borderMed)),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _infoField('Nama Pelanggan', foundRepair!['nama'] ?? '-')),
                      const SizedBox(width: 10),
                      Expanded(child: _infoField('Harga Asal (RM)', (foundRepair!['total'] ?? foundRepair!['harga'] ?? 0).toString())),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _infoField('Model', foundRepair!['model'] ?? '-')),
                      const SizedBox(width: 10),
                      Expanded(child: _infoField('Kerosakan', foundRepair!['kerosakan'] ?? '-')),
                    ]),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('rd_amaun_refund'), style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  _input(amountCtrl, '0.00', keyboard: TextInputType.number),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('rd_kaedah_bayaran'), style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  _dropdown(['TRANSFER', 'CASH'], method, (v) => setS(() => method = v!)),
                ])),
              ]),
              const SizedBox(height: 12),
              Text(_lang.get('rd_sebab_refund'), style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              _input(reasonCtrl, _lang.get('rd_cth_sebab')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('rd_kelajuan'), style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  _dropdown(['SEGERA', 'TERTUNDA'], speed, (v) => setS(() => speed = v!)),
                ])),
              ]),
              const SizedBox(height: 12),
              // Bank details
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.borderMed)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lang.get('rd_maklumat_bayaran'), style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  _labelInput(_lang.get('rd_nama_pemilik'), accNameCtrl),
                  Row(children: [
                    Expanded(child: _labelInput(_lang.get('rd_nama_bank'), bankNameCtrl, hint: _lang.get('rd_cth_bank'))),
                    const SizedBox(width: 10),
                    Expanded(child: _labelInput(_lang.get('rd_no_akaun'), accNoCtrl)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              // Submit
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () async {
                  if (foundRepair == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('rd_cari_dahulu')), backgroundColor: AppColors.red)); return; }
                  if (amountCtrl.text.isEmpty || reasonCtrl.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('rd_isi_amaun')), backgroundColor: AppColors.red)); return; }
                  if (_tenantId == null) return;
                  await _sb.from('refunds').insert({
                    'tenant_id': _tenantId,
                    'branch_id': _branchId,
                    'job_id': foundRepair!['id'],
                    'siri': siriCtrl.text.trim().toUpperCase(),
                    'nama': foundRepair!['nama'] ?? '-',
                    'refund_amount': double.tryParse(amountCtrl.text) ?? 0,
                    'refund_status': 'PENDING',
                    'reason': reasonCtrl.text.trim(),
                    'processed_by': jsonEncode({
                      'method': method,
                      'speed': speed,
                      'accName': accNameCtrl.text.trim(),
                      'bankName': bankNameCtrl.text.trim(),
                      'accNo': accNoCtrl.text.trim(),
                      'model': foundRepair!['model'] ?? '-',
                      'kerosakan': foundRepair!['kerosakan'] ?? '-',
                      'hargaAsal': foundRepair!['total'] ?? foundRepair!['harga'] ?? 0,
                    }),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('rd_permohonan_dihantar')), backgroundColor: AppColors.green));
                },
                icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 12),
                label: Text(_lang.get('rd_hantar_permohonan')),
              )),
              const SizedBox(height: 10),
              Text(_lang.get('rd_nota_bankin'),
                style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _approveRefund(String docId) async {
    if (_adminPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('rd_sila_set_password')), backgroundColor: AppColors.red));
      return;
    }
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(_lang.get('rd_pengesahan_admin'), style: TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
      content: TextField(controller: passCtrl, obscureText: true, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, letterSpacing: 4),
        decoration: const InputDecoration(hintText: '******', hintStyle: TextStyle(color: AppColors.textDim)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_lang.get('batal'), style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
          onPressed: () {
            if (passCtrl.text.trim() == _adminPass) Navigator.pop(ctx, true);
            else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('rd_kata_laluan_salah')), backgroundColor: AppColors.red));
          },
          child: Text(_lang.get('rd_approve')),
        ),
      ],
    ));
    if (confirmed == true) {
      await _sb.from('refunds').update({
        'refund_status': 'COMPLETED',
        'processed_at': DateTime.now().toIso8601String(),
      }).eq('id', docId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lang.get('rd_refund_diluluskan')), backgroundColor: AppColors.green));
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

  Widget _labelInput(String label, TextEditingController ctrl, {String hint = ''}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      _input(ctrl, hint),
    ]));
  }

  Widget _dropdown(List<String> items, String value, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderMed)),
      child: DropdownButton<String>(value: value, isExpanded: true, dropdownColor: Colors.white,
        underline: const SizedBox(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged),
    );
  }

  Widget _infoField(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
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
              FaIcon(FontAwesomeIcons.clockRotateLeft, size: 14, color: AppColors.red),
              SizedBox(width: 8),
              Text(_lang.get('rd_sejarah_status'), style: TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
            GestureDetector(
              onTap: _showRefundForm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white), SizedBox(width: 6),
                  Text(_lang.get('rd_mohon_refund'), style: TextStyle(color: AppColors.textPrimary, fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _searchCtrl, onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(hintText: _lang.get('rd_cari_hint'), hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
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
        ]),
      ),
      // List
      Expanded(
        child: _refunds.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.receipt, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              Text(_lang.get('rd_tiada_permohonan'), style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ]))
          : filtered.isEmpty
            ? Center(child: Text(_lang.get('tiada_padanan'), style: TextStyle(color: AppColors.textMuted)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final status = (r['status'] ?? 'PENDING').toString().toUpperCase();
                  final col = _statusColor(status);
                  final amtRefund = ((r['amount'] ?? 0) as num).toStringAsFixed(2);
                  final hrgAsal = ((r['hargaAsal'] ?? 0) as num).toStringAsFixed(2);
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
                      // Header: siri + status
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('#${r['siri'] ?? '-'}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: col.withValues(alpha: 0.15), border: Border.all(color: col), borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            FaIcon(_statusIcon(status), size: 9, color: col),
                            const SizedBox(width: 4),
                            Text(status, style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.w900)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      // Customer info
                      Text(r['namaCust'] ?? '-', style: const TextStyle(color: AppColors.yellow, fontSize: 12, fontWeight: FontWeight.w900)),
                      Text('${r['model'] ?? '-'}  •  ${r['kerosakan'] ?? '-'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      const SizedBox(height: 8),
                      // Amounts
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Asal: RM $hrgAsal', style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
                          Text(_fmt(r['timestamp']), style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                        ]),
                        Text('RM $amtRefund', style: const TextStyle(color: AppColors.red, fontSize: 18, fontWeight: FontWeight.w900)),
                      ]),
                      // Approve button
                      if (status == 'PENDING') ...[
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                          onPressed: () => _approveRefund(r['key']),
                          icon: const FaIcon(FontAwesomeIcons.check, size: 10),
                          label: Text(_lang.get('rd_approve'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                        )),
                      ],
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
