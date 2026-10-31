package com.memexlab.memex.ble

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId

class BleHeartRateNightReportTest {
    @get:Rule val temporary = TemporaryFolder()
    private val zone = ZoneId.of("Asia/Shanghai")
    private val night = LocalDate.of(2026, 10, 20)
    private val window = BleHeartRateNightReport.window(night, zone)
    private fun ms(time: String) = OffsetDateTime.parse(time + "+08:00").toInstant().toEpochMilli()
    private fun sample(time: Long, bpm: Number = 80) = """{"type":"sample","timestampMs":$time,"bpm":$bpm}"""
    private fun status(time: Long, status: String) = """{"type":"status","timestampMs":$time,"status":"$status","reason":"synthetic"}"""
    private fun report(vararg lines: String) = BleHeartRateNightReport.summarize(lines.asSequence(), window.first, window.second, zone)

    @Test fun streamsBothDatesAcrossMidnightAndPreservesRawLines() {
        val input = temporary.newFolder()
        val before = sample(ms("2026-10-20T23:59:59"))
        val after = "  " + sample(ms("2026-10-21T00:00:00"))
        File(input, "$night.jsonl").writeText(before + "\n")
        File(input, "${night.plusDays(1)}.jsonl").writeText(after + "\n")
        val output = temporary.newFolder()
        val exported = BleHeartRateNightReport.export(input, output, night, zone, night.plusDays(1))
        val summary = exported["summary"] as Map<*, *>
        assertEquals(2, summary["samples"])
        assertEquals(2L, summary["spanMinutes"])
        assertEquals(listOf(before, after), File(exported["jsonlPath"] as String).readLines())
        val csv = File(exported["csvPath"] as String).readLines()
        assertEquals("minuteStart,samples,bpmMedian,bpmMin,bpmMax,suspect,missingSeconds,statusEvents", csv[0])
        assertTrue(csv[1].startsWith("2026-10-20T23:59:00+08:00,1,80.0,80.0,80.0,0,59,0"))
        assertEquals(3, csv.size)
    }

    @Test fun windowIsLeftClosedRightOpen() {
        val result = report(sample(window.first - 1000), sample(window.first), sample(window.second - 1), sample(window.second))
        assertEquals(2, result.summary["samples"])
        assertEquals(window.first, result.summary["firstSampleMs"])
        assertEquals(window.second - 1, result.summary["lastSampleMs"])
        val raw = mutableListOf<String>()
        BleHeartRateNightReport.summarize(sequenceOf(
            sample(window.first - 1), sample(window.first), status(window.first + 1, "live"), sample(window.second),
        ), window.first, window.second, zone, raw::add)
        assertEquals(listOf(sample(window.first), status(window.first + 1, "live")), raw)
    }

    @Test fun gapThresholdIsStrictlyGreaterThanFifteenSeconds() {
        val start = window.first
        val result = report(sample(start), sample(start + 15_000), sample(start + 31_000), sample(start + 62_000))
        assertEquals(2, result.summary["gapCount"])
        assertEquals(30.0, result.summary["maxGapSeconds"])
        assertEquals(45.0, result.summary["totalGapSeconds"])
    }

    @Test fun suspectsDoNotEnterStatisticsButStillCountAsSamplesAndSeconds() {
        val start = window.first
        val result = report(sample(start, 29), sample(start + 1000, 30), sample(start + 2000, 220), sample(start + 3000, 221))
        assertEquals(4, result.summary["samples"])
        assertEquals(2, result.summary["suspectSamples"])
        assertEquals(125.0, result.summary["bpmMedian"])
        assertEquals(30.0, result.summary["bpmMin"])
        assertEquals(220.0, result.summary["bpmMax"])
        assertEquals(2, result.minutes.single()["suspect"])
        assertEquals(56, result.minutes.single()["missingSeconds"])
    }

    @Test fun classifiesAllDisconnectStatusesAndCountsStatusesOutsideSampleSpan() {
        val start = window.first
        val lines = listOf("disconnected", "reconnecting", "bluetoothOff", "stopped", "live", "connecting", "stale")
            .mapIndexed { index, value -> status(start + index * 1000, value) }
        val result = report(*(lines + listOf(sample(start + 60_000), status(start + 60_500, "live"), sample(start + 61_000))).toTypedArray())
        assertEquals(8, result.summary["statusEvents"])
        assertEquals(4, result.summary["disconnectEvents"])
        assertEquals(1, result.minutes.single()["statusEvents"])
    }

    @Test fun malformedLinesAreSkippedWithoutCoercingStringsToNumbers() {
        val result = report("{", "[]", "null", "{}", """{"type":"sample","timestampMs":1,"bpm":"80"}""",
            """{"type":"status","timestampMs":"1"}""", sample(window.first) + "trailing", sample(window.first))
        assertEquals(7, result.summary["malformedLines"])
        assertEquals(1, result.summary["samples"])
    }

    @Test fun optionalNestedJsonAndEscapedStatusReasonAreAccepted() {
        val line = """{"type":"sample","timestampMs":${window.first},"bpm":8e1,"contactSupported":true,"contactDetected":null,"rrIntervalsSeconds":[1.0],"extra":{"text":"a\n\u0041\""}}"""
        assertEquals(1, report(line).summary["samples"])
        assertEquals(0, report(line).summary["malformedLines"])
    }

    @Test fun emptyNightAndStatusOnlyNightHaveNullSampleStatistics() {
        for (result in listOf(report(), report(status(window.first, "stopped")))) {
            assertEquals(0, result.summary["samples"])
            for (field in listOf("firstSampleMs", "lastSampleMs", "gapCount", "maxGapSeconds", "totalGapSeconds", "coveredMinutes", "spanMinutes", "bpmMedian", "bpmMin", "bpmMax")) {
                assertNull(field, result.summary[field])
            }
            assertTrue(result.minutes.isEmpty())
        }
    }

    @Test fun missingSecondsDeduplicateSecondsAndIncludeEmptyMinutes() {
        val start = window.first
        val result = report(sample(start), sample(start + 500), sample(start + 120_000, 250))
        assertEquals(3, result.minutes.size)
        assertEquals(59, result.minutes[0]["missingSeconds"])
        assertEquals(60, result.minutes[1]["missingSeconds"])
        assertEquals(59, result.minutes[2]["missingSeconds"])
        assertEquals(1, result.summary["coveredMinutes"])
        assertEquals(3L, result.summary["spanMinutes"])
        assertNull(result.minutes[2]["bpmMedian"])
    }

    @Test fun singleSampleHasOneMinuteOfCoverage() {
        val result = report(sample(window.first))
        assertEquals(1, result.summary["coveredMinutes"])
        assertEquals(1L, result.summary["spanMinutes"])
    }

    @Test fun csvEscapesQuotesCommasAndLineBreaks() {
        assertEquals("", BleHeartRateNightReport.csvCell(null))
        assertEquals("simple", BleHeartRateNightReport.csvCell("simple"))
        assertEquals("\"a,b\"", BleHeartRateNightReport.csvCell("a,b"))
        assertEquals("\"a\"\"b\n\"", BleHeartRateNightReport.csvCell("a\"b\n"))
    }

    @Test fun missingFilesAndExpiredNightsExportHeaderOnlyAndClearPreviousFiles() {
        val input = temporary.newFolder()
        val output = temporary.newFolder()
        File(input, "$night.jsonl").writeText(sample(window.first))
        BleHeartRateNightReport.export(input, output, night, zone, night.plusDays(1))
        val expired = night.minusDays(20)
        File(input, "$expired.jsonl").writeText(sample(BleHeartRateNightReport.window(expired, zone).first))
        val exported = BleHeartRateNightReport.export(input, output, expired, zone, night)
        assertEquals(2, File(output, "ble_heart_rate_export").listFiles()!!.size)
        assertEquals("", File(exported["jsonlPath"] as String).readText())
        assertEquals(1, File(exported["csvPath"] as String).readLines().size)
        assertEquals(0, BleHeartRateNightReport.readNight(input, night.plusDays(3), zone).summary["samples"])
    }

    @Test fun readFailureClosesReadersAndExportRemovesPartialFiles() {
        val input = temporary.newFolder()
        val first = File(input, "$night.jsonl").apply { writeText(sample(window.first)) }
        val second = File(input, "${night.plusDays(1)}.jsonl").apply { writeText(sample(window.first + 60_000)) }
        assertTrue(runCatching {
            BleHeartRateNightReport.readNight(input, night, zone) { throw java.io.IOException("synthetic") }
        }.isFailure)
        assertTrue(first.delete())
        assertTrue(second.delete())
        // A directory where a daily file is expected forces a read error without real data.
        first.mkdir()
        val cache = temporary.newFolder()
        assertTrue(runCatching { BleHeartRateNightReport.export(input, cache, night, zone, night) }.isFailure)
        assertEquals(0, File(cache, "ble_heart_rate_export").listFiles()!!.size)
    }

    @Test fun latestNightSwitchesAtEighteenAndDateParsingIsStrict() {
        assertEquals(night.minusDays(1), BleHeartRateNightReport.latestNight(window.first - 1, zone))
        assertEquals(night, BleHeartRateNightReport.latestNight(window.first, zone))
        assertEquals(night, BleHeartRateNightReport.parseNight("2026-10-20"))
        for (value in listOf("2026-2-03", "2026-02-30", "../2026-10-20", "2026-10-20T00:00:00")) {
            assertTrue(runCatching { BleHeartRateNightReport.parseNight(value) }.isFailure)
        }
    }
}
