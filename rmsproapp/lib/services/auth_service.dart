import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _generateToken() {
    final random = Random();
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final token = List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
    return '$token${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  }

  Future<LoginResult> login(String rawInput, String password) async {
    final newToken = _generateToken();

    // Admin login
    if (rawInput.toLowerCase() == 'admin') {
      if (password == 'master123') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('rms_session_token', newToken);
        await prefs.setString('rms_saved_id', 'admin');
        await prefs.setString('rms_user_role', 'admin');
        return LoginResult(success: true, type: LoginType.admin);
      } else {
        throw 'Katalaluan Salah';
      }
    }

    // Branch login (format: owner@BRANCH)
    if (rawInput.contains('@')) {
      final parts = rawInput.split('@');
      final ownerID = parts[0].toLowerCase();
      final branchID = parts[1].toUpperCase();
      final globalBranchID = '$ownerID@$branchID';

      final branchSnap = await _db.collection('global_branches').doc(globalBranchID).get();
      if (branchSnap.exists) {
        final branchData = branchSnap.data()!;
        if (password == branchData['pass']) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('rms_session_token', newToken);
          await prefs.setString('rms_current_branch', globalBranchID);
          return LoginResult(success: true, type: LoginType.branch, branchId: globalBranchID);
        } else {
          throw 'Katalaluan Salah';
        }
      } else {
        throw 'ID Tidak Wujud';
      }
    }

    // Owner login
    final ownerID = rawInput.toLowerCase();
    final ownerSnap = await _db.collection('saas_dealers').doc(ownerID).get();

    if (ownerSnap.exists) {
      final ownerData = ownerSnap.data()!;
      if (ownerData['status'] != null && ownerData['status'] != 'Aktif') {
        throw 'Akaun digantung';
      }

      if (password == ownerData['pass'] || password == ownerData['password']) {
        await _db.collection('saas_dealers').doc(ownerID).update({'sessionToken': newToken});

        final shopQuery = await _db.collection('shops_$ownerID').limit(1).get();
        if (shopQuery.docs.isEmpty) {
          throw 'Sila daftar sekurang-kurangnya satu cawangan.';
        }

        final actualShopID = shopQuery.docs[0].id;
        final branchId = '$ownerID@$actualShopID';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('rms_session_token', newToken);
        await prefs.setString('rms_current_branch', branchId);
        return LoginResult(success: true, type: LoginType.branch, branchId: branchId);
      } else {
        throw 'Katalaluan Salah';
      }
    } else {
      throw 'ID Tidak Dijumpai';
    }
  }

  Future<LoginResult> loginStaff(String phone, String pin) async {
    if (phone.isEmpty || pin.isEmpty) {
      throw 'Sila isi semua ruangan';
    }

    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final staffSnap = await _db.collection('global_staff').doc(cleanPhone).get();
    if (!staffSnap.exists) {
      throw 'No telefon tidak berdaftar';
    }

    final data = staffSnap.data()!;
    if (data['status'] == 'suspended') {
      throw 'Akaun staf digantung';
    }
    if (data['pin'] != pin) {
      throw 'PIN salah';
    }

    final ownerID = data['ownerID'] ?? '';
    final shopID = data['shopID'] ?? '';
    final branchId = '$ownerID@$shopID';
    final role = (data['role'] ?? 'staff').toString().toLowerCase();
    final newToken = _generateToken();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rms_session_token', newToken);
    await prefs.setString('rms_current_branch', branchId);
    await prefs.setString('rms_staff_name', data['name'] ?? '');
    await prefs.setString('rms_staff_phone', phone);
    await prefs.setString('rms_staff_role', role);

    // Log masuk staff ke staff_logs
    try {
      await _db.collection('staff_logs_$ownerID').add({
        'staffName': data['name'] ?? '',
        'staffPhone': cleanPhone,
        'action': 'LOG MASUK',
        'shopID': shopID,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}

    final loginType = role == 'supervisor' ? LoginType.supervisor : LoginType.staff;
    return LoginResult(success: true, type: loginType, branchId: branchId);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final staffName = prefs.getString('rms_staff_name') ?? '';
    final staffPhone = prefs.getString('rms_staff_phone') ?? '';
    final branch = prefs.getString('rms_current_branch') ?? '';

    // Log keluar staff ke staff_logs
    if (staffName.isNotEmpty && branch.contains('@')) {
      final ownerID = branch.split('@')[0];
      final shopID = branch.split('@')[1];
      try {
        await _db.collection('staff_logs_$ownerID').add({
          'staffName': staffName,
          'staffPhone': staffPhone,
          'action': 'LOG KELUAR',
          'shopID': shopID,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }

    await prefs.remove('rms_session_token');
    await prefs.remove('rms_current_branch');
    await prefs.remove('rms_staff_name');
    await prefs.remove('rms_staff_phone');
    await prefs.remove('rms_user_role');
  }

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
}

enum LoginType { admin, branch, staff, supervisor }

class LoginResult {
  final bool success;
  final LoginType type;
  final String? branchId;

  LoginResult({required this.success, required this.type, this.branchId});
}
