import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/supabase_client.dart';

class SaasFeedbackScreen extends StatefulWidget {
  const SaasFeedbackScreen({super.key});
  @override
  State<SaasFeedbackScreen> createState() => _SaasFeedbackScreenState();
}

class _SaasFeedbackScreenState extends State<SaasFeedbackScreen> with SingleTickerProviderStateMixin {
  final _sb = SupabaseService.client;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  int _tsFromIso(dynamic v) {
    if (v is int) return v;
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  String _fmtTs(dynamic v) {
    final ms = _tsFromIso(v);
    if (ms == 0) return '-';
    return DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  Future<void> _markResolved(Map<String, dynamic> fb) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('TANDA SELESAI', style: TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text('Nota balasan (pilihan):', style: TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        TextField(
          controller: noteCtrl, maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Contoh: Sudah diperbaiki dalam versi 1.2.0',
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
            filled: true, fillColor: AppColors.bgDeep, isDense: true,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderMed)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderMed)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.green)),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.textDim, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, false), child: const Text('BATAL'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('SELESAI'))),
        ]),
      ])),
    )) ?? false;
    if (!ok) return;
    await _sb.from('app_feedback').update({
      'status': 'resolved',
      'resolved_at': DateTime.now().toIso8601String(),
      'resolve_note': noteCtrl.text.trim(),
    }).eq('id', fb['id']);
  }

  Future<void> _reopen(Map<String, dynamic> fb) async {
    await _sb.from('app_feedback').update({
      'status': 'open',
      'resolved_at': null,
      'resolve_note': null,
    }).eq('id', fb['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: const [
          FaIcon(FontAwesomeIcons.commentDots, size: 14, color: AppColors.primary),
          SizedBox(width: 8),
          Text('FEEDBACK PENGGUNA', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ]),
      ),
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          tabs: const [
            Tab(text: 'TERBUKA'),
            Tab(text: 'SELESAI'),
          ],
        ),
      ),
      Expanded(child: TabBarView(controller: _tab, children: [
        _buildList(status: 'open'),
        _buildList(status: 'resolved'),
      ])),
    ]);
  }

  Widget _buildList({required String status}) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sb.from('app_feedback').stream(primaryKey: ['id']).eq('status', status),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        final docs = snap.data!.map<Map<String, dynamic>>((r) {
          return {
            ...Map<String, dynamic>.from(r),
            'senderName': r['sender_name'] ?? '',
            'senderRole': r['sender_role'] ?? '',
            'ownerID': '',
            'shopID': '',
            'resolveNote': r['resolve_note'] ?? '',
            'createdAt': _tsFromIso(r['created_at']),
            'resolvedAt': _tsFromIso(r['resolved_at']),
          };
        }).toList();
        docs.sort((a, b) {
          final ka = status == 'resolved' ? (a['resolvedAt'] ?? 0) : (a['createdAt'] ?? 0);
          final kb = status == 'resolved' ? (b['resolvedAt'] ?? 0) : (b['createdAt'] ?? 0);
          return ((kb) as num).compareTo((ka) as num);
        });
        if (docs.isEmpty) {
          return Center(child: Text(
            status == 'open' ? 'Tiada feedback terbuka' : 'Tiada sejarah selesai',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
          ));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (_, i) => _card(docs[i]),
        );
      },
    );
  }

  Widget _card(Map<String, dynamic> fb) {
    final resolved = fb['status'] == 'resolved';
    final accent = resolved ? AppColors.orange : AppColors.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: resolved ? AppColors.orangeLight : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
            child: Text((fb['senderRole'] ?? '-').toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(
            (fb['senderName'] ?? '-').toString(),
            style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
          )),
          Text(_fmtTs(fb['createdAt']), style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
        ]),
        const SizedBox(height: 8),
        Text(fb['message'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.3)),
        if (resolved) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const FaIcon(FontAwesomeIcons.circleCheck, size: 10, color: AppColors.orange),
                const SizedBox(width: 6),
                Text('SELESAI · ${_fmtTs(fb['resolvedAt'])}', style: const TextStyle(color: AppColors.orange, fontSize: 9, fontWeight: FontWeight.w900)),
              ]),
              if ((fb['resolveNote'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(fb['resolveNote'], style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (!resolved)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 28),
              ),
              onPressed: () => _markResolved(fb),
              icon: const FaIcon(FontAwesomeIcons.check, size: 10),
              label: const Text('TANDA SELESAI', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textDim, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 28),
              ),
              onPressed: () => _reopen(fb),
              icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 10),
              label: const Text('BUKA SEMULA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
            ),
        ]),
      ]),
    );
  }
}
