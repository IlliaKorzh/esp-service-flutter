// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'package:firebase_messaging/firebase_messaging.dart';

import 'esp_config.dart';
import 'esp_notification.dart';
import 'esp_notification_display.dart';
import 'esp_push.dart';
import 'esp_transport.dart';

/// Android: FCM token and messages, flutter_local_notifications for pushes
/// FCM does not show by itself.
class EspFcmTransport implements EspTransport {
  EspFcmTransport(
    this.config, {
    required this.registerBackgroundHandler,
    required this.handleLocalNotificationTaps,
    required this.log,
  });

  final EspConfig config;
  final bool registerBackgroundHandler;
  final bool handleLocalNotificationTaps;
  final void Function(String message) log;

  late final _display = EspNotificationDisplay(config);

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  String get tokenName => 'FCM';

  @override
  Future<void> initialize({
    required void Function(EspNotification notification) onOpened,
    required Future<void> Function(EspNotification notification) onReceived,
    required void Function() onTokenChanged,
  }) async {
    if (registerBackgroundHandler) {
      FirebaseMessaging.onBackgroundMessage(espFirebaseBackgroundHandler);
    }

    await _display.initialize(onTap: onOpened, initializePlugin: handleLocalNotificationTaps);

    FirebaseMessaging.onMessage.listen((message) async {
      final notification = EspNotification.fromRemoteMessage(message);
      log('foreground push: $notification');
      if (notification.hasContent) await _display.show(notification);
      await onReceived(notification);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpened(EspNotification.fromRemoteMessage(m)));
    _messaging.onTokenRefresh.listen((_) => onTokenChanged());

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) onOpened(EspNotification.fromRemoteMessage(initialMessage));
    if (handleLocalNotificationTaps) {
      final launchNotification = await _display.launchNotification();
      if (launchNotification != null) onOpened(launchNotification);
    }
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Future<String> permission() async {
    final settings = await _messaging.getNotificationSettings();
    return _isGranted(settings.authorizationStatus) ? 'granted' : 'denied';
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return _isGranted(settings.authorizationStatus);
  }

  @override
  Future<Map<String, Object?>> attributes() async => const {};

  static bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
}
