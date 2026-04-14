import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class TongSampahScreen extends StatefulWidget {
  const TongSampahScreen({super.key});
  @override
  State<TongSampahScreen> createState() => _TongSampahScreenState();
}

class _TongSampahScreenState extends State<TongSampahScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _deleted = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeleted();
  }

  Future<void> _loadDeleted() async {
    setState(() => _isLoading = true);
    try {
      final List<Map<String, dynamic>> all = [];

      // Fetch deleted dealers
      final dealerSnap = await _db
          .collection('saas_dealers')
          .where('status', isEqualTo: 'DELETED')
          .get();
      for (final doc in dealerSnap.docs) {
        final d = doc.data();
        all.add({
          'id': doc.id,
          'collection': 'saas_dealers',
          'type': 'AKAUN DEALER',
          'label': (d['namaKedai'] ?? d['ownerName'] ?? doc.id).toString(),
          'sublabel': d['ownerName'] ?? '-',
          'timestamp': d['timestamp'] ?? d['createdAt'],
          ...d,
        });
      }

      // Fetch deleted complaints
      final aduanSnap = await _db
          .collection('aduan_sistem')
          .where('status', isEqualTo: 'DELETED')
          .get();
      for (final doc in aduanSnap.docs) {
        final d = doc.data();
        all.add({
          'id': doc.id,
          'collection': 'aduan_sistem',
          'type': 'TIKET ADUAN',
          'label': (d['tajuk'] ?? '-').toString(),
          'sublabel': d['namaPengirim'] ?? '-',
          'timestamp': d['timestamp'],
          ...d,
        });
      }

      // Sort by timestamp descending
      all.sort((a, b) {
        final tsA = _toMillis(a['timestamp']);
        final tsB = _toMillis(b['timestamp']);
        return tsB.compareTo(tsA);
      });

      if (mounted) setState(() { _deleted = all; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        _snack('Ralat: $e', err: true);
        setState(() => _isLoading = false);
      }
    }
  }

  int _toMillis(dynamic ts) {
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is int) return ts;
    return 0;
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(ts);
    }
    if (dt == null) return '-';
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _recover(Map<String, dynamic> item) async {
    final collection = item['collection'] as String;
    final id = item['id'] as String;
    final newStatus = collection == 'saas_dealers' ? 'Pending' : 'BARU';
    try {
      await _db.collection(collection).doc(id).update({'status': newStatus});
      _snack('Berjaya dipulihkan');
      _loadDeleted();
    } catch (e) {
      _snack('Ralat: $e', err: true);
    }
  }

  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(children: [
          FaIcon(FontAwesomeIcons.triangleExclamation, size: 14, color: AppColors.red),
          SizedBox(width: 8),
          Text('PADAM KEKAL', style: TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Tindakan ini TIDAK boleh dibatalkan. Data akan dipadam sepenuhnya.',
            style: TextStyle(color: AppColors.textSub, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text('Taipkan PADAM untuk mengesahkan:',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: confirmCtrl,
            style: const TextStyle(color: AppColors.red, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'PADAM',
              hintStyle: TextStyle(color: AppColors.textDim.withValues(alpha: 0.5), fontSize: 14),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                borderSide: const BorderSide(color: AppColors.red, width: 1.5),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () {
              if (confirmCtrl.text.trim() == 'PADAM') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('PADAM KEKAL', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.collection(item['collection']).doc(item['id']).delete();
      _snack('Data dipadam sepenuhnya');
      _loadDeleted();
    } catch (e) {
      _snack('Ralat: $e', err: true);
    }
  }

  Widget _typeBadge(String type) {
    final isDealer = type == 'AKAUN DEALER';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDealer ? AppColors.blueLight : AppColors.yellowLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDealer ? AppColors.blue.withValues(alpha: 0.4) : AppColors.yellow.withValues(alpha: 0.4)),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: isDealer ? AppColors.blue : AppColors.orange,
          fontSize: 9,
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
            FaIcon(FontAwesomeIcons.trashCan, size: 16, color: AppColors.red),
            SizedBox(width: 10),
            Text('TONG SAMPAH', style: TextStyle(
              color: AppColors.red, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1,
            )),
          ]),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.redLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${_deleted.length}', style: const TextStyle(
                color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w900,
              )),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loadDeleted,
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
            'Menunjukkan ${_deleted.length} rekod dipadam',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      ),
      // List
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.red))
            : _deleted.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(FontAwesomeIcons.trashCan, size: 40, color: AppColors.textDim.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    const Text('Tong sampah kosong', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _deleted.length,
                    itemBuilder: (_, i) {
                      final item = _deleted[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Colors.white, AppColors.bg]),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderMed),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Top row: type badge + timestamp
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            _typeBadge(item['type']),
                            Row(children: [
                              const FaIcon(FontAwesomeIcons.clock, size: 9, color: AppColors.textDim),
                              const SizedBox(width: 4),
                              Text(_formatTimestamp(item['timestamp']),
                                  style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
                            ]),
                          ]),
                          const SizedBox(height: 10),
                          // Label (name or subject)
                          Text(
                            (item['label'] ?? '-').toString().toUpperCase(),
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (item['sublabel'] ?? '-').toString(),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          // Actions
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            GestureDetector(
                              onTap: () => _recover(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.greenLight,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  FaIcon(FontAwesomeIcons.arrowRotateLeft, size: 10, color: AppColors.green),
                                  SizedBox(width: 6),
                                  Text('PULIH', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900)),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _permanentDelete(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.redLight,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  FaIcon(FontAwesomeIcons.xmark, size: 10, color: AppColors.red),
                                  SizedBox(width: 6),
                                  Text('PADAM KEKAL', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w900)),
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
