import 'package:esp_service/esp_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification message: title and body from notification, ESP ids from data', () {
    final push = EspNotification.fromRemoteMessage(
      const RemoteMessage(
        messageId: '0:1',
        notification: RemoteNotification(title: 'Title', body: 'Body'),
        data: {'esp_campaign_id': 'c-1', 'esp_delivery_id': '9'},
      ),
    );

    expect(push.title, 'Title');
    expect(push.body, 'Body');
    expect(push.deliveryId, '9');
    expect(push.isTest, isFalse);
    expect(push.hasContent, isTrue);
  });

  test('data-only message: title and body from data', () {
    final push = EspNotification.fromRemoteMessage(
      const RemoteMessage(data: {'title': 'T', 'message': 'M', 'esp_test': '1'}),
    );

    expect(push.title, 'T');
    expect(push.body, 'M');
    expect(push.deliveryId, isNull);
    expect(push.isTest, isTrue);
  });

  test('url prefers known keys and skips media', () {
    expect(
      const EspNotification(data: {'image': 'https://cdn.example.com/a.png', 'url': 'https://example.com/offer'}).url,
      'https://example.com/offer',
    );
    expect(const EspNotification(data: {'image': 'https://cdn.example.com/a.png'}).url, isNull);
    expect(const EspNotification(data: {'custom': ' https://example.com/x '}).url, 'https://example.com/x');
    expect(const EspNotification(data: {'page': 'home'}).url, isNull);
  });

  test('payload round trip keeps everything', () {
    const push = EspNotification(messageId: '0:1', title: 'T', body: 'B', data: {'esp_delivery_id': '5', 'page': 'x'});

    final restored = EspNotification.fromPayload(push.toPayload())!;

    expect(restored.messageId, push.messageId);
    expect(restored.title, push.title);
    expect(restored.body, push.body);
    expect(restored.data, push.data);
    expect(restored.dedupKey, push.dedupKey);
  });

  test('broken payload is ignored', () {
    expect(EspNotification.fromPayload(null), isNull);
    expect(EspNotification.fromPayload('not json'), isNull);
  });

  test('ESP payloads are told apart from other local notifications of the app', () {
    const push = EspNotification(messageId: '0:1', data: {'esp_delivery_id': '5'});

    expect(EspNotification.isEspPayload(push.toPayload()), isTrue);
    expect(EspNotification.isEspPayload('{"message_id":"0:1","data":{}}'), isTrue, reason: '0.1.0 payload');
    expect(EspNotification.isEspPayload('external_url::https://example.com'), isFalse);
    expect(EspNotification.isEspPayload('webview'), isFalse);
    expect(EspNotification.isEspPayload('{"url":"https://example.com"}'), isFalse);
    expect(EspNotification.isEspPayload('[1,2]'), isFalse);
    expect(EspNotification.fromPayload('{"url":"https://example.com"}'), isNull);
  });
}
