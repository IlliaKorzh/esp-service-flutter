/// Flutter client of ESP (Email & Push Service).
///
/// Push notifications on Android through Firebase Cloud Messaging and on iOS
/// through APNs directly: registers the device in ESP, shows pushes and
/// reports delivery and taps.
library;

export 'src/esp_config.dart';
export 'src/esp_notification.dart';
export 'src/esp_push.dart';
