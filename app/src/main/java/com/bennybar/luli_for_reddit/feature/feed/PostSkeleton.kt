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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Shimmering placeholder card shown while a feed loads. */
@Composable
fun PostSkeleton(modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val transition = rememberInfiniteTransition(label = "shimmer")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
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
                .background(highlight, shape),
        )
    }

    // Flutter's Shimmer.fromColors over the whole card: one gradient band
    // sweeps left→right across the card, painted srcIn over everything the
    // card draws (its background included), so it reads as one shimmering
    // card. Offscreen so the blend only sees the card's own pixels;
    // `progress` is read in the draw phase only (no recomposition per frame).
    Column(
        modifier
            .fillMaxWidth()
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val w = size.width
                val left = -w + 2 * w * progress - w // the band's rect is 3 widths wide
                drawRect(
                    Brush.linearGradient(
                        0f to base, 0.35f to base, 0.5f to highlight, 0.65f to base, 1f to base,
                        start = Offset(left, 0f),
                        end = Offset(left + 3 * w, size.height / 2),
                    ),
                    blendMode = BlendMode.SrcIn,
                )
            }
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
