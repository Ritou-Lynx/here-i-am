package com.memexlab.bedwatch

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

class JsonlLogTest {
    @get:Rule val temp = TemporaryFolder()
    private val zone = ZoneId.of("UTC")
    private fun record(day: String, pushed: Boolean = false) = FrameRecord(
        LocalDate.parse(day).atStartOfDay(zone).toInstant().toEpochMilli(),
        FrameFeatures(true, null, 1.5f, 40f), Verdict.UNKNOWN, pushed)
    @Test fun exactlySevenNumericFieldsAndUnknownEyeSentinel() {
        val line = record("2026-10-24").json()
        val parts = line.removeSurrounding("{", "}").split(',')
        assertEquals(listOf("t", "face", "eyes_open", "glow", "luma", "verdict", "pushed"),
            parts.map { it.substringBefore(':').trim('"') })
        assertTrue(parts.all { it.substringAfter(':').toDoubleOrNull()?.isFinite() == true })
        assertTrue(line.contains("\"eyes_open\":-1.0"))
    }
    @Test fun nonFiniteInputNeverProducesInvalidJsonNumbers() {
        val line = record("2026-10-24").copy(features = FrameFeatures(false, Float.NaN, Float.POSITIVE_INFINITY, Float.NaN)).json()
        assertFalse(line.contains("NaN")); assertFalse(line.contains("Infinity"))
    }
    @Test fun pushFailureUsesNumericFieldWithoutExtraMetadata() {
        assertTrue(record("2026-10-24").copy(pushFailed = true).json().contains("\"pushed\":-1"))
        assertTrue(record("2026-10-24", true).json().contains("\"pushed\":1"))
    }
    @Test fun keepsTodayAndSixPreviousDays() {
        val log = JsonlLog(temp.root, zone)
        for (day in 15..24) log.append(record("2026-10-$day"))
        assertEquals((18..24).map { "2026-10-$it.jsonl" }, temp.root.list()!!.sorted())
    }
    @Test fun cleanupIgnoresUnrelatedFiles() {
        val other = File(temp.root, "keep.txt").apply { writeText("synthetic") }
        JsonlLog(temp.root, zone).cleanup(LocalDate.parse("2026-10-24"))
        assertTrue(other.exists())
    }
    @Test fun recentTwentyFramesSpanDateFilesInTimeOrder() {
        val log = JsonlLog(temp.root, zone)
        for (day in 23..24) repeat(15) { log.append(record("2026-10-$day").copy(t = record("2026-10-$day").t + it)) }
        val rows = log.recent()
        assertEquals(20, rows.size)
        assertTrue(rows.first().contains("\"t\":${record("2026-10-23").t + 10},"))
        assertTrue(rows.last().contains("\"t\":${record("2026-10-24").t + 14},"))
    }
}
