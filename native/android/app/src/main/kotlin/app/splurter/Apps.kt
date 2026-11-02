package app.splurter

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** The Mac's app launcher: every launchable app (label + component), plus icons the Mac doesn't have yet. */
object Apps {
    fun send(ctx: Context, have: Set<String>) {
        val pm = ctx.packageManager
        val list = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .filter { it.activityInfo.packageName != ctx.packageName }.sortedBy { it.loadLabel(pm).toString().lowercase() }
        val arr = JSONArray()
        for (r in list) arr.put(JSONObject().put("pkg", r.activityInfo.packageName).put("cls", r.activityInfo.name).put("label", r.loadLabel(pm).toString()))
        App.link.send(JSONObject().put("t", "apps").put("apps", arr))
        for (r in list) { // icons last, one message each, only the ones the Mac lacks
            val pkg = r.activityInfo.packageName
            if (pkg in have) continue
            runCatching {
                val d = r.loadIcon(pm)
                val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                d.setBounds(0, 0, 96, 96); d.draw(Canvas(bmp))
                val png = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
                App.link.send(JSONObject().put("t", "app_icon").put("pkg", pkg).put("png", Base64.encodeToString(png, Base64.NO_WRAP)))
            }
        }
    }
}
