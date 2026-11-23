/*
 * SPDX-FileCopyrightText: 2024 KDE Connect contributors
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

package org.kde.kdeconnect.ui.compose.screen.device

import androidx.compose.animation.core.Spring
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
    Column(modifier = Modifier.padding(horizontal = 16.dp)) {
        buttons.chunked(numColumns).forEach { row ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                row.forEach { button ->
                    PluginButton(button = button, modifier = Modifier.weight(1f), onClick = { onButtonClick(button) })
                }
                repeat(numColumns - row.size) { Spacer(modifier = Modifier.weight(1f)) }
            }
        }
    }
}

/** An action tile, like the Mac's quick actions: white icon on a dark disc, springy press. */
@Composable
private fun PluginButton(
    button: Plugin.PluginUiButton,
    modifier: Modifier,
    onClick: () -> Unit
) {
    val scheme = MaterialTheme.colorScheme
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.95f else 1f,
        animationSpec = spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMedium),
        label = "press",
    )
    val shape = RoundedCornerShape(24.dp)
    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(shape)
            .background(scheme.surfaceContainer)
            .border(1.dp, scheme.outlineVariant, shape)
            .clickable(interactionSource = interaction, indication = androidx.compose.material3.ripple(), onClick = onClick)
            .semantics { role = Role.Button }
            .padding(16.dp)
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(scheme.surfaceContainerHighest)
        ) {
            Icon(
                painter = painterResource(id = button.iconRes),
                tint = scheme.onSurface,
                contentDescription = null,
            )
        }
        Text(
            text = button.name,
            maxLines = 2,
            minLines = 2,
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
            lineHeight = 20.sp,
            color = scheme.onSurface,
            overflow = TextOverflow.Ellipsis
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
                    Icon(Icons.Filled.Lock, contentDescription = null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
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
