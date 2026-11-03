import Foundation
import Observation

/// Post/thread singletons: the stored OpenAI key (AI summaries / Ask about this thread).
@MainActor @Observable
final class PostModule {
    /// The OpenAI(-compatible) API key, or nil/empty when AI isn't set up. Account-independent:
    /// so unlike Kotlin's module this one isn't `UserScoped`; every thread re-reads it anyway.
    private(set) var aiKey: String?

    /// The post whose poll was opened on Reddit to vote; its thread refreshes on return.
    @ObservationIgnored var pollVoteOpened: String?

    @ObservationIgnored private let secureStore: SecureStore

    init(_ c: AppContainer) { secureStore = c.secureStore }

    /// Re-reads the key (Settings may have changed it). Cheap; called when a thread opens.
    func refreshAiKey() async { aiKey = await secureStore.openaiKey() }
}
