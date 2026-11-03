import SwiftUI

private let seenPref = "whatsNewSeen"

private func parts(_ v: String) -> [Int] {
    (v.split(separator: " ", omittingEmptySubsequences: false).first ?? "").split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
}

/// Whether release `a` (its first version, for a range) is newer than version `b`.
func newer(_ a: String, _ b: String) -> Bool {
    let x = parts(a), y = parts(b)
    for i in 0..<max(x.count, y.count) {
        let d = (i < x.count ? x[i] : 0) - (i < y.count ? y[i] : 0)
        if d != 0 { return d > 0 }
    }
    return false
}

/// Once after an update: what changed since the version you last saw here
/// (or this release's, the first time). Never on a fresh install.
@MainActor func maybeShowWhatsNew() async {
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let seen = app.prefs.getString(seenPref)
    app.prefs.setString(seenPref, current)
    if seen == current { return }
    let releases: [Release]
    if let seen {
        releases = Array(CHANGELOG.filter { newer($0.version.components(separatedBy: " ").last ?? "", seen) }.prefix(3))
    } else {
        // iOS has no install / update times: an install that already ran the
        // home shell answered the notifications suggestion (which comes after
        // this), so it's an update; otherwise it's a fresh install, and nothing
        // is "new".
        guard app.prefs.getBool("notifyInboxPrompted") == true || app.settings.value.notifyInbox else { return }
        releases = Array(CHANGELOG.prefix(1))
    }
    if releases.isEmpty { return }
    let all: Bool? = await Overlays.show(detents: [.medium, .large]) { done in
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's new in Ilay \(current)").font(.title2.bold())
                    ForEach(releases) { ReleaseNotes(release: $0, showVersion: releases.count > 1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("All changes") { done(true) } }
                ToolbarItem(placement: .confirmationAction) { Button("Got it", role: .confirm) { done(false) } }
            }
        }
    }
    if all == true { app.navigator.push(.whatsNew) }
}

private struct ReleaseNotes: View {
    let release: Release
    var showVersion = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showVersion {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(release.version).bold().foregroundStyle(.tint)
                    Text(release.date).font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(release.highlights, id: \.self) { highlight in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•").foregroundStyle(.tint)
                    Text(highlight)
                }
            }
        }
        .padding(.bottom, 12)
    }
}

/// Settings → About → What's new: every release's highlights.
struct WhatsNewScreen: View {
    var body: some View {
        List(CHANGELOG) { release in
            ReleaseNotes(release: release).padding(.top, 8)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What's new")
    }
}
