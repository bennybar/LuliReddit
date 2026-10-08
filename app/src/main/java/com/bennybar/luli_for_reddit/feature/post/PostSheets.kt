package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post

/**
 * [Agent B] Reply composer (bottom sheet) for a post (t3_) or comment (t1_).
 * Supports image (inline via Reddit richtext) / video (Catbox) attachments,
 * GIFs, drafts. Returns the created comment (at depth parentDepth + 1), or
 * null if dismissed. Implemented with ui.Overlays.
 */
suspend fun showReplySheet(parentFullname: String, parentDepth: Int, replyingTo: String? = null): Comment? = null

/** [Agent B] Editor for your own post/comment body. Returns the new text, or null. */
suspend fun showEditSheet(thingFullname: String, initialText: String): String? = null

/**
 * [Agent B] The post overflow sheet: share, save, hide, report, crosspost,
 * open in browser, block, mod actions, save offline, etc.
 */
fun showPostActionsSheet(post: Post) {}

/** [Agent B] Hides [post] on Reddit and in open feeds (app.hiddenPosts), with Undo. */
suspend fun hidePost(post: Post) {}

/** [Agent B] Confirms and blocks a user. Reusable from posts, comments and profiles. */
suspend fun confirmBlockUser(username: String) {}
