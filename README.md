# esp_service

Flutter client of **ESP (Email & Push Service)**.

It registers the device's FCM token in ESP, shows push notifications and
reports delivery and taps back, so campaigns in the ESP dashboard get
`sent → delivered → clicked` statistics.

> **Android only for now.** On iOS and other platforms every call is a no-op,
> so a cross-platform app can keep the same code. iOS (APNs) support will come
> in a later version.

## What it does

- Registers the device in ESP on every launch, on FCM token rotation and when
  the notification permission changes (also when it is changed in system
  settings while the app was in the background).
- Sends a stable `device_id` (ANDROID_ID), so token rotation and reinstall do
  not create duplicate subscribers.
- Sends device attributes for segments: app and OS version, device model,
  language, timezone, SDK version, plus your own tags.
- Shows pushes while the app is in the foreground (FCM does not) and
  `data`-only pushes in the background.
- Reports `delivered` and `clicked` for every campaign push; events are kept
  and sent later if the device is offline. Test pushes (`esp_test: "1"`) are
  not reported.
- Delivers taps to your code, including the push that cold-started the app.

## Requirements

- Flutter 3.38.1+, Dart 3.10+
- Android app connected to Firebase (`google-services.json`)
- An application in the ESP dashboard for this app

## 1. Create the application in ESP

1. In Firebase console → Project settings → Service accounts, generate a new
   private key for the Firebase project of the app.
2. In the ESP dashboard create an application (platform **Android**) and upload
   that key in **Keys**. The card must show **Connected · FCM** with the right
   Firebase project.
3. Copy the application's **Public key** (`pk_live_…`) and the ESP server URL.

The service account key is a real secret: upload it to ESP and delete the file.
Never put it into the app or into git. The public key is not a secret (it ships
inside the APK and can only write this device's own data), but keep it out of
shared repositories anyway, see step 4.

## 2. Add the package

```yaml
dependencies:
  esp_service: ^0.1.0
  firebase_core: ^4.13.0
```

Remove other push SDKs (e.g. OneSignal) from the Android build: two SDKs
listening to the same FCM messages show or count pushes twice.

## 3. Android setup

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

## 4. Initialize

Pass the per-app values at build time instead of hard-coding them:

```bash
flutter run --dart-define=ESP_PUBLIC_KEY=pk_live_... --dart-define=ESP_BASE_URL=https://your-esp-host
```

For CI / release builds put them into a file that is not committed and use
`--dart-define-from-file=esp.json`.

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
      publicKey: String.fromEnvironment('ESP_PUBLIC_KEY'),
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
background. It throws `ArgumentError` if the key is empty or the URL is not
`https`.

## 5. Ask for the notification permission

On Android 13+ pushes are not shown until the user allows them. Ask where it
makes sense in your flow (e.g. on the home screen):

```dart
final allowed = await EspPush.instance.requestPermission();
```

The result is sent to ESP: `denied` makes the subscriber `unsubscribed`, and
allowing it later makes it `active` again.

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

Only one FCM background handler can exist in an app. The package registers its
own; if you need yours, pass `registerBackgroundHandler: false` and call
`EspPush.handleBackgroundMessage(message)` from your handler.

## Push payload

ESP sends FCM messages with a `notification` (title, body) and `data`:

| key | meaning |
|---|---|
| `esp_delivery_id` | id of this delivery, sent back with `delivered` / `clicked` |
| `esp_campaign_id` | campaign id |
| `esp_test` | `"1"` for a test push from the campaign page; no events are sent |

Any other campaign data arrives in `EspNotification.data`.

## Check it works

Run a debug build and watch the log (`flutter run` or `adb logcat | grep ESP`):

1. Start: `[ESP] registered: <id> (unsubscribed)`, then after allowing
   notifications `(active)`. The subscriber appears in ESP → Subscribers.
2. Send a push from a campaign in three states and tap it each time:
   - app open: the app shows the notification itself (`[ESP] foreground push`);
   - app in background: the system shows it (`[ESP] background push`);
   - app swiped away from recents: the system shows it, the tap cold-starts
     the app and your handler receives the push.

### Known limitations

- A **force-stopped** app (Settings → Force stop, or `flutter run` being
  stopped, which force-stops the app) gets no FCM messages until the user
  opens it again. This is Android behavior for every push provider. Test the
  killed state by swiping the app away from recents instead.
- Some vendors (Xiaomi, Huawei, Oppo, Vivo…) treat swipe-away as force stop
  or restrict background work; pushes may be delayed or dropped there unless
  the user allows autostart / background activity.

## Security

- Never commit the Firebase service account key; it is only uploaded to ESP.
- Keep `pk_live_…` and the server URL in `--dart-define` values, not in the
  source.
- Debug logs truncate the FCM token; nothing is logged in release builds unless
  `debug: true` is passed.
