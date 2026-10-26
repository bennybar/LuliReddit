import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Settings → App icon: switches between the alternate icons in the asset
    // catalog (AppIcon-<colour>); nil is the primary (violet) icon.
    if let registrar = registrar(forPlugin: "IlayAppIcon") {
      let channel = FlutterMethodChannel(name: "ilay/app_icon", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "set" else { return result(FlutterMethodNotImplemented) }
        let name = call.arguments as? String
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return result(nil) }
        UIApplication.shared.setAlternateIconName(name) { error in
          result(error.map { FlutterError(code: "icon", message: $0.localizedDescription, details: nil) })
        }
      }
    }

    // Background inbox polling (BGTaskScheduler). Must be registered before the
    // app finishes launching; the identifier matches kInboxTaskUnique in Dart
    // and BGTaskSchedulerPermittedIdentifiers in Info.plist. ~15 min cadence,
    // though iOS ultimately decides when (and whether) it runs.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "luli.inbox.poll",
      frequency: NSNumber(value: 15 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
