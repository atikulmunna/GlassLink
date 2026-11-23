/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.ui.compose.screen.device

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.kde.kdeconnect.DeviceType
import org.kde.kdeconnect_tp.R

/**
 * The top of the device screen, the counterpart of the Mac app's Overview: the Mac drawn
 * front-on, its name and status underneath, on a plain card.
 */
@Composable
fun GlassLinkHero(deviceName: String, deviceType: DeviceType, modifier: Modifier = Modifier) {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val enter by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessLow),
        label = "hero",
    )
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(28.dp)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(scheme.surfaceContainer)
            .border(1.dp, scheme.outlineVariant, shape)
            .padding(top = 28.dp, bottom = 22.dp, start = 20.dp, end = 20.dp)
    ) {
        Box(
            Modifier
                .width(220.dp)
                .graphicsLayer {
                    alpha = enter
                    translationY = (1f - enter) * 24f
                }
        ) {
            if (deviceType == DeviceType.DESKTOP) {
                IMacIllustration(Modifier.fillMaxWidth().aspectRatio(1.18f))
            } else {
                MacBookIllustration(Modifier.fillMaxWidth().aspectRatio(1.52f))
            }
        }
        Spacer(Modifier.height(18.dp))
        Text(
            text = deviceName,
            fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            textAlign = TextAlign.Center,
            overflow = TextOverflow.Ellipsis,
            color = scheme.onSurface,
        )
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            Box(
                Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(scheme.onSurface)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                text = stringResource(R.string.glasslink_connected_wifi),
                fontSize = 14.sp,
                color = scheme.onSurfaceVariant,
            )
        }
    }
}

private val aluminiumLight = Color(0xFFE4E5E8)
private val aluminiumMid = Color(0xFFBFC1C6)
private val aluminiumDark = Color(0xFF8C8F95)
private val bezel = Color(0xFF070708)

/** A MacBook Pro, front view, lid open: aluminium lid edge, thin black bezel with the camera
 *  notch, "hello" being written across the screen, the hinge, and the base with its thumb scoop. */
@Composable
fun MacBookIllustration(modifier: Modifier = Modifier) {
    // Write (2.8 s), hold, fade, and start again: one 6 s loop.
    val transition = rememberInfiniteTransition(label = "hello")
    val write by transition.animateFloat(
        initialValue = 0f, targetValue = 1f, label = "write",
        animationSpec = infiniteRepeatable(keyframes {
            durationMillis = 6000
            0f at 0 using FastOutSlowInEasing
            1f at 2800
            1f at 6000
        }),
    )
    val fade by transition.animateFloat(
        initialValue = 1f, targetValue = 1f, label = "fade",
        animationSpec = infiniteRepeatable(keyframes {
            durationMillis = 6000
            1f at 0
            1f at 4600
            0f at 5400
            0f at 6000
        }),
    )
    val hello = remember { helloPath() }
    val measure = remember(hello) { PathMeasure().apply { setPath(hello, false) } }
    val segment = remember { Path() }
    Canvas(modifier = modifier) {
        val w = size.width
        val lidW = w * 0.84f
        val lidX = (w - lidW) / 2
        val lidH = lidW * 0.655f
        val edge = lidW * 0.011f

        // Contact shadow under the machine.
        drawOval(
            Brush.radialGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent),
                center = Offset(w / 2, size.height * 0.97f), radius = w * 0.55f),
            topLeft = Offset(w * 0.02f, size.height * 0.9f), size = Size(w * 0.96f, size.height * 0.1f),
        )

        // Lid: aluminium edge, then the black glass.
        val lidTop = lidW * 0.04f
        val lidBottom = lidW * 0.008f
        drawRoundRectPath(lidX, 0f, lidW, lidH, lidTop, lidBottom,
            Brush.verticalGradient(listOf(aluminiumLight, aluminiumMid), 0f, lidH))
        drawRoundRectPath(lidX + edge, edge, lidW - edge * 2, lidH - edge * 1.4f, lidTop - edge, lidBottom, Brush.linearGradient(listOf(bezel, bezel)))

        // Display: black, like the Mac's setup screen.
        val dx = lidX + lidW * 0.032f
        val dy = lidW * 0.03f
        val dw = lidW - lidW * 0.064f
        val dh = lidH - dy - lidW * 0.045f
        drawRoundRectPath(dx, dy, dw, dh, lidW * 0.018f, lidW * 0.004f,
            Brush.verticalGradient(listOf(Color(0xFF0B0B0C), Color.Black), dy, dy + dh))

        // "hello", written out in a white-to-silver gradient.
        segment.reset()
        measure.getSegment(0f, measure.length * write, segment, true)
        val scale = dw * 0.6f / HELLO_WIDTH
        clipRect(dx, dy, dx + dw, dy + dh) {
            withTransform({
                translate(dx + dw / 2 - HELLO_CENTER_X * scale, dy + dh / 2 - HELLO_CENTER_Y * scale)
                scale(scale, scale, pivot = Offset.Zero)
            }) {
                // A soft glow: a few wide, faint strokes that fall off outward.
                for ((width, alpha) in listOf(10f to 0.025f, 7.5f to 0.04f, 5.5f to 0.06f)) {
                    drawPath(segment, Color.White, alpha = alpha * fade,
                        style = Stroke(width = width, cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
                drawPath(segment,
                    Brush.linearGradient(listOf(Color.White, Color(0xFFB4B4B4), Color.White), start = Offset(0f, 0f), end = Offset(100f, 0f)),
                    alpha = fade,
                    style = Stroke(width = 3.4f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
        // A faint sweep of light across the glass.
        drawRoundRectPath(dx, dy, dw, dh, lidW * 0.018f, lidW * 0.004f,
            Brush.linearGradient(listOf(Color.White.copy(alpha = 0.05f), Color.Transparent),
                start = Offset(dx, dy), end = Offset(dx + dw * 0.6f, dy + dh)))

        // Camera notch.
        val notchW = lidW * 0.105f
        val notchH = dh * 0.055f
        val notch = Path().apply {
            addRoundRect(RoundRect(left = (w - notchW) / 2, top = dy - 1f, right = (w + notchW) / 2, bottom = dy + notchH,
                topLeftCornerRadius = CornerRadius.Zero, topRightCornerRadius = CornerRadius.Zero,
                bottomRightCornerRadius = CornerRadius(notchH * 0.45f), bottomLeftCornerRadius = CornerRadius(notchH * 0.45f)))
        }
        drawPath(notch, bezel)
        drawCircle(Color(0xFF1C2433), radius = notchH * 0.18f, center = Offset(w / 2, dy + notchH * 0.45f))

        // Hinge.
        val hingeH = lidH * 0.022f
        drawRect(Brush.verticalGradient(listOf(Color(0xFF3A3B3F), Color(0xFF1F2023)), lidH, lidH + hingeH),
            topLeft = Offset(lidX + lidW * 0.03f, lidH), size = Size(lidW * 0.94f, hingeH))

        // Base: a thin aluminium slab, wider than the lid, tapering at the ends.
        val baseTop = lidH + hingeH
        val baseH = lidH * 0.075f
        val base = Path().apply {
            addRoundRect(RoundRect(left = 0f, top = baseTop, right = w, bottom = baseTop + baseH,
                topLeftCornerRadius = CornerRadius(baseH * 0.15f), topRightCornerRadius = CornerRadius(baseH * 0.15f),
                bottomRightCornerRadius = CornerRadius(w * 0.06f, baseH), bottomLeftCornerRadius = CornerRadius(w * 0.06f, baseH)))
        }
        drawPath(base, Brush.verticalGradient(listOf(aluminiumLight, aluminiumMid, aluminiumDark), baseTop, baseTop + baseH))
        drawLine(Color.White.copy(alpha = 0.8f), Offset(w * 0.01f, baseTop + 0.5f), Offset(w * 0.99f, baseTop + 0.5f), strokeWidth = 1f)
        // Thumb scoop for opening the lid.
        val scoopW = w * 0.15f
        val scoop = Path().apply {
            addRoundRect(RoundRect(left = (w - scoopW) / 2, top = baseTop, right = (w + scoopW) / 2, bottom = baseTop + baseH * 0.42f,
                topLeftCornerRadius = CornerRadius.Zero, topRightCornerRadius = CornerRadius.Zero,
                bottomRightCornerRadius = CornerRadius(baseH * 0.4f), bottomLeftCornerRadius = CornerRadius(baseH * 0.4f)))
        }
        drawPath(scoop, Brush.verticalGradient(listOf(aluminiumDark, aluminiumMid), baseTop, baseTop + baseH * 0.42f))
    }
}

/** An iMac, front view: thin white-bordered display, chin, and stand. */
@Composable
fun IMacIllustration(modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val screenH = h * 0.7f
        drawRoundRectPath(0f, 0f, w, screenH, w * 0.03f, w * 0.03f,
            Brush.verticalGradient(listOf(aluminiumLight, aluminiumMid), 0f, screenH))
        val inset = w * 0.025f
        drawRoundRectPath(inset, inset, w - inset * 2, screenH * 0.82f - inset, w * 0.012f, w * 0.004f,
            Brush.verticalGradient(listOf(Color(0xFF34363C), Color(0xFF111216)), inset, screenH * 0.82f))
        drawRect(Color.White.copy(alpha = 0.07f), topLeft = Offset(inset, inset), size = Size(w - inset * 2, screenH * 0.04f))
        val standW = w * 0.2f
        drawRect(Brush.verticalGradient(listOf(aluminiumMid, aluminiumDark), screenH, h * 0.95f),
            topLeft = Offset((w - standW) / 2, screenH), size = Size(standW, h * 0.25f))
        drawRoundRect(aluminiumMid, topLeft = Offset(w * 0.3f, h * 0.95f), size = Size(w * 0.4f, h * 0.05f),
            cornerRadius = CornerRadius(h * 0.02f))
    }
}

private fun DrawScope.drawRoundRectPath(x: Float, y: Float, width: Float, height: Float, top: Float, bottom: Float, brush: Brush) {
    val path = Path().apply {
        addRoundRect(RoundRect(left = x, top = y, right = x + width, bottom = y + height,
            topLeftCornerRadius = CornerRadius(top), topRightCornerRadius = CornerRadius(top),
            bottomRightCornerRadius = CornerRadius(bottom), bottomLeftCornerRadius = CornerRadius(bottom)))
    }
    drawPath(path, brush)
}

private const val HELLO_WIDTH = 93f
private const val HELLO_CENTER_X = 48.5f
private const val HELLO_CENTER_Y = 20.5f

/** "hello" as one continuous cursive stroke, in a 100 × 44 box (baseline 36, ascenders 4).
 *  Original lettering drawn for GlassLink. */
private fun helloPath(): Path = Path().apply {
    moveTo(2f, 34f)
    val curves = floatArrayOf(
        // h: upstroke into the loop, over the top, down the stem
        7f, 31f, 15f, 17f, 16f, 9f, 17f, 3f, 11f, 2f, 10.5f, 9f, 10f, 17f, 9f, 29f, 8.5f, 36f,
        // h: shoulder and leg, exit toward e
        10f, 28f, 15f, 22f, 18.5f, 22.5f, 22f, 23f, 21.5f, 31f, 22.5f, 35f, 23.5f, 38f, 27.5f, 37.5f, 30f, 33f,
        // e: up, over, round the bowl, exit
        33f, 29f, 38f, 26.5f, 37.5f, 23.5f, 37f, 20.5f, 31.5f, 21f, 31.5f, 27f, 31.5f, 33f, 35f, 37.5f, 40f, 36f,
        // first l
        45f, 34f, 49f, 20f, 49.5f, 11f, 50f, 4f, 45f, 3.5f, 44.5f, 10f, 44f, 19f, 43.5f, 30f, 45f, 35f, 46f, 38f, 50f, 37.5f, 53f, 33f,
        // second l
        56f, 27f, 60f, 18f, 60.5f, 11f, 61f, 4f, 56f, 3.5f, 55.5f, 10f, 55f, 19f, 54.5f, 30f, 56f, 35f, 57f, 38f, 61f, 37.5f, 64f, 32f,
        // o, then the flourish
        65.5f, 26f, 70f, 22f, 74f, 22.5f, 79f, 23f, 80.5f, 33f, 75.5f, 36.5f, 71f, 39f, 66.5f, 34f, 68f, 28.5f,
        69.5f, 24f, 75f, 22f, 79f, 24f, 83f, 26f, 89f, 24f, 95f, 20f,
    )
    for (i in curves.indices step 6) {
        cubicTo(curves[i], curves[i + 1], curves[i + 2], curves[i + 3], curves[i + 4], curves[i + 5])
    }
}
