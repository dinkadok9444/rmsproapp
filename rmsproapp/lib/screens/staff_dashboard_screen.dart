import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/repair_service.dart';
import '../services/supabase_client.dart';
import 'login_screen.dart';

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});
  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  final _authService = AuthService();
  final _searchCtrl = TextEditingController();

  String? _tenantId;
  String? _branchId;
  String _ownerID = '', _shopID = '', _staffName = '', _staffPhone = '';
  String _filterStatus = 'ALL';
  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  StreamSubscription? _sub;
  StreamSubscription? _komisyenSub;
  Color _themeColor = const Color(0xFF0D9488);

  // 0=Kerja, 1=Job Saya, 2=Sejarah, 3=Komisyen, 4=Profil
  int _currentTab = 0;

  // Komisyen data
  List<Map<String, dynamic>> _komisyenList = [];
  double _komisyenTotal = 0;
  double _komisyenPaid = 0;
  double _komisyenPending = 0;

  // Profile editing
  final _nameCtrl = TextEditingController();
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _profileLoading = false;
  Map<String, dynamic> _staffData = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _komisyenSub?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
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

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;

    final prefs = await SharedPreferences.getInstance();
    _staffName = prefs.getString('rms_staff_name') ?? 'STAF';
    _staffPhone = prefs.getString('rms_staff_phone') ?? '';

    try {
      if (_branchId != null) {
        final row = await _sb.from('branches').select('extras').eq('id', _branchId!).maybeSingle();
        final extras = (row?['extras'] is Map) ? Map<String, dynamic>.from(row!['extras']) : <String, dynamic>{};
        final hex = extras['themeColor'] as String?;
        if (hex != null && hex.isNotEmpty) {
          _themeColor = Color(int.parse(hex.replaceFirst('#', '0xFF')));
        }
      }
    } catch (_) {}
    _listenRepairs();
    _listenKomisyen();
    _loadStaffProfile();
  }

  void _listenRepairs() {
    if (_branchId == null) return;
    _sub = _sb
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = <Map<String, dynamic>>[];
      for (final r in rows) {
        final nama = (r['nama'] ?? '').toString().toUpperCase();
        final jenis = (r['jenis_servis'] ?? '').toString().toUpperCase();
        if (nama == 'JUALAN PANTAS' || jenis == 'JUALAN') continue;
        final ui = Map<String, dynamic>.from(r);
        ui['timestamp'] = _tsFromIso(r['created_at']);
        list.add(ui);
      }
      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      if (mounted) setState(() { _allData = list; _applyFilters(); });
    });
  }

  void _listenKomisyen() {
    final cleanPhone = _staffPhone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleanPhone.isEmpty || _branchId == null) return;
    _komisyenSub = _sb
        .from('staff_commissions')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = <Map<String, dynamic>>[];
      double total = 0, paid = 0, pending = 0;
      for (final r in rows) {
        final d = <String, dynamic>{
          'docId': r['id'],
          'staffPhone': r['staff_phone'] ?? '',
          'staffName': r['staff_name'] ?? '',
          'amount': r['amount'] ?? 0,
          'status': r['status'] ?? 'PENDING',
          'siri': r['siri'] ?? '',
          'kind': r['kind'] ?? '',
          'timestamp': _tsFromIso(r['created_at']),
        };
        final staffPhone = d['staffPhone'].toString().replaceAll(RegExp(r'[\s\-()]'), '');
        final staffNameDoc = d['staffName'].toString().toUpperCase();
        if (staffPhone == cleanPhone || staffNameDoc == _staffName.toUpperCase()) {
          list.add(d);
          final amt = (d['amount'] is num) ? (d['amount'] as num).toDouble() : double.tryParse(d['amount']?.toString() ?? '0') ?? 0;
          total += amt;
          if (d['status'].toString().toUpperCase() == 'PAID') {
            paid += amt;
          } else {
            pending += amt;
          }
        }
      }
      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      if (mounted) {
        setState(() {
          _komisyenList = list;
          _komisyenTotal = total;
          _komisyenPaid = paid;
          _komisyenPending = pending;
        });
      }
    });
  }

  Future<void> _loadStaffProfile() async {
    if (_staffPhone.isEmpty) return;
    final cleanPhone = _staffPhone.replaceAll(RegExp(r'[\s\-()]'), '');
    try {
      final row = await _sb.from('global_staff').select().eq('tel', cleanPhone).maybeSingle();
      if (row != null) {
        final payload = (row['payload'] is Map) ? Map<String, dynamic>.from(row['payload']) : <String, dynamic>{};
        _staffData = {
          'name': row['nama'] ?? '',
          'phone': row['tel'] ?? '',
          'role': row['role'] ?? '',
          'pin': payload['pin'] ?? '',
          'status': payload['status'] ?? 'active',
        };
        _nameCtrl.text = _staffData['name'] ?? '';
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _updateJobBySiri(String siri, Map<String, dynamic> updates) async {
    if (_branchId == null) return;
    await _sb.from('jobs').update(updates).eq('branch_id', _branchId!).eq('siri', siri);
  }

  Future<void> _addTimeline(String siri, String status) async {
    if (_branchId == null || _tenantId == null) return;
    try {
      final jobRow = await _sb.from('jobs').select('id').eq('branch_id', _branchId!).eq('siri', siri).maybeSingle();
      if (jobRow == null) return;
      await _sb.from('job_timeline').insert({
        'tenant_id': _tenantId,
        'job_id': jobRow['id'],
        'status': status,
        'note': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
        'by_user': _staffName.toUpperCase(),
      });
    } catch (_) {}
  }

  void _applyFilters() {
    var data = List<Map<String, dynamic>>.from(_allData);
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      data = data.where((d) =>
        (d['siri'] ?? '').toString().toLowerCase().contains(q) ||
        (d['nama'] ?? '').toString().toLowerCase().contains(q) ||
        (d['tel'] ?? '').toString().toLowerCase().contains(q)
      ).toList();
    }
    if (_currentTab == 0) {
      // Active jobs: exclude COMPLETED and CANCEL/REJECT
      data = data.where((d) {
        final s = (d['status'] ?? '').toString().toUpperCase();
        return s != 'COMPLETED' && s != 'CANCEL' && s != 'REJECT';
      }).toList();
      if (_filterStatus != 'ALL') {
        data = data.where((d) => (d['status'] ?? '').toString().toUpperCase() == _filterStatus).toList();
      }
    } else if (_currentTab == 1) {
      // My Jobs: only jobs assigned to me (active)
      data = data.where((d) {
        final s = (d['status'] ?? '').toString().toUpperCase();
        final repair = (d['staff_repair'] ?? '').toString().toUpperCase();
        return repair == _staffName.toUpperCase() && s != 'COMPLETED' && s != 'CANCEL' && s != 'REJECT';
      }).toList();
      if (_filterStatus != 'ALL') {
        data = data.where((d) => (d['status'] ?? '').toString().toUpperCase() == _filterStatus).toList();
      }
    } else if (_currentTab == 2) {
      // History: COMPLETED, CANCEL, REJECT
      data = data.where((d) {
        final s = (d['status'] ?? '').toString().toUpperCase();
        return s == 'COMPLETED' || s == 'CANCEL' || s == 'REJECT';
      }).toList();
    }
    _filteredData = data;
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN PROGRESS': return const Color(0xFF60A5FA);
      case 'WAITING PART': return AppColors.yellow;
      case 'READY TO PICKUP': return const Color(0xFFA78BFA);
      case 'COMPLETED': return AppColors.green;
      case 'CANCEL': case 'REJECT': return AppColors.red;
      default: return AppColors.textDim;
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toUpperCase()) {
      case 'IN PROGRESS': return FontAwesomeIcons.wrench;
      case 'WAITING PART': return FontAwesomeIcons.clock;
      case 'READY TO PICKUP': return FontAwesomeIcons.boxOpen;
      case 'COMPLETED': return FontAwesomeIcons.circleCheck;
      case 'CANCEL': case 'REJECT': return FontAwesomeIcons.ban;
      default: return FontAwesomeIcons.circle;
    }
  }

  String _fmt(dynamic ts) {
    if (ts is int && ts > 0) return DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts));
    return ts?.toString().split('T').first ?? '-';
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _formatWaTel(String tel) {
    var n = tel.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('0')) n = '6$n';
    if (!n.startsWith('6')) n = '60$n';
    return n;
  }

  // ── Update status ──
  Future<void> _updateStatus(String siri, String newStatus, {Map<String, dynamic>? job}) async {
    final now = DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now());
    final updates = <String, dynamic>{'status': newStatus};
    if (newStatus == 'READY TO PICKUP' || newStatus == 'COMPLETED') {
      updates['tarikh_siap'] = now;
    }
    if (newStatus == 'COMPLETED') {
      updates['tarikh_pickup'] = now;
    }
    await _updateJobBySiri(siri, updates);
    await _addTimeline(siri, newStatus);
    _snack('Status #$siri -> $newStatus');
  }

  // ── Take job & go to My Job tab ──
  Future<void> _takeJob(String siri) async {
    await _updateJobBySiri(siri, {'staff_repair': _staffName.toUpperCase()});
    try {
      if (_tenantId != null) {
        await _sb.from('staff_logs').insert({
          'tenant_id': _tenantId,
          'branch_id': _branchId,
          'staff_name': _staffName.toUpperCase(),
          'staff_phone': _staffPhone,
          'action': 'AMBIL JOB',
          'aktiviti': 'Ambil job #$siri',
          'siri': siri,
        });
      }
    } catch (_) {}
    _snack('Job #$siri diambil! Lihat di Job Saya.');
    // Switch to My Job tab
    setState(() {
      _currentTab = 1;
      _searchCtrl.clear();
      _filterStatus = 'ALL';
      _applyFilters();
    });
  }

  // ── Update phone ──
  void _showEditPhoneModal(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '';
    final telCtrl = TextEditingController(text: job['tel'] ?? '');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.phone, size: 14, color: AppColors.blue),
            const SizedBox(width: 8),
            Text('KEMASKINI TELEFON - #$siri', style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: telCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '011...',
              prefixIcon: const Icon(Icons.phone, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () async {
              final newTel = telCtrl.text.trim();
              if (newTel.isEmpty) { _snack('Sila isi no telefon', err: true); return; }
              await _updateJobBySiri(siri, {'tel': newTel});
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Telefon #$siri dikemaskini');
            },
            icon: const FaIcon(FontAwesomeIcons.check, size: 12),
            label: const Text('SIMPAN'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ),
    );
  }

  // ── Change status modal ──
  void _showStatusModal(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '';
    final current = (job['status'] ?? 'IN PROGRESS').toString().toUpperCase();
    final allStatuses = ['IN PROGRESS', 'WAITING PART', 'READY TO PICKUP', 'COMPLETED', 'CANCEL', 'REJECT'];
    final statusOrder = {'IN PROGRESS': 0, 'WAITING PART': 1, 'READY TO PICKUP': 2, 'COMPLETED': 3, 'CANCEL': 4, 'REJECT': 5};
    final currentLevel = statusOrder[current] ?? 0;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            FaIcon(FontAwesomeIcons.arrowsRotate, size: 14, color: _themeColor),
            const SizedBox(width: 8),
            Text('TUKAR STATUS - #$siri', style: TextStyle(color: _themeColor, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          Text('Status semasa: $current', style: const TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          ...allStatuses.map((s) {
            final sLevel = statusOrder[s] ?? 0;
            final isPast = sLevel < currentLevel && s != 'CANCEL' && s != 'REJECT';
            final isCurrent = s == current;
            final color = _statusColor(s);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (isPast || isCurrent) ? null : () async {
                    Navigator.pop(ctx);
                    await _updateStatus(siri, s, job: job);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      color: isCurrent ? color.withValues(alpha: 0.15) : isPast ? AppColors.bg : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isCurrent ? color : isPast ? AppColors.border : AppColors.borderMed),
                    ),
                    child: Row(children: [
                      FaIcon(
                        isCurrent ? FontAwesomeIcons.circleCheck : isPast ? FontAwesomeIcons.ban : FontAwesomeIcons.circle,
                        size: 14, color: isCurrent ? color : isPast ? AppColors.textDim : color,
                      ),
                      const SizedBox(width: 10),
                      Text(s, style: TextStyle(
                        color: isPast ? AppColors.textDim : color,
                        fontSize: 12, fontWeight: FontWeight.w800,
                        decoration: isPast ? TextDecoration.lineThrough : null,
                      )),
                      if (isCurrent) ...[
                        const Spacer(),
                        Text('SEMASA', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
                      ],
                    ]),
                  ),
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }

  // ─��� Job detail modal ──
  void _showJobDetail(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '-';
    final status = (job['status'] ?? 'IN PROGRESS').toString().toUpperCase();
    final color = _statusColor(status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.borderMed, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
                child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
              const Spacer(),
              Text('#$siri', style: TextStyle(color: _themeColor, fontSize: 18, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 6),
            // Staff repair tag
            if ((job['staff_repair'] ?? '').toString().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _themeColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _themeColor.withValues(alpha: 0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(FontAwesomeIcons.userGear, size: 10, color: _themeColor),
                  const SizedBox(width: 6),
                  Text('Technician: ${job['staff_repair']}', style: TextStyle(color: _themeColor, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
              ),
            const SizedBox(height: 12),
            _detailRow('Pelanggan', (job['nama'] ?? '-').toString().toUpperCase(), FontAwesomeIcons.user),
            _detailRow('Telefon', job['tel'] ?? '-', FontAwesomeIcons.phone),
            _detailRow('Model', job['model'] ?? '-', FontAwesomeIcons.mobileScreenButton),
            _detailRow('Kerosakan', job['kerosakan'] ?? '-', FontAwesomeIcons.screwdriverWrench),
            _detailRow('Tarikh Masuk', _fmt(job['timestamp']), FontAwesomeIcons.calendar),
            _detailRow('Staff Terima', job['staff_terima'] ?? '-', FontAwesomeIcons.userCheck),
            _detailRow('Staff Repair', job['staff_repair'] ?? '-', FontAwesomeIcons.userGear),
            _detailRow('Jenis Servis', job['jenis_servis'] ?? '-', FontAwesomeIcons.tags),
            _detailRow('Password', job['password'] ?? 'Tiada', FontAwesomeIcons.lock),
            const Divider(height: 24),
            _detailRow('Harga', 'RM ${job['harga'] ?? '0'}', FontAwesomeIcons.tag),
            _detailRow('Deposit', 'RM ${job['deposit'] ?? '0'}', FontAwesomeIcons.moneyBill),
            _detailRow('Baki', 'RM ${job['total'] ?? '0'}', FontAwesomeIcons.calculator),
            _detailRow('Status Bayaran', job['payment_status'] ?? 'UNPAID', FontAwesomeIcons.creditCard),
            if (job['catatan'] != null && job['catatan'].toString().isNotEmpty) ...[
              const Divider(height: 24),
              _detailRow('Catatan', job['catatan'], FontAwesomeIcons.noteSticky),
            ],
            if (job['items_array'] != null && (job['items_array'] as List).isNotEmpty) ...[
              const Divider(height: 24),
              const Text('ITEM / KEROSAKAN', style: TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ...(job['items_array'] as List).map((item) {
                final nama = item['nama'] ?? '-';
                final qty = item['qty'] ?? 1;
                final harga = (item['harga'] is num) ? (item['harga'] as num).toStringAsFixed(2) : '0.00';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Expanded(child: Text(nama, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSub))),
                    Text('x$qty', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(width: 10),
                    Text('RM $harga', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _themeColor)),
                  ]),
                );
              }),
            ],
            const SizedBox(height: 20),
            Row(children: [
              if (status != 'COMPLETED' && status != 'CANCEL' && status != 'REJECT') ...[
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _showStatusModal(job); },
                  icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 12),
                  label: const Text('TUKAR STATUS', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                )),
                const SizedBox(width: 8),
                if ((job['staff_repair'] ?? '').toString().isEmpty)
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () async { Navigator.pop(ctx); await _takeJob(siri); },
                    icon: const FaIcon(FontAwesomeIcons.handPointer, size: 12),
                    label: const Text('AMBIL JOB', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  )),
              ],
            ]),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () {
                final waUrl = 'https://wa.me/${_formatWaTel(job['tel'] ?? '')}';
                launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
              },
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 14, color: Color(0xFF25D366)),
              label: const Text('WHATSAPP PELANGGAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF25D366), padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFF25D366))),
            )),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FaIcon(icon, size: 11, color: AppColors.textDim),
      const SizedBox(width: 10),
      SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w900))),
      Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );

  // ── Save Profile ──
  Future<void> _saveProfile() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) { _snack('Sila isi nama', err: true); return; }
    setState(() => _profileLoading = true);
    final cleanPhone = _staffPhone.replaceAll(RegExp(r'[\s\-()]'), '');
    try {
      await _sb.from('global_staff').update({'nama': newName}).eq('tel', cleanPhone);
      if (_branchId != null) {
        await _sb.from('branch_staff').update({'nama': newName}).eq('branch_id', _branchId!).eq('phone', cleanPhone);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rms_staff_name', newName);
      _staffName = newName;
      _snack('Profil berjaya dikemaskini');
    } catch (e) {
      _snack('Gagal kemaskini: $e', err: true);
    }
    setState(() => _profileLoading = false);
  }

  // ── Change PIN ──
  Future<void> _changePin() async {
    final oldPin = _oldPinCtrl.text.trim();
    final newPin = _newPinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();

    if (oldPin.isEmpty || newPin.isEmpty || confirmPin.isEmpty) {
      _snack('Sila isi semua ruangan PIN', err: true); return;
    }
    if (newPin.length < 4) {
      _snack('PIN baru mesti sekurang-kurangnya 4 digit', err: true); return;
    }
    if (newPin != confirmPin) {
      _snack('PIN baru tidak sepadan', err: true); return;
    }
    if ((_staffData['pin'] ?? '') != oldPin) {
      _snack('PIN lama salah', err: true); return;
    }

    setState(() => _profileLoading = true);
    final cleanPhone = _staffPhone.replaceAll(RegExp(r'[\s\-()]'), '');
    try {
      final existing = await _sb.from('global_staff').select('payload').eq('tel', cleanPhone).maybeSingle();
      final payload = (existing?['payload'] is Map) ? Map<String, dynamic>.from(existing!['payload']) : <String, dynamic>{};
      payload['pin'] = newPin;
      await _sb.from('global_staff').update({'payload': payload}).eq('tel', cleanPhone);
      if (_branchId != null) {
        await _sb.from('branch_staff').update({'pin': newPin}).eq('branch_id', _branchId!).eq('phone', cleanPhone);
      }
      _staffData['pin'] = newPin;
      _oldPinCtrl.clear();
      _newPinCtrl.clear();
      _confirmPinCtrl.clear();
      _snack('PIN berjaya ditukar');
    } catch (e) {
      _snack('Gagal tukar PIN: $e', err: true);
    }
    setState(() => _profileLoading = false);
  }

  // ═══════════════════════════════════════════
  // BUILD
  // ═════��═════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final darkerTheme = HSLColor.fromColor(_themeColor).withLightness(0.25).toColor();
    Widget body;
    switch (_currentTab) {
      case 0: body = _buildActiveJobs(); break;
      case 1: body = _buildMyJobs(); break;
      case 2: body = _buildHistory(); break;
      case 3: body = _buildKomisyen(); break;
      default: body = _buildProfile();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        _buildHeader(darkerTheme),
        Expanded(child: body),
      ]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader(Color darkerTheme) {
    final titles = ['KERJA MASUK', 'JOB SAYA', 'SEJARAH REPAIR', 'KOMISYEN', 'PROFIL SAYA'];
    final icons = [FontAwesomeIcons.briefcase, FontAwesomeIcons.screwdriverWrench, FontAwesomeIcons.clockRotateLeft, FontAwesomeIcons.coins, FontAwesomeIcons.userPen];
    final showSearch = _currentTab <= 2;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [darkerTheme, _themeColor, _themeColor.withValues(alpha: 0.85)]),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: _themeColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: FaIcon(icons[_currentTab], size: 14, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titles[_currentTab], style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  Text(_staffName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                ]),
              ]),
              GestureDetector(
                onTap: _logout,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: const FaIcon(FontAwesomeIcons.rightFromBracket, size: 14, color: Colors.white),
                ),
              ),
            ]),
            if (showSearch) ...[
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() => _applyFilters()),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Cari siri / nama / telefon...',
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 12),
                    prefixIcon: Icon(Icons.search, color: Colors.white54, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // TAB 0 - KERJA MASUK (All active jobs)
  // ══════════���════════════════════��═══════════
  Widget _buildActiveJobs() {
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          for (final s in ['ALL', 'IN PROGRESS', 'WAITING PART', 'READY TO PICKUP'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() { _filterStatus = s; _applyFilters(); }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filterStatus == s ? _themeColor : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filterStatus == s ? _themeColor : AppColors.borderMed),
                  ),
                  child: Text(s == 'ALL' ? 'Semua' : s,
                    style: TextStyle(color: _filterStatus == s ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
      ),
      _buildStatsBar(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('${_filteredData.length} rekod aktif', style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700))),
      ),
      Expanded(child: _buildJobList()),
    ]);
  }

  Widget _buildStatsBar() {
    final activeJobs = _allData.where((d) {
      final s = (d['status'] ?? '').toString().toUpperCase();
      return s != 'COMPLETED' && s != 'CANCEL' && s != 'REJECT';
    }).toList();
    final myJobs = activeJobs.where((d) => (d['staff_repair'] ?? '').toString().toUpperCase() == _staffName.toUpperCase()).length;
    final unassigned = activeJobs.where((d) => (d['staff_repair'] ?? '').toString().isEmpty).length;
    final inProgress = activeJobs.where((d) => (d['status'] ?? '').toString().toUpperCase() == 'IN PROGRESS').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        _statChip('Job Saya', '$myJobs', _themeColor),
        const SizedBox(width: 6),
        _statChip('Belum Diambil', '$unassigned', AppColors.orange),
        const SizedBox(width: 6),
        _statChip('In Progress', '$inProgress', AppColors.blue),
      ]),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 8, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _buildJobList() {
    if (_allData.isEmpty) return Center(child: CircularProgressIndicator(color: _themeColor));
    if (_filteredData.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(FontAwesomeIcons.folderOpen, size: 40, color: AppColors.textDim),
        const SizedBox(height: 12),
        const Text('Tiada rekod dijumpai', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredData.length,
      itemBuilder: (_, i) => _buildJobCard(_filteredData[i]),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final siri = job['siri'] ?? '-';
    final nama = job['nama'] ?? '-';
    final tel = job['tel'] ?? '-';
    final model = job['model'] ?? '-';
    final kerosakan = job['kerosakan'] ?? '-';
    final status = (job['status'] ?? 'IN PROGRESS').toString().toUpperCase();
    final tarikh = _fmt(job['timestamp']);
    final color = _statusColor(status);
    final staffRepair = (job['staff_repair'] ?? '').toString();
    final isMyJob = staffRepair.toUpperCase() == _staffName.toUpperCase();
    final isUnassigned = staffRepair.isEmpty;

    return GestureDetector(
      onTap: () => _showJobDetail(job),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isMyJob ? _themeColor.withValues(alpha: 0.4) : AppColors.borderMed),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 3)),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Text('#$siri', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Text(tarikh, style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
              GestureDetector(
                onTap: () => _showStatusModal(job),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FaIcon(_statusIcon(status), size: 9, color: color),
                    const SizedBox(width: 4),
                    Text(status, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 4),
                    FaIcon(FontAwesomeIcons.chevronDown, size: 8, color: color),
                  ]),
                ),
              ),
            ]),
          ),
          // Assigned tag
          if (isMyJob)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
              color: _themeColor.withValues(alpha: 0.08),
              child: Row(children: [
                FaIcon(FontAwesomeIcons.userCheck, size: 9, color: _themeColor),
                const SizedBox(width: 6),
                Text('JOB ANDA', style: TextStyle(color: _themeColor, fontSize: 9, fontWeight: FontWeight.w900)),
              ]),
            )
          else if (!isUnassigned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
              color: AppColors.blue.withValues(alpha: 0.05),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.userGear, size: 9, color: AppColors.blue),
                const SizedBox(width: 6),
                Text('Technician: $staffRepair', style: const TextStyle(color: AppColors.blue, fontSize: 9, fontWeight: FontWeight.w800)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: Column(children: [
              _cardRow('Pelanggan', nama, FontAwesomeIcons.user),
              _cardRow('Model', model, FontAwesomeIcons.mobileScreenButton),
              _cardRow('Kerosakan', kerosakan, FontAwesomeIcons.screwdriverWrench),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const FaIcon(FontAwesomeIcons.phone, size: 10, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  const SizedBox(width: 70, child: Text('Telefon', style: TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900))),
                  Expanded(child: Text(tel, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600))),
                  GestureDetector(
                    onTap: () => _showEditPhoneModal(job),
                    child: Container(
                      padding: const EdgeInsets.all(4), margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                      child: const FaIcon(FontAwesomeIcons.penToSquare, size: 10, color: AppColors.blue),
                    ),
                  ),
                  GestureDetector(
                    onTap: () { launchUrl(Uri.parse('https://wa.me/${_formatWaTel(tel)}'), mode: LaunchMode.externalApplication); },
                    child: const FaIcon(FontAwesomeIcons.whatsapp, size: 14, color: Color(0xFF25D366)),
                  ),
                ]),
              ),
            ]),
          ),
          // Quick actions
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              if (isUnassigned)
                _actBtn('Ambil Job', FontAwesomeIcons.handPointer, AppColors.blue, () => _takeJob(siri)),
              if (!isUnassigned && (status == 'IN PROGRESS' || status == 'WAITING PART'))
                _actBtn('Ready', FontAwesomeIcons.check, AppColors.green, () => _updateStatus(siri, 'READY TO PICKUP', job: job)),
              if (status == 'READY TO PICKUP')
                _actBtn('Selesai', FontAwesomeIcons.circleCheck, AppColors.green, () => _updateStatus(siri, 'COMPLETED', job: job)),
              const Spacer(),
              _actBtn('Tukar Status', FontAwesomeIcons.arrowsRotate, _themeColor, () => _showStatusModal(job)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cardRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      FaIcon(icon, size: 10, color: AppColors.textDim),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900))),
      Expanded(child: Text(value, style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _actBtn(String label, IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  // ═══════════════════════════════════════════
  // TAB 1 - JOB SAYA (My assigned jobs)
  // ══════════���════════════════════════════════
  Widget _buildMyJobs() {
    return Column(children: [
      // Filter chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          for (final s in ['ALL', 'IN PROGRESS', 'WAITING PART', 'READY TO PICKUP'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() { _filterStatus = s; _applyFilters(); }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filterStatus == s ? _themeColor : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filterStatus == s ? _themeColor : AppColors.borderMed),
                  ),
                  child: Text(s == 'ALL' ? 'Semua' : s,
                    style: TextStyle(color: _filterStatus == s ? Colors.white : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
      ),
      // My job count
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _themeColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _themeColor.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            FaIcon(FontAwesomeIcons.screwdriverWrench, size: 14, color: _themeColor),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_filteredData.length} job ditugaskan kepada anda', style: TextStyle(color: _themeColor, fontSize: 11, fontWeight: FontWeight.w800)),
              Text('Semua job yang anda ambil akan muncul di sini', style: TextStyle(color: _themeColor.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
      ),
      // Job list - reuse same card builder
      Expanded(
        child: _filteredData.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.clipboardList, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              const Text('Belum ada job diambil', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() { _currentTab = 0; _filterStatus = 'ALL'; _searchCtrl.clear(); _applyFilters(); }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.blue.withValues(alpha: 0.3))),
                  child: const Text('Pergi ke Kerja Masuk', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filteredData.length,
              itemBuilder: (_, i) => _buildJobCard(_filteredData[i]),
            ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════
  // TAB 2 - SEJARAH
  // ═════���═══════════���═════════════════════════
  Widget _buildHistory() {
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          for (final s in ['COMPLETED', 'CANCEL', 'REJECT'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _statusColor(s).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor(s).withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(_statusIcon(s), size: 10, color: _statusColor(s)),
                  const SizedBox(width: 6),
                  Text(s, style: TextStyle(color: _statusColor(s), fontSize: 10, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Text(
                    '${_allData.where((d) => (d['status'] ?? '').toString().toUpperCase() == s).length}',
                    style: TextStyle(color: _statusColor(s), fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('${_filteredData.length} rekod sejarah', style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700))),
      ),
      Expanded(
        child: _filteredData.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              const Text('Tiada sejarah', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filteredData.length,
              itemBuilder: (_, i) {
                final job = _filteredData[i];
                final siri = job['siri'] ?? '-';
                final nama = job['nama'] ?? '-';
                final model = job['model'] ?? '-';
                final status = (job['status'] ?? '').toString().toUpperCase();
                final color = _statusColor(status);
                final tarikh = _fmt(job['timestamp']);
                final harga = job['harga'] ?? '0';

                return GestureDetector(
                  onTap: () => _showJobDetail(job),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Center(child: FaIcon(_statusIcon(status), size: 16, color: color)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('#$siri', style: TextStyle(color: _themeColor, fontSize: 12, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text(status, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text('$nama  |  $model', style: const TextStyle(color: AppColors.textSub, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(tarikh, style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w600)),
                      ])),
                      Text('RM $harga', style: TextStyle(color: _themeColor, fontSize: 13, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                );
              },
            ),
      ),
    ]);
  }

  // ══════════���════════════════════════════════
  // TAB 3 - KOMISYEN
  // ═════════════════���═════════════════════════
  Widget _buildKomisyen() {
    return Column(children: [
      // Summary cards
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Row(children: [
          _komisyenStat('Jumlah', 'RM ${_komisyenTotal.toStringAsFixed(2)}', _themeColor),
          const SizedBox(width: 6),
          _komisyenStat('Dibayar', 'RM ${_komisyenPaid.toStringAsFixed(2)}', AppColors.green),
          const SizedBox(width: 6),
          _komisyenStat('Belum Bayar', 'RM ${_komisyenPending.toStringAsFixed(2)}', AppColors.orange),
        ]),
      ),
      // Info note
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            const FaIcon(FontAwesomeIcons.circleInfo, size: 12, color: AppColors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Komisyen ditetapkan oleh Supervisor. Hubungi Supervisor untuk sebarang pertanyaan.',
              style: TextStyle(color: AppColors.blue.withValues(alpha: 0.8), fontSize: 9, fontWeight: FontWeight.w600),
            )),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('${_komisyenList.length} rekod komisyen', style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700))),
      ),
      // List
      Expanded(
        child: _komisyenList.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const FaIcon(FontAwesomeIcons.coins, size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              const Text('Tiada rekod komisyen', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Komisyen akan muncul bila Supervisor tetapkan', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _komisyenList.length,
              itemBuilder: (_, i) {
                final k = _komisyenList[i];
                final amt = (k['amount'] is num) ? (k['amount'] as num).toDouble() : double.tryParse(k['amount']?.toString() ?? '0') ?? 0;
                final isPaid = (k['status'] ?? '').toString().toUpperCase() == 'PAID';
                final siri = k['siri'] ?? '-';
                final note = k['note'] ?? k['catatan'] ?? '';
                final tarikh = _fmt(k['timestamp']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isPaid ? AppColors.green.withValues(alpha: 0.3) : AppColors.orange.withValues(alpha: 0.3)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: isPaid ? AppColors.green.withValues(alpha: 0.12) : AppColors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: FaIcon(
                        isPaid ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.hourglass,
                        size: 16, color: isPaid ? AppColors.green : AppColors.orange,
                      )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        if (siri != '-') Text('Job #$siri', style: TextStyle(color: _themeColor, fontSize: 12, fontWeight: FontWeight.w900)),
                        if (siri != '-') const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPaid ? AppColors.green.withValues(alpha: 0.12) : AppColors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(isPaid ? 'DIBAYAR' : 'BELUM BAYAR',
                            style: TextStyle(color: isPaid ? AppColors.green : AppColors.orange, fontSize: 8, fontWeight: FontWeight.w900)),
                        ),
                      ]),
                      if (note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(note, style: const TextStyle(color: AppColors.textSub, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      const SizedBox(height: 2),
                      Text(tarikh, style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w600)),
                    ])),
                    Text('RM ${amt.toStringAsFixed(2)}',
                      style: TextStyle(color: isPaid ? AppColors.green : AppColors.orange, fontSize: 15, fontWeight: FontWeight.w900)),
                  ]),
                );
              },
            ),
      ),
    ]);
  }

  Widget _komisyenStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 8, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // TAB 4 - PROFIL
  // ��═════════════��════════════════════════════
  Widget _buildProfile() {
    final totalJobs = _allData.where((d) => (d['staff_repair'] ?? '').toString().toUpperCase() == _staffName.toUpperCase()).length;
    final completedJobs = _allData.where((d) =>
      (d['staff_repair'] ?? '').toString().toUpperCase() == _staffName.toUpperCase() &&
      (d['status'] ?? '').toString().toUpperCase() == 'COMPLETED'
    ).length;
    final activeJobs = _allData.where((d) {
      final s = (d['status'] ?? '').toString().toUpperCase();
      return (d['staff_repair'] ?? '').toString().toUpperCase() == _staffName.toUpperCase() &&
        s != 'COMPLETED' && s != 'CANCEL' && s != 'REJECT';
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(color: _themeColor.withValues(alpha: 0.12), shape: BoxShape.circle,
                border: Border.all(color: _themeColor.withValues(alpha: 0.3), width: 2)),
              child: Center(child: Text(
                _staffName.isNotEmpty ? _staffName[0].toUpperCase() : 'S',
                style: TextStyle(color: _themeColor, fontSize: 28, fontWeight: FontWeight.w900),
              )),
            ),
            const SizedBox(height: 12),
            Text(_staffName.toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(_staffPhone, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _staffData['status'] == 'suspended' ? AppColors.red.withValues(alpha: 0.12) : AppColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _staffData['status'] == 'suspended' ? 'DIGANTUNG' : 'AKTIF',
                style: TextStyle(color: _staffData['status'] == 'suspended' ? AppColors.red : AppColors.green, fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 4),
            Text('Cawangan: $_shopID', style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _profileStat('Jumlah Job', '$totalJobs', _themeColor),
          const SizedBox(width: 8),
          _profileStat('Selesai', '$completedJobs', AppColors.green),
          const SizedBox(width: 8),
          _profileStat('Aktif', '$activeJobs', AppColors.blue),
        ]),
        const SizedBox(height: 20),
        // Edit name
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              FaIcon(FontAwesomeIcons.userPen, size: 13, color: _themeColor),
              const SizedBox(width: 8),
              Text('KEMASKINI NAMA', style: TextStyle(color: _themeColor, fontSize: 12, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(labelText: 'Nama Staf', prefixIcon: const Icon(Icons.person, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _profileLoading ? null : _saveProfile,
              icon: _profileLoading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
              label: const Text('SIMPAN NAMA'),
              style: ElevatedButton.styleFrom(backgroundColor: _themeColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        // Change PIN
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              FaIcon(FontAwesomeIcons.key, size: 13, color: AppColors.orange),
              SizedBox(width: 8),
              Text('TUKAR PIN', style: TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _oldPinCtrl, obscureText: true, keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(labelText: 'PIN Lama', prefixIcon: const Icon(Icons.lock_outline, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 10),
            TextField(controller: _newPinCtrl, obscureText: true, keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(labelText: 'PIN Baru', prefixIcon: const Icon(Icons.lock, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 10),
            TextField(controller: _confirmPinCtrl, obscureText: true, keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(labelText: 'Sahkan PIN Baru', prefixIcon: const Icon(Icons.lock_clock, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _profileLoading ? null : _changePin,
              icon: _profileLoading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const FaIcon(FontAwesomeIcons.key, size: 12),
              label: const Text('TUKAR PIN'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _logout,
          icon: const FaIcon(FontAwesomeIcons.rightFromBracket, size: 13, color: AppColors.red),
          label: const Text('LOG KELUAR', style: TextStyle(fontWeight: FontWeight.w900)),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red),
            padding: const EdgeInsets.symmetric(vertical: 14)),
        )),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _profileStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  // ════════════════════��══════════════════════
  // BOTTOM NAV - 5 tabs
  // ═══════════════════════════════════════════
  Widget _buildBottomNav() {
    // Badge count for My Job
    final myJobCount = _allData.where((d) {
      final s = (d['status'] ?? '').toString().toUpperCase();
      final repair = (d['staff_repair'] ?? '').toString().toUpperCase();
      return repair == _staffName.toUpperCase() && s != 'COMPLETED' && s != 'CANCEL' && s != 'REJECT';
    }).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            _navItem(0, FontAwesomeIcons.briefcase, 'Kerja', 0),
            _navItem(1, FontAwesomeIcons.screwdriverWrench, 'Job Saya', myJobCount),
            _navItem(2, FontAwesomeIcons.clockRotateLeft, 'Sejarah', 0),
            _navItem(3, FontAwesomeIcons.coins, 'Komisyen', 0),
            _navItem(4, FontAwesomeIcons.userGear, 'Profil', 0),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, int badge) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentTab = index;
            _searchCtrl.clear();
            _filterStatus = 'ALL';
            _applyFilters();
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? _themeColor.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: FaIcon(icon, size: 15, color: isActive ? _themeColor : AppColors.textDim),
              ),
              if (badge > 0)
                Positioned(
                  top: -2, right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5)),
                    child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(
            color: isActive ? _themeColor : AppColors.textDim,
            fontSize: 8, fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
          )),
        ]),
      ),
    );
  }
}
