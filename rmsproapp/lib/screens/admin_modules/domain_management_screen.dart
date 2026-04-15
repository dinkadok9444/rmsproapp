import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';
import '../../services/supabase_client.dart';

const _edgeBase = 'https://lpurtgmqecabgwwenikb.supabase.co/functions/v1/cf-custom-hostname';

class DomainManagementScreen extends StatefulWidget {
  const DomainManagementScreen({super.key});
  @override
  State<DomainManagementScreen> createState() => _DomainManagementScreenState();
}

class _DomainManagementScreenState extends State<DomainManagementScreen> {
  final _sb = SupabaseService.client;
  List<Map<String, dynamic>> _domainList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDomains();
  }

  Future<void> _loadDomains() async {
    setState(() => _isLoading = true);
    try {
      final rows = await _sb
          .from('tenants')
          .select('owner_id,nama_kedai,domain,domain_status,dns_records')
          .not('domain', 'is', null)
          .order('nama_kedai');

      _domainList = (rows as List)
          .whereType<Map>()
          .map((r) => <String, dynamic>{
                'id': (r['owner_id'] ?? '').toString(),
                'namaKedai': (r['nama_kedai'] ?? '').toString(),
                'domain': (r['domain'] ?? '').toString(),
                'domainStatus': (r['domain_status'] ?? '').toString(),
                'dnsRecords': r['dns_records'] ?? [],
              })
          .toList();
    } catch (e) {
      debugPrint('loadDomains error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showAddDialog() async {
    final domainController = TextEditingController();
    final searchController = TextEditingController();
    List<Map<String, dynamic>> allDealers = [];
    List<Map<String, dynamic>> filtered = [];
    Map<String, dynamic>? selected;
    bool loading = true;

    try {
      final rows = await _sb
          .from('tenants')
          .select('owner_id,nama_kedai')
          .order('nama_kedai');

      allDealers = (rows as List)
          .whereType<Map>()
          .map((r) => <String, dynamic>{
                'id': (r['owner_id'] ?? '').toString(),
                'namaKedai': (r['nama_kedai'] ?? '').toString(),
              })
          .toList();

      filtered = List.from(allDealers);
      loading = false;
    } catch (e) {
      loading = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal load dealer: $e'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }

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
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
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
                  if (selected == null) ...[
                    Text('Cari dealer:',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: searchController,
                      onChanged: (v) {
                        setModalState(() {
                          final q = v.toLowerCase();
                          filtered = allDealers.where((d) {
                            final dName = (d['namaKedai'] ?? '').toString().toLowerCase();
                            final dId = (d['id'] ?? '').toString().toLowerCase();
                            return dName.contains(q) || dId.contains(q);
                          }).toList();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Nama atau ID dealer...',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            return GestureDetector(
                              onTap: () => setModalState(() => selected = d),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const FaIcon(FontAwesomeIcons.store, size: 11, color: Color(0xFF3B82F6)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text((d['namaKedai'] ?? '').toString(),
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                          Text((d['id'] ?? '').toString(),
                                              style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                    const FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: AppColors.textDim),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const FaIcon(FontAwesomeIcons.store, size: 12, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (selected!['namaKedai'] ?? '').toString(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF3B82F6)),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setModalState(() => selected = null),
                            child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
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
                          Navigator.pop(ctx, {
                            'ownerID': (selected!['id'] ?? '').toString(),
                            'domain': domainController.text.trim(),
                          });
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
                ],
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result != null && result is Map) {
        _setupDomain((result['ownerID'] ?? '').toString(), (result['domain'] ?? '').toString());
      }
    });
  }

  Future<void> _setupDomain(String ownerID, String domain) async {
    _showLoading('Menyediakan domain...');
    try {
      final resp = await http.post(
        Uri.parse(_edgeBase),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'add', 'hostname': domain, 'ownerID': ownerID}),
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
      _loadDomains();
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

  Future<void> _checkStatus(Map<String, dynamic> item) async {
    _showLoading('Menyemak status...');
    try {
      final resp = await http.post(
        Uri.parse(_edgeBase),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'check',
          'hostname': (item['domain'] ?? '').toString(),
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
      _loadDomains();
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

  Future<void> _deleteDomain(Map<String, dynamic> item) async {
    final domainName = (item['domain'] ?? '').toString().replaceAll('https://', '');
    final kedaiName = (item['namaKedai'] ?? '').toString();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padam Domain?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        content: Text(
          'Domain $domainName untuk $kedaiName akan dipadam.',
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
      final safeId = (item['id'] ?? '').toString();
      if (safeId.isNotEmpty) {
        await _sb.from('tenants').update({
          'domain': null,
          'domain_status': 'PENDING_DNS',
        }).eq('owner_id', safeId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Domain telah dipadam'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _loadDomains();
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

  void _showSavedDns(Map<String, dynamic> item) {
    final domain = (item['domain'] ?? '').toString().replaceAll('https://', '');
    final status = (item['domainStatus'] ?? '').toString();
    final rawDns = item['dnsRecords'] as List? ?? [];
    final dnsRecords = rawDns
        .whereType<Map>()
        .map((r) => r.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())))
        .toList();

    if (dnsRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Tiada DNS records. Tekan "Semak" untuk refresh.'),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    _showDnsDialog(
      domain: domain,
      status: status,
      message: status == 'ACTIVE'
          ? 'Domain aktif dan sedia digunakan!'
          : 'Sila set DNS records berikut.',
      dnsRecords: dnsRecords,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const FaIcon(FontAwesomeIcons.globe, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Domain Management',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                      Text('${_domainList.length} domain aktif',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showAddDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        FaIcon(FontAwesomeIcons.plus, size: 11, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 6),
                        Text('Tambah', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_domainList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    FaIcon(FontAwesomeIcons.globe, size: 30, color: AppColors.textDim.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('Belum ada domain', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('Tekan "Tambah" untuk mula', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                  ],
                ),
              ),
            )
          else
            ..._domainList.map((item) => _buildDomainCard(item)),
        ],
      ),
    );
  }

  Widget _buildDomainCard(Map<String, dynamic> item) {
    final status = (item['domainStatus'] ?? '').toString();
    final isActive = status == 'ACTIVE';
    final domain = (item['domain'] ?? '').toString().replaceAll('https://', '');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((item['namaKedai'] ?? '').toString(), style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(domain, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF8B5CF6), fontWeight: FontWeight.w600)),
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
              Expanded(child: _actionBtn(FontAwesomeIcons.server, 'DNS', const Color(0xFF8B5CF6), () => _showSavedDns(item))),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(FontAwesomeIcons.rotate, 'Semak', const Color(0xFF10B981), () => _checkStatus(item))),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(FontAwesomeIcons.trash, 'Padam', AppColors.red, () => _deleteDomain(item))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}