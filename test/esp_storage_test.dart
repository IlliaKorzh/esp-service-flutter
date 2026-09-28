import 'dart:io';

import 'package:esp_service/esp_service.dart';
import 'package:esp_service/src/esp_api.dart';
import 'package:esp_service/src/esp_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late EspStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = EspStorage(await SharedPreferences.getInstance());
  });

  test('installation id is a stable UUID v4 and is the default external id', () {
    final id = storage.installationId;
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(storage.installationId, id);
    expect(storage.externalId, id);
  });

  test('external id can be set and reset', () async {
    await storage.saveExternalId('user-42');
    expect(storage.externalId, 'user-42');
    await storage.saveExternalId(null);
    expect(storage.externalId, storage.installationId);
  });

  test('subscriber and permission are kept', () async {
    await storage.saveSubscriber(const EspSubscriber(id: 'sub-1', status: 'active'), 'granted');
    expect(storage.subscriberId, 'sub-1');
    expect(storage.subscriberStatus, 'active');
    expect(storage.permission, 'granted');
  });

  test('config is kept for the background isolate', () async {
    await storage.saveConfig(const EspConfig(publicKey: 'pk_test_123', baseUrl: 'https://esp.example.com'));
    expect(storage.config?.publicKey, 'pk_test_123');
  });

  test('pending events keep only the latest 100', () async {
    await storage.savePendingEvents([
      for (var i = 0; i < 120; i++) EspEvent(deliveryId: '$i', type: EspEventType.delivered),
    ]);
    final events = storage.pendingEvents;
    expect(events, hasLength(100));
    expect(events.first.deliveryId, '20');
    expect(events.last.deliveryId, '119');
  });

  test('sdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(EspPush.sdkVersion, version);
  });
}
