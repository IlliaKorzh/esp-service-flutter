// Internal: not exported from package:esp_service.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'esp_config.dart';

/// Thin client for the ESP Public API (`/api/public/v1`).
class EspApi {
  EspApi(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final EspConfig config;
  final http.Client _client;

  /// `POST /subscribers` — upsert of this device's push token.
  Future<EspSubscriber> registerSubscriber(Map<String, Object?> body) async {
    final json = await _post('/api/public/v1/subscribers', body);
    final data = (json as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return EspSubscriber(id: data['id'] as String, status: data['status'] as String);
  }

  /// `POST /events` — `delivered` / `clicked` for a push.
  Future<void> sendEvent(EspEvent event) async {
    await _post('/api/public/v1/events', event.toJson());
  }

  Future<Object?> _post(String path, Map<String, Object?> body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${config.normalizedBaseUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Application-Key': config.publicKey,
            },
            body: jsonEncode(body),
          )
          .timeout(config.requestTimeout);
    } on Exception catch (e) {
      throw EspApiException(message: e.toString());
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }
    throw EspApiException.fromResponse(response);
  }
}

class EspSubscriber {
  const EspSubscriber({required this.id, required this.status});

  final String id;

  /// `active`, `invalid` or `unsubscribed`.
  final String status;
}

enum EspEventType { delivered, clicked }

class EspEvent {
  EspEvent({required this.deliveryId, required this.type, DateTime? occurredAt})
    : occurredAt = (occurredAt ?? DateTime.now()).toUtc();

  final String deliveryId;
  final EspEventType type;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => {
    'delivery_id': deliveryId,
    'event': type.name,
    'occurred_at': occurredAt.toIso8601String(),
  };

  factory EspEvent.fromJson(Map<String, dynamic> json) => EspEvent(
    deliveryId: json['delivery_id'] as String,
    type: EspEventType.values.byName(json['event'] as String),
    occurredAt: DateTime.parse(json['occurred_at'] as String),
  );
}

class EspApiException implements Exception {
  const EspApiException({this.statusCode, this.code, required this.message, this.retryAfter});

  factory EspApiException.fromResponse(http.Response response) {
    String? code;
    var message = response.body;
    try {
      final error = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as Map<String, dynamic>;
      code = error['code'] as String?;
      message = error['message'] as String? ?? message;
    } catch (_) {}
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    return EspApiException(
      statusCode: response.statusCode,
      code: code,
      message: message,
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
    );
  }

  /// `null` when the request did not reach the server (offline, timeout).
  final int? statusCode;
  final String? code;
  final String message;
  final Duration? retryAfter;

  /// Worth sending again later: network error, rate limit or server error.
  bool get isRetryable => statusCode == null || statusCode == 429 || statusCode! >= 500;

  @override
  String toString() => 'EspApiException($statusCode ${code ?? ''}): $message';
}
