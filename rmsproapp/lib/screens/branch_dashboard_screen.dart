import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart'; // ignore: unused_import
import '../services/auth_service.dart';
import '../services/branch_service.dart';
import '../services/repair_service.dart';
import '../services/supabase_client.dart';
import 'login_screen.dart';
import 'modules/create_job_screen.dart';
import 'modules/senarai_job_screen.dart';
import 'modules/jual_telefon_screen.dart';
import 'modules/dashboard_widget_screen.dart';
import 'modules/kewangan_screen.dart';
import 'modules/db_cust_screen.dart';
import 'modules/inventory_screen.dart';
import 'modules/booking_screen.dart';
import 'modules/claim_warranty_screen.dart';
import 'modules/refund_screen.dart';
import 'modules/maklum_balas_screen.dart';
import 'modules/fungsi_lain_screen.dart';
import 'modules/settings_screen.dart';
import 'modules/quick_sales_screen.dart';
import 'modules/collab_screen.dart';
import 'modules/profesional_screen.dart';
import 'modules/lost_screen.dart';
import 'modules/link_screen.dart';

class BranchDashboardScreen extends StatefulWidget {
  const BranchDashboardScreen({super.key});
  @override
  State<BranchDashboardScreen> createState() => _BranchDashboardScreenState();
}

class _BranchDashboardScreenState extends State<BranchDashboardScreen> {
  final BranchService _branchService = BranchService();
  final AuthService _authService = AuthService();

  String _currentModule = 'HOME';
  bool _isLoading = true;
  int _bottomNavIndex = 0;

  // PageView for swipe navigation
  late final PageController _pageController;

  // Theme color - customizable from settings
  Color _themeColor = const Color(0xFF0D9488); // Default teal
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String? _tenantId;
  String? _branchId;
  String _ownerID = 'admin', _shopID = 'MAIN';

  // Pro Mode subscription state
  bool _proMode = false;
  int _proModeExpire = 0;
  StreamSubscription? _proSub;

  // Enabled modules map (from admin toggles). Empty = all enabled.
  Map<String, dynamic> _enabledModules = {};

  bool _moduleEnabled(String id) {
    if (_enabledModules.isEmpty) return true;
    return _enabledModules[id] != false;
  }

  List<_ModuleItem> get _visibleModuleItems =>
      _moduleItems.where((m) => _moduleEnabled(m.moduleId) || m.moduleId == 'Settings').toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    await _branchService.initialize();
    await _repairService.init();
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;
    // Load theme color from branches.extras + enabled_modules
    try {
      if (_branchId != null) {
        final row = await _sb.from('branches').select('extras, enabled_modules').eq('id', _branchId!).maybeSingle();
        if (row != null) {
          final extras = (row['extras'] is Map) ? Map<String, dynamic>.from(row['extras']) : <String, dynamic>{};
          final colorHex = extras['themeColor'] as String?;
          if (colorHex != null && colorHex.isNotEmpty) {
            _themeColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
          }
        }
      }
    } catch (_) {}
    // Stream branches row + tenant config untuk pro mode
    if (_branchId != null) {
      _proSub = _sb.from('branches').stream(primaryKey: ['id']).eq('id', _branchId!).listen((rows) async {
        if (rows.isEmpty || !mounted) return;
        final d = rows.first;
        final extras = (d['extras'] is Map) ? Map<String, dynamic>.from(d['extras']) : <String, dynamic>{};
        final em = d['enabled_modules'];
        // Pro mode disimpan dalam tenants.config
        bool proMode = false;
        int proModeExpire = 0;
        if (_tenantId != null) {
          try {
            final t = await _sb.from('tenants').select('config').eq('id', _tenantId!).maybeSingle();
            final config = (t?['config'] is Map) ? Map<String, dynamic>.from(t!['config']) : <String, dynamic>{};
            proMode = config['proMode'] == true || config['pro_mode'] == true;
            final exp = config['proModeExpire'] ?? config['pro_mode_expire'];
            if (exp is int) proModeExpire = exp;
            if (exp is String) proModeExpire = DateTime.tryParse(exp)?.millisecondsSinceEpoch ?? 0;
          } catch (_) {}
        }
        setState(() {
          _proMode = proMode;
          _proModeExpire = proModeExpire;
          final colorHex = extras['themeColor'] as String?;
          if (colorHex != null && colorHex.isNotEmpty) {
            _themeColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
          }
          if (em is Map) {
            _enabledModules = Map<String, dynamic>.from(em);
          } else {
            _enabledModules = {};
          }
        });
      });
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _proSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  bool get _isProActive {
    if (!_proMode) return false;
    if (_proModeExpire <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch < _proModeExpire;
  }

  String _kiraBakiPro() {
    if (!_proMode || _proModeExpire == 0) return 'TIDAK AKTIF';
    final expire = DateTime.fromMillisecondsSinceEpoch(_proModeExpire);
    final beza = expire.difference(DateTime.now()).inDays;
    if (beza < 0) return 'TAMAT TEMPOH';
    if (beza == 0) return 'LUPUT HARI INI';
    return '$beza HARI LAGI';
  }

  void _showProLockedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFA855F7).withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const FaIcon(FontAwesomeIcons.lock, size: 16, color: Color(0xFFA855F7)),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('PROFESIONAL MODE', style: TextStyle(color: Color(0xFFA855F7), fontSize: 14, fontWeight: FontWeight.w900))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Column(children: [
              const Text('STATUS LANGGANAN', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(_kiraBakiPro(), style: TextStyle(color: _proMode ? AppColors.red : AppColors.textDim, fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 14),
          const Text(
            'Modul ini memerlukan langganan Pro Mode yang aktif. Sila hubungi Admin untuk mengaktifkan pakej Pro Mode.',
            style: TextStyle(color: AppColors.textSub, fontSize: 12, height: 1.5),
          ),
        ]),
        actions: [
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('FAHAM', style: TextStyle(fontWeight: FontWeight.w900)),
          )),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  // ========== MODULE GRID ITEMS ==========
  List<_ModuleItem> get _moduleItems => [
    _ModuleItem('widget', 'Dashboard', FontAwesomeIcons.chartLine, const Color(0xFF0D9488), const Color(0xFFCCFBF1)),
    _ModuleItem('Stock', 'Inventori', FontAwesomeIcons.boxesStacked, const Color(0xFFF59E0B), const Color(0xFFFEF3C7)),
    _ModuleItem('DB_Cust', 'Pelanggan', FontAwesomeIcons.users, const Color(0xFF8B5CF6), const Color(0xFFEDE9FE)),
    _ModuleItem('Booking', 'Booking', FontAwesomeIcons.calendarCheck, const Color(0xFF06B6D4), const Color(0xFFCFFAFE)),
    _ModuleItem('Claim_warranty', 'Claim', FontAwesomeIcons.shieldHalved, const Color(0xFFEC4899), const Color(0xFFFCE7F3)),
    _ModuleItem('Collab', 'Kolaborasi', FontAwesomeIcons.handshake, const Color(0xFF6366F1), const Color(0xFFE0E7FF)),
    _ModuleItem('Profesional', 'Pro Mode', FontAwesomeIcons.userTie, const Color(0xFFA855F7), const Color(0xFFF3E8FF)),
    _ModuleItem('Refund', 'Refund', FontAwesomeIcons.moneyBillTransfer, const Color(0xFFEF4444), const Color(0xFFFEE2E2)),
    _ModuleItem('Lost', 'Kerugian', FontAwesomeIcons.triangleExclamation, const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
    _ModuleItem('MaklumBalas', 'Prestasi', FontAwesomeIcons.star, const Color(0xFFF59E0B), const Color(0xFFFEF3C7)),
    _ModuleItem('Link', 'Link', FontAwesomeIcons.link, const Color(0xFF0EA5E9), const Color(0xFFE0F2FE)),
    _ModuleItem('Fungsi_lain', 'Fungsi Lain', FontAwesomeIcons.grip, const Color(0xFF64748B), const Color(0xFFF1F5F9)),
    _ModuleItem('Settings', 'Tetapan', FontAwesomeIcons.gear, const Color(0xFF6B7280), const Color(0xFFF3F4F6)),
  ];

  int _pageToNav(int pageIndex) {
    if (pageIndex <= 1) return pageIndex;
    if (pageIndex == 2) return 3;
    if (pageIndex == 3) return 4;
    return 0;
  }

  String _pageToModule(int pageIndex) {
    switch (pageIndex) {
      case 0: return 'HOME';
      case 1: return 'Senarai_job';
      case 2: return 'Kewangan';
      case 3: return 'Settings';
      default: return 'HOME';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: _themeColor)));
    }

    // If user tapped a module from grid (not one of the 4 swipeable tabs), show module page
    final isSwipeableModule = ['HOME', 'Senarai_job', 'Kewangan', 'Settings'].contains(_currentModule);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: isSwipeableModule
          ? PageView(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() {
                  _bottomNavIndex = _pageToNav(page);
                  _currentModule = _pageToModule(page);
                });
              },
              children: [
                _buildHomePage(),
                const SenaraiJobScreen(),
                KewanganScreen(enabledModules: _enabledModules),
                const SettingsScreen(),
              ],
            )
          : _buildModulePage(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ========== HOME PAGE (Grid of modules) ==========
  Widget _buildHomePage() {
    return CustomScrollView(slivers: [
      // Gradient Header
      SliverToBoxAdapter(child: _buildGradientHeader()),
      // Module Grid
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.95,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _buildModuleCard(_visibleModuleItems[i]),
            childCount: _visibleModuleItems.length,
          ),
        ),
      ),
    ]);
  }

  // ========== GRADIENT HEADER ==========
  Widget _buildGradientHeader() {
    final darkerTheme = HSLColor.fromColor(_themeColor).withLightness(0.25).toColor();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [darkerTheme, _themeColor, _themeColor.withValues(alpha: 0.85)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [BoxShadow(color: _themeColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
          child: Column(children: [
            // Top row: RMS PRO + Logout
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('RMS PRO', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
              GestureDetector(
                onTap: _logout,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(7)),
                  child: const FaIcon(FontAwesomeIcons.rightFromBracket, size: 11, color: Colors.white),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Avatar / Logo
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
              ),
              child: ClipOval(
                child: _branchService.logoBase64 != null
                    ? Image.memory(
                        base64Decode(_branchService.logoBase64!.split(',').last),
                        width: 46, height: 46, fit: BoxFit.cover,
                      )
                    : const FaIcon(FontAwesomeIcons.store, size: 20, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            // Shop Name
            Text(
              _branchService.shopName.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // Address
            if (_branchService.address.isNotEmpty)
              Text(
                _branchService.address,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 9, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 5),
            // Branch badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const FaIcon(FontAwesomeIcons.building, size: 7, color: Colors.white),
                const SizedBox(width: 4),
                Text('Cawangan: ${_branchService.shopID ?? _shopID}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 8, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ========== MODULE CARD (Grid item) ==========
  Widget _buildModuleCard(_ModuleItem item) {
    return GestureDetector(
      onTap: () {
        if (item.moduleId == 'Profesional' && !_isProActive) {
          _showProLockedDialog();
          return;
        }
        _switchToModule(item.moduleId);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            BoxShadow(color: item.color.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Stack(
          children: [
            Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon circle
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: item.bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: FaIcon(item.icon, size: 20, color: item.color)),
                ),
                const SizedBox(height: 10),
                // Label
                Text(
                  item.label,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ],
            )),
            // Pro Mode subscription badge
            if (item.moduleId == 'Profesional')
              Positioned(top: 8, right: 8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: (_isProActive ? AppColors.green : AppColors.textDim).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isProActive ? 'AKTIF' : 'OFF',
                  style: TextStyle(color: _isProActive ? AppColors.green : AppColors.textDim, fontSize: 7, fontWeight: FontWeight.w900),
                ),
              )),
          ],
        ),
      ),
    );
  }

  // ========== MODULE PAGE (When a module is selected) ==========
  Widget _buildModulePage() {
    return Column(children: [
      // Module top bar with back button
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.border)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              GestureDetector(
                onTap: () {
                  setState(() { _currentModule = 'HOME'; _bottomNavIndex = 0; });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_pageController.hasClients) _pageController.jumpToPage(0);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                  child: FaIcon(FontAwesomeIcons.arrowLeft, size: 14, color: _themeColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(
                _getModuleTitle(_currentModule),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
              )),
              // Create job button for Senarai Job
              if (_currentModule == 'Senarai_job')
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: _themeColor, borderRadius: BorderRadius.circular(10)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      FaIcon(FontAwesomeIcons.plus, size: 10, color: Colors.white), SizedBox(width: 6),
                      Text('TIKET', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
      // Module content
      Expanded(child: _buildModuleContent()),
    ]);
  }

  String _getModuleTitle(String moduleId) {
    if (moduleId == 'Profesional') return 'Profesional Mode';
    final item = _moduleItems.where((m) => m.moduleId == moduleId).firstOrNull;
    return item?.label ?? moduleId;
  }

  Widget _buildModuleContent() {
    switch (_currentModule) {
      case 'widget': return DashboardWidgetScreen(branchService: _branchService);
      case 'Senarai_job': return const SenaraiJobScreen();
      case 'Kewangan': return KewanganScreen(enabledModules: _enabledModules);
      case 'DB_Cust': return const DbCustScreen();
      case 'Stock': return InventoryScreen(enabledModules: _enabledModules);
      case 'Booking': return const BookingScreen();
      case 'Claim_warranty': return const ClaimWarrantyScreen();
      case 'Collab': return const CollabScreen();
      case 'Profesional': return ProfesionalScreen(onSwitchToCollab: () => _switchToModule('Collab'));
      case 'Refund': return const RefundScreen();
      case 'Lost': return const LostScreen();
      case 'MaklumBalas': return const MaklumBalasScreen();
      // PhoneStock now merged into Stock screen
      case 'QuickSales': return QuickSalesScreen(enabledModules: _enabledModules);
      case 'JualTelefon': return const JualTelefonScreen();
      case 'Link': return LinkScreen(enabledModules: _enabledModules);
      case 'Fungsi_lain': return const FungsiLainScreen();
      case 'Settings': return const SettingsScreen();
      default: return const Center(child: Text('Modul tidak dijumpai'));
    }
  }

  void _switchToModule(String moduleId) {
    final swipeable = {'HOME': 0, 'Senarai_job': 1, 'Kewangan': 2, 'Settings': 3};
    if (swipeable.containsKey(moduleId)) {
      _pageController.jumpToPage(swipeable[moduleId]!);
    }
    setState(() {
      _currentModule = moduleId;
      if (moduleId == 'HOME') _bottomNavIndex = 0;
      else if (moduleId == 'Senarai_job') _bottomNavIndex = 1;
      else if (moduleId == 'Kewangan') _bottomNavIndex = 3;
      else if (moduleId == 'Settings') _bottomNavIndex = 4;
      else _bottomNavIndex = 4;
    });
  }

  // ========== ADD POPUP ==========
  void _showAddPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('PILIH TINDAKAN', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _popupItem(ctx, 'POS', FontAwesomeIcons.cashRegister, const Color(0xFFEF4444), const Color(0xFFFEE2E2), () {
              Navigator.pop(ctx);
              _switchToModule('QuickSales');
            })),
            const SizedBox(width: 12),
            Expanded(child: _popupItem(ctx, 'Baikpulih', FontAwesomeIcons.screwdriverWrench, const Color(0xFF0D9488), const Color(0xFFCCFBF1), () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobScreen()));
            })),
            const SizedBox(width: 12),
            if (_moduleEnabled('JualTelefon'))
              Expanded(child: _popupItem(ctx, 'Jual Telefon', FontAwesomeIcons.mobileScreenButton, const Color(0xFF0EA5E9), const Color(0xFFE0F2FE), () {
                Navigator.pop(ctx);
                _switchToModule('JualTelefon');
              })),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _popupItem(BuildContext ctx, String label, IconData icon, Color color, Color bgColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8)]),
            child: Center(child: FaIcon(icon, size: 18, color: color)),
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // ========== BOTTOM NAVIGATION ==========
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            _navItem(0, FontAwesomeIcons.house, 'Utama', () {
              setState(() { _currentModule = 'HOME'; _bottomNavIndex = 0; });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) _pageController.jumpToPage(0);
              });
            }),
            _navItem(1, FontAwesomeIcons.clipboardList, 'Senarai', () {
              setState(() { _currentModule = 'Senarai_job'; _bottomNavIndex = 1; });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) _pageController.jumpToPage(1);
              });
            }),
            // Center FAB - Popup Menu
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showAddPopup(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Transform.translate(
                  offset: const Offset(0, -12),
                  child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_themeColor, HSLColor.fromColor(_themeColor).withLightness(0.35).toColor()]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _themeColor.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Center(child: FaIcon(FontAwesomeIcons.plus, size: 20, color: Colors.white)),
                  ),
                ),
              ]),
            )),
            _navItem(3, FontAwesomeIcons.wallet, 'Kewangan', () {
              setState(() { _currentModule = 'Kewangan'; _bottomNavIndex = 3; });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) _pageController.jumpToPage(2);
              });
            }),
            _navItem(4, FontAwesomeIcons.gear, 'Tetapan', () {
              setState(() { _currentModule = 'Settings'; _bottomNavIndex = 4; });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) _pageController.jumpToPage(3);
              });
            }),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, Function() onTap) {
    final isActive = _bottomNavIndex == index;
    return Expanded(child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(icon, size: 18, color: isActive ? _themeColor : AppColors.textDim),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isActive ? _themeColor : AppColors.textDim)),
      ]),
    ));
  }
}

class _ModuleItem {
  final String moduleId;
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _ModuleItem(this.moduleId, this.label, this.icon, this.color, this.bgColor);
}
