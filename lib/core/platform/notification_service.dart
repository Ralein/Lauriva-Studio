import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service managing native operating-system notifications across Android and iOS.
///
/// Dispatches real-time task progress, completion, and failure alerts with
/// dedicated notification channels, ongoing progress bars, and permission guards.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  ValueChanged<String?>? _onSelectNotification;

  static const String channelIdProgress = 'lauriva_background_progress';
  static const String channelNameProgress = 'Lauriva Background Activity';
  static const String channelDescProgress =
      'Real-time progress updates for ongoing forensic analysis and transformations.';

  static const String channelIdCompletion = 'lauriva_task_completion';
  static const String channelNameCompletion = 'Lauriva Task Results';
  static const String channelDescCompletion =
      'Alerts when forensic analysis and reports have completed or finished.';

  bool get isInitialized => _isInitialized;

  /// Initializes the notification plugin with platform configurations.
  Future<void> initialize({ValueChanged<String?>? onSelectNotification}) async {
    if (_isInitialized) return;
    _onSelectNotification = onSelectNotification;

    if (kIsWeb) return;

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      final darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      final linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open Lauriva',
      );

      final initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _onSelectNotification?.call(response.payload);
        },
      );

      // Create Android Notification Channels
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImpl != null) {
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              channelIdProgress,
              channelNameProgress,
              description: channelDescProgress,
              importance: Importance.low,
              playSound: false,
              enableVibration: false,
              showBadge: false,
            ),
          );

          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              channelIdCompletion,
              channelNameCompletion,
              description: channelDescCompletion,
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
              showBadge: true,
            ),
          );
        }
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('[NotificationService] Initialization error: $e');
    }
  }

  /// Checks if notification permissions have been granted on the current platform.
  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await androidImpl?.areNotificationsEnabled();
        return granted ?? false;
      } else if (Platform.isIOS || Platform.isMacOS) {
        // Darwin permission check
        return true;
      }
    } catch (_) {}
    return true;
  }

  /// Requests notification permissions on Android 13+ and iOS.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await androidImpl?.requestNotificationsPermission();
        return granted ?? false;
      } else if (Platform.isIOS) {
        final iosImpl = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted = await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error requesting permission: $e');
    }
    return false;
  }

  /// Displays or updates an ongoing background task progress notification.
  Future<void> showTaskProgress({
    required String id,
    required String title,
    required String message,
    required double progress,
  }) async {
    if (!_isInitialized) return;

    final notifId = id.hashCode & 0x7FFFFFFF;
    final int progressPercent = (progress * 100).clamp(0, 100).toInt();

    final androidDetails = AndroidNotificationDetails(
      channelIdProgress,
      channelNameProgress,
      channelDescription: channelDescProgress,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent,
      indeterminate: progress <= 0.0,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: false,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _plugin.show(
        id: notifId,
        title: title,
        body: message,
        notificationDetails: notificationDetails,
        payload: 'background_activity',
      );
    } catch (e) {
      debugPrint('[NotificationService] showTaskProgress error: $e');
    }
  }

  /// Replaces the ongoing notification with a high-priority completion alert.
  Future<void> showTaskCompleted({
    required String id,
    required String title,
    required String message,
    String? payload,
  }) async {
    if (!_isInitialized) return;

    final notifId = id.hashCode & 0x7FFFFFFF;

    final androidDetails = const AndroidNotificationDetails(
      channelIdCompletion,
      channelNameCompletion,
      channelDescription: channelDescCompletion,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
      presentBadge: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _plugin.cancel(id: notifId);
      await _plugin.show(
        id: notifId,
        title: title,
        body: message,
        notificationDetails: notificationDetails,
        payload: payload ?? 'background_activity',
      );
    } catch (e) {
      debugPrint('[NotificationService] showTaskCompleted error: $e');
    }
  }

  /// Replaces the ongoing notification with a failure alert.
  Future<void> showTaskFailed({
    required String id,
    required String title,
    required String message,
    String? payload,
  }) async {
    if (!_isInitialized) return;

    final notifId = id.hashCode & 0x7FFFFFFF;

    final androidDetails = const AndroidNotificationDetails(
      channelIdCompletion,
      channelNameCompletion,
      channelDescription: channelDescCompletion,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
      presentBadge: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _plugin.cancel(id: notifId);
      await _plugin.show(
        id: notifId,
        title: title,
        body: message,
        notificationDetails: notificationDetails,
        payload: payload ?? 'background_activity',
      );
    } catch (e) {
      debugPrint('[NotificationService] showTaskFailed error: $e');
    }
  }

  /// Cancels an active notification associated with a task ID.
  Future<void> cancelTaskNotification(String id) async {
    if (!_isInitialized) return;
    final notifId = id.hashCode & 0x7FFFFFFF;
    try {
      await _plugin.cancel(id: notifId);
    } catch (_) {}
  }

  /// Dismisses all notifications.
  Future<void> cancelAll() async {
    if (!_isInitialized) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
