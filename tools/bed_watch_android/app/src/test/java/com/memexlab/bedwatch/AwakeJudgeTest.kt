package com.memexlab.bedwatch

import org.junit.Assert.*
import org.junit.Test
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

class AwakeJudgeTest {
    private val awake = FrameFeatures(true, .6f, 1f, 50f)
    private val unknown = FrameFeatures(true, null, 1f, 50f)
    private val asleep = FrameFeatures(true, .2f, 1f, 20f)
    @Test fun eyeAndGlowBoundariesAreInclusive() {
        val j = AwakeJudge()
        assertEquals(Verdict.AWAKE, j.classify(awake))
        assertEquals(Verdict.AWAKE, j.classify(unknown.copy(glow = 1.6f)))
        assertEquals(Verdict.UNKNOWN, j.classify(awake.copy(eyesOpen = .599f)))
    }
    @Test fun asleepBranchesAndStrictBoundaries() {
        val j = AwakeJudge()
        assertEquals(Verdict.ASLEEP_LIKE, j.classify(asleep))
        assertEquals(Verdict.ASLEEP_LIKE, j.classify(FrameFeatures(false, null, 0f, 39.9f)))
        assertEquals(Verdict.UNKNOWN, j.classify(FrameFeatures(false, null, 0f, 40f)))
        assertEquals(Verdict.UNKNOWN, j.classify(asleep.copy(eyesOpen = .3f)))
        assertEquals(Verdict.UNKNOWN, j.classify(asleep.copy(glow = 1.3f)))
    }
    @Test fun missingEyesDoesNotMeanClosed() {
        assertEquals(Verdict.UNKNOWN, AwakeJudge().classify(unknown))
    }
    @Test fun noFaceCannotBeAwakeEvenInBrightFrame() {
        assertEquals(Verdict.UNKNOWN, AwakeJudge().classify(FrameFeatures(false, 1f, 10f, 200f)))
    }
    @Test fun needsFourSamplesAndThreeAwake() {
        val j = AwakeJudge()
        repeat(3) { assertFalse(j.accept(awake, it.toLong()).push) }
        assertTrue(j.accept(awake, 3).push)
    }
    @Test fun unknownKeepsVotesButDoesNotPush() {
        val j = AwakeJudge()
        j.accept(awake, 0); j.accept(awake, 1)
        assertFalse(j.accept(unknown, 2).push)
        assertTrue(j.accept(awake, 3).push)
        val k = AwakeJudge()
        repeat(3) { k.accept(awake, it.toLong()) }
        assertFalse(k.accept(unknown, 3).push)
        assertTrue(k.accept(awake, 4).push)
    }
    @Test fun slidingWindowExpiresOldAwakeVotes() {
        val j = AwakeJudge()
        j.accept(awake, 0); j.accept(awake, 1); j.accept(asleep, 2); j.accept(asleep, 3)
        assertFalse(j.accept(awake, 4).push)
    }
    @Test fun cooldownBoundaryAndPersistentCooldown() {
        val j = AwakeJudge()
        repeat(3) { j.accept(awake, it.toLong()) }
        assertTrue(j.accept(awake, 3).push)
        assertFalse(j.accept(awake, 600_002).push)
        assertTrue(j.accept(awake, 600_003).push)
        val restored = AwakeJudge().also { it.restoreLastPush(600_003) }
        repeat(4) { assertFalse(restored.accept(awake, 600_004L + it).push) }
    }
    @Test fun releaseRecordsVotesAndExpiresAtExactDeadline() {
        val j = AwakeJudge()
        repeat(4) { assertFalse(j.accept(awake, it.toLong(), 10).push) }
        assertTrue(j.accept(awake, 10, 10).push)
    }
    @Test fun releaseEndsAtNextDayNoonAcrossMidnightAndDst() {
        val now = ZonedDateTime.of(2026, 10, 24, 23, 45, 0, 0, ZoneId.of("Europe/Berlin"))
        val until = java.time.Instant.ofEpochMilli(NightWindow.releaseUntil(now)).atZone(now.zone)
        assertEquals(now.toLocalDate().plusDays(1), until.toLocalDate())
        assertEquals(LocalTime.NOON, until.toLocalTime())
    }
    @Test fun overnightAndDaytimeWindowBoundaries() {
        val start = LocalTime.of(23, 30); val end = LocalTime.of(6, 0)
        assertTrue(NightWindow.contains(start, start, end))
        assertTrue(NightWindow.contains(LocalTime.MIDNIGHT, start, end))
        assertFalse(NightWindow.contains(end, start, end))
        assertFalse(NightWindow.contains(LocalTime.NOON, start, end))
        assertTrue(NightWindow.contains(LocalTime.NOON, LocalTime.of(9, 0), LocalTime.of(17, 0)))
        assertTrue(NightWindow.contains(LocalTime.NOON, start, start))
    }
    @Test fun recoveryNotificationOnlyForEnabledMonitoring() {
        RecoveryCause.entries.forEach {
            assertTrue(RecoveryPolicy.shouldNotify(true, it))
            assertFalse(RecoveryPolicy.shouldNotify(false, it))
        }
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsOutOfOrderFrames() {
        val j = AwakeJudge(); j.accept(awake, 5); j.accept(awake, 4)
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsInvalidThresholds() { Thresholds(open = Float.NaN) }
}
