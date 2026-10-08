package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Shimmering placeholder card shown while a feed loads. */
@Composable
fun PostSkeleton(modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val transition = rememberInfiniteTransition(label = "shimmer")
    // Sweeps a highlight band across the card, like the shimmer package.
    val progress by transition.animateFloat(
        initialValue = -1f,
        targetValue = 2f,
        animationSpec = infiniteRepeatable(tween(1500, easing = LinearEasing), RepeatMode.Restart),
        label = "shimmer",
    )
    val base = cs.surfaceContainerHigh
    val highlight = cs.surfaceContainerHighest

    @Composable
    fun Bar(width: Dp?, height: Dp, shape: Shape = RoundedCornerShape(8.dp)) {
        Box(
            (if (width == null) Modifier.fillMaxWidth() else Modifier.width(width))
                .height(height)
                .clip(shape)
                .drawBehind {
                    // Reading `progress` in the draw phase only: no recomposition per frame.
                    val x = progress * 400f
                    drawRect(
                        Brush.linearGradient(
                            listOf(base, highlight, base),
                            start = Offset(x - 200f, 0f),
                            end = Offset(x + 200f, size.height),
                        ),
                    )
                },
        )
    }

    Column(
        modifier
            .fillMaxWidth()
            .clip(BloomCardShape)
            .background(cs.surfaceContainerLow)
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Bar(28.dp, 28.dp, CircleShape)
            Spacer(Modifier.width(10.dp))
            Bar(120.dp, 12.dp)
        }
        Spacer(Modifier.height(12.dp))
        Bar(null, 14.dp)
        Spacer(Modifier.height(6.dp))
        Bar(220.dp, 14.dp)
        Spacer(Modifier.height(12.dp))
        Bar(null, 160.dp, RoundedCornerShape(16.dp))
        Spacer(Modifier.height(12.dp))
        Row {
            Bar(80.dp, 28.dp)
            Spacer(Modifier.width(8.dp))
            Bar(64.dp, 28.dp)
        }
    }
}
