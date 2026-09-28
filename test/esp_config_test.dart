import 'package:esp_service/esp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const valid = EspConfig(publicKey: 'pk_test_123', baseUrl: 'https://esp.example.com/');

  test('valid config passes validation', () {
    expect(valid.validate(), isNull);
  });

  test('empty key is rejected', () {
    expect(const EspConfig(publicKey: ' ', baseUrl: 'https://esp.example.com').validate(), contains('publicKey'));
  });

  test('http is rejected for remote hosts and allowed for localhost', () {
    expect(const EspConfig(publicKey: 'k', baseUrl: 'http://esp.example.com').validate(), contains('https'));
    expect(const EspConfig(publicKey: 'k', baseUrl: 'http://10.0.2.2:8080').validate(), isNull);
    expect(const EspConfig(publicKey: 'k', baseUrl: 'esp.example.com').validate(), contains('absolute'));
  });

  test('trailing slash is dropped from baseUrl', () {
    expect(valid.normalizedBaseUrl, 'https://esp.example.com');
  });

  test('survives a JSON round trip for the background isolate', () {
    const config = EspConfig(
      publicKey: 'pk_test_123',
      baseUrl: 'https://esp.example.com',
      androidChannelId: 'app_notifications',
      androidChannelName: 'App Notifications',
      androidNotificationIcon: '@drawable/ic_notification',
      debug: true,
      requestTimeout: Duration(seconds: 5),
    );
    final restored = EspConfig.fromJson(config.toJson());
    expect(restored.toJson(), config.toJson());
  });
}
