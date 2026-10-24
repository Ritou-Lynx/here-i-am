package com.memexlab.bedwatch

import java.time.LocalTime
import java.time.ZonedDateTime

data class Judgement(val verdict: Verdict, val push: Boolean)

class AwakeJudge(private val thresholds: Thresholds = Thresholds(), private val cooldownMs: Long = 600_000) {
    private val recent = ArrayDeque<Verdict>()
    private var lastPush: Long? = null
    private var lastTime: Long? = null
    init { require(cooldownMs >= 0) }

    fun classify(f: FrameFeatures): Verdict = when {
        f.face && ((f.eyesOpen ?: -1f) >= thresholds.open || f.glow >= thresholds.glow) -> Verdict.AWAKE
        !f.face && f.frameLuma < thresholds.dark -> Verdict.ASLEEP_LIKE
        f.face && f.eyesOpen != null && f.eyesOpen < thresholds.closed && f.glow < thresholds.dimGlow -> Verdict.ASLEEP_LIKE
        else -> Verdict.UNKNOWN
    }

    fun accept(f: FrameFeatures, nowMs: Long, releaseUntilMs: Long = 0): Judgement {
        require(lastTime == null || nowMs >= lastTime!!)
        lastTime = nowMs
        val verdict = classify(f)
        recent.addLast(verdict)
        if (recent.size > 4) recent.removeFirst()
        val push = verdict == Verdict.AWAKE && recent.size == 4 &&
            recent.count { it == Verdict.AWAKE } >= 3 && nowMs >= releaseUntilMs &&
            (lastPush == null || nowMs - lastPush!! >= cooldownMs)
        if (push) lastPush = nowMs
        return Judgement(verdict, push)
    }

    fun restoreLastPush(epochMs: Long?) { lastPush = epochMs }
}

object NightWindow {
    fun contains(time: LocalTime, start: LocalTime, end: LocalTime): Boolean = when {
        start == end -> true
        start < end -> time >= start && time < end
        else -> time >= start || time < end
    }
    fun releaseUntil(now: ZonedDateTime): Long = now.toLocalDate().plusDays(1)
        .atTime(12, 0).atZone(now.zone).toInstant().toEpochMilli()
}

enum class RecoveryCause { BOOT, FOREGROUND_REJECTED }
object RecoveryPolicy {
    fun shouldNotify(monitoringEnabled: Boolean, cause: RecoveryCause): Boolean =
        monitoringEnabled && cause in setOf(RecoveryCause.BOOT, RecoveryCause.FOREGROUND_REJECTED)
}
