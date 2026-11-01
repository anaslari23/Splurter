package app.splurter

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

@Composable
fun SplurterTheme(content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx), content = content)
}

class Feature(val title: String, val desc: String, val icon: ImageVector, val granted: Boolean, val actionLabel: String = "Allow", val onAllow: () -> Unit)

@Composable
fun HomeScreen(
    state: String, paired: Boolean, features: List<Feature>,
    onScan: () -> Unit, onClipboard: () -> Unit, onFile: () -> Unit, onForget: () -> Unit,
) {
    val connected = state.startsWith("Connected")
    Scaffold { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Column {
                Text("Splurter", style = MaterialTheme.typography.displaySmall)
                Text("Your phone, working with your Mac.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            StatusCard(state, paired, connected)

            if (!paired) {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Pair with your Mac", style = MaterialTheme.typography.titleMedium)
                        Text("1. On your Mac, click the Splurter icon in the menu bar and choose “Pair a phone”.\n2. Tap the button below and point the camera at the QR code.",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(onScan, Modifier.fillMaxWidth()) { Text("Scan QR code") }
                    }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FilledTonalButton(onClipboard, Modifier.weight(1f), enabled = connected) { Icon(Icons.Filled.Send, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Clipboard") }
                    FilledTonalButton(onFile, Modifier.weight(1f), enabled = connected) { Icon(Icons.Filled.Share, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Send file") }
                }
            }

            Column {
                Text("Features", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    features.forEach { f ->
                        ListItem(
                            colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
                            leadingContent = { Icon(f.icon, null, tint = MaterialTheme.colorScheme.primary) },
                            headlineContent = { Text(f.title) },
                            supportingContent = { Text(f.desc) },
                            trailingContent = {
                                if (f.granted) Icon(Icons.Filled.Check, "Enabled", tint = MaterialTheme.colorScheme.primary)
                                else FilledTonalButton(f.onAllow) { Text(f.actionLabel) }
                            },
                        )
                    }
                }
            }

            if (paired) TextButton(onForget, Modifier.align(Alignment.CenterHorizontally)) {
                Text("Forget this Mac", color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun StatusCard(state: String, paired: Boolean, connected: Boolean) {
    val bg = if (connected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh
    val fg = if (connected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
    Card(colors = CardDefaults.cardColors(containerColor = bg, contentColor = fg)) {
        Row(Modifier.fillMaxWidth().padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(52.dp).clip(CircleShape).background(if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant),
                contentAlignment = Alignment.Center) {
                Icon(if (connected) Icons.Filled.Check else if (paired) Icons.Filled.Refresh else Icons.Filled.Person, null,
                    tint = if (connected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
            }
            Spacer(Modifier.width(16.dp))
            Column {
                Text(state, style = MaterialTheme.typography.titleMedium)
                Text(if (connected) "Encrypted, directly over your Wi-Fi" else if (paired) "Keeps trying in the background" else "Pair once — no account needed",
                    style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

val featureIcons = mapOf("notifications" to Icons.Filled.Notifications, "calls" to Icons.Filled.Call, "sms" to Icons.Filled.Email, "contacts" to Icons.Filled.Person)
