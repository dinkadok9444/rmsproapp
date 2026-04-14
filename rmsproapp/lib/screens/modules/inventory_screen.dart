import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import 'stock_screen.dart';
import 'accessories_screen.dart';
import 'phone_stock_screen.dart';

class InventoryScreen extends StatefulWidget {
  final Map<String, dynamic>? enabledModules;
  const InventoryScreen({super.key, this.enabledModules});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  int _segment = 0;

  bool get _phoneEnabled {
    final m = widget.enabledModules;
    if (m == null || m.isEmpty) return true;
    return m['JualTelefon'] != false;
  }

  List<_InvSeg> get _segments => [
        _InvSeg('SPAREPART', FontAwesomeIcons.screwdriverWrench,
            const Color(0xFFF59E0B), const StockScreen()),
        _InvSeg('ACCESSORIES', FontAwesomeIcons.headphones,
            const Color(0xFF8B5CF6), const AccessoriesScreen()),
        if (_phoneEnabled)
          _InvSeg('TELEFON', FontAwesomeIcons.mobileScreenButton,
              const Color(0xFF0EA5E9), const PhoneStockScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final segs = _segments;
    if (_segment >= segs.length) _segment = 0;
    if (segs.length <= 1) {
      return segs.isEmpty ? const SizedBox.shrink() : segs.first.screen;
    }
    return Column(children: [
      _buildSegmentBar(segs),
      Expanded(child: segs[_segment].screen),
    ]);
  }

  Widget _buildSegmentBar(List<_InvSeg> segs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        for (int i = 0; i < segs.length; i++) ...[
          _segBtn(i, segs[i]),
          if (i < segs.length - 1) const SizedBox(width: 6),
        ],
      ]),
    );
  }

  Widget _segBtn(int idx, _InvSeg seg) {
    final active = _segment == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _segment = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? seg.color : AppColors.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? seg.color : AppColors.border),
          boxShadow: active ? [BoxShadow(color: seg.color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FaIcon(seg.icon, size: 10, color: active ? Colors.white : AppColors.textDim),
          const SizedBox(width: 5),
          Text(seg.label, style: TextStyle(color: active ? Colors.white : AppColors.textDim, fontSize: 9, fontWeight: FontWeight.w900)),
        ]),
      ),
    ));
  }
}

class _InvSeg {
  final String label;
  final IconData icon;
  final Color color;
  final Widget screen;
  const _InvSeg(this.label, this.icon, this.color, this.screen);
}
