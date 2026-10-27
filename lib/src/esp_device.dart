// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_udid/flutter_udid.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Device facts sent with every registration.
abstract final class EspDevice {
  /// Stable per-device id: SHA-256 of ANDROID_ID (SSAID) on Android, Keychain on
  /// iOS. Survives app reinstall; not IMEI and not the advertising id.
  static Future<String?> id() async {
    try {
      final udid = await FlutterUdid.udid;
      return udid.isEmpty ? null : udid;
    } catch (_) {
      return null;
    }
  }

  /// When the app was installed on this device (reinstall resets it).
  static Future<DateTime?> installedAt() async {
    try {
      return (await PackageInfo.fromPlatform()).installTime;
    } catch (_) {
      return null;
    }
  }

  /// Recommended `attributes` keys from the API docs (except `sdk_version`).
  static Future<Map<String, Object?>> attributes() async {
    final attributes = <String, Object?>{'language': PlatformDispatcher.instance.locale.languageCode};

    try {
      final package = await PackageInfo.fromPlatform();
      attributes['app_version'] = package.version;
      attributes['app_build'] = package.buildNumber;
    } catch (_) {}

    try {
      if (Platform.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        attributes['os_version'] = android.version.release;
        attributes['device_model'] = android.model;
        attributes['device_manufacturer'] = android.manufacturer;
      } else if (Platform.isIOS) {
        final ios = await DeviceInfoPlugin().iosInfo;
        attributes['os_version'] = ios.systemVersion;
        // `iPhone 16 Pro`; the hardware id (`iPhone17,1`) when the name is unknown.
        attributes['device_model'] = ios.modelName.isNotEmpty ? ios.modelName : ios.utsname.machine;
        attributes['device_manufacturer'] = 'Apple';
      }
    } catch (_) {}

    try {
      // flutter_timezone 4.x returns the IANA id as a String, 5.x a TimezoneInfo.
      final Object zone = await FlutterTimezone.getLocalTimezone();
      attributes['timezone'] = zone is String ? zone : (zone as dynamic).identifier as String;
    } catch (_) {}

    return attributes;
  }
}
