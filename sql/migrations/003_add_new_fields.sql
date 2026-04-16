-- ===================================================
-- إضافة الحقول الجديدة المطلوبة للتزامن
-- Migration: 003_add_new_fields.sql
-- ===================================================

USE hotel_db;

-- جدول bookings - إضافة حقول معلومات النزيل والدفع
ALTER TABLE bookings 
    ADD COLUMN IF NOT EXISTS payment_status VARCHAR(20) DEFAULT 'pending',
    ADD INDEX idx_payment_status (payment_status);

-- جدول booking_notes - إضافة حقول التنبيهات
ALTER TABLE booking_notes 
    ADD COLUMN IF NOT EXISTS alert_type VARCHAR(20) DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS alert_until TIMESTAMP NULL,
    ADD INDEX idx_alert (alert_type, alert_until);

-- جدول employees - إضافة حقول إضافية
ALTER TABLE employees 
    ADD COLUMN IF NOT EXISTS id_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS nationality VARCHAR(50),
    ADD COLUMN IF NOT EXISTS hire_date DATE,
    ADD INDEX idx_id_number (id_number);

-- جدول payments - إضافة وصف
ALTER TABLE payments 
    ADD COLUMN IF NOT EXISTS description TEXT;

-- جدول cash_transactions - إضافة حقل balance_after
ALTER TABLE cash_transactions 
    ADD COLUMN IF NOT EXISTS balance_after DECIMAL(10,2) DEFAULT 0;

-- التحقق من تغيير اسم حقل room_type في rooms
-- بعض الأنظمة تستخدم type والبعض يستخدم room_type
SET @column_exists = (
    SELECT COUNT(*) 
    FROM information_schema.columns 
    WHERE table_schema = 'hotel_db' 
    AND table_name = 'rooms' 
    AND column_name = 'room_type'
);

-- إذا لم يكن room_type موجوداً ولكن type موجود، نضيف alias
SET @type_exists = (
    SELECT COUNT(*) 
    FROM information_schema.columns 
    WHERE table_schema = 'hotel_db' 
    AND table_name = 'rooms' 
    AND column_name = 'type'
);

-- إذا كان type موجود، نضيف عمود room_type كنسخة منه
-- سنستخدم trigger للحفاظ على التزامن
SET @sql_add_room_type = IF(@column_exists = 0 AND @type_exists > 0,
    'ALTER TABLE rooms ADD COLUMN room_type VARCHAR(50) AFTER type',
    'SELECT "room_type column handled" AS status'
);
PREPARE stmt FROM @sql_add_room_type;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- نسخ القيم من type إلى room_type إذا كان جديد
UPDATE rooms SET room_type = type WHERE room_type IS NULL AND type IS NOT NULL;

-- إضافة trigger للحفاظ على التزامن بين type و room_type
DROP TRIGGER IF EXISTS sync_room_type_insert;
DROP TRIGGER IF EXISTS sync_room_type_update;

DELIMITER $$
CREATE TRIGGER sync_room_type_insert BEFORE INSERT ON rooms
FOR EACH ROW
BEGIN
    IF NEW.room_type IS NULL AND NEW.type IS NOT NULL THEN
        SET NEW.room_type = NEW.type;
    ELSEIF NEW.type IS NULL AND NEW.room_type IS NOT NULL THEN
        SET NEW.type = NEW.room_type;
    END IF;
END$$

CREATE TRIGGER sync_room_type_update BEFORE UPDATE ON rooms
FOR EACH ROW
BEGIN
    IF NEW.room_type != OLD.room_type THEN
        SET NEW.type = NEW.room_type;
    ELSEIF NEW.type != OLD.type THEN
        SET NEW.room_type = NEW.type;
    END IF;
END$$
DELIMITER ;

SELECT '✓ تم إضافة الحقول الجديدة بنجاح' AS status;
