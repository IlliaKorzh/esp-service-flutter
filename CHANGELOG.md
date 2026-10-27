## 0.4.0

**Upgrading from 0.3.0: nothing changes on iOS until you pass `iosPublicKey`.**
Without it every call stays a no-op on iOS (no permission dialog, no token, no
registration), and Android works as before.

- **iOS support** through APNs directly, without Firebase on iOS, opt-in with
  the new `EspConfig.iosPublicKey` (the key of the iOS application in ESP;
  `publicKey` stays the Android key, and an iOS-only app may pass `''`). The
  package is now a Flutter plugin with a small native iOS part (CocoaPods and
  Swift Package Manager); Android has no native code and works as before.
- iOS registers the raw APNs device token (lowercase hex) with the same
  `device_id`, permission, session attributes and tags as Android, on every
  session start, on token change and when the permission changes. The device
  is registered at launch before the permission is asked, as `denied`.
- `requestPermission()` shows the iOS dialog (alert, badge, sound).
  Authorized, provisional and ephemeral authorization count as `granted`.
- Taps on ESP pushes go to `setNotificationOpenedHandler` and are reported as
  `clicked`, including the tap that launched the app (also in UIScene apps,
  from the scene connection options). A debug warning tells when another
  object is the notification center delegate and taps cannot reach ESP.
  When firebase_messaging (a dependency) made itself the delegate at launch
  without wrapping another one, ESP hands the place to the Flutter app delegate,
  through which firebase_messaging keeps working; other delegates are kept. Pushes shown while the
  app is open are reported as `delivered`. Without a Notification Service
  Extension there is no `delivered` for pushes in the background.
- The plugin handles only ESP pushes (`esp_delivery_id`, `esp_campaign_id` or
  `esp_test`, at the top level or inside `data`) and leaves other
  notifications to firebase_messaging, flutter_local_notifications and the
  app's `AppDelegate`.
- New attributes on iOS: `device_manufacturer: Apple`, `apns_environment`
  (`sandbox` / `production`); `device_model` is the marketing name
  (`iPhone 16 Pro`) when known.
- `EspNotification.fromApns(userInfo)` and `EspNotification.isEspApns(userInfo)`;
  iOS pushes are de-duplicated by `esp_delivery_id` first.
- `EspConfig.validateIos()`.
- `EspPush.isSupported` is true on Android and iOS. Android behaviour is
  unchanged; `handleBackgroundMessage` stays Android only.

## 0.3.0

- Sessions for segments: `attributes` now carry `first_session_at`,
  `last_session_at` (ISO 8601, UTC) and `session_count`. A session starts on
  launch or after 30+ seconds in the background, and is registered right away.
  Apps updating from an earlier version get the install time as their first
  session. Nothing to change in the app.
- Built-in attributes can no longer be overridden by `setTags`.

## 0.2.0

- Works next to the app's own flutter_local_notifications setup (reminders,
  scheduled pushes): `initialize(..., handleLocalNotificationTaps: false)` keeps
  the app's tap callback, and `EspPush.instance.handleLocalNotificationTap(payload)`
  hands ESP taps over. Before, whichever `initialize` ran last took all taps.
- `EspNotification.isEspPayload(payload)` tells ESP notifications apart.
- Foreground notifications use `EspConfig.androidNotificationIcon` even when the
  app initialized the plugin with another icon.

## 0.1.0

First release. **Android only** — on iOS and other platforms every call is a no-op.

- Registers the FCM token in ESP (`POST /api/public/v1/subscribers`) on every
  launch, on token rotation and when the notification permission changes.
- Sends `device_id`, `external_id`, `permission` and device `attributes`
  (app and OS version, device model, language, timezone, SDK version).
- Shows pushes in the foreground and `data`-only pushes in the background.
- Reports `delivered` and `clicked` (`POST /api/public/v1/events`); keeps
  events for the next launch when the device is offline.
- Delivers taps to the app, including the push that cold-started it.
- `setExternalId` and `setTags` for product data.
