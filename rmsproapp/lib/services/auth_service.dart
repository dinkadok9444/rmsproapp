import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

// Synthetic email domain — Supabase Auth perlukan format email, tapi user
// tak pakai email sebenar untuk login. Prefix beza ikut jenis akaun.
const _domain = 'rmspro.internal';

class AuthService {
  SupabaseClient get _sb => SupabaseService.client;

  // ------------------------------------------------------------------
  // Login — Owner / Branch / Admin (input: system_id atau owner@BRANCH)
  // ------------------------------------------------------------------
  Future<LoginResult> login(String rawInput, String password) async {
    final input = rawInput.trim();

    // Admin
    if (input.toLowerCase() == 'admin') {
      await _signIn('admin@$_domain', password);
      final profile = await _loadProfile();
      if (profile.role != 'admin') {
        await _sb.auth.signOut();
        throw 'Akaun ini bukan admin';
      }
      await _persistSession(profile, branchId: null, userRole: 'admin');
      return LoginResult(success: true, type: LoginType.admin);
    }

    // Branch login: owner@BRANCH
    if (input.contains('@') && !input.contains(_domain)) {
      final parts = input.split('@');
      final ownerId = parts[0].toLowerCase();
      final branchCode = parts[1].toUpperCase();
      final syntheticEmail = 'owner.$ownerId.$branchCode@$_domain';

      await _signIn(syntheticEmail, password);
      final profile = await _loadProfile();
      final branchId = '$ownerId@$branchCode';
      await _persistSession(profile, branchId: branchId);
      return LoginResult(success: true, type: LoginType.branch, branchId: branchId);
    }

    // Owner login (system_id + password) — sign in guna synthetic email
    final ownerId = input.toLowerCase();
    await _signIn('$ownerId@$_domain', password);
    final profile = await _loadProfile();

    // Pick first available branch untuk tenant ni
    final branch = await _firstBranch(profile.tenantId);
    if (branch == null) {
      await _sb.auth.signOut();
      throw 'Sila daftar sekurang-kurangnya satu cawangan.';
    }
    final branchId = '${profile.ownerId}@${branch['shop_code']}';
    await _persistSession(profile, branchId: branchId);
    return LoginResult(success: true, type: LoginType.branch, branchId: branchId);
  }

  // ------------------------------------------------------------------
  // Login — Staff (input: phone + PIN)
  // ------------------------------------------------------------------
  Future<LoginResult> loginStaff(String phone, String pin) async {
    if (phone.isEmpty || pin.isEmpty) throw 'Sila isi semua ruangan';
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final syntheticEmail = 'staff.$cleanPhone@$_domain';

    await _signIn(syntheticEmail, pin);
    final profile = await _loadProfile();
    if (profile.status == 'suspended') {
      await _sb.auth.signOut();
      throw 'Akaun staf digantung';
    }

    // Cari branch_staff row untuk staff ni
    final staffRow = await _sb
        .from('branch_staff')
        .select('branch_id, role, nama, branches!inner(shop_code, tenant_id)')
        .eq('phone', cleanPhone)
        .maybeSingle();
    if (staffRow == null) throw 'No telefon tidak berdaftar';

    final branch = staffRow['branches'] as Map;
    final shopCode = branch['shop_code'];
    final branchId = '${profile.ownerId}@$shopCode';
    final role = (staffRow['role'] ?? 'staff').toString().toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rms_session_token', _sb.auth.currentSession?.accessToken ?? '');
    await prefs.setString('rms_current_branch', branchId);
    await prefs.setString('rms_staff_name', staffRow['nama'] ?? '');
    await prefs.setString('rms_staff_phone', cleanPhone);
    await prefs.setString('rms_staff_role', role);

    return LoginResult(
      success: true,
      type: role == 'supervisor' ? LoginType.supervisor : LoginType.staff,
      branchId: branchId,
    );
  }

  // ------------------------------------------------------------------
  // Logout
  // ------------------------------------------------------------------
  Future<void> logout() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rms_session_token');
    await prefs.remove('rms_current_branch');
    await prefs.remove('rms_staff_name');
    await prefs.remove('rms_staff_phone');
    await prefs.remove('rms_staff_role');
    await prefs.remove('rms_user_role');
  }

  // ------------------------------------------------------------------
  // Remember-me helpers
  // ------------------------------------------------------------------
  Future<void> rememberUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rms_saved_id', userId);
  }

  Future<void> clearRememberedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rms_saved_id');
  }

  Future<String?> getRememberedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rms_saved_id');
  }

  Future<String?> getCurrentBranch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rms_current_branch');
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------
  Future<void> _signIn(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid')) throw 'Katalaluan Salah';
      if (e.message.toLowerCase().contains('not found')) throw 'ID Tidak Dijumpai';
      throw e.message;
    }
  }

  Future<_Profile> _loadProfile() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw 'Sesi tidak sah';
    final row = await _sb
        .from('users')
        .select('tenant_id, role, status, tenants!inner(owner_id, status)')
        .eq('id', uid)
        .maybeSingle();
    if (row == null) throw 'Profil pengguna tidak dijumpai';
    final tenant = row['tenants'] as Map;
    if (tenant['status'] != null && tenant['status'] != 'Aktif') {
      await _sb.auth.signOut();
      throw 'Akaun digantung';
    }
    return _Profile(
      tenantId: row['tenant_id'] as String,
      role: row['role'] as String? ?? 'staff',
      status: row['status'] as String? ?? 'active',
      ownerId: tenant['owner_id'] as String,
    );
  }

  Future<Map<String, dynamic>?> _firstBranch(String tenantId) async {
    final rows = await _sb
        .from('branches')
        .select('id, shop_code')
        .eq('tenant_id', tenantId)
        .eq('active', true)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> _persistSession(_Profile profile,
      {String? branchId, String? userRole}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'rms_session_token', _sb.auth.currentSession?.accessToken ?? '');
    if (branchId != null) await prefs.setString('rms_current_branch', branchId);
    await prefs.setString('rms_user_role', userRole ?? profile.role);
  }
}

class _Profile {
  final String tenantId;
  final String role;
  final String status;
  final String ownerId;
  _Profile({
    required this.tenantId,
    required this.role,
    required this.status,
    required this.ownerId,
  });
}

enum LoginType { admin, branch, staff, supervisor }

class LoginResult {
  final bool success;
  final LoginType type;
  final String? branchId;
  LoginResult({required this.success, required this.type, this.branchId});
}
