package com.memexlab.bedwatch

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

object WatchNotifications {
    const val RUNNING_ID = 1
    private const val RECOVERY_ID = 2
    private const val RUNNING = "monitoring"
    private const val RECOVERY = "recovery"
    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    private fun channels(c: Context) {
        manager(c).createNotificationChannel(NotificationChannel(RUNNING, "监测状态", NotificationManager.IMPORTANCE_LOW))
        manager(c).createNotificationChannel(NotificationChannel(RECOVERY, "恢复监测", NotificationManager.IMPORTANCE_HIGH))
    }
    private fun intent(c: Context): PendingIntent = PendingIntent.getActivity(c, 0,
        Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun allowed(c: Context): Boolean = manager(c).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    fun running(c: Context, last: String): Notification {
        channels(c)
        return Notification.Builder(c, RUNNING).setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("床头哨兵运行中 · 上次判断 $last").setContentIntent(intent(c))
            .setOngoing(true).setOnlyAlertOnce(true).build()
    }
    fun recover(c: Context, cause: RecoveryCause) {
        if (!RecoveryPolicy.shouldNotify(Settings(c).read().enabled, cause)) return
        channels(c)
        if (!allowed(c)) return
        try {
            manager(c).notify(RECOVERY_ID, Notification.Builder(c, RECOVERY)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("床头哨兵已停止，点一下恢复监测")
                .setContentIntent(intent(c)).setAutoCancel(true).setOnlyAlertOnce(true).build())
        } catch (_: SecurityException) { /* Permission may be revoked between check and notify. */ }
    }
    fun clearRecovery(c: Context) { manager(c).cancel(RECOVERY_ID) }
}
