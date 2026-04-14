import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import 'sv_stock_tab.dart';
import 'sv_accessories_tab.dart';
import 'sv_phone_stock_tab.dart';

class SvInventoryTab extends StatefulWidget {
  final String ownerID, shopID;
  final bool phoneEnabled;
  const SvInventoryTab({
    super.key,
    required this.ownerID,
    required this.shopID,
    this.phoneEnabled = true,
  });
  @override
  State<SvInventoryTab> createState() => _SvInventoryTabState();
}

class _SvInventoryTabState extends State<SvInventoryTab> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.phoneEnabled && _segment == 2) _segment = 0;
    return Column(children: [
      _buildSegmentBar(),
      Expanded(child: _buildContent()),
    ]);
  }

  Widget _buildSegmentBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        _segBtn(0, 'SPAREPART', FontAwesomeIcons.screwdriverWrench, const Color(0xFFF59E0B)),
        const SizedBox(width: 6),
        _segBtn(1, 'ACCESSORIES', FontAwesomeIcons.headphones, const Color(0xFF8B5CF6)),
        if (widget.phoneEnabled) ...[
          const SizedBox(width: 6),
          _segBtn(2, 'TELEFON', FontAwesomeIcons.mobileScreenButton, const Color(0xFF0EA5E9)),
        ],
      ]),
    );
  }

  Widget _segBtn(int idx, String label, IconData icon, Color color) {
    final active = _segment == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _segment = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? color : AppColors.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : AppColors.border),
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(icon, size: 10, color: active ? Colors.white : AppColors.textDim),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: active ? Colors.white : AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900)),
        ]),
      ),
    ));
  }

  Widget _buildContent() {
    switch (_segment) {
      case 0: return SvStockTab(ownerID: widget.ownerID, shopID: widget.shopID);
      case 1: return SvAccessoriesTab(ownerID: widget.ownerID, shopID: widget.shopID);
      case 2: return SvPhoneStockTab(ownerID: widget.ownerID, shopID: widget.shopID);
      default: return SvStockTab(ownerID: widget.ownerID, shopID: widget.shopID);
    }
  }
}
