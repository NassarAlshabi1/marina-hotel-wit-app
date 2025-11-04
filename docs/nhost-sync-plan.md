# Nhost Sync Plan (Supabase/Postgres Compatible)

هذه الوثيقة تلخّص خطة المزامنة والتهيئة المقترحة بين تطبيق Flutter (Drift) وخادم Postgres/Nhost.

## 1. نظرة عامة على سير المزامنة
- **Outbox محلي**: يحتفظ بكل عمليات create/update/delete مع `localUuid` ونسخة بيانات JSON.
- **Push**: إرسال دفعة JSON إلى Endpoint (REST أو Edge Function). الخادم ينفذ عمليات upsert/delete داخل معاملات ويولّد `serverId` ويربطه بـ `localUuid`.
- **Pull**: الجهاز يطلب التغييرات منذ آخر `last_modified` معروف، والخادم يعيد السجلات المعدّلة لكل جدول.
- **SyncState**: حفظ `last_push_ts` و `last_pull_ts` محلياً (Drift) وأيضاً في خادم عند الحاجة.

## 2. مخطط قاعدة البيانات (Postgres DDL)
- الاعتماد على `uuid` لـ `local_uuid` و `timestamptz` للتواريخ.
- تفعيل الامتداد:
  ```sql
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  ```
- مثال جدول `rooms`:
  ```sql
  CREATE TABLE rooms (
    id bigserial PRIMARY KEY,
    local_uuid uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    room_number text NOT NULL UNIQUE,
    type text NOT NULL,
    price numeric NOT NULL,
    status text NOT NULL,
    image_url text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    last_modified timestamptz NOT NULL DEFAULT now(),
    version integer NOT NULL DEFAULT 1,
    origin text NOT NULL DEFAULT 'server'
  );
  CREATE INDEX idx_rooms_last_modified ON rooms(last_modified);
  ```
- النمط نفسه يطبّق على الجداول الأخرى (`bookings`, `booking_notes`, `employees`, `expenses`, `cash_transactions`, `payments`) مع الحقول الملائمة.

## 3. سياسات RLS (اختيارية)
```sql
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY rooms_select_public
ON rooms FOR SELECT
USING (deleted_at IS NULL);

-- مثال للسماح للمالك فقط (يتطلب حقل created_by)
CREATE POLICY rooms_owner_policy
ON rooms FOR ALL
USING (origin = 'server' OR created_by = auth.uid())
WITH CHECK (origin = 'server' OR created_by = auth.uid());
```
- استخدم دور `service_role` في Edge Function لتنفيذ عمليات upsert بدون قيود RLS.

## 4. وظائف SQL/PLPGSQL للـ Push/Pull
- وظيفة `apply_room_change` تتعامل مع create/update/delete وتعيد `sync_result`.
- وظيفة `process_changes(p_changes jsonb)` تمر على العناصر وترجع نتائج لكل عنصر.
- وظيفة `fetch_changes(p_since timestamptz)` تعيد JSON لكل الجداول التي تحتوي `last_modified > p_since`.

## 5. مثال Edge Function (TypeScript / Deno)
```ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(url, key);

serve(async (req) => {
  const auth = req.headers.get("x-hasura-admin-secret");
  if (auth !== Deno.env.get("HASURA_ADMIN_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  if (req.method === "POST") {
    const body = await req.json();
    const { data, error } = await supabase.rpc("process_changes", { p_changes: body.changes });
    if (error) return new Response(JSON.stringify({ error }), { status: 400 });
    return new Response(JSON.stringify({ results: data }), { headers: { "content-type": "application/json" } });
  }

  const since = req.headers.get("x-last-modified") ?? "1970-01-01T00:00:00Z";
  const { data, error } = await supabase.rpc("fetch_changes", { p_since: since });
  if (error) return new Response(JSON.stringify({ error }), { status: 400 });
  return new Response(JSON.stringify(data), { headers: { "content-type": "application/json" } });
});
```

## 6. أمثلة Dart/Drift
- **Push**: إرسال دفعة عبر HTTP POST، ثم تحديث Outbox باستخدام نتائج `sync_result` (تعيين `serverId`, `lastModified`, حذف العنصر من outbox).
- **Pull**: استدعاء Endpoint مع `x-last-modified` واستقبال JSON، تطبيق التغييرات عبر Companion مع مقارنة `lastModified` (LWW).
- مثال تحديث بعد pull:
  ```dart
  await (db.update(db.rooms)..where((t) => t.localUuid.equals(localUuid))).write(
    RoomsCompanion(
      status: Value(record['status'] as String),
      serverId: Value(record['id'] as int?),
      lastModified: Value(DateTime.parse(record['last_modified']).millisecondsSinceEpoch ~/ 1000),
      origin: const Value('server'),
    ),
  );
  ```

## 7. استراتيجية حل التعارضات
1. **Last-Write-Wins**: مقارنة `last_modified` (timestamptz). إذا كانت قيمة الخادم أحدث تُطبّق وإلا تُتجاهل.
2. **Version Field**: زيادة `version` عند كل تعديل محلي. رفض أي دفعة تحمل إصداراً أقل من المخزن في الخادم.
3. **Conflict Log**: العمليات التي تفشل (constraints أو إصدار أقدم) تُسجل ويُعاد إرسالها أو تُعرض للمستخدم.
4. **Soft Delete**: حذف منطقي عبر `deleted_at`. أثناء السحب يتم احترام الأحدث.

## 8. ملاحظات تنفيذية
- ضبط Secrets في Nhost/Supabase (`HASURA_ADMIN_SECRET`, `HASURA_WEBHOOK_SECRET`, `HASURA_GRAPHQL_JWT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`).
- تشغيل migrations عبر CLI أو SQL مباشرة.
- اختبار الحماية عبر GraphQL باستخدام Header `x-hasura-admin-secret` أو JWT عند تفعيل RLS.

تستطيع استخدام هذه الوثيقة كمرجع لإنشاء migrations وEdge Functions وتحديث تطبيق Flutter ليعمل بالمزامنة المقترحة.
