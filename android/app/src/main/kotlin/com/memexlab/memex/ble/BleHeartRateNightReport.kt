package com.memexlab.memex.ble

import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Read-only reports never flush or close the service writer; its last ~7 seconds may be absent. */
object BleHeartRateNightReport {
    private val numberPattern = Regex("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
    private val disconnectStatuses = setOf("disconnected", "reconnecting", "bluetoothOff", "stopped")
    data class Report(val summary: Map<String, Any?>, val minutes: List<Map<String, Any?>>)
    private data class Row(val timestamp: Long, val bpm: Double?, val status: String?)
    private class Minute {
        var samples = 0
        var suspect = 0
        var statuses = 0
        val seconds = mutableSetOf<Long>()
        val bpms = mutableListOf<Double>()
    }

    fun window(night: LocalDate, zone: ZoneId): Pair<Long, Long> =
        night.atTime(18, 0).atZone(zone).toInstant().toEpochMilli() to
            night.plusDays(1).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()

    fun latestNight(nowMs: Long, zone: ZoneId): LocalDate {
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        return now.toLocalDate().minusDays(if (now.hour >= 18) 0 else 1)
    }

    fun parseNight(value: String): LocalDate {
        require(Regex("\\d{4}-\\d{2}-\\d{2}").matches(value))
        return LocalDate.parse(value)
    }

    fun summarize(
        lines: Sequence<String>, startMs: Long, endMs: Long, zone: ZoneId,
        onRawLine: (String) -> Unit = {},
    ): Report {
        val buckets = sortedMapOf<Long, Minute>()
        val bpms = mutableListOf<Double>()
        var first: Long? = null
        var last: Long? = null
        var samples = 0
        var suspect = 0
        var statuses = 0
        var disconnects = 0
        var malformed = 0
        var gaps = 0
        var maxGap = 0.0
        var totalGap = 0.0
        for (line in lines) {
            val row = runCatching { parseRow(line) }.getOrNull()
            if (row == null) { malformed++; continue }
            if (row.timestamp < startMs || row.timestamp >= endMs) continue
            onRawLine(line)
            val bucket = buckets.getOrPut(Math.floorDiv(row.timestamp, 60_000L)) { Minute() }
            if (row.bpm != null) {
                val previous = last
                if (previous != null && row.timestamp - previous > 15_000L) {
                    val seconds = (row.timestamp - previous) / 1000.0 - 1
                    gaps++
                    maxGap = maxOf(maxGap, seconds)
                    totalGap += seconds
                }
                if (first == null) first = row.timestamp
                last = row.timestamp
                samples++
                bucket.samples++
                bucket.seconds.add(Math.floorDiv(row.timestamp, 1000L))
                if (row.bpm in 30.0..220.0) {
                    bpms.add(row.bpm)
                    bucket.bpms.add(row.bpm)
                } else { suspect++; bucket.suspect++ }
            } else {
                statuses++
                bucket.statuses++
                if (row.status in disconnectStatuses) disconnects++
            }
        }
        val firstMinute = first?.let { Math.floorDiv(it, 60_000L) }
        val lastMinute = last?.let { Math.floorDiv(it, 60_000L) }
        val minutes = if (firstMinute == null || lastMinute == null) emptyList() else
            (firstMinute..lastMinute).map { minute ->
                val bucket = buckets[minute] ?: Minute()
                linkedMapOf<String, Any?>(
                    "minuteStart" to DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(
                        Instant.ofEpochMilli(minute * 60_000L).atZone(zone)),
                    "samples" to bucket.samples, "bpmMedian" to median(bucket.bpms),
                    "bpmMin" to bucket.bpms.minOrNull(), "bpmMax" to bucket.bpms.maxOrNull(),
                    "suspect" to bucket.suspect, "missingSeconds" to (60 - bucket.seconds.size).coerceAtLeast(0),
                    "statusEvents" to bucket.statuses,
                )
            }
        return Report(linkedMapOf(
            "night" to Instant.ofEpochMilli(startMs).atZone(zone).toLocalDate().toString(),
            "windowStartMs" to startMs, "windowEndMs" to endMs,
            "firstSampleMs" to first, "lastSampleMs" to last, "samples" to samples,
            "suspectSamples" to suspect, "statusEvents" to statuses, "disconnectEvents" to disconnects,
            "gapCount" to if (first == null) null else gaps,
            "maxGapSeconds" to if (first == null) null else maxGap,
            "totalGapSeconds" to if (first == null) null else totalGap,
            "coveredMinutes" to if (first == null) null else buckets.values.count { it.bpms.isNotEmpty() },
            // Inclusive minute buckets keep coverage defined even for a single sample.
            "spanMinutes" to if (firstMinute == null || lastMinute == null) null else lastMinute - firstMinute + 1,
            "bpmMedian" to median(bpms), "bpmMin" to bpms.minOrNull(), "bpmMax" to bpms.maxOrNull(),
            "malformedLines" to malformed,
        ), minutes)
    }

    private fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        return (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2
    }

    private fun parseRow(line: String): Row {
        val json = Json(line).parse() as? Map<*, *> ?: error("object required")
        val timestamp = json["timestampMs"] as? Number ?: error("timestamp required")
        require(timestamp.toDouble().isFinite())
        return when (json["type"]) {
            "sample" -> {
                val bpm = (json["bpm"] as? Number)?.toDouble() ?: error("bpm required")
                require(bpm.isFinite())
                Row(timestamp.toLong(), bpm, null)
            }
            "status" -> Row(timestamp.toLong(), null, json["status"] as? String)
            else -> error("unknown type")
        }
    }

    /** Reader scopes enclose consumption, so even an export write failure closes both readers. */
    fun readNight(directory: File, night: LocalDate, zone: ZoneId, onRawLine: (String) -> Unit = {}): Report {
        val (start, end) = window(night, zone)
        return withLines(File(directory, "$night.jsonl")) { first ->
            withLines(File(directory, "${night.plusDays(1)}.jsonl")) { second ->
                summarize(first + second, start, end, zone, onRawLine)
            }
        }
    }

    private fun <T> withLines(file: File, consume: (Sequence<String>) -> T): T =
        if (file.exists()) file.bufferedReader(Charsets.UTF_8).useLines(consume) else consume(emptySequence())

    val csvFields = listOf("minuteStart", "samples", "bpmMedian", "bpmMin", "bpmMax", "suspect", "missingSeconds", "statusEvents")
    fun csvCell(value: Any?): String {
        val text = value?.toString() ?: ""
        return if (text.any { it in ",\"\r\n" }) "\"${text.replace("\"", "\"\"")}\"" else text
    }

    fun export(directory: File, cacheDir: File, night: LocalDate, zone: ZoneId, today: LocalDate): Map<String, Any?> {
        val output = File(cacheDir, "ble_heart_rate_export")
        if (!output.isDirectory && !output.mkdirs()) throw IOException("Export directory unavailable")
        for (file in output.listFiles() ?: throw IOException("Export directory unreadable")) {
            if (!file.isFile || !file.delete()) throw IOException("Export cleanup failed")
        }
        val jsonl = File(output, "heart-rate-$night.jsonl")
        val csv = File(output, "heart-rate-$night-minutes.csv")
        try {
            val report = jsonl.bufferedWriter(Charsets.UTF_8).use { writer ->
                if (night.isBefore(today.minusDays(13)) || night.isAfter(today)) {
                    val (start, end) = window(night, zone)
                    summarize(emptySequence(), start, end, zone)
                } else readNight(directory, night, zone) { writer.write(it); writer.newLine() }
            }
            csv.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(csvFields.joinToString(",")); writer.newLine()
                for (minute in report.minutes) {
                    writer.write(csvFields.joinToString(",") { csvCell(minute[it]) }); writer.newLine()
                }
            }
            return mapOf("jsonlPath" to jsonl.absolutePath, "csvPath" to csv.absolutePath, "summary" to report.summary)
        } catch (error: Exception) {
            jsonl.delete(); csv.delete()
            throw error
        }
    }

    /** Small strict JSON reader keeps the report usable on the JVM without Android JSON stubs. */
    private class Json(private val text: String) {
        private var index = 0
        fun parse(): Any? {
            val result = value(0)
            whitespace(); require(index == text.length)
            return result
        }
        private fun whitespace() { while (index < text.length && text[index] in " \t\r\n") index++ }
        private fun take(char: Char): Boolean {
            whitespace()
            return if (index < text.length && text[index] == char) { index++; true } else false
        }
        private fun value(depth: Int): Any? {
            require(depth < 64)
            whitespace()
            return when (text[index]) {
                '{' -> {
                    index++
                    val map = mutableMapOf<String, Any?>()
                    if (!take('}')) {
                        do {
                            whitespace(); val key = string(); require(take(':'))
                            map[key] = value(depth + 1)
                        } while (take(','))
                        require(take('}'))
                    }
                    map
                }
                '[' -> {
                    index++
                    val list = mutableListOf<Any?>()
                    if (!take(']')) {
                        do { list.add(value(depth + 1)) } while (take(','))
                        require(take(']'))
                    }
                    list
                }
                '"' -> string()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                else -> {
                    val match = numberPattern.find(text, index)
                    require(match != null && match.range.first == index)
                    index = match.range.last + 1
                    match.value.toLongOrNull() ?: match.value.toDouble().also { require(it.isFinite()) }
                }
            }
        }
        private fun literal(word: String, result: Any?): Any? {
            require(text.startsWith(word, index)); index += word.length; return result
        }
        private fun string(): String {
            require(text[index++] == '"')
            val result = StringBuilder()
            while (true) {
                val char = text[index++]
                if (char == '"') return result.toString()
                require(char >= ' ')
                if (char != '\\') result.append(char) else {
                    result.append(when (val escaped = text[index++]) {
                        '"', '\\', '/' -> escaped
                        'b' -> '\b'; 'f' -> '\u000C'; 'n' -> '\n'; 'r' -> '\r'; 't' -> '\t'
                        'u' -> {
                            val hex = text.substring(index, index + 4)
                            require(hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' })
                            index += 4
                            hex.toInt(16).toChar()
                        }
                        else -> error("invalid escape")
                    })
                }
            }
        }
    }
}
