# esp_service

Flutter client of **ESP (Email & Push Service)**.

It registers the device's push token in ESP (FCM on Android, APNs on iOS),
shows push notifications and reports delivery and taps back, so campaigns in
the ESP dashboard get `sent → delivered → clicked` statistics.

> **Android and iOS.** On iOS the package talks to APNs directly and does not
> use Firebase. iOS is opt-in: it stays off until you pass
> `EspConfig.iosPublicKey` (see [Upgrading from 0.3.0](#upgrading-from-030)).
> On other platforms every call is a no-op, so a cross-platform app can keep
> the same code.

## What it does

- Registers the device in ESP on every session start, on token rotation and
  when the notification permission changes (also when it is changed in system
  settings while the app was in the background).
- Sends a stable `device_id` (ANDROID_ID on Android, a Keychain id on iOS), so
  token rotation and reinstall do not create duplicate subscribers.
- Sends device and session attributes for segments, with no code in the app
  (see [Attributes](#attributes)), plus your own tags.
- Android: shows pushes while the app is in the foreground (FCM does not) and
  `data`-only pushes in the background. iOS: the system shows them, also in the
  foreground.
- Reports `delivered` and `clicked` for every campaign push; events are kept
  and sent later if the device is offline. Test pushes (`esp_test: "1"`) are
  not reported. On iOS `delivered` is sent only for pushes that arrive while
  the app is open (see [iOS setup](#3b-ios-setup)).
- Delivers taps to your code, including the push that cold-started the app.

## Requirements

- Flutter 3.38.1+, Dart 3.10+
- Android: app connected to Firebase (`google-services.json`)
- iOS: Push Notifications capability (no Firebase needed for ESP). The native
  part needs iOS 13; firebase_messaging, which the package uses on Android,
  makes the app's minimum iOS 15
- An application in the ESP dashboard for each platform of the app

## 1. Create the application in ESP

ESP tells Android and iOS apart by the application key, so an app on both
platforms has **two** applications in ESP and two public keys.

Android:

1. In Firebase console → Project settings → Service accounts, generate a new
   private key for the Firebase project of the app.
2. In the ESP dashboard create an application (platform **Android**) and upload
   that key in **Keys**. The card must show **Connected · FCM** with the right
   Firebase project.
3. Copy the application's **Public key** (`pk_live_…`) and the ESP server URL.

iOS:

1. Create an application with platform **iOS** for the app's bundle id and
   connect APNs in **Keys**, as the dashboard asks.
2. Copy its **Public key** (`pk_live_…`); it goes to `EspConfig.iosPublicKey`.

The service account key (and an APNs `.p8` key) is a real secret: upload it to
ESP and delete the file. Never put it into the app or into git. The public key
is not a secret (it ships inside the app and can only write this device's own
data), but keep it out of shared repositories anyway, see step 4.

## 2. Add the package

```yaml
dependencies:
  esp_service: ^0.4.0
  firebase_core: ^4.13.0 # Android (FCM)
```

Remove other push SDKs (e.g. OneSignal) from the Android build: two SDKs
listening to the same FCM messages show or count pushes twice.

## 3a. Android setup

`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application ...>
        <!-- Pushes that FCM shows by itself go to the same channel as EspConfig.androidChannelId -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="app_notifications" />
    </application>
</manifest>
```

`android/app/build.gradle(.kts)` needs the Google services plugin, as for any
Firebase app, and `minSdk` 21 or higher.

For a monochrome status bar icon add `android/app/src/main/res/drawable/ic_notification.png`
and pass `androidNotificationIcon: '@drawable/ic_notification'`.

## 3b. iOS setup

1. In Xcode → Runner → Signing & Capabilities add **Push Notifications**. It
   adds the `aps-environment` entitlement to `Runner.entitlements`:

   ```xml
   <key>aps-environment</key>
   <string>development</string>
   ```

   Xcode switches it to `production` when the app is exported for TestFlight /
   App Store. **Background Modes are not needed.**
2. Run `pod install` (or just `flutter run`): the package has a small native
   part (`EspServicePlugin`) and supports CocoaPods and Swift Package Manager.
3. Pass `iosPublicKey` to `EspConfig` (step 4). Without it ESP stays off on
   iOS.
4. Usually nothing else is required in `AppDelegate`. The plugin needs
   Flutter's app delegate to forward APNs and notification callbacks to
   plugins, which `FlutterAppDelegate` does:
   - **Token.** `didRegisterForRemoteNotificationsWithDeviceToken` reaches the
     plugin as long as an override in `AppDelegate` calls `super`.
   - **Taps.** iOS sends them to `UNUserNotificationCenter.current().delegate`,
     and only a `FlutterAppDelegate` there forwards them to plugins. With
     `iosPublicKey` set, the plugin makes the app delegate the notification
     delegate when there is none, or when firebase_messaging took the empty
     place at launch (firebase_messaging, a dependency of this package, does
     that before Dart runs; it keeps working through the app delegate). This
     happens when `initialize` runs and, from the next launch on, as soon as
     the plugin is registered. Without `iosPublicKey` the plugin leaves the
     delegate alone. If the app sets one itself, it must be the `AppDelegate`
     (`UNUserNotificationCenter.current().delegate = self`), and an override of
     `userNotificationCenter(_:didReceive:withCompletionHandler:)` must call
     `super`.
   - **The tap that launches the app.** Apps without scenes (no
     `UIApplicationSceneManifest` in `Info.plist`) get it as long as the
     delegate is set in `didFinishLaunchingWithOptions`, which the plugin does
     when it is registered there (`GeneratedPluginRegistrant.register(with: self)`).
     UIScene apps (the Flutter 3.38+ template, where plugins register in
     `didInitializeImplicitFlutterEngine`) get it from the scene connection
     options, so they usually need nothing extra either. But Flutter hands the
     connection options to plugins one by one, and once a plugin returns `YES`
     from `scene(_:willConnectTo:options:)` (it "handled" the launch, e.g. a deep
     link plugin), later plugins get `nil` options. Then the launch tap only
     reaches ESP through the notification delegate, so we recommend setting
     `UNUserNotificationCenter.current().delegate = self` in
     `didFinishLaunchingWithOptions` in every app; it is the most robust setup.
   - **Foreground.** Without an override of `willPresent` the plugin shows ESP
     pushes as banners and reports `delivered`. An override that does not call
     `super` decides the presentation itself; the push is still shown if it
     returns `.banner` / `.alert`, but `delivered` is not reported.
   - **Another notification delegate.** If something else becomes the
     notification center delegate (OneSignal, Braze, the app's own class, or
     firebase_messaging wrapping one of them), taps never reach ESP:
     no `clicked` and no opened handler. In debug builds the log then says
     `[ESP] WARNING: UNUserNotificationCenter.delegate is …`. Make that delegate
     forward to the `AppDelegate`, or keep the `AppDelegate` as the delegate.

   The plugin only handles ESP pushes (with `esp_delivery_id`, `esp_campaign_id`
   or `esp_test`) and leaves other notifications to their owners, so
   firebase_messaging, flutter_local_notifications and the app's own handling
   keep working next to it.

   **Completion handlers.** `FlutterAppDelegate` hands the same completion
   handler of `willPresent` / `didReceive` to every plugin, in registration
   order (`GeneratedPluginRegistrant` registers plugins alphabetically, so
   `esp_service` comes before `firebase_messaging`). ESP calls it once, and only
   for ESP pushes. firebase_messaging, which this package depends on, calls it
   for **every** notification when the `AppDelegate` is the delegate, so for an
   ESP push it is called twice. In our tests iOS used the first call (ESP's
   banner options) and ignored the second; an `AppDelegate` that overrides
   `willPresent` without `super` avoids the question altogether.

**Sandbox and production.** A debug build signed with a development profile
gets a sandbox APNs token; TestFlight, Ad Hoc and App Store builds get
production tokens. The package sends `apns_environment` (`sandbox` /
`production`) with every registration, so ESP and you can tell which gateway
the token belongs to. The simulator (Xcode 14+, Apple silicon or T2 Mac) also
gets sandbox tokens.

**No Notification Service Extension yet.** iOS shows ESP pushes without running
any app code, so `delivered` is reported only for pushes that arrive while the
app is open. `clicked` is reported for every tap, including the one that
launches the app.

## 4. Initialize

Pass the per-app values at build time instead of hard-coding them:

```bash
flutter run --dart-define=ESP_PUBLIC_KEY=pk_live_... --dart-define=ESP_IOS_PUBLIC_KEY=pk_live_... \
  --dart-define=ESP_BASE_URL=https://your-esp-host
```

For CI / release builds put them into a file that is not committed and use
`--dart-define-from-file=esp.json`. Android and iOS are separate applications in
ESP (see step 1): `publicKey` is the **Android** key and `iosPublicKey` the
**iOS** key. The package picks the one for the running platform; an iOS-only
app may pass `publicKey: ''`.

```dart
import 'package:esp_service/esp_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await EspPush.instance.initialize(
    const EspConfig(
      publicKey: String.fromEnvironment('ESP_PUBLIC_KEY'), // Android application
      iosPublicKey: String.fromEnvironment('ESP_IOS_PUBLIC_KEY'), // iOS application
      baseUrl: String.fromEnvironment('ESP_BASE_URL'),
      androidChannelId: 'app_notifications', // same as in AndroidManifest
      androidChannelName: 'Notifications',
      debug: kDebugMode, // prints [ESP] logs
    ),
  );

  runApp(const MyApp());
}
```

`initialize` does not wait for the network: registration runs in the
background. It throws `ArgumentError` if the key of the platform is empty
(Android) or the URL is not `https`. On iOS an empty or missing `iosPublicKey`
does not throw: ESP is simply off there. On iOS ESP does not need
`Firebase.initializeApp()`; call it only if the app uses Firebase for something
else. The `android…` settings are ignored on iOS.

### Upgrading from 0.3.0

Nothing changes on iOS until you pass `iosPublicKey`: without it `initialize`
is a no-op on iOS, `requestPermission()` returns `false` without a dialog, no
token is requested and nothing is registered, exactly as in 0.3.0 (the native
part only listens and forgets an earlier opt-in). Android works as before with `publicKey`. To turn iOS on,
create the iOS application in ESP, do the [iOS setup](#3b-ios-setup) and pass
its key as `iosPublicKey`.

## 5. Ask for the notification permission

On Android 13+ and iOS pushes are not shown until the user allows them. Ask
where it makes sense in your flow (e.g. on the home screen):

```dart
final allowed = await EspPush.instance.requestPermission();
```

The result is sent to ESP: `denied` makes the subscriber `unsubscribed`, and
allowing it later makes it `active` again. The device is registered at launch
before the question too (as `unsubscribed`). iOS shows the dialog only once;
after that the user changes it in Settings, and the package notices it when
the app comes back. Provisional (quiet) authorization counts as allowed.

## 6. Handle taps

Set the handler once the navigator is ready. Taps that happened earlier (the
push that launched the app) are delivered right away:

```dart
runApp(const MyApp());
WidgetsBinding.instance.addPostFrameCallback((_) {
  EspPush.instance.setNotificationOpenedHandler((push) {
    final url = push.url; // data.url / link / deeplink, if the push has one
    final page = push.data['page']; // any custom data from the campaign
    // navigate…
  });
});
```

## 7. Optional

```dart
// Your user id once the person logs in; campaigns can then target all their devices.
await EspPush.instance.setExternalId('user-42');

// Product tags for segments; null removes a tag.
await EspPush.instance.setTags({'plan': 'pro', 'form_submitted': true});

// ESP subscriber id of this device (null until the first registration).
EspPush.instance.subscriberId.addListener(() {
  print(EspPush.instance.subscriberId.value);
});
```

Android: only one FCM background handler can exist in an app. The package
registers its own; if you need yours, pass `registerBackgroundHandler: false`
and call `EspPush.handleBackgroundMessage(message)` from your handler.

## Apps that already use flutter_local_notifications

This section is about Android: on iOS ESP does not use
flutter_local_notifications at all, and its taps arrive through the plugin's
own channel.

flutter_local_notifications keeps **one** tap callback per app: the last
`initialize` call wins. If the app shows its own local notifications
(reminders, scheduled pushes), let the app own the plugin and forward ESP taps:

```dart
await EspPush.instance.initialize(config, handleLocalNotificationTaps: false);

// The app's own setup, as before:
await plugin.initialize(
  settings: settings,
  onDidReceiveNotificationResponse: (response) {
    if (EspPush.instance.handleLocalNotificationTap(response.payload)) return;
    // ...the app's own taps, unchanged
  },
);

final launch = await plugin.getNotificationAppLaunchDetails();
if (launch?.didNotificationLaunchApp ?? false) {
  final payload = launch!.notificationResponse?.payload;
  if (!EspPush.instance.handleLocalNotificationTap(payload)) {
    // ...the app's own cold-start tap, unchanged
  }
}
```

ESP still creates its channel and shows foreground pushes; the plugin must be
initialized by the app at startup, before the first push can arrive.

## Attributes

Sent in `attributes` with every registration. Nothing to set up in the app.

| key | example | meaning |
|---|---|---|
| `first_session_at` | `2026-10-01T09:00:00Z` | first session (UTC). For apps that update to 0.3.0 it is the install time |
| `last_session_at` | `2026-10-16T18:30:00Z` | start of the current session (UTC) |
| `session_count` | `12` | sessions so far |
| `language` | `uk` | system language |
| `timezone` | `Europe/Kyiv` | IANA time zone |
| `app_version` / `app_build` | `2.3.2` / `41` | app version and build number |
| `os_version` | `14` / `18.1` | Android / iOS version |
| `device_model` / `device_manufacturer` | `Pixel 8` / `Google`, `iPhone 16 Pro` / `Apple` | device |
| `apns_environment` | `sandbox` / `production` | iOS only: APNs gateway of the token |
| `sdk_version` | `0.4.0` | version of this package |

A session starts when the app is launched or comes back after at least 30
seconds in the background (`EspPush.sessionTimeout`); each new session is
registered right away. Pushes handled in the background do not start one.
Country and device type are not sent: ESP gets them from the request IP and
the application. Tags from `setTags` cannot override these keys.

## Push payload

ESP sends FCM messages with a `notification` (title, body) and `data`:

| key | meaning |
|---|---|
| `esp_delivery_id` | id of this delivery, sent back with `delivered` / `clicked` |
| `esp_campaign_id` | campaign id |
| `esp_test` | `"1"` for a test push from the campaign page; no events are sent |

Any other campaign data arrives in `EspNotification.data`.

On iOS the same keys come in the APNs payload, either next to `aps` or inside a
`data` dictionary; title and body come from `aps.alert`:

```json
{
  "aps": {"alert": {"title": "Title", "body": "Text"}, "sound": "default"},
  "esp_delivery_id": "184467",
  "esp_campaign_id": "c-1",
  "url": "https://example.com/offer"
}
```

`EspNotification.data` then holds every key except `aps` (the keys of a nested
`data` dictionary included), as strings.

## Check it works

Run a debug build and watch the log (`flutter run`, `adb logcat | grep ESP` on
Android, the Xcode console on iOS):

1. Start: `[ESP] registered: <id> (unsubscribed)`, then after allowing
   notifications `(active)`. The subscriber appears in ESP → Subscribers.
2. Send a push from a campaign in three states and tap it each time:
   - app open: the app shows the notification itself (`[ESP] foreground push`);
   - app in background: the system shows it (`[ESP] background push`);
   - app swiped away from recents: the system shows it, the tap cold-starts
     the app and your handler receives the push.

On iOS the app in the background logs nothing until the tap (`[ESP] opened`).
A debug build has a sandbox token (`apns_environment: sandbox`), so ESP must
send to it through the APNs sandbox. If the log says
`APNs token is not available`, check the Push Notifications capability and the
provisioning profile; the line before it has the reason from iOS.

### Known limitations

- A **force-stopped** app (Settings → Force stop, or `flutter run` being
  stopped, which force-stops the app) gets no FCM messages until the user
  opens it again. This is Android behavior for every push provider. Test the
  killed state by swiping the app away from recents instead.
- Some vendors (Xiaomi, Huawei, Oppo, Vivo…) treat swipe-away as force stop
  or restrict background work; pushes may be delayed or dropped there unless
  the user allows autostart / background activity.
- iOS: `delivered` only for pushes that arrive while the app is open (there is
  no Notification Service Extension yet).

## Security

- Never commit the Firebase service account key or an APNs `.p8` key; they are
  only uploaded to ESP.
- Keep `pk_live_…` and the server URL in `--dart-define` values, not in the
  source.
- Debug logs truncate the push token; nothing is logged in release builds unless
  `debug: true` is passed.
