package com.memexlab.bedwatch

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** "1 小时内别看" from the look notification. The server is told "paused" on the next request. */
class LookPauseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Settings(context).lookPausedUntil = System.currentTimeMillis() + 3_600_000L
        WatchNotifications.clearLooked(context)
    }
}
