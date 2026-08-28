package com.memexlab.memex.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartRateMeasurementParserTest {
    @Test
    fun parsesEightBitBpmWithoutOptionalFields() {
        val parsed = valid(0x00, 72)
        assertEquals(72, parsed.bpm)
        assertFalse(parsed.contactSupported)
        assertNull(parsed.contactDetected)
        assertNull(parsed.energyExpended)
        assertTrue(parsed.rrIntervalsSeconds.isEmpty())
    }

    @Test
    fun parsesSixteenBitBpm() {
        val parsed = valid(0x01, 0x2c, 0x01)
        assertEquals(300, parsed.bpm)
    }

    @Test
    fun parsesContactSupportedDetectedAndNotDetected() {
        val detected = valid(0x06, 80)
        assertTrue(detected.contactSupported)
        assertEquals(true, detected.contactDetected)

        val notDetected = valid(0x04, 80)
        assertTrue(notDetected.contactSupported)
        assertEquals(false, notDetected.contactDetected)

        val reservedDetectedBit = valid(0x02, 80)
        assertFalse(reservedDetectedBit.contactSupported)
        assertNull(reservedDetectedBit.contactDetected)
    }

    @Test
    fun parsesEnergyAndMultipleRrIntervalsAtCorrectOffsets() {
        val parsed = valid(
            0x1f,
            0x34, 0x01, // 308 bpm
            0x2a, 0x00, // 42 kJ
            0x00, 0x04, // 1 second
            0x00, 0x02, // 0.5 seconds
        )
        assertEquals(308, parsed.bpm)
        assertEquals(42, parsed.energyExpended)
        assertEquals(listOf(1.0, 0.5), parsed.rrIntervalsSeconds)
    }

    @Test
    fun rejectsMalformedAndZeroMeasurements() {
        val payloads = listOf(
            byteArrayOf(),
            bytes(0x00),
            bytes(0x01, 0x20),
            bytes(0x08, 70, 0x01),
            bytes(0x10, 70),
            bytes(0x10, 70, 0x01),
            bytes(0x00, 0),
            bytes(0x00, 70, 0x01),
        )
        for (payload in payloads) {
            assertTrue(
                "Expected malformed for ${payload.contentToString()}",
                HeartRateMeasurementParser.parse(payload) is HeartRateParseResult.Malformed,
            )
        }
    }

    private fun valid(vararg values: Int): HeartRateMeasurement {
        val result = HeartRateMeasurementParser.parse(bytes(*values))
        return (result as HeartRateParseResult.Valid).measurement
    }

    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }
}
