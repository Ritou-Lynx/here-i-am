package com.memexlab.bedwatch

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.util.Base64

data class PushRequest(val url: String, val headers: Map<String, String>, val body: ByteArray, val timeoutMs: Int = 10_000)
fun interface PushTransport { fun send(request: PushRequest): Boolean }

class UrlConnectionTransport(
    private val open: (URI) -> HttpURLConnection = { it.toURL().openConnection() as HttpURLConnection },
) : PushTransport {
    override fun send(request: PushRequest): Boolean {
        require(URI(request.url).scheme == "https")
        val connection = open(URI(request.url))
        return try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = request.timeoutMs
            connection.readTimeout = request.timeoutMs
            connection.doOutput = true
            request.headers.forEach { (key, value) -> connection.setRequestProperty(key, value) }
            connection.setRequestProperty("Content-Type", "text/plain; charset=utf-8")
            connection.setFixedLengthStreamingMode(request.body.size)
            connection.outputStream.use { it.write(request.body) }
            connection.responseCode in 200..299
        } finally { connection.disconnect() }
    }
}

class NtfyNotifier(
    private val transport: PushTransport = UrlConnectionTransport(),
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
    private val shouldContinue: () -> Boolean = { true },
) {
    companion object {
        const val TITLE = "林埃来电"
        fun endpoint(server: String, topic: String): String {
            val uri = URI(server.trim())
            require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null &&
                uri.rawQuery == null && uri.rawFragment == null) { "服务器必须是无凭据、查询或片段的 https 地址" }
            require(topic.isNotBlank() && topic == topic.trim() && topic.none { it.isISOControl() } &&
                topic != "." && topic != "..") { "请填写有效 topic" }
            return server.trim().trimEnd('/') + "/" + URLEncoder.encode(topic, "UTF-8").replace("+", "%20")
        }
    }

    fun send(server: String, topic: String, reason: String): Boolean {
        val request = PushRequest(endpoint(server, topic), mapOf(
            // HttpURLConnection cannot reliably emit non-ASCII header bytes. ntfy decodes RFC 2047.
            "Title" to "=?UTF-8?B?${Base64.getEncoder().encodeToString(TITLE.toByteArray(Charsets.UTF_8))}?=",
            "Priority" to "urgent", "Tags" to "telephone_receiver",
        ), reason.toByteArray(Charsets.UTF_8))
        for (attempt in 0..2) {
            if (!shouldContinue()) return false
            try { if (transport.send(request)) return true } catch (_: IOException) { /* retry, no endpoint logging */ }
            if (attempt < 2) sleep(if (attempt == 0) 5_000 else 30_000)
        }
        return false
    }
}
