import AVFoundation
import Flutter
import UIKit
import UserNotifications
import workmanager_apple

// UIScene lifecycle (required by current iOS): the Flutter engine is created
// implicitly by FlutterSceneDelegate, so plugins register once it exists.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background inbox polling (BGTaskScheduler). Must be registered before the
    // app finishes launching; the identifier matches kInboxTaskUnique in Dart
    // and BGTaskSchedulerPermittedIdentifiers in Info.plist. ~15 min cadence,
    // though iOS ultimately decides when (and whether) it runs.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "luli.inbox.poll",
      frequency: NSNumber(value: 15 * 60)
    )
    // Notification taps (inbox, post reminders) and notifications arriving
    // while Ilay is open reach flutter_local_notifications through the app
    // delegate, which forwards them to the plugins.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Settings → App icon: switches between the alternate icons in the asset
    // catalog (AppIcon-<colour>); nil is the primary (violet) icon.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IlayAppIcon") {
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

    // Saving / sharing a Reddit video with its sound (see save_media.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IlayMediaMux") {
      let channel = FlutterMethodChannel(name: "ilay/media_mux", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "mux", let args = call.arguments as? [String: String],
              let video = args["video"], let audio = args["audio"], let out = args["out"]
        else { return result(FlutterMethodNotImplemented) }
        Task { @MainActor in
          do {
            try await AppDelegate.mux(video: video, audio: audio, out: out)
            result(nil)
          } catch {
            result(FlutterError(code: "mux", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  /// A Reddit video's picture and its sound (separate files on v.redd.it)
  /// into one mp4, copying the samples as they are (no re-encode).
  private static func mux(video: String, audio: String, out: String) async throws {
    let v = AVURLAsset(url: URL(fileURLWithPath: video))
    let a = AVURLAsset(url: URL(fileURLWithPath: audio))
    guard let videoTrack = try await v.loadTracks(withMediaType: .video).first,
          let audioTrack = try await a.loadTracks(withMediaType: .audio).first
    else { throw NSError(domain: "mux", code: 1, userInfo: [NSLocalizedDescriptionKey: "No track"]) }
    let duration = try await v.load(.duration)
    let audioDuration = try await a.load(.duration)
    let composition = AVMutableComposition()
    let cv = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    let ca = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    try cv?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
    cv?.preferredTransform = try await videoTrack.load(.preferredTransform)
    try ca?.insertTimeRange(
      CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero)
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
    else { throw NSError(domain: "mux", code: 2, userInfo: [NSLocalizedDescriptionKey: "No exporter"]) }
    let url = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: url)
    try await export.export(to: url, as: .mp4)
  }
}
