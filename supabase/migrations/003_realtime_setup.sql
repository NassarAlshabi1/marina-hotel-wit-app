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

-- ============================================================================
-- الخطوة 2: إنشاء دالة البث (Broadcast Function)
-- ============================================================================

CREATE OR REPLACE FUNCTION broadcast_table_changes()
RETURNS TRIGGER AS $$
DECLARE
  channel_name TEXT;
  event_type TEXT;
  payload JSON;
BEGIN
  channel_name := TG_TABLE_NAME || '_changes';
  
  IF TG_OP = 'INSERT' THEN
    event_type := 'INSERT';
    payload := row_to_json(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    event_type := 'UPDATE';
    payload := json_build_object(
      'old', row_to_json(OLD),
      'new', row_to_json(NEW)
    );
  ELSIF TG_OP = 'DELETE' THEN
    event_type := 'DELETE';
    payload := row_to_json(OLD);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- الخطوة 3: إنشاء Triggers للبث التلقائي
-- ============================================================================

DROP TRIGGER IF EXISTS rooms_realtime_broadcast ON rooms;
CREATE TRIGGER rooms_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON rooms
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

DROP TRIGGER IF EXISTS bookings_realtime_broadcast ON bookings;
CREATE TRIGGER bookings_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

DROP TRIGGER IF EXISTS booking_notes_realtime_broadcast ON booking_notes;
CREATE TRIGGER booking_notes_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON booking_notes
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

-- ============================================================================
-- الخطوة 4: إنشاء دالة للإحصائيات الفورية
-- ============================================================================

CREATE OR REPLACE FUNCTION get_room_statistics()
RETURNS JSON AS $$
DECLARE
  stats JSON;
BEGIN
  SELECT json_build_object(
    'total', COUNT(*),
    'available', COUNT(*) FILTER (WHERE status = 'شاغرة'),
    'occupied', COUNT(*) FILTER (WHERE status = 'مشغولة'),
    'reserved', COUNT(*) FILTER (WHERE status = 'محجوزة'),
    'maintenance', COUNT(*) FILTER (WHERE status = 'صيانة'),
    'last_updated', NOW()
  ) INTO stats
  FROM rooms
  WHERE deleted_at IS NULL;
  
  RETURN stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_booking_statistics()
RETURNS JSON AS $$
DECLARE
  stats JSON;
BEGIN
  SELECT json_build_object(
    'total', COUNT(*),
    'active', COUNT(*) FILTER (WHERE status = 'حالية'),
    'reserved', COUNT(*) FILTER (WHERE status = 'محجوزة'),
    'checked_out', COUNT(*) FILTER (WHERE status = 'مغادرة'),
    'cancelled', COUNT(*) FILTER (WHERE status = 'ملغاة'),
    'today_checkins', COUNT(*) FILTER (
      WHERE DATE(checkin_date) = CURRENT_DATE AND status = 'محجوزة'
    ),
    'today_checkouts', COUNT(*) FILTER (
      WHERE DATE(checkout_date) = CURRENT_DATE AND status = 'حالية'
    ),
    'last_updated', NOW()
  ) INTO stats
  FROM bookings
  WHERE deleted_at IS NULL;
  
  RETURN stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- دالة بسيطة لإعادة استخدام المشغلات في حالة الحاجة لمراقبة إضافية
CREATE OR REPLACE FUNCTION public.notify_table_changes()
RETURNS trigger AS $$
BEGIN
  -- Supabase Realtime يقوم تلقائياً ببث التغييرات، يتم الإبقاء على الدالة لأغراض التوسعة مستقبلاً
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION broadcast_table_changes() IS 
'دالة لبث التغييرات على الجداول إلى قنوات Realtime';

COMMENT ON FUNCTION get_room_statistics() IS 
'دالة لحساب إحصائيات الغرف الفورية';

COMMENT ON FUNCTION get_booking_statistics() IS 
'دالة لحساب إحصائيات الحجوزات الفورية';
