package com.memexlab.bedwatch

import org.junit.Assert.*
import org.junit.Test

class LumaStatsTest {
    @Test fun darkFrameHasNoFaceAndZeroGlow() {
        assertEquals(FrameFeatures(false, null, 0f, 0f), LumaStats.features(ByteArray(16), 4, 4, null, null))
    }
    @Test fun brightBoxUsesFaceMeanOverFrameMedian() {
        val y = ByteArray(16) { 20 }
        y[5] = 100; y[6] = 100; y[9] = 100; y[10] = 100
        val f = LumaStats.features(y, 4, 4, FaceBox(1, 1, 3, 3), .8f)
        assertEquals(5f, f.glow, .001f); assertEquals(40f, f.frameLuma, .001f)
        assertTrue(f.face); assertEquals(.8f, f.eyesOpen!!, .001f)
    }
    @Test fun outOfBoundsBoxIsClipped() {
        val f = LumaStats.features(byteArrayOf(20, 40, 60, 80), 2, 2, FaceBox(-5, -5, 1, 1), null)
        assertEquals(.4f, f.glow, .001f)
    }
    @Test fun whollyOutsideBoxHasZeroGlow() {
        assertEquals(0f, LumaStats.features(ByteArray(4), 2, 2, FaceBox(4, 4, 6, 6), null).glow, 0f)
    }
    @Test fun unsignedLumaAndEvenMedian() {
        val f = LumaStats.features(byteArrayOf(0, 255.toByte()), 2, 1, FaceBox(0, 0, 2, 1), null)
        assertEquals(127.5f, f.frameLuma, 0f); assertEquals(1f, f.glow, 0f)
    }
    @Test fun zeroMedianRemainsFinite() {
        val f = LumaStats.features(byteArrayOf(0, 0, 0, 100), 2, 2, FaceBox(1, 1, 2, 2), null)
        assertTrue(f.glow.isFinite()); assertEquals(100f, f.glow, 0f)
    }
    @Test fun rotationAlignsFaceCoordinates() {
        val y = byteArrayOf(1, 2, 3, 4, 5, 6)
        assertArrayEquals(byteArrayOf(5, 3, 1, 6, 4, 2), LumaStats.rotate(y, 2, 3, 90))
        assertArrayEquals(byteArrayOf(6, 5, 4, 3, 2, 1), LumaStats.rotate(y, 2, 3, 180))
        assertArrayEquals(byteArrayOf(2, 4, 6, 1, 3, 5), LumaStats.rotate(y, 2, 3, 270))
        assertArrayEquals(y, LumaStats.rotate(y, 2, 3, 0))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsShortPlane() {
        LumaStats.features(ByteArray(3), 2, 2, null, null)
    }
}
