package com.bennybar.luli_for_reddit.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

/**
 * Material Symbols' rounded "search" (Material 3's), in place of the older Material
 * Icons glyph (#128). Its path is in the symbols' 960-unit grid, which starts at -960.
 */
val SearchIcon: ImageVector = ImageVector.Builder("SearchRounded", 24.dp, 24.dp, 960f, 960f).apply {
    group(translationY = 960f) {
        addPath(
            PathParser().parsePathString(
                "M380-320q-109 0-184.5-75.5T120-580q0-109 75.5-184.5T380-840q109 0 184.5 75.5T640-580q0 44-14 83t-38 69l224 224q11 11 11 28t-11 28q-11 11-28 11t-28-11L532-372q-30 24-69 38t-83 14Zm0-80q75 0 127.5-52.5T560-580q0-75-52.5-127.5T380-760q-75 0-127.5 52.5T200-580q0 75 52.5 127.5T380-400Z"
            ).toNodes(),
            fill = SolidColor(Color.Black),
        )
    }
}.build()
