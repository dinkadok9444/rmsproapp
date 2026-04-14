import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compress image to approximately 30kb PNG
Future<Uint8List?> compressImage(File file) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final decoded = frame.image;

  double scale = 1.0;
  if (bytes.length > 30000) {
    scale = sqrt(30000 / bytes.length);
  }
  final w = (decoded.width * scale).round().clamp(50, 600);
  final h = (decoded.height * scale).round().clamp(50, 600);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final src = Rect.fromLTWH(0, 0, decoded.width.toDouble(), decoded.height.toDouble());
  final dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  canvas.drawImageRect(decoded, src, dst, Paint());
  final pic = recorder.endRecording();
  final img = await pic.toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd?.buffer.asUint8List();
}
