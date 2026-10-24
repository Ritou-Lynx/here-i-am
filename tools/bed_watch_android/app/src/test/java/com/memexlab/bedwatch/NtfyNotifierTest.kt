package com.memexlab.bedwatch

import org.junit.Assert.*
import org.junit.Test
import java.io.Closeable
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.SocketTimeoutException
import java.net.URL
import java.util.Base64
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NtfyNotifierTest {
    private data class Received(val path: String, val headers: Map<String, String>, val body: String)
    private class FakeServer(private val codes: List<Int>, private val stall: Boolean = false) : Closeable {
        val socket = ServerSocket(0, 8, java.net.InetAddress.getByName("127.0.0.1"))
        val received: MutableList<Received> = Collections.synchronizedList(mutableListOf())
        private val executor = Executors.newSingleThreadExecutor()
        init {
            socket.soTimeout = 3000
            executor.submit {
                codes.forEach { code ->
                    socket.accept().use { client ->
                        client.soTimeout = 3000
                        val input = client.getInputStream()
                        fun line(): String {
                            val bytes = java.io.ByteArrayOutputStream()
                            while (true) { val b = input.read(); check(b >= 0); if (b == 10) break; if (b != 13) bytes.write(b) }
                            return bytes.toString("US-ASCII")
                        }
                        val path = line().split(' ')[1]
                        val headers = mutableMapOf<String, String>()
                        while (true) {
                            val header = line(); if (header.isEmpty()) break
                            headers[header.substringBefore(':').lowercase()] = header.substringAfter(':').trim()
                        }
                        val body = ByteArray(headers.getValue("content-length").toInt())
                        var count = 0
                        while (count < body.size) { val n = input.read(body, count, body.size - count); check(n > 0); count += n }
                        received.add(Received(path, headers, body.toString(Charsets.UTF_8)))
                        if (stall) Thread.sleep(150)
                        else client.getOutputStream().write("HTTP/1.1 $code Test\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
                    }
                }
            }
        }
        fun transport(onOpen: (HttpURLConnection) -> Unit = {}): PushTransport = UrlConnectionTransport { uri ->
            (URL("http://127.0.0.1:${socket.localPort}${uri.rawPath}").openConnection() as HttpURLConnection).also(onOpen)
        }
        override fun close() { socket.close(); executor.shutdownNow(); executor.awaitTermination(2, TimeUnit.SECONDS) }
    }
    @Test fun localServerReceivesPathHeadersAndChineseBody() {
        FakeServer(listOf(200)).use { server ->
            var connection: HttpURLConnection? = null
            assertTrue(NtfyNotifier(server.transport { connection = it }, { fail("no retry") })
                .send("https://example.invalid/base/", "sample topic", "合成测试：仍然清醒"))
            val req = server.received.single()
            assertEquals("/base/sample%20topic", req.path)
            assertEquals("urgent", req.headers["priority"])
            assertEquals("telephone_receiver", req.headers["tags"])
            val title = req.headers.getValue("title").removePrefix("=?UTF-8?B?").removeSuffix("?=")
            assertEquals("林埃来电", Base64.getDecoder().decode(title).toString(Charsets.UTF_8))
            assertEquals("合成测试：仍然清醒", req.body)
            assertEquals(10_000, connection!!.connectTimeout)
            assertEquals(10_000, connection!!.readTimeout)
            assertFalse(connection!!.instanceFollowRedirects)
        }
    }
    @Test fun failedHttpResponsesRetryAtFiveAndThirtySeconds() {
        FakeServer(listOf(503, 500, 200)).use { server ->
            val waits = mutableListOf<Long>()
            assertTrue(NtfyNotifier(server.transport(), { waits.add(it) }).send("https://example.invalid", "sample", "test"))
            assertEquals(listOf(5000L, 30000L), waits)
            assertEquals(3, server.received.size)
        }
    }
    @Test fun timeoutRetriesExactlyTwiceThenFails() {
        var attempts = 0
        val waits = mutableListOf<Long>()
        assertFalse(NtfyNotifier(PushTransport {
            attempts++; assertEquals(10_000, it.timeoutMs); throw SocketTimeoutException("synthetic timeout")
        }, { waits.add(it) }).send("https://example.invalid", "sample", "test"))
        assertEquals(3, attempts); assertEquals(listOf(5000L, 30000L), waits)
    }
    @Test fun actualReadTimeoutAgainstSilentLocalServer() {
        FakeServer(listOf(200), stall = true).use { server ->
            val transport = server.transport()
            try {
                transport.send(PushRequest("https://example.invalid/sample", emptyMap(), "test".toByteArray(), 50))
                fail("expected read timeout")
            } catch (_: SocketTimeoutException) { /* Real socket deadline exercised without a ten-second test. */ }
        }
    }
    @Test fun rejectsNonHttpsAndCredentialUrlsBeforeTransport() {
        var calls = 0
        val notifier = NtfyNotifier(PushTransport { calls++; true })
        listOf("http://example.invalid", "ftp://example.invalid", "https://user:password@example.invalid",
            "https://example.invalid?token=sample", "https://example.invalid/#fragment").forEach {
            try { notifier.send(it, "sample", "test"); fail("expected rejection") }
            catch (_: IllegalArgumentException) { }
        }
        assertEquals(0, calls)
    }
    @Test fun redirectsAreFailuresRatherThanFollowingOtherHosts() {
        FakeServer(listOf(302, 302, 302)).use { server ->
            assertFalse(NtfyNotifier(server.transport(), {}).send("https://example.invalid", "sample", "test"))
            assertEquals(3, server.received.size)
        }
    }
    @Test fun topicIsOneEncodedPathSegment() {
        assertEquals("https://example.invalid/a%2Fb", NtfyNotifier.endpoint("https://example.invalid", "a/b"))
    }
    @Test fun disablingMonitoringCancelsPendingRetries() {
        var enabled = true
        var attempts = 0
        assertFalse(NtfyNotifier(PushTransport { attempts++; false }, { enabled = false }, { enabled })
            .send("https://example.invalid", "sample", "test"))
        assertEquals(1, attempts)
    }
}
