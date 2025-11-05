# دليل Supabase Realtime لتطبيق Marina Hotel

هذا الدليل يشرح كيفية تفعيل واستخدام نظام Realtime في Supabase داخل مشروع Marina Hotel لجعل البيانات تتحدث فورياً على الأجهزة بدون تحديث يدوي.

## ما هو Realtime؟

- Realtime هو خدمة بث أحداث من قاعدة بيانات PostgreSQL عبر WebSocket.
- كل عملية INSERT/UPDATE/DELETE على الجداول المدرجة في Publication يتم بثها فورًا إلى العملاء المتصلين.
- في Supabase، يكفي إضافة الجداول إلى `PUBLICATION supabase_realtime` لتبدأ الأحداث في الوصول إلى تطبيق Flutter عبر `supabase_flutter`.

## المتطلبات

- تم تفعيل Supabase في التطبيق عبر `SupabaseConfig.initialize()` في `main.dart`.
- RLS مفعّل والجداول ضمن سكيمة `public`.
- الجداول مضافة إلى Publication: rooms, bookings, booking_notes, employees, expenses, payments, cash_transactions, debts.

## خطوات الإعداد (ملخص التنفيذ)

1. إضافة ملفات الترحيل SQL:
   - `supabase/migrations/003_realtime_setup.sql`
   - `supabase/migrations/004_realtime_additional_tables.sql`
2. هذه الملفات تقوم بـ:
   - إضافة الجداول إلى Publication `supabase_realtime`.
   - إنشاء Triggers نموذجية للبث (اختيارية)، والاعتماد الأساسي على Publication.
   - إضافة دوال إحصائية جاهزة للاستدعاء من التطبيق.
3. إنشاء Widgets في Flutter لشاشات تعرض تحديثات فورية وإحصائيات حية.

## أمثلة استخدام في Flutter

### الاشتراك في بث جدول

```dart
final channel = Supabase.instance.client
  .channel('public:rooms')
  .onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'rooms',
    callback: (payload) {
      // payload.eventType: insert/update/delete
      // payload.newRecord / payload.oldRecord
    },
  )
  .subscribe();

// لإلغاء الاشتراك
Supabase.instance.client.removeChannel(channel);
```

### جلب إحصائيات جاهزة

```dart
final res = await Supabase.instance.client.rpc('get_room_statistics');
final stats = (res as Map?)?.cast<String, dynamic>();
```

## أفضل الممارسات

- استخدم قناة لكل جدول لسهولة الإدارة وإلغاء الاشتراك.
- طبّق Debounce إذا كان هناك تدفق أحداث سريع لتقليل إعادة الرسم.
- اجعل واجهاتك RTL ومتوافقة مع ثيم التطبيق الحالي.
- عند عرض القوائم، حدّث البيانات تدريجياً وتجنّب عمليات جلب كاملة متكررة.

## حل المشاكل الشائعة

- لا تصلني الأحداث:
  - تأكد أن الجدول مضاف إلى Publication `supabase_realtime`.
  - تأكد من أن سكيمة الجدول صحيحة (public) وتطابق ما في الاشتراك.
  - تحقق من اتصال الإنترنت ونجاح تهيئة Supabase في التطبيق.

- خطأ صلاحيات أو RLS:
  - تأكد من سياسات RLS بما يسمح بقراءة السجلات المناسبة للمستخدم الحالي.
  - Realtime يبث الأحداث، لكنه لا يتجاوز RLS عند القراءة التقليدية.

- ازدواجية اشتراكات:
  - تأكد من إلغاء القنوات في `dispose()`.
  - لا تنشئ نفس القناة عدة مرات داخل نفس الشاشة.

- اختلاف التوقيت:
  - احرص على تحويل التواريخ إلى UTC عند تمريرها إلى دوال الإحصاء.

## أين أجد الشاشات؟

- `mobile/lib/screens/realtime/realtime_dashboard_example.dart`
- `mobile/lib/screens/realtime/employees_realtime_screen.dart`
- `mobile/lib/screens/realtime/expenses_realtime_screen.dart`
- `mobile/lib/screens/realtime/payments_realtime_screen.dart`

## ملاحظات

- تم الالتزام بالـ RTL والعناوين العربية.
- لا حاجة لتعديل ملفات موجودة؛ جميع الإضافات في ملفات جديدة.
- يمكنك دمج هذه الشاشات في الـ Navigation القائم عبر إضافة Routes أو أزرار وصول.
