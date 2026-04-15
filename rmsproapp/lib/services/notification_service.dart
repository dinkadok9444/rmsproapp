import 'dart:developer' as dev;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_client.dart';

/// Background message handler — mesti top-level function.
/// FCM kekal Firebase (exception dari migration); hanya storage token guna Supabase.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  dev.log('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotif = FlutterLocalNotificationsPlugin();

  static const _channelId = 'rms_pro_booking';
  static const _channelName = 'Booking Notifications';
  static const _channelDesc = 'Notifikasi booking baru dari customer';

  Future<void> initialize() async {
    final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
    dev.log('[FCM] Permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    if (!kIsWeb) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _localNotif.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      );
      await _localNotif
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    FirebaseMessaging.onMessage.listen(_showLocalNotification);
    await _saveToken();
    _messaging.onTokenRefresh.listen((_) => _saveToken());
  }

  Future<void> _saveToken() async {
    try {
      String? token;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _messaging.getAPNSToken();
        token = await _messaging.getToken();
      } else {
        token = await _messaging.getToken();
      }
      if (token == null) return;

      final prefs = await SharedPreferences.getInstance();
      final tenantId = prefs.getString('rms_tenant_id');
      final branchId = prefs.getString('rms_branch_id');
      if (tenantId == null || branchId == null) return;

      String platform = 'web';
      if (!kIsWeb) {
        platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      }

      await SupabaseService.client.from('fcm_tokens').upsert({
        'token': token,
        'tenant_id': tenantId,
        'branch_id': branchId,
        'user_id': SupabaseService.currentUser?.id,
        'platform': platform,
      }, onConflict: 'token');

      dev.log('[FCM] Token saved');
    } catch (e) {
      dev.log('[FCM] Error saving token: $e');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotif.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
    );
  }

  Future<void> deleteToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await SupabaseService.client.from('fcm_tokens').delete().eq('token', token);
      }
      await _messaging.deleteToken();
      dev.log('[FCM] Token deleted');
    } catch (e) {
      dev.log('[FCM] Error deleting token: $e');
    }
  }
}
