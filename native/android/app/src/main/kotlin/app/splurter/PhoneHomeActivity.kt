package app.splurter

import android.app.ActivityOptions
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Telephony
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * The home screen of the Mac's own phone screen (a virtual display). Android's launcher only offers a dock there, so this
 * is a small launcher of our own: the phone's wallpaper, clock, a searchable app grid and a dock. Apps start on the same display;
 * Back from an app returns here, so the Mac window never lands on an empty screen.
 */
class PhoneHomeActivity : ComponentActivity() {
    private class Item(val label: String, val pkg: String, val cls: String, val icon: ImageBitmap)

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        setContent { Home() }
    }

    private fun launch(i: Item) {
        val o = ActivityOptions.makeBasic().setLaunchDisplayId(display?.displayId ?: 0)
        runCatching { startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setComponent(ComponentName(i.pkg, i.cls)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), o.toBundle()) }
    }

    /** Adaptive icons already come masked; old square icons get a white circle so every icon has the same shape. */
    private fun bitmap(d: android.graphics.drawable.Drawable): ImageBitmap {
        val b = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        if (d is android.graphics.drawable.AdaptiveIconDrawable) { d.setBounds(0, 0, 128, 128); d.draw(c) }
        else {
            c.drawCircle(64f, 64f, 64f, android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
            d.setBounds(22, 22, 106, 106); d.draw(c)
        }
        return b.asImageBitmap()
    }

    private suspend fun load(): List<Item> = withContext(Dispatchers.Default) {
        val pm = packageManager
        pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .filter { it.activityInfo.packageName != packageName }
            .map { Item(it.loadLabel(pm).toString(), it.activityInfo.packageName, it.activityInfo.name, bitmap(it.loadIcon(pm))) }
            .sortedBy { it.label.lowercase() }
    }

    /** The usual dock: phone, messages, browser, camera — whatever the phone has set for each. */
    private fun dockPackages(): List<String> {
        val pm = packageManager
        val intents = listOf(Intent(Intent.ACTION_DIAL), Intent(Intent.ACTION_SENDTO, android.net.Uri.parse("smsto:")),
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://example.com")), Intent(MediaStore.ACTION_IMAGE_CAPTURE))
        return intents.mapNotNull { pm.resolveActivity(it, 0)?.activityInfo?.packageName }.distinct()
    }

    @Composable
    private fun Home() {
        BackHandler(true) {} // this is the root: Back does nothing here
        var apps by remember { mutableStateOf(emptyList<Item>()) }
        var query by remember { mutableStateOf("") }
        var now by remember { mutableStateOf(LocalDateTime.now()) }
        LaunchedEffect(Unit) { apps = load() }
        LaunchedEffect(Unit) { while (true) { now = LocalDateTime.now(); delay(1000L * (61 - now.second)) } }
        val dock = remember(apps) { dockPackages().mapNotNull { p -> apps.firstOrNull { it.pkg == p } } }
        val shown = remember(apps, query) { if (query.isBlank()) apps else apps.filter { it.label.contains(query, ignoreCase = true) } }

        Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF070B1A), Color(0xFF14264A), Color(0xFF3A2A66), Color(0xFF7A3F73)))).systemBarsPadding().padding(horizontal = 14.dp)) {
            Spacer(Modifier.height(40.dp)) // room for the Mac window's status bar, which Android doesn't draw on this screen
            Text(now.format(DateTimeFormatter.ofPattern("h:mm")), color = Color.White, fontSize = 72.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Light, modifier = Modifier.padding(start = 8.dp))
            Text(now.format(DateTimeFormatter.ofPattern("EEE, d MMM")), color = Color.White.copy(alpha = 0.9f), fontSize = 18.sp, modifier = Modifier.padding(start = 10.dp, bottom = 12.dp))
            TextField(query, { query = it }, placeholder = { Text("Search apps") }, singleLine = true, shape = RoundedCornerShape(28.dp),
                colors = TextFieldDefaults.colors(focusedContainerColor = Color(0x55FFFFFF), unfocusedContainerColor = Color(0x2EFFFFFF),
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, focusedTextColor = Color.White, unfocusedTextColor = Color.White,
                    focusedPlaceholderColor = Color.White.copy(alpha = 0.8f), unfocusedPlaceholderColor = Color.White.copy(alpha = 0.8f)),
                modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(10.dp))
            LazyVerticalGrid(GridCells.Fixed(4), Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                items(shown, key = { it.pkg + it.cls }) { AppCell(it) }
            }
            if (dock.isNotEmpty()) Row(Modifier.fillMaxWidth().padding(vertical = 10.dp).clip(RoundedCornerShape(32.dp)).background(Color(0x2EFFFFFF)).padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceEvenly) { dock.forEach { Icon(it) } }
        }
    }

    @Composable private fun Icon(i: Item) = Image(i.icon, i.label, Modifier.size(56.dp).clickable { launch(i) })

    @Composable
    private fun AppCell(i: Item) = Column(Modifier.clickable { launch(i) }.padding(2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Image(i.icon, i.label, Modifier.size(58.dp).shadow(6.dp, androidx.compose.foundation.shape.CircleShape))
        Spacer(Modifier.height(4.dp))
        Text(i.label, color = Color.White, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
