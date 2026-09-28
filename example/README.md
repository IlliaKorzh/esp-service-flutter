# esp_service example

Only `lib/main.dart` is kept here. To run it, create a Flutter app with
`flutter create --platforms=android .` in this folder, add your own
`android/app/google-services.json` and the manifest entries from the package
README, then:

```bash
flutter run --dart-define=ESP_PUBLIC_KEY=pk_live_... --dart-define=ESP_BASE_URL=https://your-esp-host
```
