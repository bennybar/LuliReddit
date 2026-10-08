package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Post/thread singletons: the stored OpenAI key (AI summaries / Ask about this thread). */
class PostModule(private val c: AppContainer) : UserScoped {
    private val _aiKey = MutableStateFlow<String?>(null)

    /** The OpenAI(-compatible) API key, or null/empty when AI isn't set up. Account-independent. */
    val aiKey: StateFlow<String?> = _aiKey

    /** Re-reads the key (Settings may have changed it). Cheap; called when a thread opens. */
    fun refreshAiKey() {
        c.scope.launch { _aiKey.value = c.secureStore.openaiKey() }
    }

    override fun onUserChanged(username: String) {
        refreshAiKey()
    }
}
