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
