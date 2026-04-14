import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import 'marketplace_browse_screen.dart';
import 'kedai_saya_screen.dart';
import 'pesanan_saya_screen.dart';
import 'jualan_masuk_screen.dart';

class MarketplaceShell extends StatefulWidget {
  final String ownerID, shopID;
  const MarketplaceShell({super.key, required this.ownerID, required this.shopID});
  @override
  State<MarketplaceShell> createState() => _MarketplaceShellState();
}

class _MarketplaceShellState extends State<MarketplaceShell> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      MarketplaceBrowseScreen(ownerID: widget.ownerID, shopID: widget.shopID),
      KedaiSayaScreen(ownerID: widget.ownerID, shopID: widget.shopID),
      PesananSayaScreen(ownerID: widget.ownerID, shopID: widget.shopID),
      JualanMasukScreen(ownerID: widget.ownerID, shopID: widget.shopID),
    ];

    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _tab(0, FontAwesomeIcons.store, 'Marketplace'),
              _tab(1, FontAwesomeIcons.shop, 'Kedai Saya'),
              _tab(2, FontAwesomeIcons.bagShopping, 'Pesanan'),
              _tab(3, FontAwesomeIcons.moneyBills, 'Jualan'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: pages[_currentTab]),
      ],
    );
  }

  Widget _tab(int index, IconData icon, String label) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF8B5CF6) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                icon,
                size: 14,
                color: isActive ? Colors.white : AppColors.textDim,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textDim,
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
