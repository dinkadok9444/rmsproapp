import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int _kMaxBytes = 80 * 1024; // 80KB hard cap per image

/// Compress image to approximately 30kb PNG (legacy — kekal untuk avatar kecik)
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

Future<Uint8List> _renderPng(ui.Image decoded, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final src = Rect.fromLTWH(0, 0, decoded.width.toDouble(), decoded.height.toDouble());
  final dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  canvas.drawImageRect(decoded, src, dst, Paint());
  final pic = recorder.endRecording();
  final img = await pic.toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// Compress any image bytes/file to ≤ 80KB PNG by iteratively reducing dimensions.
Future<Uint8List> compressToMax80KB(dynamic source) async {
  Uint8List bytes;
  if (source is File) {
    bytes = await source.readAsBytes();
  } else if (source is Uint8List) {
    bytes = source;
  } else {
    throw ArgumentError('source must be File or Uint8List');
  }

  if (bytes.length <= _kMaxBytes) return bytes;

  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final decoded = frame.image;

  int maxSide = max(decoded.width, decoded.height);
  int targetMax = 1280;
  if (maxSide > targetMax) {
    final s = targetMax / maxSide;
    int w = (decoded.width * s).round();
    int h = (decoded.height * s).round();
    Uint8List out = await _renderPng(decoded, w, h);
    // Iteratively shrink 20% until ≤ 80KB or too small
    while (out.length > _kMaxBytes && max(w, h) > 200) {
      w = (w * 0.8).round();
      h = (h * 0.8).round();
      out = await _renderPng(decoded, w, h);
    }
    return out;
  } else {
    // Already small dims but big bytes — shrink from current size
    int w = decoded.width, h = decoded.height;
    Uint8List out = bytes;
    while (out.length > _kMaxBytes && max(w, h) > 200) {
      w = (w * 0.8).round();
      h = (h * 0.8).round();
      out = await _renderPng(decoded, w, h);
    }
    return out;
  }
}

/// Convenience: compress File → Uint8List ≤ 80KB.
Future<Uint8List> compressFileTo80KB(File file) => compressToMax80KB(file);

/// Convenience: compress bytes ≤ 80KB.
Future<Uint8List> compressBytesTo80KB(Uint8List bytes) => compressToMax80KB(bytes);
