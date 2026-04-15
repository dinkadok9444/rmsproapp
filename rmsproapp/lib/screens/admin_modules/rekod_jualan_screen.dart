import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/supabase_client.dart';

class RekodJualanScreen extends StatefulWidget {
  const RekodJualanScreen({super.key});

  @override
  State<RekodJualanScreen> createState() => _RekodJualanScreenState();
}

class _RekodJualanScreenState extends State<RekodJualanScreen>
    with SingleTickerProviderStateMixin {
  final _sb = SupabaseService.client;
  final _searchCtrl = TextEditingController();

  late TabController _tabCtrl;

  // Tab 1 - Langganan SaaS
  List<Map<String, dynamic>> _dealers = [];
  List<Map<String, dynamic>> _filteredDealers = [];
  String _saasTimeFilter = 'Semua';
  bool _isLoadingSaas = true;

  // Tab 2 - Jualan Dealer
  List<Map<String, dynamic>> _dealerSales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  String _salesTimeFilter = 'Semua';
  bool _isLoadingSales = true;

  // Package pricing
  static const Map<String, double> _packagePrice = {
    '1': 30.0,
    '6': 150.0,
    '12': 250.0,
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _loadSaasData();
    _loadDealerSales();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════

  DateTime? _parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is double) return DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    if (ts is String && ts.isNotEmpty) return DateTime.tryParse(ts);
    return null;
  }

  String _formatDate(dynamic ts) {
    final d = _parseTimestamp(ts);
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy').format(d);
  }

  String _formatRM(double amount) {
    return NumberFormat('#,##0.00', 'ms_MY').format(amount);
  }

  bool _matchesTimeFilter(DateTime? date, String filter) {
    if (date == null || filter == 'Semua') return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (filter) {
      case 'Hari Ini':
        return date.isAfter(today) ||
            (date.year == today.year &&
                date.month == today.month &&
                date.day == today.day);
      case 'Minggu Ini':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        return date.isAfter(weekStart) || date.isAtSameMomentAs(weekStart);
      case 'Bulan Ini':
        return date.year == now.year && date.month == now.month;
      default:
        return true;
    }
  }

  String _resolvePackageKey(Map<String, dynamic> d) {
    final pkg = (d['package'] ?? d['planType'] ?? '').toString().trim();
    if (pkg.contains('12')) return '12';
    if (pkg.contains('6')) return '6';
    return '1';
  }

  double _resolvePayment(Map<String, dynamic> d) {
    final key = _resolvePackageKey(d);
    return _packagePrice[key] ?? 30.0;
  }

  // ═══════════════════════════════════════
  // TAB 1 — LANGGANAN SAAS
  // ═══════════════════════════════════════

  Future<void> _loadSaasData() async {
    setState(() => _isLoadingSaas = true);
    try {
      final rows = await _sb.from('tenants').select();
      _dealers = rows.map<Map<String, dynamic>>((r) {
        final config = (r['config'] is Map) ? Map<String, dynamic>.from(r['config']) : <String, dynamic>{};
        return {
          'id': r['id'],
          'ownerID': r['owner_id'],
          'namaKedai': r['nama_kedai'] ?? '',
          'ownerName': config['ownerName'] ?? '',
          'ownerPhone': config['ownerContact'] ?? '',
          'phone': config['ownerContact'] ?? '',
          'package': config['package'] ?? config['planType'] ?? '1',
          'createdAt': r['created_at'],
          'joinDate': r['created_at'],
        };
      }).toList();
      _dealers.sort((a, b) {
        final da = _parseTimestamp(a['createdAt'] ?? a['joinDate']);
        final db = _parseTimestamp(b['createdAt'] ?? b['joinDate']);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
      _applySaasFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSaas = false);
    }
  }

  void _applySaasFilter() {
    final query = _searchCtrl.text.toLowerCase();
    _filteredDealers = _dealers.where((d) {
      final joinDate =
          _parseTimestamp(d['createdAt'] ?? d['joinDate']);
      if (!_matchesTimeFilter(joinDate, _saasTimeFilter)) return false;
      if (query.isNotEmpty) {
        final nama = (d['namaKedai'] ?? d['shopName'] ?? '').toString().toLowerCase();
        final owner = (d['ownerName'] ?? '').toString().toLowerCase();
        final phone = (d['ownerPhone'] ?? d['phone'] ?? '').toString().toLowerCase();
        final id = (d['id'] ?? '').toString().toLowerCase();
        return nama.contains(query) ||
            owner.contains(query) ||
            phone.contains(query) ||
            id.contains(query);
      }
      return true;
    }).toList();
    setState(() {});
  }

  // ═══════════════════════════════════════
  // TAB 2 — JUALAN DEALER
  // ═══════════════════════════════════════

  Future<void> _loadDealerSales() async {
    setState(() => _isLoadingSales = true);
    try {
      // Read pre-aggregated totals from tenants (total_sales, ticket_count).
      final rows = await _sb
          .from('tenants')
          .select()
          .order('total_sales', ascending: false)
          .limit(100);

      _dealerSales = rows.map<Map<String, dynamic>>((r) {
        final config = (r['config'] is Map) ? Map<String, dynamic>.from(r['config']) : <String, dynamic>{};
        return {
          'id': r['id'],
          'ownerID': r['owner_id'],
          'namaKedai': r['nama_kedai'] ?? '',
          'ownerName': config['ownerName'] ?? '',
          'ticketCount': r['ticket_count'] ?? 0,
          'totalSales': (r['total_sales'] as num?)?.toDouble() ?? 0.0,
          'createdAt': r['created_at'],
          'joinDate': r['created_at'],
        };
      }).toList();

      _applySalesFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSales = false);
    }
  }

  void _applySalesFilter() {
    _filteredSales = _dealerSales.where((d) {
      final joinDate =
          _parseTimestamp(d['createdAt'] ?? d['joinDate']);
      return _matchesTimeFilter(joinDate, _salesTimeFilter);
    }).toList();
    setState(() {});
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            unselectedLabelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'LANGGANAN SAAS'),
              Tab(text: 'JUALAN DEALER'),
            ],
          ),
        ),
        // Tab body
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildLanggananTab(),
              _buildJualanTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // TAB 1 — LANGGANAN SAAS UI
  // ═══════════════════════════════════════

  Widget _buildLanggananTab() {
    // Stats
    double totalCollection = 0;
    int count1 = 0, count6 = 0, count12 = 0;
    for (final d in _filteredDealers) {
      final key = _resolvePackageKey(d);
      totalCollection += _resolvePayment(d);
      if (key == '1') count1++;
      if (key == '6') count6++;
      if (key == '12') count12++;
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        // Summary card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const FaIcon(FontAwesomeIcons.sackDollar,
                  color: Colors.white, size: 22),
              const SizedBox(height: 8),
              const Text(
                'JUMLAH KUTIPAN SAAS',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text(
                'RM ${_formatRM(totalCollection)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _miniStat('1 Bulan', count1, Colors.white),
                  _miniStat('6 Bulan', count6, Colors.white),
                  _miniStat('12 Bulan', count12, Colors.white),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Time filter chips
        _buildTimeChips(_saasTimeFilter, (v) {
          _saasTimeFilter = v;
          _applySaasFilter();
        }),
        const SizedBox(height: 8),
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cari dealer, nama kedai, telefon...',
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textMuted, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        _searchCtrl.clear();
                        _applySaasFilter();
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (_) => _applySaasFilter(),
          ),
        ),
        const SizedBox(height: 6),
        // Count label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_filteredDealers.length} dealer',
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // List
        Expanded(
          child: _isLoadingSaas
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary))
              : _filteredDealers.isEmpty
                  ? const Center(
                      child: Text('Tiada rekod',
                          style: TextStyle(color: AppColors.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _loadSaasData,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: _filteredDealers.length,
                        itemBuilder: (_, i) =>
                            _buildSaasCard(_filteredDealers[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSaasCard(Map<String, dynamic> d) {
    final nama = d['namaKedai'] ?? d['shopName'] ?? '-';
    final owner = d['ownerName'] ?? '-';
    final phone = d['ownerPhone'] ?? d['phone'] ?? '-';
    final joinDate = _formatDate(d['createdAt'] ?? d['joinDate']);
    final pkgKey = _resolvePackageKey(d);
    final amount = _resolvePayment(d);

    Color pkgColor;
    String pkgLabel;
    switch (pkgKey) {
      case '12':
        pkgColor = AppColors.orange;
        pkgLabel = '12 Bulan';
        break;
      case '6':
        pkgColor = AppColors.blue;
        pkgLabel = '6 Bulan';
        break;
      default:
        pkgColor = AppColors.green;
        pkgLabel = '1 Bulan';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Package badge
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: pkgColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${pkgKey}B',
                style: TextStyle(
                    color: pkgColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama.toString(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.user,
                        size: 10, color: AppColors.textDim),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '$owner  •  $phone',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.calendar,
                        size: 10, color: AppColors.textDim),
                    const SizedBox(width: 5),
                    Text(
                      joinDate,
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Amount + Package
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RM ${_formatRM(amount)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pkgColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  pkgLabel,
                  style: TextStyle(
                      color: pkgColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // TAB 2 — JUALAN DEALER UI
  // ═══════════════════════════════════════

  Widget _buildJualanTab() {
    double totalNetworkSales = 0;
    for (final d in _filteredSales) {
      totalNetworkSales += (d['totalSales'] as double?) ?? 0;
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        // Summary card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.blue,
                AppColors.blue.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.blue.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const FaIcon(FontAwesomeIcons.rankingStar,
                  color: Colors.white, size: 22),
              const SizedBox(height: 8),
              const Text(
                'JUMLAH JUALAN RANGKAIAN',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text(
                'RM ${_formatRM(totalNetworkSales)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Top ${_filteredSales.length} Dealer',
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Time filter chips
        _buildTimeChips(_salesTimeFilter, (v) {
          _salesTimeFilter = v;
          _applySalesFilter();
        }),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: _isLoadingSales
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary))
              : _filteredSales.isEmpty
                  ? const Center(
                      child: Text('Tiada rekod',
                          style: TextStyle(color: AppColors.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _loadDealerSales,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: _filteredSales.length,
                        itemBuilder: (_, i) =>
                            _buildSalesCard(_filteredSales[i], i + 1),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSalesCard(Map<String, dynamic> d, int rank) {
    final nama = d['namaKedai'] ?? d['shopName'] ?? '-';
    final dealerID = d['id'] ?? '-';
    final ticketCount = d['ticketCount'] ?? 0;
    final totalSales = (d['totalSales'] as double?) ?? 0;

    // Rank styling
    Color rankBg;
    Color rankFg;
    IconData? rankIcon;
    switch (rank) {
      case 1:
        rankBg = const Color(0xFFFFC107);
        rankFg = const Color(0xFF7B5E00);
        rankIcon = FontAwesomeIcons.trophy;
        break;
      case 2:
        rankBg = const Color(0xFFB0BEC5);
        rankFg = const Color(0xFF37474F);
        rankIcon = FontAwesomeIcons.medal;
        break;
      case 3:
        rankBg = const Color(0xFFD4915C);
        rankFg = const Color(0xFF5D3A1A);
        rankIcon = FontAwesomeIcons.award;
        break;
      default:
        rankBg = AppColors.bg;
        rankFg = AppColors.textMuted;
        rankIcon = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rank <= 3
              ? rankBg.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: rankBg.withValues(alpha: rank <= 3 ? 0.2 : 1.0),
              borderRadius: BorderRadius.circular(10),
              border: rank <= 3
                  ? Border.all(color: rankBg.withValues(alpha: 0.5))
                  : null,
            ),
            child: Center(
              child: rankIcon != null
                  ? FaIcon(rankIcon, size: 16, color: rankFg)
                  : Text(
                      '#$rank',
                      style: TextStyle(
                          color: rankFg,
                          fontSize: 13,
                          fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama.toString(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'ID: $dealerID',
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 10),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.ticket,
                        size: 10, color: AppColors.textDim),
                    const SizedBox(width: 5),
                    Text(
                      '$ticketCount tiket selesai',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Total
          Text(
            'RM ${_formatRM(totalSales)}',
            style: TextStyle(
              color: rank <= 3 ? rankFg : AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════

  Widget _buildTimeChips(String selected, ValueChanged<String> onChanged) {
    const filters = ['Semua', 'Hari Ini', 'Minggu Ini', 'Bulan Ini'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = filters[i];
          final isSelected = f == selected;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: Text(
                f,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniStat(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
