// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'esp_config.dart';
import 'esp_notification.dart';

/// Shows notifications FCM does not show by itself: any push while the app is
/// in the foreground, and `data`-only pushes in the background.
class EspNotificationDisplay {
  EspNotificationDisplay(this.config);

  final EspConfig config;
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize({void Function(EspNotification notification)? onTap}) async {
    await _plugin.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(config.androidNotificationIcon),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) {
              final notification = EspNotification.fromPayload(response.payload);
              if (notification != null) onTap(notification);
            },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            config.androidChannelId,
            config.androidChannelName,
            description: config.androidChannelDescription,
            importance: Importance.high,
          ),
        );
  }

  /// The notification that cold-started the app, if it was one of ours.
  Future<EspNotification?> launchNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return EspNotification.fromPayload(details.notificationResponse?.payload);
  }

  Future<void> show(EspNotification notification) {
    return _plugin.show(
      id: notification.notificationId,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          config.androidChannelId,
          config.androidChannelName,
          channelDescription: config.androidChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(notification.body ?? ''),
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
      payload: notification.toPayload(),
    );
  }
}
