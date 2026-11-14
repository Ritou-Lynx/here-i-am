package com.memexlab.bedwatch

import org.junit.Assert.*
import org.junit.Test

class LookRunnerTest {
    private class FakeCamera(private val frames: MutableList<Snapshot?>) : LookCamera {
        val warmups = mutableListOf<Long>()
        var released = 0
        override fun snap(warmupMs: Long): Snapshot? { warmups += warmupMs; return if (frames.isEmpty()) null else frames.removeAt(0) }
        override fun release() { released++ }
    }
    private fun frame(face: Boolean, x: Float? = null, y: Float? = null) =
        Snapshot(byteArrayOf(1, 2), FrameFeatures(face, if (face) 0.9f else null, 1f, 50f), x, y)
    private val id = "0123456789abcdef01234567"
    private val presets = linkedMapOf("床" to Aim(90, 70), "书桌" to Aim(150, 85), "门口" to Aim(30, 90))

    @Test fun pausedNeverTouchesCamera() {
        val cam = FakeCamera(mutableListOf(frame(true)))
        val r = LookRunner(cam) { null }.run(LookRequest(id, "current"), LookConfig(pausedUntil = 100), 50)
        assertEquals("paused", r.failure)
        assertTrue(cam.warmups.isEmpty())
    }

    @Test fun presetTurnsThenShoots() {
        val moves = mutableListOf<Aim>()
        val cam = FakeCamera(mutableListOf(frame(false)))
        val r = LookRunner(cam) { { aim -> moves += aim; true } }
            .run(LookRequest(id, "书桌"), LookConfig(gimbal = "http://192.168.1.9", positions = presets), 0)
        assertNull(r.failure)
        assertEquals("书桌", r.reached)
        assertEquals(listOf(Aim(150, 85)), moves)
        assertEquals(listOf(LookRunner.AFTER_MOVE_MS), cam.warmups)
        assertEquals(1, cam.released)
    }

    @Test fun unknownPresetOrFailedMoveIsGimbalError() {
        val cfg = LookConfig(gimbal = "http://192.168.1.9", positions = presets)
        assertEquals("gimbal_error", LookRunner(FakeCamera(mutableListOf())) { { true } }.run(LookRequest(id, "厨房"), cfg, 0).failure)
        assertEquals("gimbal_error", LookRunner(FakeCamera(mutableListOf())) { { false } }.run(LookRequest(id, "床"), cfg, 0).failure)
    }

    @Test fun withoutGimbalPresetJustShootsCurrent() {
        val r = LookRunner(FakeCamera(mutableListOf(frame(true)))) { null }.run(LookRequest(id, "书桌"), LookConfig(), 0)
        assertEquals("current", r.reached)
        assertNotNull(r.snapshot)
    }

    @Test fun findMeScansAndRecentres() {
        val moves = mutableListOf<Aim>()
        val cam = FakeCamera(mutableListOf(frame(false), frame(true, 0.7f, 0.5f), frame(true, 0.5f, 0.5f)))
        val r = LookRunner(cam) { { aim -> moves += aim; true } }
            .run(LookRequest(id, "find_me"), LookConfig(gimbal = "http://192.168.1.9", positions = presets), 0)
        assertEquals(true, r.found)
        assertEquals("书桌", r.reached)
        assertEquals(listOf(Aim(90, 70), Aim(150, 85), Aim(136, 85)), moves)
        assertEquals(0.5f, r.snapshot!!.faceX)
    }

    @Test fun findMeNotFoundAndCameraError() {
        val cfg = LookConfig(gimbal = "http://192.168.1.9", positions = presets)
        val none = LookRunner(FakeCamera(mutableListOf(frame(false), frame(false), frame(false)))) { { true } }
            .run(LookRequest(id, "find_me"), cfg, 0)
        assertEquals("not_found", none.failure)
        assertEquals("camera_error", LookRunner(FakeCamera(mutableListOf())) { null }.run(LookRequest(id, "current"), LookConfig(), 0).failure)
    }
}
