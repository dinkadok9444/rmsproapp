import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import 'checkout_screen.dart';

const _purple = Color(0xFF8B5CF6);
const _priceRed = Color(0xFFEF4444);

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String buyerOwnerID;
  final String buyerShopID;

  const ProductDetailScreen({
    super.key,
    required this.item,
    required this.buyerOwnerID,
    required this.buyerShopID,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;

  String get _docId => (widget.item['_docId'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    debugPrint('=== PRODUCT DETAIL === docId: $_docId');
    debugPrint('=== ITEM DATA === ${widget.item}');
    if (_docId.isEmpty) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _purple, foregroundColor: Colors.white),
        body: const Center(child: Text('Produk tidak dijumpai')),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('marketplace_global')
          .doc(_docId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              title: const Text('Produk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ),
            body: const Center(child: CircularProgressIndicator(color: _purple)),
          );
        }

        final item = snapshot.data!.data() as Map<String, dynamic>;
        item['_docId'] = snapshot.data!.id;
        debugPrint('=== LIVE DATA === description: ${item['description']}');

        final itemName = (item['itemName'] ?? 'Produk').toString();
        final description = (item['description'] ?? '').toString();
        final price = (item['price'] is num) ? (item['price'] as num).toDouble() : 0.0;
        final stock = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 0;
        final category = (item['category'] ?? '').toString();
        final imageUrl = (item['imageUrl'] ?? '').toString();
        final soldCount = (item['soldCount'] is num) ? (item['soldCount'] as num).toInt() : 0;
        final isOwnProduct = (item['ownerID'] ?? '') == widget.buyerOwnerID;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: _purple,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 16),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              itemName.toUpperCase(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                Container(
                  width: double.infinity,
                  height: 250,
                  color: AppColors.bgDeep,
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, height: 250,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),

                // Price
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RM ${price.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _priceRed),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (category.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _purple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(category, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _purple)),
                            ),
                          if (category.isNotEmpty) const SizedBox(width: 10),
                          const FaIcon(FontAwesomeIcons.boxOpen, size: 11, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text('Stok: $stock', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          if (soldCount > 0) ...[
                            const SizedBox(width: 10),
                            const FaIcon(FontAwesomeIcons.fireFlameSimple, size: 11, color: AppColors.orange),
                            const SizedBox(width: 4),
                            Text('$soldCount terjual', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Product Info + Description
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName.toUpperCase(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(description, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSub)),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 80),
              ],
            ),
          ),

          // Bottom Bar
          bottomNavigationBar: Container(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: AppColors.border)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
              ],
            ),
            child: isOwnProduct
                ? Container(
                    height: 48,
                    decoration: BoxDecoration(color: AppColors.bgDeep, borderRadius: BorderRadius.circular(12)),
                    child: const Center(
                      child: Text('Ini produk anda', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                    ),
                  )
                : stock <= 0
                    ? Container(
                        height: 48,
                        decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
                        child: const Center(
                          child: Text('Stok habis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.red)),
                        ),
                      )
                    : SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: _quantity > 1 ? () => setState(() => _quantity--) : null,
                                    child: SizedBox(
                                      width: 40, height: 46,
                                      child: Center(child: FaIcon(FontAwesomeIcons.minus, size: 11,
                                        color: _quantity > 1 ? AppColors.textPrimary : AppColors.textDim)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: Center(
                                      child: Text('$_quantity', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _quantity < stock ? () => setState(() => _quantity++) : null,
                                    child: SizedBox(
                                      width: 40, height: 46,
                                      child: Center(child: FaIcon(FontAwesomeIcons.plus, size: 11,
                                        color: _quantity < stock ? AppColors.textPrimary : AppColors.textDim)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => CheckoutScreen(
                                      item: item,
                                      quantity: _quantity,
                                      buyerOwnerID: widget.buyerOwnerID,
                                      buyerShopID: widget.buyerShopID,
                                    ),
                                  ));
                                },
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(12)),
                                  child: const Center(
                                    child: Text('BELI SEKARANG', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaIcon(FontAwesomeIcons.image, size: 40, color: AppColors.textDim.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          const Text('Tiada gambar', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}
