import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class KatakataScreen extends StatefulWidget {
  const KatakataScreen({super.key});

  @override
  State<KatakataScreen> createState() => _KatakataScreenState();
}

class _KatakataScreenState extends State<KatakataScreen> {
  final _db = FirebaseFirestore.instance;
  final _motivasiCtrl = TextEditingController();
  final _solatCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSavingMotivasi = false;
  bool _isSavingSolat = false;
  String _lastUpdateMotivasi = '-';
  String _lastUpdateSolat = '-';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _motivasiCtrl.dispose();
    _solatCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    DateTime? d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else if (ts is int) {
      d = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is double) {
      d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    }
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(d);
  }

  // ═══════════════════════════════════════
  // LOAD
  // ═══════════════════════════════════════

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _db
          .collection('system_settings')
          .doc('pengumuman')
          .get();

      if (snap.exists) {
        final data = snap.data() ?? {};
        _motivasiCtrl.text = (data['motivasi'] ?? '').toString();
        _solatCtrl.text = (data['nasihatSolat'] ?? '').toString();
        _lastUpdateMotivasi =
            _formatTimestamp(data['tarikhKemaskiniMotivasi']);
        _lastUpdateSolat =
            _formatTimestamp(data['tarikhKemaskiniSolat']);
      }
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

  // ═══════════════════════════════════════
  // SAVE
  // ═══════════════════════════════════════

  Future<void> _saveMotivasi() async {
    if (_motivasiCtrl.text.trim().isEmpty) return;
    setState(() => _isSavingMotivasi = true);
    try {
      await _db.collection('system_settings').doc('pengumuman').set({
        'motivasi': _motivasiCtrl.text.trim(),
        'tarikhKemaskiniMotivasi': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _lastUpdateMotivasi = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                FaIcon(FontAwesomeIcons.circleCheck,
                    color: Colors.white, size: 16),
                SizedBox(width: 10),
                Text('Motivasi berjaya dikemaskini!'),
              ],
            ),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMotivasi = false);
    }
  }

  Future<void> _saveSolat() async {
    if (_solatCtrl.text.trim().isEmpty) return;
    setState(() => _isSavingSolat = true);
    try {
      await _db.collection('system_settings').doc('pengumuman').set({
        'nasihatSolat': _solatCtrl.text.trim(),
        'tarikhKemaskiniSolat': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _lastUpdateSolat = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                FaIcon(FontAwesomeIcons.circleCheck,
                    color: Colors.white, size: 16),
                SizedBox(width: 10),
                Text('Nasihat solat berjaya dikemaskini!'),
              ],
            ),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSolat = false);
    }
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: const BoxDecoration(
            color: AppColors.bgDeep,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KATA-KATA HARI INI',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Hebahkan motivasi dan nasihat solat kepada semua dealer.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildMotivasiCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildSolatCard()),
                          ],
                        )
                      : Column(
                          children: [
                            _buildMotivasiCard(),
                            const SizedBox(height: 16),
                            _buildSolatCard(),
                          ],
                        ),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // MOTIVATION CARD
  // ═══════════════════════════════════════

  Widget _buildMotivasiCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const FaIcon(FontAwesomeIcons.lightbulb,
                    size: 18, color: Color(0xFF6366F1)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motivasi Harian',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Kata-kata semangat untuk dealer',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Text field
          TextField(
            controller: _motivasiCtrl,
            maxLines: 6,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: 'Tulis motivasi hari ini...',
              hintStyle: const TextStyle(color: AppColors.textDim),
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 10),
          // Last update
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.clock,
                  size: 10, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text(
                'Kemaskini: $_lastUpdateMotivasi',
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingMotivasi ? null : _saveMotivasi,
              icon: _isSavingMotivasi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const FaIcon(FontAwesomeIcons.bullhorn,
                      size: 14, color: Colors.white),
              label: const Text('HEBAHKAN MOTIVASI'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5),
                elevation: 2,
                shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // PRAYER ADVICE CARD
  // ═══════════════════════════════════════

  Widget _buildSolatCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const FaIcon(FontAwesomeIcons.handsPraying,
                    size: 18, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nasihat Solat',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Peringatan solat untuk dealer',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Text field
          TextField(
            controller: _solatCtrl,
            maxLines: 6,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: 'Tulis nasihat solat hari ini...',
              hintStyle: const TextStyle(color: AppColors.textDim),
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.green, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 10),
          // Last update
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.clock,
                  size: 10, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text(
                'Kemaskini: $_lastUpdateSolat',
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingSolat ? null : _saveSolat,
              icon: _isSavingSolat
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const FaIcon(FontAwesomeIcons.bullhorn,
                      size: 14, color: Colors.white),
              label: const Text('HEBAHKAN NASIHAT SOLAT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5),
                elevation: 2,
                shadowColor: AppColors.green.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
