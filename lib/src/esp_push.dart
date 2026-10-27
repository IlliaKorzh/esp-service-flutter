import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'esp_api.dart';
import 'esp_apns_transport.dart';
import 'esp_config.dart';
import 'esp_device.dart';
import 'esp_fcm_transport.dart';
import 'esp_notification.dart';
import 'esp_notification_display.dart';
import 'esp_storage.dart';
import 'esp_transport.dart';

/// Receives a push the user tapped.
typedef EspNotificationHandler = void Function(EspNotification notification);

/// FCM background handler (Android). Registered by [EspPush.initialize]; if the
/// app needs its own handler, pass `registerBackgroundHandler: false` and call
/// [EspPush.handleBackgroundMessage] from it.
@pragma('vm:entry-point')
Future<void> espFirebaseBackgroundHandler(RemoteMessage message) => EspPush.handleBackgroundMessage(message);

/// Client of the ESP push system: registers the push token of this device in
/// ESP (FCM on Android, APNs on iOS), shows incoming pushes and reports
/// `delivered` / `clicked` back.
///
/// Android and iOS. On iOS ESP is off (every call is a no-op) until
/// [EspConfig.iosPublicKey] is set; on other platforms every call is a no-op,
/// so the same code can stay in a cross-platform app.
class EspPush {
  EspPush._();

  /// The client. There is one per app.
  static final EspPush instance = EspPush._();

  /// Sent as `attributes.sdk_version`. Keep in sync with pubspec.yaml.
  static const sdkVersion = '0.4.0';

  /// Back from the background after at least this long counts as a new session.
  static const sessionTimeout = Duration(seconds: 30);

  /// Whether ESP push works on this platform.
  static bool get isSupported => _isAndroid || (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  EspConfig? _config;
  late EspStorage _storage;
  late EspApi _api;
  late EspTransport _transport;

  /// ESP subscriber id of this device; `null` until the first successful
  /// registration. Kept between launches.
  final ValueNotifier<String?> subscriberId = ValueNotifier(null);

  EspNotificationHandler? _openedHandler;
  final _pendingOpened = <EspNotification>[];
  final _handledOpened = <String>{};

  Future<void>? _registration;
  bool _registerAgain = false;
  DateTime? _pausedAt;

  /// Whether [initialize] has completed on a supported platform (on iOS: with
  /// an [EspConfig.iosPublicKey]).
  bool get isInitialized => _config != null;

  /// Call once at startup (on Android after `Firebase.initializeApp()`).
  /// Registration runs in the background and does not delay app start.
  ///
  /// Android only: flutter_local_notifications has one tap callback per app,
  /// and the last `initialize` call wins. If the app shows its own local
  /// notifications (reminders, scheduled pushes), pass
  /// `handleLocalNotificationTaps: false`, initialize the plugin in the app and
  /// forward taps with [handleLocalNotificationTap]. On iOS ESP uses neither
  /// firebase_messaging nor flutter_local_notifications, and both flags are
  /// ignored.
  ///
  /// On iOS this is a no-op without [EspConfig.iosPublicKey]: ESP keys are per
  /// platform, and the Android [EspConfig.publicKey] is never sent from iOS.
  Future<void> initialize(
    EspConfig config, {
    bool registerBackgroundHandler = true,
    bool handleLocalNotificationTaps = true,
  }) async {
    if (_config != null) return;
    if (!isSupported) {
      if (config.debug) debugPrint('[ESP] ${defaultTargetPlatform.name} is not supported yet, ESP push is off');
      return;
    }
    final applicationKey = _isAndroid ? config.publicKey : config.iosPublicKey;
    if (!_isAndroid && (applicationKey?.trim().isEmpty ?? true)) {
      if (config.debug) debugPrint('[ESP] EspConfig.iosPublicKey is not set, ESP push is off on iOS');
      // Forgets an earlier opt-in, so the plugin leaves the notification center alone again.
      unawaited(EspApnsTransport.disable());
      return;
    }
    final problem = _isAndroid ? config.validate() : config.validateIos();
    if (problem != null) throw ArgumentError('Invalid EspConfig: $problem');
    _config = config;

    _storage = EspStorage(await SharedPreferences.getInstance());
    await _storage.saveConfig(config);
    _api = EspApi(config, applicationKey: applicationKey);
    subscriberId.value = _storage.subscriberId;
    final firstLaunch = _storage.sessionCount == 0;
    await _storage.startSession(DateTime.now(), installedAt: firstLaunch ? await EspDevice.installedAt() : null);

    _transport = _isAndroid
        ? EspFcmTransport(
            config,
            registerBackgroundHandler: registerBackgroundHandler,
            handleLocalNotificationTaps: handleLocalNotificationTaps,
            log: _log,
          )
        : EspApnsTransport(log: _log, warn: (message) => _warn(config, message));
    await _transport.initialize(onOpened: _onOpened, onReceived: _onReceived, onTokenChanged: () => register());

    AppLifecycleListener(onPause: () => _pausedAt = DateTime.now(), onResume: _onResume);

    unawaited(register());
    unawaited(_flushPendingEvents());
  }

  /// Asks for the notification permission (Android 13+ and iOS show the system
  /// dialog) and sends the result to ESP. Returns whether pushes are allowed.
  Future<bool> requestPermission() async {
    if (!isInitialized) return false;
    final granted = await _transport.requestPermission();
    await register();
    return granted;
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

  /// Handles a tap on a local notification shown by ESP (a push that arrived
  /// while the app was open). Returns `false` when [payload] belongs to another
  /// notification of the app, which the app then handles as before.
  ///
  /// Needed only on Android with `handleLocalNotificationTaps: false`: call it
  /// first in the app's `onDidReceiveNotificationResponse` and with the payload
  /// of `getNotificationAppLaunchDetails()`. ESP shows no local notifications on
  /// iOS, so there it returns `false` for every payload of the app.
  bool handleLocalNotificationTap(String? payload) {
    if (!isInitialized) return false;
    final notification = EspNotification.fromPayload(payload);
    if (notification == null) return false;
    _onOpened(notification);
    return true;
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
  /// session start, on token rotation and when the permission changes.
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
      final token = await _transport.token();
      if (token == null) {
        _log('${_transport.tokenName} token is not available');
        return;
      }
      final permission = await _transport.permission();
      final body = <String, Object?>{
        'device_id': await EspDevice.id() ?? _storage.installationId,
        'token': token,
        'external_id': _storage.externalId,
        'permission': permission,
        // Built-in keys win over tags of the same name: segments rely on them.
        'attributes': {
          ..._storage.tags,
          ...await EspDevice.attributes(),
          ...await _transport.attributes(),
          ..._storage.sessionAttributes,
          'sdk_version': sdkVersion,
        },
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
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt != null && DateTime.now().difference(pausedAt) >= sessionTimeout) {
      await _storage.startSession(DateTime.now());
      await register();
      return;
    }
    // The user may have toggled notifications in system settings.
    if (await _transport.permission() != _storage.permission) await register();
  }

  /// A push reached the app's code while it was open (the transport has
  /// already shown it where the platform does not).
  Future<void> _onReceived(EspNotification notification) =>
      _track(_api, _storage, notification, EspEventType.delivered);

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

  void _log(String message) => _logFor(_config, message);

  /// A setup problem the developer should see: printed in debug builds even
  /// without `debug: true`.
  static void _warn(EspConfig config, String message) {
    if (kDebugMode || config.debug) debugPrint('[ESP] WARNING: $message');
  }

  /// Android background isolate: shows `data`-only pushes (FCM shows
  /// `notification` ones itself) and reports `delivered`. Does nothing on iOS.
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    if (!_isAndroid) return;
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

  static void _logFor(EspConfig? config, String message) {
    if (config?.debug ?? false) debugPrint('[ESP] $message');
  }
}
