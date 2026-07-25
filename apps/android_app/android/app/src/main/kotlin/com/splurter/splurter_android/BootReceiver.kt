package com.splurter.splurter_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Starts SplurterForegroundService after device boot / reboot.
 * Requires RECEIVE_BOOT_COMPLETED permission.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            SplurterForegroundService.start(context)
        }
    }
}
