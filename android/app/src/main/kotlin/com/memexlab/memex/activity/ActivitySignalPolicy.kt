package com.memexlab.memex.activity

internal const val ANDROID_USAGE_EVENTS_SOURCE = "android_usage_events"
internal const val ANDROID_SCREEN_STATE_SOURCE = "android_screen_state"

internal val ALLOWED_COARSE_CATEGORIES = setOf(
    "chat",
    "social",
    "video",
    "reading",
    "work",
    "other",
)

internal data class RawUsageActivityEvent(
    val packageId: String,
    val eventType: Int,
    val signalAtMs: Long,
)

internal data class ReducedActivitySignal(
    val type: String,
    val signalAtMs: Long,
    val category: String? = null,
) {
    fun toFlutterMap(): Map<String, Any> = buildMap {
        put("type", type)
        put("signal_at_ms", signalAtMs)
        category?.let { put("category", it) }
    }
}

internal enum class UsagePermissionState(val wireValue: String) {
    GRANTED("granted"),
    DENIED("denied"),
    REVOKED("revoked"),
}

/** Tracks revocation without treating a first unavailable observation as revoked. */
internal class UsagePermissionLifecycle {
    private var wasGranted = false

    fun observe(granted: Boolean): UsagePermissionState {
        if (granted) {
            wasGranted = true
            return UsagePermissionState.GRANTED
        }
        return if (wasGranted) UsagePermissionState.REVOKED else UsagePermissionState.DENIED
    }
}

internal class ActivitySignalPolicyException(val fixedCode: String) : Exception(fixedCode)

internal data class ActivityActivationRequest(
    val enabled: Boolean,
    val integrityAuthorityReady: Boolean,
    val boundSources: Set<String>,
    val categoryMapping: Map<String, String>,
)

internal data class UsageQueryWindow(
    val startMs: Long,
    val endMs: Long,
)

/** Exact MethodChannel request contracts, kept free of Android side effects. */
internal object ActivitySignalRequestPolicy {
    private val activationKeys = setOf(
        "enabled",
        "integrity_authority_ready",
        "bound_sources",
        "category_mapping",
    )
    private val queryKeys = setOf("start_ms", "end_ms")

    fun parseActivation(arguments: Any?): ActivityActivationRequest {
        val args = exactMap(arguments, activationKeys)
        val enabled = args["enabled"] as? Boolean
            ?: throw ActivitySignalPolicyException("invalid_arguments")
        val integrityReady = args["integrity_authority_ready"] as? Boolean
            ?: throw ActivitySignalPolicyException("invalid_arguments")
        val sourceList = args["bound_sources"] as? List<*>
            ?: throw ActivitySignalPolicyException("invalid_arguments")
        if (sourceList.any { it !is String }) {
            throw ActivitySignalPolicyException("invalid_arguments")
        }
        val sources = sourceList.filterIsInstance<String>().toSet()
        if (sources.size != sourceList.size) {
            throw ActivitySignalPolicyException("invalid_arguments")
        }
        val rawMapping = args["category_mapping"] as? Map<*, *>
            ?: throw ActivitySignalPolicyException("invalid_arguments")
        return ActivityActivationRequest(
            enabled = enabled,
            integrityAuthorityReady = integrityReady,
            boundSources = sources,
            categoryMapping = ActivitySignalPolicy.validateCategoryMapping(rawMapping),
        )
    }

    fun parseQuery(arguments: Any?): UsageQueryWindow {
        val args = exactMap(arguments, queryKeys)
        val startMs = integer(args["start_ms"])
        val endMs = integer(args["end_ms"])
        return ActivitySignalPolicy.validateQueryWindow(startMs, endMs)
    }

    private fun exactMap(arguments: Any?, expectedKeys: Set<String>): Map<*, *> {
        val args = arguments as? Map<*, *>
            ?: throw ActivitySignalPolicyException("invalid_arguments")
        if (args.keys != expectedKeys) {
            throw ActivitySignalPolicyException("invalid_arguments")
        }
        return args
    }

    private fun integer(value: Any?): Long = when (value) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> throw ActivitySignalPolicyException("invalid_query_window")
    }
}

internal object ActivitySignalPolicy {
    // UsageEvents.Event.ACTIVITY_RESUMED and the deprecated MOVE_TO_FOREGROUND alias are 1.
    const val ACTIVITY_RESUMED = 1

    fun validateQueryWindow(startMs: Long, endMs: Long): UsageQueryWindow {
        if (startMs < 0L || endMs <= startMs) {
            throw ActivitySignalPolicyException("invalid_query_window")
        }
        return UsageQueryWindow(startMs, endMs)
    }

    fun validateCategoryMapping(input: Map<*, *>): Map<String, String> {
        val validated = linkedMapOf<String, String>()
        for ((rawPackage, rawCategory) in input) {
            val packageId = rawPackage as? String
            val category = rawCategory as? String
            if (packageId == null ||
                packageId.isBlank() ||
                packageId.length > 255 ||
                category == null ||
                category !in ALLOWED_COARSE_CATEGORIES
            ) {
                throw ActivitySignalPolicyException("invalid_category_mapping")
            }
            validated[packageId] = category
        }
        return validated.toMap()
    }

    /**
     * Reduces one query window to privacy-safe signals. The raw package id is
     * used only for the in-memory lookup and is never included in the result.
     * Window semantics are [startMs, endMs).
     */
    fun reduceUsageEvents(
        startMs: Long,
        endMs: Long,
        permission: UsagePermissionState,
        categoryMapping: Map<String, String>,
        rawEvents: List<RawUsageActivityEvent>,
    ): List<ReducedActivitySignal> {
        validateQueryWindow(startMs, endMs)
        if (permission != UsagePermissionState.GRANTED) return emptyList()

        return rawEvents
            .asSequence()
            .filter { event ->
                event.eventType == ACTIVITY_RESUMED &&
                    event.signalAtMs >= startMs &&
                    event.signalAtMs < endMs
            }
            .mapNotNull { event ->
                categoryMapping[event.packageId]?.let { category ->
                    ReducedActivitySignal(
                        type = "usage_category",
                        signalAtMs = event.signalAtMs,
                        category = category,
                    )
                }
            }
            .distinct()
            .sortedBy { it.signalAtMs }
            .toList()
    }

    /** Validates the window before invoking the raw UsageEvents boundary. */
    fun queryUsageEvents(
        startMs: Long,
        endMs: Long,
        permission: UsagePermissionState,
        categoryMapping: Map<String, String>,
        rawQuery: (Long, Long) -> List<RawUsageActivityEvent>,
    ): List<ReducedActivitySignal> {
        validateQueryWindow(startMs, endMs)
        if (permission != UsagePermissionState.GRANTED) return emptyList()
        return reduceUsageEvents(
            startMs = startMs,
            endMs = endMs,
            permission = permission,
            categoryMapping = categoryMapping,
            rawEvents = rawQuery(startMs, endMs),
        )
    }

}

internal data class ActivityActivationDecision(
    val active: Boolean,
    val fixedCode: String,
)

internal object ActivityActivationGate {
    private val requiredSources = setOf(
        ANDROID_USAGE_EVENTS_SOURCE,
        ANDROID_SCREEN_STATE_SOURCE,
    )

    fun decide(
        enabled: Boolean,
        integrityAuthorityReady: Boolean,
        boundSources: Set<String>,
    ): ActivityActivationDecision = when {
        !enabled -> ActivityActivationDecision(false, "collector_disabled")
        !integrityAuthorityReady -> ActivityActivationDecision(false, "integrity_authority_missing")
        boundSources != requiredSources -> ActivityActivationDecision(false, "source_binding_missing")
        else -> ActivityActivationDecision(true, "ready")
    }
}
