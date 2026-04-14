import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class SenaraiAktifScreen extends StatefulWidget {
  const SenaraiAktifScreen({super.key});

  @override
  State<SenaraiAktifScreen> createState() => _SenaraiAktifScreenState();
}

class _SenaraiAktifScreenState extends State<SenaraiAktifScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _dealers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterNegeri = 'Semua';
  String _sortMode = 'newest';
  int _currentPage = 0;
  static const int _pageSize = 20;
  static const int _fetchBatch = 200;
  DocumentSnapshot? _lastCursor;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDealers() async {
    setState(() {
      _isLoading = true;
      _dealers = [];
      _lastCursor = null;
      _hasMore = true;
    });
    await _fetchMore();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('saas_dealers')
          .orderBy('createdAt', descending: true)
          .limit(_fetchBatch);
      if (_lastCursor != null) q = q.startAfterDocument(_lastCursor!);
      final snap = await q.get();
      if (snap.docs.isEmpty) {
        _hasMore = false;
      } else {
        _lastCursor = snap.docs.last;
        _dealers.addAll(snap.docs.map((d) => {'id': d.id, ...d.data()}));
        if (snap.docs.length < _fetchBatch) _hasMore = false;
      }
      _applyFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      _isLoadingMore = false;
      if (mounted) setState(() {});
    }
  }

  void _applyFilter() {
    _filtered = _dealers.where((d) {
      final nama = (d['namaKedai'] ?? '').toString().toLowerCase();
      final owner = (d['ownerName'] ?? '').toString().toLowerCase();
      final id = (d['id'] ?? '').toString().toLowerCase();
      final phone = (d['ownerContact'] ?? d['phone'] ?? '').toString().toLowerCase();
      final negeri = (d['negeri'] ?? '').toString();
      final matchSearch = _searchQuery.isEmpty ||
          nama.contains(_searchQuery) ||
          owner.contains(_searchQuery) ||
          id.contains(_searchQuery) ||
          phone.contains(_searchQuery);
      final matchNegeri = _filterNegeri == 'Semua' || negeri == _filterNegeri;
      return matchSearch && matchNegeri;
    }).toList();

    _applySorting();
    _currentPage = 0;
    setState(() {});
  }

  void _applySorting() {
    switch (_sortMode) {
      case 'newest':
        _filtered.sort((a, b) {
          final tA = _toMillis(a['createdAt']);
          final tB = _toMillis(b['createdAt']);
          return tB.compareTo(tA);
        });
        break;
      case 'alpha':
        _filtered.sort((a, b) {
          final nA = (a['namaKedai'] ?? '').toString().toLowerCase();
          final nB = (b['namaKedai'] ?? '').toString().toLowerCase();
          return nA.compareTo(nB);
        });
        break;
      case 'expiry':
        _filtered.sort((a, b) {
          final eA = _toMillis(a['expireDate']);
          final eB = _toMillis(b['expireDate']);
          return eA.compareTo(eB);
        });
        break;
    }
  }

  int _toMillis(dynamic ts) {
    if (ts == null) return 0;
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    if (ts is int) return ts;
    if (ts is double) return ts.toInt();
    return 0;
  }

  List<String> get _senaraiNegeri {
    final set = <String>{'Semua'};
    for (final d in _dealers) {
      final n = (d['negeri'] ?? '').toString();
      if (n.isNotEmpty) set.add(n);
    }
    return set.toList();
  }

  int get _totalPages => (_filtered.length / _pageSize).ceil().clamp(1, 99999);

  List<Map<String, dynamic>> get _pagedList {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _filtered.length);
    if (start >= _filtered.length) return [];
    return _filtered.sublist(start, end);
  }

  String _kiraBakiHari(dynamic expireTimestamp) {
    if (expireTimestamp == null) return '-';
    DateTime? expire;
    if (expireTimestamp is Timestamp) {
      expire = expireTimestamp.toDate();
    } else if (expireTimestamp is int) {
      expire = DateTime.fromMillisecondsSinceEpoch(expireTimestamp);
    } else if (expireTimestamp is double) {
      expire = DateTime.fromMillisecondsSinceEpoch(expireTimestamp.toInt());
    }
    if (expire == null) return '-';
    final beza = expire.difference(DateTime.now()).inDays;
    if (beza < 0) return 'Tamat Tempoh';
    if (beza == 0) return 'Luput Hari Ini';
    return '$beza Hari Lagi';
  }

  Color _warnaExpiry(dynamic expireTimestamp) {
    if (expireTimestamp == null) return AppColors.textDim;
    DateTime? expire;
    if (expireTimestamp is Timestamp) {
      expire = expireTimestamp.toDate();
    } else if (expireTimestamp is int) {
      expire = DateTime.fromMillisecondsSinceEpoch(expireTimestamp);
    } else if (expireTimestamp is double) {
      expire = DateTime.fromMillisecondsSinceEpoch(expireTimestamp.toInt());
    }
    if (expire == null) return AppColors.textDim;
    final beza = expire.difference(DateTime.now()).inDays;
    if (beza <= 7) return AppColors.red;
    return AppColors.green;
  }

  String _formatTarikh(dynamic ts) {
    if (ts == null) return '-';
    DateTime? d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else if (ts is int) {
      d = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is double) {
      d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    }
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy').format(d);
  }

  void _openDealerDetail(Map<String, dynamic> dealer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DealerDetailSheet(
        dealer: dealer,
        db: _db,
        onUpdated: _loadDealers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search & filter bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: AppColors.borderMed)),
          ),
          child: Column(
            children: [
              // Search field
              TextField(
                controller: _searchController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Cari nama kedai, pemilik, telefon atau ID...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _applyFilter();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (v) {
                  _searchQuery = v.toLowerCase();
                  _applyFilter();
                },
              ),
              const SizedBox(height: 10),
              // Filter row: negeri dropdown + sort + count
              Row(
                children: [
                  // Negeri dropdown
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        border: Border.all(color: AppColors.borderMed),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filterNegeri,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textMuted),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                          items: _senaraiNegeri.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                          onChanged: (v) {
                            _filterNegeri = v ?? 'Semua';
                            _applyFilter();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Sort dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      border: Border.all(color: AppColors.borderMed),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortMode,
                        dropdownColor: AppColors.card,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textMuted),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                        items: const [
                          DropdownMenuItem(value: 'newest', child: Text('Terbaru')),
                          DropdownMenuItem(value: 'alpha', child: Text('A-Z')),
                          DropdownMenuItem(value: 'expiry', child: Text('Luput')),
                        ],
                        onChanged: (v) {
                          _sortMode = v ?? 'newest';
                          _applyFilter();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_filtered.length}',
                      style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Dealer list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FontAwesomeIcons.store, size: 40, color: AppColors.textDim.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text('Tiada rekod dijumpai', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDealers,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _pagedList.length,
                        itemBuilder: (_, i) => _buildDealerCard(_pagedList[i]),
                      ),
                    ),
        ),
        // Pagination bar
        if (!_isLoading && _filtered.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.borderMed)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous button
                _paginationButton(
                  icon: FontAwesomeIcons.chevronLeft,
                  enabled: _currentPage > 0,
                  onTap: () {
                    setState(() => _currentPage--);
                  },
                ),
                // Page info
                Text(
                  'Halaman ${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                // Next button
                _paginationButton(
                  icon: FontAwesomeIcons.chevronRight,
                  enabled: _currentPage < _totalPages - 1,
                  onTap: () {
                    setState(() => _currentPage++);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _paginationButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled ? AppColors.primary.withValues(alpha: 0.1) : AppColors.bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border,
            ),
          ),
          child: FaIcon(
            icon,
            size: 12,
            color: enabled ? AppColors.primary : AppColors.textDim,
          ),
        ),
      ),
    );
  }

  Widget _buildDealerCard(Map<String, dynamic> d) {
    final nama = d['namaKedai'] ?? d['shopName'] ?? '-';
    final owner = d['ownerName'] ?? '-';
    final negeri = d['negeri'] ?? '-';
    final status = d['status'] ?? 'Aktif';
    final isGantung = status == 'Digantung' || status == 'Suspend';
    final isPending = status == 'Pending';
    final shopID = d['shopID'] ?? '-';

    final proActive = d['proMode'] == true;
    final galleryActive = d['addonGallery'] == true;
    final singleStaff = d['singleStaffMode'] == true;

    return GestureDetector(
      onTap: () => _openDealerDetail(d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isGantung
                ? AppColors.red.withValues(alpha: 0.3)
                : isPending
                    ? AppColors.yellow.withValues(alpha: 0.3)
                    : AppColors.borderMed,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        owner,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTarikh(d['expireDate']),
                      style: TextStyle(
                        color: _warnaExpiry(d['expireDate']),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _kiraBakiHari(d['expireDate']),
                      style: TextStyle(
                        color: _warnaExpiry(d['expireDate']),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isGantung
                        ? AppColors.red.withValues(alpha: 0.15)
                        : isPending
                            ? AppColors.yellow.withValues(alpha: 0.15)
                            : AppColors.green.withValues(alpha: 0.15),
                    border: Border.all(
                      color: isGantung
                          ? AppColors.red.withValues(alpha: 0.4)
                          : isPending
                              ? AppColors.yellow.withValues(alpha: 0.4)
                              : AppColors.green.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isGantung ? 'SUSPEND' : (isPending ? 'PENDING' : 'AKTIF'),
                    style: TextStyle(
                      color: isGantung ? AppColors.red : (isPending ? AppColors.yellow : AppColors.green),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.borderMed),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') {
                      _openDealerDetail(d);
                    } else if (v == 'suspend') {
                      _quickSuspend(d);
                    } else if (v == 'delete') {
                      _quickDelete(d);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: const [
                        FaIcon(FontAwesomeIcons.penToSquare, size: 12, color: AppColors.blue),
                        SizedBox(width: 10),
                        Text('Edit', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'suspend',
                      child: Row(children: [
                        FaIcon(
                          isGantung ? FontAwesomeIcons.circlePlay : FontAwesomeIcons.circlePause,
                          size: 12,
                          color: isGantung ? AppColors.green : AppColors.orange,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isGantung ? 'Aktifkan' : 'Gantung',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        FaIcon(FontAwesomeIcons.trash, size: 12, color: AppColors.red),
                        SizedBox(width: 10),
                        Text('Padam', style: TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Info row
            Row(
              children: [
                _infoChip(FontAwesomeIcons.idBadge, shopID, AppColors.orange),
                const SizedBox(width: 8),
                _infoChip(FontAwesomeIcons.locationDot, negeri, AppColors.blue),
              ],
            ),
            const SizedBox(height: 10),
            // Subscription badges
            Row(
              children: [
                _subscriptionBadge('PRO', proActive, const Color(0xFFA855F7), d['proModeExpire']),
                const SizedBox(width: 6),
                _subscriptionBadge('GALLERY', galleryActive, AppColors.yellow, d['galleryExpire']),
                const SizedBox(width: 6),
                _subscriptionBadge(
                  singleStaff ? 'SINGLE' : 'MULTI',
                  true,
                  AppColors.cyan,
                  null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickSuspend(Map<String, dynamic> d) async {
    final id = d['id'] ?? '';
    if (id.isEmpty) return;
    final currentStatus = (d['status'] ?? 'Aktif').toString();
    final isCurrentlySuspended = currentStatus == 'Digantung' || currentStatus == 'Suspend';
    final newStatus = isCurrentlySuspended ? 'Aktif' : 'Digantung';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderMed),
        ),
        title: Text(
          isCurrentlySuspended ? 'Aktifkan akaun?' : 'Gantung akaun?',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '${d['namaKedai'] ?? '-'}',
          style: const TextStyle(color: AppColors.textSub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlySuspended ? AppColors.green : AppColors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isCurrentlySuspended ? 'Aktifkan' : 'Gantung',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection('saas_dealers').doc(id).update({'status': newStatus});
      await _loadDealers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status: $newStatus'),
            backgroundColor: isCurrentlySuspended ? AppColors.green : AppColors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  Future<void> _quickDelete(Map<String, dynamic> d) async {
    final id = d['id'] ?? '';
    if (id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.red),
        ),
        title: const Text(
          'PADAM AKAUN?',
          style: TextStyle(color: AppColors.red, fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Padam "${d['namaKedai'] ?? ''}" secara kekal?',
          style: const TextStyle(color: AppColors.textSub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Padam', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection('saas_dealers').doc(id).delete();
      await _loadDealers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Akaun dipadam.'), backgroundColor: AppColors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _subscriptionBadge(String label, bool active, Color color, dynamic expire) {
    final bakiText = expire != null ? _kiraBakiHari(expire) : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
        border: Border.all(color: active ? color.withValues(alpha: 0.4) : AppColors.textDim.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            active ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleXmark,
            size: 10,
            color: active ? color : AppColors.textDim,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? color : AppColors.textDim,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (bakiText.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              bakiText,
              style: TextStyle(
                color: active ? color.withValues(alpha: 0.7) : AppColors.textDim,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Dealer Detail Bottom Sheet ─────────────────────────────────────────────

class _DealerDetailSheet extends StatefulWidget {
  final Map<String, dynamic> dealer;
  final FirebaseFirestore db;
  final VoidCallback onUpdated;

  const _DealerDetailSheet({
    required this.dealer,
    required this.db,
    required this.onUpdated,
  });

  @override
  State<_DealerDetailSheet> createState() => _DealerDetailSheetState();
}

class _DealerDetailSheetState extends State<_DealerDetailSheet> {
  late Map<String, dynamic> _d;
  bool _isSaving = false;
  bool _showPassword = false;
  bool _editAsas = false;
  late TextEditingController _ownerCtrl;
  late TextEditingController _ssmCtrl;
  late TextEditingController _alamatCtrl;
  late TextEditingController _daerahCtrl;
  late TextEditingController _negeriCtrl;
  late TextEditingController _telCtrl;
  late TextEditingController _emelCtrl;
  late TextEditingController _passCtrl;

  @override
  void initState() {
    super.initState();
    _d = Map.from(widget.dealer);
    _initAsasControllers();
    _loadShopExtras();
  }

  Future<void> _loadShopExtras() async {
    try {
      if (_dealerID.isEmpty || _shopID.isEmpty) return;
      final snap = await widget.db.collection('shops_$_dealerID').doc(_shopID).get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (!mounted) return;
      setState(() {
        _d['svTel'] = data['svTel'] ?? _d['svTel'];
        _d['svPass'] = data['svPass'] ?? _d['svPass'];
      });
    } catch (_) {}
  }

  void _initAsasControllers() {
    _ownerCtrl = TextEditingController(text: (_d['ownerName'] ?? '').toString());
    _ssmCtrl = TextEditingController(text: (_d['ssm'] ?? '').toString());
    _alamatCtrl = TextEditingController(text: (_d['alamat'] ?? _d['address'] ?? '').toString());
    _daerahCtrl = TextEditingController(text: (_d['daerah'] ?? '').toString());
    _negeriCtrl = TextEditingController(text: (_d['negeri'] ?? '').toString());
    _telCtrl = TextEditingController(text: (_d['ownerContact'] ?? _d['phone'] ?? '').toString());
    _emelCtrl = TextEditingController(text: (_d['emel'] ?? _d['email'] ?? '').toString());
    _passCtrl = TextEditingController(text: (_d['password'] ?? '').toString());
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _ssmCtrl.dispose();
    _alamatCtrl.dispose();
    _daerahCtrl.dispose();
    _negeriCtrl.dispose();
    _telCtrl.dispose();
    _emelCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _simpanMaklumatAsas() async {
    setState(() => _isSaving = true);
    try {
      final update = {
        'ownerName': _ownerCtrl.text.trim(),
        'ssm': _ssmCtrl.text.trim(),
        'alamat': _alamatCtrl.text.trim(),
        'daerah': _daerahCtrl.text.trim(),
        'negeri': _negeriCtrl.text.trim(),
        'ownerContact': _telCtrl.text.trim(),
        'emel': _emelCtrl.text.trim(),
        'username': _dealerID,
        'password': _passCtrl.text.trim(),
      };
      await widget.db.collection('saas_dealers').doc(_dealerID).update(update);
      try {
        await widget.db.collection('shops_$_dealerID').doc(_shopID).update(update);
      } catch (_) {}
      setState(() {
        _d.addAll(update);
        _editAsas = false;
      });
      widget.onUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maklumat berjaya dikemaskini'), backgroundColor: AppColors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String get _dealerID => _d['id'] ?? '';
  String get _shopID {
    final s = (_d['shopID'] ?? '').toString();
    return (s.isEmpty || s == '-') ? 'MAIN' : s;
  }

  Color _warnaStatus(dynamic ts, bool active) {
    if (!active || ts == null || ts == 0) return AppColors.textDim;
    DateTime? expire;
    if (ts is Timestamp) {
      expire = ts.toDate();
    } else if (ts is int) {
      expire = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is double) {
      expire = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    }
    if (expire == null) return AppColors.textDim;
    final beza = expire.difference(DateTime.now()).inDays;
    if (beza <= 7) return AppColors.red;
    return AppColors.green;
  }

  String _formatTarikh(dynamic ts) {
    if (ts == null || ts == 0) return '-';
    DateTime? d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else if (ts is int) {
      d = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is double) {
      d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    }
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy').format(d);
  }

  Future<void> _kemaskiniLangganan(String jenis, int hari) async {
    if (hari == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.borderMed),
          ),
          title: Text(
            'Tutup ${jenis.toUpperCase()}?',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Pasti mahu MENUTUP akses ${jenis.toUpperCase()} untuk kedai ini?',
            style: const TextStyle(color: AppColors.textSub, fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tutup', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);

    Map<String, dynamic> updateSaaS;
    Map<String, dynamic> updateShop;

    if (hari == 0) {
      if (jenis == 'pro') {
        updateSaaS = {'proMode': false, 'proModeExpire': 0};
        updateShop = {'proMode': false, 'proModeExpire': 0};
      } else {
        updateSaaS = {'addonGallery': false, 'galleryExpire': 0};
        updateShop = {'addonGallery': false, 'galleryExpire': 0};
      }
    } else {
      final expireTime = DateTime.now().millisecondsSinceEpoch + (hari * 24 * 60 * 60 * 1000);
      if (jenis == 'pro') {
        updateSaaS = {'proMode': true, 'proModeExpire': expireTime};
        updateShop = {'proMode': true, 'proModeExpire': expireTime};
      } else {
        updateSaaS = {'addonGallery': true, 'galleryExpire': expireTime};
        updateShop = {'addonGallery': true, 'galleryExpire': expireTime};
      }
    }

    try {
      await widget.db.collection('saas_dealers').doc(_dealerID).update(updateSaaS);
      await widget.db.collection('shops_$_dealerID').doc(_shopID).update(updateShop);

      setState(() {
        _d.addAll(updateSaaS);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pakej ${jenis.toUpperCase()} berjaya dikemaskini.'),
            backgroundColor: AppColors.green,
          ),
        );
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Module keys must match branch_dashboard_screen _moduleItems moduleId values
  static const List<Map<String, String>> _modulList = [
    {'id': 'widget', 'label': 'Dashboard'},
    {'id': 'Stock', 'label': 'Inventori'},
    {'id': 'DB_Cust', 'label': 'Pelanggan'},
    {'id': 'Booking', 'label': 'Booking'},
    {'id': 'Claim_warranty', 'label': 'Claim'},
    {'id': 'Collab', 'label': 'Kolaborasi'},
    {'id': 'Profesional', 'label': 'Pro Mode'},
    {'id': 'Refund', 'label': 'Refund'},
    {'id': 'Lost', 'label': 'Kerugian'},
    {'id': 'MaklumBalas', 'label': 'Prestasi'},
    {'id': 'Link', 'label': 'Link'},
    {'id': 'Fungsi_lain', 'label': 'Fungsi Lain'},
    {'id': 'Settings', 'label': 'Tetapan'},
  ];

  Map<String, dynamic> get _enabledModulesMap {
    final raw = _d['enabledModules'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  bool _isModuleEnabled(String id) {
    final m = _enabledModulesMap;
    if (m.isEmpty) return true; // default all on
    return m[id] != false;
  }

  Future<void> _toggleModule(String id, bool value) async {
    setState(() => _isSaving = true);
    try {
      final current = Map<String, dynamic>.from(_enabledModulesMap);
      if (current.isEmpty) {
        for (final m in _modulList) {
          current[m['id']!] = true;
        }
      }
      current[id] = value;
      // 1) Update dealer doc
      await widget.db.collection('saas_dealers').doc(_dealerID).set(
            {'enabledModules': current},
            SetOptions(merge: true),
          );
      // 2) Update ALL shops under this dealer (so every branch sees the change)
      try {
        final shopsSnap = await widget.db.collection('shops_$_dealerID').get();
        final batch = widget.db.batch();
        for (final d in shopsSnap.docs) {
          batch.set(d.reference, {'enabledModules': current}, SetOptions(merge: true));
        }
        await batch.commit();
      } catch (_) {
        // fallback: at least update the current known shop
        try {
          await widget.db.collection('shops_$_dealerID').doc(_shopID).set(
                {'enabledModules': current},
                SetOptions(merge: true),
              );
        } catch (_) {}
      }
      setState(() => _d['enabledModules'] = current);
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleGalleryAddon(bool value) async {
    if (value) {
      await _kemaskiniLangganan('gallery', 30);
    } else {
      await _kemaskiniLangganan('gallery', 0);
    }
  }

  Future<void> _kemaskiniModPekerja(bool isSingle) async {
    setState(() => _isSaving = true);
    try {
      await widget.db.collection('saas_dealers').doc(_dealerID).update({'singleStaffMode': isSingle});
      await widget.db.collection('shops_$_dealerID').doc(_shopID).update({'singleStaffMode': isSingle});

      setState(() {
        _d['singleStaffMode'] = isSingle;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mod ${isSingle ? 'Single Staff' : 'Multi Staff'} berjaya diaktifkan.'),
            backgroundColor: AppColors.green,
          ),
        );
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pilihTarikhLuput() async {
    DateTime initialDate = DateTime.now().add(const Duration(days: 30));
    final currentExpire = _d['expireDate'];
    if (currentExpire != null) {
      if (currentExpire is Timestamp) {
        initialDate = currentExpire.toDate();
      } else if (currentExpire is int && currentExpire > 0) {
        initialDate = DateTime.fromMillisecondsSinceEpoch(currentExpire);
      } else if (currentExpire is double && currentExpire > 0) {
        initialDate = DateTime.fromMillisecondsSinceEpoch(currentExpire.toInt());
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.card,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null) return;

    setState(() => _isSaving = true);
    try {
      final expireMs = picked.millisecondsSinceEpoch;
      await widget.db.collection('saas_dealers').doc(_dealerID).update({'expireDate': expireMs});
      await widget.db.collection('shops_$_dealerID').doc(_shopID).update({'expireDate': expireMs});

      setState(() {
        _d['expireDate'] = expireMs;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tarikh luput dikemaskini: ${DateFormat('dd MMM yyyy').format(picked)}'),
            backgroundColor: AppColors.green,
          ),
        );
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleSuspend() async {
    final currentStatus = (_d['status'] ?? 'Aktif').toString();
    final isCurrentlySuspended = currentStatus == 'Digantung' || currentStatus == 'Suspend';
    final newStatus = isCurrentlySuspended ? 'Aktif' : 'Digantung';
    final actionLabel = isCurrentlySuspended ? 'AKTIFKAN SEMULA' : 'GANTUNG';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderMed),
        ),
        title: Text(
          '$actionLabel akaun ini?',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          isCurrentlySuspended
              ? 'Akaun ini akan diaktifkan semula dan boleh digunakan.'
              : 'Akaun ini akan digantung dan tidak boleh digunakan sementara.',
          style: const TextStyle(color: AppColors.textSub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlySuspended ? AppColors.green : AppColors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await widget.db.collection('saas_dealers').doc(_dealerID).update({'status': newStatus});
      setState(() {
        _d['status'] = newStatus;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Akaun berjaya ${isCurrentlySuspended ? 'diaktifkan semula' : 'digantung'}.'),
            backgroundColor: isCurrentlySuspended ? AppColors.green : AppColors.orange,
          ),
        );
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _padamAkaun() async {
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.red),
        ),
        title: const Text(
          'PADAM AKAUN?',
          style: TextStyle(color: AppColors.red, fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Anda pasti mahu MEMADAM akaun "${_d['namaKedai'] ?? ''}"?\n\nTindakan ini TIDAK BOLEH dibatalkan.',
          style: const TextStyle(color: AppColors.textSub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Padam', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm1 != true) return;
    if (!mounted) return;

    // Second confirmation
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.red),
        ),
        title: const Text(
          'PENGESAHAN AKHIR',
          style: TextStyle(color: AppColors.red, fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Ini adalah pengesahan AKHIR. Semua data akaun akan dipadam secara kekal.',
          style: TextStyle(color: AppColors.textSub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PADAM KEKAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (confirm2 != true) return;

    setState(() => _isSaving = true);
    try {
      await widget.db.collection('saas_dealers').doc(_dealerID).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Akaun berjaya dipadam.'), backgroundColor: AppColors.green),
        );
        Navigator.pop(context);
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final galleryActive = _d['addonGallery'] == true;
    final singleStaff = _d['singleStaffMode'] == true;
    final nama = _d['namaKedai'] ?? _d['shopName'] ?? '-';
    final currentStatus = (_d['status'] ?? 'Aktif').toString();
    final isGantung = currentStatus == 'Digantung' || currentStatus == 'Suspend';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nama,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: $_shopID',
                          style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.borderMed, height: 1),
            // Content
            Expanded(
              child: _isSaving
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // ─── Maklumat Asas ────────────────────
                        _buildSection(
                          icon: FontAwesomeIcons.circleInfo,
                          title: 'Maklumat Asas',
                          color: AppColors.textSub,
                          trailing: GestureDetector(
                            onTap: () {
                              if (_editAsas) {
                                _simpanMaklumatAsas();
                              } else {
                                _initAsasControllers();
                                setState(() => _editAsas = true);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: (_editAsas ? AppColors.green : AppColors.blue).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (_editAsas ? AppColors.green : AppColors.blue).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                FaIcon(
                                  _editAsas ? FontAwesomeIcons.floppyDisk : FontAwesomeIcons.penToSquare,
                                  size: 10,
                                  color: _editAsas ? AppColors.green : AppColors.blue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _editAsas ? 'SIMPAN' : 'EDIT',
                                  style: TextStyle(
                                    color: _editAsas ? AppColors.green : AppColors.blue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          child: Column(
                            children: [
                              _idRow(FontAwesomeIcons.idBadge, 'Owner ID / Username', _dealerID, AppColors.orange),
                              const SizedBox(height: 6),
                              _idRow(FontAwesomeIcons.shop, 'Shop ID', _shopID, AppColors.primary),
                              const SizedBox(height: 12),
                              if (_editAsas) ...[
                                _editField('Pemilik', _ownerCtrl, FontAwesomeIcons.user),
                                _editField('SSM', _ssmCtrl, FontAwesomeIcons.idCard),
                                _editField('Alamat', _alamatCtrl, FontAwesomeIcons.locationDot, maxLines: 2),
                                _editField('Daerah', _daerahCtrl, FontAwesomeIcons.mapLocationDot),
                                _editField('Negeri', _negeriCtrl, FontAwesomeIcons.flag),
                                _editField('Telefon', _telCtrl, FontAwesomeIcons.phone, keyboardType: TextInputType.phone),
                                _editField('Emel', _emelCtrl, FontAwesomeIcons.envelope, keyboardType: TextInputType.emailAddress),
                                _editField('Password', _passCtrl, FontAwesomeIcons.key, obscure: !_showPassword, suffix: GestureDetector(
                                  onTap: () => setState(() => _showPassword = !_showPassword),
                                  child: Icon(
                                    _showPassword ? Icons.visibility_off : Icons.visibility,
                                    size: 16,
                                    color: AppColors.textMuted,
                                  ),
                                )),
                              ] else ...[
                                _infoRow('Pemilik', _d['ownerName'] ?? '-'),
                                _infoRow('SSM', _d['ssm'] ?? '-'),
                                _infoRow('Alamat', _d['alamat'] ?? _d['address'] ?? '-'),
                                _infoRow('Daerah', _d['daerah'] ?? '-'),
                                _infoRow('Negeri', _d['negeri'] ?? '-'),
                                _infoRow('Telefon', _d['ownerContact'] ?? _d['phone'] ?? '-'),
                                _infoRow('Emel', _d['emel'] ?? _d['email'] ?? '-'),
                                Row(children: [
                                  const SizedBox(
                                    width: 80,
                                    child: Text('Password', style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _showPassword
                                          ? ((_d['password'] ?? '-').toString())
                                          : ((_d['password'] ?? '').toString().isEmpty
                                              ? '-'
                                              : '•' * (_d['password'].toString().length)),
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _showPassword = !_showPassword),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        _showPassword ? Icons.visibility_off : Icons.visibility,
                                        size: 14,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ]),
                                const Divider(color: AppColors.borderMed, height: 20),
                                const Row(children: [
                                  FaIcon(FontAwesomeIcons.userShield, size: 11, color: AppColors.cyan),
                                  SizedBox(width: 6),
                                  Text('SUPERVISOR',
                                      style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                                ]),
                                const SizedBox(height: 8),
                                _infoRow('Tel SV', (_d['svTel'] ?? '-').toString()),
                                Row(children: [
                                  const SizedBox(
                                    width: 80,
                                    child: Text('Pass SV', style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _showPassword
                                          ? ((_d['svPass'] ?? '-').toString())
                                          : ((_d['svPass'] ?? '').toString().isEmpty
                                              ? '-'
                                              : '•' * (_d['svPass'].toString().length)),
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ─── Akses Menu (Switches) ────────────
                        _buildSection(
                          icon: FontAwesomeIcons.listCheck,
                          title: 'Akses Menu Pengguna',
                          color: AppColors.primary,
                          child: Column(
                            children: [
                              ..._modulList.map((m) => _moduleSwitchRow(
                                    label: m['label']!,
                                    value: _isModuleEnabled(m['id']!),
                                    onChanged: (v) => _toggleModule(m['id']!, v),
                                  )),
                              const Divider(color: AppColors.borderMed, height: 20),
                              _moduleSwitchRow(
                                label: 'Jualan Telefon',
                                value: _isModuleEnabled('JualTelefon'),
                                onChanged: (v) => _toggleModule('JualTelefon', v),
                                accent: const Color(0xFF0EA5E9),
                              ),
                              _moduleSwitchRow(
                                label: 'Add-On Gallery',
                                value: galleryActive,
                                onChanged: _toggleGalleryAddon,
                                accent: AppColors.yellow,
                              ),
                              _moduleSwitchRow(
                                label: 'Multi Staff',
                                value: !singleStaff,
                                onChanged: (v) => _kemaskiniModPekerja(!v),
                                accent: AppColors.cyan,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ─── Tarikh Luput ─────────────────────
                        _buildSection(
                          icon: FontAwesomeIcons.calendarDays,
                          title: 'Tarikh Luput Akaun',
                          color: AppColors.blue,
                          statusText: _formatTarikh(_d['expireDate']),
                          statusColor: _warnaStatus(_d['expireDate'], true),
                          child: SizedBox(
                            width: double.infinity,
                            child: _actionButton(
                              label: 'Tukar Tarikh Luput',
                              color: AppColors.blue,
                              onTap: _pilihTarikhLuput,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ─── Suspend + Delete (50/50) ──────────
                        _buildSection(
                          icon: FontAwesomeIcons.shieldHalved,
                          title: 'Tindakan Akaun',
                          color: AppColors.red,
                          child: Row(
                            children: [
                              Expanded(
                                child: _actionButton(
                                  label: isGantung ? 'Aktifkan' : 'Gantung',
                                  color: isGantung ? AppColors.green : AppColors.orange,
                                  isDestructive: !isGantung,
                                  onTap: _toggleSuspend,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _actionButton(
                                  label: 'Padam',
                                  color: AppColors.red,
                                  isDestructive: true,
                                  onTap: _padamAkaun,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderMed),
      ),
      child: Row(children: [
        FaIcon(icon, size: 11, color: color),
        const SizedBox(width: 8),
        Text('$label:', style: const TextStyle(color: AppColors.textDim, fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, fontFamily: 'monospace', letterSpacing: 0.5),
          ),
        ),
      ]),
    );
  }

  Widget _editField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FaIcon(icon, size: 13, color: AppColors.textMuted),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffix == null
              ? null
              : Padding(padding: const EdgeInsets.only(right: 10), child: suffix),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
    String? statusText,
    Color? statusColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (statusText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (statusColor ?? color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor ?? color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isActive = false,
    bool isDestructive = false,
  }) {
    return Material(
      color: isActive
          ? color.withValues(alpha: 0.2)
          : isDestructive
              ? AppColors.red.withValues(alpha: 0.1)
              : AppColors.bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? color.withValues(alpha: 0.5)
                  : isDestructive
                      ? AppColors.red.withValues(alpha: 0.4)
                      : AppColors.borderMed,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isDestructive ? AppColors.red : (isActive ? color : AppColors.textPrimary),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moduleSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? accent,
  }) {
    final c = accent ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: c,
              inactiveThumbColor: AppColors.textDim,
              inactiveTrackColor: AppColors.bg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
