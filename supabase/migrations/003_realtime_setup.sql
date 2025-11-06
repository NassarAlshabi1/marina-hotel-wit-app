-- ============================================================================
-- Marina Hotel - Supabase Realtime Setup
-- إعداد Realtime لضمان بث التغييرات لجميع الجداول الأساسية
-- ============================================================================

-- تأكد من إضافة جميع الجداول إلى منشور supabase_realtime (يدعم Realtime)
DO $$
DECLARE
  tbl TEXT;
  target_tables CONSTANT TEXT[] := ARRAY[
    'rooms',
    'bookings',
    'booking_notes',
    'employees',
    'expenses',
    'cash_transactions',
    'payments',
    'debts'
  ];
BEGIN
  FOREACH tbl IN ARRAY target_tables LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', tbl);
    END IF;
  END LOOP;
END $$;

-- دالة بسيطة لإعادة استخدام المشغلات في حالة الحاجة لمراقبة إضافية
CREATE OR REPLACE FUNCTION public.notify_table_changes()
RETURNS trigger AS $$
BEGIN
  -- Supabase Realtime يقوم تلقائياً ببث التغييرات، يتم الإبقاء على الدالة لأغراض التوسعة مستقبلاً
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
