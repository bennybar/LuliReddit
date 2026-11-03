package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.theme.AppTheme
import kotlin.math.abs
import kotlin.math.roundToInt

/** [argb]'s hue (0–360), saturation and value (0–1). */
fun argbToHsv(argb: Long): FloatArray {
    val r = ((argb shr 16) and 0xFF) / 255f
    val g = ((argb shr 8) and 0xFF) / 255f
    val b = (argb and 0xFF) / 255f
    val max = maxOf(r, g, b)
    val delta = max - minOf(r, g, b)
    val h = when {
        delta == 0f -> 0f
        max == r -> 60f * (((g - b) / delta).mod(6f))
        max == g -> 60f * ((b - r) / delta + 2f)
        else -> 60f * ((r - g) / delta + 4f)
    }
    return floatArrayOf(h, if (max == 0f) 0f else delta / max, max)
}

/** An opaque ARGB colour from hue (0–360), saturation and value (0–1). */
fun hsvToArgb(h: Float, s: Float, v: Float): Long {
    val c = v * s
    val x = c * (1 - abs((h / 60f).mod(2f) - 1))
    val m = v - c
    val (r, g, b) = when ((h.mod(360f) / 60f).toInt()) {
        0 -> Triple(c, x, 0f)
        1 -> Triple(x, c, 0f)
        2 -> Triple(0f, c, x)
        3 -> Triple(0f, x, c)
        4 -> Triple(x, 0f, c)
        else -> Triple(c, 0f, x)
    }
    fun byte(f: Float) = ((f + m) * 255f).roundToInt().coerceIn(0, 255).toLong()
    return 0xFF000000L or (byte(r) shl 16) or (byte(g) shl 8) or byte(b)
}

private val HUES = (0..6).map { Color.hsv(it * 60f % 360f, 1f, 1f) }

/**
 * Any accent colour (#84): a saturation/brightness square over a hue bar,
 * with the Material scheme it seeds (as the presets do) previewed below.
 * The picked colour, or null when cancelled.
 */
internal suspend fun pickCustomColor(initial: Long): Long? = Overlays.show<Long> { done ->
    val start = remember { argbToHsv(initial) }
    var hue by remember { mutableFloatStateOf(start[0]) }
    var sat by remember { mutableFloatStateOf(start[1]) }
    var value by remember { mutableFloatStateOf(start[2]) }
    val argb = hsvToArgb(hue, sat, value)
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val scheme = remember(argb, dark) { AppTheme.fromSeed(Color(argb.toInt()), dark) }
    AlertDialog(
        onDismissRequest = { done(null) },
        title = { Text("Custom color") },
        text = {
            Column {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(180.dp)
                        .clip(RoundedCornerShape(18.dp))
                        .background(Brush.horizontalGradient(listOf(Color.White, Color.hsv(hue, 1f, 1f))))
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
                        .pointerInput(Unit) {
                            awaitEachGesture {
                                val down = awaitFirstDown()
                                fun at(p: Offset) {
                                    sat = (p.x / size.width).coerceIn(0f, 1f)
                                    value = 1f - (p.y / size.height).coerceIn(0f, 1f)
                                }
                                at(down.position)
                                drag(down.id) { at(it.position); it.consume() }
                            }
                        },
                ) {
                    Canvas(Modifier.fillMaxSize()) {
                        val c = Offset(sat * size.width, (1f - value) * size.height)
                        drawCircle(Color.White, 11.dp.toPx(), c, style = Stroke(3.dp.toPx()))
                        drawCircle(Color.Black.copy(alpha = 0.3f), 12.5.dp.toPx(), c, style = Stroke(1.dp.toPx()))
                    }
                }
                Spacer(Modifier.height(16.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(28.dp)
                        .clip(CircleShape)
                        .background(Brush.horizontalGradient(HUES))
                        .pointerInput(Unit) {
                            awaitEachGesture {
                                val down = awaitFirstDown()
                                fun at(p: Offset) { hue = (p.x / size.width).coerceIn(0f, 1f) * 359.9f }
                                at(down.position)
                                drag(down.id) { at(it.position); it.consume() }
                            }
                        },
                ) {
                    Canvas(Modifier.fillMaxSize()) {
                        val r = size.height / 2
                        val c = Offset(r + hue / 360f * (size.width - 2 * r), r)
                        drawCircle(Color.hsv(hue, 1f, 1f), r - 4.dp.toPx(), c)
                        drawCircle(Color.White, r - 4.dp.toPx(), c, style = Stroke(3.dp.toPx()))
                    }
                }
                Spacer(Modifier.height(20.dp))
                // The colour, then what it seeds: the accent and its containers.
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(40.dp).background(Color(argb.toInt()), CircleShape))
                    for (c in listOf(scheme.primary, scheme.primaryContainer, scheme.secondaryContainer, scheme.tertiaryContainer)) {
                        Box(Modifier.size(28.dp).background(c, RoundedCornerShape(10.dp)))
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "#%06X".format(argb and 0xFFFFFF),
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        dismissButton = { TextButton(onClick = { done(null) }, shapes = ButtonDefaults.shapes()) { Text("Cancel") } },
        confirmButton = { Button(onClick = { done(argb) }, shapes = ButtonDefaults.shapes()) { Text("Use color") } },
    )
}
