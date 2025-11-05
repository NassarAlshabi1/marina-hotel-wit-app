-- ============================================================================
-- Marina Hotel - Supabase Realtime Setup for Additional Tables
-- إعداد البث الفوري للجداول الإضافية
-- ============================================================================

-- تفعيل Realtime للجداول الإضافية
ALTER PUBLICATION supabase_realtime ADD TABLE employees;
ALTER PUBLICATION supabase_realtime ADD TABLE expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE payments;
ALTER PUBLICATION supabase_realtime ADD TABLE cash_transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE debts;

-- ============================================================================
-- إنشاء Triggers للبث التلقائي
-- ============================================================================

DROP TRIGGER IF EXISTS employees_realtime_broadcast ON employees;
CREATE TRIGGER employees_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON employees
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

DROP TRIGGER IF EXISTS expenses_realtime_broadcast ON expenses;
CREATE TRIGGER expenses_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON expenses
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

DROP TRIGGER IF EXISTS payments_realtime_broadcast ON payments;
CREATE TRIGGER payments_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON payments
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

DROP TRIGGER IF EXISTS cash_transactions_realtime_broadcast ON cash_transactions;
CREATE TRIGGER cash_transactions_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON cash_transactions
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

DROP TRIGGER IF EXISTS debts_realtime_broadcast ON debts;
CREATE TRIGGER debts_realtime_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON debts
  FOR EACH ROW
  EXECUTE FUNCTION broadcast_table_changes();

-- ============================================================================
-- دوال إحصائيات فورية للجداول الإضافية
-- ============================================================================

CREATE OR REPLACE FUNCTION get_employee_statistics()
RETURNS JSON AS $$
DECLARE
  stats JSON;
BEGIN
  SELECT json_build_object(
    'total', COUNT(*),
    'active', COUNT(*) FILTER (WHERE status = 'active'),
    'inactive', COUNT(*) FILTER (WHERE status = 'inactive'),
    'terminated', COUNT(*) FILTER (WHERE status = 'terminated'),
    'total_salary', COALESCE(SUM(basic_salary) FILTER (WHERE status = 'active'), 0),
    'last_updated', NOW()
  ) INTO stats
  FROM employees
  WHERE deleted_at IS NULL;
  
  RETURN stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_expense_statistics(
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  stats JSON;
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  v_start_date := COALESCE(p_start_date, date_trunc('month', NOW()));
  v_end_date := COALESCE(p_end_date, NOW());
  
  SELECT json_build_object(
    'total_count', COUNT(*),
    'total_amount', COALESCE(SUM(amount), 0),
    'salary_expenses', COALESCE(SUM(amount) FILTER (WHERE expense_type = 'salary'), 0),
    'maintenance_expenses', COALESCE(SUM(amount) FILTER (WHERE expense_type = 'maintenance'), 0),
    'utilities_expenses', COALESCE(SUM(amount) FILTER (WHERE expense_type = 'utilities'), 0),
    'supplies_expenses', COALESCE(SUM(amount) FILTER (WHERE expense_type = 'supplies'), 0),
    'other_expenses', COALESCE(SUM(amount) FILTER (WHERE expense_type = 'other'), 0),
    'start_date', v_start_date,
    'end_date', v_end_date,
    'last_updated', NOW()
  ) INTO stats
  FROM expenses
  WHERE deleted_at IS NULL
    AND created_at BETWEEN v_start_date AND v_end_date;
  
  RETURN stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_payment_statistics(
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  stats JSON;
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  v_start_date := COALESCE(p_start_date, date_trunc('month', NOW()));
  v_end_date := COALESCE(p_end_date, NOW());
  
  SELECT json_build_object(
    'total_count', COUNT(*),
    'total_amount', COALESCE(SUM(amount), 0),
    'cash_payments', COALESCE(SUM(amount) FILTER (WHERE payment_method = 'نقدي'), 0),
    'card_payments', COALESCE(SUM(amount) FILTER (WHERE payment_method = 'بطاقة'), 0),
    'transfer_payments', COALESCE(SUM(amount) FILTER (WHERE payment_method = 'تحويل'), 0),
    'other_payments', COALESCE(SUM(amount) FILTER (WHERE payment_method = 'آخر'), 0),
    'room_revenue', COALESCE(SUM(amount) FILTER (WHERE revenue_type = 'room'), 0),
    'service_revenue', COALESCE(SUM(amount) FILTER (WHERE revenue_type = 'service'), 0),
    'other_revenue', COALESCE(SUM(amount) FILTER (WHERE revenue_type = 'other'), 0),
    'start_date', v_start_date,
    'end_date', v_end_date,
    'last_updated', NOW()
  ) INTO stats
  FROM payments
  WHERE deleted_at IS NULL
    AND payment_date BETWEEN v_start_date AND v_end_date;
  
  RETURN stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_employee_statistics() IS 
'دالة لحساب إحصائيات الموظفين الفورية';

COMMENT ON FUNCTION get_expense_statistics(TIMESTAMPTZ, TIMESTAMPTZ) IS 
'دالة لحساب إحصائيات المصروفات الفورية';

COMMENT ON FUNCTION get_payment_statistics(TIMESTAMPTZ, TIMESTAMPTZ) IS 
'دالة لحساب إحصائيات الدفعات الفورية';
