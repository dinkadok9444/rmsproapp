import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import 'widgets/product_grid_card.dart';
import 'product_detail_screen.dart';

class MarketplaceBrowseScreen extends StatefulWidget {
  final String ownerID;
  final String shopID;

  const MarketplaceBrowseScreen({
    super.key,
    required this.ownerID,
    required this.shopID,
  });

  @override
  State<MarketplaceBrowseScreen> createState() =>
      _MarketplaceBrowseScreenState();
}

class _MarketplaceBrowseScreenState extends State<MarketplaceBrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Semua';

  static const List<String> _categories = [
    'Semua',
    'LCD',
    'Bateri',
    'Casing',
    'Spare Part',
    'Aksesori',
    'Lain-lain',
  ];

  static const _purple = Color(0xFF8B5CF6);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _buildStream() {
    Query query = FirebaseFirestore.instance.collection('marketplace_global');

    if (_selectedCategory != 'Semua') {
      query = query.where('category', isEqualTo: _selectedCategory);
    }

    return query.orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final itemName = (data['itemName'] ?? '').toString().toLowerCase();
    final shopName = (data['shopName'] ?? '').toString().toLowerCase();
    final description = (data['description'] ?? '').toString().toLowerCase();
    return itemName.contains(q) ||
        shopName.contains(q) ||
        description.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Cari item atau kedai...',
                hintStyle: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: FaIcon(
                    FontAwesomeIcons.magnifyingGlass,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: FaIcon(
                            FontAwesomeIcons.xmark,
                            size: 14,
                            color: AppColors.textDim,
                          ),
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Category chips
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = cat;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _purple
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _purple
                          : AppColors.border,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _purple.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSub,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 10),

        // Product grid
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: _purple,
                    strokeWidth: 2.5,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.triangleExclamation,
                        size: 28,
                        color: AppColors.red.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ralat memuatkan data',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];
              final filteredDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _matchesSearch(data);
              }).toList();

              if (filteredDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.boxOpen,
                        size: 32,
                        color: AppColors.textDim.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tiada item dalam marketplace',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Cuba tukar kategori atau kata carian',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isOwn = data['shopID'] == widget.shopID;

                  return ProductGridCard(
                    item: data,
                    isOwn: isOwn,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(
                            item: {...data, '_docId': doc.id},
                            buyerOwnerID: widget.ownerID,
                            buyerShopID: widget.shopID,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
