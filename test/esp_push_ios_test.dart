import 'package:esp_service/esp_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Apps that call `initialize` with their Android key on every platform must
/// keep working on iOS exactly as with 0.3.0 until they pass `iosPublicKey`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('esp_service');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('without iosPublicKey everything is a no-op on iOS', () async {
    expect(EspPush.isSupported, isTrue);

    await EspPush.instance.initialize(
      const EspConfig(publicKey: 'pk_live_android', baseUrl: 'https://esp.example.com', debug: true),
    );
    expect(EspPush.instance.isInitialized, isFalse);

    expect(await EspPush.instance.requestPermission(), isFalse);
    await EspPush.instance.register();
    await EspPush.instance.setExternalId('user-42');
    await EspPush.instance.setTags({'plan': 'pro'});
    expect(EspPush.instance.handleLocalNotificationTap('{"esp":1,"data":{}}'), isFalse);
    expect(EspPush.instance.subscriberId.value, isNull);

    expect(calls.map((c) => c.method), [
      'disable',
    ], reason: 'only forgets an earlier opt-in: no permission dialog, no token, no plugin start');
  });

  test('an empty iosPublicKey does not throw either', () async {
    await EspPush.instance.initialize(const EspConfig(publicKey: '', baseUrl: 'not a url', iosPublicKey: ' '));
    expect(EspPush.instance.isInitialized, isFalse);
    expect(calls.map((c) => c.method), ['disable']);
  });

  test('handleBackgroundMessage does nothing on iOS', () async {
    await EspPush.handleBackgroundMessage(const RemoteMessage(data: {'esp_delivery_id': '1'}));
    expect(calls, isEmpty);
  });

  test('without the native plugin the no-op path does not throw', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await EspPush.instance.initialize(
      const EspConfig(publicKey: 'pk_live_android', baseUrl: 'https://esp.example.com'),
    );
    expect(EspPush.instance.isInitialized, isFalse);
  });
}
