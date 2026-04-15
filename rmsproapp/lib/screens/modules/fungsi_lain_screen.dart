import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';

class FungsiLainScreen extends StatefulWidget {
  const FungsiLainScreen({super.key});
  @override
  State<FungsiLainScreen> createState() => _FungsiLainScreenState();
}

class _FungsiLainScreenState extends State<FungsiLainScreen> {
  final _lang = AppLanguage();
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  String _senderRole = 'admin', _senderName = '';
  String _announcement = '';
  List<Map<String, dynamic>> _posRecords = [];
  List<Map<String, dynamic>> _myFeedbacks = [];
  final TextEditingController _feedbackCtrl = TextEditingController();
  bool _sending = false;
  StreamSubscription? _posSub, _feedbackSub;
  Timer? _announceTimer;

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() {
    _announceTimer?.cancel(); _posSub?.cancel(); _feedbackSub?.cancel();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  int _tsFromIso(dynamic v) {
    if (v is int) return v;
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  Future<void> _loadAnnouncement() async {
    try {
      final rows = await _sb
          .from('admin_announcements')
          .select('body, title')
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final msg = (rows.first['body'] ?? rows.first['title'] ?? '').toString().trim();
        if (mounted) setState(() => _announcement = msg);
      } else {
        if (mounted) setState(() => _announcement = '');
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;

    final prefs = await SharedPreferences.getInstance();
    final staffRole = prefs.getString('rms_staff_role') ?? '';
    final userRole = prefs.getString('rms_user_role') ?? '';
    _senderRole = staffRole.isNotEmpty ? staffRole : (userRole.isNotEmpty ? userRole : 'branch');
    _senderName = prefs.getString('rms_staff_name') ?? _repairService.ownerID;

    // Announcement — poll every 60s (global, no branch filter)
    await _loadAnnouncement();
    _announceTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadAnnouncement());

    if (_branchId == null) return;

    // Pos records
    _posSub = _sb
        .from('pos_trackings')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>((r) => {
        'id': r['id'],
        'tarikh': r['tarikh'] ?? '',
        'item': r['item'] ?? '',
        'kurier': r['kurier'] ?? '',
        'trackNo': r['track_no'] ?? '',
        'status_track': r['status_track'] ?? 'DIPOS',
        'timestamp': _tsFromIso(r['created_at']),
      }).toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _posRecords = list.take(15).toList());
    });

    // My feedback history
    if (_tenantId != null) {
      _feedbackSub = _sb
          .from('app_feedback')
          .stream(primaryKey: ['id'])
          .eq('tenant_id', _tenantId!)
          .listen((rows) {
        final list = rows.where((r) => r['branch_id'] == _branchId).map<Map<String, dynamic>>((r) => {
          'id': r['id'],
          'message': r['message'] ?? '',
          'status': r['status'] ?? 'open',
          'resolveNote': r['resolve_note'] ?? '',
          'resolvedAt': _tsFromIso(r['resolved_at']),
          'createdAt': _tsFromIso(r['created_at']),
        }).toList();
        list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
        if (mounted) setState(() => _myFeedbacks = list);
      });
    }
  }

  Future<void> _submitFeedback() async {
    final msg = _feedbackCtrl.text.trim();
    if (msg.isEmpty || _sending || _tenantId == null) return;
    setState(() => _sending = true);
    try {
      await _sb.from('app_feedback').insert({
        'tenant_id': _tenantId,
        'branch_id': _branchId,
        'sender_role': _senderRole,
        'sender_name': _senderName,
        'message': msg,
        'status': 'open',
      });
      _feedbackCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback dihantar'), backgroundColor: AppColors.green),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtTs(dynamic v) {
    final ms = v is num ? v.toInt() : 0;
    if (ms == 0) return '-';
    return DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  Color _posStatusColor(String s) {
    if (s == 'SELESAI') return AppColors.green;
    if (s == 'DALAM PERJALANAN') return AppColors.blue;
    return AppColors.yellow;
  }

  // ========== POS MODAL ==========
  void _showPosModal({Map<String, dynamic>? existing}) {
    final tarikhCtrl = TextEditingController(text: existing?['tarikh'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final itemCtrl = TextEditingController(text: existing?['item'] ?? '');
    final kurierCtrl = TextEditingController(text: existing?['kurier'] ?? '');
    final trackCtrl = TextEditingController(text: existing?['trackNo'] ?? '');
    String status = existing?['status_track'] ?? 'DIPOS';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(existing != null ? _lang.get('fl_kemaskini_rekod') : _lang.get('fl_tambah_rekod'), style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        _lbl(_lang.get('tarikh'), tarikhCtrl, 'yyyy-mm-dd'),
        _lbl(_lang.get('fl_item_tujuan'), itemCtrl, _lang.get('fl_maklumat_barang')),
        Row(children: [
          Expanded(child: _lbl(_lang.get('fl_kurier'), kurierCtrl, 'J&T / PosLaju')),
          const SizedBox(width: 8),
          Expanded(child: _lbl(_lang.get('fl_no_tracking'), trackCtrl, 'No Track', caps: true)),
        ]),
        Text(_lang.get('status'), style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        _dropdown([_lang.get('fl_dipos'), _lang.get('fl_dalam_perjalanan'), _lang.get('selesai')], status, (v) => setS(() => status = v!)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.textDim, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx), child: Text(_lang.get('batal')))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
            onPressed: () async {
              if (itemCtrl.text.trim().isEmpty) return;
              if (_tenantId == null || _branchId == null) return;
              final Map<String, dynamic> data = {
                'tenant_id': _tenantId,
                'branch_id': _branchId,
                'tarikh': tarikhCtrl.text.trim(),
                'item': itemCtrl.text.trim().toUpperCase(),
                'kurier': kurierCtrl.text.trim().toUpperCase(),
                'track_no': trackCtrl.text.trim().toUpperCase(),
                'status_track': status,
              };
              if (existing != null) {
                await _sb.from('pos_trackings').update(data).eq('id', existing['id']);
              } else {
                await _sb.from('pos_trackings').insert(data);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(_lang.get('simpan')))),
        ]),
      ])),
    )));
  }

  // ========== HELPERS ==========
  Widget _lbl(String label, TextEditingController ctrl, String hint, {TextInputType keyboard = TextInputType.text, bool caps = false}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      TextField(controller: ctrl, keyboardType: keyboard, textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
          filled: true, fillColor: AppColors.bgDeep, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderMed)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderMed)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)))),
    ]));
  }

  Widget _dropdown(List<String> items, String value, ValueChanged<String?> onChanged) {
    if (!items.contains(value)) value = items.first;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderMed)),
      child: DropdownButton<String>(value: value, isExpanded: true, underline: const SizedBox(), dropdownColor: Colors.white,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: _leftColumn());
  }

  Widget _leftColumn() => Column(children: [
    // Announcement
    _card(color: AppColors.blue, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const FaIcon(FontAwesomeIcons.bullhorn, size: 12, color: AppColors.blue), const SizedBox(width: 8),
        Text(_lang.get('fl_notifikasi_admin'), style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 10),
      _announcement.isEmpty
        ? Text(_lang.get('fl_tiada_pengumuman'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic))
        : Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
            child: Text('${_lang.get('fl_berita')}: $_announcement', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w900))),
    ])),
    const SizedBox(height: 16),
    // Feedback ke RMS Pro
    _card(color: AppColors.primary, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: const [
        FaIcon(FontAwesomeIcons.commentDots, size: 12, color: AppColors.primary),
        SizedBox(width: 8),
        Text('FEEDBACK KE RMS PRO', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ]),
      const SizedBox(height: 4),
      const Text('Hantar cadangan / aduan / bug kepada pembangun', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
      const SizedBox(height: 10),
      TextField(
        controller: _feedbackCtrl,
        maxLines: 3,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Tulis feedback anda di sini...',
          hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
          filled: true, fillColor: AppColors.bgDeep, isDense: true,
          contentPadding: const EdgeInsets.all(10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderMed)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderMed)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary, foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: _sending ? null : _submitFeedback,
        icon: _sending
            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : const FaIcon(FontAwesomeIcons.paperPlane, size: 12),
        label: Text(_sending ? 'MENGHANTAR...' : 'HANTAR FEEDBACK', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
      )),
      if (_myFeedbacks.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 10),
        const Text('SEJARAH FEEDBACK', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Column(children: _myFeedbacks.map((fb) {
          final resolved = fb['status'] == 'resolved';
          final accent = resolved ? AppColors.orange : AppColors.blue;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: resolved ? AppColors.orangeLight : AppColors.borderLight,
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                  child: Text(resolved ? 'SELESAI' : 'TERBUKA', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                Text(_fmtTs(fb['createdAt']), style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              ]),
              const SizedBox(height: 6),
              Text(fb['message'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, height: 1.3)),
              if (resolved && (fb['resolveNote'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FaIcon(FontAwesomeIcons.reply, size: 9, color: AppColors.orange),
                    const SizedBox(width: 6),
                    Expanded(child: Text(fb['resolveNote'], style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontStyle: FontStyle.italic))),
                  ]),
                ),
              ],
              if (resolved) ...[
                const SizedBox(height: 4),
                Text('Diselesaikan: ${_fmtTs(fb['resolvedAt'])}', style: const TextStyle(color: AppColors.orange, fontSize: 9, fontWeight: FontWeight.w800)),
              ],
            ]),
          );
        }).toList()),
      ],
    ])),
    const SizedBox(height: 16),
    // Pos & Tracking
    _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [const FaIcon(FontAwesomeIcons.truckFast, size: 12, color: AppColors.primary), const SizedBox(width: 8),
          Text(_lang.get('fl_rekod_pos'), style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900))]),
        GestureDetector(onTap: () => _showPosModal(), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const FaIcon(FontAwesomeIcons.plusCircle, size: 10, color: Colors.black), const SizedBox(width: 4),
            Text(_lang.get('tambah'), style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900))]))),
      ]),
      const SizedBox(height: 12),
      _posRecords.isEmpty
        ? Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(_lang.get('fl_tiada_rekod_pos'), style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic))))
        : Column(children: _posRecords.map((t) {
            final col = _posStatusColor(t['status_track'] ?? 'DIPOS');
            return Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: AppColors.primary, width: 3))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['tarikh'] ?? '-', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                  Text(t['trackNo'] ?? '-', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  Text('(${t['kurier'] ?? '-'})', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                  Text(t['item'] ?? '', style: const TextStyle(color: AppColors.textSub, fontSize: 10)),
                  const SizedBox(height: 4),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: col), borderRadius: BorderRadius.circular(4)),
                    child: Text(t['status_track'] ?? 'DIPOS', style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.w900))),
                ])),
                Column(children: [
                  GestureDetector(onTap: () => _showPosModal(existing: t),
                    child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.yellow)),
                      child: const FaIcon(FontAwesomeIcons.penToSquare, size: 10, color: AppColors.yellow))),
                  const SizedBox(height: 6),
                  GestureDetector(onTap: () async {
                    if (await _confirmDelete('Padam rekod pos ini?')) {
                      await _sb.from('pos_trackings').delete().eq('id', t['id']);
                    }
                  }, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const FaIcon(FontAwesomeIcons.trashCan, size: 10, color: AppColors.red))),
                ]),
              ]),
            );
          }).toList()),
    ])),
  ]);

  Widget _card({Widget? child, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16), width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color != null ? color.withValues(alpha: 0.3) : AppColors.borderMed),
      ),
      child: child,
    );
  }

  Future<bool> _confirmDelete(String msg) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_lang.get('batal'))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(_lang.get('padam'))),
      ],
    )) ?? false;
  }
}
