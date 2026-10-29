import AVFoundation
import Flutter
import NaturalLanguage
import SwiftUI
import Translation
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

    // The share extension can't read the app's settings: copy the ones its
    // summary uses to the shared keychain, now and whenever Ilay leaves the
    // screen.
    AppDelegate.shareAiSettings()
    NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { _ in AppDelegate.shareAiSettings() }

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

    // Summaries made by the share extension, for You → Summaries (app.dart):
    // handed over once, as the JSON list the extension left.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IlaySharedSummaries") {
      let channel = FlutterMethodChannel(name: "ilay/shared_summaries", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "take" else { return result(FlutterMethodNotImplemented) }
        guard let data = SharedStore.read(SharedStore.pendingSummaries) else { return result(nil) }
        SharedStore.write(SharedStore.pendingSummaries, nil)
        result(String(data: data, encoding: .utf8))
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

    // On-device translation (translate.dart): Apple's Translation framework,
    // and NaturalLanguage to tell which language a post is in.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IlayTranslate") {
      let channel = FlutterMethodChannel(name: "ilay/translate", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "detect":
          result(AppDelegate.detectLanguage(args["text"] as? String ?? ""))
        case "canTranslate":
          Task {
            result(await AppDelegate.canTranslate(from: args["from"] as? String ?? "", to: args["to"] as? String ?? ""))
          }
        case "translate":
          Task { @MainActor in
            result(await AppDelegate.translate(
              args["texts"] as? [String] ?? [], from: args["from"] as? String ?? "", to: args["to"] as? String ?? ""))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// The language [text] is in ("de"), when NaturalLanguage clearly leads with one.
  private static func detectLanguage(_ text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(2000)))
    let guesses = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
    guard let best = guesses.first, best.value >= 0.25,
          best.value > (guesses.dropFirst().first?.value ?? 0) + 0.05 else { return nil }
    return best.key.rawValue
  }

  /// Whether the phone can translate [from] into [to] (now, or after a download).
  private static func canTranslate(from: String, to: String) async -> Bool {
    let status = await LanguageAvailability().status(
      from: Locale.Language(identifier: from), to: Locale.Language(identifier: to))
    return status != .unsupported
  }

  /// [texts] translated in order, or nil. A language not downloaded yet goes
  /// through the system's download prompt, which needs a view: a clear one
  /// shown over Ilay while it works.
  @MainActor
  private static func translate(_ texts: [String], from: String, to: String) async -> [String]? {
    let source = Locale.Language(identifier: from)
    let targetLanguage = Locale.Language(identifier: to)
    func run(_ session: TranslationSession) async -> [String]? {
      let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)") }
      guard let responses = try? await session.translations(from: requests) else { return nil }
      var out = texts
      for r in responses { if let i = Int(r.clientIdentifier ?? "") { out[i] = r.targetText } }
      return out
    }
    if await LanguageAvailability().status(from: source, to: targetLanguage) == .installed {
      return await run(TranslationSession(installedSource: source, target: targetLanguage))
    }
    guard let top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return nil }
    var presenter = top
    while let next = presenter.presentedViewController { presenter = next }
    return await withCheckedContinuation { cont in
      let host = UIHostingController(rootView: TranslateHost(
        config: .init(source: source, target: targetLanguage),
        work: { session in
          let out = await run(session)
          presenter.dismiss(animated: false)
          cont.resume(returning: out)
        }))
      host.view.backgroundColor = .clear
      host.modalPresentationStyle = .overFullScreen
      presenter.present(host, animated: false)
    }
  }

  /// Settings → AI summaries (and the comment sort) where the share extension
  /// can read them; shared_preferences keeps them as "flutter.<key>".
  private static func shareAiSettings() {
    var settings: [String: Any] = [:]
    for key in ["aiModel", "aiSummaryStyle", "aiMaxChars", "aiUseCustomUrl", "aiBaseUrl",
                "aiSummaryLanguage", "defaultCommentSort"] {
      settings[key] = UserDefaults.standard.object(forKey: "flutter.\(key)")
    }
    SharedStore.write(SharedStore.aiSettings, try? JSONSerialization.data(withJSONObject: settings))
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

/// Runs [work] with a translation session from SwiftUI's translationTask,
/// which asks to download the language first when it isn't on the phone.
private struct TranslateHost: View {
  let config: TranslationSession.Configuration
  let work: (TranslationSession) async -> Void

  var body: some View {
    Color.clear.translationTask(config) { session in await work(session) }
  }
}
