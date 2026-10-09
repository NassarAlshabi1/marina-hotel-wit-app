-- ===================================================
-- إضافة حقول التزامن للجداول الموجودة
-- Migration: 002_add_sync_fields.sql
-- ===================================================

USE hotel_db;

-- جدول rooms
ALTER TABLE rooms 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS cleaning_status VARCHAR(20) DEFAULT 'clean';

-- إنشاء local_uuid لجميع السجلات الموجودة في rooms
UPDATE rooms SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن
ALTER TABLE rooms ADD INDEX idx_rooms_sync (updated_at, deleted_at);

-- جدول bookings
ALTER TABLE bookings 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

-- إنشاء local_uuid لجميع السجلات الموجودة
UPDATE bookings SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن
ALTER TABLE bookings ADD INDEX idx_bookings_sync (last_calculation, deleted_at);

-- جدول booking_notes
ALTER TABLE booking_notes 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

-- إنشاء local_uuid لجميع السجلات الموجودة
UPDATE booking_notes SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن
ALTER TABLE booking_notes ADD INDEX idx_notes_sync (updated_at, deleted_at);

-- جدول employees
ALTER TABLE employees 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

-- إنشاء local_uuid لجميع السجلات الموجودة
UPDATE employees SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن
ALTER TABLE employees ADD INDEX idx_employees_sync (updated_at, deleted_at);

-- جدول expenses
ALTER TABLE expenses 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS category_uuid VARCHAR(36) NULL;

-- إنشاء local_uuid لجميع السجلات الموجودة
UPDATE expenses SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن والربط بالفئة
ALTER TABLE expenses ADD INDEX idx_expenses_sync (updated_at, deleted_at);
ALTER TABLE expenses ADD INDEX idx_expenses_category (category_uuid);

-- جدول cash_transactions
ALTER TABLE cash_transactions 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

-- إنشاء local_uuid لجميع السجلات الموجودة
UPDATE cash_transactions SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن
ALTER TABLE cash_transactions ADD INDEX idx_cash_sync (updated_at, deleted_at);

-- جدول payment (تحويله إلى payments)
-- التحقق من وجود جدول payment القديم وإعادة تسميته
SET @payment_exists = (SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'hotel_db' AND table_name = 'payment');

-- إذا كان الجدول القديم موجود، إعادة تسميته
SET @sql_rename = IF(@payment_exists > 0, 
    'RENAME TABLE payment TO payments', 
    'SELECT "جدول payment غير موجود" AS status');
PREPARE stmt FROM @sql_rename;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- الآن نضيف الحقول لجدول payments
ALTER TABLE payments 
    ADD COLUMN IF NOT EXISTS local_uuid VARCHAR(36) UNIQUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS revenue_type VARCHAR(50) DEFAULT 'room';

-- إنشاء local_uuid لجميع السجلات الموجودة
UPDATE payments SET local_uuid = UUID() WHERE local_uuid IS NULL;

-- إضافة فهرس للتزامن
ALTER TABLE payments ADD INDEX idx_payments_sync (updated_at, deleted_at);
ALTER TABLE payments ADD INDEX idx_payments_type (revenue_type);

SELECT '✓ تم إضافة حقول التزامن لجميع الجداول بنجاح' AS status;
