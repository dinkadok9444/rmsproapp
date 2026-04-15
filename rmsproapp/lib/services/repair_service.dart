import 'dart:math';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_client.dart';

class RepairService {
  String? _ownerID;
  String? _shopID;
  String? _tenantId;
  String? _branchId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final branch = prefs.getString('rms_current_branch') ?? '';
    if (branch.contains('@')) {
      final parts = branch.split('@');
      _ownerID = parts[0].toLowerCase();
      _shopID = parts[1].toUpperCase();
    } else {
      _ownerID = 'admin';
      _shopID = 'MAIN';
    }
    _tenantId = prefs.getString('rms_tenant_id');
    _branchId = prefs.getString('rms_branch_id');

    // Fallback: resolve from DB kalau prefs kosong (sebelum BranchService.initialize)
    if (_tenantId == null || _branchId == null) {
      final row = await SupabaseService.client
          .from('branches')
          .select('id, tenant_id, tenants!inner(owner_id)')
          .eq('shop_code', _shopID!)
          .eq('tenants.owner_id', _ownerID!)
          .maybeSingle();
      if (row != null) {
        _branchId = row['id'] as String;
        _tenantId = row['tenant_id'] as String;
        await prefs.setString('rms_tenant_id', _tenantId!);
        await prefs.setString('rms_branch_id', _branchId!);
      }
    }
  }

  String get ownerID => _ownerID ?? 'admin';
  String get shopID => _shopID ?? 'MAIN';
  String? get tenantId => _tenantId;
  String? get branchId => _branchId;

  String _generateVoucherCode() {
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final code = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
    return 'V-$code';
  }

  Future<String> _getNextSiri() async {
    if (_tenantId == null || _branchId == null) throw Exception('Tenant/branch belum di-resolve');
    // RPC: atomic increment kat job_counters, return siri string
    final result = await SupabaseService.client.rpc('next_siri', params: {
      'p_tenant_id': _tenantId,
      'p_branch_id': _branchId,
      'p_shop_code': shopID,
    });
    return result as String;
  }

  Future<String> simpanTiket({
    required String nama,
    required String tel,
    String telWasap = '',
    required String model,
    required String jenisServis,
    String catatan = '',
    required List<RepairItem> items,
    required String tarikh,
    required double harga,
    required double deposit,
    required String paymentStatus,
    required String caraBayaran,
    String staffTerima = '',
    String phonePass = '',
    String patternResult = '',
    String custType = 'NEW CUST',
    String kodVoucher = '',
    double voucherAmt = 0,
  }) async {
    await init();
    final siri = await _getNextSiri();
    final newVoucherGen = _generateVoucherCode();

    String finalPass = phonePass.isNotEmpty ? phonePass : 'Tiada';
    if (patternResult.isNotEmpty && finalPass == 'Tiada') {
      finalPass = 'Pattern: $patternResult';
    } else if (patternResult.isNotEmpty) {
      finalPass += ' (Pattern: $patternResult)';
    }

    final kerosakan = items.map((i) => '${i.nama} (x${i.qty})').join(', ');
    final total = harga - voucherAmt - deposit;

    final sb = SupabaseService.client;

    // Insert job row
    final jobRow = await sb
        .from('jobs')
        .insert({
          'tenant_id': _tenantId,
          'branch_id': _branchId,
          'siri': siri,
          'receipt_no': siri,
          'nama': nama.toUpperCase(),
          'tel': tel,
          'tel_wasap': telWasap.isNotEmpty ? telWasap : '-',
          'model': model.toUpperCase(),
          'kerosakan': kerosakan,
          'jenis_servis': jenisServis,
          'status': 'IN PROGRESS',
          'tarikh': tarikh,
          'harga': harga,
          'deposit': deposit,
          'diskaun': 0,
          'tambahan': 0,
          'total': total,
          'baki': total,
          'payment_status': paymentStatus,
          'cara_bayaran': caraBayaran,
          'voucher_generated': newVoucherGen,
          'voucher_used': kodVoucher,
          'voucher_used_amt': voucherAmt,
          'device_password': finalPass,
          'cust_type': custType,
          'staff_terima': staffTerima,
          'catatan': catatan,
        })
        .select('id')
        .single();
    final jobId = jobRow['id'] as String;

    // Insert items
    if (items.isNotEmpty) {
      await sb.from('job_items').insert(items
          .map((i) => {
                'tenant_id': _tenantId,
                'job_id': jobId,
                'nama': i.nama,
                'qty': i.qty,
                'harga': i.harga,
              })
          .toList());
    }

    // Initial timeline
    await sb.from('job_timeline').insert({
      'tenant_id': _tenantId,
      'job_id': jobId,
      'status': 'IN PROGRESS',
      'note': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
      'by_user': staffTerima,
    });

    return siri;
  }

  Future<List<Map<String, dynamic>>> getDrafts() async {
    await init();
    final rows = await SupabaseService.client
        .from('job_drafts')
        .select()
        .eq('branch_id', _branchId!)
        .eq('status', 'ACTIVE')
        .order('created_at', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> deleteDraft(String draftId) async {
    await init();
    try {
      await SupabaseService.client.from('job_drafts').delete().eq('id', draftId);
    } catch (_) {
      try {
        await SupabaseService.client
            .from('job_drafts')
            .update({'status': 'PULLED'}).eq('id', draftId);
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> getInventory() async {
    await init();
    final rows = await SupabaseService.client
        .from('stock_parts')
        .select()
        .eq('tenant_id', _tenantId!)
        .eq('status', 'AVAILABLE')
        .gt('qty', 0);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> getBranchSettings() async {
    await init();
    if (_tenantId == null || _branchId == null) return null;

    final row = await SupabaseService.client
        .from('branches')
        .select(
            'nama_kedai, alamat, phone, email, enabled_modules, single_staff_mode, expire_date, tenants!inner(addon_gallery, gallery_expire, single_staff_mode, config)')
        .eq('id', _branchId!)
        .maybeSingle();
    if (row == null) return null;

    final merged = <String, dynamic>{};
    final tenant = row['tenants'] as Map?;
    if (tenant != null) merged.addAll(Map<String, dynamic>.from(tenant));
    final branchFields = Map<String, dynamic>.from(row)..remove('tenants');
    merged.addAll(branchFields);

    bool hasGallery = merged['addon_gallery'] == true;
    final ge = merged['gallery_expire'];
    if (hasGallery && ge != null) {
      final dt = DateTime.tryParse(ge.toString());
      if (dt != null && DateTime.now().isAfter(dt)) hasGallery = false;
    }
    merged['hasGalleryAddon'] = hasGallery;
    merged['singleStaffMode'] = merged['single_staff_mode'] == true;
    return merged;
  }

  Future<List<String>> getStaffList() async {
    await init();
    if (_branchId == null) return [];
    final rows = await SupabaseService.client
        .from('branch_staff')
        .select('nama')
        .eq('branch_id', _branchId!)
        .eq('status', 'active');
    return rows.map((r) => (r['nama'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
  }
}

class RepairItem {
  String nama;
  int qty;
  double harga;
  RepairItem({required this.nama, this.qty = 1, this.harga = 0});
}
