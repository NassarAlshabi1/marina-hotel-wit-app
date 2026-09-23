package com.marina.marina.data.remote

import com.google.gson.Gson
import com.marina.marina.data.local.entity.OutboxEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * ✅ (2026-09-24) اختبارات عقد السلك للدفع — تحرس مطابقة
 * buildPushOperation/PayloadNormalizer المنقولة من Flutter
 * (sync/payload_normalizer.dart) في PushWireContract.
 */
class PushWireContractTest {

    private val gson = Gson()

    private fun outboxRow(
        entity: String = "rooms",
        op: String = "insert",
        localUuid: String = "uuid-1",
        payload: Map<String, Any> = emptyMap(),
        clientTs: Long = 1_700_000_000_000L,
        idempotencyKey: String? = "rooms_insert_uuid-1"
    ) = OutboxEntity(
        entity = entity,
        op = op,
        localUuid = localUuid,
        payload = gson.toJson(payload),
        clientTs = clientTs,
        idempotencyKey = idempotencyKey
    )

    // ─── mapOperation: عقد operation الخادمي (create|update|delete) ──

    @Test
    fun `insert maps to create`() {
        assertEquals("create", PushWireContract.mapOperation("insert"))
        assertEquals("create", PushWireContract.mapOperation("INSERT"))
        assertEquals("create", PushWireContract.mapOperation(" create "))
    }

    @Test
    fun `update and edit map to update`() {
        assertEquals("update", PushWireContract.mapOperation("update"))
        assertEquals("update", PushWireContract.mapOperation("edit"))
    }

    @Test
    fun `delete variants map to delete`() {
        assertEquals("delete", PushWireContract.mapOperation("delete"))
        assertEquals("delete", PushWireContract.mapOperation("soft_delete"))
        assertEquals("delete", PushWireContract.mapOperation("softdelete"))
    }

    @Test
    fun `unknown op passes through for explicit server rejection`() {
        assertEquals("merge", PushWireContract.mapOperation("merge"))
    }

    // ─── toSnakeCase: idempotent boundary conversion ─────────────

    @Test
    fun `camelCase converts with word boundaries only`() {
        assertEquals("guest_name", PushWireContract.toSnakeCase("guestName"))
        assertEquals("employee_id", PushWireContract.toSnakeCase("employeeId"))
        assertEquals("hotel_day_key", PushWireContract.toSnakeCase("hotelDayKey"))
    }

    @Test
    fun `acronyms collapse without letter-by-letter underscores`() {
        // localUUID → local_uuid (لا local_u_u_i_d) — نفس سلوك Flutter.
        assertEquals("local_uuid", PushWireContract.toSnakeCase("localUUID"))
        assertEquals("guest_id2", PushWireContract.toSnakeCase("guestID2"))
    }

    @Test
    fun `already snake_case keys pass through untouched`() {
        assertEquals("local_uuid", PushWireContract.toSnakeCase("local_uuid"))
        assertEquals("idempotency_key", PushWireContract.toSnakeCase("idempotency_key"))
    }

    // ─── normalizeForWire: top-level keys + bool→int ─────────────

    @Test
    fun `booleans become integers for D1 INTEGER affinity`() {
        val normalized = PushWireContract.normalizeForWire(
            mapOf("is_active" to true, "is_deleted" to false)
        )
        assertEquals(1, normalized["is_active"])
        assertEquals(0, normalized["is_deleted"])
    }

    @Test
    fun `camelCase keys normalized to snake_case`() {
        val normalized = PushWireContract.normalizeForWire(
            mapOf("guestName" to "أحمد", "isActive" to true)
        )
        assertTrue(normalized.containsKey("guest_name"))
        assertTrue(normalized.containsKey("is_active"))
        assertEquals("أحمد", normalized["guest_name"])
    }

    @Test
    fun `nested values preserved verbatim as data`() {
        // القيم المتداخلة بيانات (مثل applied_adjustments_json) — مفاتيحها
        // الداخلية تُحفظ (نفس تعليق Flutter: only column names are normalized).
        val nested = mapOf("innerCamelKey" to "value")
        val normalized = PushWireContract.normalizeForWire(
            mapOf("outer_name" to nested, "is_active" to true)
        )
        @Suppress("UNCHECKED_CAST")
        val inner = normalized["outer_name"] as Map<String, Any>
        assertTrue(inner.containsKey("innerCamelKey"))
        assertFalse(inner.containsKey("inner_camel_key"))
    }

    // ─── buildOperation: عقد PushOperation الكامل ────────────────

    @Test
    fun `operation carries wire contract fields`() {
        val op = PushWireContract.buildOperation(
            outboxRow(
                entity = "bookings",
                op = "insert",
                payload = mapOf("guest_name" to "أحمد", "is_active" to true),
                idempotencyKey = "bookings_insert_uuid-1"
            ),
            deviceId = "cf_dev_1"
        )
        assertEquals("bookings_insert_uuid-1", op.idempotencyKey)
        assertEquals("bookings", op.entity)
        assertEquals("create", op.operation)
        assertEquals("أحمد", op.data["guest_name"])
        assertEquals(1, op.data["is_active"])
        assertEquals(1_700_000_000_000L, op.updatedAt)
        assertEquals("cf_dev_1", op.deviceId)
    }

    @Test
    fun `local_uuid injected when payload lacks it`() {
        // الحمولات الرقيقة (soft-deletes {'id': n}) — requireEntityId يرفض
        // id الرقمي؛ local_uuid من صف outbox يُحقن.
        val op = PushWireContract.buildOperation(
            outboxRow(op = "delete", payload = mapOf("id" to 42.0)),
            deviceId = "cf_dev_1"
        )
        assertEquals("uuid-1", op.data["local_uuid"])
        assertEquals("delete", op.operation)
    }

    @Test
    fun `vector_clock carried from payload when present`() {
        val op = PushWireContract.buildOperation(
            outboxRow(
                payload = mapOf("vector_clock" to "{\"dev1\":5}", "local_uuid" to "uuid-1")
            ),
            deviceId = "cf_dev_1"
        )
        assertEquals("{\"dev1\":5}", op.vectorClock)
        assertEquals("{\"dev1\":5}", op.data["vector_clock"])
    }

    @Test
    fun `vector_clock defaults to empty clock object`() {
        val op = PushWireContract.buildOperation(
            outboxRow(payload = emptyMap()),
            deviceId = "cf_dev_1"
        )
        assertEquals("{}", op.vectorClock)
        assertEquals("{}", op.data["vector_clock"])
    }

    @Test
    fun `blank deviceId falls back to unknown-origin`() {
        // مراجعة 2026-09-09 #18 في worker: الصفوف ذات الأصل المجهول تُختم
        // 'unknown-origin' — لا هوية فارغة تكسر فلتر الصدى.
        val op = PushWireContract.buildOperation(outboxRow(), deviceId = "")
        assertEquals("unknown-origin", op.deviceId)
    }

    @Test
    fun `missing idempotency key falls back to entity_op_uuid`() {
        val op = PushWireContract.buildOperation(
            outboxRow(idempotencyKey = null),
            deviceId = "cf_dev_1"
        )
        assertEquals("rooms_insert_uuid-1", op.idempotencyKey)
    }

    // ─── ثوابت العقد ─────────────────────────────────────────────

    @Test
    fun `push batch size respects server MAX_BATCH_SIZE`() {
        // worker/src/sync.ts: MAX_BATCH_SIZE = 100 — الدفعات لا تتجاوزه.
        assertEquals(100, CloudflareConfig.PUSH_BATCH_SIZE)
    }

    @Test
    fun `pull batch sizes match flutter contract`() {
        // deltaPullBatchSize=250 و fullPullBatchSize=500 (ترقية 2026-09-15).
        assertEquals(250, CloudflareConfig.DELTA_PULL_BATCH_SIZE)
        assertEquals(500, CloudflareConfig.FULL_PULL_BATCH_SIZE)
    }

    @Test
    fun `builtin worker url matches deployed worker`() {
        assertEquals(
            "https://marina-hotel-api.adenmarina2.workers.dev",
            CloudflareConfig.BUILTIN_WORKER_URL
        )
    }

    @Test
    fun `default credentials are admin-admin for auto-login`() {
        assertEquals("admin", CloudflareConfig.DEFAULT_USERNAME)
        assertEquals("admin", CloudflareConfig.DEFAULT_PASSWORD)
    }

    @Test
    fun `sync entities cover the default sync scope`() {
        // 24 كياناً — نفس migrationOrder في cloudflare_config.dart.
        assertEquals(24, CloudflareConfig.SYNC_ENTITIES.size)
        assertTrue(CloudflareConfig.SYNC_ENTITIES.contains("rooms"))
        assertTrue(CloudflareConfig.SYNC_ENTITIES.contains("blacklist"))
        assertTrue(CloudflareConfig.SYNC_ENTITIES.contains("app_users"))
        // hotel_day_ledger مستبعد عمداً (محلي-فقط بالتصميم — D8).
        assertFalse(CloudflareConfig.SYNC_ENTITIES.contains("hotel_day_ledger"))
    }

    @Test
    fun `d1 constants match wrangler toml`() {
        assertEquals("81a73bba9acc1de5693ff929d0a372ce", CloudflareConfig.D1_ACCOUNT_ID)
        assertEquals("607f1090-83b1-4281-975f-d81b8f6154e7", CloudflareConfig.D1_DATABASE_ID)
    }

    // ─── Login request shape ─────────────────────────────────────

    @Test
    fun `login request carries device_id`() {
        val req = WorkerLoginRequest("admin", "admin", "cf_dev_9")
        val json = gson.toJson(req)
        assertTrue(json.contains("\"device_id\":\"cf_dev_9\""))
        assertTrue(json.contains("\"username\":\"admin\""))
    }

    @Test
    fun `login response deserializes real worker shape`() {
        // الاستجابة الحقيقية: {token, user} — لا حقل success إطلاقاً.
        val json = """
            {"token":"eyJhbGciOiJIUzI1NiJ9.abc","user":{"id":"u1","username":"admin","role":"admin"}}
        """.trimIndent()
        val resp = gson.fromJson(json, WorkerLoginResponse::class.java)
        assertEquals("eyJhbGciOiJIUzI1NiJ9.abc", resp.token)
        assertEquals("admin", resp.user?.username)
        assertEquals("admin", resp.user?.role)
    }

    @Test
    fun `pull response deserializes real worker shape with _entity routing`() {
        val json = """
            {"changes":[{"_entity":"rooms","local_uuid":"r1","room_number":"101","last_modified":1780000000000},
                        {"_entity":"bookings","local_uuid":"b1","guest_name":"أحمد","last_modified":1780000001000}],
             "cursor":"1780000001000","has_more":false,"remaining":null,"errors":[],
             "server_time":1780000001}
        """.trimIndent()
        val resp = gson.fromJson(json, WorkerPullResponse::class.java)
        assertEquals(2, resp.changes?.size)
        assertEquals("rooms", resp.changes!![0]["_entity"])
        assertEquals("bookings", resp.changes!![1]["_entity"])
        assertEquals(1780000001000L, resp.cursor?.toLongOrNull())
        assertEquals(false, resp.hasMore)
        assertTrue(resp.errors.isNullOrEmpty())
        assertNull(resp.remaining)
    }

    @Test
    fun `push response deserializes per-operation results with statuses`() {
        val json = """
            {"results":[
               {"idempotencyKey":"rooms_insert_r1","success":true,"entity":"rooms","entityId":"r1"},
               {"idempotencyKey":"bookings_insert_b1","success":false,"status":"validation_error","error":"vectorClock is required"},
               {"idempotencyKey":"payments_delete_p1","success":true,"skipped":true},
               {"idempotencyKey":"debts_update_d1","success":true,"status":"deleted"}],
             "summary":{"total":4,"success":3,"failed":1,"skipped":1},
             "server_time":1780000001}
        """.trimIndent()
        val resp = gson.fromJson(json, WorkerPushResponse::class.java)
        assertEquals(4, resp.results?.size)
        assertEquals(true, resp.results!![0].success)
        assertEquals("validation_error", resp.results!![1].status)
        assertEquals(true, resp.results!![2].skipped)
        // F1 delete-vs-update: نجاح شكلي مع status=deleted.
        assertEquals("deleted", resp.results!![3].status)
        assertEquals(4, resp.summary?.total)
        assertEquals(1, resp.summary?.failed)
    }
}
