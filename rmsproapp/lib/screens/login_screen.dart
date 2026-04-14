import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import 'branch_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'staff_dashboard_screen.dart';
import 'supervisor_dashboard_screen.dart';
import 'daftar_online_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _resetEmailController = TextEditingController();
  final _staffPhoneController = TextEditingController();
  final _staffPinController = TextEditingController();
  final _authService = AuthService();

  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isStaffLogin = false;
  String? _errorMessage;
  late AnimationController _animController;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnim = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
    _loadSavedId();
  }

  Future<void> _loadSavedId() async {
    final savedId = await _authService.getRememberedUserId();
    if (savedId != null && mounted) {
      setState(() {
        _userIdController.text = savedId;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _resetEmailController.dispose();
    _staffPhoneController.dispose();
    _staffPinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final rawInput = _userIdController.text.trim();
    final password = _passwordController.text.trim();

    if (rawInput.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Sila isi semua ruangan');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.login(rawInput, password);

      if (_rememberMe) {
        await _authService.rememberUserId(rawInput);
      } else {
        await _authService.clearRememberedUserId();
      }

      if (!mounted) return;

      if (result.type == LoginType.admin) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BranchDashboardScreen()),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
      _passwordController.clear();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStaffLogin() async {
    final phone = _staffPhoneController.text.trim();
    final pin = _staffPinController.text.trim();

    if (phone.isEmpty || pin.isEmpty) {
      setState(() => _errorMessage = 'Sila isi semua ruangan');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final result = await _authService.loginStaff(phone, pin);
      if (!mounted) return;
      final destination = result.type == LoginType.supervisor
          ? const SupervisorDashboardScreen()
          : const StaffDashboardScreen();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString());
      _staffPinController.clear();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showResetDialog() {
    _resetEmailController.clear();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Column(
              children: [
                Icon(Icons.lock_reset, size: 40, color: AppColors.primary),
                const SizedBox(height: 10),
                const Text(
                  'TETAPAN SEMULA',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Masukkan System ID anda. Password baru akan dijana secara automatik.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _resetEmailController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(hintText: 'System ID anda'),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    final systemId = _resetEmailController.text.trim().toLowerCase();
                    if (systemId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sila masukkan System ID'), backgroundColor: AppColors.red),
                      );
                      return;
                    }
                    setDialogState(() => isLoading = true);
                    try {
                      final doc = await FirebaseFirestore.instance.collection('saas_dealers').doc(systemId).get();
                      if (!doc.exists) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('System ID tidak dijumpai'), backgroundColor: AppColors.red),
                          );
                        }
                        setDialogState(() => isLoading = false);
                        return;
                      }

                      // Generate new password
                      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
                      final rand = DateTime.now().millisecondsSinceEpoch;
                      final newPass = List.generate(8, (i) => chars[(rand + i * 7) % chars.length]).join();

                      // Update both 'pass' and 'password' fields
                      await FirebaseFirestore.instance.collection('saas_dealers').doc(systemId).update({
                        'pass': newPass,
                        'password': newPass,
                      });

                      // Hantar email ke dealer
                      final dealerData = doc.data()!;
                      final dealerEmail = ((dealerData['email'] ?? dealerData['emel'] ?? dealerData['ownerEmail'] ?? '').toString()).trim();
                      final dealerName = (dealerData['ownerName'] ?? dealerData['namaKedai'] ?? systemId).toString();
                      if (dealerEmail.isNotEmpty && dealerEmail.contains('@')) {
                        await FirebaseFirestore.instance.collection('mail').add({
                          'to': dealerEmail,
                          'message': {
                            'subject': 'RMS Pro - Password Baru Anda',
                            'html': '''
<div style="font-family:Arial,sans-serif;max-width:500px;margin:0 auto;padding:20px;">
  <h2 style="color:#00C853;text-align:center;">RMS PRO</h2>
  <hr/>
  <p>Salam <b>$dealerName</b>,</p>
  <p>Password akaun anda telah ditetapkan semula. Berikut adalah maklumat log masuk baru anda:</p>
  <div style="background:#f5f5f5;padding:16px;border-radius:8px;text-align:center;margin:16px 0;">
    <p style="margin:4px 0;font-size:13px;color:#666;">System ID</p>
    <p style="margin:4px 0;font-size:18px;font-weight:bold;">$systemId</p>
    <br/>
    <p style="margin:4px 0;font-size:13px;color:#666;">Password Baru</p>
    <p style="margin:4px 0;font-size:24px;font-weight:bold;color:#00C853;letter-spacing:2px;">$newPass</p>
  </div>
  <p style="font-size:12px;color:#999;">Sila tukar password anda selepas log masuk di bahagian Settings.</p>
  <hr/>
  <p style="font-size:11px;color:#bbb;text-align:center;">© RMS Pro - Repair Management System</p>
</div>
''',
                          },
                        });
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (!mounted) return;

                      // Show confirmation
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(dealerEmail.isNotEmpty
                              ? 'Password baru telah dihantar ke $dealerEmail'
                              : 'Password berjaya ditukar. Sila hubungi admin untuk dapatkan password baru.'),
                          backgroundColor: AppColors.green,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ralat: $e'), backgroundColor: AppColors.red),
                        );
                      }
                      setDialogState(() => isLoading = false);
                    }
                  },
                  child: isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('RESET PASSWORD'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Glow effect background
          Positioned(
            top: MediaQuery.of(context).size.height * 0.2,
            left: MediaQuery.of(context).size.width * 0.5 - 175,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 120, spreadRadius: 20),
                ],
              ),
            ),
          ),
          // Login form
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AnimatedBuilder(
                listenable: _animController,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, _slideAnim.value),
                  child: Opacity(
                    opacity: _animController.value,
                    child: child,
                  ),
                ),
                child: _buildLoginBox(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginBox() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderMed),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 40, offset: const Offset(0, 20)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo
          Icon(Icons.shield, size: 45, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            'RMS PRO',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: [Shadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
          ),
          const SizedBox(height: 20),

          // Segment toggle: Pemilik / Staf
          Container(
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderMed),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _isStaffLogin = false; _errorMessage = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isStaffLogin ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('PEMILIK', textAlign: TextAlign.center,
                        style: TextStyle(
                          color: !_isStaffLogin ? Colors.black : AppColors.textMuted,
                          fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5,
                        )),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _isStaffLogin = true; _errorMessage = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isStaffLogin ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('STAF', textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isStaffLogin ? Colors.black : AppColors.textMuted,
                          fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5,
                        )),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Error message
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),

          // ── Owner login form ──
          if (!_isStaffLogin) ...[
            _buildLabel('ID SISTEM / PENGGUNA'),
            const SizedBox(height: 8),
            TextField(
              controller: _userIdController,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              decoration: const InputDecoration(),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLabel('KATA LALUAN'),
                GestureDetector(
                  onTap: _showResetDialog,
                  child: Text(
                    'Lupa Kata Laluan?',
                    style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              decoration: const InputDecoration(),
              onSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                    activeColor: AppColors.primary,
                    checkColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: const Text(
                    'Kekal Log Masuk (Ingat ID)',
                    style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLoading ? AppColors.border : null,
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.textMuted,
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted))
                    : const Text('LOG MASUK SEKARANG'),
              ),
            ),
          ],

          // ── Staff login form ──
          if (_isStaffLogin) ...[
            _buildLabel('NO TELEFON'),
            const SizedBox(height: 8),
            TextField(
              controller: _staffPhoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              decoration: const InputDecoration(hintText: '011...'),
            ),
            const SizedBox(height: 20),
            _buildLabel('PIN / KATA LALUAN'),
            const SizedBox(height: 8),
            TextField(
              controller: _staffPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              decoration: const InputDecoration(),
              onSubmitted: (_) => _handleStaffLogin(),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleStaffLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLoading ? AppColors.border : null,
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.textMuted,
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted))
                    : const Text('LOG MASUK STAF'),
              ),
            ),
          ],

          // Footer
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.only(top: 20),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderMed, style: BorderStyle.solid))),
            child: Column(
              children: [
                const Text(
                  'Belum ada akaun RMS Pro?',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DaftarOnlineScreen()));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    child: const Text('DAFTAR SEKARANG'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSub,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget? child;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) => builder(context, child);
}
