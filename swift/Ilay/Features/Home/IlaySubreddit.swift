import SwiftUI

/// Ilay's own subreddit: news, help, bug reports and ideas.
let ilaySubreddit = "IlayFR"
private let announcedPref = "ilaySubredditAnnounced"

/// Already a member (from the subscription list, usually loaded already for Explore).
@MainActor func inIlaySubreddit() async -> Bool {
    guard app.session.session?.anonymous == false else { return false }
    let subs = (try? await app.repository.getSubscribedSubreddits()) ?? []
    return subs.contains { $0.name.caseInsensitiveCompare(ilaySubreddit) == .orderedSame }
}

/// Joins r/IlayFR (signed out, or already in: opens it), with Open on the snackbar.
@MainActor func joinIlaySubreddit() async {
    let nav = app.navigator
    let member = await inIlaySubreddit()
    if app.session.session?.anonymous != false || member {
        nav.push(.subreddit(name: ilaySubreddit))
        return
    }
    do {
        try await app.repository.setSubscribed(ilaySubreddit, subscribe: true)
        nav.showSnackbar("Joined r/\(ilaySubreddit)", actionLabel: "Open") { nav.push(.subreddit(name: ilaySubreddit)) }
    } catch {
        nav.showActionError("join r/\(ilaySubreddit)", error)
    }
}

/// Once, on a launch: Ilay has a subreddit. Join (or Open, signed out), or Not now; never asked again.
@MainActor func maybeAnnounceIlaySubreddit() async {
    let prefs = app.prefs
    if prefs.getBool(announcedPref) == true { return }
    prefs.setBool(announcedPref, true)
    if await inIlaySubreddit() { return }
    let signedIn = app.session.session?.anonymous == false
    let join = await Overlays.alert(
        "Ilay has a subreddit",
        message: "r/\(ilaySubreddit) is the place for Ilay news, help, bug reports and ideas."
            + (signedIn ? " Join to see it in your feed." : "")
            + "\n\nYou can join anytime from Settings › About.",
        buttons: [(title: "Not now", role: .cancel, value: false), (title: signedIn ? "Join" : "Open", role: nil, value: true)]
    )
    if join == true { await joinIlaySubreddit() }
}
