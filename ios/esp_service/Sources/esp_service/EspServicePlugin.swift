import Flutter
import UIKit

/// Method channel `esp_service` between Dart (`EspApnsTransport`) and iOS.
///
/// One instance per Flutter engine. Everything app-wide (the APNs token,
/// taps that arrived before Dart was ready) lives in [EspPushCenter], so a
/// second engine (e.g. a background isolate of another plugin) neither
/// steals taps nor completes notification callbacks twice.
///
/// Dart → iOS:
/// - `getPermissionStatus` → `authorized` / `denied` / `notDetermined` / `provisional` / `ephemeral`
/// - `requestPermission` → the same, after the system dialog (alert, badge, sound)
/// - `getToken` `{timeoutMs}` → APNs device token, lowercase hex; `FlutterError` when there is none
/// - `getApnsEnvironment` → `sandbox` / `production`
/// - `start` → `{taps, receivesNotifications, notificationDelegate}`: taps that happened
///   before Dart was ready (later ones are sent live), whether notification callbacks can
///   reach the plugin, and the class of the notification center delegate. Dart calls it
///   only when ESP is on for iOS (`EspConfig.iosPublicKey`); until then the plugin is passive.
/// - `disable` → nil: ESP is off on iOS; forget the opt-in so later launches leave the
///   notification center delegate alone. No other effect.
///
/// iOS → Dart:
/// - `onToken` (token) — the APNs token changed after Dart had received one
/// - `onNotificationOpened` `{identifier, userInfo}` — the user tapped an ESP push
/// - `onForegroundNotification` `{identifier, userInfo}` — an ESP push is shown while the app is open
public final class EspServicePlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "esp_service", binaryMessenger: registrar.messenger())
    let instance = EspServicePlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    EspPushCenter.shared.attach(to: registrar)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    EspPushCenter.shared.remove(self)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let center = EspPushCenter.shared
    switch call.method {
    case "getPermissionStatus":
      center.permissionStatus { result($0) }
    case "requestPermission":
      center.requestPermission { result($0) }
    case "getToken":
      let timeoutMs = (call.arguments as? [String: Any])?["timeoutMs"] as? Int ?? 10_000
      center.token(timeout: Double(timeoutMs) / 1000) { token, error in
        if let token = token {
          result(token)
        } else {
          result(FlutterError(code: "token_unavailable", message: error, details: nil))
        }
      }
    case "getApnsEnvironment":
      result(center.apnsEnvironment)
    case "start":
      result(center.start(self))
    case "disable":
      center.disable()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func send(_ method: String, _ arguments: Any?) {
    channel.invokeMethod(method, arguments: arguments)
  }
}
