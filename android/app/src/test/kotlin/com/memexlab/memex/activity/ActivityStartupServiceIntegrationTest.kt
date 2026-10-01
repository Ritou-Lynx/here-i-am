package com.memexlab.memex.activity

import java.io.File
import org.junit.Assert.*
import org.junit.Test

/** Source contract against the exact compiled service, not a second startup implementation. */
class ActivityStartupServiceIntegrationTest {
    private fun service() = File(requireNotNull(System.getProperty("activity.service.source"))).readText()

    @Test fun notificationMayAppearAfterStartForegroundWithoutPrematureStop() {
        val source = service()
        val immediateFailure = Regex("if \\(!notificationVisible\\) \\{\\s*return ActivityObservationServiceResult\\(false, \"notification_not_visible\"\\)")
        assertFalse("A notification absent on the first lookup must remain pending, not synchronously stop/remove the service", immediateFailure.containsMatchIn(source))
        assertTrue("The production service must schedule token-bound notification confirmation", source.contains("scheduleStartupConfirmation"))
    }

    private fun section(source: String, start: String, end: String) = source.substringAfter(start).substringBefore(end)
    private fun channel() = File(requireNotNull(System.getProperty("activity.channel.source"))).readText()

    @Test fun productionStartupDoesNotCollectBeforeConfirmedArm() {
        val source = service()
        val begin = section(source, "private fun beginActivation", "private fun scheduleStartupConfirmation")
        assertTrue(begin.indexOf("registerAppOpsWatcher") < begin.indexOf("accessGate.isGranted"))
        assertTrue(begin.contains("usage_permission_denied"))
        assertTrue(begin.contains("startForeground(")); assertTrue(begin.contains("scheduleStartupConfirmation"))
        listOf("epochAuthority.start", "DynamicScreenSignalReceiver", "active = true", "queryAndAccumulate").forEach { assertFalse(it, begin.contains(it)) }
        val confirm = section(source, "private fun scheduleStartupConfirmation", "private fun failStartup")
        assertTrue(confirm.contains("ActivityStartupStep.WAITING -> mainHandler.postDelayed"))
        assertTrue(confirm.contains("ActivityStartupStep.CONFIRMED ->"))
        assertTrue(confirm.contains("activateConfirmed(config)")); assertTrue(confirm.contains("startup.complete"))
        assertTrue(confirm.contains("catch (_: Exception)")); assertTrue(confirm.contains("failStartup(token"))
        assertTrue(source.contains("service == null || !service.active"))
    }
    @Test fun productionUsesMonotonicWholeRequestDeadlineAndImmediateNotification() {
        val source = service()
        assertTrue(source.contains("SystemClock.elapsedRealtime() + START_CONFIRM_TIMEOUT_MS"))
        assertTrue(source.contains("startup.expire(requestToken, SystemClock.elapsedRealtime())"))
        assertTrue(source.contains("stopMatchingStartup(requestToken"))
        assertFalse(source.contains("context.stopService")); assertFalse(source.contains("Thread.sleep"))
        assertTrue(source.contains("Build.VERSION.SDK_INT >= Build.VERSION_CODES.S"))
        assertTrue(source.contains("setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)"))
    }
    @Test fun productionPermissionEdgeFencesImmediatelyButCleansOnMainAndDestroyOwnsInstance() {
        val source = service()
        val listener = section(source, "val listener = AppOpsManager.OnOpChangedListener", "manager.startWatchingMode")
        assertTrue(listener.indexOf("startup.cancelPending") < listener.indexOf("mainHandler.post"))
        assertTrue(listener.indexOf("mainHandler.post") < listener.indexOf("stopMatchingStartup"))
        assertTrue(listener.contains("if (stopping) return@post"))
        val stop = section(source, "private fun stopObservation", "override fun onDestroy")
        assertTrue(stop.contains("startupPoll?.let(mainHandler::removeCallbacks)"))
        assertTrue(stop.contains("unregisterAppOpsWatcher()"))
        assertTrue(source.contains("startup.release(serviceInstanceId"))
        assertTrue(source.contains("if (live === this) live = null"))
    }
    @Test fun productionBridgeRejectsLateReplyAndDetachOnlyCancelsPendingStartup() {
        val source = channel()
        assertTrue(source.contains("startupReplies.accept(requestToken, requestGeneration)"))
        assertTrue(source.contains("accepted && startupReplies.isCurrent(requestGeneration)"))
        assertTrue(source.contains("setDeliveryListener(requestToken)"))
        val detach = source.substringAfter("private fun detachBridge()")
        assertTrue(detach.contains("startupReplies.invalidate(detach = true)"))
        assertTrue(detach.contains("pendingActivationResult = null"))
        assertTrue(detach.contains("if (pending != null) ActivityObservationForegroundService.cancelPendingStart"))
        assertFalse(detach.contains("requestStop(")); assertFalse(detach.contains("result.success"))
        val shutdown = section(source, "private fun shutdown()", "/** Detach")
        assertTrue(shutdown.indexOf("startupReplies.invalidate") < shutdown.indexOf("cancelPendingStart"))
        assertTrue(shutdown.contains("reply?.success"))
    }
    @Test fun postedSuccessRevalidatesNativeStopBeforeTouchingBridge() {
        val dispatch = section(service(), "if (!startup.begin", "}) return false")
        assertTrue(dispatch.contains("Handler(Looper.getMainLooper()).post"))
        assertTrue(dispatch.contains("service != null && service.active"))
        assertTrue(dispatch.contains("startup.isActive(requestToken, service.serviceInstanceId)"))
        assertTrue(dispatch.contains("enabled && !stillActive"))
        assertTrue(dispatch.contains("ActivityObservationServiceResult(false, \"collector_disabled\")"))
    }
}
