package com.bennybar.luli_for_reddit.feature.foryou

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import kotlinx.coroutines.delay

private val EaseInOutCubic = CubicBezierEasing(0.645f, 0.045f, 0.355f, 1f)
private val EaseOutCubic = CubicBezierEasing(0.215f, 0.61f, 0.355f, 1f)

/** "Remove animations" (system animator scale 0). */
@Composable
private fun animationsDisabled(): Boolean {
    val context = LocalContext.current
    return remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** Out to [peak] over the first 40%, back to [end] by 80%, then settle at 0. */
private fun lerpPath(t: Float, start: Float, peak: Float, end: Float): Float = when {
    t < 0.4f -> start + (peak - start) * EaseInOutCubic.transform(t / 0.4f)
    t < 0.8f -> peak + (end - peak) * EaseInOutCubic.transform((t - 0.4f) / 0.4f)
    else -> end * (1 - (t - 0.8f) / 0.2f)
}

/**
 * Home's loading state: a small deck of post cards shuffling while a live
 * counter shows how many posts have been found. Shown when there's no saved
 * Home page to paint instead (first open, or switching to Home).
 */
@Composable
fun HomeLoadingDeck() {
    val cs = MaterialTheme.colorScheme
    val found by app.forYou.redditHome.progress.collectAsStateWithLifecycle()
    // Respect "remove animations": a still deck, the counter still counts.
    val still = animationsDisabled()
    val riffle = rememberInfiniteTransition(label = "riffle")
    val animated by riffle.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1600, easing = LinearEasing), RepeatMode.Restart),
        label = "t",
    )
    val density = LocalDensity.current
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(230.dp, 170.dp), contentAlignment = Alignment.Center) {
                val t = if (still) 0f else animated
                // The top card is flicked out to the right, then slides back
                // in *behind* the others: it switches sides at 41%.
                val behind = t >= 0.41f
                val top = @Composable {
                    DeckCard(
                        accent = true,
                        modifier = Modifier.graphicsLayer {
                            translationX = with(density) { lerpPath(t, 0f, 110f, 0f).dp.toPx() }
                            translationY = with(density) { lerpPath(t, 0f, -14f, 0f).dp.toPx() }
                            rotationZ = lerpPath(t, 0f, 16f, -2f)
                        },
                    )
                }
                if (behind) top()
                DeckCard(Modifier.graphicsLayer {
                    translationX = with(density) { (-8).dp.toPx() }
                    rotationZ = -8f
                })
                DeckCard(Modifier.graphicsLayer {
                    translationX = with(density) { 6.dp.toPx() }
                    rotationZ = 5f
                })
                if (!behind) top()
            }
            Spacer(Modifier.height(18.dp))
            Text(
                if (found == 0) buildAnnotatedString { append("Opening your Home…") }
                else buildAnnotatedString {
                    append("Found ")
                    withStyle(SpanStyle(color = cs.primary, fontWeight = FontWeight.ExtraBold)) { append("$found") }
                    append(if (found == 1) " post" else " posts")
                    append(" in your Home")
                },
                fontSize = 13.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = cs.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
            )
        }
    }
}

@Composable
private fun DeckCard(modifier: Modifier = Modifier, accent: Boolean = false) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(16.dp)
    @Composable
    fun Bar(w: Int) = Box(
        Modifier.width(w.dp).height(7.dp).background(cs.surfaceContainerHigh, RoundedCornerShape(5.dp)),
    )
    Column(
        modifier
            .size(150.dp, 120.dp)
            .shadow(14.dp, shape, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
            .background(cs.surfaceContainerLow, shape)
            .border(1.dp, cs.surfaceContainerHighest, shape)
            .padding(10.dp),
    ) {
        Bar(60)
        Spacer(Modifier.height(6.dp))
        Bar(128)
        Spacer(Modifier.height(8.dp))
        Box(
            Modifier.fillMaxWidth().weight(1f)
                .background(if (accent) cs.primaryContainer else cs.surfaceContainerHigh, RoundedCornerShape(9.dp)),
        )
    }
}

/**
 * Deals a freshly loaded Home card into the feed: it rises from below with a
 * slight tilt, staggered by [index], once. Used for the first few cards after
 * the loading deck. [animate] is read once, when the card first appears: only
 * cards that arrive right after the loading deck are dealt; ones rebuilt later
 * just show.
 */
@Composable
fun DealIn(index: Int, animate: Boolean, content: @Composable () -> Unit) {
    if (animationsDisabled()) {
        content()
        return
    }
    val progress = remember { Animatable(if (animate) 0f else 1f) }
    LaunchedEffect(Unit) {
        if (progress.value < 1f) {
            delay(100L * index)
            progress.animateTo(1f, tween(600, easing = LinearEasing))
        }
    }
    val tilt = listOf(-6f, 5f, -3f)[index % 3]
    val rise = 180f - 60 * (index % 3)
    val density = LocalDensity.current
    Box(
        Modifier.graphicsLayer {
            val t = EaseOutCubic.transform(progress.value)
            alpha = t
            translationY = with(density) { (rise * (1 - t)).dp.toPx() }
            rotationZ = tilt * (1 - t)
            val s = 0.85f + 0.15f * t
            scaleX = s
            scaleY = s
        },
    ) { content() }
}
