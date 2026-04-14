import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../theme/app_theme.dart';

class ProductGridCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isOwn;
  final VoidCallback onTap;

  const ProductGridCard({
    super.key,
    required this.item,
    required this.isOwn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = (item['price'] is num) ? (item['price'] as num).toDouble() : 0.0;
    final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 0;
    final sold = (item['soldCount'] is num) ? (item['soldCount'] as num).toInt() : 0;
    final imageUrl = item['imageUrl'] as String?;

    return GestureDetector(
      onTap: onTap,
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
              color: Colors.black.withValues(alpha: 0.04),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              child: Container(
                height: 85,
                width: double.infinity,
                color: AppColors.bgDeep,
                child: Stack(
                  children: [
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 85,
                        errorBuilder: (_, __, ___) => const Center(
                          child: FaIcon(FontAwesomeIcons.image, size: 24, color: AppColors.textDim),
                        ),
                      )
                    else
                      const Center(
                        child: FaIcon(FontAwesomeIcons.image, size: 24, color: AppColors.textDim),
                      ),
                    if (isOwn)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ANDA',
                            style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    if (qty <= 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'HABIS',
                            style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['itemName'] ?? '-').toString().toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((item['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        (item['description'] ?? '').toString(),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 8,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'RM ${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (sold > 0)
                      Text(
                        '$sold terjual',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 8,
                        ),
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
}
