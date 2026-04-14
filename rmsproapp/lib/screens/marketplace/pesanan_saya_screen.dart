import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/marketplace_service.dart';
import 'order_detail_screen.dart';

class PesananSayaScreen extends StatefulWidget {
  final String ownerID, shopID;
  const PesananSayaScreen({super.key, required this.ownerID, required this.shopID});

  @override
  State<PesananSayaScreen> createState() => _PesananSayaScreenState();
}

class _PesananSayaScreenState extends State<PesananSayaScreen> {
  static const _purple = Color(0xFF8B5CF6);
  final _service = MarketplaceService();
  String _selectedFilter = 'all';

  static const _filters = <String, String>{
    'all': 'Semua',
    'pending_payment': 'Belum Bayar',
    'paid': 'Dibayar',
    'shipped': 'Dihantar',
    'completed': 'Selesai',
    'cancelled': 'Dibatalkan',
  };

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_payment':
        return Colors.amber.shade700;
      case 'paid':
        return AppColors.blue;
      case 'shipped':
        return _purple;
      case 'completed':
        return AppColors.green;
      case 'cancelled':
        return AppColors.red;
      default:
        return AppColors.textDim;
    }
  }

  String _statusLabel(String status) {
    return _filters[status] ?? status.toUpperCase();
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '-';
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter Chips ──
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final key = _filters.keys.elementAt(index);
              final label = _filters.values.elementAt(index);
              final isActive = _selectedFilter == key;
              return FilterChip(
                selected: isActive,
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : AppColors.textSub,
                  ),
                ),
                backgroundColor: AppColors.bgDeep,
                selectedColor: _purple,
                side: BorderSide(
                  color: isActive ? _purple : AppColors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                showCheckmark: false,
                onSelected: (_) => setState(() => _selectedFilter = key),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // ── Orders List ──
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _service.streamBuyerOrders(widget.ownerID),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _purple),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Ralat: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];

              // Apply filter
              final docs = _selectedFilter == 'all'
                  ? allDocs
                  : allDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return data['status'] == _selectedFilter;
                    }).toList();

              if (docs.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildOrderCard(doc.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.boxOpen,
            size: 48,
            color: AppColors.textDim.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tiada pesanan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pesanan anda akan dipaparkan di sini',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Order Card ──
  Widget _buildOrderCard(String docId, Map<String, dynamic> data) {
    final status = (data['status'] ?? '') as String;
    final itemName = (data['itemName'] ?? '-') as String;
    final sellerShopName = (data['sellerShopName'] ?? '-') as String;
    final qty = (data['quantity'] is num) ? (data['quantity'] as num).toInt() : 1;
    final price = (data['unitPrice'] is num) ? (data['unitPrice'] as num).toDouble() : 0.0;
    final total = (data['totalPrice'] is num) ? (data['totalPrice'] as num).toDouble() : 0.0;
    final trackingNumber = (data['trackingNumber'] ?? '') as String;
    final createdAt = data['createdAt'];

    final statusCol = _statusColor(status);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              order: {...data, '_docId': docId},
              viewerOwnerID: widget.ownerID,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Row: Status badge + date ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusCol.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusCol,
                    ),
                  ),
                ),
                Text(
                  _formatDate(createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Item Name ──
            Text(
              itemName.toUpperCase(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // ── Seller shop name ──
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.shop,
                  size: 11,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sellerShopName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Qty × Price = Total ──
            Row(
              children: [
                Text(
                  '$qty x RM ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSub,
                  ),
                ),
                const Spacer(),
                Text(
                  'RM ${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _purple,
                  ),
                ),
              ],
            ),

            // ── Tracking Number (if shipped) ──
            if (status == 'shipped' && trackingNumber.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _purple.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.truck,
                      size: 12,
                      color: _purple,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        trackingNumber,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _purple,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Terima Barang Button (paid or shipped) ──
            if (status == 'paid' || status == 'shipped') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmReceived(docId, data),
                  icon: const FaIcon(
                    FontAwesomeIcons.circleCheck,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'TERIMA BARANG',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Confirm Received Dialog ──
  Future<void> _confirmReceived(String docId, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sahkan Penerimaan',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'Adakah anda pasti telah menerima barang ini? Tindakan ini tidak boleh dibatalkan.',
          style: TextStyle(fontSize: 13, color: AppColors.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Batal',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Ya, Terima',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _service.markOrderCompleted(docId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Pesanan ditandakan sebagai selesai!'),
              backgroundColor: AppColors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ralat: $e'),
              backgroundColor: AppColors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    }
  }
}
