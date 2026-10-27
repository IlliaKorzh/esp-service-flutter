// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

/// Android entry of the plugin (`dartPluginClass` in pubspec.yaml). Android
/// needs no native code: FCM and local notifications come from
/// firebase_messaging and flutter_local_notifications, so there is nothing to
/// register.
class EspServiceAndroid {
  EspServiceAndroid._();

  static void registerWith() {}
}
