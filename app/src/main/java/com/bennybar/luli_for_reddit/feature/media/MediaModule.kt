package com.bennybar.luli_for_reddit.feature.media

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.state.UserScoped

/** [Agent D] Media singletons (save-to-folder choice, players, …). */
class MediaModule(private val c: AppContainer) : UserScoped {
    override fun onUserChanged(username: String) {}
}
