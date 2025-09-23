-- Marina Hotel sync and consistency migration
-- Adds updated_at/deleted_at for sync, converts MyISAM tables to InnoDB, and introduces optional room_images table.
-- Safe to run multiple times on MariaDB/MySQL 5.7+ (uses IF NOT EXISTS where supported).

-- 1) Add sync columns to core entities
ALTER TABLE `bookings`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `rooms`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `booking_notes`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `employees`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `expenses`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `cash_transactions`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `suppliers`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

-- users already has updated_at; add deleted_at only
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

-- MyISAM tables to be converted also receive the sync fields
ALTER TABLE `payment`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `invoices`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE `salary_withdrawals`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS `deleted_at` TIMESTAMP NULL DEFAULT NULL;

-- 2) Convert legacy MyISAM tables to InnoDB (required for FK and transactions)
ALTER TABLE `payment` ENGINE=InnoDB;
ALTER TABLE `invoices` ENGINE=InnoDB;
ALTER TABLE `salary_withdrawals` ENGINE=InnoDB;

-- 3) Add missing foreign keys where feasible
-- Ensure payment.booking_id can be nullable for ON DELETE SET NULL
ALTER TABLE `payment`
  MODIFY COLUMN `booking_id` INT(11) NULL;

-- Add FK: payment.booking_id -> bookings.booking_id
ALTER TABLE `payment`
  ADD CONSTRAINT `fk_payment_booking` FOREIGN KEY (`booking_id`) REFERENCES `bookings`(`booking_id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- invoices.booking_id -> bookings.booking_id
ALTER TABLE `invoices`
  MODIFY COLUMN `booking_id` INT(11) NULL,
  ADD CONSTRAINT `fk_invoices_booking` FOREIGN KEY (`booking_id`) REFERENCES `bookings`(`booking_id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- salary_withdrawals.employee_id -> employees.id (logical FK)
ALTER TABLE `salary_withdrawals`
  MODIFY COLUMN `employee_id` INT(11) NULL,
  ADD CONSTRAINT `fk_withdrawals_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- 4) Optional media table for room images
CREATE TABLE IF NOT EXISTS `room_images` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `room_number` VARCHAR(10) NOT NULL,
  `url` VARCHAR(255) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_room_number` (`room_number`),
  CONSTRAINT `fk_room_images_room` FOREIGN KEY (`room_number`) REFERENCES `rooms`(`room_number`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Notes:
-- - If IF NOT EXISTS is unsupported on your MySQL version for ADD COLUMN, re-run conditionally or ignore duplicate column errors.
-- - Some FKs may fail if legacy orphan rows exist; clean data or temporarily disable FK checks during migration if necessary.
