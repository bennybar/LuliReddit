import SwiftUI

/// The first-run flow: the user connects their own Reddit API app (client id
/// + redirect uri, optional Giphy key), or signs in through the website, or
/// browses without an account. The root navigates on its own once a session
/// exists.
struct LoginScreen: View {
    private enum Field { case clientId, redirect, giphy }

    @Environment(AppNavigator.self) private var nav
    @FocusState private var focus: Field?

    @State private var clientId = ""
    @State private var redirect = RedditConstants.defaultRedirectUri
    @State private var giphy = ""
    @State private var busy = false
    @State private var error: String?
    @State private var checkResult: String?
    @State private var checkOk = false
    // Two equal ways in. New users default to the website (Reddit no longer
    // hands out new API keys); someone with a saved Client ID gets the API form.
    @State private var useApi = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    AppIconPreview(icon: AppIcon.parse(app.settings.value.appIcon), size: 72)
                    Text("Ilay for Reddit").font(.largeTitle.bold())
                    Text("Sign in with your Reddit account. Both ways work the same once you're in.")
                        .foregroundStyle(.secondary)
                    ConnectedChoice(
                        options: [(false, "Reddit website"), (true, "API key")],
                        selected: useApi,
                        onSelect: { useApi = $0; error = nil }
                    )
                    .padding(.top, 8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if useApi { apiForm } else { websiteForm }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        // Prefill whatever was saved before (a retry, or after signing out).
        .task {
            let store = app.secureStore
            if let saved = await store.clientId() {
                clientId = saved
                if !saved.isBlank { useApi = true }
            }
            if let saved = await store.redirectUri() { redirect = saved }
            if let saved = await store.giphyKey() { giphy = saved }
        }
    }

    // MARK: - Website

    @ViewBuilder private var websiteForm: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in on reddit.com").font(.headline)
                Text("Reddit's own sign-in page opens inside Ilay. No API key needed, and your password goes only to Reddit.")
                    .font(.subheadline)
                Text("This uses the website rather than Reddit's official API. It can stop working if Reddit changes its site, and Reddit could treat it as against its usage policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        if let error { Banner(ok: false, text: error) }
        Section {
            // Website-session login (no API key): a Reddit login page inside Ilay,
            // which stores the session itself. Its caveat is shown above.
            WideButton(title: "Sign in with Reddit", systemImage: "person.crop.circle", prominent: true) {
                nav.push(.webLogin())
            }
            .disabled(busy)
            .bareRow()
        }
    }

    // MARK: - API key

    @ViewBuilder private var apiForm: some View {
        Section { SetupCard(redirectUri: redirect) }

        Section("Reddit Client ID") {
            HStack {
                TextField("e.g. AbCdEf123...", text: $clientId)
                    .focused($focus, equals: .clientId)
                    .plainInput()
                PasteButton(payloadType: String.self) { strings in
                    if let text = strings.first?.trimmed, !text.isEmpty { clientId = text }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
            }
        }

        Section {
            TextField(RedditConstants.defaultRedirectUri, text: $redirect)
                .focused($focus, equals: .redirect)
                .plainInput()
                .keyboardType(.URL)
            // A RedReader-issued client ID only redirects to RedReader's URI.
            Button("Using a RedReader client ID?", systemImage: "arrow.left.arrow.right") {
                redirect = RedditConstants.redReaderRedirectUri
            }
        } header: {
            Text("Redirect URI")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Must match the redirect URI registered on your Reddit app.")
                if redirect.trimmed.hasPrefix("redreader:") {
                    // No "which app?" question here, unlike Android: the sign-in
                    // session hands the redirect straight back to Ilay.
                    Text("This client ID was issued to RedReader, and Reddit could revoke it.")
                }
            }
        }

        Section("Giphy API Key (optional)") {
            TextField("Enables GIF picker", text: $giphy)
                .focused($focus, equals: .giphy)
                .plainInput()
        }

        if let checkResult { Banner(ok: checkOk, text: checkResult) }
        if let error { Banner(ok: false, text: error) }

        Section {
            VStack(spacing: 12) {
                WideButton(title: "Test configuration", systemImage: "checkmark.seal", prominent: false, action: checkConfig)
                WideButton(title: busy ? "Working…" : "Connect Reddit account", systemImage: "person.crop.circle", prominent: true, busy: busy, action: login)
                // Read-only browsing uses the same Client ID.
                Button("Browse without signing in", systemImage: "binoculars", action: browseAnonymously)
                    .padding(.top, 4)
            }
            .disabled(busy)
            .bareRow()
        }
    }

    // MARK: - Actions

    private func checkConfig() {
        focus = nil
        busy = true
        error = nil
        checkResult = nil
        Task {
            let result = await app.authRepository.validateClientId(clientId)
            busy = false
            checkOk = result.valid
            checkResult = result.message
        }
    }

    private func login() {
        focus = nil
        let id = clientId.trimmed
        let uri = redirect.trimmed
        if id.isEmpty {
            error = "Enter your Reddit Client ID first."
            return
        }
        if uri.isEmpty {
            error = "A Redirect URI is required."
            return
        }
        if !uri.contains("://") {
            error = "The Redirect URI looks invalid — it should look like \(RedditConstants.defaultRedirectUri)"
            return
        }
        busy = true
        error = nil
        Task {
            // Pre-flight: confirm the client id is a valid installed-app credential
            // before launching the browser, so we can give a precise error.
            let check = await app.authRepository.validateClientId(id)
            if !check.valid {
                busy = false
                error = check.message
                return
            }
            do {
                // Persist credentials early so a retry keeps them.
                await app.secureStore.saveCredentials(clientId: id, redirectUri: uri, giphyKey: giphy.trimmed)
                try await app.session.login(clientId: id, redirectUri: uri)
                // The root navigates to Home automatically on success.
            } catch let e as AuthException {
                busy = false
                error = e.message
            } catch {
                busy = false
                self.error = "Login failed: \(error.localizedDescription)"
            }
        }
    }

    // Read-only browsing with just a Client ID (Reddit refuses anonymous
    // requests without one). Voting, commenting and the inbox need an account.
    private func browseAnonymously() {
        focus = nil
        if clientId.trimmed.isEmpty {
            error = "Browsing without an account still needs a Reddit Client ID — enter it above."
            return
        }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await app.session.browseAnonymously(clientId: clientId.trimmed)
            } catch {
                self.error = friendlyError(error)
            }
        }
    }
}

/// "How to get your Client ID": an expandable row with the setup steps.
private struct SetupCard: View {
    let redirectUri: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Open reddit.com/prefs/apps and tap \"create app\".")
                step(2, "Choose the \"installed app\" type (no secret needed).")
                step(3, "Set the redirect URI to exactly:  \(redirectUri)")
                step(4, "Create it. The Client ID is the string just under the app name.")
                step(5, "Paste that Client ID below and connect.")
                Link(destination: URL(string: "https://www.reddit.com/prefs/apps")!) {
                    Label("Open Reddit app settings", systemImage: "arrow.up.right.square")
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        } label: {
            Label("How to get your Client ID", systemImage: "questionmark.circle")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n).").font(.subheadline.bold()).foregroundStyle(.secondary)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if text.contains(RedditConstants.callbackScheme) {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = RedditConstants.defaultRedirectUri
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
    }
}

/// A result or error, in its own section.
private struct Banner: View {
    let ok: Bool
    let text: String

    var body: some View {
        Section {
            Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(ok ? Color.green : Color.red)
        }
    }
}

private struct WideButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    var busy = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView() } else { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        if prominent { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.glass) }
    }
}

private extension View {
    /// Client IDs, URIs and keys: typed exactly as they are.
    func plainInput() -> some View {
        textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    /// A form row that's only its buttons.
    func bareRow() -> some View {
        listRowBackground(Color.clear).listRowInsets(EdgeInsets())
    }
}
