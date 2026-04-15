import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/supabase_client.dart';

class NotisAduanScreen extends StatefulWidget {
  const NotisAduanScreen({super.key});
  @override
  State<NotisAduanScreen> createState() => _NotisAduanScreenState();
}

class _NotisAduanScreenState extends State<NotisAduanScreen> {
  final _sb = SupabaseService.client;
  List<Map<String, dynamic>> _aduan = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAduan();
  }

  Future<void> _loadAduan() async {
    setState(() => _isLoading = true);
    try {
      final rows = await _sb
          .from('system_complaints')
          .select()
          .order('created_at', ascending: false);
      _aduan = rows.map<Map<String, dynamic>>((r) => {
        'id': r['id'],
        'tajuk': r['subject'] ?? '',
        'keterangan': r['description'] ?? '',
        'namaPengirim': r['assigned_to'] ?? '',
        'status': r['status'] ?? 'OPEN',
        'timestamp': r['created_at'],
      }).where((d) => (d['status'] ?? '') != 'DELETED').toList();
    } catch (e) {
      if (mounted) _snack('Ralat: $e', err: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _markSelesai(String id) async {
    try {
      await _sb.from('system_complaints').update({'status': 'SELESAI'}).eq('id', id);
      _snack('Aduan ditanda selesai');
      _loadAduan();
    } catch (e) {
      _snack('Ralat: $e', err: true);
    }
  }

  Future<void> _softDelete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Padam Aduan',
            style: TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
        content: const Text('Aduan ini akan dipindahkan ke Tong Sampah.',
            style: TextStyle(color: AppColors.textSub, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PADAM', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _sb.from('system_complaints').update({'status': 'DELETED'}).eq('id', id);
      _snack('Aduan dipadam');
      _loadAduan();
    } catch (e) {
      _snack('Ralat: $e', err: true);
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    DateTime? dt;
    if (ts is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String && ts.isNotEmpty) {
      dt = DateTime.tryParse(ts);
    }
    if (dt == null) return '-';
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  Widget _statusBadge(String status) {
    final isBaru = status == 'BARU';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBaru ? AppColors.orangeLight : AppColors.greenLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isBaru ? AppColors.orange.withValues(alpha: 0.4) : AppColors.green.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isBaru ? AppColors.orange : AppColors.green,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.borderMed),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [
            FaIcon(FontAwesomeIcons.bullhorn, size: 16, color: AppColors.orange),
            SizedBox(width: 10),
            Text('ADUAN SISTEM', style: TextStyle(
              color: AppColors.orange, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1,
            )),
          ]),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${_aduan.length}', style: const TextStyle(
                color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w900,
              )),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loadAduan,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14, color: AppColors.textMuted),
              ),
            ),
          ]),
        ]),
      ),
      // Count
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Menunjukkan ${_aduan.length} aduan aktif',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      ),
      // List
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
            : _aduan.isEmpty
                ? const Center(child: Text('Tiada aduan', style: TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _aduan.length,
                    itemBuilder: (_, i) {
                      final a = _aduan[i];
                      final status = (a['status'] ?? 'BARU').toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderMed),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Top row: sender + status
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Expanded(
                              child: Row(children: [
                                const FaIcon(FontAwesomeIcons.user, size: 11, color: AppColors.textMuted),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    (a['namaPengirim'] ?? '-').toString().toUpperCase(),
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ]),
                            ),
                            _statusBadge(status),
                          ]),
                          const SizedBox(height: 4),
                          // OwnerID + timestamp
                          Row(children: [
                            Text('ID: ${a['ownerID'] ?? '-'}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 12),
                            FaIcon(FontAwesomeIcons.clock, size: 9, color: AppColors.textDim),
                            const SizedBox(width: 4),
                            Text(_formatTimestamp(a['timestamp']),
                                style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
                          ]),
                          const SizedBox(height: 10),
                          // Tajuk
                          Text(
                            (a['tajuk'] ?? '-').toString(),
                            style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          // Mesej
                          Text(
                            (a['mesej'] ?? '-').toString(),
                            style: const TextStyle(color: AppColors.textSub, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          // Actions
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if (status == 'BARU') ...[
                              GestureDetector(
                                onTap: () => _markSelesai(a['id']),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.greenLight,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    FaIcon(FontAwesomeIcons.check, size: 10, color: AppColors.green),
                                    SizedBox(width: 6),
                                    Text('SELESAI', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900)),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            GestureDetector(
                              onTap: () => _softDelete(a['id']),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.redLight,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  FaIcon(FontAwesomeIcons.trash, size: 10, color: AppColors.red),
                                  SizedBox(width: 6),
                                  Text('PADAM', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w900)),
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
