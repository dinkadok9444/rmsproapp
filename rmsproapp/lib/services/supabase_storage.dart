import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

/// Wrapper for Supabase Storage — paralel pattern dengan FirebaseStorage
/// yang dah dibuang. Semua upload guna path `{ownerId}/{...}` supaya
/// RLS `storage.objects` boleh extract tenant dari first folder segment.
class SupabaseStorageHelper {
  final SupabaseClient _sb = SupabaseService.client;

  /// Upload file → return public URL.
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
    String contentType = 'image/jpeg',
  }) async {
    await _sb.storage.from(bucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _sb.storage.from(bucket).getPublicUrl(path);
  }

  /// Upload bytes → return public URL.
  Future<String> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    await _sb.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _sb.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> delete({required String bucket, required String path}) async {
    await _sb.storage.from(bucket).remove([path]);
  }

  String publicUrl({required String bucket, required String path}) =>
      _sb.storage.from(bucket).getPublicUrl(path);
}
