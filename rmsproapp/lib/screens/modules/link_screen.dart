import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

const _functionsBase = 'https://us-central1-rmspro-2f454.cloudfunctions.net';

class LinkScreen extends StatefulWidget {
  final Map<String, dynamic>? enabledModules;
  const LinkScreen({super.key, this.enabledModules});
  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  bool get _phoneEnabled {
    final m = widget.enabledModules;
    if (m == null || m.isEmpty) return true;
    return m['JualTelefon'] != false;
  }
  final _lang = AppLanguage();
  final _db = FirebaseFirestore.instance;
  String _ownerID = 'admin';
  String _dealerCode = '';
  String _domain = 'https://rmspro.net';
  bool _isCustomDomain = false;
  String _domainStatus = '';
  List<Map<String, String>> _dnsRecords = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      _ownerID = branch.split('@')[0];
    }
    try {
      final dealerSnap = await _db
          .collection('saas_dealers')
          .doc(_ownerID)
          .get();
      if (dealerSnap.exists) {
        final data = dealerSnap.data()!;
        final domain = data['domain'] as String?;
        if (domain != null && domain.isNotEmpty) {
          _domain = domain;
          _isCustomDomain = _domain != 'https://rmspro.net';
        }
        _domainStatus = (data['domainStatus'] ?? '').toString();
        final rawDns = data['dnsRecords'] as List? ?? [];
        _dnsRecords = rawDns
            .whereType<Map>()
            .map((r) => r.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())))
            .toList();
        // Load or generate dealerCode
        if (data['dealerCode'] != null && (data['dealerCode'] as String).isNotEmpty) {
          _dealerCode = data['dealerCode'];
        } else {
          _dealerCode = _generateCode();
          await _db.collection('saas_dealers').doc(_ownerID).set({
            'dealerCode': _dealerCode,
          }, SetOptions(merge: true));
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String _generateCode() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final rand = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var seed = rand;
    for (var i = 0; i < 6; i++) {
      buf.write(chars[seed % chars.length]);
      seed = (seed ~/ chars.length) + i * 7;
    }
    return buf.toString();
  }

  String _buildUrl(String route) {
    if (_isCustomDomain) {
      // profixmobile.my/booking
      return '$_domain/$route';
    }
    // rmspro.net/booking/DEALER_CODE
    return '$_domain/$route/$_dealerCode';
  }

  List<_LinkItem> get _links => [
    _LinkItem(
      title: _lang.get('link_borang_booking'),
      subtitle: _lang.get('link_borang_booking_desc'),
      icon: FontAwesomeIcons.calendarCheck,
      color: const Color(0xFF06B6D4),
      bgColor: const Color(0xFFCFFAFE),
      url: _buildUrl('booking'),
      actualUrl: _buildUrl('booking'),
      pageKey: 'booking',
    ),
    _LinkItem(
      title: _lang.get('link_borang_pelanggan'),
      subtitle: _lang.get('link_borang_pelanggan_desc'),
      icon: FontAwesomeIcons.fileLines,
      color: const Color(0xFF3B82F6),
      bgColor: const Color(0xFFDBEAFE),
      url: _buildUrl('borang'),
      actualUrl: _buildUrl('borang'),
      pageKey: 'borang',
    ),
    if (_phoneEnabled)
      _LinkItem(
        title: _lang.get('link_katalog_telefon'),
        subtitle: _lang.get('link_katalog_telefon_desc'),
        icon: FontAwesomeIcons.store,
        color: const Color(0xFF10B981),
        bgColor: const Color(0xFFD1FAE5),
        url: _buildUrl('catalog'),
        actualUrl: _buildUrl('catalog'),
        pageKey: 'catalog',
      ),
    _LinkItem(
      title: _lang.get('link_bio'),
      subtitle: _lang.get('link_bio_desc'),
      icon: FontAwesomeIcons.idCard,
      color: const Color(0xFF8B5CF6),
      bgColor: const Color(0xFFEDE9FE),
      url: _buildUrl('link'),
      actualUrl: _buildUrl('link'),
      pageKey: 'link',
    ),
  ];

  void _copyLink(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_lang.get('link_disalin')),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════
  // DOMAIN MANAGEMENT
  // ═══════════════════════════════════════

  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Text(msg, style: const TextStyle(fontSize: 12)),
        ]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
      ),
    );
  }

  Future<void> _showAddDomainDialog() async {
    final domainController = TextEditingController();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TAMBAH DOMAIN',
                style: TextStyle(
                  color: AppColors.textSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Text('Domain:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: domainController,
                decoration: InputDecoration(
                  hintText: 'contoh: kedaisaya.com',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (domainController.text.trim().isEmpty) return;
                    Navigator.pop(ctx, domainController.text.trim());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Simpan & Setup',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        );
      },
    ).then((result) {
      if (result != null && result is String && result.isNotEmpty) {
        _setupDomain(result);
      }
    });
  }

  Future<void> _setupDomain(String domain) async {
    _showLoading('Menyediakan domain...');
    try {
      final resp = await http.post(
        Uri.parse('$_functionsBase/addCustomDomain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'domain': domain, 'ownerID': _ownerID}),
      );

      if (!mounted) return;
      Navigator.pop(context);

      final data = jsonDecode(resp.body) as Map<String, dynamic>? ?? {};

      if (resp.statusCode != 200) {
        throw Exception(data['error'] ?? 'Gagal menambah domain.');
      }

      final rawDns = data['dnsRecords'] as List? ?? [];
      final dnsRecords = rawDns.whereType<Map>().map((r) =>
        r.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
      ).toList();

      _showDnsDialog(
        domain: (data['domain'] ?? domain).toString(),
        status: (data['status'] ?? 'PENDING_DNS').toString(),
        message: (data['message'] ?? '').toString(),
        dnsRecords: dnsRecords,
      );
      _init();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _checkDomainStatus() async {
    if (!_isCustomDomain) return;
    _showLoading('Menyemak status...');
    try {
      final domainClean = _domain.replaceAll('https://', '').replaceAll('http://', '');
      final resp = await http.post(
        Uri.parse('$_functionsBase/checkDomainStatus'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'domain': domainClean,
          'ownerID': _ownerID,
        }),
      );

      if (!mounted) return;
      Navigator.pop(context);

      final data = jsonDecode(resp.body) as Map<String, dynamic>? ?? {};

      if (resp.statusCode != 200) {
        throw Exception(data['error'] ?? 'Gagal semak status.');
      }

      final rawDns = data['dnsRecords'] as List? ?? [];
      final dnsRecords = rawDns.whereType<Map>().map((r) =>
        r.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
      ).toList();

      _showDnsDialog(
        domain: (data['domain'] ?? '').toString(),
        status: (data['status'] ?? '').toString(),
        message: (data['message'] ?? '').toString(),
        dnsRecords: dnsRecords,
      );
      _init();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal semak: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _deleteDomain() async {
    final domainClean = _domain.replaceAll('https://', '').replaceAll('http://', '');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padam Domain?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        content: Text(
          'Domain $domainClean akan dipadam. Link anda akan kembali ke rmspro.net.',
          style: TextStyle(color: AppColors.textSub, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
            child: const Text('Padam', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
      ),
    );
    if (confirm != true) return;

    try {
      await _db.collection('saas_dealers').doc(_ownerID).update({
        'domain': FieldValue.delete(),
        'domainStatus': FieldValue.delete(),
        'dnsRecords': FieldValue.delete(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Domain telah dipadam'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _init();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal padam: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _showSavedDns() {
    if (_dnsRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Tiada DNS records. Tekan "Semak" untuk refresh.'),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    final domainClean = _domain.replaceAll('https://', '').replaceAll('http://', '');
    _showDnsDialog(
      domain: domainClean,
      status: _domainStatus,
      message: _domainStatus == 'ACTIVE'
          ? 'Domain aktif dan sedia digunakan!'
          : 'Sila set DNS records berikut.',
      dnsRecords: _dnsRecords,
    );
  }

  void _showDnsDialog({
    required String domain,
    required String status,
    required String message,
    required List<Map<String, String>> dnsRecords,
  }) {
    final isActive = status == 'ACTIVE';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(isActive ? Icons.check_circle : Icons.dns,
              color: isActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(isActive ? 'Domain Aktif!' : 'DNS Records',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w900))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.language, size: 14, color: Color(0xFF3B82F6)),
                const SizedBox(width: 8),
                Expanded(child: Text(domain, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'monospace'))),
              ]),
            ),
            const SizedBox(height: 10),
            Text(message, style: TextStyle(color: AppColors.textSub, fontSize: 11, height: 1.4)),
            if (dnsRecords.isNotEmpty && !isActive) ...[
              const SizedBox(height: 14),
              Text('SET DNS RECORDS INI:', style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              ...dnsRecords.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(4)),
                      child: Text((r['type'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Text('Name: ${(r['host'] ?? '@').toString()}', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: (r['value'] ?? '').toString()));
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: const Text('Disalin!'), backgroundColor: AppColors.green,
                        behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ));
                    },
                    child: Row(children: [
                      Expanded(child: Text((r['value'] ?? '').toString(), style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w600))),
                      Icon(Icons.copy, size: 12, color: AppColors.textMuted),
                    ]),
                  ),
                ]),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        scrollable: true,
      ),
    );
  }

  // ignore: unused_element
  Widget _buildDomainSection() {
    final domainClean = _domain.replaceAll('https://', '').replaceAll('http://', '');
    final isActive = _domainStatus == 'ACTIVE';

    if (!_isCustomDomain) {
      // No custom domain - show add button
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const FaIcon(FontAwesomeIcons.globe, size: 14, color: Color(0xFF8B5CF6)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Domain Custom',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF8B5CF6))),
                      Text('Guna domain sendiri untuk semua link',
                          style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _showAddDomainDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FaIcon(FontAwesomeIcons.plus, size: 10, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 6),
                      Text('Tambah Domain', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Has custom domain - show status card
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const FaIcon(FontAwesomeIcons.globe, size: 14, color: Color(0xFF8B5CF6)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(domainClean,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6))),
                    const SizedBox(height: 2),
                    Text('Domain Custom',
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isActive ? 'Aktif' : 'Pending',
                  style: TextStyle(
                    color: isActive ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _actionBtn(FontAwesomeIcons.server, 'DNS', const Color(0xFF8B5CF6), _showSavedDns)),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(FontAwesomeIcons.rotate, 'Semak', const Color(0xFF10B981), _checkDomainStatus)),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(FontAwesomeIcons.trash, 'Padam', AppColors.red, _deleteDomain)),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomSheet(String pageKey, String title) async {
    // Load existing theme
    Map<String, dynamic> theme = {};
    try {
      final doc = await _db.collection('saas_dealers').doc(_ownerID).get();
      if (doc.exists) {
        final themes = doc.data()?['pageThemes'] as Map?;
        if (themes != null && themes[pageKey] != null) {
          theme = Map<String, dynamic>.from(themes[pageKey] as Map);
        }
      }
    } catch (_) {}

    String bgColor = (theme['bgColor'] as String?) ?? '#020617';
    String textColor = (theme['textColor'] as String?) ?? '#ffffff';
    String accentColor = (theme['accentColor'] as String?) ?? '#00ffa3';
    double fontSize = (theme['fontSize'] as num?)?.toDouble() ?? 14.0;

    const presetColors = [
      '#020617', '#0f172a', '#1e293b', '#111827', '#18181b',
      '#ffffff', '#f8fafc', '#f1f5f9', '#fef2f2', '#fdf4ff',
      '#00ffa3', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899',
      '#ef4444', '#f59e0b', '#06b6d4', '#6366f1', '#14b8a6',
    ];

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Widget colorGrid(String label, String selected, ValueChanged<String> onSelect) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSub)),
                      const SizedBox(width: 8),
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: _hexToColor(selected),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presetColors.map((c) {
                      final isSelected = c == selected;
                      return GestureDetector(
                        onTap: () => setModalState(() => onSelect(c)),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: _hexToColor(c),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF3B82F6) : AppColors.border,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isSelected
                              ? Icon(Icons.check, size: 14, color: _isDark(c) ? Colors.white : Colors.black)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CUSTOM: $title'.toUpperCase(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.textSub)),
                    const SizedBox(height: 20),

                    // Background color
                    colorGrid('Warna Background', bgColor, (c) => bgColor = c),
                    const SizedBox(height: 16),

                    // Text color
                    colorGrid('Warna Tulisan', textColor, (c) => textColor = c),
                    const SizedBox(height: 16),

                    // Accent color
                    colorGrid('Warna Accent', accentColor, (c) => accentColor = c),
                    const SizedBox(height: 16),

                    // Font size
                    Text('Saiz Tulisan: ${fontSize.round()}px',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSub)),
                    Slider(
                      value: fontSize,
                      min: 10,
                      max: 22,
                      divisions: 12,
                      activeColor: const Color(0xFF3B82F6),
                      onChanged: (v) => setModalState(() => fontSize = v),
                    ),
                    const SizedBox(height: 8),

                    // Preview
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _hexToColor(bgColor),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Text('Preview', style: TextStyle(color: _hexToColor(accentColor), fontSize: fontSize + 2, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('Contoh tulisan biasa', style: TextStyle(color: _hexToColor(textColor), fontSize: fontSize)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text('Simpan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((result) async {
      if (result == true) {
        try {
          await _db.collection('saas_dealers').doc(_ownerID).set({
            'pageThemes': {
              pageKey: {
                'bgColor': bgColor,
                'textColor': textColor,
                'accentColor': accentColor,
                'fontSize': fontSize.round(),
              }
            }
          }, SetOptions(merge: true));

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Theme disimpan!'),
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal simpan: $e'),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    });
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  bool _isDark(String hex) {
    final color = _hexToColor(hex);
    return (color.r * 0.299 + color.g * 0.587 + color.b * 0.114) < 0.5;
  }

  void _openLink(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _shareLink(String url, String title) {
    final waText = Uri.encodeComponent('$title\n$url');
    launchUrl(
      Uri.parse('https://wa.me/?text=$waText'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const FaIcon(
                        FontAwesomeIcons.link,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _lang.get('link_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _lang.get('link_desc'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Domain section — only available in Owner SaaS module
          // _buildDomainSection(),

          // Link cards
          ...links.map((link) => _buildLinkCard(link)),
        ],
      ),
    );
  }

  Widget _buildLinkCard(_LinkItem link) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: link.bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FaIcon(link.icon, size: 16, color: link.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.title,
                        style: TextStyle(
                          color: link.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        link.subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _actionBtn(
                    FontAwesomeIcons.copy,
                    _lang.get('link_salin'),
                    AppColors.blue,
                    () => _copyLink(link.actualUrl),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    FontAwesomeIcons.arrowUpRightFromSquare,
                    _lang.get('link_buka'),
                    AppColors.green,
                    () => _openLink(link.actualUrl),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    FontAwesomeIcons.whatsapp,
                    _lang.get('link_kongsi'),
                    const Color(0xFF25D366),
                    () => _shareLink(link.actualUrl, link.title),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    FontAwesomeIcons.palette,
                    'Custom',
                    const Color(0xFFE11D48),
                    () => _showCustomSheet(link.pageKey, link.title),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, size: 11, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkItem {
  final String title, subtitle, url, actualUrl, pageKey;
  final IconData icon;
  final Color color, bgColor;
  const _LinkItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.url,
    required this.actualUrl,
    required this.pageKey,
  });
}
