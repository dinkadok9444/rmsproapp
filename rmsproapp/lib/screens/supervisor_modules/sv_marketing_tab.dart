import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/repair_service.dart';
import '../../services/supabase_client.dart';
class SvMarketingTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvMarketingTab({required this.ownerID, required this.shopID});
  @override
  State<SvMarketingTab> createState() => SvMarketingTabState();
}

class SvMarketingTabState extends State<SvMarketingTab>
    with SingleTickerProviderStateMixin {
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  late TabController _tabCtrl;

  // Voucher list
  List<Map<String, dynamic>> _vouchers = [];
  StreamSubscription? _voucherSub;

  // Referral list
  List<Map<String, dynamic>> _referrals = [];
  StreamSubscription? _refSub;

  // Customer database (deduplicated from repairs)
  List<Map<String, dynamic>> _customers = [];
  StreamSubscription? _repairsSub;

  // Search
  final _custSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _init();
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
    _listen();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _voucherSub?.cancel();
    _refSub?.cancel();
    _repairsSub?.cancel();
    _custSearchCtrl.dispose();
    super.dispose();
  }

  void _listen() {
    if (_branchId == null) return;

    // Vouchers → shop_vouchers table
    _voucherSub = _sb
        .from('shop_vouchers')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>((r) => {
        'id': r['id'],
        'code': r['voucher_code'] ?? '',
        'value': r['value'] ?? 0,
        'limit': r['max_uses'] ?? 0,
        'claimed': r['used_amount'] ?? 0,
        'status': r['status'] ?? 'ACTIVE',
        'shopID': widget.shopID,
        'custNama': r['customer_name'] ?? '',
        'custTel': r['customer_phone'] ?? '',
        'siriAsal': r['origin_siri'] ?? '',
        'expiry': r['expiry'] ?? 'LIFETIME',
        'timestamp': _tsFromIso(r['created_at']),
      }).toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _vouchers = list);
    });

    // Referrals → referrals table (schema stash extras in created_by jsonb string)
    _refSub = _sb
        .from('referrals')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map<Map<String, dynamic>>((r) {
        Map<String, dynamic> extra = {};
        final cb = r['created_by'];
        if (cb is String && cb.isNotEmpty) {
          try { extra = Map<String, dynamic>.from(jsonDecode(cb) as Map); } catch (_) {}
        }
        return {
          'id': r['id'],
          'refCode': r['code'] ?? '',
          'nama': extra['nama'] ?? '',
          'tel': extra['tel'] ?? '',
          'siriAsal': extra['siriAsal'] ?? '',
          'shopID': widget.shopID,
          'status': r['active'] == true ? 'ACTIVE' : 'INACTIVE',
          'bank': extra['bank'] ?? '',
          'accNo': extra['accNo'] ?? '',
          'commission': extra['commission'] ?? 0,
          'timestamp': _tsFromIso(r['created_at']),
        };
      }).toList();
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() => _referrals = list);
    });

    // Customer list from jobs
    _repairsSub = _sb
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
          final all = <Map<String, dynamic>>[];
          for (final r in rows) {
            final d = Map<String, dynamic>.from(r);
            d['timestamp'] = _tsFromIso(r['created_at']);
            final nama = (d['nama'] ?? '').toString().toUpperCase();
            final jenis = (d['jenis_servis'] ?? '').toString().toUpperCase();
            if (nama == 'JUALAN PANTAS' || jenis == 'JUALAN') continue;
            all.add(d);
          }
          // Sort newest first
          all.sort(
            (a, b) => ((b['timestamp'] ?? 0) as num).compareTo(
              (a['timestamp'] ?? 0) as num,
            ),
          );
          // Deduplicate by tel — keep latest record per customer
          final seen = <String>{};
          final custs = <Map<String, dynamic>>[];
          for (final d in all) {
            final tel = (d['tel'] ?? '').toString().replaceAll(
              RegExp(r'\D'),
              '',
            );
            if (tel.isNotEmpty && seen.add(tel)) {
              // Count total repairs for this customer
              final totalRepairs = all
                  .where(
                    (r) =>
                        (r['tel'] ?? '').toString().replaceAll(
                          RegExp(r'\D'),
                          '',
                        ) ==
                        tel,
                  )
                  .length;
              custs.add({...d, '_totalRepairs': totalRepairs});
            }
          }
          if (mounted) setState(() => _customers = custs);
        });
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: err ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatWaTel(String tel) {
    var n = tel.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('0')) n = '6$n';
    if (!n.startsWith('6')) n = '60$n';
    return n;
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '-';
    if (ts is int)
      return DateFormat(
        'dd/MM/yyyy',
      ).format(DateTime.fromMillisecondsSinceEpoch(ts));
    return ts.toString();
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _tabCtrl,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.black,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'VOUCHER KEDAI'),
              Tab(text: 'VOUCHER CUST'),
              Tab(text: 'REFERRAL'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildVoucherKedaiTab(),
              _buildVoucherCustTab(),
              _buildReferralTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // TAB 1: VOUCHER KEDAI (Shop Voucher — bulk promo)
  // ═══════════════════════════════════════
  Widget _buildVoucherKedaiTab() {
    return Column(
      children: [
        // Create button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
              ),
              onPressed: _showCreateShopVoucher,
              icon: const FaIcon(FontAwesomeIcons.plus, size: 10),
              label: const Text(
                'JANA VOUCHER KEDAI',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child:
              _vouchers
                  .where((v) => (v['custTel'] ?? '').toString().isEmpty)
                  .toList()
                  .isEmpty
              ? const Center(
                  child: Text(
                    'Tiada voucher kedai.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _vouchers
                      .where((v) => (v['custTel'] ?? '').toString().isEmpty)
                      .length,
                  itemBuilder: (_, i) {
                    final v = _vouchers
                        .where((v) => (v['custTel'] ?? '').toString().isEmpty)
                        .toList()[i];
                    return _voucherCard(v);
                  },
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // TAB 2: VOUCHER PELANGGAN (Customer-specific)
  // ═══════════════════════════════════════
  Widget _buildVoucherCustTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
              ),
              onPressed: () => _showCustSearchModal('VOUCHER'),
              icon: const FaIcon(FontAwesomeIcons.ticket, size: 10),
              label: const Text(
                'JANA VOUCHER PELANGGAN',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              _vouchers
                  .where((v) => (v['custTel'] ?? '').toString().isNotEmpty)
                  .toList()
                  .isEmpty
              ? const Center(
                  child: Text(
                    'Tiada voucher pelanggan.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _vouchers
                      .where((v) => (v['custTel'] ?? '').toString().isNotEmpty)
                      .length,
                  itemBuilder: (_, i) {
                    final v = _vouchers
                        .where(
                          (v) => (v['custTel'] ?? '').toString().isNotEmpty,
                        )
                        .toList()[i];
                    return _voucherCard(v, showCust: true);
                  },
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // TAB 3: REFERRAL
  // ═══════════════════════════════════════
  Widget _buildReferralTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.black,
              ),
              onPressed: () => _showCustSearchModal('REFERRAL'),
              icon: const FaIcon(FontAwesomeIcons.userPlus, size: 10),
              label: const Text(
                'JANA REFERRAL',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _referrals.isEmpty
              ? const Center(
                  child: Text(
                    'Tiada referral.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _referrals.length,
                  itemBuilder: (_, i) => _referralCard(_referrals[i]),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // VOUCHER CARD WIDGET
  // ═══════════════════════════════════════
  Widget _voucherCard(Map<String, dynamic> v, {bool showCust = false}) {
    final code = v['code'] ?? '-';
    final value = double.tryParse(v['value']?.toString() ?? '0') ?? 0;
    final limit = v['limit'] ?? 0;
    final claimed = v['claimed'] ?? 0;
    final status = (v['status'] ?? 'ACTIVE').toString().toUpperCase();
    final expiry = v['expiry']?.toString() ?? '';
    final isLifetime = expiry.isEmpty || expiry == 'LIFETIME';
    final isActive = status == 'ACTIVE';
    final isExpired =
        !isLifetime &&
        DateTime.tryParse(expiry)?.isBefore(DateTime.now()) == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive && !isExpired
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.borderMed,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      (isActive && !isExpired ? AppColors.green : AppColors.red)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isExpired ? 'TAMAT' : status,
                  style: TextStyle(
                    color: isActive && !isExpired
                        ? AppColors.green
                        : AppColors.red,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'RM ${value.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _infoChip(FontAwesomeIcons.hashtag, 'Guna: $claimed/$limit'),
              const SizedBox(width: 8),
              _infoChip(
                FontAwesomeIcons.clock,
                isLifetime ? 'Lifetime' : 'Sah: $expiry',
              ),
            ],
          ),
          if (showCust && (v['custNama'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.user,
                  size: 9,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 6),
                Text(
                  '${v['custNama']} (${v['custTel'] ?? '-'})',
                  style: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _voucherActionBtn(
                'Hantar WA',
                FontAwesomeIcons.whatsapp,
                const Color(0xFF25D366),
                () => _sendVoucherWA(v),
              ),
              const SizedBox(width: 6),
              _voucherActionBtn(
                'Salin',
                FontAwesomeIcons.copy,
                AppColors.blue,
                () {
                  Clipboard.setData(ClipboardData(text: code));
                  _snack('Kod $code disalin');
                },
              ),
              const SizedBox(width: 6),
              _voucherActionBtn(
                'Padam',
                FontAwesomeIcons.trash,
                AppColors.red,
                () => _deleteVoucher(v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 8, color: AppColors.textDim),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _voucherActionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // REFERRAL CARD WIDGET
  // ═══════════════════════════════════════
  Widget _referralCard(Map<String, dynamic> r) {
    final code = r['refCode'] ?? '-';
    final nama = r['nama'] ?? '-';
    final tel = r['tel'] ?? '-';
    final status = (r['status'] ?? 'ACTIVE').toString().toUpperCase();
    final isActive = status == 'ACTIVE';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.green.withValues(alpha: 0.3)
              : AppColors.borderMed,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: (isActive ? AppColors.green : AppColors.red)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: isActive ? AppColors.green : AppColors.red,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.user,
                size: 9,
                color: AppColors.textDim,
              ),
              const SizedBox(width: 6),
              Text(
                nama,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              const FaIcon(
                FontAwesomeIcons.phone,
                size: 8,
                color: AppColors.textDim,
              ),
              const SizedBox(width: 4),
              Text(
                tel,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dijana: ${_fmtDate(r['timestamp'])}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 9),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _voucherActionBtn(
                'Hantar WA',
                FontAwesomeIcons.whatsapp,
                const Color(0xFF25D366),
                () => _sendReferralWA(r),
              ),
              const SizedBox(width: 6),
              _voucherActionBtn(
                'Salin',
                FontAwesomeIcons.copy,
                AppColors.blue,
                () {
                  Clipboard.setData(ClipboardData(text: code));
                  _snack('Kod $code disalin');
                },
              ),
              const SizedBox(width: 6),
              _voucherActionBtn(
                'Padam',
                FontAwesomeIcons.trash,
                AppColors.red,
                () => _deleteReferral(r),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // CREATE SHOP VOUCHER (Voucher Kedai)
  // ═══════════════════════════════════════
  void _showCreateShopVoucher() {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController(text: '5');
    final limitCtrl = TextEditingController(text: '100');
    String expiryType = 'LIFETIME'; // LIFETIME or DATE
    DateTime? expiryDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'JANA VOUCHER KEDAI',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Divider(color: AppColors.borderMed, height: 20),
                _dialogField(
                  'Kod (Kosong = Auto)',
                  codeCtrl,
                  'Cth: RAYA2026',
                  caps: true,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _dialogField(
                        'Nilai (RM)',
                        valueCtrl,
                        '5.00',
                        keyboard: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dialogField(
                        'Guna Berapa Kali',
                        limitCtrl,
                        '100',
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tempoh Sah',
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _expiryChip(
                      'LIFETIME',
                      'Lifetime',
                      expiryType,
                      (v) => setS(() {
                        expiryType = v;
                        expiryDate = null;
                      }),
                    ),
                    const SizedBox(width: 6),
                    _expiryChip('DATE', 'Sah Sehingga', expiryType, (v) async {
                      final d = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                        initialDate: DateTime.now().add(
                          const Duration(days: 30),
                        ),
                      );
                      if (d != null)
                        setS(() {
                          expiryType = 'DATE';
                          expiryDate = d;
                        });
                    }),
                  ],
                ),
                if (expiryType == 'DATE' && expiryDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Tamat: ${DateFormat('dd/MM/yyyy').format(expiryDate!)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      final val = double.tryParse(valueCtrl.text) ?? 0;
                      final limit = int.tryParse(limitCtrl.text) ?? 0;
                      if (val <= 0 || limit <= 0) {
                        _snack('Sila isi nilai dan kuota', err: true);
                        return;
                      }
                      final code = codeCtrl.text.trim().toUpperCase().isNotEmpty
                          ? codeCtrl.text.trim().toUpperCase()
                          : 'V-${Random().nextInt(999999).toString().padLeft(6, '0')}';
                      if (_tenantId == null || _branchId == null) return;
                      await _sb.from('shop_vouchers').insert({
                            'tenant_id': _tenantId,
                            'branch_id': _branchId,
                            'voucher_code': code,
                            'value': val,
                            'max_uses': limit,
                            'used_amount': 0,
                            'status': 'ACTIVE',
                            'expiry': expiryType == 'LIFETIME'
                                ? 'LIFETIME'
                                : DateFormat('yyyy-MM-dd').format(expiryDate!),
                            'timestamp': DateTime.now().millisecondsSinceEpoch,
                          });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Voucher $code dijana!');
                    },
                    icon: const FaIcon(FontAwesomeIcons.plus, size: 10),
                    label: const Text('JANA VOUCHER'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _expiryChip(
    String value,
    String label,
    String selected,
    ValueChanged<String> onTap,
  ) {
    final isActive = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.borderMed,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // SEARCH CUSTOMER MODAL (for Voucher Pelanggan & Referral)
  // ═══════════════════════════════════════
  void _showCustSearchModal(String type) {
    _custSearchCtrl.clear();
    List<Map<String, dynamic>> results = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        FaIcon(
                          type == 'VOUCHER'
                              ? FontAwesomeIcons.ticket
                              : FontAwesomeIcons.userPlus,
                          size: 14,
                          color: type == 'VOUCHER'
                              ? const Color(0xFFF59E0B)
                              : AppColors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type == 'VOUCHER'
                              ? 'CARI PELANGGAN (VOUCHER)'
                              : 'CARI PELANGGAN (REFERRAL)',
                          style: TextStyle(
                            color: type == 'VOUCHER'
                                ? const Color(0xFFF59E0B)
                                : AppColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 16,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ),
                const Divider(color: AppColors.borderMed, height: 20),
                const Text(
                  'Cari pelanggan menggunakan nama atau nombor telefon.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _custSearchCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Masukkan nama atau no telefon...',
                    hintStyle: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                    suffixIcon: GestureDetector(
                      onTap: () {
                        final q = _custSearchCtrl.text.toLowerCase().trim();
                        if (q.isEmpty) return;
                        final res = _customers
                            .where((d) {
                              final nama = (d['nama'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final tel = (d['tel'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final model = (d['model'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return nama.contains(q) ||
                                  tel.contains(q) ||
                                  model.contains(q);
                            })
                            .take(20)
                            .toList();
                        setS(() => results = res);
                      },
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CARI',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.bgDeep,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  onSubmitted: (_) {
                    final q = _custSearchCtrl.text.toLowerCase().trim();
                    if (q.isEmpty) return;
                    final res = _customers
                        .where((d) {
                          final nama = (d['nama'] ?? '')
                              .toString()
                              .toLowerCase();
                          final tel = (d['tel'] ?? '').toString().toLowerCase();
                          final model = (d['model'] ?? '')
                              .toString()
                              .toLowerCase();
                          return nama.contains(q) ||
                              tel.contains(q) ||
                              model.contains(q);
                        })
                        .take(20)
                        .toList();
                    setS(() => results = res);
                  },
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: results.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Tiada hasil carian',
                              style: TextStyle(
                                color: AppColors.textDim,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final c = results[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.bgDeep,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.borderMed),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (c['nama'] ?? '-')
                                              .toString()
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${c['tel'] ?? '-'}  |  ${c['_totalRepairs'] ?? 0} repair(s)',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          'Model: ${c['model'] ?? '-'}  |  Siri terakhir: #${c['siri'] ?? '-'}',
                                          style: const TextStyle(
                                            color: AppColors.textDim,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      if (type == 'VOUCHER') {
                                        _showCreateCustVoucher(c);
                                      } else {
                                        _createReferral(c);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: type == 'VOUCHER'
                                            ? const Color(0xFFF59E0B)
                                            : AppColors.green,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FaIcon(
                                            FontAwesomeIcons.plus,
                                            size: 9,
                                            color: Colors.black,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'PILIH',
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // CREATE CUSTOMER VOUCHER
  // ═══════════════════════════════════════
  void _showCreateCustVoucher(Map<String, dynamic> cust) {
    final nama = (cust['nama'] ?? '-').toString().toUpperCase();
    final tel = (cust['tel'] ?? '-').toString();
    final siri = (cust['siri'] ?? '-').toString();
    final valueCtrl = TextEditingController(text: '5');
    final limitCtrl = TextEditingController(text: '1');
    String expiryType = 'LIFETIME';
    DateTime? expiryDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'JANA VOUCHER PELANGGAN',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderMed),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Tel: $tel  |  Siri: #$siri',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _dialogField(
                        'Nilai (RM)',
                        valueCtrl,
                        '5.00',
                        keyboard: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dialogField(
                        'Guna Berapa Kali',
                        limitCtrl,
                        '1',
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tempoh Sah',
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _expiryChip(
                      'LIFETIME',
                      'Lifetime',
                      expiryType,
                      (v) => setS(() {
                        expiryType = v;
                        expiryDate = null;
                      }),
                    ),
                    const SizedBox(width: 6),
                    _expiryChip('DATE', 'Sah Sehingga', expiryType, (v) async {
                      final d = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                        initialDate: DateTime.now().add(
                          const Duration(days: 30),
                        ),
                      );
                      if (d != null)
                        setS(() {
                          expiryType = 'DATE';
                          expiryDate = d;
                        });
                    }),
                  ],
                ),
                if (expiryType == 'DATE' && expiryDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Tamat: ${DateFormat('dd/MM/yyyy').format(expiryDate!)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      final val = double.tryParse(valueCtrl.text) ?? 0;
                      final limit = int.tryParse(limitCtrl.text) ?? 0;
                      if (val <= 0 || limit <= 0) {
                        _snack('Sila isi nilai dan kuota', err: true);
                        return;
                      }
                      final code =
                          'V-${Random().nextInt(999999).toString().padLeft(6, '0')}';
                      if (_tenantId == null || _branchId == null) return;
                      await _sb.from('shop_vouchers').insert({
                            'tenant_id': _tenantId,
                            'branch_id': _branchId,
                            'voucher_code': code,
                            'value': val,
                            'max_uses': limit,
                            'used_amount': 0,
                            'status': 'ACTIVE',
                            'customer_name': nama,
                            'customer_phone': tel,
                            'origin_siri': siri,
                            'expiry': expiryType == 'LIFETIME'
                                ? 'LIFETIME'
                                : DateFormat('yyyy-MM-dd').format(expiryDate!),
                          });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Voucher $code dijana untuk $nama');
                    },
                    icon: const FaIcon(FontAwesomeIcons.ticket, size: 10),
                    label: const Text('JANA VOUCHER'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // CREATE REFERRAL
  // ═══════════════════════════════════════
  Future<void> _createReferral(Map<String, dynamic> cust) async {
    final nama = (cust['nama'] ?? '-').toString().toUpperCase();
    final tel = (cust['tel'] ?? '-').toString();
    final siri = (cust['siri'] ?? '-').toString();

    if (_tenantId == null || _branchId == null) return;
    // Check duplicate — baca semua referrals branch, parse extras, match tel
    final existing = await _sb
        .from('referrals')
        .select()
        .eq('branch_id', _branchId!);
    for (final r in existing) {
      final cb = r['created_by'];
      Map<String, dynamic> extra = {};
      if (cb is String && cb.isNotEmpty) {
        try { extra = Map<String, dynamic>.from(jsonDecode(cb) as Map); } catch (_) {}
      }
      if (extra['tel'] == tel) {
        final existCode = r['code'] ?? '';
        _snack('Pelanggan ini sudah ada kod referral: $existCode', err: true);
        return;
      }
    }
    final refCode = 'REF-${Random().nextInt(900000) + 100000}';
    await _sb.from('referrals').insert({
      'tenant_id': _tenantId,
      'branch_id': _branchId,
      'code': refCode,
      'active': true,
      'created_by': jsonEncode({
        'nama': nama,
        'tel': tel,
        'siriAsal': siri,
        'bank': '',
        'accNo': '',
        'commission': 0,
      }),
    });
    _snack('Referral $refCode dijana untuk $nama');
  }

  // ═══════════════════════════════════════
  // SEND VIA WHATSAPP
  // ═══════════════════════════════════════
  void _sendVoucherWA(Map<String, dynamic> v) {
    final code = v['code'] ?? '';
    final value = double.tryParse(v['value']?.toString() ?? '0') ?? 0;
    final tel = (v['custTel'] ?? '').toString();
    final expiry = v['expiry']?.toString() ?? 'LIFETIME';
    final limit = v['limit'] ?? 0;

    final msg = Uri.encodeComponent(
      'Tahniah! Anda menerima voucher potongan harga.\n\n'
      'Kod Voucher: *$code*\n'
      'Nilai: *RM ${value.toStringAsFixed(2)}*\n'
      'Boleh guna: *$limit kali*\n'
      'Tempoh: *${expiry == 'LIFETIME' ? 'Tiada had masa' : 'Sah sehingga $expiry'}*\n\n'
      'Tunjukkan kod ini semasa menghantar barang untuk repair. Terima kasih!',
    );

    final targetTel = tel.isNotEmpty ? _formatWaTel(tel) : '';
    final waUrl = targetTel.isNotEmpty
        ? 'https://wa.me/$targetTel?text=$msg'
        : 'https://wa.me/?text=$msg';
    launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
  }

  void _sendReferralWA(Map<String, dynamic> r) {
    final code = r['refCode'] ?? '';
    final tel = (r['tel'] ?? '').toString();

    final msg = Uri.encodeComponent(
      'Tahniah! Anda mempunyai kod referral.\n\n'
      'Kod Referral: *$code*\n\n'
      'Kongsi kod ini kepada rakan anda. Apabila mereka menggunakan kod ini semasa repair, '
      'anda dan rakan anda akan mendapat potongan harga!\n\n'
      'Terima kasih!',
    );

    final waUrl = 'https://wa.me/${_formatWaTel(tel)}?text=$msg';
    launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
  }

  // ═══════════════════════════════════════
  // DELETE
  // ═══════════════════════════════════════
  Future<void> _deleteVoucher(Map<String, dynamic> v) async {
    final code = v['code'] ?? v['id'] ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Padam Voucher?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Voucher $code akan dipadam.',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PADAM', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _sb.from('shop_vouchers').delete().eq('voucher_code', code).eq('branch_id', _branchId!);
      _snack('Voucher $code dipadam');
    }
  }

  Future<void> _deleteReferral(Map<String, dynamic> r) async {
    final code = r['refCode'] ?? r['id'] ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Padam Referral?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Referral $code akan dipadam.',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PADAM', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _sb.from('referrals').delete().eq('code', code).eq('branch_id', _branchId!);
      _snack('Referral $code dipadam');
    }
  }

  // ═══════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════
  Widget _dialogField(
    String label,
    TextEditingController ctrl,
    String hint, {
    bool caps = false,
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSub,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          textCapitalization: caps
              ? TextCapitalization.characters
              : TextCapitalization.none,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
            filled: true,
            fillColor: AppColors.bgDeep,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
