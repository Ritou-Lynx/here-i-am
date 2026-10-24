package com.memexlab.bedwatch

import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

data class FrameRecord(val t: Long, val features: FrameFeatures, val verdict: Verdict, val pushed: Boolean, val pushFailed: Boolean = false) {
    fun json(): String {
        fun finite(value: Float): Float = if (value.isFinite()) value else 0f
        return "{\"t\":$t,\"face\":${if (features.face) 1 else 0}," +
            "\"eyes_open\":${features.eyesOpen?.let(::finite) ?: -1f},\"glow\":${finite(features.glow)}," +
            "\"luma\":${finite(features.frameLuma)},\"verdict\":${verdict.ordinal},\"pushed\":${if (pushed) 1 else if (pushFailed) -1 else 0}}"
    }
}

class JsonlLog(private val directory: File, private val zone: ZoneId = ZoneId.systemDefault()) {
    @Synchronized fun append(record: FrameRecord) {
        check(directory.isDirectory || directory.mkdirs())
        val date = Instant.ofEpochMilli(record.t).atZone(zone).toLocalDate()
        File(directory, "$date.jsonl").appendText(record.json() + "\n", Charsets.UTF_8)
        cleanup(date)
    }
    @Synchronized fun cleanup(today: LocalDate) {
        directory.listFiles()?.forEach { file ->
            val date = if (file.extension == "jsonl") runCatching { LocalDate.parse(file.nameWithoutExtension) }.getOrNull() else null
            if (date != null && date < today.minusDays(6)) check(file.delete())
        }
    }
    @Synchronized fun recent(limit: Int = 20): List<String> = directory.listFiles().orEmpty()
        .filter { it.extension == "jsonl" && runCatching { LocalDate.parse(it.nameWithoutExtension) }.isSuccess }
        .sortedByDescending { it.name }.asSequence().flatMap { file ->
            val tail = ArrayDeque<String>()
            file.useLines { lines -> lines.forEach { tail.addLast(it); if (tail.size > limit) tail.removeFirst() } }
            tail.reversed().asSequence()
        }.take(limit).toList().reversed()
}
