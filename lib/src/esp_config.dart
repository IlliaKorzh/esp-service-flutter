/// Settings of the ESP push client.
///
/// Stored in SharedPreferences on [EspPush.initialize], so the background
/// isolate (which has no access to app memory) can send delivery events.
class EspConfig {
  /// [publicKey] and [baseUrl] come from the application card in the ESP
  /// dashboard. Pass them with `--dart-define` instead of committing them.
  const EspConfig({
    required this.publicKey,
    required this.baseUrl,
    this.androidChannelId = 'esp_notifications',
    this.androidChannelName = 'Notifications',
    this.androidChannelDescription = '',
    this.androidNotificationIcon = '@mipmap/ic_launcher',
    this.debug = false,
    this.requestTimeout = const Duration(seconds: 15),
  });

  /// `pk_live_...` from the application card in the ESP dashboard.
  ///
  /// Not a secret (it ships inside the APK and can only write this device's
  /// own data), but still one key per application.
  final String publicKey;

  /// Root of the ESP server, e.g. `https://esp.example.com`, without `/api`.
  final String baseUrl;

  /// Channel for notifications shown by the app itself (foreground and
  /// data-only pushes). Put the same id into AndroidManifest as
  /// `com.google.firebase.messaging.default_notification_channel_id`.
  final String androidChannelId;

  /// Channel name the user sees in the app's notification settings.
  final String androidChannelName;

  /// Channel description the user sees in the app's notification settings.
  final String androidChannelDescription;

  /// Drawable or mipmap resource, e.g. `@drawable/ic_notification`.
  final String androidNotificationIcon;

  /// Prints requests and incoming push payloads with the `[ESP]` prefix.
  /// The FCM token is truncated in the output.
  final bool debug;

  /// Timeout of a single request to ESP.
  final Duration requestTimeout;

  /// [baseUrl] without a trailing slash.
  String get normalizedBaseUrl => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  /// Why this config cannot be used, or `null` when it is valid.
  String? validate() {
    if (publicKey.trim().isEmpty) return 'publicKey is empty';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'baseUrl is not an absolute URL: "$baseUrl"';
    final isLocal = uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '10.0.2.2';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLocal)) {
      return 'baseUrl must use https (http is allowed only for localhost): "$baseUrl"';
    }
    return null;
  }

  /// Serializes the config for the background isolate.
  Map<String, Object?> toJson() => {
    'public_key': publicKey,
    'base_url': baseUrl,
    'android_channel_id': androidChannelId,
    'android_channel_name': androidChannelName,
    'android_channel_description': androidChannelDescription,
    'android_notification_icon': androidNotificationIcon,
    'debug': debug,
    'request_timeout_ms': requestTimeout.inMilliseconds,
  };

  /// Restores a config saved with [toJson].
  factory EspConfig.fromJson(Map<String, Object?> json) => EspConfig(
    publicKey: json['public_key'] as String,
    baseUrl: json['base_url'] as String,
    androidChannelId: json['android_channel_id'] as String? ?? 'esp_notifications',
    androidChannelName: json['android_channel_name'] as String? ?? 'Notifications',
    androidChannelDescription: json['android_channel_description'] as String? ?? '',
    androidNotificationIcon: json['android_notification_icon'] as String? ?? '@mipmap/ic_launcher',
    debug: json['debug'] as bool? ?? false,
    requestTimeout: Duration(milliseconds: json['request_timeout_ms'] as int? ?? 15000),
  );
}
