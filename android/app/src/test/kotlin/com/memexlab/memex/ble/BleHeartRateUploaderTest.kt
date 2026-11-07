package com.memexlab.memex.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// All readings are synthetic.
class BleHeartRateUploaderTest {
    private val t0 = 1_800_000_000_000L

    @Test
    fun queueKeepsOrderedSaneSamplesAndBatchesOldestFirst() {
        val queue = BleHeartRateUploadQueue(maxBatch = 3)
        queue.offer(t0, 70)
        queue.offer(t0, 71) // duplicate timestamp
        queue.offer(t0 - 1_000, 72) // older than the last one
        queue.offer(t0 + 1_000, 29) // out of range
        queue.offer(t0 + 2_000, 221) // out of range
        for (i in 1..4) queue.offer(t0 + i * 1_000L, 70 + i)
        assertEquals(5, queue.size())
        val batch = queue.batch(t0 + 5_000)
        assertEquals(listOf(t0, t0 + 1_000, t0 + 2_000), batch.map { it.timestampMs })
        queue.acknowledge(batch)
        assertEquals(listOf(73, 74), queue.batch(t0 + 5_000).map { it.bpm })
    }

    @Test
    fun queueDropsSamplesOlderThanTenMinutes() {
        val queue = BleHeartRateUploadQueue()
        queue.offer(t0, 70)
        queue.offer(t0 + 60_000, 71)
        assertEquals(listOf(71), queue.batch(t0 + 10 * 60_000 + 1).map { it.bpm })
        assertEquals(1, queue.size())
    }

    @Test
    fun failuresBackOffFiveSecondsDoublingToOneMinuteAndResetOnSuccess() {
        val queue = BleHeartRateUploadQueue()
        queue.offer(t0, 70)
        val delays = (1..6).map { queue.fail(t0); queue.nextAttemptAtMs() - t0 }
        assertEquals(listOf(5_000L, 10_000L, 20_000L, 40_000L, 60_000L, 60_000L), delays)
        assertTrue(queue.batch(t0 + 59_999).isEmpty())
        val batch = queue.batch(t0 + 60_000)
        assertEquals(1, batch.size)
        queue.acknowledge(batch)
        assertEquals(0L, queue.nextAttemptAtMs())
    }

    @Test
    fun onlyPlainHttpsRootsBecomeUploadUrls() {
        assertEquals(
            "https://pc.example.ts.net:8447/v1/heart-rate/samples",
            BleHeartRateUploadProtocol.samplesUrl(" https://pc.example.ts.net:8447/ "),
        )
        assertEquals("http://127.0.0.1:47866/v1/heart-rate/samples", BleHeartRateUploadProtocol.samplesUrl("http://127.0.0.1:47866"))
        for (bad in listOf(null, "", "http://pc.example.ts.net:8447", "https://user@pc.example.ts.net", "https://pc.example.ts.net/x",
            "https://pc.example.ts.net?a=1", "https://pc.example.ts.net#f", "not a url", "ftp://pc.example.ts.net")) {
            assertNull(bad, BleHeartRateUploadProtocol.samplesUrl(bad))
        }
    }

    @Test
    fun bodyCarriesOnlyTimestampsBpmAndAPlainStatus() {
        val batch = listOf(BleHeartRateUploadQueue.Sample(t0, 70), BleHeartRateUploadQueue.Sample(t0 + 1_000, 71))
        assertEquals(
            "{\"format\":\"hr-samples-v1\",\"status\":\"live\",\"samples\":[{\"t\":$t0,\"bpm\":70},{\"t\":${t0 + 1_000},\"bpm\":71}]}",
            BleHeartRateUploadProtocol.body(batch, "live"),
        )
        assertEquals(
            "{\"format\":\"hr-samples-v1\",\"samples\":[{\"t\":$t0,\"bpm\":70}]}",
            BleHeartRateUploadProtocol.body(batch.take(1), "bad\"status"),
        )
    }

    private class Harness(var target: String? = "https://pc.example.ts.net:8447", val codes: ArrayDeque<Int> = ArrayDeque()) {
        var now = 1_800_000_000_000L
        val posts = mutableListOf<Pair<String, String>>()
        val outcomes = mutableListOf<BleHeartRateUploadOutcome>()
        val queue = BleHeartRateUploadQueue(maxBatch = 2)
        val uploader = BleHeartRateUploader(
            target = { target },
            onOutcome = { outcomes += it },
            nowMs = { now },
            post = { url, body ->
                posts += url to body
                val code = codes.removeFirstOrNull() ?: 200
                if (code == -1) throw java.io.IOException("synthetic network failure")
                code
            },
            queue = queue,
        )
    }

    @Test
    fun pumpSendsBatchesUntilEmptyAndRecordsSuccess() {
        val h = Harness()
        for (i in 0 until 5) h.uploader.offer(h.now - 5_000 + i * 1_000L, 70 + i)
        h.uploader.setStatus("live")
        h.uploader.pump()
        assertEquals(3, h.posts.size)
        assertTrue(h.posts.all { it.first == "https://pc.example.ts.net:8447/v1/heart-rate/samples" })
        assertEquals(listOf(2, 2, 1), h.outcomes.map { it.accepted })
        assertTrue(h.outcomes.all { it.success })
        assertEquals(0, h.queue.size())
    }

    @Test
    fun networkAndAuthFailuresKeepTheBacklogAndStopThePump() {
        val h = Harness(codes = ArrayDeque(listOf(-1, 403)))
        h.uploader.offer(h.now - 1_000, 70)
        h.uploader.pump()
        assertEquals(1, h.posts.size)
        assertEquals("network", h.outcomes.single().errorCode)
        assertEquals(1, h.queue.size())
        h.uploader.pump() // still backing off
        assertEquals(1, h.posts.size)
        h.now += 5_000
        h.uploader.pump()
        assertEquals("forbidden", h.outcomes.last().errorCode)
        assertEquals(1, h.queue.size())
        h.now += 10_000
        h.uploader.pump()
        assertTrue(h.outcomes.last().success)
        assertEquals(0, h.queue.size())
    }

    @Test
    fun rejectedBatchesAreDroppedAndOffOrNoAddressClearsTheBacklog() {
        val h = Harness(codes = ArrayDeque(listOf(400)))
        h.uploader.offer(h.now - 2_000, 70)
        h.uploader.offer(h.now - 1_000, 71)
        h.uploader.pump()
        assertEquals("rejected_400", h.outcomes.single().errorCode)
        assertEquals(0, h.queue.size())
        h.uploader.offer(h.now, 72)
        h.target = null
        h.uploader.pump()
        assertEquals(0, h.queue.size())
        h.target = "http://pc.example.ts.net:8447"
        h.uploader.offer(h.now + 1_000, 73)
        h.uploader.pump()
        assertEquals(1, h.posts.size)
        assertEquals(0, h.queue.size())
    }
}
