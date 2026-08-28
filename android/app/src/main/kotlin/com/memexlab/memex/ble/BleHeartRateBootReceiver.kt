package com.memexlab.memex.ble

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BleHeartRateBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val store = BleHeartRateStore(context.applicationContext)
        try {
            val config = store.activeConfig()
            if (config?.enabled == true && !BleHeartRateService.start(context.applicationContext)) {
                store.updateStatus(
                    config.userKey,
                    "disconnected",
                    "background_start_denied",
                    recordGap = true,
                )
            }
        } finally {
            store.close()
        }
    }
}
