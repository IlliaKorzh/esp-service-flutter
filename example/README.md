# esp_service example

Only `lib/main.dart` is kept here. To run it, create a Flutter app with
`flutter create --platforms=android,ios .` in this folder. For Android add your
own `android/app/google-services.json` and the manifest entries from the
package README; for iOS add the Push Notifications capability in Xcode and set
the iOS deployment target to 15.0. Then:

```bash
flutter run --dart-define=ESP_PUBLIC_KEY=pk_live_... --dart-define=ESP_IOS_PUBLIC_KEY=pk_live_... \
  --dart-define=ESP_BASE_URL=https://your-esp-host
```
