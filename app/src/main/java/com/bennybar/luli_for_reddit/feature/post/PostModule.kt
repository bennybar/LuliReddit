package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.state.UserScoped

/** [Agent B] Post/thread singletons (AI service, …). */
class PostModule(private val c: AppContainer) : UserScoped {
    override fun onUserChanged(username: String) {}
}
