import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
// niimbot_print removed - plugin broken

class PrinterService {
  static final PrinterService _instance = PrinterService._();
  factory PrinterService() => _instance;
  PrinterService._();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  bool _isConnected = false;

  // Niimbot removed - use standard BLE instead
  bool _niimbotConnected = false;

  // Standard label printer (non-Niimbot BLE)
  BluetoothDevice? _labelDevice;
  BluetoothCharacteristic? _labelWriteChar;
  bool _labelConnected = false;

  bool get isConnected => _isConnected;
  bool get isLabelConnected => _niimbotConnected || _labelConnected;
  String get deviceName => _connectedDevice?.platformName ?? '';
  String get labelDeviceName => _labelDevice?.platformName ?? '';

  Future<bool> autoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('printer_80mm_id') ?? '';
    final savedName = prefs.getString('printer_80mm_name') ?? '';

    if (savedId.isEmpty && savedName.isEmpty) return false;
    if (_isConnected && _writeChar != null) return true;

    try {
      if (!kIsWeb) {
        final isOn = await FlutterBluePlus.adapterState.first;
        if (isOn != BluetoothAdapterState.on) return false;
      }

      // Try connect by ID first
      if (savedId.isNotEmpty) {
        try {
          final device = BluetoothDevice.fromId(savedId);
          await device.connect(license: License.free, timeout: const Duration(seconds: 8));
          final found = await _findWriteCharacteristic(device);
          if (found) return true;
        } catch (e) {
          debugPrint('[Printer] Auto-connect by ID failed: $e');
        }
      }

      // Scan and find by name
      if (savedName.isNotEmpty) {
        final found = await _scanAndConnect(savedName, _findWriteCharacteristic);
        if (found) return true;
      }
    } catch (e) {
      debugPrint('[Printer] Auto-connect failed: $e');
    }
    return false;
  }

  /// Scan Bluetooth for a device by name with proper timeout (no hanging).
  Future<bool> _scanAndConnect(String targetName, Future<bool> Function(BluetoothDevice) onFound) async {
    final completer = Completer<bool>();
    StreamSubscription? sub;

    try {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      sub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          if (r.device.platformName == targetName && !completer.isCompleted) {
            FlutterBluePlus.stopScan();
            try {
              await r.device.connect(license: License.free, timeout: const Duration(seconds: 8));
              final ok = await onFound(r.device);
              if (!completer.isCompleted) completer.complete(ok);
            } catch (_) {
              if (!completer.isCompleted) completer.complete(false);
            }
            return;
          }
        }
      });

      // Timeout: if scan finishes without finding the device
      return await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      await sub?.cancel();
      FlutterBluePlus.stopScan();
    }
  }

  Future<bool> _findWriteCharacteristic(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _connectedDevice = device;
            _writeChar = char;
            _isConnected = true;

            device.connectionState.listen((state) {
              if (state == BluetoothConnectionState.disconnected) {
                _isConnected = false;
                _writeChar = null;
              }
            });
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Kick open cash drawer via ESC/POS command
  /// Standard command: ESC p 0 25 250 (pin 2, pulse 25*2ms on, 250*2ms off)
  Future<bool> kickCashDrawer() async {
    // ESC p m t1 t2 — m=0 (pin2), t1=25 (50ms on), t2=250 (500ms off)
    final cmd = [0x1B, 0x70, 0x00, 0x19, 0xFA];
    return await printRaw(cmd);
  }

  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _writeChar = null;
    _isConnected = false;
  }

  /// Print raw bytes to 80mm thermal printer
  Future<bool> printRaw(List<int> data) async {
    if (!_isConnected || _writeChar == null) {
      final ok = await autoConnect();
      if (!ok) return false;
    }

    try {
      final chunkSize = 128;
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
        final chunk = data.sublist(i, end);
        if (_writeChar!.properties.writeWithoutResponse) {
          await _writeChar!.write(chunk, withoutResponse: true);
        } else {
          await _writeChar!.write(chunk);
        }
      }
      return true;
    } catch (_) {
      _isConnected = false;
      _writeChar = null;
      return false;
    }
  }

  /// Print formatted 80mm receipt for a repair job
  Future<bool> printReceipt(Map<String, dynamic> job, Map<String, dynamic> branchSettings) async {
    const lebar = 48;
    final garis = '${'=' * 48}\n';
    final garis2 = '${'-' * 48}\n';
    const escInit = '\x1B\x40';
    const escCenter = '\x1B\x61\x01';
    const escLeft = '\x1B\x61\x00';
    const escBoldOn = '\x1B\x45\x01';
    const escBoldOff = '\x1B\x45\x00';
    const escDblSize = '\x1B\x21\x30';
    const escNormal = '\x1B\x21\x00';

    String baris(String label, String nilai, [int lebarLabel = 18]) {
      final l = label.padRight(lebarLabel);
      final gap = lebar - l.length - nilai.length;
      return '$l${' ' * (gap > 0 ? gap : 1)}$nilai\n';
    }

    final s = branchSettings;
    final namaKedai = (s['shopName'] ?? s['namaKedai'] ?? 'RMS PRO').toString().toUpperCase();
    final telKedai = s['phone'] ?? s['ownerContact'] ?? '-';
    final alamat = s['address'] ?? s['alamat'] ?? '';
    final notaKaki = s['notaInvoice'] ?? 'Barang yang tidak dituntut selepas 30 hari adalah tanggungjawab pelanggan.';
    final siri = job['siri'] ?? '-';

    // Parse tarikh
    final tarikh = job['tarikh'] ?? job['tarikhMasuk'] ?? '';
    String tarikhStr = '';
    String masaStr = '';
    if (tarikh is String && tarikh.isNotEmpty) {
      try {
        final dt = DateTime.parse(tarikh);
        tarikhStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        masaStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        tarikhStr = tarikh.length > 10 ? tarikh.substring(0, 10) : tarikh;
      }
    } else {
      final now = DateTime.now();
      tarikhStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      masaStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }

    // Parse items
    List<Map<String, dynamic>> items = [];
    if (job['items_array'] is List && (job['items_array'] as List).isNotEmpty) {
      items = (job['items_array'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      items = [
        {
          'nama': (job['kerosakan'] ?? '-').toString(),
          'harga': double.tryParse(job['harga']?.toString() ?? '0') ?? 0,
        }
      ];
    }

    double total = items.fold(0.0, (sum, item) {
      final h = double.tryParse(item['harga']?.toString() ?? '0') ?? 0;
      final qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      return sum + (h * qty);
    });

    // ── HEADER (escCenter handles alignment — no manual padding) ──
    var r = escInit;
    r += '\n\n';
    r += escCenter + escDblSize + escBoldOn;
    r += '${namaKedai.length > 24 ? namaKedai.substring(0, 24) : namaKedai}\n';
    r += escNormal + escBoldOff;
    r += '\n';
    r += escCenter;
    if (alamat.isNotEmpty) {
      final words = alamat.split(', ');
      var line = '';
      for (final w in words) {
        if (line.isEmpty) {
          line = w;
        } else if ('$line, $w'.length <= lebar) {
          line = '$line, $w';
        } else {
          r += '$line\n';
          line = w;
        }
      }
      if (line.isNotEmpty) r += '$line\n';
    }
    r += 'Tel: $telKedai\n';
    r += '\n';
    r += garis;

    // ── INFO PELANGGAN ──
    r += '\n';
    r += escLeft;
    final tarikhLine = 'Tarikh: $tarikhStr';
    final masaLine = 'Masa: $masaStr';
    if (masaStr.isNotEmpty) {
      final gap = lebar - tarikhLine.length - masaLine.length;
      r += '$tarikhLine${' ' * (gap > 0 ? gap : 2)}$masaLine\n';
    } else {
      r += '$tarikhLine\n';
    }
    r += '\n';
    r += baris('No. Siri', ': $siri');
    r += baris('Pelanggan', ': ${(job['nama'] ?? '-').toString().length > 28 ? (job['nama'] ?? '-').toString().substring(0, 28) : job['nama'] ?? '-'}');
    r += baris('No. Tel', ': ${job['tel'] ?? '-'}');
    r += baris('Model', ': ${(job['model'] ?? '-').toString().length > 28 ? (job['model'] ?? '-').toString().substring(0, 28) : job['model'] ?? '-'}');
    r += '\n';
    r += garis2;

    // ── ITEM HEADER ──
    r += '\n';
    r += escBoldOn;
    r += 'ITEM                          QTY  HARGA(RM)\n';
    r += escBoldOff;
    r += garis2;
    r += '\n';

    // ── SENARAI ITEM ──
    for (final item in items) {
      final namaItem = (item['nama'] ?? '-').toString();
      final qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      final harga = double.tryParse(item['harga']?.toString() ?? '0') ?? 0;
      final hargaStr = harga.toStringAsFixed(2);
      final qtyStr = qty.toString();

      // Nama item — potong jika panjang, atau wrap ke baris baru
      if (namaItem.length > 30) {
        r += '${namaItem.substring(0, 30)}\n';
        final tail = '${' ' * 30}${qtyStr.padLeft(3)}  ${hargaStr.padLeft(10)}\n';
        r += tail;
      } else {
        final pad = 30 - namaItem.length;
        r += '$namaItem${' ' * (pad > 0 ? pad : 1)}${qtyStr.padLeft(3)}  ${hargaStr.padLeft(10)}\n';
      }
    }

    r += '\n';
    r += garis2;

    // ── TOTAL ──
    r += '\n';
    r += escBoldOn;
    final totalStr = 'RM ${total.toStringAsFixed(2)}';
    final totalLabel = 'TOTAL:';
    final totalGap = lebar - totalLabel.length - totalStr.length;
    r += '$totalLabel${' ' * (totalGap > 0 ? totalGap : 1)}$totalStr\n';
    r += escBoldOff;
    r += '\n';
    r += garis;

    // ── NOTA KAKI (escCenter active — no manual padding) ──
    if (notaKaki.toString().isNotEmpty) {
      r += '\n';
      r += escCenter;
      final notaWords = notaKaki.toString().split(' ');
      var notaLine = '';
      for (final w in notaWords) {
        if (notaLine.isEmpty) {
          notaLine = w;
        } else if ('$notaLine $w'.length <= lebar) {
          notaLine = '$notaLine $w';
        } else {
          r += '$notaLine\n';
          notaLine = w;
        }
      }
      if (notaLine.isNotEmpty) r += '$notaLine\n';
      r += '\n';
    }

    r += garis;
    r += '\n';
    r += '${escCenter}Terima Kasih\n';
    r += '\n\n\n\n\n\n\x1D\x56\x00'; // extra feed (2x panjang) + cut

    final bytes = utf8.encode(r);
    return await printRaw(bytes);
  }

  // ═══════════════════════════════════════
  // LABEL PRINTER (Niimbot via package / Standard BLE)
  // ═══════════════════════════════════════

  /// Check if saved label printer is Niimbot
  bool _isNiimbotPrinter() {
    final prefs = _cachedLabelName.toLowerCase();
    return prefs.contains('niimbot') || prefs.contains('b21') ||
           prefs.contains('b1') || prefs.contains('b18') ||
           prefs.contains('b16') || prefs.contains('d11') ||
           prefs.contains('d110') || prefs.contains('b203') ||
           prefs.contains('b3s');
  }

  String _cachedLabelName = '';

  Future<void> _loadLabelName() async {
    if (_cachedLabelName.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedLabelName = prefs.getString('printer_label_name') ?? '';
  }

  /// Print label — routes to Niimbot package or standard BLE
  Future<bool> printLabel(Map<String, dynamic> job, Map<String, dynamic> branchSettings) async {
    await _loadLabelName();
    if (_cachedLabelName.isEmpty) return false;

    if (_isNiimbotPrinter()) {
      return _printNiimbotLabel(job);
    }
    return _printStandardLabel(job);
  }

  // ─── NIIMBOT (via niimbot_print package) ───

  // Niimbot removed — route to standard BLE label printer instead
  Future<bool> _printNiimbotLabel(Map<String, dynamic> job) async {
    return _printStandardLabel(job);
  }

  // ─── STANDARD LABEL PRINTER (BLE + TSPL) ───

  Future<bool> _autoConnectStandardLabel() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('printer_label_id') ?? '';
    final savedName = prefs.getString('printer_label_name') ?? '';

    if (savedId.isEmpty && savedName.isEmpty) return false;
    if (_labelConnected && _labelWriteChar != null) return true;

    try {
      if (!kIsWeb) {
        final isOn = await FlutterBluePlus.adapterState.first;
        if (isOn != BluetoothAdapterState.on) return false;
      }

      if (savedId.isNotEmpty) {
        try {
          final device = BluetoothDevice.fromId(savedId);
          await device.connect(license: License.free, timeout: const Duration(seconds: 8));
          final found = await _findLabelWriteChar(device);
          if (found) return true;
        } catch (_) {}
      }

      if (savedName.isNotEmpty) {
        final found = await _scanAndConnect(savedName, _findLabelWriteChar);
        if (found) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _findLabelWriteChar(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _labelDevice = device;
            _labelWriteChar = char;
            _labelConnected = true;
            device.connectionState.listen((state) {
              if (state == BluetoothConnectionState.disconnected) {
                _labelConnected = false;
                _labelWriteChar = null;
              }
            });
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<bool> writeLabelRaw(List<int> data) async {
    if (!_labelConnected || _labelWriteChar == null) {
      final ok = await _autoConnectStandardLabel();
      if (!ok) return false;
    }
    try {
      const chunkSize = 128;
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
        final chunk = data.sublist(i, end);
        if (_labelWriteChar!.properties.writeWithoutResponse) {
          await _labelWriteChar!.write(chunk, withoutResponse: true);
        } else {
          await _labelWriteChar!.write(chunk);
        }
      }
      return true;
    } catch (_) {
      _labelConnected = false;
      _labelWriteChar = null;
      return false;
    }
  }

  Future<bool> _printStandardLabel(Map<String, dynamic> job) async {
    final siri = job['siri'] ?? '-';
    final nama = (job['nama'] ?? '-').toString();
    final tel = (job['tel'] ?? '-').toString();
    final model = (job['model'] ?? '-').toString();

    List<Map<String, dynamic>> items = [];
    if (job['items_array'] is List && (job['items_array'] as List).isNotEmpty) {
      items = (job['items_array'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      items = [
        {
          'nama': (job['kerosakan'] ?? '-').toString(),
          'harga': double.tryParse(job['harga']?.toString() ?? '0') ?? 0,
          'qty': 1,
        }
      ];
    }

    double total = items.fold(0.0, (sum, item) {
      final h = double.tryParse(item['harga']?.toString() ?? '0') ?? 0;
      final qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      return sum + (h * qty);
    });

    String kerosText;
    if (items.length == 1) {
      final n = (items[0]['nama'] ?? '-').toString();
      final qty = int.tryParse(items[0]['qty']?.toString() ?? '1') ?? 1;
      kerosText = qty > 1 ? '$n (x$qty)' : n;
    } else {
      kerosText = items.map((i) {
        final n = (i['nama'] ?? '-').toString();
        final qty = int.tryParse(i['qty']?.toString() ?? '1') ?? 1;
        return qty > 1 ? '$n(x$qty)' : n;
      }).join(', ');
    }

    final prefs = await SharedPreferences.getInstance();
    final labelW = double.tryParse(prefs.getString('printer_label_width') ?? '50') ?? 50;
    final labelH = double.tryParse(prefs.getString('printer_label_height') ?? '30') ?? 30;
    final lang = prefs.getString('printer_label_lang') ?? 'escpos';

    final lines = <String>[
      'SIRI: #$siri',
      'NAMA: $nama',
      'TEL: $tel',
      'MODEL: $model',
      'ROSAK: $kerosText',
      'RM ${total.toStringAsFixed(2)}',
    ];

    final bytes = lang == 'tspl'
        ? _buildTsplLabel(labelW, labelH, lines)
        : _buildEscPosLabel(labelW, labelH, lines);
    return await writeLabelRaw(bytes);
  }

  /// Print a test label using saved width/height so user can verify auto-cut.
  Future<bool> printTestLabel() async {
    await _loadLabelName();
    if (_cachedLabelName.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final labelW = double.tryParse(prefs.getString('printer_label_width') ?? '50') ?? 50;
    final labelH = double.tryParse(prefs.getString('printer_label_height') ?? '30') ?? 30;
    final lang = prefs.getString('printer_label_lang') ?? 'escpos';

    final lines = <String>[
      '*** CEK LABEL ***',
      'RMS PRO',
      '${labelW.toStringAsFixed(0)} x ${labelH.toStringAsFixed(0)} mm',
      DateTime.now().toString().substring(11, 19),
    ];

    final bytes = lang == 'tspl'
        ? _buildTsplLabel(labelW, labelH, lines)
        : _buildEscPosLabel(labelW, labelH, lines);
    return await writeLabelRaw(bytes);
  }

  // ─── ESC/POS label builder (default) ───
  // Works on most generic BLE thermal label printers. Feeds the exact number
  // of dots so each print advances by (labelH + fixed gap) every time.
  List<int> _buildEscPosLabel(double wMm, double hMm, List<String> lines) {
    // 203 DPI = 8 dots/mm
    final heightDots = (hMm * 8).round();
    const gapMm = 2; // fixed inter-label gap
    final gapDots = gapMm * 8;

    // Font A = 12w x 24h, Font B = 9w x 17h. Pick by width.
    final useFontB = wMm <= 35;
    final fontH = useFontB ? 17 : 24;
    final charW = useFontB ? 1.5 : 2.1;
    var maxChars = (wMm / charW).floor();
    if (maxChars < 6) maxChars = 6;

    String potong(String s) {
      if (s.length <= maxChars) return s;
      if (maxChars < 4) return s.substring(0, maxChars);
      return '${s.substring(0, maxChars - 2)}..';
    }

    final trimmed = lines.map(potong).toList();

    // Line spacing: try to distribute lines across label height.
    int spacing = trimmed.isEmpty ? fontH : (heightDots / trimmed.length).floor();
    if (spacing < fontH + 2) spacing = fontH + 2;
    if (spacing > fontH * 2) spacing = fontH * 2;
    final maxLines = (heightDots / spacing).floor().clamp(1, trimmed.length);
    final drawn = trimmed.take(maxLines).toList();

    final bytes = <int>[];
    bytes.addAll([0x1B, 0x40]); // init
    bytes.addAll([0x1B, 0x4D, useFontB ? 0x01 : 0x00]); // font A/B
    bytes.addAll([0x1B, 0x45, 0x01]); // bold on
    bytes.addAll([0x1D, 0x21, 0x00]); // size 1x1
    bytes.addAll([0x1B, 0x33, spacing.clamp(1, 255)]); // line spacing

    for (final line in drawn) {
      bytes.addAll(utf8.encode('$line\n'));
    }

    // Feed the remaining dots to reach exactly (heightDots + gapDots) per label.
    final usedDots = drawn.length * spacing;
    var remain = heightDots - usedDots + gapDots;
    if (remain < 0) remain = gapDots;
    while (remain > 0) {
      final chunk = remain > 255 ? 255 : remain;
      bytes.addAll([0x1B, 0x4A, chunk]); // ESC J n — feed n dots
      remain -= chunk;
    }

    return bytes;
  }

  // ─── TSPL label builder (opt-in for TSPL-compatible printers) ───
  List<int> _buildTsplLabel(double wMm, double hMm, List<String> lines) {
    final heightDots = (hMm * 8).round();
    final widthDots = (wMm * 8).round();

    final font = wMm <= 30 ? '2' : '3';
    final fontH = wMm <= 30 ? 16 : 24;
    final fontW = wMm <= 30 ? 8 : 12;

    const marginX = 8;
    const marginY = 8;
    final usableW = widthDots - (marginX * 2);
    var maxChars = (usableW / fontW).floor();
    if (maxChars < 6) maxChars = 6;

    String potong(String s) {
      if (s.length <= maxChars) return s;
      if (maxChars < 4) return s.substring(0, maxChars);
      return '${s.substring(0, maxChars - 2)}..';
    }

    String escape(String s) => s.replaceAll('"', "'").replaceAll('\\', '/');

    final usable = heightDots - (marginY * 2);
    int spacing = lines.isEmpty ? fontH : (usable / lines.length).floor();
    if (spacing < fontH + 2) spacing = fontH + 2;
    final maxLines = (usable / spacing).floor().clamp(1, lines.length);
    final drawn = lines.take(maxLines).toList();

    final sb = StringBuffer();
    sb.write('SIZE ${wMm.toStringAsFixed(0)} mm, ${hMm.toStringAsFixed(0)} mm\r\n');
    sb.write('GAP 2 mm, 0 mm\r\n');
    sb.write('DIRECTION 1\r\n');
    sb.write('REFERENCE 0,0\r\n');
    sb.write('CLS\r\n');
    int y = marginY;
    for (final line in drawn) {
      sb.write('TEXT $marginX,$y,"$font",0,1,1,"${escape(potong(line))}"\r\n');
      y += spacing;
    }
    sb.write('PRINT 1,1\r\n');

    return utf8.encode(sb.toString());
  }

  Future<void> disconnectLabel() async {
    try { await _labelDevice?.disconnect(); } catch (_) {}
    _labelDevice = null;
    _labelWriteChar = null;
    _labelConnected = false;
    _niimbotConnected = false;
  }
}
