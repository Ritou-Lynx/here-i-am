package com.memexlab.memex.ble

data class HeartRateMeasurement(
    val bpm: Int,
    val contactSupported: Boolean,
    val contactDetected: Boolean?,
    val energyExpended: Int?,
    val rrIntervalsSeconds: List<Double>,
)

sealed interface HeartRateParseResult {
    data class Valid(val measurement: HeartRateMeasurement) : HeartRateParseResult
    data class Malformed(val reason: String) : HeartRateParseResult
}

/** Pure Bluetooth SIG Heart Rate Measurement (0x2A37) parser. */
object HeartRateMeasurementParser {
    fun parse(value: ByteArray): HeartRateParseResult {
        if (value.isEmpty()) return HeartRateParseResult.Malformed("missing_flags")

        val flags = value[0].toInt() and 0xff
        var offset = 1
        val bpm = if ((flags and 0x01) != 0) {
            if (value.size < offset + 2) return HeartRateParseResult.Malformed("missing_uint16_bpm")
            readUInt16(value, offset).also { offset += 2 }
        } else {
            if (value.size < offset + 1) return HeartRateParseResult.Malformed("missing_uint8_bpm")
            (value[offset].toInt() and 0xff).also { offset += 1 }
        }
        if (bpm == 0) return HeartRateParseResult.Malformed("zero_bpm")

        val contactSupported = (flags and 0x04) != 0
        val contactDetected = if (contactSupported) (flags and 0x02) != 0 else null

        val energyExpended = if ((flags and 0x08) != 0) {
            if (value.size < offset + 2) return HeartRateParseResult.Malformed("missing_energy")
            readUInt16(value, offset).also { offset += 2 }
        } else {
            null
        }

        val rrIntervals = mutableListOf<Double>()
        if ((flags and 0x10) != 0) {
            val remaining = value.size - offset
            if (remaining < 2 || remaining % 2 != 0) {
                return HeartRateParseResult.Malformed("invalid_rr_length")
            }
            while (offset < value.size) {
                rrIntervals += readUInt16(value, offset) / 1024.0
                offset += 2
            }
        } else if (offset != value.size) {
            return HeartRateParseResult.Malformed("unexpected_trailing_bytes")
        }

        return HeartRateParseResult.Valid(
            HeartRateMeasurement(
                bpm = bpm,
                contactSupported = contactSupported,
                contactDetected = contactDetected,
                energyExpended = energyExpended,
                rrIntervalsSeconds = rrIntervals,
            ),
        )
    }

    private fun readUInt16(value: ByteArray, offset: Int): Int =
        (value[offset].toInt() and 0xff) or
            ((value[offset + 1].toInt() and 0xff) shl 8)
}
