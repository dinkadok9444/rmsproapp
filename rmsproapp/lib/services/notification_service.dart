import 'dart:developer' as dev;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background message handler — mesti top-level function
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
  final _db = FirebaseFirestore.instance;

  static const _channelId = 'rms_pro_booking';
  static const _channelName = 'Booking Notifications';
  static const _channelDesc = 'Notifikasi booking baru dari customer';

  Future<void> initialize() async {
    // Request permission (iOS & Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    dev.log('[FCM] Permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    if (!kIsWeb) {
      // Setup local notifications (for foreground display) — mobile only
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _localNotif.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      // Create Android notification channel
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

    // Listen foreground messages
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // Save FCM token for this branch
    await _saveToken();

    // Listen token refresh
    _messaging.onTokenRefresh.listen((_) => _saveToken());
  }

  Future<void> _saveToken() async {
    try {
      String? token;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS: get APNs token first, then FCM token
        await _messaging.getAPNSToken();
        token = await _messaging.getToken();
      } else if (kIsWeb) {
        // Web: need VAPID key for FCM token
        token = await _messaging.getToken();
      } else {
        token = await _messaging.getToken();
      }

      if (token == null) return;

      final prefs = await SharedPreferences.getInstance();
      final branch = prefs.getString('rms_current_branch') ?? '';
      if (branch.isEmpty) return;

      final ownerID = branch.split('@')[0];
      final shopID = branch.split('@')[1].toUpperCase();

      String platform = 'web';
      if (!kIsWeb) {
        platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      }

      // Save token with branch info
      await _db.collection('fcm_tokens').doc(token).set({
        'token': token,
        'ownerID': ownerID,
        'shopID': shopID,
        'branchID': '$ownerID@$shopID',
        'platform': platform,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      dev.log('[FCM] Token saved for branch: $ownerID@$shopID');
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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Delete token on logout
  Future<void> deleteToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _db.collection('fcm_tokens').doc(token).delete();
      }
      await _messaging.deleteToken();
      dev.log('[FCM] Token deleted');
    } catch (e) {
      dev.log('[FCM] Error deleting token: $e');
    }
  }
}
