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
