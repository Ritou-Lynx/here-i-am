package com.memexlab.bedwatch

data class FrameFeatures(val face: Boolean, val eyesOpen: Float?, val glow: Float, val frameLuma: Float)
data class FaceBox(val left: Int, val top: Int, val right: Int, val bottom: Int)

data class Thresholds(
    val open: Float = 0.6f,
    val glow: Float = 1.6f,
    val closed: Float = 0.3f,
    val dimGlow: Float = 1.3f,
    val dark: Float = 40f,
) {
    init {
        require(open.isFinite() && closed.isFinite() && closed in 0f..open && open <= 1f)
        require(glow.isFinite() && dimGlow.isFinite() && dimGlow >= 0f && glow >= dimGlow)
        require(dark.isFinite() && dark in 0f..255f)
    }
}

enum class Verdict { AWAKE, ASLEEP_LIKE, UNKNOWN }

object LumaStats {
    /** Packed, upright Y plane; crops the box and never retains the input array. */
    fun features(y: ByteArray, width: Int, height: Int, box: FaceBox?, eyes: Float?): FrameFeatures {
        require(width > 0 && height > 0 && y.size.toLong() == width.toLong() * height)
        val histogram = IntArray(256)
        var sum = 0L
        y.forEach { val value = it.toInt() and 255; histogram[value]++; sum += value }
        fun order(index: Int): Int {
            var count = 0
            for (value in histogram.indices) { count += histogram[value]; if (count > index) return value }
            return 255
        }
        val median = (order((y.size - 1) / 2) + order(y.size / 2)) / 2f
        val left = box?.left?.coerceIn(0, width) ?: 0
        val right = box?.right?.coerceIn(0, width) ?: 0
        val top = box?.top?.coerceIn(0, height) ?: 0
        val bottom = box?.bottom?.coerceIn(0, height) ?: 0
        var faceSum = 0L
        var count = 0
        for (row in top until bottom) for (col in left until right) {
            faceSum += y[row * width + col].toInt() and 255; count++
        }
        // Floor the denominator to one luma level to avoid infinity in total darkness.
        val glow = if (count == 0) 0f else (faceSum.toFloat() / count) / median.coerceAtLeast(1f)
        return FrameFeatures(box != null, eyes, glow, sum.toFloat() / y.size)
    }

    /** Rotate packed raw sensor luma into ML Kit's upright coordinate system. */
    fun rotate(y: ByteArray, width: Int, height: Int, degrees: Int): ByteArray {
        require(y.size == width * height && degrees in listOf(0, 90, 180, 270))
        val output = ByteArray(y.size)
        for (row in 0 until height) for (col in 0 until width) {
            val index = when (degrees) {
                90 -> col * height + height - 1 - row
                180 -> (height - 1 - row) * width + width - 1 - col
                270 -> (width - 1 - col) * height + row
                else -> row * width + col
            }
            output[index] = y[row * width + col]
        }
        return output
    }
}
