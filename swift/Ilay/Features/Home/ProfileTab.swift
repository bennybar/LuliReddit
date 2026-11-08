import SwiftUI

/// The Profile tab: your profile (Posts, Comments, Saved) under a bar with a
/// Library menu (Upvoted, Downvoted, and what's kept on this device) and
/// Settings; your name opens the account switcher. Browsing without an
/// account: sign in, plus your stuff.
struct ProfileTab: View {
    @Environment(AppNavigator.self) private var nav
    @State private var tab = "Posts"

    var body: some View {
        let session = app.session.session
        let username = session?.username ?? ""
        let anonymous = session?.anonymous ?? false

        Group {
            if anonymous || username.isEmpty {
                List {
                    Section {
                        SignInPrompt(message: "You're browsing without an account. Sign in to vote, comment, save, see your inbox and get your own frontpage.")
                    }
                    Section("Your stuff") {
                        navTile("clock.arrow.circlepath", "History", "Recently viewed (stored on this device)", .history)
                        navTile("arrow.down.circle", "Read later", "Threads saved for offline reading", .offline)
                        navTile("sparkles", "Summaries", "Posts you summarized with AI, and their summaries", .summaries)
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                UserProfileBody(username: username, scrollTop: app.navigator.tabReselect[3], tab: $tab) {
                    Task { await showAccountSheet(current: username) }
                }
                .id(username)
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SideBarButton() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !anonymous && !username.isEmpty { library }
                SettingsButton()
            }
        }
    }

    private func navTile(_ systemImage: String, _ title: String, _ subtitle: String, _ route: Route) -> some View {
        NavigationLink(value: route) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    /// Your Upvoted and Downvoted lists (shown in the profile), then what's kept on
    /// this device: History, Read later, Drafts, Summaries and saved search.
    private var library: some View {
        // Reading `changes` keeps the count live.
        let drafts = app.drafts.changes >= 0 ? app.drafts.list().count : 0
        return Menu("Library", systemImage: "books.vertical") {
            Section {
                Button("Upvoted", systemImage: "arrow.up") { tab = "Upvoted" }
                Button("Downvoted", systemImage: "arrow.down") { tab = "Downvoted" }
            }
            Section {
                Button("History", systemImage: "clock.arrow.circlepath") { nav.push(.history) }
                Button("Read later", systemImage: "arrow.down.circle") { nav.push(.offline) }
                Button(drafts == 0 ? "Drafts" : "Drafts · \(drafts)", systemImage: "square.and.pencil") { nav.push(.drafts) }
                Button("Summaries", systemImage: "sparkles") { nav.push(.summaries) }
                Button("Search saved", systemImage: "bookmark") { nav.push(.saved) }
            }
        }
    }
}

private enum AccountAction {
    case switchTo(String)
    case remove(String)
    case add
}

/// What to do runs once the sheet has closed.
@MainActor private func showAccountSheet(current: String) async {
    let action: AccountAction? = await Overlays.show(detents: [.medium, .large]) { done in
        AccountSheet(current: current, onAction: done)
    }
    switch action {
    case let .switchTo(username): await app.session.switchAccount(username)
    case let .remove(username): await confirmRemove(username)
    case .add: await addAccount()
    case nil: break
    }
}

private struct AccountSheet: View {
    let current: String
    let onAction: (AccountAction?) -> Void

    @State private var accounts: [String]

    init(current: String, onAction: @escaping (AccountAction?) -> Void) {
        self.current = current
        self.onAction = onAction
        _accounts = State(initialValue: [current])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accounts, id: \.self) { account in
                        HStack(spacing: 12) {
                            Button {
                                if account != current { onAction(.switchTo(account)) }
                            } label: {
                                HStack(spacing: 12) {
                                    LetterAvatar(name: account, size: 40)
                                    Text("u/\(account)")
                                        .foregroundStyle(account == current ? Color.accentColor : Color.primary)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(account == current ? .isSelected : [])
                            if account == current {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            } else {
                                // Removing another account confirms over the sheet (Cancel returns to it).
                                Button("Remove", systemImage: "xmark.circle") {
                                    Task { await confirmRemove(account) }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("Add account", systemImage: "person.badge.plus") { onAction(.add) }
                    Button("Log out of u/\(current)", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        onAction(.remove(current))
                    }
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: app.session.accountsVersion) {
            let list = await app.session.accounts()
            accounts = list.isEmpty ? [current] : list
        }
    }
}

@MainActor private func addAccount() async {
    do {
        if await app.session.authMode() == "web" {
            // Match the current method: website-session add with fresh cookies
            // (the web login screen signs the new account in and reports
            // "Could not add account: …" itself — this push returns at once).
            app.navigator.push(.webLogin(clearFirst: true))
        } else {
            try await app.session.addAccount()
        }
    } catch {
        app.navigator.showSnackbar("Could not add account: \(error.localizedDescription)")
    }
}

@MainActor private func confirmRemove(_ username: String) async {
    let ok = await confirmDialog(
        "Log out of u/\(username)?",
        "This removes the account from this device. Your saved API credentials stay so you can add it again.",
        "Log out",
        destructive: true
    )
    if ok { await app.session.removeAccount(username) }
}

/// Shown where an account is needed while browsing without one: explains it
/// and offers to sign in (which goes back to the login screen).
struct SignInPrompt: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Browsing without an account", systemImage: "binoculars").font(.headline)
            Text(message)
            // Ends the anonymous session; the app then shows login (the
            // Client ID stays filled in).
            Button("Sign in", systemImage: "person.crop.circle") {
                Task { await app.session.logout() }
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.vertical, 4)
    }
}
