import 'supabase_client.dart';

class SaasFlagsService {
  static const _key = 'feature_flags';

  static Map<String, bool> _normalize(Map? raw) => {
        'marketplace': raw?['marketplace'] == true, // hidden by default per Abe Din 2026-04-15
        'chat': raw?['chat'] != false,
      };

  static Stream<Map<String, bool>> stream() {
    return SupabaseService.client
        .from('saas_settings')
        .stream(primaryKey: ['id'])
        .eq('id', _key)
        .map((rows) => _normalize(rows.isNotEmpty ? rows.first['value'] as Map? : null));
  }

  static Future<Map<String, bool>> get() async {
    final row = await SupabaseService.client
        .from('saas_settings')
        .select('value')
        .eq('id', _key)
        .maybeSingle();
    return _normalize(row?['value'] as Map?);
  }

  static Future<void> set(String key, bool value) async {
    final existing = await SupabaseService.client
        .from('saas_settings')
        .select('value')
        .eq('id', _key)
        .maybeSingle();
    final merged = Map<String, dynamic>.from(existing?['value'] as Map? ?? {});
    merged[key] = value;
    await SupabaseService.client
        .from('saas_settings')
        .upsert({'id': _key, 'value': merged});
  }
}
