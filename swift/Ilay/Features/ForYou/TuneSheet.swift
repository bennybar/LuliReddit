import SwiftUI
import UIKit

/// "Tune For You" for one post: why it's here, and explicit More/Less for
/// its subreddit and its most distinctive topics (one "less" no longer
/// demotes every word of the title), plus mute.
@MainActor func showTuneSheet(_ post: Post) {
    // The title's 1–2 most distinctive words: rare ones say more than "help".
    let idf = app.forYou.docFreq.idfFunction()
    let topics = Array(titleKeywords(post.title).uniqued().sorted { idf($0) > idf($1) }.prefix(2))
    Task {
        // What was picked runs after the sheet has gone, so its snackbar shows on the feed.
        let after: (() -> Void)? = await Overlays.show(detents: [.medium, .large]) { done in
            TuneSheet(post: post, topics: topics, close: done)
        }
        after?()
    }
}

private struct TuneSheet: View {
    let post: Post
    let topics: [String]
    let close: ((() -> Void)?) -> Void

    private var m: ForYouModule { app.forYou }

    private func toast(_ message: String) {
        let nav = app.navigator
        nav.showSnackbar(message, actionLabel: "Manage") { nav.push(.manageForYou) }
    }

    var body: some View {
        let sub = post.subreddit
        let learner = m.forYouLearner
        let explicit = m.explicit.value
        let subPref = explicit.subs[sub.lowercased()] ?? 0
        let muted = m.muted.contains(sub)
        let why = m.meta[post.id]?.why ?? []

        NavigationStack {
            List {
                if !why.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach(why, id: \.self) { Text($0).foregroundStyle(.secondary) }
                        } label: {
                            Label("Why am I seeing this?", systemImage: "questionmark.circle")
                        }
                    }
                }
                Section {
                    prefRow("More from r/\(sub)", "hand.thumbsup", on: subPref > 0) {
                        close {
                            learner.subPreference(post, subPref > 0 ? 0 : 1)
                            toast(subPref > 0 ? "Cleared" : "We'll show more from r/\(sub)")
                        }
                    }
                    prefRow("Less from r/\(sub)", "hand.thumbsdown", on: subPref < 0) {
                        close {
                            learner.subPreference(post, subPref < 0 ? 0 : -1)
                            toast(subPref < 0 ? "Cleared" : "We'll show less from r/\(sub)")
                        }
                    }
                }
                if !topics.isEmpty {
                    Section {
                        ForEach(topics, id: \.self) { topic in
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("“\(topic)”")
                                        Text("This topic, in any community").font(.footnote).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "number")
                                }
                                Spacer()
                                ForEach([1, -1], id: \.self) { v in
                                    let on = explicit.topics[topic] == v
                                    Button {
                                        close {
                                            learner.topicPreference(topic, on ? 0 : v)
                                            toast(on ? "Cleared" : "We'll show \(v > 0 ? "more" : "less") about “\(topic)”")
                                        }
                                    } label: {
                                        Image(systemName: "hand.thumbs\(v > 0 ? "up" : "down")\(on ? ".fill" : "")")
                                            .frame(minWidth: 36, minHeight: 36)
                                    }
                                    .buttonStyle(.borderless)
                                    .tint(on ? .accentColor : .secondary)
                                    .accessibilityLabel("\(v > 0 ? "More about" : "Less about") “\(topic)”")
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        close {
                            m.muted.toggle(sub)
                            toast(muted ? "r/\(sub) unmuted" : "r/\(sub) muted from For You")
                        }
                    } label: {
                        Label(muted ? "Unmute r/\(sub)" : "Mute r/\(sub) in For You", systemImage: muted ? "speaker.wave.2" : "speaker.slash")
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Tune For You")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    private func prefRow(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .foregroundStyle(.primary)
    }
}
