package com.splurter.splurter_android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Prompts the user to exempt Splurter from battery optimization.
 * On modern Android, OEMs (Samsung, Xiaomi, OnePlus) kill background services
 * unless explicitly exempted. This opens the direct system dialog — no manual
 * settings digging required.
 *
 * Call from MainActivity on first launch when the foreground service is enabled.
 */
object BatteryOptimizationHelper {

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestExemption(context: Context) {
        if (isIgnoringBatteryOptimizations(context)) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            // Fallback: open general battery settings on restricted ROMs
            try {
                val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(fallback)
            } catch (_: Exception) {}
        }
    }
}
