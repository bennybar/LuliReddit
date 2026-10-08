package com.bennybar.luli_for_reddit.data

/** Sort options for post listings. Order matters: persisted by index (`defaultSort`). */
enum class PostSort(val path: String, val label: String) {
    BEST("best", "Best"),
    HOT("hot", "Hot"),
    NEWEST("new", "New"),
    TOP("top", "Top"),
    RISING("rising", "Rising");

    val needsTime: Boolean get() = this == TOP
}

enum class TopTime(val param: String, val label: String) {
    HOUR("hour", "Now"),
    DAY("day", "Today"),
    WEEK("week", "This week"),
    MONTH("month", "This month"),
    YEAR("year", "This year"),
    ALL("all", "All time"),
}

/** Reddit comment sorts: id → label. */
val COMMENT_SORTS: List<Pair<String, String>> = listOf(
    "confidence" to "Best",
    "top" to "Top",
    "new" to "New",
    "controversial" to "Controversial",
    "old" to "Old",
    "qa" to "Q&A",
)
