import AuthenticationServices
import UIKit

/// Browser-based OAuth, like flutter_web_auth_2: opens Reddit's authorize page
/// in an ASWebAuthenticationSession, which hands the `luli://` (or `redreader://`)
/// redirect straight back to us (no registered URL scheme needed, so the Debug
/// build logs in too) and reports a real cancel when it's closed.
@MainActor
enum OAuthFlow {
    private static var current: ASWebAuthenticationSession?

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }

    private static let anchor = Anchor()

    /// Returns the redirect URL. [ephemeral] = don't reuse the browser's Reddit
    /// cookies, so adding a second account can sign into a *different* account.
    static func authenticate(_ url: URL, scheme: String, ephemeral: Bool) async throws -> URL {
        current?.cancel()
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callback, error in
                current = nil
                if let callback {
                    cont.resume(returning: callback)
                } else {
                    cont.resume(throwing: error ?? AppException("No valid browser available for authentication."))
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = ephemeral
            current = session
            if !session.start() {
                current = nil
                cont.resume(throwing: AppException("No valid browser available for authentication."))
            }
        }
    }
}
