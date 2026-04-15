import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/image_utils.dart';
import 'supabase_client.dart';

/// Wrapper for Supabase Storage — paralel pattern dengan FirebaseStorage
/// yang dah dibuang. Semua upload guna path `{ownerId}/{...}` supaya
/// RLS `storage.objects` boleh extract tenant dari first folder segment.
///
/// Image uploads auto-compressed ke ≤ 80KB sebelum upload.
class SupabaseStorageHelper {
  final SupabaseClient _sb = SupabaseService.client;

  bool _isImage(String ct) => ct.toLowerCase().startsWith('image/');

  /// Upload file → return public URL. Auto-compress if image.
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
    String contentType = 'image/jpeg',
  }) async {
    if (_isImage(contentType)) {
      final compressed = await compressFileTo80KB(file);
      return uploadBytes(
        bucket: bucket,
        path: path,
        bytes: compressed,
        contentType: 'image/png',
      );
    }
    await _sb.storage.from(bucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _sb.storage.from(bucket).getPublicUrl(path);
  }

  /// Upload bytes → return public URL. Auto-compress if image.
  Future<String> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    Uint8List out = bytes;
    String ct = contentType;
    if (_isImage(contentType) && bytes.length > 80 * 1024) {
      out = await compressBytesTo80KB(bytes);
      ct = 'image/png';
    }
    await _sb.storage.from(bucket).uploadBinary(
          path,
          out,
          fileOptions: FileOptions(contentType: ct, upsert: true),
        );
    return _sb.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> delete({required String bucket, required String path}) async {
    await _sb.storage.from(bucket).remove([path]);
  }

  String publicUrl({required String bucket, required String path}) =>
      _sb.storage.from(bucket).getPublicUrl(path);
}
