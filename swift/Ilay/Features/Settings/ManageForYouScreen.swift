import SwiftUI

/// Everything that shapes the "For You" feed, visible and undoable:
/// explicit choices, mutes, learned topics and communities, and a full reset.
/// All local and per-account. Long-press the title for local metrics.
struct ManageForYouScreen: View {
    private var m: ForYouModule { app.forYou }

    var body: some View {
        let explicit = m.explicit.value
        let muted = m.muted.value.sorted()
        let keywords = m.keywords.value
        // Re-rank topics as rarity changes.
        let df = m.docFreq
        let _ = df.state
        // Learned topics, by how much they actually matter: weight × rarity.
        let topics = Array(keywords.filter { abs($0.value) >= 1 }
            .sorted { abs($0.value) * df.idf($0.key) > abs($1.value) * df.idf($1.key) }
            .prefix(20))
        let weights = m.interest.value
        let less = weights.filter { $0.value < 0 }.sorted { $0.value < $1.value }
        let more = weights.filter { $0.value >= 3 }.sorted { $0.value > $1.value }
        let empty = explicit.isEmpty && muted.isEmpty && topics.isEmpty && less.isEmpty && more.isEmpty

        List {
            if empty {
                ContentUnavailableView(
                    "Nothing to manage yet",
                    systemImage: "slider.horizontal.3",
                    description: Text("Long-press a For You post to tune it, or use its ⋯ menu. Your choices and what For You learns will show up here.")
                )
                .listRowBackground(Color.clear)
            }
            if !explicit.isEmpty {
                section("Your choices", "What you asked for with More / Less — these don't fade") {
                    ForEach(explicit.subs.keys, id: \.self) { sub in
                        let v = explicit.subs[sub] ?? 0
                        row(thumb: v, "r/\(sub)", v > 0 ? "More from here" : "Less from here") {
                            Button("Remove") { m.explicit.setSub(sub, 0) }
                        }
                    }
                    ForEach(explicit.topics.keys, id: \.self) { topic in
                        let v = explicit.topics[topic] ?? 0
                        row(thumb: v, "“\(topic)”", v > 0 ? "More about this" : "Less about this") {
                            Button("Remove") { m.explicit.setTopic(topic, 0) }
                        }
                    }
                }
            }
            if !muted.isEmpty {
                section("Muted", "Hidden from For You entirely") {
                    ForEach(muted, id: \.self) { sub in
                        row("speaker.slash", "r/\(sub)") {
                            Button("Unmute") { m.muted.toggle(sub) }
                        }
                    }
                }
            }
            if !topics.isEmpty {
                section("Topics", "Learned from the titles you engage with") {
                    ForEach(topics, id: \.key) { e in
                        row(e.value > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis", "“\(e.key)”") {
                            HStack(spacing: 14) {
                                Button("Reset") { m.keywords.reset(e.key) }
                                Button("Block") {
                                    m.keywords.reset(e.key)
                                    m.explicit.setTopic(e.key, -1)
                                }
                            }
                        }
                    }
                }
            }
            if !less.isEmpty {
                section("Showing less", "Learned from what you skip or downvote") {
                    ForEach(less, id: \.key) { e in
                        row("hand.thumbsdown", "r/\(e.key)") {
                            Button("Reset") { m.interest.reset(e.key) }
                        }
                    }
                }
            }
            if !more.isEmpty {
                section("Showing more", "Learned favourites — reset to forget") {
                    ForEach(more, id: \.key) { e in
                        row("hand.thumbsup", "r/\(e.key)") {
                            Button("Reset") { m.interest.reset(e.key) }
                        }
                    }
                }
            }
            Section {
                Button("Reset For You", systemImage: "arrow.counterclockwise") {
                    Task { await confirmReset() }
                }
            } footer: {
                Text("Learned signals fade by half in about two weeks; your explicit choices and mutes don't. Everything here stays on this device.")
            }
        }
        .listStyle(.insetGrouped)
        .buttonStyle(.borderless)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Manage For You")
                    .font(.headline)
                    .onLongPressGesture { showMetrics() }
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func section<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title)
        } footer: {
            Text(subtitle)
        }
    }

    private func row<Trailing: View>(_ systemImage: String, _ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            trailing()
        }
    }

    /// An explicit choice: its thumb, what it means.
    private func row<Trailing: View>(thumb v: Int, _ title: String, _ subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: v > 0 ? "hand.thumbsup" : "hand.thumbsdown")
                    .foregroundStyle(v > 0 ? Color.accentColor : Color.red)
            }
            Spacer()
            trailing()
        }
    }

    private func confirmReset() async {
        let ok = await confirmDialog(
            "Reset For You?",
            "Forgets everything For You learned and your More / Less choices. Mutes are kept.",
            "Reset",
            destructive: true
        )
        if !ok { return }
        m.interest.clear()
        m.keywords.clear()
        m.impressions.clear()
        m.explicit.clear()
        m.subStats.clear()
        m.typeStats.clear()
    }

    /// Local, never-uploaded counters for judging For You changes.
    private func showMetrics() {
        let metrics = m.metrics
        let t = metrics.totals()
        func n(_ k: String) -> Int { t[k] ?? 0 }
        func rate(_ opens: String, _ impr: String) -> String {
            let i = n(impr)
            return i == 0 ? "–" : String(format: "%.1f%%", 100.0 * Double(n(opens)) / Double(i))
        }
        var rows: [(String, String)] = [
            ("Seen (primary / discovery)", "\(n("impr.primary")) / \(n("impr.discovery"))"),
            ("Open rate (primary)", rate("open.primary", "impr.primary")),
            ("Open rate (discovery)", rate("open.discovery", "impr.discovery")),
            ("Read 30s+ (primary / discovery)", "\(n("read30.primary")) / \(n("read30.discovery"))"),
            ("Votes", "\(n("vote.primary") + n("vote.discovery"))"),
            ("More / Less taps", "\(n("more")) / \(n("less"))"),
            ("Discovery appetite", String(format: "%.2f", metrics.discoveryAppetite())),
        ]
        for e in t.filter({ $0.key.hasPrefix("src.ranked.") }).sorted(by: { $0.value > $1.value }) {
            rows.append(("Placed from \(e.key.dropFirst(11))", "\(e.value)"))
        }
        let shown = rows
        Overlays.launch(detents: [.medium, .large]) { _ in
            NavigationStack {
                List {
                    Section {
                        ForEach(shown, id: \.0) { LabeledContent($0.0, value: $0.1) }
                    } footer: {
                        Text("On this device only. Never uploaded.")
                    }
                }
                .navigationTitle("For You · last 7 days")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
