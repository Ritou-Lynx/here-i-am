package com.memexlab.memex.activity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivitySignalPolicyTest {
    private val categories = mapOf(
        "private.chat.app" to "chat",
        "private.reader.app" to "reading",
    )

    @Test
    fun `permission lifecycle distinguishes denied granted and revoked`() {
        val lifecycle = UsagePermissionLifecycle()
        assertEquals(UsagePermissionState.DENIED, lifecycle.observe(false))
        assertEquals(UsagePermissionState.GRANTED, lifecycle.observe(true))
        assertEquals(UsagePermissionState.REVOKED, lifecycle.observe(false))
        assertEquals(UsagePermissionState.REVOKED, lifecycle.observe(false))
    }

    @Test
    fun `denied and revoked permissions produce no usage activity`() {
        val raw = listOf(RawUsageActivityEvent("private.chat.app", 1, 100L))
        for (permission in listOf(UsagePermissionState.DENIED, UsagePermissionState.REVOKED)) {
            assertTrue(
                ActivitySignalPolicy.reduceUsageEvents(0L, 200L, permission, categories, raw).isEmpty(),
            )
        }
    }

    @Test
    fun `query window is start inclusive and end exclusive`() {
        val raw = listOf(
            RawUsageActivityEvent("private.chat.app", 1, 99L),
            RawUsageActivityEvent("private.chat.app", 1, 100L),
            RawUsageActivityEvent("private.reader.app", 1, 199L),
            RawUsageActivityEvent("private.chat.app", 1, 200L),
        )
        val signals = ActivitySignalPolicy.reduceUsageEvents(
            100L,
            200L,
            UsagePermissionState.GRANTED,
            categories,
            raw,
        )
        assertEquals(listOf(100L, 199L), signals.map { it.signalAtMs })
    }

    @Test
    fun `unknown events and packages without mapping are filtered`() {
        val raw = listOf(
            RawUsageActivityEvent("private.chat.app", 2, 100L),
            RawUsageActivityEvent("private.unmapped.app", 1, 101L),
            RawUsageActivityEvent("private.chat.app", 99, 102L),
        )
        assertTrue(
            ActivitySignalPolicy.reduceUsageEvents(
                0L,
                200L,
                UsagePermissionState.GRANTED,
                categories,
                raw,
            ).isEmpty(),
        )
    }

    @Test
    fun `mapped foreground usage returns only coarse category and time`() {
        val signals = ActivitySignalPolicy.reduceUsageEvents(
            0L,
            200L,
            UsagePermissionState.GRANTED,
            categories,
            listOf(
                RawUsageActivityEvent("private.reader.app", 1, 120L),
                RawUsageActivityEvent("private.chat.app", 1, 110L),
            ),
        )
        assertEquals(listOf("chat", "reading"), signals.map { it.category })
        val encoded = signals.map { it.toFlutterMap().toString() }.joinToString()
        assertFalse(encoded.contains("private."))
        assertFalse(encoded.contains("package", ignoreCase = true))
        assertFalse(encoded.contains("appName", ignoreCase = true))
    }

    @Test
    fun `duplicate reduced signals are removed without exposing package identity`() {
        val signals = ActivitySignalPolicy.reduceUsageEvents(
            0L,
            200L,
            UsagePermissionState.GRANTED,
            categories,
            listOf(
                RawUsageActivityEvent("private.chat.app", 1, 110L),
                RawUsageActivityEvent("private.chat.app", 1, 110L),
            ),
        )
        assertEquals(1, signals.size)
        assertEquals(
            mapOf("type" to "usage_category", "signal_at_ms" to 110L, "category" to "chat"),
            signals.single().toFlutterMap(),
        )
    }

    @Test
    fun `screen signals come only from raw usage event timestamps`() {
        val reduced = ActivityUsageEventReducer.reduce(
            events = listOf(
                RawActivityUsageEvent(null, ActivityUsageEventReducer.SCREEN_INTERACTIVE, 41L),
                RawActivityUsageEvent(null, ActivityUsageEventReducer.SCREEN_NON_INTERACTIVE, 42L),
                RawActivityUsageEvent(null, ActivityUsageEventReducer.KEYGUARD_HIDDEN, 43L),
                RawActivityUsageEvent(null, 999, 44L),
            ),
            startMs = 40L,
            endMs = 50L,
            categoryMapping = emptyMap(),
        )
        assertEquals(
            listOf("screen_interactive", "screen_non_interactive", "user_present"),
            reduced.screenSignals.map { it.type },
        )
        assertEquals(listOf(41L, 42L, 43L), reduced.screenSignals.map { it.signalAtMs })
    }

    @Test
    fun `mapping and window failures expose fixed codes only`() {
        val badMapping = runCatching {
            ActivitySignalPolicy.validateCategoryMapping(mapOf("private.app" to "private-category"))
        }.exceptionOrNull() as ActivitySignalPolicyException
        assertEquals("invalid_category_mapping", badMapping.fixedCode)
        assertEquals("invalid_category_mapping", badMapping.message)

        val badWindow = runCatching {
            ActivitySignalPolicy.reduceUsageEvents(
                5L,
                5L,
                UsagePermissionState.GRANTED,
                categories,
                emptyList(),
            )
        }.exceptionOrNull() as ActivitySignalPolicyException
        assertEquals("invalid_query_window", badWindow.fixedCode)
    }

    @Test
    fun `invalid query window is rejected before raw query side effect`() {
        for ((startMs, endMs) in listOf(-1L to 5L, 5L to 5L, 6L to 5L)) {
            var rawQueries = 0
            val failure = runCatching {
                ActivitySignalPolicy.queryUsageEvents(
                    startMs = startMs,
                    endMs = endMs,
                    permission = UsagePermissionState.GRANTED,
                    categoryMapping = categories,
                    rawQuery = { _, _ ->
                        rawQueries++
                        emptyList()
                    },
                )
            }.exceptionOrNull() as ActivitySignalPolicyException
            assertEquals("invalid_query_window", failure.fixedCode)
            assertEquals(0, rawQueries)
        }
    }

    @Test
    fun `query request rejects missing unknown and non integer fields`() {
        val invalid = listOf(
            mapOf("start_ms" to 0L),
            mapOf("start_ms" to 0L, "end_ms" to 1L, "private" to "secret"),
            mapOf("start_ms" to 0.5, "end_ms" to 1L),
        )
        for (request in invalid) {
            val failure = runCatching {
                ActivitySignalRequestPolicy.parseQuery(request)
            }.exceptionOrNull() as ActivitySignalPolicyException
            assertEquals(
                if (request.keys == setOf("start_ms", "end_ms")) {
                    "invalid_query_window"
                } else {
                    "invalid_arguments"
                },
                failure.fixedCode,
            )
        }
    }

    @Test
    fun `activation request rejects missing unknown and duplicate fields before use`() {
        val valid = mapOf(
            "enabled" to true,
            "integrity_authority_ready" to true,
            "bound_sources" to listOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE),
            "category_mapping" to categories,
        )
        assertEquals(
            setOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE),
            ActivitySignalRequestPolicy.parseActivation(valid).boundSources,
        )
        for (request in listOf(
            valid - "category_mapping",
            valid + ("private" to "secret"),
            valid + ("bound_sources" to listOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_USAGE_EVENTS_SOURCE)),
        )) {
            val failure = runCatching {
                ActivitySignalRequestPolicy.parseActivation(request)
            }.exceptionOrNull() as ActivitySignalPolicyException
            assertEquals("invalid_arguments", failure.fixedCode)
        }
    }

    @Test
    fun `activation gate requires enabled integrity authority and both bindings`() {
        assertEquals(
            ActivityActivationDecision(false, "collector_disabled"),
            ActivityActivationGate.decide(false, true, setOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE)),
        )
        assertEquals(
            ActivityActivationDecision(false, "integrity_authority_missing"),
            ActivityActivationGate.decide(true, false, setOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE)),
        )
        assertEquals(
            ActivityActivationDecision(false, "source_binding_missing"),
            ActivityActivationGate.decide(true, true, setOf(ANDROID_USAGE_EVENTS_SOURCE)),
        )
        assertTrue(
            ActivityActivationGate.decide(
                true,
                true,
                setOf(ANDROID_USAGE_EVENTS_SOURCE, ANDROID_SCREEN_STATE_SOURCE),
            ).active,
        )
    }
}
