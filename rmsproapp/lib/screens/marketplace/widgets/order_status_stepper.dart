import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';

const _purple = Color(0xFF8B5CF6);

class OrderStatusStepper extends StatelessWidget {
  final String currentStatus;
  final Map<String, dynamic>? timestamps;

  const OrderStatusStepper({
    super.key,
    required this.currentStatus,
    this.timestamps,
  });

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    if (ts is Timestamp) return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
    if (ts is int && ts > 0) return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts));
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = currentStatus == 'cancelled';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(child: FaIcon(FontAwesomeIcons.circleXmark, size: 16, color: AppColors.red)),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PESANAN DIBATALKAN', style: TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w900)),
                SizedBox(height: 2),
                Text('Pesanan ini telah dibatalkan', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ],
        ),
      );
    }

    final steps = [
      _TimelineStep(
        label: 'Pesanan Dibuat',
        subtitle: 'Menunggu pembayaran',
        status: 'pending_payment',
        icon: FontAwesomeIcons.cartShopping,
        time: _fmtTs(timestamps?['createdAt']),
      ),
      _TimelineStep(
        label: 'Pembayaran Berjaya',
        subtitle: 'Penjual sedang menyediakan pesanan',
        status: 'paid',
        icon: FontAwesomeIcons.creditCard,
        time: _fmtTs(timestamps?['paidAt']),
      ),
      _TimelineStep(
        label: 'Pesanan Dihantar',
        subtitle: _buildTrackingSubtitle(),
        status: 'shipped',
        icon: FontAwesomeIcons.truck,
        time: _fmtTs(timestamps?['shippedAt']),
      ),
      _TimelineStep(
        label: 'Pesanan Selesai',
        subtitle: 'Barang telah diterima',
        status: 'completed',
        icon: FontAwesomeIcons.circleCheck,
        time: _fmtTs(timestamps?['completedAt']),
      ),
    ];

    final currentIndex = steps.indexWhere((s) => s.status == currentStatus);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              FaIcon(FontAwesomeIcons.timeline, size: 12, color: _purple),
              SizedBox(width: 8),
              Text('STATUS PESANAN', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (i) {
            final step = steps[i];
            final isActive = i <= currentIndex;
            final isCurrent = i == currentIndex;
            final isLast = i == steps.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline line + dot
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      // Dot
                      Container(
                        width: isCurrent ? 28 : 22,
                        height: isCurrent ? 28 : 22,
                        decoration: BoxDecoration(
                          color: isActive ? _purple : AppColors.bgDeep,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isActive ? _purple : AppColors.border,
                            width: isCurrent ? 2 : 1,
                          ),
                          boxShadow: isCurrent ? [
                            BoxShadow(color: _purple.withValues(alpha: 0.3), blurRadius: 8),
                          ] : null,
                        ),
                        child: Center(
                          child: FaIcon(
                            step.icon,
                            size: isCurrent ? 11 : 9,
                            color: isActive ? Colors.white : AppColors.textDim,
                          ),
                        ),
                      ),
                      // Line
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 40,
                          color: i < currentIndex ? _purple : AppColors.border,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: isCurrent ? 2 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.label,
                          style: TextStyle(
                            color: isActive ? AppColors.textPrimary : AppColors.textDim,
                            fontSize: isCurrent ? 13 : 11,
                            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        if (isActive && step.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            step.subtitle,
                            style: TextStyle(
                              color: isCurrent ? _purple : AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                        if (step.time.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              FaIcon(FontAwesomeIcons.clock, size: 8,
                                color: isActive ? AppColors.textMuted : AppColors.textDim),
                              const SizedBox(width: 4),
                              Text(
                                step.time,
                                style: TextStyle(
                                  color: isActive ? AppColors.textMuted : AppColors.textDim,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _buildTrackingSubtitle() {
    if (timestamps == null) return 'Sedang dalam penghantaran';
    final tracking = (timestamps!['trackingNumber'] ?? '').toString();
    final courier = (timestamps!['courierName'] ?? '').toString();
    if (tracking.isNotEmpty) {
      return '${courier.isNotEmpty ? "$courier: " : ""}$tracking';
    }
    return 'Sedang dalam penghantaran';
  }
}

class _TimelineStep {
  final String label;
  final String subtitle;
  final String status;
  final IconData icon;
  final String time;

  const _TimelineStep({
    required this.label,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.time,
  });
}
