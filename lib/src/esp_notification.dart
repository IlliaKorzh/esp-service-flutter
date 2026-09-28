import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

/// A push as the app sees it, whether FCM delivered it as a `notification`
/// or a `data`-only message.
class EspNotification {
  /// Creates a notification; normally built by the package from FCM.
  const EspNotification({this.messageId, this.title, this.body, this.data = const {}});

  /// Reads title, body and data of an FCM message.
  factory EspNotification.fromRemoteMessage(RemoteMessage message) {
    final data = {for (final e in message.data.entries) e.key: e.value?.toString() ?? ''};
    return EspNotification(
      messageId: message.messageId,
      title: message.notification?.title ?? data['title'],
      body: message.notification?.body ?? data['body'] ?? data['message'],
      data: data,
    );
  }

  /// Payload of a notification shown through flutter_local_notifications.
  static EspNotification? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      return EspNotification(
        messageId: json['message_id'] as String?,
        title: json['title'] as String?,
        body: json['body'] as String?,
        data: (json['data'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v.toString())),
      );
    } catch (_) {
      return null;
    }
  }

  /// FCM message id.
  final String? messageId;

  /// Title from `notification.title` or `data.title`.
  final String? title;

  /// Text from `notification.body`, `data.body` or `data.message`.
  final String? body;

  /// FCM `data` of the push, values as strings.
  final Map<String, String> data;

  /// Sent back with `delivered` / `clicked` events. Opaque, do not parse.
  String? get deliveryId {
    final id = data['esp_delivery_id'];
    return id == null || id.isEmpty ? null : id;
  }

  /// Test push from the campaign page: no events are sent for it.
  bool get isTest => data['esp_test'] == '1';

  /// Whether there is a title or a text to show.
  bool get hasContent => (title?.isNotEmpty ?? false) || (body?.isNotEmpty ?? false);

  /// Link to open on tap: one of the known keys first, then any http(s) value.
  String? get url {
    const known = ['url', 'link', 'launch_url', 'deeplink', 'deep_link'];
    const media = ['image', 'icon', 'picture', 'large_icon'];
    for (final key in known) {
      if (_isHttp(data[key])) return data[key]!.trim();
    }
    for (final entry in data.entries) {
      if (!media.contains(entry.key) && _isHttp(entry.value)) return entry.value.trim();
    }
    return null;
  }

  /// Key for de-duplicating the same push reported by several callbacks.
  String get dedupKey => messageId ?? deliveryId ?? '${title ?? ''}|${body ?? ''}|$data';

  /// Id for the local notification that shows this push.
  int get notificationId => dedupKey.hashCode & 0x7fffffff;

  /// Encodes the push for a local notification payload ([fromPayload]).
  String toPayload() => jsonEncode({'message_id': messageId, 'title': title, 'body': body, 'data': data});

  @override
  String toString() => 'EspNotification(id: $messageId, title: $title, body: $body, data: $data)';

  static bool _isHttp(String? value) {
    final v = value?.trim() ?? '';
    return v.startsWith('https://') || v.startsWith('http://');
  }
}
