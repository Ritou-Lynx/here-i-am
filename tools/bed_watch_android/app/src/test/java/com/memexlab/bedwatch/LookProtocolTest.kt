package com.memexlab.bedwatch

import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class LookProtocolTest {
    @Test fun lanBaseAcceptsOnlyPrivateHttp() {
        assertEquals("http://192.168.1.20:47867", LookProtocol.lanBase(" http://192.168.1.20:47867/ "))
        assertEquals("http://10.0.0.5", LookProtocol.lanBase("http://10.0.0.5"))
        for (bad in listOf("https://192.168.1.20", "http://8.8.8.8", "http://example.test", "http://172.32.0.1",
            "http://u:p@192.168.1.2", "http://192.168.1.2/x", "http://192.168.1.2?q=1", "ftp://192.168.1.2")) {
            assertThrows(bad, Exception::class.java) { LookProtocol.lanBase(bad) }
        }
    }

    @Test fun positionsRoundTrip() {
        val map = LookProtocol.parsePositions("床=90,70; 书桌=150,85 ;门口=30,90")
        assertEquals(listOf("床", "书桌", "门口"), map.keys.toList())
        assertEquals(Aim(150, 85), map["书桌"])
        assertEquals(map, LookProtocol.parsePositions(LookProtocol.formatPositions(map)))
        assertTrue(LookProtocol.parsePositions("  ").isEmpty())
        for (bad in listOf("床", "床=90", "床=200,10", "current=1,1", "床=1,1;床=2,2", "a b=1,1")) {
            assertThrows(bad, Exception::class.java) { LookProtocol.parsePositions(bad) }
        }
    }

    @Test fun parsesServerRequest() {
        val id = "0123456789abcdef01234567"
        assertEquals(LookRequest(id, "书桌"), LookProtocol.parseRequest("{\"id\":\"$id\",\"position\":\"书桌\"}"))
        assertEquals("书桌", LookProtocol.parseRequest("{\"id\":\"$id\",\"position\":\"\\u4e66\\u684c\"}").position)
        assertEquals("find_me", LookProtocol.parseRequest("{\"position\":\"find_me\",\"id\":\"$id\"}").position)
        assertThrows(Exception::class.java) { LookProtocol.parseRequest("{\"id\":\"xyz\",\"position\":\"床\"}") }
        assertThrows(Exception::class.java) { LookProtocol.parseRequest("{\"id\":\"$id\",\"position\":\"a b\"}") }
    }

    @Test fun metaIsSmallAsciiJson() {
        val encoded = LookProtocol.meta(true, 0.876f, 41.2f, null, "书\"桌")
        assertTrue(encoded.all { it.code < 128 })
        val json = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        assertEquals("{\"face\":true,\"eyes_open\":0.88,\"luma\":41.20,\"reached\":\"书\\\"桌\"}", json)
        assertEquals("{}", String(Base64.getDecoder().decode(LookProtocol.meta(null, Float.NaN, null, null, null))))
    }

    @Test fun recenterMovesTowardFace() {
        val aim = Aim(90, 90)
        assertEquals(aim, LookProtocol.recenter(aim, 0.5f, 0.5f, 70f, false, false))
        assertEquals(Aim(76, 90), LookProtocol.recenter(aim, 0.7f, 0.5f, 70f, false, false))
        assertEquals(Aim(104, 90), LookProtocol.recenter(aim, 0.7f, 0.5f, 70f, true, false))
        assertEquals(Aim(90, 111), LookProtocol.recenter(aim, 0.5f, 0.9f, 70f, false, false))
        assertEquals(Aim(0, 90), LookProtocol.recenter(Aim(5, 90), 1f, 0.5f, 70f, false, false))
    }
}
