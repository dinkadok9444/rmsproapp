import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/saas_flags_service.dart';
import '../services/repair_service.dart';
import '../services/supabase_client.dart';
import 'login_screen.dart';
import 'modules/chat_screen.dart';
import 'supervisor_modules/sv_inventory_tab.dart';
import 'supervisor_modules/sv_untungrugi_tab.dart';
import 'supervisor_modules/sv_refund_tab.dart';
import 'supervisor_modules/sv_claim_tab.dart';
import 'supervisor_modules/sv_staff_tab.dart';
import 'supervisor_modules/sv_marketing_tab.dart';
import 'supervisor_modules/sv_dashboard_tab.dart';
import 'supervisor_modules/sv_expense_tab.dart';
import 'supervisor_modules/sv_kewangan_tab.dart';
import 'supervisor_modules/sv_settings_tab.dart';
import 'marketplace/marketplace_shell.dart';

class SupervisorDashboardScreen extends StatefulWidget {
  const SupervisorDashboardScreen({super.key});
  @override
  State<SupervisorDashboardScreen> createState() =>
      _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen> {
  final _db = FirebaseFirestore.instance; // legacy: marketplace_notifications (skip per marketplace rule)
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  final _authService = AuthService();

  String? _tenantId;
  String? _branchId;
  String _ownerID = '', _shopID = '', _staffName = '';
  String _shopName = '';
  String? _logoBase64;
  Color _themeColor = const Color(0xFF6366F1); // Indigo for supervisor
  int _currentTab = 0;
  String _moreSubPage =
      ''; // '' = grid menu, 'STAFF', 'MARKETING', 'MARKETPLACE'
  int _unreadNotifications = 0;
  StreamSubscription? _notifSub;
  StreamSubscription? _shopSub;
  StreamSubscription? _flagsSub;
  Map<String, dynamic> _enabledModules = {};
  Map<String, bool> _saasFlags = {'marketplace': false, 'chat': true};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;

    final prefs = await SharedPreferences.getInstance();
    _staffName = prefs.getString('rms_staff_name') ?? 'SUPERVISOR';

    if (_branchId != null) {
      _shopSub = _sb
          .from('branches')
          .stream(primaryKey: ['id'])
          .eq('id', _branchId!)
          .listen((rows) {
        if (rows.isEmpty || !mounted) return;
        final data = rows.first;
        final extras = (data['extras'] is Map) ? Map<String, dynamic>.from(data['extras']) : <String, dynamic>{};
        final hex = extras['themeColor'] as String?;
        final em = data['enabled_modules'];
        setState(() {
          if (hex != null && hex.isNotEmpty) {
            _themeColor = Color(int.parse(hex.replaceFirst('#', '0xFF')));
          }
          _shopName = (data['nama_kedai'] ?? '').toString();
          _logoBase64 = data['logo_base64'] as String?;
          _enabledModules = em is Map ? Map<String, dynamic>.from(em) : {};
        });
      });
    }
    if (mounted) setState(() {});
    _listenNotifications();
    _flagsSub = SaasFlagsService.stream().listen((flags) {
      if (mounted) setState(() => _saasFlags = flags);
    });
  }

  bool _moduleEnabled(String id) {
    if (_enabledModules.isEmpty) return true;
    return _enabledModules[id] != false;
  }

  void _listenNotifications() {
    if (_ownerID.isEmpty) return;
    _notifSub = _db
        .collection('marketplace_notifications')
        .where('targetOwnerID', isEqualTo: _ownerID)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _unreadNotifications = snap.docs.length);
        });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _shopSub?.cancel();
    _flagsSub?.cancel();
    super.dispose();
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.bell,
                    size: 14,
                    color: Color(0xFF8B5CF6),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NOTIFIKASI',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (_unreadNotifications > 0)
                    GestureDetector(
                      onTap: () async {
                        final snap = await _db
                            .collection('marketplace_notifications')
                            .where('targetOwnerID', isEqualTo: _ownerID)
                            .where('read', isEqualTo: false)
                            .get();
                        final batch = _db.batch();
                        for (final doc in snap.docs) {
                          batch.update(doc.reference, {'read': true});
                        }
                        await batch.commit();
                      },
                      child: const Text(
                        'Tandakan semua dibaca',
                        style: TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db
                    .collection('marketplace_notifications')
                    .where('targetOwnerID', isEqualTo: _ownerID)
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData)
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6),
                      ),
                    );
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(
                            FontAwesomeIcons.bellSlash,
                            size: 30,
                            color: AppColors.textDim.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Tiada notifikasi',
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final isRead = data['read'] == true;
                      final type = data['type'] ?? '';
                      final createdAt = data['createdAt'] is Timestamp
                          ? DateFormat(
                              'dd/MM HH:mm',
                            ).format((data['createdAt'] as Timestamp).toDate())
                          : '-';

                      IconData icon;
                      Color color;
                      switch (type) {
                        case 'order_approved':
                          icon = FontAwesomeIcons.circleCheck;
                          color = const Color(0xFF8B5CF6);
                          break;
                        case 'order_rejected':
                          icon = FontAwesomeIcons.circleXmark;
                          color = AppColors.red;
                          break;
                        case 'order_completed':
                          icon = FontAwesomeIcons.trophy;
                          color = AppColors.green;
                          break;
                        case 'tracking_update':
                          icon = FontAwesomeIcons.truck;
                          color = const Color(0xFF3B82F6);
                          break;
                        default:
                          icon = FontAwesomeIcons.bell;
                          color = const Color(0xFFF59E0B);
                          break;
                      }

                      return GestureDetector(
                        onTap: () {
                          if (!isRead) {
                            _db
                                .collection('marketplace_notifications')
                                .doc(docs[i].id)
                                .update({'read': true});
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isRead
                                ? Colors.white
                                : color.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isRead
                                  ? AppColors.border
                                  : color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: FaIcon(icon, size: 12, color: color),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['title'] ?? '',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 11,
                                        fontWeight: isRead
                                            ? FontWeight.w700
                                            : FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      data['message'] ?? '',
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 10,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      createdAt,
                                      style: const TextStyle(
                                        color: AppColors.textDim,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
  }

  @override
  Widget build(BuildContext context) {
    final darkerTheme = HSLColor.fromColor(
      _themeColor,
    ).withLightness(0.25).toColor();
    final pages = [
      SvDashboardTab(
        ownerID: _ownerID,
        shopID: _shopID,
        phoneEnabled: _moduleEnabled('JualTelefon'),
      ),
      SvUntungRugiTab(
        ownerID: _ownerID,
        shopID: _shopID,
        phoneEnabled: _moduleEnabled('JualTelefon'),
      ),
      if (_saasFlags['marketplace'] == true)
        MarketplaceShell(ownerID: _ownerID, shopID: _shopID)
      else
        const SizedBox.shrink(),
      SvClaimTab(ownerID: _ownerID, shopID: _shopID),
      _buildMorePage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  darkerTheme,
                  _themeColor,
                  _themeColor.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: _themeColor.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child:
                                  _logoBase64 != null && _logoBase64!.isNotEmpty
                                  ? Image.memory(
                                      base64Decode(
                                        _logoBase64!.split(',').last,
                                      ),
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    )
                                  : const Center(
                                      child: FaIcon(
                                        FontAwesomeIcons.store,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_shopName.isNotEmpty)
                                  Text(
                                    _shopName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Row(
                                  children: [
                                    const FaIcon(
                                      FontAwesomeIcons.userShield,
                                      size: 8,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${_staffName.toUpperCase()} · SUPERVISOR',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Notification bell
                    GestureDetector(
                      onTap: _showNotifications,
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const FaIcon(
                              FontAwesomeIcons.bell,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          if (_unreadNotifications > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$_unreadNotifications',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _logout,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.rightFromBracket,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Body
          Expanded(
            child: _ownerID.isEmpty
                ? Center(child: CircularProgressIndicator(color: _themeColor))
                : pages[_currentTab],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _navItem(0, FontAwesomeIcons.chartPie, 'Dashboard'),
                _navItem(1, FontAwesomeIcons.chartLine, 'Untung Rugi'),
                if (_saasFlags['marketplace'] == true)
                  _navItem(2, FontAwesomeIcons.store, 'Marketplace'),
                _navItem(3, FontAwesomeIcons.fileShield, 'Claim'),
                _navItem(4, FontAwesomeIcons.ellipsis, 'Lagi'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // MORE PAGE — Grid menu for Staff & Marketing
  // ═══════════════════════════════════════
  Widget _buildMorePage() {
    // If a sub-page is selected, show that sub-page
    if (_moreSubPage == 'STAFF') {
      return Column(
        children: [
          _moreBackHeader('PENGURUSAN STAF'),
          Expanded(
            child: SvStaffTab(ownerID: _ownerID, shopID: _shopID),
          ),
        ],
      );
    }
    if (_moreSubPage == 'MARKETING') {
      return Column(
        children: [
          _moreBackHeader('MARKETING'),
          Expanded(
            child: SvMarketingTab(ownerID: _ownerID, shopID: _shopID),
          ),
        ],
      );
    }
    if (_moreSubPage == 'DELETE_RECORD') {
      return Column(
        children: [
          _moreBackHeader('PADAM REKOD'),
          Expanded(child: _buildDeleteRecordPage()),
        ],
      );
    }
    if (_moreSubPage == 'REFUND') {
      return Column(
        children: [
          _moreBackHeader('KELULUSAN REFUND'),
          Expanded(
            child: SvRefundTab(ownerID: _ownerID, shopID: _shopID),
          ),
        ],
      );
    }
    if (_moreSubPage == 'INVENTORY') {
      return Column(
        children: [
          _moreBackHeader('INVENTORI'),
          Expanded(
            child: SvInventoryTab(
              ownerID: _ownerID,
              shopID: _shopID,
              phoneEnabled: _moduleEnabled('JualTelefon'),
            ),
          ),
        ],
      );
    }
    if (_moreSubPage == 'CHAT') {
      return Column(
        children: [
          _moreBackHeader('CHAT'),
          Expanded(
            child: ChatScreen(ownerID: _ownerID, shopID: _shopID),
          ),
        ],
      );
    }
    if (_moreSubPage == 'EXPENSE') {
      return Column(
        children: [
          _moreBackHeader('PERBELANJAAN'),
          Expanded(
            child: SvExpenseTab(ownerID: _ownerID, shopID: _shopID),
          ),
        ],
      );
    }
    if (_moreSubPage == 'KEWANGAN') {
      return Column(
        children: [
          _moreBackHeader('LAPORAN KEWANGAN'),
          Expanded(
            child: SvKewanganTab(
              ownerID: _ownerID,
              shopID: _shopID,
              phoneEnabled: _moduleEnabled('JualTelefon'),
            ),
          ),
        ],
      );
    }
    if (_moreSubPage == 'SETTINGS') {
      return Column(
        children: [
          _moreBackHeader('TETAPAN'),
          const Expanded(
            child: SvSettingsTab(),
          ),
        ],
      );
    }

    // Grid menu
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LAGI',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pilih fungsi tambahan',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _moreMenuCard(
                'Staf',
                FontAwesomeIcons.users,
                const Color(0xFF3B82F6),
                const Color(0xFFDBEAFE),
                () {
                  setState(() => _moreSubPage = 'STAFF');
                },
              ),
              const SizedBox(width: 14),
              _moreMenuCard(
                'Marketing',
                FontAwesomeIcons.bullhorn,
                const Color(0xFFF59E0B),
                const Color(0xFFFEF3C7),
                () {
                  setState(() => _moreSubPage = 'MARKETING');
                },
              ),
              const SizedBox(width: 14),
              _moreMenuCard(
                'Padam Rekod',
                FontAwesomeIcons.trash,
                const Color(0xFFEF4444),
                const Color(0xFFFEE2E2),
                () {
                  setState(() => _moreSubPage = 'DELETE_RECORD');
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _moreMenuCard(
                'Inventori',
                FontAwesomeIcons.boxesStacked,
                const Color(0xFFF59E0B),
                const Color(0xFFFEF3C7),
                () {
                  setState(() => _moreSubPage = 'INVENTORY');
                },
              ),
              const SizedBox(width: 14),
              _moreMenuCard(
                'Refund',
                FontAwesomeIcons.moneyBillTransfer,
                const Color(0xFFEF4444),
                const Color(0xFFFEE2E2),
                () {
                  setState(() => _moreSubPage = 'REFUND');
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_saasFlags['chat'] == true) ...[
                _moreMenuCard(
                  'Dealer Support',
                  FontAwesomeIcons.comments,
                  const Color(0xFF10B981),
                  const Color(0xFFD1FAE5),
                  () {
                    setState(() => _moreSubPage = 'CHAT');
                  },
                ),
                const SizedBox(width: 14),
              ],
              _moreMenuCard(
                'Perbelanjaan',
                FontAwesomeIcons.receipt,
                const Color(0xFFF59E0B),
                const Color(0xFFFEF3C7),
                () {
                  setState(() => _moreSubPage = 'EXPENSE');
                },
              ),
              const SizedBox(width: 14),
              _moreMenuCard(
                'Kewangan',
                FontAwesomeIcons.chartPie,
                const Color(0xFF06B6D4),
                const Color(0xFFCFFAFE),
                () {
                  setState(() => _moreSubPage = 'KEWANGAN');
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _moreMenuCard(
                'Tetapan',
                FontAwesomeIcons.gear,
                const Color(0xFF6B7280),
                const Color(0xFFF3F4F6),
                () {
                  setState(() => _moreSubPage = 'SETTINGS');
                },
              ),
              const SizedBox(width: 14),
              Expanded(child: Container()),
              const SizedBox(width: 14),
              Expanded(child: Container()),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // DELETE RECORD
  // ═══════════════════════════════════════
  Widget _buildDeleteRecordPage() {
    final siriCtrl = TextEditingController();
    Map<String, dynamic>? foundRecord;
    String? foundDocId;
    bool isSearching = false;

    return StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.triangleExclamation,
                    size: 14,
                    color: AppColors.red,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PADAM REKOD',
                    style: TextStyle(
                      color: AppColors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Cari rekod menggunakan nombor siri untuk dipadam.',
                style: TextStyle(color: AppColors.textDim, fontSize: 10),
              ),
              const SizedBox(height: 14),

              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Nombor Siri',
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: siriCtrl,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Cth: INV-001',
                        hintStyle: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: AppColors.bgDeep,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isSearching
                        ? null
                        : () async {
                            if (siriCtrl.text.trim().isEmpty) {
                              _svSnack('Sila masukkan nombor siri', err: true);
                              return;
                            }
                            setS(() {
                              isSearching = true;
                              foundRecord = null;
                              foundDocId = null;
                            });
                            try {
                              if (_branchId == null) throw Exception('Branch belum resolved');
                              final rows = await _sb
                                  .from('jobs')
                                  .select()
                                  .eq('branch_id', _branchId!)
                                  .eq('siri', siriCtrl.text.trim().toUpperCase())
                                  .limit(1);
                              if (rows.isNotEmpty) {
                                setS(() {
                                  foundRecord = Map<String, dynamic>.from(rows.first);
                                  foundDocId = rows.first['id']?.toString();
                                });
                              } else {
                                _svSnack('Rekod tidak dijumpai', err: true);
                              }
                            } catch (e) {
                              _svSnack('Gagal carian: $e', err: true);
                            }
                            setS(() => isSearching = false);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                    ),
                    child: isSearching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const FaIcon(
                            FontAwesomeIcons.magnifyingGlass,
                            size: 12,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (foundRecord != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'REKOD DIJUMPAI',
                        style: TextStyle(
                          color: AppColors.red,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _previewRow('Siri', foundRecord!['siri'] ?? '-'),
                      _previewRow('Nama', foundRecord!['nama'] ?? '-'),
                      _previewRow(
                        'Model',
                        foundRecord!['model'] ??
                            foundRecord!['kerosakan'] ??
                            '-',
                      ),
                      _previewRow(
                        'Status',
                        foundRecord!['status_repair'] ??
                            foundRecord!['payment_status'] ??
                            '-',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmDeleteRecord(foundDocId!),
                    icon: const FaIcon(FontAwesomeIcons.trash, size: 12),
                    label: const Text('PADAM REKOD INI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value.toString().toUpperCase(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRecord(String docId) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Sahkan Pemadaman?',
          style: TextStyle(
            color: AppColors.red,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Rekod ini akan dipadam secara kekal dan tidak boleh dipulihkan.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dCtx);
              _performDeleteRecord(docId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('PADAM'),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteRecord(String docId) async {
    try {
      await _sb.from('jobs').delete().eq('id', docId);
      _svSnack('Rekod berjaya dipadam');
    } catch (e) {
      _svSnack('Gagal padam rekod: $e', err: true);
    }
  }

  void _svSnack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: err ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _moreMenuCard(
    String label,
    IconData icon,
    Color color,
    Color bgColor,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Center(child: FaIcon(icon, size: 20, color: color)),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreBackHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _moreSubPage = ''),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const FaIcon(
                FontAwesomeIcons.arrowLeft,
                size: 12,
                color: AppColors.textSub,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _currentTab = index;
          if (index != 4) _moreSubPage = '';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: _themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                icon,
                size: 16,
                color: isActive ? _themeColor : AppColors.textDim,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? _themeColor : AppColors.textDim,
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
}
