// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'esp_api.dart';
import 'esp_config.dart';

/// Everything the client keeps between launches. All keys are prefixed `esp_`.
class EspStorage {
  EspStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _config = 'esp_config';
  static const _externalId = 'esp_external_id';
  static const _installationId = 'esp_installation_id';
  static const _subscriberId = 'esp_subscriber_id';
  static const _subscriberStatus = 'esp_subscriber_status';
  static const _permission = 'esp_permission';
  static const _tags = 'esp_tags';
  static const _pendingEvents = 'esp_pending_events';
  static const _firstSessionAt = 'esp_first_session_at';
  static const _lastSessionAt = 'esp_last_session_at';
  static const _sessionCount = 'esp_session_count';

  static const _maxPendingEvents = 100;

  /// Picks up writes made by the other isolate (foreground ↔ background).
  Future<void> reload() => _prefs.reload();

  EspConfig? get config {
    final raw = _prefs.getString(_config);
    if (raw == null) return null;
    try {
      return EspConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConfig(EspConfig config) => _prefs.setString(_config, jsonEncode(config.toJson()));

  /// Random id created on first launch; identifies this installation.
  String get installationId {
    final existing = _prefs.getString(_installationId);
    if (existing != null) return existing;
    final id = _uuidV4();
    _prefs.setString(_installationId, id);
    return id;
  }

  /// Id of the recipient in the app's product. Until the app has accounts it is
  /// the [installationId], as the API docs suggest.
  String get externalId => _prefs.getString(_externalId) ?? installationId;

  Future<void> saveExternalId(String? id) =>
      id == null ? _prefs.remove(_externalId) : _prefs.setString(_externalId, id);

  String? get subscriberId => _prefs.getString(_subscriberId);

  String? get subscriberStatus => _prefs.getString(_subscriberStatus);

  /// Last `permission` value the server accepted.
  String? get permission => _prefs.getString(_permission);

  Future<void> saveSubscriber(EspSubscriber subscriber, String permission) async {
    await _prefs.setString(_subscriberId, subscriber.id);
    await _prefs.setString(_subscriberStatus, subscriber.status);
    await _prefs.setString(_permission, permission);
  }

  Map<String, Object?> get tags {
    final raw = _prefs.getString(_tags);
    return raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveTags(Map<String, Object?> tags) => _prefs.setString(_tags, jsonEncode(tags));

  /// Counts a new session. The first one falls back to [installedAt] when it is
  /// earlier, so apps that update to this version keep their real start date.
  Future<void> startSession(DateTime now, {DateTime? installedAt}) async {
    if (_prefs.getString(_firstSessionAt) == null) {
      final first = installedAt != null && installedAt.isBefore(now) ? installedAt : now;
      await _prefs.setString(_firstSessionAt, _timestamp(first));
    }
    await _prefs.setString(_lastSessionAt, _timestamp(now));
    await _prefs.setInt(_sessionCount, sessionCount + 1);
  }

  int get sessionCount => _prefs.getInt(_sessionCount) ?? 0;

  /// `first_session_at`, `last_session_at` and `session_count`
  /// for `attributes`; empty until the first session.
  Map<String, Object?> get sessionAttributes {
    final first = _prefs.getString(_firstSessionAt);
    if (first == null) return {};
    return {
      'first_session_at': first,
      'last_session_at': _prefs.getString(_lastSessionAt),
      'session_count': sessionCount,
    };
  }

  List<EspEvent> get pendingEvents {
    final raw = _prefs.getStringList(_pendingEvents) ?? const [];
    return [for (final item in raw) ?_tryDecodeEvent(item)];
  }

  Future<void> savePendingEvents(List<EspEvent> events) {
    final latest = events.length > _maxPendingEvents ? events.sublist(events.length - _maxPendingEvents) : events;
    return _prefs.setStringList(_pendingEvents, [for (final e in latest) jsonEncode(e.toJson())]);
  }

  static EspEvent? _tryDecodeEvent(String raw) {
    try {
      return EspEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// ISO 8601 in UTC with whole seconds, e.g. `2026-10-16T09:28:21Z`.
  static String _timestamp(DateTime time) => '${time.toUtc().toIso8601String().substring(0, 19)}Z';

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
