import 'package:esp_service/esp_service.dart';
import 'package:esp_service/src/esp_apns_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EspNotification.fromApns', () {
    test('ESP keys at the top level, alert with title and body', () {
      final push = EspNotification.fromApns({
        'aps': {
          'alert': {'title': 'Title', 'body': 'Body'},
          'sound': 'default',
        },
        'esp_delivery_id': '184467',
        'esp_campaign_id': 'c-1',
        'url': 'https://example.com/offer',
      }, messageId: 'A1B2');

      expect(push.messageId, 'A1B2');
      expect(push.title, 'Title');
      expect(push.body, 'Body');
      expect(push.data, {'esp_delivery_id': '184467', 'esp_campaign_id': 'c-1', 'url': 'https://example.com/offer'});
      expect(push.deliveryId, '184467');
      expect(push.isTest, isFalse);
      expect(push.url, 'https://example.com/offer');
      expect(push.hasContent, isTrue);
    });

    test('ESP keys inside a nested data dictionary', () {
      final push = EspNotification.fromApns({
        'aps': {'alert': 'Just text'},
        'data': {'esp_delivery_id': '5', 'page': 'home', 'link': 'https://example.com/x'},
      });

      expect(push.title, isNull);
      expect(push.body, 'Just text');
      expect(push.data, {'esp_delivery_id': '5', 'page': 'home', 'link': 'https://example.com/x'});
      expect(push.deliveryId, '5');
      expect(push.url, 'https://example.com/x');
    });

    test('nested data wins over top-level keys of the same name', () {
      final push = EspNotification.fromApns({
        'page': 'top',
        'other': 'kept',
        'data': {'page': 'nested'},
      });

      expect(push.data, {'page': 'nested', 'other': 'kept'});
    });

    test('test push has no delivery id and is marked as a test', () {
      final push = EspNotification.fromApns({
        'aps': {
          'alert': {'title': 'T', 'body': 'B'},
        },
        'esp_test': '1',
      });

      expect(push.isTest, isTrue);
      expect(push.deliveryId, isNull);
    });

    test('values become strings, objects are JSON-encoded', () {
      final push = EspNotification.fromApns({
        'esp_test': 1,
        'count': 3,
        'flag': true,
        'empty': null,
        'list': [1, 'a'],
        'object': {'a': 1},
      });

      expect(push.data, {
        'esp_test': '1',
        'count': '3',
        'flag': 'true',
        'empty': '',
        'list': '[1,"a"]',
        'object': '{"a":1}',
      });
      expect(push.isTest, isTrue);
    });

    test('title and body fall back to data when aps has no alert', () {
      final push = EspNotification.fromApns({
        'aps': {'content-available': 1},
        'title': 'T',
        'message': 'M',
      });

      expect(push.title, 'T');
      expect(push.body, 'M');
      expect(push.data.containsKey('aps'), isFalse);
    });

    test('a non-dictionary data value is kept as is', () {
      final push = EspNotification.fromApns({'data': 'plain', 'esp_campaign_id': 'c'});
      expect(push.data, {'data': 'plain', 'esp_campaign_id': 'c'});
    });

    test('dedup key prefers the delivery id: request identifiers can repeat with apns-collapse-id', () {
      expect(EspNotification.fromApns({'esp_delivery_id': '5'}, messageId: 'collapse-1').dedupKey, '5');
      expect(EspNotification.fromApns({'esp_test': '1'}, messageId: 'id-1').dedupKey, 'id-1');
      expect(EspNotification.fromApns({'esp_test': '1', 'title': 'T'}).dedupKey, 'T||{esp_test: 1, title: T}');
    });

    test('Android dedup key is unchanged: message id first', () {
      expect(const EspNotification(messageId: '0:1', data: {'esp_delivery_id': '5'}).dedupKey, '0:1');
      expect(const EspNotification(data: {'esp_delivery_id': '5'}).dedupKey, '5');
    });
  });

  test('ESP pushes are told apart from other notifications of the app', () {
    expect(EspNotification.isEspApns({'esp_delivery_id': '1'}), isTrue);
    expect(EspNotification.isEspApns({'esp_campaign_id': 'c'}), isTrue);
    expect(EspNotification.isEspApns({'esp_test': '1'}), isTrue);
    expect(
      EspNotification.isEspApns({
        'data': {'esp_delivery_id': '1'},
      }),
      isTrue,
    );

    expect(
      EspNotification.isEspApns({
        'aps': {'alert': 'x'},
        'gcm.message_id': '1',
      }),
      isFalse,
      reason: 'FCM push',
    );
    expect(EspNotification.isEspApns({'NotificationId': 3, 'payload': '{}'}), isFalse, reason: 'local notification');
    expect(EspNotification.isEspApns({'data': 'esp_delivery_id'}), isFalse);
    expect(EspNotification.isEspApns({}), isFalse);
  });

  test('iOS permission maps to ESP permission as on Android', () {
    expect(EspApnsTransport.permissionOf('authorized'), 'granted');
    expect(EspApnsTransport.permissionOf('provisional'), 'granted');
    expect(EspApnsTransport.permissionOf('ephemeral'), 'granted');
    expect(EspApnsTransport.permissionOf('denied'), 'denied');
    expect(EspApnsTransport.permissionOf('notDetermined'), 'denied');
    expect(EspApnsTransport.permissionOf(null), 'denied');
  });

  test('plugin arguments of non-ESP or broken notifications are ignored', () {
    expect(EspApnsTransport.parse(null), isNull);
    expect(EspApnsTransport.parse({'identifier': 'x'}), isNull);
    expect(
      EspApnsTransport.parse({
        'identifier': 'x',
        'userInfo': {'gcm.message_id': '1'},
      }),
      isNull,
    );
    expect(
      EspApnsTransport.parse({
        'identifier': 'x',
        'userInfo': {'esp_delivery_id': '7'},
      })?.deliveryId,
      '7',
    );
  });

  group('method channel', () {
    const channel = MethodChannel('esp_service');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() => calls = []);
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void mockPlugin(Object? Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });
    }

    Future<void> fromPlugin(String method, Object? arguments) async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
    }

    test('taps kept by the plugin before start are delivered, later ones live', () async {
      mockPlugin(
        (call) => switch (call.method) {
          'start' => {
            'taps': [
              {
                'identifier': 'cold',
                'userInfo': {'esp_delivery_id': '1'},
              },
            ],
            'receivesNotifications': true,
            'notificationDelegate': 'Runner.AppDelegate',
          },
          _ => null,
        },
      );
      final opened = <EspNotification>[];
      final received = <EspNotification>[];
      var tokenChanges = 0;
      final warnings = <String>[];
      final transport = EspApnsTransport(log: (_) {}, warn: warnings.add);

      await transport.initialize(
        onOpened: opened.add,
        onReceived: (n) async => received.add(n),
        onTokenChanged: () => tokenChanges++,
      );
      expect(opened.map((n) => n.messageId), ['cold']);
      expect(warnings, isEmpty);

      await fromPlugin('onNotificationOpened', {
        'identifier': 'live',
        'userInfo': {
          'data': {'esp_delivery_id': '2'},
        },
      });
      await fromPlugin('onForegroundNotification', {
        'identifier': 'fg',
        'userInfo': {'esp_delivery_id': '3'},
      });
      await fromPlugin('onToken', 'ab' * 32);

      expect(opened.map((n) => n.deliveryId), ['1', '2']);
      expect(received.single.deliveryId, '3');
      expect(tokenChanges, 1);
    });

    test('warns when another object is the notification center delegate', () async {
      mockPlugin(
        (call) => {
          'taps': const [],
          'receivesNotifications': false,
          'notificationDelegate': 'FLTFirebaseMessagingPlugin',
        },
      );
      final warnings = <String>[];
      final transport = EspApnsTransport(log: (_) {}, warn: warnings.add);

      await transport.initialize(onOpened: (_) {}, onReceived: (_) async {}, onTokenChanged: () {});

      expect(warnings.single, contains('FLTFirebaseMessagingPlugin'));
    });

    test('token, permission and environment come from the plugin', () async {
      mockPlugin(
        (call) => switch (call.method) {
          'getToken' => 'ab' * 32,
          'getPermissionStatus' => 'provisional',
          'requestPermission' => 'denied',
          'getApnsEnvironment' => 'sandbox',
          _ => null,
        },
      );
      final transport = EspApnsTransport(log: (_) {});

      expect(await transport.token(), 'ab' * 32);
      expect(calls.single.arguments, {'timeoutMs': 10000});
      expect(await transport.permission(), 'granted');
      expect(await transport.requestPermission(), isFalse);
      expect(await transport.attributes(), {'apns_environment': 'sandbox'});
    });

    test('no token when APNs registration fails', () async {
      mockPlugin((call) => throw PlatformException(code: 'token_unavailable', message: 'no entitlement'));
      final logs = <String>[];
      final transport = EspApnsTransport(log: logs.add);

      expect(await transport.token(), isNull);
      expect(logs.single, contains('no entitlement'));
      expect(await transport.permission(), 'denied');
      expect(await transport.attributes(), isEmpty);
    });
  });
}
