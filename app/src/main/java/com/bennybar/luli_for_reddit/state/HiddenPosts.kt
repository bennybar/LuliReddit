package com.bennybar.luli_for_reddit.state

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * Posts hidden this session, filtered out of every feed straight away
 * (hiding on Reddit only takes effect on the next fetch).
 */
class HiddenPosts : UserScoped {
    private val _ids = MutableStateFlow<Set<String>>(emptySet())
    val ids: StateFlow<Set<String>> = _ids
    fun add(id: String) = _ids.update { it + id }
    fun remove(id: String) = _ids.update { it - id }
    override fun onUserChanged(username: String) { _ids.value = emptySet() }
}
