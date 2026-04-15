import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';

/// Dealer Support chat — single ticket per branch (user ↔ Dealer Support admin).
/// Table: sv_tickets (branch_id = thread key), sv_ticket_meta (sidebar meta).
class ChatScreen extends StatefulWidget {
  final String ownerID;
  final String shopID;
  const ChatScreen({super.key, required this.ownerID, required this.shopID});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _sb = SupabaseService.client;
  final _repair = RepairService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  String? _tenantId;
  String? _branchId;
  String _senderName = 'USER';
  String _shopCode = '';

  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _repair.init();
    _tenantId = _repair.tenantId;
    _branchId = _repair.branchId;
    if (_branchId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final row = await _sb
          .from('branches')
          .select('nama_kedai, shop_code')
          .eq('id', _branchId!)
          .maybeSingle();
      if (row != null) {
        _senderName = (row['nama_kedai'] ?? 'USER').toString().toUpperCase();
        _shopCode = (row['shop_code'] ?? '').toString().toUpperCase();
      }
    } catch (_) {}

    // Realtime stream
    _sub = _sb
        .from('sv_tickets')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .order('created_at')
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _messages = rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
        _loading = false;
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _tenantId == null || _branchId == null) return;
    _msgCtrl.clear();
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _sb.from('sv_tickets').insert({
        'tenant_id': _tenantId,
        'branch_id': _branchId,
        'sender_id': _branchId,
        'sender_name': _senderName,
        'role': 'user',
        'text': text,
      });
      await _sb.from('sv_ticket_meta').upsert({
        'branch_id': _branchId,
        'tenant_id': _tenantId,
        'name': _senderName,
        'shop_code': _shopCode,
        'last_msg': text,
        'last_ts': now,
        'last_from': 'user',
        'updated_at': now,
      }, onConflict: 'branch_id');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal hantar: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  String _fmtTime(dynamic iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso.toString());
    if (d == null) return '';
    final now = DateTime.now();
    final local = d.toLocal();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return DateFormat('HH:mm').format(local);
    }
    return DateFormat('dd/MM HH:mm').format(local);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      Expanded(child: _buildBody()),
      _buildCompose(),
    ]);
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.green, width: 2)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
            shape: BoxShape.circle,
          ),
          child: const Center(child: FaIcon(FontAwesomeIcons.userShield, size: 16, color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Dealer Support', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900)),
          SizedBox(height: 2),
          Text('Hubungi support untuk bantuan', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.green));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          FaIcon(FontAwesomeIcons.commentDots, size: 40, color: AppColors.textDim),
          SizedBox(height: 12),
          Text('Belum ada mesej', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Hantar mesej pertama untuk hubungi support', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
        ]),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(14),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final mine = (m['role'] ?? 'user') != 'admin';
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const FaIcon(FontAwesomeIcons.userShield, size: 9, color: AppColors.green),
                      const SizedBox(width: 4),
                      Text(
                        (m['sender_name'] ?? 'DEALER SUPPORT').toString(),
                        style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ]),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.green : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(mine ? 12 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 12),
                    ),
                    border: mine ? null : Border.all(color: AppColors.borderMed),
                  ),
                  child: Text(
                    (m['text'] ?? '').toString(),
                    style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary, fontSize: 12, height: 1.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(_fmtTime(m['created_at']),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompose() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderMed)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Tulis mesej...',
              hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              filled: true, fillColor: AppColors.bgDeep,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
            child: const Center(child: FaIcon(FontAwesomeIcons.paperPlane, size: 13, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
