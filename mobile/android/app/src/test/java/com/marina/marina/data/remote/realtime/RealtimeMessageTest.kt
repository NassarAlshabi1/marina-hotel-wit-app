package com.marina.marina.data.remote.realtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** التحليل المتسامح لرسائل Realtime الخادمية (عقد Dart نفسه). */
class RealtimeMessageTest {

    @Test
    fun parsesTheWorkerShape() {
        val message = RealtimeMessage.tryParse(
            """{"type":"change","entity":"bookings","entityId":"abc","operation":"update","deviceId":"dev-A","timestamp":1712345678}"""
        )
        assertNotNull(message)
        assertEquals("change", message!!.type)
        assertEquals("bookings", message.entity)
        assertEquals("abc", message.entityId)
        assertEquals("update", message.operation)
        assertEquals("dev-A", message.deviceId)
        assertEquals(1_712_345_678L, message.timestamp)
    }

    @Test
    fun optionalFieldsStayNullAndTimestampDefaultsToZero() {
        val message = RealtimeMessage.tryParse("""{"type":"presence","entity":"rooms"}""")
        assertNotNull(message)
        assertEquals("presence", message!!.type)
        assertEquals("", message.entityId)
        assertNull(message.operation)
        assertNull(message.deviceId)
        assertEquals(0L, message.timestamp)
    }

    @Test
    fun malformedOrUnexpectedFramesAreIgnoredWithoutThrowing() {
        assertNull(RealtimeMessage.tryParse(null))
        assertNull(RealtimeMessage.tryParse(""))
        assertNull(RealtimeMessage.tryParse("not json at all"))
        assertNull(RealtimeMessage.tryParse("[1,2,3]"))
        assertNull(RealtimeMessage.tryParse("""{"entity":"rooms"}""")) // type مفقود
        assertNull(RealtimeMessage.tryParse("""{"type":"change"}""")) // entity مفقود
        assertNull(RealtimeMessage.tryParse("""{"type":42,"entity":"rooms"}""")) // نوع غير نصي
        assertNull(RealtimeMessage.tryParse("""{"type":"change","entity":["rooms"]}"""))
    }

    @Test
    fun extraUnknownFieldsDoNotBreakParsing() {
        val message = RealtimeMessage.tryParse(
            """{"type":"change","entity":"payments","entityId":"p1","extra":{"nested":true},"vectorClock":"{}","timestamp":"later"}"""
        )
        assertNotNull(message)
        assertEquals("payments", message!!.entity)
        // timestamp نصي غير رقمي → الافتراضي بلا استثناء.
        assertEquals(0L, message.timestamp)
    }
}
