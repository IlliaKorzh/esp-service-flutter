// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'esp_notification.dart';

/// What differs between platforms: where the push token comes from, how the
/// notification permission is read and asked, and how pushes reach the app.
/// Sessions, attributes and events stay in [EspPush] and are shared.
abstract interface class EspTransport {
  /// `FCM` or `APNs`, for logs.
  String get tokenName;

  /// Subscribes to pushes. Taps that happened before (the push that launched
  /// the app) go to [onOpened] before this completes.
  Future<void> initialize({
    required void Function(EspNotification notification) onOpened,
    required Future<void> Function(EspNotification notification) onReceived,
    required void Function() onTokenChanged,
  });

  /// Push token of this device, or `null` when it is not available.
  Future<String?> token();

  /// `granted` or `denied`, as ESP expects.
  Future<String> permission();

  /// Asks for the notification permission; returns whether pushes are allowed.
  Future<bool> requestPermission();

  /// Attributes only this platform has, e.g. `apns_environment`.
  Future<Map<String, Object?>> attributes();
}
