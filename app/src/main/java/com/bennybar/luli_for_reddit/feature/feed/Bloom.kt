package com.bennybar.luli_for_reddit.feature.feed

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.size.Dimension
import coil3.size.Size
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import kotlinx.coroutines.delay

// Shared Material 3 "Bloom" building blocks for the feed / home screens
// (the Flutter theme's component overrides: framed filled cards radius 28,
// stadium chips/buttons, pill search fields, flat surface app bars).

val BloomCardShape = RoundedCornerShape(28.dp)

/**
 * A Bloom card: filled `surfaceContainerLow`, radius 28, no elevation, with
 * optional tap / long-press (the whole card is the ink target).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BloomCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    shape: RoundedCornerShape = BloomCardShape,
    color: Color = MaterialTheme.colorScheme.surfaceContainerLow,
    content: @Composable ColumnScope.() -> Unit,
) {
    var m = modifier.clip(shape).background(color)
    if (onClick != null || onLongClick != null) {
        m = m.combinedClickable(onClick = { onClick?.invoke() }, onLongClick = onLongClick)
    }
    Column(m, content = content)
}

/**
 * Flutter's GlassSurface on Android: a solid Material surface
 * (`surfaceContainerHigh` unless [color] is given), clipped to [shape].
 */
@Composable
fun GlassSurface(
    modifier: Modifier = Modifier,
    shape: RoundedCornerShape = RoundedCornerShape(28.dp),
    color: Color = MaterialTheme.colorScheme.surfaceContainerHigh,
    content: @Composable () -> Unit,
) {
    Surface(modifier, shape = shape, color = color, content = content)
}

/**
 * Ignores pointer input for a short window after it first appears, so the
 * gesture that opened a sheet (a tap or a press-and-hold) can't "fall
 * through" and trigger the item under the finger.
 */
@Composable
fun TapGuard(durationMs: Long = 300, content: @Composable () -> Unit) {
    var ignore by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        delay(durationMs)
        ignore = false
    }
    Box(
        if (!ignore) Modifier else Modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                }
            }
        },
    ) { content() }
}

/**
 * Pixel width to decode full-width feed images at: the screen's width.
 * Without it every image decodes at its source size (a direct i.redd.it link
 * can be 4000px wide for a card a tenth of that), which drops frames while
 * scrolling and evicts the rest of the image cache.
 */
@Composable
fun feedDecodeWidth(): Int {
    val density = LocalDensity.current
    val widthDp = LocalConfiguration.current.screenWidthDp
    return remember(density, widthDp) { (widthDp * density.density).toInt().coerceAtLeast(1) }
}

/** A Coil request for [url] decoded at most [widthPx] wide (never upscaled). */
@Composable
fun rememberSizedRequest(url: String?, widthPx: Int): ImageRequest? {
    val context = androidx.compose.ui.platform.LocalContext.current
    return remember(url, widthPx) {
        url?.let {
            ImageRequest.Builder(context).data(it).size(Size(Dimension(widthPx), Dimension.Undefined)).build()
        }
    }
}

/** Haptics with Flutter's Android mapping (HapticFeedback.* → View constants). */
object Haptics {
    fun medium(view: View) = view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    fun selection(view: View) = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
}

@Composable
fun rememberView(): View = LocalView.current

/** Circle avatar showing [imageUrl] or the first letter of [name]. */
@Composable
fun LetterAvatar(
    name: String,
    size: Dp,
    container: Color,
    content: Color,
    modifier: Modifier = Modifier,
    imageUrl: String? = null,
    fontSize: androidx.compose.ui.unit.TextUnit = (size.value * 0.42f).sp,
    shape: androidx.compose.ui.graphics.Shape = CircleShape,
) {
    Box(
        modifier.size(size).clip(shape).background(container),
        contentAlignment = Alignment.Center,
    ) {
        if (imageUrl != null) {
            val px = with(LocalDensity.current) { size.roundToPx() }
            AsyncImage(
                model = rememberSizedRequest(imageUrl, px * 2),
                contentDescription = null,
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier.size(size),
            )
        } else {
            Text(
                if (name.isNotEmpty()) name.first().uppercase() else "?",
                color = content,
                fontWeight = FontWeight.Bold,
                fontSize = fontSize,
            )
        }
    }
}

/** Primary-coloured section label ("Favorites", "Custom feeds", …). */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        title,
        modifier,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        fontWeight = FontWeight.Bold,
    )
}

/** Flat Bloom app bar: surface background, headlineSmall w700 title, back arrow. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BloomTopBar(
    title: String,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
    titleContent: (@Composable () -> Unit)? = null,
    showBack: Boolean = true,
) {
    val nav = LocalNavigator.current
    TopAppBar(
        title = {
            if (titleContent != null) titleContent()
            else Text(
                title,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        },
        navigationIcon = {
            if (showBack) IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        },
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
            scrolledContainerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}

/** Filled pill text field (radius 24/28, no outline) used for search / filter boxes. */
@Composable
fun PillTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    leading: ImageVector = Icons.Rounded.Search,
    trailing: (@Composable () -> Unit)? = null,
    radius: Dp = 24.dp,
    onSearch: ((String) -> Unit)? = null,
    singleLine: Boolean = true,
) {
    val cs = MaterialTheme.colorScheme
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        placeholder = { Text(placeholder, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = { Icon(leading, null) },
        trailingIcon = trailing,
        singleLine = singleLine,
        shape = RoundedCornerShape(radius),
        keyboardOptions = KeyboardOptions(imeAction = if (onSearch != null) ImeAction.Search else ImeAction.Done),
        keyboardActions = KeyboardActions(onSearch = { onSearch?.invoke(value) }),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = cs.surfaceContainerHigh,
            unfocusedContainerColor = cs.surfaceContainerHigh,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
    )
}

/** A tappable pill that looks like a search box ("Search Reddit"). */
@Composable
fun SearchPill(label: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector = Icons.Rounded.Search) {
    val cs = MaterialTheme.colorScheme
    GlassSurface(modifier) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, null, tint = cs.onSurfaceVariant)
            Spacer(Modifier.width(12.dp))
            Text(label, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Centred muted message (empty states). */
@Composable
fun CenterMessage(text: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Material's `edit_square` (pencil in a square), missing from the Compose icon set. */
val EditSquareIcon: ImageVector by lazy {
    ImageVector.Builder("EditSquare", 24.dp, 24.dp, 960f, 960f).apply {
        addGroup(translationY = 960f)
        addPath(
            pathData = addPathNodes(
                "M200-120q-33 0-56.5-23.5T120-200v-560q0-33 23.5-56.5T200-840h357L357-640v280h280l203-203v363" +
                    "q0 33-23.5 56.5T760-120H200Zm160-240v-170l367-367q12-12 27-18t30-6q16 0 30.5 6t26.5 18l56 57" +
                    "q11 12 17 26.5t6 29.5q0 15-5.5 29.5T897-728L530-360H360Z",
            ),
            fill = SolidColor(Color.Black),
            pathFillType = PathFillType.NonZero,
        )
        clearGroup()
    }.build()
}

/** Spacing helper for vertical lists of cards. */
val CardSpacing = Arrangement.spacedBy(10.dp)

/**
 * Flutter's ListTile: optional leading / trailing, a title and an optional
 * subtitle, 16dp side padding, 56/72dp min height, full-width ink.
 */
@Composable
fun Tile(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: (@Composable () -> Unit)? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val cs = MaterialTheme.colorScheme
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = if (subtitle != null) 72.dp else 56.dp)
            .padding(start = 16.dp, end = if (trailing != null) 8.dp else 16.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) {
            CompositionLocalProvider(LocalContentColor provides cs.onSurfaceVariant) {
                Box(Modifier.widthIn(min = 24.dp), contentAlignment = Alignment.CenterStart) { leading() }
            }
            Spacer(Modifier.width(16.dp))
        }
        Column(Modifier.weight(1f)) {
            ProvideTextStyle(MaterialTheme.typography.bodyLarge.copy(color = cs.onSurface)) { title() }
            if (subtitle != null) {
                ProvideTextStyle(MaterialTheme.typography.bodyMedium.copy(color = cs.onSurfaceVariant)) { subtitle() }
            }
        }
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            CompositionLocalProvider(LocalContentColor provides cs.onSurfaceVariant) { trailing() }
        }
    }
}
