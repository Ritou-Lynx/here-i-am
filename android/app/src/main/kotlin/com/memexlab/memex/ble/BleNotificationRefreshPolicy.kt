package com.memexlab.memex.ble

/** Keeps live BPM notification redraws off the one-hertz sample hot path. */
internal object BleNotificationRefreshPolicy {
    const val LIVE_REFRESH_INTERVAL_MS = 60_000L

    fun shouldNotify(
        force: Boolean,
        statusChanged: Boolean,
        elapsedSinceLastMs: Long,
    ): Boolean = force || statusChanged || elapsedSinceLastMs >= LIVE_REFRESH_INTERVAL_MS
}
