import Flutter
import UIKit
import UserNotifications

/// App-wide part of the plugin: receives the APNs token and notification
/// callbacks that FlutterAppDelegate forwards to plugins, keeps taps until
/// Dart is ready and hands them to every started [EspServicePlugin].
///
/// FlutterAppDelegate passes the same completion handler of
/// `UNUserNotificationCenterDelegate` to every plugin (in registration order),
/// so each plugin must complete only the notifications it owns. This class
/// calls it once for ESP pushes and never for other notifications. Other
/// plugins may call it too: firebase_messaging completes every notification.
///
/// Passive until Dart opts in (`start`, sent only when `EspConfig.iosPublicKey`
/// is set): before that the notification center delegate is left alone, so an
/// app that does not use ESP on iOS behaves as without the plugin.
///
/// Registered once per process and kept alive here: Flutter holds application
/// delegates weakly, and a plugin instance dies with its engine.
final class EspPushCenter: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static let shared = EspPushCenter()

  /// Keys that mark an ESP push, at the top level of `userInfo` or inside `data`.
  static let espKeys = ["esp_delivery_id", "esp_campaign_id", "esp_test"]

  /// Required by FlutterPlugin; Flutter registers [EspServicePlugin] instead.
  static func register(with registrar: FlutterPluginRegistrar) {}

  /// Set once Dart has opted in; from the next launch the notification center
  /// delegate is claimed at registration, early enough for the launch tap.
  private static let enabledKey = "esp_service.enabled"

  private var attached = false
  private let receivers = NSHashTable<EspServicePlugin>.weakObjects()
  private var pendingTaps: [[String: Any]] = []
  /// Taps already handled; the launch tap can come both from the scene
  /// connection options and from `didReceive`.
  private var openedKeys = Set<String>()

  private var token: String?
  private var tokenError: String?
  /// Last token Dart has seen; a different one later is reported as `onToken`.
  private var deliveredToken: String?
  private var tokenWaiters: [(String?, String?) -> Void] = []
  private var tokenRequest = 0

  // MARK: - Setup

  func attach(to registrar: FlutterPluginRegistrar) {
    // Per engine: the launch tap of a UIScene app comes with the scene
    // connection options (Flutter 3.38+), which reach plugins of each engine.
    registrar.addSceneDelegate(self)

    guard !attached else { return }
    attached = true
    registrar.addApplicationDelegate(self)
    if UserDefaults.standard.bool(forKey: EspPushCenter.enabledKey) { claimNotificationCenter() }
  }

  /// FlutterAppDelegate forwards notification callbacks to plugins only when it
  /// is the notification center delegate. Apps that never set one get it here.
  ///
  /// firebase_messaging (a dependency of this package, so always in the build)
  /// makes itself the delegate when there is none, at launch and before Dart
  /// can call `start`. It also works when reached through FlutterAppDelegate,
  /// so its place is taken over as long as it does not wrap another delegate.
  /// Any other delegate (the app's own, OneSignal, Braze…) is kept.
  private func claimNotificationCenter() {
    guard let appDelegate = UIApplication.shared.delegate,
      appDelegate is FlutterAppLifeCycleProvider,
      let notificationDelegate = appDelegate as? UNUserNotificationCenterDelegate
    else { return }
    let center = UNUserNotificationCenter.current()
    if let current = center.delegate {
      guard EspPushCenter.isBareFirebaseMessaging(current) else { return }
    }
    center.delegate = notificationDelegate
  }

  /// Whether [delegate] is firebase_messaging's plugin without an original
  /// delegate behind it. Checked by class and ivar name, without linking the plugin;
  /// when its layout is unknown the delegate is left alone.
  private static func isBareFirebaseMessaging(_ delegate: UNUserNotificationCenterDelegate) -> Bool {
    let object = delegate as AnyObject
    guard NSStringFromClass(type(of: object)) == "FLTFirebaseMessagingPlugin",
      let ivar = class_getInstanceVariable(type(of: object), "_originalNotificationCenterDelegate")
    else { return false }
    // object_getIvar reads __weak ivars through the weak reference.
    return object_getIvar(object, ivar) == nil
  }

  /// Whether notification callbacks can reach the plugin: the notification
  /// center delegate is Flutter's app delegate, which forwards them to plugins.
  private func receivesNotifications() -> Bool {
    guard let appDelegate = UIApplication.shared.delegate, appDelegate is FlutterAppLifeCycleProvider else {
      return false
    }
    return (UNUserNotificationCenter.current().delegate as AnyObject?) === (appDelegate as AnyObject)
  }

  /// Dart is ready: returns taps kept until now (later ones are sent live) and
  /// whether taps can reach the plugin at all.
  func start(_ plugin: EspServicePlugin) -> [String: Any] {
    UserDefaults.standard.set(true, forKey: EspPushCenter.enabledKey)
    claimNotificationCenter()
    receivers.add(plugin)
    let taps = pendingTaps
    pendingTaps = []
    let delegate = UNUserNotificationCenter.current().delegate
    return [
      "taps": taps,
      "receivesNotifications": receivesNotifications(),
      "notificationDelegate": delegate.map { String(describing: type(of: $0)) } ?? "nil",
    ]
  }

  /// ESP is off on iOS (no `EspConfig.iosPublicKey`): stop claiming the
  /// notification center delegate on later launches.
  func disable() {
    UserDefaults.standard.removeObject(forKey: EspPushCenter.enabledKey)
  }

  func remove(_ plugin: EspServicePlugin) {
    receivers.remove(plugin)
  }

  private func send(_ method: String, _ arguments: Any?) {
    for plugin in receivers.allObjects {
      plugin.send(method, arguments)
    }
  }

  // MARK: - Permission

  func permissionStatus(_ completion: @escaping (String) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status = EspPushCenter.name(of: settings.authorizationStatus)
      DispatchQueue.main.async { completion(status) }
    }
  }

  func requestPermission(_ completion: @escaping (String) -> Void) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
      self.permissionStatus(completion)
    }
  }

  static func name(of status: UNAuthorizationStatus) -> String {
    if #available(iOS 14.0, *), status == .ephemeral { return "ephemeral" }
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    case .provisional: return "provisional"
    default: return "unknown"
    }
  }

  // MARK: - APNs token

  /// The cached token, or a new registration that waits for the delegate
  /// callback up to [timeout]. Works without the notification permission.
  func token(timeout: TimeInterval, completion: @escaping (String?, String?) -> Void) {
    if let token = token {
      deliveredToken = token
      completion(token, nil)
      return
    }
    tokenWaiters.append(completion)
    guard tokenWaiters.count == 1 else { return }

    tokenRequest += 1
    let request = tokenRequest
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self = self, self.tokenRequest == request else { return }
      self.finishTokenRequest(nil, self.tokenError ?? "APNs did not return a device token in \(Int(timeout)) s")
    }
  }

  private func finishTokenRequest(_ token: String?, _ error: String?) {
    tokenRequest += 1
    let waiters = tokenWaiters
    tokenWaiters = []
    if token != nil && !waiters.isEmpty { deliveredToken = token }
    for waiter in waiters {
      waiter(token, error)
    }
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    token = hex
    tokenError = nil
    if !tokenWaiters.isEmpty {
      finishTokenRequest(hex, nil)
    } else if hex != deliveredToken && !receivers.allObjects.isEmpty {
      // A new token (or the first one after a timed-out request): Dart registers it again.
      deliveredToken = hex
      send("onToken", hex)
    }
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    tokenError = error.localizedDescription
    if !tokenWaiters.isEmpty { finishTokenRequest(nil, tokenError) }
  }

  // MARK: - Environment

  /// `sandbox` for the simulator and development-signed builds, else `production`.
  lazy var apnsEnvironment: String = {
    #if targetEnvironment(simulator)
      return "sandbox"
    #else
      return EspPushCenter.provisioningApsEnvironment() == "development" ? "sandbox" : "production"
    #endif
  }()

  /// `aps-environment` of embedded.mobileprovision; App Store builds have none.
  private static func provisioningApsEnvironment() -> String? {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      // The profile is a signed CMS envelope with the plist inside as plain text.
      let text = String(data: data, encoding: .isoLatin1),
      let start = text.range(of: "<?xml"),
      let end = text.range(of: "</plist>", range: start.upperBound..<text.endIndex),
      let plist = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
      let profile = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
      let entitlements = profile["Entitlements"] as? [String: Any]
    else { return nil }
    return entitlements["aps-environment"] as? String
  }

  // MARK: - Notifications

  static func isEsp(_ userInfo: [AnyHashable: Any]) -> Bool {
    if espKeys.contains(where: { userInfo[$0] != nil }) { return true }
    guard let data = userInfo["data"] as? [AnyHashable: Any] else { return false }
    return espKeys.contains { data[$0] != nil }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    // Not ours: its owner completes it.
    guard EspPushCenter.isEsp(userInfo) else { return }

    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
    send("onForegroundNotification", EspPushCenter.arguments(of: notification))
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let notification = response.notification
    guard EspPushCenter.isEsp(notification.request.content.userInfo) else { return }

    if response.actionIdentifier != UNNotificationDismissActionIdentifier {
      opened(notification)
    }
    completionHandler()
  }

  /// A UIScene app launched by a tap gets the response here, possibly before
  /// any notification center delegate is set. Never consumes the options.
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let response = connectionOptions?.notificationResponse,
      response.actionIdentifier != UNNotificationDismissActionIdentifier,
      EspPushCenter.isEsp(response.notification.request.content.userInfo)
    else { return false }
    opened(response.notification)
    return false
  }

  private func opened(_ notification: UNNotification) {
    let key = "\(notification.request.identifier)|\(notification.date.timeIntervalSince1970)"
    guard openedKeys.insert(key).inserted else { return }
    let arguments = EspPushCenter.arguments(of: notification)
    if receivers.allObjects.isEmpty {
      // Dart is not running yet, e.g. the tap launched the app.
      pendingTaps.append(arguments)
    } else {
      send("onNotificationOpened", arguments)
    }
  }

  private static func arguments(of notification: UNNotification) -> [String: Any] {
    return [
      "identifier": notification.request.identifier,
      "userInfo": codable(notification.request.content.userInfo),
    ]
  }

  /// `userInfo` in types the standard message codec can send.
  private static func codable(_ value: Any) -> Any {
    switch value {
    case let dictionary as [AnyHashable: Any]:
      var result: [String: Any] = [:]
      for (key, item) in dictionary {
        result["\(key)"] = codable(item)
      }
      return result
    case let array as [Any]:
      return array.map(codable)
    case is String, is NSNumber, is NSNull:
      return value
    default:
      return "\(value)"
    }
  }
}
