/*
 * SPDX-FileCopyrightText: 2024 KDE Connect contributors
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

package org.kde.kdeconnect.ui.compose.screen.device

import androidx.compose.animation.core.Spring
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.kde.kdeconnect.DeviceType
import org.kde.kdeconnect.extensions.safeDrawingBottomPadding
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.clipboard.ClipboardPlugin
import org.kde.kdeconnect.plugins.mpris.MprisPlugin
import org.kde.kdeconnect.plugins.ping.PingPlugin
import org.kde.kdeconnect.plugins.presenter.PresenterPlugin
import org.kde.kdeconnect.plugins.runcommand.RunCommandPlugin
import org.kde.kdeconnect.ui.compose.KdeTheme
import org.kde.kdeconnect.ui.compose.components.KdeThemePreviews
import org.kde.kdeconnect_tp.R

@Composable
fun PluginsScreen(
    pluginsWithButtons: List<Plugin.PluginUiButton>,
    pluginsNeedPermissions: List<Plugin>,
    pluginsNeedOptionalPermissions: List<Plugin>,
    onButtonClick: (Plugin.PluginUiButton) -> Unit,
    actionNeedPermissions: (plugin: Plugin) -> Unit,
    actionNeedOptionalPermissions: (plugin: Plugin) -> Unit,
    deviceName: String = "",
    deviceType: DeviceType = DeviceType.LAPTOP,
) {
    PluginsScreenContent(
        pluginsWithButtons = pluginsWithButtons,
        pluginsNeedPermissions = pluginsNeedPermissions,
        pluginsNeedOptionalPermissions = pluginsNeedOptionalPermissions,
        onButtonClick = onButtonClick,
        actionNeedPermissions = actionNeedPermissions,
        actionNeedOptionalPermissions = actionNeedOptionalPermissions,
        deviceName = deviceName,
        deviceType = deviceType,
    )
}

@Composable
private fun PluginsScreenContent(
    pluginsWithButtons: List<Plugin.PluginUiButton>,
    pluginsNeedPermissions: List<Plugin>,
    pluginsNeedOptionalPermissions: List<Plugin>,
    onButtonClick: (Plugin.PluginUiButton) -> Unit,
    actionNeedPermissions: (plugin: Plugin) -> Unit,
    actionNeedOptionalPermissions: (plugin: Plugin) -> Unit,
    deviceName: String = "",
    deviceType: DeviceType = DeviceType.LAPTOP,
) {
    val bottomPadding = safeDrawingBottomPadding().calculateBottomPadding()
    val scheme = MaterialTheme.colorScheme
    Surface(modifier = Modifier.fillMaxSize(), color = scheme.background) {
        Box {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(state = rememberScrollState())
                    .padding(top = 12.dp, bottom = bottomPadding + 16.dp)
            ) {
                if (deviceName.isNotEmpty()) {
                    GlassLinkHero(
                        deviceName = deviceName,
                        deviceType = deviceType,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Spacer(modifier = Modifier.padding(vertical = 10.dp))
                }
                val numColumns = LocalResources.current.getInteger(R.integer.plugins_columns)
                PluginButtons(
                    buttons = pluginsWithButtons,
                    numColumns = numColumns,
                    onButtonClick = onButtonClick
                )
                if (pluginsNeedPermissions.isNotEmpty()) {
                    Spacer(modifier = Modifier.padding(vertical = 8.dp))
                    PluginsWithoutPermissions(
                        title = stringResource(id = R.string.glasslink_finish_setup),
                        plugins = pluginsNeedPermissions,
                        subtitle = stringResource(R.string.glasslink_needs_permission),
                        action = actionNeedPermissions,
                    )
                }
                if (pluginsNeedOptionalPermissions.isNotEmpty()) {
                    Spacer(modifier = Modifier.padding(vertical = 8.dp))
                    PluginsWithoutPermissions(
                        title = stringResource(id = R.string.glasslink_optional_extras),
                        plugins = pluginsNeedOptionalPermissions,
                        subtitle = stringResource(R.string.glasslink_optional_permission),
                        action = actionNeedOptionalPermissions
                    )
                }
            }
        }
    }
}

@Composable
private fun PluginButtons(
    buttons: List<Plugin.PluginUiButton>,
    numColumns: Int,
    onButtonClick: (Plugin.PluginUiButton) -> Unit
) {
    // Round glass buttons, four to a row, like the Mac app's quick actions.
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val perRow = maxOf(4, numColumns)
    Column(
        verticalArrangement = Arrangement.spacedBy(18.dp),
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
    ) {
        buttons.chunked(perRow).forEachIndexed { rowIndex, row ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                row.forEachIndexed { i, button ->
                    GlassCircleButton(
                        button = button,
                        index = rowIndex * perRow + i,
                        appeared = appeared,
                        modifier = Modifier.weight(1f),
                        onClick = { onButtonClick(button) },
                    )
                }
                repeat(perRow - row.size) { Spacer(modifier = Modifier.weight(1f)) }
            }
        }
    }
}

/** Frosted glass disc: translucent fill brighter at the top, a thin light rim, springy press. */
@Composable
private fun GlassCircleButton(
    button: Plugin.PluginUiButton,
    index: Int,
    appeared: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    // Dark mode: midnight glass in the text colour. Light mode: Material tonal buttons
    // (primaryContainer), so the palette's colour shows.
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    val ink = if (dark) scheme.onSurface else scheme.onPrimaryContainer
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (pressed) 0.9f else 1f,
        animationSpec = spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMedium),
        label = "press",
    )
    val enter by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow),
        label = "enter",
    )
    // The icon pops each time the button is tapped.
    val pop = remember { Animatable(1f) }
    var taps by remember { mutableIntStateOf(0) }
    LaunchedEffect(taps) {
        if (taps > 0) {
            pop.animateTo(1.25f, spring(dampingRatio = 0.4f, stiffness = Spring.StiffnessHigh))
            pop.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessMediumLow))
        }
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = modifier.graphicsLayer {
            // Staggered entrance: each button arrives a beat after the previous one, and every
            // button ends fully visible however many there are (a fixed 1.6x left the 6th and 7th
            // tiles at 85% and 70% opacity).
            val delayed = ((enter * (1f + index * 0.15f)) - index * 0.15f).coerceIn(0f, 1f)
            alpha = delayed
            scaleX = 0.7f + 0.3f * delayed
            scaleY = 0.7f + 0.3f * delayed
        }
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(64.dp)
                .graphicsLayer {
                    scaleX = pressScale
                    scaleY = pressScale
                }
                .clip(CircleShape)
                .then(
                    if (dark) Modifier
                        .background(Brush.verticalGradient(listOf(ink.copy(alpha = if (pressed) 0.20f else 0.13f), ink.copy(alpha = 0.04f))))
                        .border(1.dp, Brush.verticalGradient(listOf(ink.copy(alpha = 0.34f), ink.copy(alpha = 0.06f))), CircleShape)
                    else Modifier.background(if (pressed) scheme.primary.copy(alpha = 0.28f) else scheme.primaryContainer)
                )
                .clickable(interactionSource = interaction, indication = androidx.compose.material3.ripple(bounded = true)) {
                    taps++
                    onClick()
                }
                .semantics { role = Role.Button }
        ) {
            // A soft highlight across the top of the glass (dark mode only).
            if (dark) Box(
                Modifier
                    .matchParentSize()
                    .background(Brush.radialGradient(listOf(ink.copy(alpha = 0.10f), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(60f, 30f), radius = 120f))
            )
            Icon(
                painter = painterResource(id = button.iconRes),
                tint = if (dark) scheme.primary else ink, // the accent, on midnight glass in dark mode
                contentDescription = null,
                modifier = Modifier
                    .size(26.dp)
                    .graphicsLayer {
                        scaleX = pop.value
                        scaleY = pop.value
                    },
            )
        }
        Text(
            text = button.name,
            maxLines = 2,
            textAlign = TextAlign.Center,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.Medium,
            color = scheme.onSurfaceVariant,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Features waiting on a permission, as one card with a row each. */
@Composable
private fun PluginsWithoutPermissions(
    title: String,
    subtitle: String,
    plugins: Collection<Plugin>,
    action: (plugin: Plugin) -> Unit
) {
    val scheme = MaterialTheme.colorScheme
    Text(
        text = title,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        color = scheme.onSurfaceVariant,
        modifier = Modifier
            .padding(horizontal = 28.dp, vertical = 6.dp)
            .semantics { heading() }
    )
    Column(
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(scheme.surfaceContainer)
            .border(1.dp, scheme.outlineVariant, RoundedCornerShape(24.dp))
    ) {
        plugins.forEach { plugin ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { action(plugin) }
                    .semantics { role = Role.Button }
                    .padding(horizontal = 16.dp, vertical = 14.dp)
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(scheme.surfaceContainerHighest)
                ) {
                    Icon(Icons.Filled.Lock, contentDescription = null, modifier = Modifier.size(16.dp),
                        tint = scheme.primary)
                }
                Column(modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 14.dp)) {
                    Text(text = plugin.displayName, fontSize = 16.sp, color = scheme.onSurface)
                    Text(text = subtitle, fontSize = 13.sp, color = scheme.onSurfaceVariant)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = scheme.onSurfaceVariant)
            }
        }
    }
}

@KdeThemePreviews
@Composable
private fun PluginsScreenPreview() {
    KdeTheme(context = LocalContext.current) {
        val mprisPlugin = MprisPlugin().also { it.setContext(LocalContext.current, null) }
        val runCommandPlugin = RunCommandPlugin().also { it.setContext(LocalContext.current, null) }
        val presenterPlugin = PresenterPlugin().also { it.setContext(LocalContext.current, null) }
        val pingPlugin = PingPlugin().also { it.setContext(LocalContext.current, null) }
        val clipboardPlugin = ClipboardPlugin().also { it.setContext(LocalContext.current, null) }

        val pluginsWithButtons = listOf(pingPlugin, mprisPlugin, presenterPlugin, runCommandPlugin)
        val pluginsWithoutPermissions = listOf(clipboardPlugin, presenterPlugin)
        val pluginsWithoutOptionalPermissions = listOf(mprisPlugin, presenterPlugin)

        PluginsScreenContent(
            pluginsWithButtons = pluginsWithButtons.flatMap { plugin -> plugin.getUiButtons() },
            pluginsNeedPermissions = pluginsWithoutPermissions,
            pluginsNeedOptionalPermissions = pluginsWithoutOptionalPermissions,
            onButtonClick = { /* Do nothing */ },
            actionNeedPermissions = { /* Do nothing */ },
            actionNeedOptionalPermissions = { /* Do nothing */ },
            deviceName = "MacBook Pro",
        )
    }
}
