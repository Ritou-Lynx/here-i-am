package com.memexlab.memex.activity

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.UserManager

internal data class RawActivityUsageEvent(
    val packageId: String?,
    val eventType: Int,
    val occurredAtMs: Long,
)

internal sealed interface ActivityUsageEventQueryResult {
    data class Available(val events: List<RawActivityUsageEvent>) : ActivityUsageEventQueryResult
    data object NullResult : ActivityUsageEventQueryResult
    data object DeviceLocked : ActivityUsageEventQueryResult
    data object Failed : ActivityUsageEventQueryResult
}

internal interface ActivityUsageEventSource {
    fun query(startMs: Long, endMs: Long): ActivityUsageEventQueryResult
}

internal class AndroidActivityUsageEventSource(private val context: Context) : ActivityUsageEventSource {
    override fun query(startMs: Long, endMs: Long): ActivityUsageEventQueryResult {
        val userManager = context.getSystemService(Context.USER_SERVICE) as UserManager
        if (!userManager.isUserUnlocked) return ActivityUsageEventQueryResult.DeviceLocked
        return try {
            val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val stream = manager.queryEvents(startMs, endMs)
                ?: return ActivityUsageEventQueryResult.NullResult
            val event = UsageEvents.Event()
            val result = mutableListOf<RawActivityUsageEvent>()
            while (stream.hasNextEvent() && stream.getNextEvent(event)) {
                result += RawActivityUsageEvent(
                    packageId = event.packageName,
                    eventType = event.eventType,
                    occurredAtMs = event.timeStamp,
                )
            }
            ActivityUsageEventQueryResult.Available(result)
        } catch (_: Exception) {
            ActivityUsageEventQueryResult.Failed
        }
    }
}

internal data class ReducedActivityUsageBatch(
    val usageSignals: List<ReducedActivitySignal>,
    val screenSignals: List<ReducedActivitySignal>,
)

internal object ActivityUsageEventReducer {
    const val KEYGUARD_HIDDEN = 18
    const val SCREEN_INTERACTIVE = 15
    const val SCREEN_NON_INTERACTIVE = 16

    fun reduce(
        events: List<RawActivityUsageEvent>,
        startMs: Long,
        endMs: Long,
        categoryMapping: Map<String, String>,
    ): ReducedActivityUsageBatch {
        ActivitySignalPolicy.validateQueryWindow(startMs, endMs)
        val usage = mutableListOf<ReducedActivitySignal>()
        val screen = mutableListOf<ReducedActivitySignal>()
        for (event in events) {
            if (event.occurredAtMs < startMs || event.occurredAtMs >= endMs) continue
            when (event.eventType) {
                ActivitySignalPolicy.ACTIVITY_RESUMED -> {
                    val category = event.packageId?.let(categoryMapping::get) ?: continue
                    usage += ReducedActivitySignal(
                        type = "usage_category",
                        signalAtMs = event.occurredAtMs,
                        category = category,
                    )
                }
                KEYGUARD_HIDDEN -> screen += ReducedActivitySignal(
                    type = "user_present",
                    signalAtMs = event.occurredAtMs,
                )
                SCREEN_INTERACTIVE -> screen += ReducedActivitySignal(
                    type = "screen_interactive",
                    signalAtMs = event.occurredAtMs,
                )
                SCREEN_NON_INTERACTIVE -> screen += ReducedActivitySignal(
                    type = "screen_non_interactive",
                    signalAtMs = event.occurredAtMs,
                )
            }
        }
        return ReducedActivityUsageBatch(
            usageSignals = usage.distinct().sortedBy { it.signalAtMs },
            screenSignals = screen.distinct().sortedBy { it.signalAtMs },
        )
    }
}
