import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'esp_api.dart';
import 'esp_config.dart';
import 'esp_device.dart';
import 'esp_notification.dart';
import 'esp_notification_display.dart';
import 'esp_storage.dart';

/// Receives a push the user tapped.
typedef EspNotificationHandler = void Function(EspNotification notification);

/// FCM background handler. Registered by [EspPush.initialize]; if the app needs
/// its own handler, pass `registerBackgroundHandler: false` and call
/// [EspPush.handleBackgroundMessage] from it.
@pragma('vm:entry-point')
Future<void> espFirebaseBackgroundHandler(RemoteMessage message) => EspPush.handleBackgroundMessage(message);

/// Client of the ESP push system: registers the FCM token of this device in
/// ESP, shows incoming pushes and reports `delivered` / `clicked` back.
///
/// Android only for now. On other platforms every call is a no-op, so the
/// same code can stay in a cross-platform app.
class EspPush {
  EspPush._();

  /// The client. There is one per app.
  static final EspPush instance = EspPush._();

  /// Sent as `attributes.sdk_version`. Keep in sync with pubspec.yaml.
  static const sdkVersion = '0.1.0';

  /// Whether ESP push works on this platform.
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  EspConfig? _config;
  late EspStorage _storage;
  late EspApi _api;
  late EspNotificationDisplay _display;

  /// ESP subscriber id of this device; `null` until the first successful
  /// registration. Kept between launches.
  final ValueNotifier<String?> subscriberId = ValueNotifier(null);

  EspNotificationHandler? _openedHandler;
  final _pendingOpened = <EspNotification>[];
  final _handledOpened = <String>{};

  Future<void>? _registration;
  bool _registerAgain = false;

  /// Whether [initialize] has completed on a supported platform.
  bool get isInitialized => _config != null;

  /// Call once after `Firebase.initializeApp()`. Registration runs in the
  /// background and does not delay app start.
  Future<void> initialize(EspConfig config, {bool registerBackgroundHandler = true}) async {
    if (_config != null) return;
    if (!isSupported) {
      if (config.debug) debugPrint('[ESP] ${defaultTargetPlatform.name} is not supported yet, ESP push is off');
      return;
    }
    final problem = config.validate();
    if (problem != null) throw ArgumentError('Invalid EspConfig: $problem');
    _config = config;

    _storage = EspStorage(await SharedPreferences.getInstance());
    await _storage.saveConfig(config);
    _api = EspApi(config);
    subscriberId.value = _storage.subscriberId;

    if (registerBackgroundHandler) {
      FirebaseMessaging.onBackgroundMessage(espFirebaseBackgroundHandler);
    }

    _display = EspNotificationDisplay(config);
    await _display.initialize(onTap: _onOpened);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _onOpened(EspNotification.fromRemoteMessage(m)));
    _messaging.onTokenRefresh.listen((_) => register());

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _onOpened(EspNotification.fromRemoteMessage(initialMessage));
    final launchNotification = await _display.launchNotification();
    if (launchNotification != null) _onOpened(launchNotification);

    AppLifecycleListener(onResume: _onResume);

    unawaited(register());
    unawaited(_flushPendingEvents());
  }

  /// Asks for the notification permission (Android 13+ shows the system
  /// dialog) and sends the result to ESP. Returns whether pushes are allowed.
  Future<bool> requestPermission() async {
    if (!isInitialized) return false;
    final settings = await _messaging.requestPermission();
    await register();
    return _isGranted(settings.authorizationStatus);
  }

  /// Receives taps on pushes. Taps that happened before the handler was set
  /// (e.g. the push that cold-started the app) are delivered right away, so
  /// set it once the navigator is ready.
  void setNotificationOpenedHandler(EspNotificationHandler handler) {
    _openedHandler = handler;
    final pending = List.of(_pendingOpened);
    _pendingOpened.clear();
    pending.forEach(handler);
  }

  /// Id of the person in your product. `null` returns to the installation id.
  Future<void> setExternalId(String? externalId) async {
    if (!isInitialized) return;
    await _storage.saveExternalId(externalId);
    await register();
  }

  /// Product tags, sent inside `attributes`. A `null` value removes the tag.
  Future<void> setTags(Map<String, Object?> tags) async {
    if (!isInitialized) return;
    final merged = {..._storage.tags, ...tags}..removeWhere((_, v) => v == null);
    await _storage.saveTags(merged);
    await register();
  }

  /// Sends the current token, permission and attributes to ESP. Called on every
  /// launch, on token rotation and when the permission changes.
  Future<void> register() {
    if (!isInitialized) return Future.value();
    final running = _registration;
    if (running != null) {
      _registerAgain = true;
      return running;
    }
    return _registration = _register().whenComplete(() {
      _registration = null;
      if (_registerAgain) {
        _registerAgain = false;
        unawaited(register());
      }
    });
  }

  Future<void> _register() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _log('FCM token is not available');
        return;
      }
      final permission = await _currentPermission();
      final body = <String, Object?>{
        'device_id': await EspDevice.id() ?? _storage.installationId,
        'token': token,
        'external_id': _storage.externalId,
        'permission': permission,
        'attributes': {...await EspDevice.attributes(), 'sdk_version': sdkVersion, ..._storage.tags},
      };
      _log('register → ${{...body, 'token': '${token.substring(0, 12)}…'}}');

      final subscriber = await _api.registerSubscriber(body);
      await _storage.saveSubscriber(subscriber, permission);
      subscriberId.value = subscriber.id;
      _log('registered: ${subscriber.id} (${subscriber.status})');
    } catch (e) {
      _log('registration failed: $e');
    }
  }

  Future<void> _onResume() async {
    // The user may have toggled notifications in system settings.
    if (await _currentPermission() != _storage.permission) await register();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = EspNotification.fromRemoteMessage(message);
    _log('foreground push: $notification');
    if (notification.hasContent) await _display.show(notification);
    await _track(_api, _storage, notification, EspEventType.delivered);
  }

  void _onOpened(EspNotification notification) {
    if (!_handledOpened.add(notification.dedupKey)) return;
    _log('opened: $notification');
    unawaited(_track(_api, _storage, notification, EspEventType.clicked));

    final handler = _openedHandler;
    if (handler == null) {
      _pendingOpened.add(notification);
    } else {
      handler(notification);
    }
  }

  Future<void> _flushPendingEvents() async {
    await _storage.reload();
    final events = _storage.pendingEvents;
    if (events.isEmpty) return;
    await _storage.savePendingEvents(const []);
    for (final event in events) {
      await _send(_api, _storage, event);
    }
  }

  Future<String> _currentPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return _isGranted(settings.authorizationStatus) ? 'granted' : 'denied';
  }

  void _log(String message) => _logFor(_config, message);

  /// Background isolate: shows `data`-only pushes (FCM shows `notification`
  /// ones itself) and reports `delivered`.
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    if (!isSupported) return;
    final storage = EspStorage(await SharedPreferences.getInstance());
    final config = storage.config;
    if (config == null) return;

    final notification = EspNotification.fromRemoteMessage(message);
    _logFor(config, 'background push: $notification');

    if (message.notification == null && notification.hasContent) {
      final display = EspNotificationDisplay(config);
      await display.initialize();
      await display.show(notification);
    }
    await _track(EspApi(config), storage, notification, EspEventType.delivered);
  }

  static Future<void> _track(EspApi api, EspStorage storage, EspNotification notification, EspEventType type) async {
    final deliveryId = notification.deliveryId;
    if (deliveryId == null || notification.isTest) return;
    await _send(api, storage, EspEvent(deliveryId: deliveryId, type: type));
  }

  /// Sends an event; keeps it for the next launch if the device is offline or
  /// the server is busy. The server ignores repeats of (delivery_id, event).
  static Future<void> _send(EspApi api, EspStorage storage, EspEvent event) async {
    try {
      await api.sendEvent(event);
      _logFor(api.config, 'event ${event.type.name} sent for ${event.deliveryId}');
    } on EspApiException catch (e) {
      _logFor(api.config, 'event ${event.type.name} failed: $e');
      if (e.isRetryable) {
        await storage.reload();
        await storage.savePendingEvents([...storage.pendingEvents, event]);
      }
    }
  }

  static bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;

  static void _logFor(EspConfig? config, String message) {
    if (config?.debug ?? false) debugPrint('[ESP] $message');
  }
}
