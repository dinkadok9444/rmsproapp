import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/billplz_service.dart'; // ToyyibpayService
import '../../services/marketplace_service.dart';
import '../../services/courier_service.dart';
import '../../theme/app_theme.dart';

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final int quantity;
  final String buyerOwnerID;
  final String buyerShopID;

  const CheckoutScreen({
    super.key,
    required this.item,
    required this.quantity,
    required this.buyerOwnerID,
    required this.buyerShopID,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const _purple = Color(0xFF8B5CF6);
  static const _priceRed = Color(0xFFEF4444);

  bool _isProcessing = false;

  // Alamat penerima
  final _namaCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _alamatCtrl = TextEditingController();
  final _bandarCtrl = TextEditingController();
  final _poskodCtrl = TextEditingController();
  final _negeriCtrl = TextEditingController();

  // Shipping cost
  double _shippingCost = 0;
  String _shippingService = '';
  bool _loadingShipping = false;
  String _senderPostcode = '';

  @override
  void initState() {
    super.initState();
    _loadReceiverAddress();
    _loadSenderPostcode();
  }

  @override
  void dispose() {
    _namaCtrl.dispose();
    _telCtrl.dispose();
    _alamatCtrl.dispose();
    _bandarCtrl.dispose();
    _poskodCtrl.dispose();
    _negeriCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReceiverAddress() async {
    final docId = '${widget.buyerOwnerID}_${widget.buyerShopID}';
    debugPrint('=== CHECKOUT LOAD RECEIVER === docId: $docId');
    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_shops')
          .doc(docId)
          .get();
      debugPrint('=== DOC EXISTS: ${doc.exists} ===');
      if (doc.exists) {
        final d = doc.data()!;
        debugPrint('=== RECEIVER DATA: receiverName=${d['receiverName']}, receiverAlamat=${d['receiverAlamat']} ===');
        _namaCtrl.text = d['receiverName'] ?? '';
        _telCtrl.text = d['receiverPhone'] ?? '';
        _alamatCtrl.text = d['receiverAlamat'] ?? '';
        _bandarCtrl.text = d['receiverBandar'] ?? '';
        _poskodCtrl.text = d['receiverPoskod'] ?? '';
        _negeriCtrl.text = d['receiverNegeri'] ?? '';
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('=== CHECKOUT LOAD ERROR: $e ===');
    }
  }

  double get _pricePerUnit {
    final p = widget.item['price'];
    if (p is num) return p.toDouble();
    return double.tryParse(p?.toString() ?? '0') ?? 0;
  }

  double get _subtotal => _pricePerUnit * widget.quantity;
  double get _grandTotal => _subtotal + _shippingCost;

  Future<void> _loadSenderPostcode() async {
    // Load seller's pickup postcode for shipping quote
    final sellerOwnerID = (widget.item['ownerID'] ?? '').toString();
    final sellerShopID = (widget.item['shopID'] ?? '').toString();
    if (sellerOwnerID.isEmpty || sellerShopID.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_shops')
          .doc('${sellerOwnerID}_$sellerShopID')
          .get();
      if (doc.exists) {
        _senderPostcode = (doc.data()?['pickupPoskod'] ?? '').toString();
      }
    } catch (_) {}
  }

  Future<void> _getShippingQuote() async {
    final receiverPostcode = _poskodCtrl.text.trim();
    if (_senderPostcode.isEmpty || receiverPostcode.isEmpty || receiverPostcode.length < 4) return;

    setState(() => _loadingShipping = true);
    try {
      final courier = CourierService();
      await courier.loadConfig();
      final quote = await courier.getShippingQuote(
        senderPostcode: _senderPostcode,
        receiverPostcode: receiverPostcode,
        weight: 0.5,
      );
      if (quote != null && mounted) {
        setState(() {
          _shippingCost = (quote['cost'] as num).toDouble();
          _shippingService = quote['serviceName'] as String;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingShipping = false);
  }
  double get _commission => _subtotal * 0.02;
  double get _total => _subtotal;
  double get _sellerPayout => _total * 0.98;

  String _rm(double v) => v.toStringAsFixed(2);

  // ─────────────────────────────────────────
  // PAYMENT FLOW
  // ─────────────────────────────────────────

  Future<void> _processPayment() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // 1. Buyer shop name
      final buyerShopName = await _getBuyerShopName();

      // Validate alamat penerima
      if (_namaCtrl.text.trim().isEmpty || _telCtrl.text.trim().isEmpty ||
          _alamatCtrl.text.trim().isEmpty || _poskodCtrl.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sila isi alamat penerima yang lengkap'), backgroundColor: _priceRed),
          );
          setState(() => _isProcessing = false);
        }
        return;
      }

      // 2. Create order with receiver address
      final orderData = {
        'itemDocId': widget.item['_docId'] ?? widget.item['docId'] ?? '',
        'itemName': widget.item['itemName'] ?? widget.item['name'] ?? '',
        'category': widget.item['category'] ?? '',
        'pricePerUnit': _pricePerUnit,
        'quantity': widget.quantity,
        'totalPrice': _grandTotal,
        'productPrice': _subtotal,
        'shippingCost': _shippingCost,
        'shippingService': _shippingService,
        'commission': _commission,
        'sellerPayout': _sellerPayout,
        'sellerOwnerID': widget.item['ownerID'] ?? '',
        'sellerShopID': widget.item['shopID'] ?? '',
        'sellerShopName': widget.item['shopName'] ?? '',
        'buyerOwnerID': widget.buyerOwnerID,
        'buyerShopID': widget.buyerShopID,
        'buyerShopName': buyerShopName,
        // Alamat penerima
        'receiverName': _namaCtrl.text.trim(),
        'receiverPhone': _telCtrl.text.trim(),
        'receiverAlamat': _alamatCtrl.text.trim(),
        'receiverBandar': _bandarCtrl.text.trim(),
        'receiverPoskod': _poskodCtrl.text.trim(),
        'receiverNegeri': _negeriCtrl.text.trim(),
      };

      final orderId = await MarketplaceService().createOrder(orderData);

      // 3. ToyyibPay
      final toyyibpay = ToyyibpayService();
      await toyyibpay.loadConfig();

      if (toyyibpay.isConfigured) {
        final bill = await toyyibpay.createBill(
          orderId: orderId,
          buyerName: buyerShopName,
          buyerEmail: 'buyer@rms.my',
          buyerPhone: _telCtrl.text.trim(),
          amount: _grandTotal,
          description: 'RMS Marketplace: ${(widget.item['itemName'] ?? widget.item['name'] ?? 'Produk').toString()}',
          callbackUrl: 'https://us-central1-rmspro-2f454.cloudfunctions.net/toyyibpayCallback',
          redirectUrl: 'https://rmspro.net/payment-complete',
        );

        if (bill != null) {
          await MarketplaceService().updateOrderBillplz(
            orderId,
            bill['billCode']!,
            bill['url']!,
          );

          await _notifySeller(orderId, buyerShopName);

          final uri = Uri.parse(bill['url']!);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }

          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pesanan berjaya dibuat. Sila selesaikan pembayaran.'),
                backgroundColor: _purple,
              ),
            );
          }
          return;
        }
      }

      // 4. ToyyibPay not configured — testing mode
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Makluman'),
            content: const Text(
              'Payment gateway belum dikonfigurasi. '
              'Pesanan akan ditanda sebagai "paid" untuk tujuan ujian.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      // Mark as paid for testing
      await MarketplaceService().markOrderPaid(orderId);

      // Send notification to seller
      await _notifySeller(orderId, buyerShopName);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesanan berjaya dibuat!'),
            backgroundColor: _purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ralat: $e'),
            backgroundColor: _priceRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<String> _getBuyerShopName() async {
    // Try SharedPreferences first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('rms_shop_name');
    if (cached != null && cached.isNotEmpty) return cached;

    // Fallback to Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_shops')
          .doc('${widget.buyerOwnerID}_${widget.buyerShopID}')
          .get();
      if (doc.exists) {
        return doc.data()?['shopName'] ?? 'Pembeli';
      }
    } catch (_) {}
    return 'Pembeli';
  }

  Future<void> _notifySeller(String orderId, String buyerShopName) async {
    final sellerOwnerID = widget.item['ownerID'] ?? '';
    final sellerShopID = widget.item['shopID'] ?? '';
    if (sellerOwnerID.isEmpty) return;

    await MarketplaceService().sendNotification(
      targetOwnerID: sellerOwnerID,
      targetShopID: sellerShopID,
      type: 'new_order',
      title: 'Pesanan Baru!',
      message:
          '$buyerShopName telah membuat pesanan ${widget.item['name'] ?? ''} x${widget.quantity}.',
      orderDocId: orderId,
    );
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: _purple,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Order Summary ──
                  _buildOrderSummaryCard(),
                  const SizedBox(height: 16),

                  // ── Alamat Terima ──
                  _buildAlamatTerimaCard(),
                  const SizedBox(height: 16),

                  // ── Price Breakdown ──
                  _buildPriceBreakdown(),
                  const SizedBox(height: 16),

                  // ── Seller receives ──
                  _buildSellerReceivesInfo(),
                ],
              ),
            ),
          ),

          // ── Bottom Button ──
          _buildBottomButton(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────

  Widget _buildAlamatTerimaCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              FaIcon(FontAwesomeIcons.locationDot, size: 14, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Alamat Penerima', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Alamat untuk kurier hantar barang kepada anda', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          _addressField('Nama Penerima', _namaCtrl, 'cth: Ahmad bin Ali'),
          const SizedBox(height: 8),
          _addressField('No. Telefon', _telCtrl, 'cth: 0123456789'),
          const SizedBox(height: 8),
          _addressField('Alamat Penuh', _alamatCtrl, 'No. 1, Jalan ABC...'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _addressField('Bandar', _bandarCtrl, 'cth: Puchong')),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: TextField(
                controller: _poskodCtrl,
                onChanged: (v) { if (v.length >= 5) _getShippingQuote(); },
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Poskod',
                  labelStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  hintText: '47100',
                  hintStyle: const TextStyle(fontSize: 11, color: AppColors.textDim),
                  filled: true, fillColor: AppColors.bg, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _purple, width: 1.5)),
                ),
              )),
            ],
          ),
          const SizedBox(height: 8),
          _addressField('Negeri', _negeriCtrl, 'cth: Selangor'),
        ],
      ),
    );
  }

  Widget _addressField(String label, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.textDim),
        filled: true,
        fillColor: AppColors.bg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    final imageUrl = widget.item['imageUrl'] ?? widget.item['image'] ?? '';
    final name = widget.item['name'] ?? 'Produk';
    final lineTotal = _pricePerUnit * widget.quantity;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ringkasan Pesanan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl.toString().isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderImage(),
                      )
                    : _placeholderImage(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RM ${_rm(_pricePerUnit)} x ${widget.quantity}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'RM ${_rm(lineTotal)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _priceRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholderImage() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: _purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: FaIcon(FontAwesomeIcons.boxOpen, size: 24, color: _purple),
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pecahan Harga',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Subtotal
          _priceRow('Harga Produk', 'RM ${_rm(_subtotal)}'),
          const SizedBox(height: 8),

          // Shipping cost
          _loadingShipping
              ? Row(
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _purple)),
                    const SizedBox(width: 8),
                    const Text('Mengira kos penghantaran...', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                )
              : _shippingCost > 0
                  ? Column(
                      children: [
                        _priceRow('Kos Penghantaran', 'RM ${_rm(_shippingCost)}'),
                        if (_shippingService.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const FaIcon(FontAwesomeIcons.truck, size: 9, color: AppColors.textDim),
                                const SizedBox(width: 4),
                                Text(_shippingService, style: const TextStyle(fontSize: 9, color: AppColors.textDim)),
                              ],
                            ),
                          ),
                      ],
                    )
                  : _priceRow('Kos Penghantaran', 'Isi poskod untuk kira'),
          const SizedBox(height: 8),

          // Commission info
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.circleInfo, size: 10, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text(
                'Komisyen Platform (2%): RM ${_rm(_commission)}',
                style: const TextStyle(fontSize: 10, color: AppColors.textDim, fontStyle: FontStyle.italic),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppColors.border, height: 1),
          ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Jumlah Bayaran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              Text('RM ${_rm(_grandTotal)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _priceRed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSub),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerReceivesInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _purple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.shopSlash, size: 14, color: _purple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Penjual akan menerima: RM ${_rm(_sellerPayout)} (98%)',
              style: const TextStyle(
                fontSize: 12,
                color: _purple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _processPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: _purple,
            disabledBackgroundColor: _purple.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'BAYAR SEKARANG (RM ${_rm(_grandTotal)})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}
