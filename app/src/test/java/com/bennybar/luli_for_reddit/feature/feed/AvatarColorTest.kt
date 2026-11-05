package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AvatarColorTest {
    @Test
    fun `a name keeps its colour, picked like the comment author dots`() {
        assertEquals(Color(0xFFC46A96), avatarColor("AskReddit"))
        assertEquals(Color(0xFF5FA85A), avatarColor("pics"))
        assertEquals(Color(0xFF7C5CE0), avatarColor("spez"))
        assertEquals(avatarColor("pics"), avatarColor("pics"))
        assertNotEquals(avatarColor("pics"), avatarColor("spez"))
    }
}
