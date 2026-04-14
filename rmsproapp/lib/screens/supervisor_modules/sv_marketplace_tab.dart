import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
class SvMarketplaceTab extends StatefulWidget {
  final String ownerID, shopID;
  const SvMarketplaceTab({required this.ownerID, required this.shopID});
  @override
  State<SvMarketplaceTab> createState() => SvMarketplaceTabState();
}

// helper: compress image to ~30kb
Future<Uint8List?> compressImage(File file) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final decoded = frame.image;
  // Scale down if large
  double scale = 1.0;
  if (bytes.length > 30000) {
    scale = sqrt(30000 / bytes.length);
  }
  final w = (decoded.width * scale).round().clamp(50, 600);
  final h = (decoded.height * scale).round().clamp(50, 600);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final src = Rect.fromLTWH(
    0,
    0,
    decoded.width.toDouble(),
    decoded.height.toDouble(),
  );
  final dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  canvas.drawImageRect(decoded, src, dst, Paint());
  final pic = recorder.endRecording();
  final img = await pic.toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd?.buffer.asUint8List();
}

class SvMarketplaceTabState extends State<SvMarketplaceTab>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _myOrders = [];
  StreamSubscription? _sub;
  StreamSubscription? _ordersSub;
  bool _loading = true;
  bool _loadingOrders = true;
  String _filterCategory = 'Semua';
  bool _isGridView = true;

  // Stats
  double _totalSales = 0;
  int _totalSold = 0;

  final List<String> _categories = [
    'Semua',
    'LCD',
    'Bateri',
    'Casing',
    'Spare Part',
    'Aksesori',
    'Lain-lain',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _listen();
    _listenOrders();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ordersSub?.cancel();
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _listen() {
    _sub = _db
        .collection('marketplace_global')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _items = snap.docs.map((d) {
              final data = d.data();
              data['_docId'] = d.id;
              return data;
            }).toList();
            _loading = false;
            _applyFilter();
          });
        });
  }

  void _listenOrders() {
    _ordersSub = _db
        .collection('marketplace_orders')
        .where('sellerOwnerID', isEqualTo: widget.ownerID)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final orders = snap.docs.map((d) {
            final data = d.data();
            data['_docId'] = d.id;
            return data;
          }).toList();

          double sales = 0;
          int sold = 0;
          for (final o in orders) {
            if (o['status'] == 'completed') {
              sales += (o['sellerPayout'] is num
                  ? (o['sellerPayout'] as num).toDouble()
                  : 0);
              sold++;
            }
          }

          setState(() {
            _myOrders = orders;
            _totalSales = sales;
            _totalSold = sold;
            _loadingOrders = false;
          });
        });
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _items.where((item) {
        final matchSearch =
            q.isEmpty ||
            (item['itemName'] ?? '').toString().toLowerCase().contains(q) ||
            (item['description'] ?? '').toString().toLowerCase().contains(q) ||
            (item['shopName'] ?? '').toString().toLowerCase().contains(q);
        final matchCat =
            _filterCategory == 'Semua' || item['category'] == _filterCategory;
        return matchSearch && matchCat;
      }).toList();
    });
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: err ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tabs: Marketplace | Pesanan Saya
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _tabCtrl,
            indicator: BoxDecoration(
              color: const Color(0xFF8B5CF6),
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textDim,
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: [
              const Tab(text: 'MARKETPLACE'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('PESANAN SAYA'),
                    if (_myOrders
                        .where((o) => o['status'] == 'approved')
                        .isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_myOrders.where((o) => o['status'] == 'approved').length}',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [_buildMarketplaceTab(), _buildMyOrdersTab()],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // MARKETPLACE TAB
  // ═══════════════════════════════════════
  Widget _buildMarketplaceTab() {
    return Column(
      children: [
        // Search & Add & View toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cari item atau kedai...',
                    hintStyle: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 10, right: 8),
                      child: FaIcon(
                        FontAwesomeIcons.magnifyingGlass,
                        size: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    filled: true,
                    fillColor: AppColors.bgDeep,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Grid/List toggle
              GestureDetector(
                onTap: () => setState(() => _isGridView = !_isGridView),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: FaIcon(
                    _isGridView
                        ? FontAwesomeIcons.gripVertical
                        : FontAwesomeIcons.list,
                    size: 14,
                    color: AppColors.textSub,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showAddItemDialog,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const FaIcon(
                    FontAwesomeIcons.plus,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Category filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: SizedBox(
            height: 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final isActive = cat == _filterCategory;
                return GestureDetector(
                  onTap: () {
                    setState(() => _filterCategory = cat);
                    _applyFilter();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF8B5CF6)
                          : AppColors.bgDeep,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF8B5CF6)
                            : AppColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isActive ? Colors.white : AppColors.textSub,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Items
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                )
              : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.store,
                        size: 40,
                        color: AppColors.textDim.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tiada item dalam marketplace',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tekan + untuk jual item pertama',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                )
              : _isGridView
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _buildGridCard(_filtered[i]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildItemCard(_filtered[i]),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // MY ORDERS TAB (Pesanan Saya)
  // ═══════════════════════════════════════
  Widget _buildMyOrdersTab() {
    return Column(
      children: [
        // Sales stats
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'JUMLAH TERIMA',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'RM ${_totalSales.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'JUALAN SELESAI',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_totalSold',
                        style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Orders list
        Expanded(
          child: _loadingOrders
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                )
              : _myOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.inbox,
                        size: 36,
                        color: AppColors.textDim.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Tiada pesanan masuk',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _myOrders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildOrderCard(_myOrders[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final price = (order['totalPrice'] is num)
        ? (order['totalPrice'] as num).toDouble()
        : 0.0;
    final payout = (order['sellerPayout'] is num)
        ? (order['sellerPayout'] as num).toDouble()
        : 0.0;
    final qty = (order['quantity'] is num)
        ? (order['quantity'] as num).toInt()
        : 0;
    final status = order['status'] ?? 'pending';
    final tracking = order['tracking'] ?? '';
    final createdAt = order['createdAt'] is Timestamp
        ? DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format((order['createdAt'] as Timestamp).toDate())
        : '-';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor = const Color(0xFF3B82F6);
        statusLabel = 'DILULUSKAN';
        break;
      case 'completed':
        statusColor = AppColors.green;
        statusLabel = 'SELESAI';
        break;
      case 'rejected':
        statusColor = AppColors.red;
        statusLabel = 'DITOLAK';
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'MENUNGGU';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                createdAt,
                style: const TextStyle(color: AppColors.textDim, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (order['itemName'] ?? '-').toString().toUpperCase(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pembeli: ${(order['buyerShopName'] ?? '-').toString().toUpperCase()}',
            style: const TextStyle(
              color: AppColors.textSub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$qty × RM ${(order['pricePerUnit'] ?? 0).toStringAsFixed(2)} = RM ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Terima: RM ${payout.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (tracking.toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.truck,
                    size: 10,
                    color: Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tracking: $tracking',
                      style: const TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // GRID VIEW CARD
  // ═══════════════════════════════════════
  Widget _buildGridCard(Map<String, dynamic> item) {
    final isOwn = item['ownerID'] == widget.ownerID;
    final price = (item['price'] is num)
        ? (item['price'] as num).toDouble()
        : 0.0;
    final qty = (item['quantity'] is num)
        ? (item['quantity'] as num).toInt()
        : 0;
    final imageUrl = item['imageUrl'] as String?;

    return GestureDetector(
      onTap: () => _showItemDetail(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOwn
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                : AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
              child: Container(
                height: 100,
                width: double.infinity,
                color: AppColors.bgDeep,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: FaIcon(
                            FontAwesomeIcons.image,
                            size: 24,
                            color: AppColors.textDim,
                          ),
                        ),
                      )
                    : const Center(
                        child: FaIcon(
                          FontAwesomeIcons.image,
                          size: 24,
                          color: AppColors.textDim,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['itemName'] ?? '-').toString().toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      'RM ${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Stok: $qty',
                          style: TextStyle(
                            color: qty > 0 ? AppColors.textDim : AppColors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (isOwn)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF8B5CF6,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ANDA',
                              style: TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontSize: 7,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemDetail(Map<String, dynamic> item) {
    final isOwn = item['ownerID'] == widget.ownerID;
    final price = (item['price'] is num)
        ? (item['price'] as num).toDouble()
        : 0.0;
    final qty = (item['quantity'] is num)
        ? (item['quantity'] as num).toInt()
        : 0;
    final imageUrl = item['imageUrl'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Container(
                height: 200,
                width: double.infinity,
                color: AppColors.bgDeep,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: FaIcon(
                            FontAwesomeIcons.image,
                            size: 40,
                            color: AppColors.textDim,
                          ),
                        ),
                      )
                    : const Center(
                        child: FaIcon(
                          FontAwesomeIcons.image,
                          size: 40,
                          color: AppColors.textDim,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item['category'] ?? 'Lain-lain',
                            style: const TextStyle(
                              color: Color(0xFF8B5CF6),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (isOwn) ...[
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showEditItemDialog(item);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.bgDeep,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const FaIcon(
                                FontAwesomeIcons.penToSquare,
                                size: 10,
                                color: AppColors.textSub,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _confirmDelete(item['_docId']);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const FaIcon(
                                FontAwesomeIcons.trash,
                                size: 10,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (item['itemName'] ?? '-').toString().toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if ((item['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item['description'],
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'RM ${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF16A34A),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgDeep,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Stok: $qty',
                            style: TextStyle(
                              color: qty > 0
                                  ? AppColors.textSub
                                  : AppColors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.shop,
                            size: 10,
                            color: AppColors.textDim,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (item['shopName'] ?? item['ownerID'] ?? '-')
                                  .toString()
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textSub,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isOwn && qty > 0) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showBuyDialog(item);
                          },
                          icon: const FaIcon(
                            FontAwesomeIcons.cartShopping,
                            size: 12,
                          ),
                          label: const Text(
                            'BELI SEKARANG',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final isOwn = item['ownerID'] == widget.ownerID;
    final price = (item['price'] is num)
        ? (item['price'] as num).toDouble()
        : 0.0;
    final qty = (item['quantity'] is num)
        ? (item['quantity'] as num).toInt()
        : 0;
    final category = item['category'] ?? 'Lain-lain';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOwn
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (isOwn)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showEditItemDialog(item),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.penToSquare,
                          size: 10,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _confirmDelete(item['_docId']),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.trash,
                          size: 10,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              if (!isOwn && qty > 0)
                GestureDetector(
                  onTap: () => _showBuyDialog(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(
                          FontAwesomeIcons.cartShopping,
                          size: 10,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Beli',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Item name
          Text(
            (item['itemName'] ?? '-').toString().toUpperCase(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          if ((item['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item['description'],
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          // Price & Qty row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'RM ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Stok: $qty',
                  style: TextStyle(
                    color: qty > 0 ? AppColors.textSub : AppColors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Seller info
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.shop,
                  size: 10,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (item['shopName'] ?? item['ownerID'] ?? '-')
                        .toString()
                        .toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isOwn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ANDA',
                      style: TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    String selectedCat = 'Spare Part';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'JUAL ITEM BARU',
                  style: TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Item anda akan dipaparkan kepada semua dealer',
                  style: TextStyle(color: AppColors.textDim, fontSize: 10),
                ),
                const SizedBox(height: 16),

                _mpField(
                  'Nama Item *',
                  nameCtrl,
                  'Cth: LCD iPhone 13 Pro Max',
                  caps: true,
                ),
                _mpField(
                  'Penerangan',
                  descCtrl,
                  'Cth: Original, ada warranty 3 bulan',
                ),
                Row(
                  children: [
                    Expanded(
                      child: _mpField(
                        'Harga (RM) *',
                        priceCtrl,
                        '0.00',
                        keyboard: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _mpField(
                        'Kuantiti *',
                        qtyCtrl,
                        '1',
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),

                // Category picker
                const Text(
                  'Kategori',
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _categories.where((c) => c != 'Semua').map((cat) {
                    final isActive = cat == selectedCat;
                    return GestureDetector(
                      onTap: () => setS(() => selectedCat = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF8B5CF6)
                              : AppColors.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFF8B5CF6)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: isActive ? Colors.white : AppColors.textSub,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          priceCtrl.text.trim().isEmpty) {
                        _snack('Sila isi semua medan wajib (*)', err: true);
                        return;
                      }
                      final price = double.tryParse(priceCtrl.text.trim());
                      if (price == null || price <= 0) {
                        _snack('Harga tidak sah', err: true);
                        return;
                      }
                      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;

                      try {
                        // Get shop name
                        String shopName = widget.shopID;
                        try {
                          final shopDoc = await _db
                              .collection('shops_${widget.ownerID}')
                              .doc(widget.shopID)
                              .get();
                          if (shopDoc.exists)
                            shopName =
                                shopDoc.data()?['namaKedai'] ??
                                shopDoc.data()?['shopName'] ??
                                widget.shopID;
                        } catch (_) {}

                        await _db.collection('marketplace_global').add({
                          'ownerID': widget.ownerID,
                          'shopID': widget.shopID,
                          'shopName': shopName,
                          'itemName': nameCtrl.text.trim().toUpperCase(),
                          'description': descCtrl.text.trim(),
                          'price': price,
                          'quantity': qty,
                          'category': selectedCat,
                          'createdAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Item berjaya ditambah ke marketplace');
                      } catch (e) {
                        _snack('Gagal: $e', err: true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'SENARAIKAN ITEM',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditItemDialog(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(text: item['itemName'] ?? '');
    final descCtrl = TextEditingController(text: item['description'] ?? '');
    final priceCtrl = TextEditingController(
      text: (item['price'] ?? 0).toString(),
    );
    final qtyCtrl = TextEditingController(
      text: (item['quantity'] ?? 1).toString(),
    );
    String selectedCat = item['category'] ?? 'Spare Part';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'KEMASKINI ITEM',
                  style: TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),

                _mpField('Nama Item *', nameCtrl, '', caps: true),
                _mpField('Penerangan', descCtrl, ''),
                Row(
                  children: [
                    Expanded(
                      child: _mpField(
                        'Harga (RM) *',
                        priceCtrl,
                        '0.00',
                        keyboard: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _mpField(
                        'Kuantiti *',
                        qtyCtrl,
                        '1',
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Kategori',
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _categories.where((c) => c != 'Semua').map((cat) {
                    final isActive = cat == selectedCat;
                    return GestureDetector(
                      onTap: () => setS(() => selectedCat = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF8B5CF6)
                              : AppColors.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFF8B5CF6)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: isActive ? Colors.white : AppColors.textSub,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          priceCtrl.text.trim().isEmpty) {
                        _snack('Sila isi semua medan wajib (*)', err: true);
                        return;
                      }
                      final price = double.tryParse(priceCtrl.text.trim());
                      if (price == null || price <= 0) {
                        _snack('Harga tidak sah', err: true);
                        return;
                      }

                      try {
                        await _db
                            .collection('marketplace_global')
                            .doc(item['_docId'])
                            .update({
                              'itemName': nameCtrl.text.trim().toUpperCase(),
                              'description': descCtrl.text.trim(),
                              'price': price,
                              'quantity':
                                  int.tryParse(qtyCtrl.text.trim()) ?? 1,
                              'category': selectedCat,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Item berjaya dikemaskini');
                      } catch (e) {
                        _snack('Gagal: $e', err: true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'KEMASKINI',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Padam Item?',
          style: TextStyle(
            color: AppColors.red,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Item ini akan dikeluarkan dari marketplace.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              try {
                await _db.collection('marketplace_global').doc(docId).delete();
                _snack('Item dipadam');
              } catch (e) {
                _snack('Gagal: $e', err: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('PADAM'),
          ),
        ],
      ),
    );
  }

  void _showBuyDialog(Map<String, dynamic> item) {
    final price = (item['price'] is num)
        ? (item['price'] as num).toDouble()
        : 0.0;
    final maxQty = (item['quantity'] is num)
        ? (item['quantity'] as num).toInt()
        : 0;
    int buyQty = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final total = price * buyQty;
          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'BELI ITEM',
                  style: TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pesanan akan dihantar kepada admin untuk diproses',
                  style: TextStyle(color: AppColors.textDim, fontSize: 10),
                ),
                const SizedBox(height: 16),

                // Item info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['itemName'] ?? '-').toString().toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Penjual: ${(item['shopName'] ?? '-').toString().toUpperCase()}',
                        style: const TextStyle(
                          color: AppColors.textSub,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'RM ${price.toStringAsFixed(2)} / unit',
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Quantity picker
                const Text(
                  'Kuantiti',
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (buyQty > 1) setS(() => buyQty--);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Center(
                          child: FaIcon(
                            FontAwesomeIcons.minus,
                            size: 10,
                            color: AppColors.textSub,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$buyQty',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        if (buyQty < maxQty) setS(() => buyQty++);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Center(
                          child: FaIcon(
                            FontAwesomeIcons.plus,
                            size: 10,
                            color: AppColors.textSub,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Stok: $maxQty',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Total
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'JUMLAH',
                        style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'RM ${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        // Get buyer shop name
                        String buyerShopName = widget.shopID;
                        try {
                          final shopDoc = await _db
                              .collection('shops_${widget.ownerID}')
                              .doc(widget.shopID)
                              .get();
                          if (shopDoc.exists)
                            buyerShopName =
                                shopDoc.data()?['namaKedai'] ??
                                shopDoc.data()?['shopName'] ??
                                widget.shopID;
                        } catch (_) {}

                        await _db.collection('marketplace_orders').add({
                          'itemDocId': item['_docId'],
                          'itemName': item['itemName'],
                          'category': item['category'] ?? 'Lain-lain',
                          'pricePerUnit': price,
                          'quantity': buyQty,
                          'totalPrice': total,
                          'commission': total * 0.02,
                          'sellerPayout': total * 0.98,
                          // Seller info
                          'sellerOwnerID': item['ownerID'],
                          'sellerShopID': item['shopID'],
                          'sellerShopName': item['shopName'] ?? '',
                          // Buyer info
                          'buyerOwnerID': widget.ownerID,
                          'buyerShopID': widget.shopID,
                          'buyerShopName': buyerShopName,
                          // Status
                          'status':
                              'pending', // pending → approved → completed / rejected
                          'createdAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Pesanan dihantar kepada admin untuk kelulusan');
                      } catch (e) {
                        _snack('Gagal: $e', err: true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'HANTAR PESANAN',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _mpField(
    String label,
    TextEditingController ctrl,
    String hint, {
    bool caps = false,
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSub,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          textCapitalization: caps
              ? TextCapitalization.characters
              : TextCapitalization.none,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 11),
            filled: true,
            fillColor: AppColors.bgDeep,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
