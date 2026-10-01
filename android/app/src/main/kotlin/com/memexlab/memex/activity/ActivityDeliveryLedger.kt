package com.memexlab.memex.activity

/** Bounded live-epoch delivery responsibility. No publication completeness claim.
 * Entries acknowledged by Dart stay deduplicated for the whole rescan horizon.
 * A batch is immutable until every item has an explicit terminal disposition.
 */
internal data class ActivityDeliveryBatch(val epoch: String, val id: String, val signals: List<ReducedActivitySignal>)

internal class ActivityDeliveryLedger(private val capacity: Int = 2048, private val batchCapacity: Int = 128) {
    private val known = linkedMapOf<ReducedActivitySignal, Boolean>()
    private val expiredSeenUntil = linkedMapOf<ReducedActivitySignal, Long>()
    private var epoch = ""
    private var serial = 0L
    private var flight: ActivityDeliveryBatch? = null
    var expired = 0; private set
    var overflowBatches = 0; private set
    var abandoned = 0; private set
    var rejected = 0; private set
    val pendingCount get() = known.values.count { !it }
    val retainedCount get() = known.size + expiredSeenUntil.size

    fun reset(newEpoch: String) {
        abandoned += pendingCount
        known.clear()
        expiredSeenUntil.clear()
        flight = null
        epoch = newEpoch
    }

    fun append(signals: List<ReducedActivitySignal>, now: Long) {
        expire(now)
        var overflow = false
        for (signal in signals) {
            if (known.containsKey(signal) || expiredSeenUntil.containsKey(signal)) continue
            if (retainedCount >= capacity) { overflow = true; continue }
            if (signal.signalAtMs < now - ACTIVITY_RESCAN_AGE_MS) {
                expired++
                expiredSeenUntil[signal] = now + ACTIVITY_RESCAN_AGE_MS
            } else known[signal] = false
        }
        if (overflow) overflowBatches++
    }

    fun batch(now: Long): ActivityDeliveryBatch? {
        expire(now)
        flight?.let { return it }
        val next = known.filterValues { !it }.keys.sortedWith(compareBy<ReducedActivitySignal> { if (it.type == "usage_category") 0 else 1 }.thenBy { it.signalAtMs }).take(batchCapacity)
        if (next.isEmpty()) return null
        return ActivityDeliveryBatch(epoch, "${++serial}", next).also { flight = it }
    }

    fun acknowledge(batchEpoch: String, batchId: String, dispositions: List<String>): Boolean {
        val current = flight ?: return false
        if (epoch != batchEpoch || current.id != batchId || dispositions.size != current.signals.size ||
            dispositions.any { it !in allowedDispositions }) return false
        // Validation is atomic; an invalid ACK cannot retire even its valid prefix.
        for ((signal, disposition) in current.signals.zip(dispositions)) {
            if (disposition != "retry") {
                known[signal] = true
                if (disposition !in setOf("accepted", "duplicate")) rejected++
            }
        }
        if (dispositions.all { it != "retry" }) flight = null
        return true
    }

    private fun expire(now: Long) {
        expiredSeenUntil.entries.removeAll { it.value < now }
        // In-flight retries keep the same ID and shape until their oldest item expires.
        // Its acknowledged items remain in known; unaccepted expired items become gaps.
        if (flight?.signals?.any { it.signalAtMs < now - ACTIVITY_RESCAN_AGE_MS } == true) flight = null
        val iterator = known.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.key.signalAtMs < now - ACTIVITY_RESCAN_AGE_MS) {
                if (!entry.value) expired++
                iterator.remove()
            }
        }
    }

    private companion object {
        val allowedDispositions = setOf("accepted", "duplicate", "retry", "expired_before_acceptance", "late_out_of_order", "before_subscription")
    }
}
