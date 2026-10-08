package com.bennybar.luli_for_reddit.feature.feed

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.state.UserScoped

/** [Agent A] Feed/home singletons (feed state holders, tab re-select signals, …). */
class FeedModule(private val c: AppContainer) : UserScoped {
    override fun onUserChanged(username: String) {}
}
