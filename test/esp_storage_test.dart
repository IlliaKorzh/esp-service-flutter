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

  test('no session attributes before the first session', () {
    expect(storage.sessionAttributes, isEmpty);
  });

  test('sessions keep the first start, move the last one and count', () async {
    final first = DateTime.utc(2026, 10, 1, 9);
    final second = DateTime.utc(2026, 10, 2, 18, 30);
    await storage.startSession(first);
    await storage.startSession(second);

    expect(storage.sessionAttributes, {
      'first_session_at': '2026-10-01T09:00:00Z',
      'last_session_at': '2026-10-02T18:30:00Z',
      'session_count': 2,
    });
  });

  test('first session falls back to an earlier install time', () async {
    await storage.startSession(DateTime.utc(2026, 10, 16), installedAt: DateTime.utc(2026, 9, 1));
    expect(storage.sessionAttributes['first_session_at'], '2026-09-01T00:00:00Z');
  });

  test('timestamps are UTC with whole seconds', () async {
    await storage.startSession(DateTime.utc(2026, 10, 16, 9, 28, 21, 801, 489));
    expect(storage.sessionAttributes['last_session_at'], '2026-10-16T09:28:21Z');
  });

  test('install time later than now is ignored', () async {
    await storage.startSession(DateTime.utc(2026, 10, 16), installedAt: DateTime.utc(2026, 10, 20));
    expect(storage.sessionAttributes['first_session_at'], '2026-10-16T00:00:00Z');
  });

  test('install time does not change the first session once it is set', () async {
    await storage.startSession(DateTime.utc(2026, 10, 16));
    await storage.startSession(DateTime.utc(2026, 10, 17), installedAt: DateTime.utc(2026, 9, 1));
    expect(storage.sessionAttributes['first_session_at'], '2026-10-16T00:00:00Z');
  });

  test('sdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(EspPush.sdkVersion, version);
  });
}
