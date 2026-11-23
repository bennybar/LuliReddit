import SwiftUI

/// The Digest's one-time offer: a card at the top of Posts for people who haven't turned it
/// on, until they answer it. Not in the first day (counted from when the app first asks),
/// not signed out, and not without a favourite community (the digest would be empty).
@MainActor @Observable
final class DigestOffer {
    static let shared = DigestOffer()
    private static let doneKey = "digestOfferDone"
    private static let firstSeenKey = "digestOfferFirstSeen"

    /// Answered (either way): never shown again.
    private(set) var done: Bool

    private init() { done = app.prefs.getBool(Self.doneKey) == true }

    func answer() {
        app.prefs.setBool(Self.doneKey, true)
        done = true
    }

    /// Whether Posts shows it now.
    var shown: Bool {
        let s = app.settings.value
        guard !done, !s.digestEnabled, app.session.session?.anonymous == false else { return false }
        let now = nowMillis()
        let first = app.prefs.getInt(Self.firstSeenKey) ?? {
            app.prefs.setInt(Self.firstSeenKey, now)
            return now
        }()
        guard now - first >= 24 * 60 * 60_000 else { return false }
        return SubscriptionsViewModel.shared.subs.value?.contains(where: \.userHasFavorited) == true
    }
}

/// The card: what Digest is, Try it (the explainer, with Turn on) or No thanks.
struct DigestOfferCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("New: Digest", systemImage: "newspaper").font(.headline)
            Text("The posts that stood out today in your favourite communities, in one short list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("No thanks") { DigestOffer.shared.answer() }
                Button("Try it") {
                    Task {
                        // How Digest works, with Turn on / Not now: either way, answered.
                        let on = await showDigestExplainer(ask: true)
                        DigestOffer.shared.answer()
                        guard on else { return }
                        app.prefs.setBool("digestExplained", true)
                        app.settings.setDigestEnabled(true)
                        DigestNotifications.reschedule()
                        // There it is: the chip's digest, when it's a chip.
                        if app.settings.value.digestPlace == 0 { app.digest.onPosts = true }
                    }
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
