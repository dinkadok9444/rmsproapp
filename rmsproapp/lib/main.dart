import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/branch_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/staff_dashboard_screen.dart';
import 'screens/supervisor_dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check — verify requests come from genuine app, not bots/scrapers
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      webProvider: kIsWeb
          ? ReCaptchaV3Provider('YOUR_RECAPTCHA_V3_SITE_KEY')
          : null,
    );
  } catch (e) {
    debugPrint('[AppCheck] init failed: $e');
  }

  // Setup FCM background handler (not supported on web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Initialize push notifications
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('[FCM] Notification init failed: $e');
  }

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
  }

  final prefs = await SharedPreferences.getInstance();
  final hasSession = prefs.getString('rms_session_token') != null;
  final hasBranch = prefs.getString('rms_current_branch') != null;
  final isStaff = prefs.getString('rms_staff_phone') != null && prefs.getString('rms_staff_phone')!.isNotEmpty;
  final staffRole = prefs.getString('rms_staff_role') ?? '';
  final userRole = prefs.getString('rms_user_role') ?? '';
  final isAdmin = userRole == 'admin';

  runApp(RmsProApp(isLoggedIn: hasSession && (hasBranch || isAdmin), isStaff: isStaff, staffRole: staffRole, isAdmin: isAdmin));
}

class RmsProApp extends StatelessWidget {
  final bool isLoggedIn;
  final bool isStaff;
  final String staffRole;
  final bool isAdmin;
  const RmsProApp({super.key, required this.isLoggedIn, this.isStaff = false, this.staffRole = '', this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (!isLoggedIn) {
      home = const LoginScreen();
    } else if (isAdmin) {
      home = const AdminDashboardScreen();
    } else if (isStaff && staffRole == 'supervisor') {
      home = const SupervisorDashboardScreen();
    } else if (isStaff) {
      home = const StaffDashboardScreen();
    } else {
      home = const BranchDashboardScreen();
    }
    return MaterialApp(
      title: 'RMS PRO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: home,
      routes: {
        '/login': (_) => const LoginScreen(),
        '/branch': (_) => const BranchDashboardScreen(),
        '/admin': (_) => const AdminDashboardScreen(),
        '/staff': (_) => const StaffDashboardScreen(),
        '/supervisor': (_) => const SupervisorDashboardScreen(),
      },
    );
  }
}
