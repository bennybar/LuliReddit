package com.bennybar.luli_for_reddit.feature.inbox

/** A GIF or a picture someone replied with, as the inbox shows it instead of its link (#313). */
enum class InboxMedia(val label: String) { GIF("GIF"), IMAGE("Image") }

/**
 * An inbox item's one-line preview: Reddit's media markdown (`![gif](giphy|…)`,
 * `![img](…)`) and bare GIF or picture links read "GIF" / "Image" instead of
 * the raw link (#313). [media] is set when that's all the reply is, so the row
 * shows the icon with the word.
 */
data class InboxSnippet(val text: String, val media: InboxMedia?) {
    companion object {
        private val markdownMedia = Regex("""!\[(gif|img)]\(([^)\s]*)\)""", RegexOption.IGNORE_CASE)
        private val gifLink = Regex(
            """https?://(?:[a-z0-9]+\.)?giphy\.com/\S+|https?://(?:i|preview)\.redd\.it/\S+\.gif\S*|https?://i\.imgur\.com/\S+\.gifv?\b\S*""",
            RegexOption.IGNORE_CASE,
        )
        private val imageLink = Regex(
            """https?://(?:i|preview)\.redd\.it/\S+|https?://i\.imgur\.com/\S+\.(?:png|jpe?g|webp)\b\S*""",
            RegexOption.IGNORE_CASE,
        )

        fun of(body: String): InboxSnippet {
            val found = mutableListOf<InboxMedia>()
            var text = markdownMedia.replace(body) { m ->
                val gif = m.groupValues[1].equals("gif", ignoreCase = true)
                // `![img](emote|…)` is a community emoji inside text, not a picture.
                if (!gif && m.groupValues[2].startsWith("emote|")) return@replace ""
                (if (gif) InboxMedia.GIF else InboxMedia.IMAGE).also { found += it }.label
            }
            text = gifLink.replace(text) { found += InboxMedia.GIF; InboxMedia.GIF.label }
            text = imageLink.replace(text) { found += InboxMedia.IMAGE; InboxMedia.IMAGE.label }
            text = text.replace('\n', ' ').replace(Regex(" {2,}"), " ").trim()
            val only = found.singleOrNull()?.takeIf { text == it.label }
            return InboxSnippet(text, only)
        }
    }
}
