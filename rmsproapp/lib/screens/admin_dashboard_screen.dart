import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'admin_modules/senarai_aktif_screen.dart';
import 'admin_modules/daftar_manual_screen.dart';
import 'admin_modules/rekod_jualan_screen.dart';
import 'admin_modules/katakata_screen.dart';
import 'admin_modules/notis_aduan_screen.dart';
import 'admin_modules/tetapan_sistem_screen.dart';
import 'admin_modules/tong_sampah_screen.dart';
import 'admin_modules/marketplace_admin_screen.dart';
import 'admin_modules/domain_management_screen.dart';
import 'admin_modules/template_pdf_screen.dart';
import 'admin_modules/whatsapp_bot_screen.dart';
import 'admin_modules/saas_feedback_screen.dart';
import 'admin_modules/database_user_screen.dart';
import 'admin_modules/suis_modul_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;

  static const _modules = [
    {'icon': FontAwesomeIcons.listCheck, 'label': 'Senarai Aktif', 'color': AppColors.green},
    {'icon': FontAwesomeIcons.userPlus, 'label': 'Daftar Dealer', 'color': AppColors.blue},
    {'icon': FontAwesomeIcons.chartPie, 'label': 'Rekod Jualan', 'color': AppColors.orange},
    {'icon': FontAwesomeIcons.quoteLeft, 'label': 'Kata-Kata', 'color': Color(0xFF6366F1)},
    {'icon': FontAwesomeIcons.bullhorn, 'label': 'Notis Aduan', 'color': AppColors.red},
    {'icon': FontAwesomeIcons.gear, 'label': 'Tetapan API', 'color': AppColors.cyan},
    {'icon': FontAwesomeIcons.trash, 'label': 'Tong Sampah', 'color': AppColors.textMuted},
    {'icon': FontAwesomeIcons.store, 'label': 'Marketplace', 'color': Color(0xFF8B5CF6)},
    {'icon': FontAwesomeIcons.globe, 'label': 'Domain', 'color': Color(0xFF6D28D9)},
    {'icon': FontAwesomeIcons.filePdf, 'label': 'Template PDF', 'color': Color(0xFFEC4899)},
    {'icon': FontAwesomeIcons.whatsapp, 'label': 'Bot WhatsApp', 'color': Color(0xFF25D366)},
    {'icon': FontAwesomeIcons.commentDots, 'label': 'Feedback', 'color': AppColors.primary},
    {'icon': FontAwesomeIcons.database, 'label': 'Database User', 'color': Color(0xFF0EA5E9)},
    {'icon': FontAwesomeIcons.toggleOn, 'label': 'Suis Modul', 'color': Color(0xFF14B8A6)},
  ];

  final _pages = const [
    SenaraiAktifScreen(),
    DaftarManualScreen(),
    RekodJualanScreen(),
    KatakataScreen(),
    NotisAduanScreen(),
    TetapanSistemScreen(),
    TongSampahScreen(),
    MarketplaceAdminScreen(),
    DomainManagementScreen(),
    TemplatePdfScreen(),
    WhatsappBotScreen(),
    SaasFeedbackScreen(),
    DatabaseUserScreen(),
    SuisModulScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: _pages[_currentIndex]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    // Show first 4 + more button
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(children: [
            _bottomNavItem(0),
            _bottomNavItem(7), // Marketplace
            _bottomNavItem(2), // Rekod Jualan
            _bottomNavItem(5), // Tetapan API
            _bottomNavMore(),
          ]),
        ),
      ),
    );
  }

  Widget _bottomNavItem(int index) {
    final isActive = _currentIndex == index;
    final color = _modules[index]['color'] as Color;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: isActive ? BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(_modules[index]['icon'] as IconData, size: 14, color: isActive ? color : AppColors.textDim),
          const SizedBox(height: 3),
          Text((_modules[index]['label'] as String).split(' ').first, style: TextStyle(color: isActive ? color : AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w800)),
        ]),
      ),
    ));
  }

  Widget _bottomNavMore() {
    final isActive = _currentIndex == 1 || _currentIndex == 3 || _currentIndex == 4 || _currentIndex == 6 || _currentIndex == 8 || _currentIndex == 9 || _currentIndex == 10 || _currentIndex == 11 || _currentIndex == 12;
    return Expanded(child: GestureDetector(
      onTap: () => _showMoreMenu(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: isActive ? BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(FontAwesomeIcons.ellipsis, size: 14, color: isActive ? AppColors.primary : AppColors.textDim),
          const SizedBox(height: 3),
          Text('Lagi', style: TextStyle(color: isActive ? AppColors.primary : AppColors.textDim, fontSize: 8, fontWeight: FontWeight.w800)),
        ]),
      ),
    ));
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('MODUL LAIN', style: TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 16),
          for (final i in [1, 12, 10, 9, 8, 3, 4, 11, 6]) _moreMenuItem(ctx, i), // Daftar Dealer, Database User, Template PDF, Domain, Marketplace, Kata-Kata, Notis Aduan, Feedback, Tong Sampah
          const SizedBox(height: 8),
          // Promosi
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://rmspro.net/promote'), mode: LaunchMode.externalApplication);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.bullhorn, size: 14, color: AppColors.orange),
                const SizedBox(width: 12),
                const Text('Promosi', style: TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: AppColors.orange.withValues(alpha: 0.5)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          // Logout
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const FaIcon(FontAwesomeIcons.rightFromBracket, size: 14, color: AppColors.red),
                const SizedBox(width: 12),
                const Text('Log Keluar', style: TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: AppColors.red.withValues(alpha: 0.5)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _moreMenuItem(BuildContext ctx, int index) {
    final color = _modules[index]['color'] as Color;
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); setState(() => _currentIndex = index); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          FaIcon(_modules[index]['icon'] as IconData, size: 14, color: color),
          const SizedBox(width: 12),
          Text(_modules[index]['label'] as String, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          FaIcon(FontAwesomeIcons.chevronRight, size: 10, color: color.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }

}
