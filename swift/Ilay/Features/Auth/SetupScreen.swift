import SwiftUI
import UniformTypeIdentifiers

/// Set once the setup has run (or been skipped), and for anyone who already had an account.
let setupDoneKey = "setupDone"

/// Whether a fresh install still gets the setup before signing in (#114).
@MainActor func needsSetup() -> Bool { app.prefs.getBool(setupDoneKey) != true }

/// The first-run setup (#114): welcome, restore a backup, the look, getting around and
/// the front page, then sign-in. Every page can be skipped; it all stays in Settings.
struct SetupScreen: View {
    let onDone: () -> Void

    @State private var step = 0
    private let last = 4

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: Welcome { advance() }
                case 1: RestorePage(onRestored: finish) { advance() }
                case 2: SetupPage(title: "Make It Yours", subtitle: "Light or dark, and your colour. It's all in Settings later too.", next: advance) { LookSection() }
                case 3: SetupPage(title: "Getting Around", subtitle: "How you move between Posts, Explore, Inbox and Profile, and how posts look.", next: advance) { LayoutSection() }
                default: SetupPage(title: "Your Front Page", subtitle: "What Posts shows first. You can switch any time.", nextLabel: "Sign In", next: finish) { FeedSection() }
                }
            }
            .animation(.smooth, value: step)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") { step -= 1 }
                    }
                    ToolbarItem(placement: .principal) {
                        ProgressView(value: Double(step), total: Double(last)).frame(width: 120)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip", action: finish)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func advance() { step = min(step + 1, last) }

    private func finish() {
        app.prefs.setBool(setupDoneKey, true)
        onDone()
    }
}

private struct Welcome: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AppIconPreview(icon: AppIcon.parse(app.settings.value.appIcon), size: 96)
            Text("Welcome to Ilay")
                .font(.largeTitle.bold())
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 22) {
                feature("text.bubble", "Calm threads", "Comments in tidy cards that are easy to follow.")
                feature("sparkles", "For You", "A front page built on your phone from what you read.")
                feature("paintpalette", "Yours", "Your colours, your layout. A few quick choices next.")
            }
            .padding(.top, 36)
            .padding(.horizontal, 32)
            Spacer()
            BottomButton("Get Started", action: next)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RestorePage: View {
    let onRestored: () -> Void
    let skip: () -> Void
    @State private var importing = false

    var body: some View {
        SetupPage(
            title: "Coming From Another Phone?",
            subtitle: "Restore an Ilay backup to bring your settings, For You and history. Sign-in and keys aren't in backups.",
            nextLabel: "I Don't Have a Backup",
            next: skip
        ) {
            Section {
                Button("Restore a Backup", systemImage: "clock.arrow.circlepath") { importing = true }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data, .text]) { result in
            Task {
                await restoreData(result)
                if (try? result.get()) != nil { onRestored() }
            }
        }
    }
}

/// Light / dark and the accent: the system's own colour picker for any colour.
private struct LookSection: View {
    var body: some View {
        let s = app.settings.value
        Section("Appearance") {
            Picker("Theme", selection: Binding(get: { s.themeMode }, set: app.settings.setThemeMode)) {
                Text("System").tag(ThemeMode.system)
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)
        }
        Section("Accent Colour") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(accentSwatches, id: \.argb) { swatch in
                    Button {
                        app.settings.setSeedColor(swatch.argb)
                    } label: {
                        Circle()
                            .fill(Color(argb: swatch.argb))
                            .frame(width: 44, height: 44)
                            .overlay {
                                if s.seedColor == swatch.argb {
                                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(s.seedColor == swatch.argb ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            ColorPicker("Any Colour", selection: Binding(
                get: { Color(argb: s.seedColor) },
                set: { app.settings.setSeedColor(argbOf($0)) }
            ), supportsOpacity: false)
        }
        Section {
            // A preview in the colours being picked.
            HStack(spacing: 12) {
                Button("Join") {}.buttonStyle(.borderedProminent)
                Button("Save", systemImage: "bookmark") {}.buttonStyle(.bordered)
                Spacer()
                Image(systemName: "arrow.up").foregroundStyle(.tint)
                Text("4.2k").monospacedDigit()
            }
            .allowsHitTesting(false)
        } header: {
            Text("Preview")
        }
    }

    /// An opaque ARGB int, as `seedColor` keeps it.
    private func argbOf(_ color: Color) -> Int {
        let c = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return 0xFF00_0000 | byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

/// Navigation (tab bar / side bar / both) and the post layout.
private struct LayoutSection: View {
    var body: some View {
        let s = app.settings.value
        Section("Navigation") {
            Picker("Navigation", selection: Binding(get: { min(max(s.navStyle, 0), 2) }, set: app.settings.setNavStyle)) {
                ForEach(navStyles.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(navStyles[i].0)
                        Text(navStyles[i].1).font(.footnote).foregroundStyle(.secondary)
                    }
                    .tag(i)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Section("Posts") {
            Picker("Posts", selection: Binding(get: { s.postDisplay }, set: app.settings.setPostDisplay)) {
                ForEach(PostDisplay.allCases, id: \.self) { d in
                    Label(d.label, systemImage: d.icon).tag(d)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

/// For You, and Reddit Home (with its warning) and Blend.
private struct FeedSection: View {
    var body: some View {
        let s = app.settings.value
        Section {
            Toggle(isOn: Binding(get: { s.forYouFeed }, set: app.settings.setForYouFeed)) {
                Text("For You")
                Text("Ilay picks posts from your subscriptions and what you read, instead of Reddit's Best")
            }
        }
        Section {
            Toggle(isOn: Binding(get: { s.redditHomeAllowed }, set: { v in
                if !v {
                    app.settings.setRedditHomeAllowed(false)
                    return
                }
                Task { if await confirmRedditHome() { app.settings.setRedditHomeAllowed(true) } }
            })) {
                Text("Reddit Home (experimental)").foregroundStyle(homeAmber)
                Text("Your real reddit.com Home feed, with the website sign-in")
            }
            if s.redditHomeAllowed {
                Toggle(isOn: Binding(get: { s.forYouFeed && s.blendHome }, set: { v in
                    app.settings.setBlendHome(v)
                    if v { app.settings.setForYouFeed(true) }
                })) {
                    Text("Blend (Beta)")
                    Text("For You also ranks your Reddit Home: Reddit's recommendations, under your For You choices")
                }
            }
        }
    }
}

/// A step: its title and why above an inset-grouped list, and the button on to the next.
private struct SetupPage<Content: View>: View {
    let title: String
    let subtitle: String
    var nextLabel = "Continue"
    let next: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Wrapped, not cut off: a list row keeps text to one line otherwise.
                    Text(title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }
            content()
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { BottomButton(nextLabel, action: next) }
    }
}

private struct BottomButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}
