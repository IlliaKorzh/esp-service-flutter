import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

/// A push as the app sees it: an FCM `notification` or `data`-only message on
/// Android, an APNs notification on iOS.
class EspNotification {
  /// Creates a notification; normally built by the package from FCM or APNs.
  const EspNotification({this.messageId, this.title, this.body, this.data = const {}}) : _fromApns = false;

  const EspNotification._apns({this.messageId, this.title, this.body, required this.data}) : _fromApns = true;

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

  /// Reads an APNs push from the `userInfo` of an iOS notification.
  ///
  /// Title and body come from `aps.alert` (a string is the body), [data] from
  /// every top-level key except `aps`, merged with a nested `data` dictionary
  /// when there is one (its values win). Values are strings; nested objects
  /// are JSON-encoded. [messageId] is the identifier of the notification request.
  factory EspNotification.fromApns(Map<Object?, Object?> userInfo, {String? messageId}) {
    final data = <String, String>{};
    final nested = userInfo['data'];
    for (final entry in userInfo.entries) {
      if (entry.key == 'aps' || (entry.key == 'data' && nested is Map)) continue;
      data['${entry.key}'] = _stringify(entry.value);
    }
    if (nested is Map) {
      for (final entry in nested.entries) {
        data['${entry.key}'] = _stringify(entry.value);
      }
    }

    String? title;
    String? body;
    final aps = userInfo['aps'];
    final alert = aps is Map ? aps['alert'] : null;
    if (alert is String) {
      body = alert;
    } else if (alert is Map) {
      title = alert['title']?.toString();
      body = alert['body']?.toString();
    }
    return EspNotification._apns(
      messageId: messageId,
      title: title ?? data['title'],
      body: body ?? data['body'] ?? data['message'],
      data: data,
    );
  }

  /// Whether an APNs `userInfo` belongs to an ESP push: `esp_delivery_id`,
  /// `esp_campaign_id` or `esp_test` at the top level or inside `data`.
  static bool isEspApns(Map<Object?, Object?> userInfo) {
    const keys = ['esp_delivery_id', 'esp_campaign_id', 'esp_test'];
    final nested = userInfo['data'];
    return keys.any(userInfo.containsKey) || (nested is Map && keys.any(nested.containsKey));
  }

  /// Payload of a notification shown through flutter_local_notifications, or
  /// `null` when the payload belongs to another notification of the app.
  static EspNotification? fromPayload(String? payload) {
    final json = _decodeEspPayload(payload);
    if (json == null) return null;
    return EspNotification(
      messageId: json['message_id'] as String?,
      title: json['title'] as String?,
      body: json['body'] as String?,
      data: (json['data'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v.toString())),
    );
  }

  /// Whether a flutter_local_notifications payload was created by ESP.
  ///
  /// Apps that show their own local notifications use it to tell ESP taps
  /// apart from theirs (see [EspPush.handleLocalNotificationTap]).
  static bool isEspPayload(String? payload) => _decodeEspPayload(payload) != null;

  static Map<String, dynamic>? _decodeEspPayload(String? payload) {
    if (payload == null || !payload.startsWith('{')) return null;
    try {
      final json = jsonDecode(payload);
      if (json is! Map<String, dynamic>) return null;
      // `esp` marks payloads since 0.2.0; 0.1.0 payloads have message_id + data.
      final isEsp = json['esp'] == 1 || (json.containsKey('message_id') && json['data'] is Map);
      return isEsp ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// FCM message id on Android, notification request identifier on iOS.
  final String? messageId;

  /// Title from `notification.title` (`aps.alert.title` on iOS) or `data.title`.
  final String? title;

  /// Text from `notification.body` (`aps.alert` on iOS), `data.body` or `data.message`.
  final String? body;

  /// APNs request identifiers can repeat (`apns-collapse-id`), so iOS pushes
  /// are de-duplicated by delivery id first.
  final bool _fromApns;

  /// Custom data of the push (FCM `data`, or APNs keys besides `aps`), values as strings.
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
  String get dedupKey => _fromApns ? deliveryId ?? messageId ?? _contentKey : messageId ?? deliveryId ?? _contentKey;

  String get _contentKey => '${title ?? ''}|${body ?? ''}|$data';

  /// Id for the local notification that shows this push.
  int get notificationId => dedupKey.hashCode & 0x7fffffff;

  /// Encodes the push for a local notification payload ([fromPayload]).
  String toPayload() => jsonEncode({'esp': 1, 'message_id': messageId, 'title': title, 'body': body, 'data': data});

  @override
  String toString() => 'EspNotification(id: $messageId, title: $title, body: $body, data: $data)';

  static String _stringify(Object? value) => switch (value) {
    null => '',
    String() => value,
    Map() || List() => jsonEncode(value),
    _ => value.toString(),
  };

  static bool _isHttp(String? value) {
    final v = value?.trim() ?? '';
    return v.startsWith('https://') || v.startsWith('http://');
  }
}
