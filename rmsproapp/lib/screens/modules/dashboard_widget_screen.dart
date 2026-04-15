import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/supabase_client.dart';
import '../../services/repair_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/branch_service.dart';
import '../../services/app_language.dart';
import '../../services/printer_service.dart';

class DashboardWidgetScreen extends StatefulWidget {
  final BranchService branchService;
  const DashboardWidgetScreen({super.key, required this.branchService});

  @override
  State<DashboardWidgetScreen> createState() => _DashboardWidgetScreenState();
}

class _DashboardWidgetScreenState extends State<DashboardWidgetScreen> {
  final _lang = AppLanguage();
  final _sb = SupabaseService.client;
  final _repairService = RepairService();
  String _ownerID = 'admin', _shopID = 'MAIN';
  String? _tenantId;
  String? _branchId;
  String _filterStats = 'TODAY', _filterKew = 'TODAY';
  String _kataHariIni =
      '"Konsisten adalah kunci kejayaan. Lakukan yang terbaik hari ini."';

  // Stats
  int _total = 0, _prog = 0, _wait = 0, _ready = 0, _comp = 0, _cancel = 0;
  // Kewangan
  double _sales = 0, _expense = 0, _refund = 0;
  // Data
  List<Map<String, dynamic>> _allRepairs = [];
  List<Map<String, dynamic>> _allExpenses = [];
  List<Map<String, dynamic>> _allJualanPantas = [];
  List<Map<String, dynamic>> _inventory = [];
  List<String> _staffList = [];
  // Existing customers for quick sales autocomplete
  List<Map<String, dynamic>> _existingCustomers = [];
  // Komponen search results
  List<Map<String, dynamic>> _bateriResults = [];
  List<Map<String, dynamic>> _lcdResults = [];
  bool _isSearchingKomponen = false;
  // Quick sales
  final _jpItemCtrl = TextEditingController();
  final _jpHargaCtrl = TextEditingController();
  final _jpCustNameCtrl = TextEditingController();
  final _jpCustTelCtrl = TextEditingController();
  final _komponenCtrl = TextEditingController();
  String _jpStaff = '';
  bool _showCustBox = false;
  bool _isSavingJP = false;
  bool _jpLocked = false;
  String _jpSavedSiri = '';
  Map<String, dynamic> _jpSavedData = {};

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _jpItemCtrl.dispose();
    _jpHargaCtrl.dispose();
    _jpCustNameCtrl.dispose();
    _jpCustTelCtrl.dispose();
    _komponenCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _repairService.init();
    _ownerID = _repairService.ownerID;
    _shopID = _repairService.shopID;
    _tenantId = _repairService.tenantId;
    _branchId = _repairService.branchId;
    _listenRepairs();
    _listenExpenses();
    _listenJualanPantas();
    _listenInventory();
    _loadStaff();
    _loadQuote();
  }

  int _tsFromIso(dynamic v) {
    if (v is int) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }

  // ─── LISTENERS ───
  void _listenRepairs() {
    if (_branchId == null) return;
    _subs.add(_sb
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = <Map<String, dynamic>>[];
      final custSeen = <String>{};
      final custs = <Map<String, dynamic>>[];
      for (final r in rows) {
        final d = Map<String, dynamic>.from(r);
        d['timestamp'] = _tsFromIso(r['created_at']);
        list.add(d);
        final tel = (d['tel'] ?? '').toString();
        if (tel.isNotEmpty && tel != '-' && !custSeen.contains(tel)) {
          custSeen.add(tel);
          custs.add({'nama': d['nama'] ?? '', 'tel': tel});
        }
      }
      if (mounted) {
        setState(() {
          _allRepairs = list;
          _existingCustomers = custs;
          _updateStats();
          _updateKewangan();
        });
      }
    }));
  }

  void _listenExpenses() {
    if (_branchId == null) return;
    _subs.add(_sb
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map((r) {
        final d = Map<String, dynamic>.from(r);
        d['jumlah'] = r['amount'] ?? 0;
        d['amaun'] = r['amount'] ?? 0;
        d['perkara'] = r['description'] ?? '';
        d['timestamp'] = _tsFromIso(r['created_at']);
        return d;
      }).toList();
      if (mounted) {
        setState(() {
          _allExpenses = list;
          _updateKewangan();
        });
      }
    }));
  }

  void _listenJualanPantas() {
    if (_branchId == null) return;
    _subs.add(_sb
        .from('quick_sales')
        .stream(primaryKey: ['id'])
        .eq('branch_id', _branchId!)
        .listen((rows) {
      final list = rows.map((r) {
        final d = Map<String, dynamic>.from(r);
        d['total'] = r['amount'] ?? 0;
        d['timestamp'] = _tsFromIso(r['sold_at']);
        return d;
      }).toList();
      if (mounted) {
        setState(() {
          _allJualanPantas = list;
          _updateKewangan();
        });
      }
    }));
  }

  void _listenInventory() {
    if (_tenantId == null) return;
    // FAST SERVICE dari stock_parts (category='FAST SERVICE')
    _subs.add(_sb
        .from('stock_parts')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', _tenantId!)
        .listen((rows) {
      final fastService = rows
          .where((d) => ((d['qty'] as num?) ?? 0) > 0 && (d['category'] ?? '').toString().toUpperCase() == 'FAST SERVICE')
          .map((d) => {
                'id': d['id'],
                'source': 'inventory',
                'nama': d['part_name'] ?? '',
                'kod': d['sku'] ?? '',
                'jual': d['price'] ?? 0,
                'qty': d['qty'] ?? 0,
                'category': d['category'] ?? '',
              })
          .toList();
      _inventory = [...fastService, ..._inventory.where((d) => d['source'] == 'accessories')];
    }));
    _subs.add(_sb
        .from('accessories')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', _tenantId!)
        .listen((rows) {
      final acc = rows
          .where((d) => ((d['qty'] as num?) ?? 0) > 0)
          .map((d) => {
                'id': d['id'],
                'source': 'accessories',
                'nama': d['item_name'] ?? '',
                'kod': d['sku'] ?? '',
                'jual': d['price'] ?? 0,
                'qty': d['qty'] ?? 0,
              })
          .toList();
      _inventory = [..._inventory.where((d) => d['source'] != 'accessories'), ...acc];
    }));
  }

  Future<void> _loadStaff() async {
    if (_branchId == null) return;
    try {
      final row = await _sb
          .from('branches')
          .select('branch_staff(nama, status)')
          .eq('id', _branchId!)
          .maybeSingle();
      final staffRaw = row?['branch_staff'];
      if (staffRaw is List) {
        _staffList = staffRaw
            .where((s) => s is Map && (s['status'] ?? 'active') == 'active')
            .map((s) => (s['nama'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList();
        if (_staffList.isNotEmpty && mounted) {
          setState(() => _jpStaff = _staffList.first);
        }
      }
    } catch (_) {}
  }

  void _loadQuote() async {
    try {
      final row = await _sb.from('system_settings').select('message').eq('id', 'pengumuman').maybeSingle();
      final m = row?['message'];
      if (m != null && mounted) {
        setState(() => _kataHariIni = '"$m"');
      }
    } catch (_) {}
  }

  // ─── TIME RANGE HELPERS ───
  (int, int) _getRange(String period) {
    final now = DateTime.now();
    DateTime start;
    switch (period) {
      case 'TODAY':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'WEEK':
        start = now.subtract(Duration(days: now.weekday % 7));
        start = DateTime(start.year, start.month, start.day);
        break;
      case 'MONTH':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'YEAR':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = DateTime(2020);
    }
    return (start.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  }

  // ─── STATS CALCULATION ───
  void _updateStats() {
    final range = _getRange(_filterStats);
    final filtered = _allRepairs.where((d) {
      final ts = d['timestamp'] ?? 0;
      final nama = (d['nama'] ?? '').toString().toUpperCase();
      final jenis = (d['jenis_servis'] ?? '').toString().toUpperCase();
      return ts >= range.$1 &&
          ts <= range.$2 &&
          nama != 'JUALAN PANTAS' &&
          nama != 'QUICK SALES' &&
          jenis != 'JUALAN';
    }).toList();
    _total = filtered.length;
    _prog = filtered
        .where((d) =>
            (d['status'] ?? '').toString().toUpperCase() == 'IN PROGRESS')
        .length;
    _wait = filtered
        .where((d) =>
            (d['status'] ?? '').toString().toUpperCase() == 'WAITING PART')
        .length;
    _ready = filtered
        .where((d) =>
            (d['status'] ?? '').toString().toUpperCase() ==
            'READY TO PICKUP')
        .length;
    _comp = filtered
        .where((d) =>
            (d['status'] ?? '').toString().toUpperCase() == 'COMPLETED')
        .length;
    _cancel = filtered.where((d) {
      final s = (d['status'] ?? '').toString().toUpperCase();
      return s == 'CANCEL' || s == 'CANCELLED';
    }).length;
  }

  // ─── KEWANGAN CALCULATION ───
  void _updateKewangan() {
    final range = _getRange(_filterKew);
    double sales = 0, refund = 0, expense = 0;

    // From repairs (PAID)
    for (final d in _allRepairs) {
      final ts = d['timestamp'] ?? 0;
      if (ts >= range.$1 && ts <= range.$2) {
        if ((d['payment_status'] ?? '').toString().toUpperCase() == 'PAID') {
          final total =
              double.tryParse(d['total']?.toString() ?? '0') ?? 0;
          final st = (d['status'] ?? '').toString().toUpperCase();
          if (st == 'CANCEL' || st == 'CANCELLED' || st == 'REFUND') {
            refund += total;
          } else {
            sales += total;
          }
        }
      }
    }

    // From jualan_pantas
    for (final d in _allJualanPantas) {
      final ts = d['timestamp'] ?? 0;
      if (ts >= range.$1 && ts <= range.$2) {
        if ((d['payment_status'] ?? '').toString().toUpperCase() == 'PAID') {
          final total =
              double.tryParse(d['total']?.toString() ?? '0') ?? 0;
          // Avoid double count: skip if same siri already in repairs
          final siri = (d['siri'] ?? '').toString();
          final alreadyCounted =
              _allRepairs.any((r) => (r['siri'] ?? '').toString() == siri);
          if (!alreadyCounted) {
            sales += total;
          }
        }
      }
    }

    // From expenses
    for (final d in _allExpenses) {
      final ts = d['timestamp'] ?? 0;
      if (ts >= range.$1 && ts <= range.$2) {
        final amt =
            double.tryParse(d['amount']?.toString() ?? '0') ?? 0;
        expense += amt;
      }
    }

    _sales = sales;
    _refund = refund;
    _expense = expense;
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: err ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── QUICK SALES ───
  Future<void> _simpanJualanPantas() async {
    final item = _jpItemCtrl.text.trim();
    final harga = double.tryParse(_jpHargaCtrl.text) ?? 0;
    if (item.isEmpty || harga <= 0 || _jpStaff.isEmpty) {
      _snack('Sila isi Item, Harga & Staff', err: true);
      return;
    }

    setState(() => _isSavingJP = true);
    final custName = _jpCustNameCtrl.text.trim().isNotEmpty
        ? _jpCustNameCtrl.text.trim().toUpperCase()
        : 'QUICK SALES';
    final custTel = _jpCustTelCtrl.text.trim().isNotEmpty
        ? _jpCustTelCtrl.text.trim()
        : '-';
    final siri = (10000000 + Random().nextInt(90000000)).toString();
    final tarikhNow = DateTime.now();

    final data = {
      'siri': siri,
      'receiptNo': siri,
      'shopID': _shopID,
      'nama': custName,
      'pelanggan': custName,
      'tel': custTel,
      'telefon': custTel,
      'tel_wasap': custTel,
      'wasap': custTel,
      'model': item.toUpperCase(),
      'kerosakan': '-',
      'items_array': [
        {'nama': item.toUpperCase(), 'qty': 1, 'harga': harga}
      ],
      'tarikh': DateFormat("yyyy-MM-dd'T'HH:mm").format(tarikhNow),
      'harga': harga.toStringAsFixed(2),
      'deposit': '0',
      'diskaun': '0',
      'tambahan': '0',
      'total': harga.toStringAsFixed(2),
      'baki': '0',
      'voucher_generated': '-',
      'voucher_used': '-',
      'voucher_used_amt': 0,
      'payment_status': 'PAID',
      'cara_bayaran': 'CASH',
      'catatan': '-',
      'jenis_servis': 'JUALAN',
      'staff_terima': _jpStaff,
      'staff_repair': _jpStaff,
      'staff_serah': _jpStaff,
      'password': '-',
      'cust_type': 'NEW CUST',
      'status': 'COMPLETED',
      'timestamp': tarikhNow.millisecondsSinceEpoch,
    };

    if (_tenantId == null || _branchId == null) {
      _snack('Tenant/branch belum dimuatkan', err: true);
      return;
    }

    try {
      // Insert ke jobs (untuk listing) + quick_sales (untuk income log)
      final jobRow = await _sb.from('jobs').insert({
        'tenant_id': _tenantId,
        'branch_id': _branchId,
        'siri': siri,
        'receipt_no': siri,
        'nama': data['nama'],
        'tel': data['tel'],
        'tel_wasap': data['tel_wasap'],
        'model': data['model'],
        'kerosakan': '-',
        'jenis_servis': 'JUALAN',
        'status': 'COMPLETED',
        'tarikh': DateFormat('yyyy-MM-dd').format(tarikhNow),
        'harga': harga,
        'total': harga,
        'baki': 0,
        'payment_status': 'PAID',
        'cara_bayaran': 'CASH',
        'staff_terima': _jpStaff,
        'staff_repair': _jpStaff,
        'staff_serah': _jpStaff,
        'cust_type': 'NEW CUST',
        'catatan': '-',
      }).select('id').single();
      // Job items kalau ada
      final jobId = jobRow['id'] as String;
      if ((data['items_array'] is List) && (data['items_array'] as List).isNotEmpty) {
        await _sb.from('job_items').insert((data['items_array'] as List).map((i) {
          final m = Map<String, dynamic>.from(i as Map);
          return {
            'tenant_id': _tenantId,
            'job_id': jobId,
            'nama': m['nama'],
            'qty': m['qty'],
            'harga': m['harga'],
          };
        }).toList());
      }
      await _sb.from('quick_sales').insert({
        'tenant_id': _tenantId,
        'branch_id': _branchId,
        'kind': 'JUALAN PANTAS',
        'amount': harga,
        'description': siri,
        'sold_by': _jpStaff,
        'payment_method': 'CASH',
      });
      _snack('Jualan Disimpan! Siri: #$siri');
      if (mounted) setState(() {
        _isSavingJP = false;
        _jpLocked = true;
        _jpSavedSiri = siri;
        _jpSavedData = data;
      });
      return;
    } catch (e) {
      _snack('Gagal simpan: $e', err: true);
    }
    if (mounted) setState(() => _isSavingJP = false);
  }

  void _jpResetForm() {
    setState(() {
      _jpItemCtrl.clear();
      _jpHargaCtrl.clear();
      _jpCustNameCtrl.clear();
      _jpCustTelCtrl.clear();
      _jpLocked = false;
      _jpSavedSiri = '';
      _jpSavedData = {};
    });
  }

  void _jpShowPrintPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const FaIcon(FontAwesomeIcons.print, size: 14, color: AppColors.blue),
            const SizedBox(width: 8),
            Text('CETAK RESIT #$_jpSavedSiri', style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w900)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await PrinterService().printReceipt(_jpSavedData, {});
              _snack(ok ? 'Resit 80mm berjaya dicetak' : 'Gagal cetak. Sila sambung printer', err: !ok);
            },
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.25))),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: FaIcon(FontAwesomeIcons.receipt, size: 16, color: AppColors.blue))),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Resit 80mm', style: TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.w900)),
                  Text('Thermal Bluetooth', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                ])),
              ]),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              _snack('Sila generate PDF dari senarai job untuk A4/A5');
            },
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.25))),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: FaIcon(FontAwesomeIcons.print, size: 16, color: AppColors.green))),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('A4 / A5', style: TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
                  Text('WiFi / Bluetooth', style: TextStyle(color: AppColors.textDim, fontSize: 10)),
                ])),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── KOMPONEN SEARCH ───
  Future<void> _cariKomponen() async {
    final carian = _komponenCtrl.text.trim().toLowerCase();
    if (carian.isEmpty) return;
    setState(() {
      _isSearchingKomponen = true;
      _bateriResults = [];
      _lcdResults = [];
    });

    try {
      // Stash dalam platform_config (id=battery_db / lcd_db) jsonb {items: [...]}
      final results = await Future.wait([
        _sb.from('platform_config').select('value').eq('id', 'battery_db').maybeSingle(),
        _sb.from('platform_config').select('value').eq('id', 'lcd_db').maybeSingle(),
      ]);

      final bateriItems = (results[0]?['value']?['items'] as List?) ?? [];
      final lcdItems = (results[1]?['value']?['items'] as List?) ?? [];
      final bateri = <Map<String, dynamic>>[];
      final lcd = <Map<String, dynamic>>[];

      for (final item in bateriItems) {
        final d = Map<String, dynamic>.from(item as Map);
        final m = (d['model'] ?? '').toString().toLowerCase();
        final k = (d['kod'] ?? '').toString().toLowerCase();
        final i = (d['info'] ?? '').toString().toLowerCase();
        if (m.contains(carian) || k.contains(carian) || i.contains(carian)) {
          bateri.add(d);
        }
      }
      for (final item in lcdItems) {
        final d = Map<String, dynamic>.from(item as Map);
        final m = (d['model'] ?? '').toString().toLowerCase();
        final k = (d['kod'] ?? '').toString().toLowerCase();
        final i = (d['info'] ?? '').toString().toLowerCase();
        if (m.contains(carian) || k.contains(carian) || i.contains(carian)) {
          lcd.add(d);
        }
      }
      if (mounted) {
        setState(() {
          _bateriResults = bateri;
          _lcdResults = lcd;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingKomponen = false);
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildQuoteCard(),
        const SizedBox(height: 15),
        // 2x2 Grid
        LayoutBuilder(builder: (ctx, constraints) {
          final isWide = constraints.maxWidth > 700;
          if (isWide) {
            return Column(children: [
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildStatsBox()),
                    const SizedBox(width: 15),
                    Expanded(child: _buildKomponenBox()),
                  ]),
              const SizedBox(height: 15),
              _buildKewanganBox(),
            ]);
          }
          return Column(children: [
            _buildStatsBox(),
            const SizedBox(height: 15),
            _buildKomponenBox(),
            const SizedBox(height: 15),
            _buildKewanganBox(),
          ]);
        }),
        const SizedBox(height: 30),
      ]),
    );
  }

  // ─── MOTIVATIONAL QUOTE CARD ───
  Widget _buildQuoteCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        FaIcon(FontAwesomeIcons.quoteLeft,
            size: 16, color: AppColors.textDim),
        const SizedBox(width: 14),
        Expanded(
          child: Text(_kataHariIni,
              style: const TextStyle(
                  color: AppColors.textSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  height: 1.5)),
        ),
      ]),
    );
  }

  // ─── BOX 1: STATISTIK KEDAI ───
  Widget _buildStatsBox() {
    return _glassBox(
      'STATISTIK KEDAI',
      FontAwesomeIcons.chartPie,
      AppColors.primary,
      trailing: _periodChip(
          _filterStats,
          (v) => setState(() {
                _filterStats = v;
                _updateStats();
              }),
          showAll: true),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.3,
        children: [
          _statCard('Total Job', _total, AppColors.primary),
          _statCard('In Progress', _prog, AppColors.yellow),
          _statCard('Wait Part', _wait, AppColors.orange),
          _statCard('Ready', _ready, AppColors.blue),
          _statCard('Selesai', _comp, AppColors.green),
          _statCard('Batal', _cancel, AppColors.red),
        ],
      ),
    );
  }

  // ─── BOX 2: POS ───
  Widget _buildQuickSalesBox() {
    return _glassBox(
      'POS',
      FontAwesomeIcons.cashRegister,
      AppColors.red,
      trailing: GestureDetector(
        onTap: () => setState(() => _showCustBox = !_showCustBox),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bg,
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
              child: FaIcon(FontAwesomeIcons.userPlus,
                  size: 12, color: AppColors.textMuted)),
        ),
      ),
      child: Column(children: [
        // Optional customer info
        if (_showCustBox)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              // Customer name with autocomplete from repairs
              Autocomplete<Map<String, dynamic>>(
                optionsBuilder: (v) => v.text.isEmpty
                    ? const Iterable.empty()
                    : _existingCustomers
                        .where((c) =>
                            (c['nama'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(v.text.toLowerCase()) ||
                            (c['tel'] ?? '')
                                .toString()
                                .contains(v.text))
                        .take(5),
                displayStringForOption: (o) =>
                    '${o['nama']} (${o['tel']})',
                onSelected: (o) {
                  _jpCustNameCtrl.text =
                      (o['nama'] ?? '').toString();
                  _jpCustTelCtrl.text =
                      (o['tel'] ?? '').toString();
                  setState(() {});
                },
                fieldViewBuilder: (_, ctrl, fn, _) {
                  if (ctrl.text.isEmpty &&
                      _jpCustNameCtrl.text.isNotEmpty) {
                    ctrl.text = _jpCustNameCtrl.text;
                  }
                  return _rawInput(
                      ctrl, fn, 'Nama Pelanggan (Pilihan)',
                      onChanged: (v) =>
                          _jpCustNameCtrl.text = v);
                },
                optionsViewBuilder: (_, onSel, opts) =>
                    _custAutoCompleteList(opts, onSel),
              ),
              const SizedBox(height: 8),
              // Tel with autocomplete
              Autocomplete<Map<String, dynamic>>(
                optionsBuilder: (v) => v.text.isEmpty
                    ? const Iterable.empty()
                    : _existingCustomers
                        .where((c) =>
                            (c['tel'] ?? '')
                                .toString()
                                .contains(v.text) ||
                            (c['nama'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(v.text.toLowerCase()))
                        .take(5),
                displayStringForOption: (o) =>
                    '${o['tel']} (${o['nama']})',
                onSelected: (o) {
                  _jpCustTelCtrl.text =
                      (o['tel'] ?? '').toString();
                  _jpCustNameCtrl.text =
                      (o['nama'] ?? '').toString();
                  setState(() {});
                },
                fieldViewBuilder: (_, ctrl, fn, _) {
                  if (ctrl.text.isEmpty &&
                      _jpCustTelCtrl.text.isNotEmpty) {
                    ctrl.text = _jpCustTelCtrl.text;
                  }
                  return _rawInput(
                      ctrl, fn, 'No Telefon (Pilihan)',
                      onChanged: (v) =>
                          _jpCustTelCtrl.text = v);
                },
                optionsViewBuilder: (_, onSel, opts) =>
                    _custAutoCompleteList(opts, onSel),
              ),
            ]),
          ),

        // Item input with inventory autocomplete
        Autocomplete<Map<String, dynamic>>(
          optionsBuilder: (v) => v.text.isEmpty
              ? const Iterable.empty()
              : _inventory
                  .where((inv) =>
                      (inv['nama'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(v.text.toLowerCase()) ||
                      (inv['kod'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(v.text.toLowerCase()))
                  .take(5),
          displayStringForOption: (o) => o['nama']?.toString() ?? '',
          onSelected: (o) {
            _jpItemCtrl.text = o['nama']?.toString() ?? '';
            _jpHargaCtrl.text =
                ((o['jual'] ?? 0) as num).toStringAsFixed(2);
            setState(() {});
          },
          fieldViewBuilder: (_, ctrl, fn, _) {
            if (ctrl.text.isEmpty && _jpItemCtrl.text.isNotEmpty) {
              ctrl.text = _jpItemCtrl.text;
            }
            return _rawInput(
                ctrl, fn, 'Cari dari inventori / taip manual...',
                onChanged: (v) => _jpItemCtrl.text = v);
          },
          optionsViewBuilder: (_, onSel, opts) =>
              _autoCompleteList(opts, onSel),
        ),
        const SizedBox(height: 10),

        // Harga
        _input(_jpHargaCtrl, 'Harga Jualan (RM)',
            keyboard:
                const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),

        // Staff dropdown
        _staffDropdown(),
        const SizedBox(height: 14),

        // Success banner
        if (_jpLocked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const FaIcon(FontAwesomeIcons.circleCheck, size: 12, color: AppColors.green),
              const SizedBox(width: 8),
              Text('DISIMPAN  #$_jpSavedSiri', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w900)),
            ]),
          ),

        // Action buttons — sentiasa visible
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isSavingJP || _jpLocked) ? null : _simpanJualanPantas,
            icon: _isSavingJP
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const FaIcon(FontAwesomeIcons.floppyDisk, size: 12),
            label: Text(_isSavingJP ? 'MENYIMPAN...' : 'SIMPAN JUALAN'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.textPrimary.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _jpLocked ? _jpShowPrintPopup : null,
            icon: const FaIcon(FontAwesomeIcons.print, size: 12),
            label: const Text('CETAK'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.blue.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton.icon(
            onPressed: _jpResetForm,
            icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 12),
            label: const Text('RESET'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ]),
    );
  }

  // ─── BOX 3: KOMPONEN ───
  Widget _buildKomponenBox() {
    return _glassBox(
      'KOMPONEN',
      FontAwesomeIcons.database,
      AppColors.blue,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(_lang.get('online'),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w900)),
      ),
      child: Column(children: [
        // 2 panel — Bateri & LCD
        Row(children: [
          Expanded(
              child: _komponenPanel('KOD BATERI', AppColors.blue,
                  _bateriResults, _isSearchingKomponen)),
          const SizedBox(width: 10),
          Expanded(
              child: _komponenPanel('LCD COMPATIBLE', AppColors.yellow,
                  _lcdResults, _isSearchingKomponen)),
        ]),
        const SizedBox(height: 12),
        // Search bar
        Row(children: [
          // Clear button
          GestureDetector(
            onTap: () {
              _komponenCtrl.clear();
              setState(() {
                _bateriResults = [];
                _lcdResults = [];
              });
            },
            child: Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border)),
              child: const Center(
                  child: FaIcon(FontAwesomeIcons.broom,
                      size: 12, color: AppColors.textMuted)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _rawInput(
                TextEditingController()..text = _komponenCtrl.text,
                null,
                'Cari Model...',
                onChanged: (v) => _komponenCtrl.text = v,
                onSubmitted: (_) => _cariKomponen()),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cariKomponen,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(FontAwesomeIcons.magnifyingGlass,
                        size: 11, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(_lang.get('cari'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900)),
                  ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _komponenPanel(String title, Color color,
      List<Map<String, dynamic>> results, bool loading) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(9)),
            border:
                Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
        ),
        Expanded(
          child: loading
              ? Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: color)))
              : results.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          FaIcon(
                              title.contains('BATERI')
                                  ? FontAwesomeIcons.batteryHalf
                                  : FontAwesomeIcons
                                      .mobileScreenButton,
                              size: 20,
                              color: AppColors.textDim),
                          const SizedBox(height: 6),
                          Text(_lang.get('dw_sedia'),
                              style: const TextStyle(
                                  color: AppColors.textDim,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final d = results[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                                left: BorderSide(
                                    color: AppColors.textDim, width: 3)),
                          ),
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(d['model'] ?? '-',
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.bold)),
                                Text(d['kod'] ?? '-',
                                    style: const TextStyle(
                                        color: AppColors.textSub,
                                        fontSize: 12,
                                        fontWeight:
                                            FontWeight.w900)),
                                Text(d['info'] ?? '-',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 9)),
                              ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  // ─── BOX 4: KEWANGAN ───
  Widget _buildKewanganBox() {
    return _glassBox(
      'KEWANGAN',
      FontAwesomeIcons.wallet,
      AppColors.green,
      trailing: _periodChip(
          _filterKew,
          (v) => setState(() {
                _filterKew = v;
                _updateKewangan();
              })),
      child: Column(children: [
        _kewCard('Jualan (Paid)', 'RM ${_sales.toStringAsFixed(2)}',
            FontAwesomeIcons.moneyBill, AppColors.green),
        const SizedBox(height: 10),
        _kewCard('Duit Keluar', 'RM ${_expense.toStringAsFixed(2)}',
            FontAwesomeIcons.arrowTrendDown, AppColors.yellow),
        const SizedBox(height: 10),
        _kewCard('Refund', 'RM ${_refund.toStringAsFixed(2)}',
            FontAwesomeIcons.rotate, AppColors.red),
      ]),
    );
  }

  // ═══════════════════════════════════════
  // REUSABLE WIDGETS
  // ═══════════════════════════════════════
  Widget _glassBox(String title, IconData icon, Color color,
      {Widget? trailing, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    FaIcon(icon, size: 12, color: color),
                    const SizedBox(width: 8),
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1)),
                  ]),
                  ?trailing,
                ]),
            Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 1,
                color: AppColors.borderLight),
            child,
          ]),
    );
  }

  Widget _statCard(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Text(value.toString(),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _kewCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              FaIcon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ]),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
          ]),
    );
  }

  Widget _periodChip(String current, ValueChanged<String> onChanged,
      {bool showAll = false}) {
    final opts = <String, String>{
      'TODAY': 'HARI INI',
      'WEEK': 'MINGGU',
      'MONTH': 'BULAN',
      'YEAR': 'TAHUN',
    };
    if (showAll) opts['ALL'] = 'SEMUA';

    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(opts[current] ?? current,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          const FaIcon(FontAwesomeIcons.chevronDown,
              size: 8, color: AppColors.textDim),
        ]),
      ),
      itemBuilder: (_) => opts.entries
          .map((e) => PopupMenuItem(
              value: e.key,
              child: Text(e.value,
                  style: TextStyle(
                      color: e.key == current
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))))
          .toList(),
    );
  }

  Widget _staffDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _staffList.contains(_jpStaff)
              ? _jpStaff
              : (_staffList.isNotEmpty ? _staffList.first : ''),
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold),
          hint: Text(_lang.get('dw_pilih_staff'),
              style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
          items: _staffList
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _jpStaff = v ?? ''),
        ),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppColors.textDim, fontSize: 11),
        filled: true,
        fillColor: AppColors.bg,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  Widget _rawInput(TextEditingController c, FocusNode? fn, String h,
      {ValueChanged<String>? onChanged,
      ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: c,
      focusNode: fn,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
      decoration: InputDecoration(
        hintText: h,
        hintStyle:
            const TextStyle(color: AppColors.textDim, fontSize: 11),
        filled: true,
        fillColor: AppColors.bg,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  Widget _autoCompleteList(Iterable<Map<String, dynamic>> opts,
      AutocompleteOnSelected<Map<String, dynamic>> onSel) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxHeight: 200, maxWidth: 300),
          child: ListView(
            shrinkWrap: true,
            children: opts
                .map((o) => InkWell(
                      onTap: () => onSel(o),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(o['kod']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                              Text(o['nama']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11)),
                              Text(
                                  'RM ${(o['jual'] as num?)?.toStringAsFixed(2) ?? '0'} (Stok: ${o['qty']})',
                                  style: const TextStyle(
                                      color: AppColors.textSub,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ]),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _custAutoCompleteList(Iterable<Map<String, dynamic>> opts,
      AutocompleteOnSelected<Map<String, dynamic>> onSel) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxHeight: 200, maxWidth: 300),
          child: ListView(
            shrinkWrap: true,
            children: opts
                .map((o) => InkWell(
                      onTap: () => onSel(o),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          const FaIcon(FontAwesomeIcons.userCheck,
                              size: 10, color: AppColors.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      (o['nama'] ?? '')
                                          .toString()
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.bold)),
                                  Text(
                                      'Tel: ${o['tel'] ?? '-'}',
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 9)),
                                ]),
                          ),
                        ]),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
