import 'dart:convert';

import 'package:esp_service/esp_service.dart';
import 'package:esp_service/src/esp_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const config = EspConfig(publicKey: 'pk_test_123', baseUrl: 'https://esp.example.com/');

  test('registerSubscriber posts JSON with the application key', () async {
    late http.Request sent;
    final api = EspApi(
      config,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'data': {'id': 'sub-1', 'status': 'active'},
          }),
          201,
        );
      }),
    );

    final subscriber = await api.registerSubscriber({'token': 'abc'});

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://esp.example.com/api/public/v1/subscribers');
    expect(sent.headers['X-Application-Key'], 'pk_test_123');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'token': 'abc'});
    expect(subscriber.id, 'sub-1');
    expect(subscriber.status, 'active');
  });

  test('sendEvent posts delivery id, event and UTC time', () async {
    late http.Request sent;
    final api = EspApi(
      config,
      client: MockClient((request) async {
        sent = request;
        return http.Response('', 202);
      }),
    );

    await api.sendEvent(
      EspEvent(deliveryId: '184467', type: EspEventType.clicked, occurredAt: DateTime.utc(2026, 9, 23, 10, 34, 50)),
    );

    expect(sent.url.path, '/api/public/v1/events');
    expect(jsonDecode(sent.body), {
      'delivery_id': '184467',
      'event': 'clicked',
      'occurred_at': '2026-09-23T10:34:50.000Z',
    });
  });

  test('API errors carry code, message and Retry-After', () async {
    final api = EspApi(
      config,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'too_many_attempts', 'message': 'Too many attempts'},
          }),
          429,
          headers: {'retry-after': '30'},
        ),
      ),
    );

    await expectLater(
      api.registerSubscriber({'token': 'abc'}),
      throwsA(
        isA<EspApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.code, 'code', 'too_many_attempts')
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))
            .having((e) => e.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });

  test('validation errors are not retried', () async {
    final api = EspApi(
      config,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'validation_error', 'message': 'The token field is required.'},
          }),
          422,
        ),
      ),
    );

    await expectLater(
      api.registerSubscriber({}),
      throwsA(isA<EspApiException>().having((e) => e.isRetryable, 'isRetryable', isFalse)),
    );
  });

  test('network failures are retried', () async {
    final api = EspApi(config, client: MockClient((_) async => throw http.ClientException('offline')));

    await expectLater(
      api.sendEvent(EspEvent(deliveryId: '1', type: EspEventType.delivered)),
      throwsA(
        isA<EspApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });
}
