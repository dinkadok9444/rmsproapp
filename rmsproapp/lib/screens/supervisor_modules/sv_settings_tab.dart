import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

class SvSettingsTab extends StatefulWidget {
  const SvSettingsTab({super.key});
  @override
  State<SvSettingsTab> createState() => _SvSettingsTabState();
}

class _SvSettingsTabState extends State<SvSettingsTab> {
  final _lang = AppLanguage();

  @override
  void initState() {
    super.initState();
    _lang.addListener(_onLangChanged);
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lang.removeListener(_onLangChanged);
    super.dispose();
  }

  Future<void> _setLanguage(String lang) async {
    await _lang.setLanguage(lang);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lang.get('sv_settings_saved'), style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const FaIcon(FontAwesomeIcons.language, size: 14, color: AppColors.green),
          const SizedBox(width: 8),
          Text(_lang.get('sv_settings_language'), style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 6),
        Text(_lang.get('sv_settings_language_desc'), style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _lang.lang,
              isExpanded: true,
              icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 10, color: AppColors.green),
              style: const TextStyle(color: AppColors.green, fontSize: 14, fontWeight: FontWeight.w800),
              dropdownColor: Colors.white,
              items: [
                DropdownMenuItem(
                  value: 'ms',
                  child: Row(children: [
                    const Text('\u{1F1F2}\u{1F1FE}', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Text(_lang.get('sv_settings_malay'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Row(children: [
                    const Text('\u{1F1EC}\u{1F1E7}', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Text(_lang.get('sv_settings_english'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
              onChanged: (val) {
                if (val != null) _setLanguage(val);
              },
            ),
          ),
        ),
      ]),
    );
  }
}
