import 'package:cloud_firestore/cloud_firestore.dart';

class SaasFlagsService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'saas_settings';
  static const _docId = 'feature_flags';

  static DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection(_collection).doc(_docId);

  static Stream<Map<String, bool>> stream() {
    return _ref.snapshots().map((snap) {
      final data = snap.data() ?? {};
      return {
        'marketplace': data['marketplace'] != false,
        'chat': data['chat'] != false,
      };
    });
  }

  static Future<Map<String, bool>> get() async {
    final snap = await _ref.get();
    final data = snap.data() ?? {};
    return {
      'marketplace': data['marketplace'] != false,
      'chat': data['chat'] != false,
    };
  }

  static Future<void> set(String key, bool value) async {
    await _ref.set({key: value}, SetOptions(merge: true));
  }
}
