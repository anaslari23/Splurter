package app.splurter

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject

/**
 * Remote input from the Mac's mirror window. Coordinates arrive normalised (0..1).
 * Only acts while a mirroring session that the user approved on this phone is live.
 */
class ControlService : AccessibilityService() {
    override fun onServiceConnected() { instance = this }
    override fun onUnbind(i: android.content.Intent?): Boolean { if (instance === this) instance = null; return super.onUnbind(i) }
    override fun onAccessibilityEvent(e: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    fun handle(m: JSONObject) {
        if (MirrorService.instance == null) return
        val w = resources.displayMetrics.widthPixels.toFloat(); val h = resources.displayMetrics.heightPixels.toFloat()
        when (m.optString("t")) {
            "tap" -> stroke(m.getDouble("x").toFloat() * w, m.getDouble("y").toFloat() * h, null, null, m.optLong("ms", 50).coerceIn(30, 1000))
            "swipe" -> stroke(m.getDouble("x1").toFloat() * w, m.getDouble("y1").toFloat() * h,
                m.getDouble("x2").toFloat() * w, m.getDouble("y2").toFloat() * h, m.optLong("ms", 200).coerceIn(30, 1500))
            "key" -> when (m.optString("k")) {
                "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
                "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
                "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
                "enter" -> focused()?.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
                "del" -> edit { it.dropLast(1) }
            }
            "text" -> edit { it + m.getString("s") }
        }
    }

    private fun stroke(x1: Float, y1: Float, x2: Float?, y2: Float?, ms: Long) {
        val p = Path().apply { moveTo(x1, y1); if (x2 != null && y2 != null) lineTo(x2, y2) }
        dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(p, 0, ms)).build(), null, null)
    }

    private fun focused() = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)

    /** ponytail: edits the focused field by replacing its whole text (appends/deletes at the end, no cursor support). */
    private fun edit(f: (String) -> String) {
        val n = focused() ?: return
        val cur = if (n.isShowingHintText) "" else n.text?.toString().orEmpty()
        n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, f(cur))
        })
    }

    companion object { @Volatile var instance: ControlService? = null }
}
