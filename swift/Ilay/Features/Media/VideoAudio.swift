import AVFoundation

/// The audio session every player shares. Muted clips play silently alongside the
/// user's music (`.ambient`); one with sound takes over the session like any player
/// (pauses for a call, stops other audio). iOS's counterpart of Android's audio focus.
///
/// AVPlayer activates the session as soon as it plays, even muted, so `.ambient` has
/// to be in place before the first clip: the default category would stop the music.
@MainActor final class VideoAudio {
    static let shared = VideoAudio()

    /// Session calls are synchronous IPC, long enough to drop frames: never on main.
    private let queue = DispatchQueue(label: "ilay.video-audio")
    private var audible = false

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    /// `resume` runs on main once the session is settled. Going silent, `player` is
    /// paused meanwhile: deactivating (which gives the music back) fails while it runs.
    func setAudible(_ on: Bool, player: AVPlayer? = nil, resume: @escaping @MainActor () -> Void = {}) {
        guard on != audible else {
            resume()
            return
        }
        audible = on
        let session = AVAudioSession.sharedInstance()
        if on {
            queue.async {
                try? session.setCategory(.playback, mode: .moviePlayback)
                try? session.setActive(true)
            }
            resume()
        } else {
            player?.pause()
            queue.async {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try? session.setCategory(.ambient)
                DispatchQueue.main.async { MainActor.assumeIsolated { resume() } }
            }
        }
    }
}

/// Calls `resume` when an interruption (a call, Siri) ends: a clip with sound only if
/// the system says so, a muted one always, as it never took the audio over.
@MainActor func observeAudioInterruptions(muted: @escaping @MainActor () -> Bool, resume: @escaping @MainActor () -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
        guard let info = note.userInfo,
              let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init),
              type == .ended else { return }
        let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        MainActor.assumeIsolated {
            if muted() || options.contains(.shouldResume) { resume() }
        }
    }
}
