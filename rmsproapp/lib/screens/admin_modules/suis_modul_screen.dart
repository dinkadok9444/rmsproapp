import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/saas_flags_service.dart';

class SuisModulScreen extends StatelessWidget {
  const SuisModulScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: const [
                  FaIcon(FontAwesomeIcons.toggleOn,
                      size: 16, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text('SUIS MODUL SAAS',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                'On/Off modul untuk SEMUA tenant. Berkesan serta-merta.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
            Expanded(
              child: StreamBuilder<Map<String, bool>>(
                stream: SaasFlagsService.stream(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final flags = snap.data!;
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _tile(
                        icon: FontAwesomeIcons.store,
                        color: const Color(0xFF8B5CF6),
                        title: 'Marketplace',
                        desc: 'Platform jual beli antara kedai.',
                        value: flags['marketplace'] ?? true,
                        onChanged: (v) =>
                            SaasFlagsService.set('marketplace', v),
                      ),
                      const SizedBox(height: 10),
                      _tile(
                        icon: FontAwesomeIcons.comments,
                        color: const Color(0xFF10B981),
                        title: 'Chat',
                        desc: 'Mesej antara staff & owner kedai.',
                        value: flags['chat'] ?? true,
                        onChanged: (v) => SaasFlagsService.set('chat', v),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: FaIcon(icon, color: color, size: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
          ),
        ],
      ),
    );
  }
}
