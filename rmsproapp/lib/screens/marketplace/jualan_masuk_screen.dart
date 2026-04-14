import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/marketplace_service.dart';
import '../../services/courier_service.dart';
import 'package:url_launcher/url_launcher.dart';

class JualanMasukScreen extends StatefulWidget {
  final String ownerID;
  final String shopID;

  const JualanMasukScreen({
    super.key,
    required this.ownerID,
    required this.shopID,
  });

  @override
  State<JualanMasukScreen> createState() => _JualanMasukScreenState();
}

class _JualanMasukScreenState extends State<JualanMasukScreen> {
  static const _purple = Color(0xFF8B5CF6);
  static const _green = Color(0xFF16A34A);

  final _service = MarketplaceService();

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_payment':
        return Colors.amber.shade700;
      case 'paid':
        return const Color(0xFF3B82F6);
      case 'shipped':
        return _purple;
      case 'completed':
        return _green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending_payment':
        return 'BELUM BAYAR';
      case 'paid':
        return 'DIBAYAR';
      case 'shipped':
        return 'DIHANTAR';
      case 'completed':
        return 'SELESAI';
      case 'cancelled':
        return 'DIBATALKAN';
      default:
        return status.toUpperCase();
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '-';
    if (timestamp is Timestamp) {
      return DateFormat('dd/MM/yyyy, hh:mm a').format(timestamp.toDate());
    }
    return '-';
  }

  String _formatRM(dynamic value) {
    final amount = (value is num) ? value.toDouble() : 0.0;
    return 'RM ${amount.toStringAsFixed(2)}';
  }

  // ─────────────────────────────────────────
  // Ship Order — Confirm & Auto Generate AWB
  // ─────────────────────────────────────────

  void _showShipDialog(String orderId, Map<String, dynamic> orderData) {
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setS) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  FaIcon(FontAwesomeIcons.truckFast, size: 18, color: _purple),
                  SizedBox(width: 10),
                  Text('Uruskan Penghantaran', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: const Column(
                      children: [
                        FaIcon(FontAwesomeIcons.triangleExclamation, size: 24, color: Colors.orange),
                        SizedBox(height: 10),
                        Text(
                          'Adakah anda pasti?',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Sistem akan terus menjana Airway Bill melalui kurier. Tindakan ini TIDAK BOLEH dibatalkan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(color: _purple),
                    const SizedBox(height: 8),
                    const Text('Menjana Airway Bill...', style: TextStyle(fontSize: 11, color: _purple, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
              actions: isLoading ? [] : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    setS(() => isLoading = true);

                    final courier = CourierService();
                    await courier.loadConfig();

                    if (!courier.isConfigured) {
                      setS(() => isLoading = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Kurier belum dikonfigurasi oleh admin.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }

                    // Load addresses
                    final sender = await courier.loadSenderAddress(widget.ownerID, widget.shopID);
                    final receiver = await courier.getReceiverAddress(orderData);

                    // Validate
                    final senderErr = courier.validateAddress(sender, 'Alamat Pickup');
                    final receiverErr = courier.validateAddress(receiver, 'Alamat Penerima');
                    if (senderErr != null || receiverErr != null) {
                      setS(() => isLoading = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(senderErr ?? receiverErr!),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }

                    // Create shipment & generate AWB
                    final result = await courier.createShipment(
                      sender: sender,
                      receiver: receiver,
                      itemDescription: (orderData['itemName'] ?? orderData['name'] ?? 'Spare Part').toString(),
                      itemValue: (orderData['productPrice'] is num) ? (orderData['productPrice'] as num).toDouble() : 0,
                      weight: 0.5,
                    );

                    if (result != null && (result['trackingNumber'] ?? '').isNotEmpty) {
                      // Save tracking + delyva orderId for AWB
                      await _service.markOrderShipped(orderId, result['trackingNumber']!, result['courierName']!);
                      // Save delyva orderId for print AWB later
                      await FirebaseFirestore.instance.collection('marketplace_orders').doc(orderId).update({
                        'delyvaOrderId': result['orderId'] ?? '',
                      });
                      setS(() => isLoading = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Airway Bill dijana! Tracking: ${result['trackingNumber']}'),
                            backgroundColor: _green,
                          ),
                        );
                      }
                    } else {
                      setS(() => isLoading = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Gagal menjana AWB. Sila semak tetapan API Kurier dan alamat.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 12),
                  label: const Text('YA, HANTAR SEKARANG'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────
  // Cancel Order (before shipped)
  // ─────────────────────────────────────────

  void _showCancelDialog(String orderId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            FaIcon(FontAwesomeIcons.circleXmark, size: 16, color: AppColors.red),
            SizedBox(width: 8),
            Text('Batalkan Pesanan?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.red)),
          ],
        ),
        content: const Text(
          'Pesanan ini akan dibatalkan. Tindakan ini tidak boleh diundur.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tidak'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.cancelOrder(orderId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pesanan dibatalkan'), backgroundColor: AppColors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // Stats Row
  // ─────────────────────────────────────────

  Widget _buildStatsRow(List<QueryDocumentSnapshot> docs) {
    double totalPayout = 0;
    int completedCount = 0;

    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['status'] == 'completed') {
        completedCount++;
        final payout =
            (d['sellerPayout'] is num) ? (d['sellerPayout'] as num).toDouble() : 0.0;
        totalPayout += payout;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              icon: FontAwesomeIcons.moneyBillWave,
              label: 'JUMLAH TERIMA',
              value: 'RM ${totalPayout.toStringAsFixed(2)}',
              color: _green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: FontAwesomeIcons.circleCheck,
              label: 'JUALAN SELESAI',
              value: '$completedCount',
              color: _purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // Order Card
  // ─────────────────────────────────────────

  Widget _buildOrderCard(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['status'] ?? '';
    final itemName = d['itemName'] ?? '-';
    final buyerShopName = d['buyerShopName'] ?? d['shopName'] ?? '-';
    final qty = d['quantity'] ?? 1;
    final price = (d['price'] is num) ? (d['price'] as num).toDouble() : 0.0;
    final totalPrice =
        (d['totalPrice'] is num) ? (d['totalPrice'] as num).toDouble() : 0.0;
    final sellerPayout =
        (d['sellerPayout'] is num) ? (d['sellerPayout'] as num).toDouble() : 0.0;
    final trackingNumber = d['trackingNumber'] ?? '';
    final courierName = d['courierName'] ?? '';
    final createdAt = d['createdAt'];

    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badge + date
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Item name
            Text(
              itemName.toString().toUpperCase(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            // Buyer
            Text(
              'Pembeli: ${buyerShopName.toString().toUpperCase()}',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 8),

            // Price info
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$qty × ${_formatRM(price)} = ${_formatRM(totalPrice)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Text(
                  'Terima: ${_formatRM(sellerPayout)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _green,
                  ),
                ),
              ],
            ),

            // Tracking info for shipped orders
            if (status == 'shipped' && trackingNumber.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _purple.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.truckFast,
                        size: 14, color: _purple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            courierName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _purple,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trackingNumber,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Print AWB button
              if ((d['delyvaOrderId'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final courier = CourierService();
                      await courier.loadConfig();
                      final url = courier.getAirwayBillUrl((d['delyvaOrderId'] ?? '').toString());
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.print, size: 12, color: _purple),
                    label: const Text('CETAK AIRWAY BILL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],

            // Ship + Cancel buttons for paid orders
            if (status == 'paid') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showShipDialog(doc.id, d),
                      icon: const FaIcon(FontAwesomeIcons.truckFast, size: 12, color: Colors.white),
                      label: const Text('HANTAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showCancelDialog(doc.id),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 12, color: AppColors.red),
                    label: const Text('BATAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              FontAwesomeIcons.boxOpen,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Tiada jualan masuk',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _service.streamSellerOrders(widget.ownerID),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Ralat: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Column(
            children: [
              _buildStatsRow([]),
              Expanded(child: _buildEmptyState()),
            ],
          );
        }

        return Column(
          children: [
            _buildStatsRow(docs),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                itemCount: docs.length,
                itemBuilder: (context, index) =>
                    _buildOrderCard(docs[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}
