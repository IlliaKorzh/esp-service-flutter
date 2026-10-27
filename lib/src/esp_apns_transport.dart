// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'package:flutter/services.dart';

import 'esp_notification.dart';
import 'esp_transport.dart';

/// iOS: APNs token, permission and taps through the plugin's own method
/// channel (ios/esp_service). Does not touch firebase_messaging or
/// flutter_local_notifications: iOS shows ESP pushes by itself.
class EspApnsTransport implements EspTransport {
  EspApnsTransport({required this.log, void Function(String message)? warn, MethodChannel? channel})
    : warn = warn ?? log,
      _channel = channel ?? const MethodChannel('esp_service');

  /// How long to wait for `didRegisterForRemoteNotificationsWithDeviceToken`.
  static const tokenTimeout = Duration(seconds: 10);

  final void Function(String message) log;

  /// Setup problems, shown in debug builds even without `EspConfig.debug`.
  final void Function(String message) warn;

  final MethodChannel _channel;
  String? _environment;

  @override
  String get tokenName => 'APNs';

  @override
  Future<void> initialize({
    required void Function(EspNotification notification) onOpened,
    required Future<void> Function(EspNotification notification) onReceived,
    required void Function() onTokenChanged,
  }) async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onToken':
          onTokenChanged();
        case 'onNotificationOpened':
          final notification = parse(call.arguments);
          if (notification != null) onOpened(notification);
        case 'onForegroundNotification':
          final notification = parse(call.arguments);
          if (notification == null) return;
          log('foreground push: $notification');
          await onReceived(notification);
      }
    });

    try {
      // Turns the plugin on, switches it to live taps and returns the ones that came earlier.
      final started = await _channel.invokeMapMethod<String, Object?>('start') ?? const {};
      if (started['receivesNotifications'] == false) {
        warn(
          'UNUserNotificationCenter.delegate is ${started['notificationDelegate']}, not the FlutterAppDelegate, '
          'so taps on ESP pushes do not reach esp_service (no clicked events, no opened handler). '
          'Set UNUserNotificationCenter.current().delegate = self in AppDelegate (see README, iOS setup).',
        );
      }
      for (final item in started['taps'] as List? ?? const []) {
        final notification = parse(item);
        if (notification != null) onOpened(notification);
      }
    } on Exception catch (e) {
      warn('the iOS part of esp_service is not available ($e); run pod install and rebuild the app');
    }
  }

  @override
  Future<String?> token() async {
    try {
      return await _channel.invokeMethod<String>('getToken', {'timeoutMs': tokenTimeout.inMilliseconds});
    } on PlatformException catch (e) {
      log('APNs token: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String> permission() async {
    try {
      return permissionOf(await _channel.invokeMethod<String>('getPermissionStatus'));
    } on Exception {
      return 'denied';
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return permissionOf(await _channel.invokeMethod<String>('requestPermission')) == 'granted';
    } on Exception {
      return false;
    }
  }

  @override
  Future<Map<String, Object?>> attributes() async {
    try {
      _environment ??= await _channel.invokeMethod<String>('getApnsEnvironment');
    } on Exception {
      // Left out until the next registration.
    }
    return {'apns_environment': ?_environment};
  }

  /// ESP is off on iOS: the plugin forgets an earlier opt-in and stays passive
  /// on later launches. Nothing else happens (no permission, no token).
  static Future<void> disable({MethodChannel channel = const MethodChannel('esp_service')}) async {
    try {
      await channel.invokeMethod<void>('disable');
    } on Exception {
      // No plugin (e.g. pods not installed): nothing to forget.
    }
  }

  /// `UNAuthorizationStatus` name → ESP `permission`, as on Android:
  /// provisional (quiet) and ephemeral (App Clip) delivery count as allowed.
  static String permissionOf(String? status) =>
      const {'authorized', 'provisional', 'ephemeral'}.contains(status) ? 'granted' : 'denied';

  /// `{identifier, userInfo}` from the plugin, or `null` when it is not an ESP push.
  static EspNotification? parse(Object? arguments) {
    if (arguments is! Map) return null;
    final userInfo = arguments['userInfo'];
    if (userInfo is! Map || !EspNotification.isEspApns(userInfo)) return null;
    return EspNotification.fromApns(userInfo, messageId: arguments['identifier'] as String?);
  }
}
