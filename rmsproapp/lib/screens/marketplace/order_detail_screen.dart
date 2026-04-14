import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/marketplace_service.dart';
import 'widgets/order_status_stepper.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final String viewerOwnerID;

  const OrderDetailScreen({
    super.key,
    required this.order,
    required this.viewerOwnerID,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  static const _purple = Color(0xFF8B5CF6);

  final _service = MarketplaceService();
  bool _loading = false;

  String get _docId => widget.order['_docId'] ?? '';
  String get _status => widget.order['status'] ?? '';
  bool get _isBuyer => widget.viewerOwnerID == widget.order['buyerOwnerID'];

  // ─── helpers ───────────────────────────────────────────────────

  String _truncateId(String id) {
    if (id.length <= 10) return id;
    return '${id.substring(0, 5)}...${id.substring(id.length - 5)}';
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    } else {
      return '-';
    }
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return 'RM 0.00';
    final num amount = value is num ? value : num.tryParse(value.toString()) ?? 0;
    return 'RM ${amount.toStringAsFixed(2)}';
  }

  // ─── actions ───────────────────────────────────────────────────

  Future<void> _confirmReceived() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sahkan Terima Barang'),
        content: const Text(
          'Adakah anda pasti telah menerima barang ini? '
          'Tindakan ini tidak boleh dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Terima'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await _service.markOrderCompleted(_docId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesanan telah disahkan selesai.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Batal Pesanan'),
        content: const Text(
          'Adakah anda pasti ingin membatalkan pesanan ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batal'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await _service.cancelOrder(_docId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesanan telah dibatalkan.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Butiran Pesanan'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Status Stepper ──
                OrderStatusStepper(
                  currentStatus: _status,
                  timestamps: {
                    'createdAt': widget.order['createdAt'],
                    'paidAt': widget.order['paidAt'],
                    'shippedAt': widget.order['shippedAt'],
                    'completedAt': widget.order['completedAt'],
                    'trackingNumber': widget.order['trackingNumber'] ?? '',
                    'courierName': widget.order['courierName'] ?? '',
                  },
                ),
                const SizedBox(height: 20),

                // ── Order Info ──
                _buildSectionCard(
                  icon: FontAwesomeIcons.fileLines,
                  title: 'Maklumat Pesanan',
                  children: [
                    _infoRow('ID Pesanan', _truncateId(_docId)),
                    _infoRow('Tarikh Dibuat', _formatTimestamp(order['createdAt'])),
                    if (order['paidAt'] != null)
                      _infoRow('Tarikh Dibayar', _formatTimestamp(order['paidAt'])),
                    if (order['shippedAt'] != null)
                      _infoRow('Tarikh Dihantar', _formatTimestamp(order['shippedAt'])),
                    if (order['completedAt'] != null)
                      _infoRow('Tarikh Selesai', _formatTimestamp(order['completedAt'])),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Item Card ──
                _buildSectionCard(
                  icon: FontAwesomeIcons.boxOpen,
                  title: 'Item Pesanan',
                  children: [
                    _infoRow('Nama Item', order['itemName'] ?? '-'),
                    _infoRow('Kategori', order['category'] ?? '-'),
                    _infoRow(
                      'Kuantiti × Harga',
                      '${order['quantity'] ?? 0} × ${_formatCurrency(order['pricePerUnit'])}',
                    ),
                    const Divider(height: 20),
                    _infoRow(
                      'Jumlah',
                      _formatCurrency(order['totalPrice']),
                      valueBold: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Payment Info ──
                _buildSectionCard(
                  icon: FontAwesomeIcons.moneyBill,
                  title: 'Maklumat Bayaran',
                  children: [
                    _infoRow('Jumlah Bayaran', _formatCurrency(order['totalPrice'])),
                    _infoRow('Komisyen (2%)', _formatCurrency(order['commission'])),
                    const Divider(height: 20),
                    _infoRow(
                      'Penjual Terima',
                      _formatCurrency(order['sellerPayout']),
                      valueBold: true,
                      valueColor: _purple,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Seller / Buyer Info ──
                _buildSectionCard(
                  icon: FontAwesomeIcons.userGroup,
                  title: 'Pihak Terlibat',
                  children: [
                    _infoRow('Penjual', order['sellerShopName'] ?? '-'),
                    _infoRow('Pembeli', order['buyerShopName'] ?? '-'),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Tracking Info ──
                if ((order['trackingNumber'] ?? '').toString().isNotEmpty) ...[
                  _buildTrackingCard(order),
                  const SizedBox(height: 14),
                ],

                // spacing for bottom button
                const SizedBox(height: 80),
              ],
            ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  // ─── section card builder ──────────────────────────────────────

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: _purple),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool valueBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── tracking card ─────────────────────────────────────────────

  Widget _buildTrackingCard(Map<String, dynamic> order) {
    final courier = order['courierName'] ?? '-';
    final tracking = order['trackingNumber'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.blueLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(FontAwesomeIcons.truck, size: 14, color: AppColors.blue),
              const SizedBox(width: 8),
              const Text(
                'Maklumat Penghantaran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _trackingRow('Kurier', courier),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                flex: 4,
                child: Text(
                  'No. Penjejakan',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
              Expanded(
                flex: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        tracking,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: tracking));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No. penjejakan disalin.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const FaIcon(
                        FontAwesomeIcons.copy,
                        size: 13,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trackingRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // ─── bottom action ─────────────────────────────────────────────

  Widget? _buildBottomAction() {
    // Buyer can confirm receipt when paid or shipped
    if ((_status == 'paid' || _status == 'shipped') && _isBuyer) {
      return _bottomBar(
        label: 'TERIMA BARANG',
        icon: FontAwesomeIcons.circleCheck,
        color: _purple,
        onTap: _confirmReceived,
      );
    }

    // Pending payment: allow cancel
    if (_status == 'pending_payment') {
      return _bottomBar(
        label: 'BATAL PESANAN',
        icon: FontAwesomeIcons.ban,
        color: AppColors.red,
        onTap: _cancelOrder,
      );
    }

    return null;
  }

  Widget _bottomBar({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : onTap,
            icon: FaIcon(icon, size: 16),
            label: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }
}
