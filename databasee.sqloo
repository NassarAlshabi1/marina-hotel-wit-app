-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: May 26, 2025 at 01:10 AM
-- Server version: 5.7.34
-- PHP Version: 8.0.28

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `hotel_db`
--

-- --------------------------------------------------------

--
-- Table structure for table `bookings`
--

CREATE TABLE `bookings` (
  `booking_id` int(11) NOT NULL,
  `guest_id` int(11) DEFAULT NULL,
  `guest_name` varchar(100) NOT NULL,
  `guest_id_type` enum('بطاقة شخصية','رخصة قيادة','جواز سفر') NOT NULL,
  `guest_id_number` varchar(50) NOT NULL,
  `guest_id_issue_date` date DEFAULT NULL,
  `guest_id_issue_place` varchar(50) DEFAULT NULL,
  `guest_phone` varchar(20) NOT NULL,
  `guest_nationality` varchar(50) DEFAULT NULL,
  `guest_email` varchar(100) DEFAULT NULL,
  `guest_address` text,
  `guest_created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `room_number` varchar(10) NOT NULL,
  `checkin_date` datetime NOT NULL,
  `checkout_date` datetime DEFAULT NULL,
  `status` enum('شاغرة','محجوزة') NOT NULL DEFAULT 'محجوزة' COMMENT 'حالة الحجز',
  `notes` text,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expected_nights` int(11) DEFAULT '1' COMMENT 'عدد الليالي المتوقع',
  `actual_checkout` datetime DEFAULT NULL,
  `calculated_nights` int(11) DEFAULT '1',
  `last_calculation` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table `bookings`
--

INSERT INTO `bookings` (`booking_id`, `guest_id`, `guest_name`, `guest_id_type`, `guest_id_number`, `guest_id_issue_date`, `guest_id_issue_place`, `guest_phone`, `guest_nationality`, `guest_email`, `guest_address`, `guest_created_at`, `room_number`, `checkin_date`, `checkout_date`, `status`, `notes`, `created_at`, `expected_nights`, `actual_checkout`, `calculated_nights`, `last_calculation`) VALUES
(2, 2, 'محمد عهد علي  الموزعي', 'بطاقة شخصية', '1444111666', NULL, NULL, '22228744', 'هندي', NULL, NULL, '2025-05-11 01:54:42', '104', '2025-05-10 00:00:00', NULL, 'محجوزة', '0', '2025-05-11 01:54:42', 1, NULL, 6, '2025-05-15 17:06:16'),
(4, 4, 'نصار عبدالله حسن الشعبي ', 'بطاقة شخصية', '5558841695', '2024-10-20', 'عدن', '773114243', 'يمني', '', '', '2025-05-15 17:01:41', '101', '2025-05-15 00:00:00', NULL, 'محجوزة', '', '2025-05-15 17:01:41', 1, NULL, 1, '2025-05-15 17:01:41'),
(5, 5, 'بلقيس فتحي سرور ', 'بطاقة شخصية', '543322888', '2019-05-15', 'تعز', '77311424', 'يمني', '', '', '2025-05-15 17:11:21', '102', '2025-05-15 00:00:00', NULL, 'محجوزة', 'تريد تطول', '2025-05-15 17:11:21', 1, NULL, 1, '2025-05-15 17:11:21'),
(6, NULL, 'ليلى مسعد', 'جواز سفر', '1111112', '2025-05-16', 'عدن', '7711111', 'يمني', NULL, NULL, '2025-05-16 02:01:01', '101', '2025-05-16 00:00:00', NULL, 'محجوزة', '', '2025-05-16 02:01:01', 1, NULL, 0, '2025-05-16 02:01:01'),
(7, 7, 'نصار عبدالله حسن الشعبي', 'جواز سفر', '1444111666', '2024-05-07', 'عدن', '77311424', 'يمني', NULL, NULL, '2025-05-16 03:45:19', '201', '2025-05-16 00:00:00', NULL, 'محجوزة', NULL, '2025-05-16 03:45:19', 1, NULL, 0, '2025-05-16 03:45:19');

--
-- Triggers `bookings`
--
DELIMITER $$
CREATE TRIGGER `after_booking_insert` AFTER INSERT ON `bookings` FOR EACH ROW BEGIN
    UPDATE `rooms` 
    SET `status` = NEW.status
    WHERE `room_number` = NEW.room_number;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `after_booking_update` AFTER UPDATE ON `bookings` FOR EACH ROW BEGIN
    IF NEW.status != OLD.status THEN
        UPDATE `rooms` 
        SET `status` = NEW.status
        WHERE `room_number` = NEW.room_number;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `before_booking_insert` BEFORE INSERT ON `bookings` FOR EACH ROW BEGIN
    -- تعيين تاريخ الوصول إذا لم يتم تحديده
    IF NEW.checkin_date IS NULL THEN
        SET NEW.checkin_date = CURDATE();
    END IF;
    
    -- التحقق من أن الغرفة شاغرة قبل الحجز
    IF (SELECT `status` FROM `rooms` WHERE `room_number` = NEW.room_number) != 'شاغرة' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'لا يمكن حجز الغرفة لأنها غير شاغرة';
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `calculate_nights_on_insert` BEFORE INSERT ON `bookings` FOR EACH ROW BEGIN
    SET NEW.calculated_nights = DATEDIFF(CURRENT_DATE(), DATE(NEW.checkin_date)) + 
                              (CASE WHEN TIME(CURRENT_TIME()) > '13:00:00' THEN 1 ELSE 0 END);
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `calculate_nights_on_update` BEFORE UPDATE ON `bookings` FOR EACH ROW BEGIN
    IF NEW.status = 'محجوزة' THEN
        SET NEW.calculated_nights = DATEDIFF(CURRENT_DATE(), DATE(NEW.checkin_date)) + 
                                  (CASE WHEN TIME(CURRENT_TIME()) > '13:00:00' THEN 1 ELSE 0 END);
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `booking_notes`
--

CREATE TABLE `booking_notes` (
  `note_id` int(11) NOT NULL,
  `booking_id` int(11) NOT NULL,
  `note_text` text NOT NULL,
  `alert_type` enum('high','medium','low') NOT NULL DEFAULT 'medium',
  `alert_until` datetime DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT '1',
  `created_at` datetime NOT NULL,
  `created_by` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Dumping data for table `booking_notes`
--

INSERT INTO `booking_notes` (`note_id`, `booking_id`, `note_text`, `alert_type`, `alert_until`, `is_active`, `created_at`, `created_by`) VALUES
(2, 6, 'انتبه منه', 'high', NULL, 1, '2025-05-22 01:19:50', NULL),
(3, 7, 'شل بطاقتة', 'high', NULL, 1, '2025-05-22 01:20:05', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `cash_register`
--

CREATE TABLE `cash_register` (
  `id` int(11) NOT NULL,
  `date` date NOT NULL,
  `opening_balance` decimal(10,2) NOT NULL DEFAULT '0.00',
  `closing_balance` decimal(10,2) DEFAULT NULL,
  `total_income` decimal(10,2) NOT NULL DEFAULT '0.00',
  `total_expense` decimal(10,2) NOT NULL DEFAULT '0.00',
  `notes` text COLLATE utf8mb4_unicode_ci,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `status` enum('open','closed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `cash_register`
--

INSERT INTO `cash_register` (`id`, `date`, `opening_balance`, `closing_balance`, `total_income`, `total_expense`, `notes`, `created_by`, `created_at`, `updated_at`, `status`) VALUES
(1, '2025-05-21', 0.00, NULL, 640000.00, 0.00, NULL, NULL, '2025-05-21 21:41:31', '2025-05-21 21:42:35', 'open'),
(2, '2025-05-22', 0.00, NULL, 0.00, 0.00, NULL, NULL, '2025-05-22 00:45:20', '2025-05-22 00:45:20', 'open'),
(3, '2025-05-23', 0.00, NULL, 0.00, 0.00, NULL, NULL, '2025-05-23 19:02:18', '2025-05-23 19:02:18', 'open'),
(4, '2025-05-24', 0.00, 45000.00, 45000.00, 0.00, '', NULL, '2025-05-24 03:33:44', '2025-05-24 03:34:47', 'closed');

-- --------------------------------------------------------

--
-- Table structure for table `cash_transactions`
--

CREATE TABLE `cash_transactions` (
  `id` int(11) NOT NULL,
  `register_id` int(11) NOT NULL,
  `transaction_type` enum('income','expense') COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `reference_type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `reference_id` int(11) NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `transaction_time` datetime NOT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `cash_transactions`
--

INSERT INTO `cash_transactions` (`id`, `register_id`, `transaction_type`, `amount`, `reference_type`, `reference_id`, `description`, `transaction_time`, `created_by`, `created_at`) VALUES
(1, 1, 'income', 640000.00, 'booking', 0, 'دخل تاريخ 20/5/2025', '2025-05-21 23:42:35', NULL, '2025-05-21 21:42:35'),
(2, 4, 'income', 45000.00, 'booking', 0, 'ايراد', '2025-05-24 05:34:34', NULL, '2025-05-24 03:34:34');

-- --------------------------------------------------------

--
-- Table structure for table `employees`
--

CREATE TABLE `employees` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `basic_salary` decimal(12,2) NOT NULL DEFAULT '0.00',
  `status` enum('active','inactive') DEFAULT 'active'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table `employees`
--

INSERT INTO `employees` (`id`, `name`, `basic_salary`, `status`) VALUES
(1, 'محمد احمد', 0.00, 'active'),
(2, 'عبدالله طه', 0.00, 'active'),
(3, 'عمار الشوب', 0.00, 'active'),
(4, 'سعيد الاورمو', 0.00, 'active');

-- --------------------------------------------------------

--
-- Table structure for table `expenses`
--

CREATE TABLE `expenses` (
  `id` int(11) NOT NULL,
  `expense_type` varchar(50) NOT NULL,
  `related_id` int(11) DEFAULT NULL,
  `description` varchar(255) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `date` date NOT NULL,
  `cash_transaction_id` int(11) DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table `expenses`
--

INSERT INTO `expenses` (`id`, `expense_type`, `related_id`, `description`, `amount`, `date`, `cash_transaction_id`, `created_by`, `created_at`) VALUES
(1, 'utilities', NULL, 'فاتورة كهرباء', 450000.00, '2025-05-10', NULL, NULL, '2025-05-16 02:46:18'),
(2, 'other', NULL, 'ديزل', 21500.00, '2025-05-23', NULL, NULL, '2025-05-24 03:37:16'),
(3, 'other', NULL, 'ديزل', 20000.00, '2025-05-24', NULL, NULL, '2025-05-24 03:37:42'),
(4, 'purchases', 4, 'ديزل 11', 25000.00, '2025-05-24', NULL, NULL, '2025-05-25 02:58:34'),
(5, 'purchases', 2, 'قصبة', 2000.00, '2025-05-24', NULL, NULL, '2025-05-25 02:59:28'),
(6, 'purchases', 1, 'بوكس', 5000.00, '2025-05-22', NULL, NULL, '2025-05-25 03:17:29'),
(7, 'purchases', 3, 'اكياس', 10000.00, '2025-05-24', NULL, NULL, '2025-05-25 03:30:30'),
(8, 'other', NULL, 'ديزل', 2.00, '2025-05-25', NULL, NULL, '2025-05-25 04:38:23');

-- --------------------------------------------------------

--
-- Table structure for table `expense_logs`
--

CREATE TABLE `expense_logs` (
  `id` int(11) NOT NULL,
  `expense_id` int(11) NOT NULL,
  `action` varchar(50) NOT NULL,
  `details` text,
  `user_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table `expense_logs`
--

INSERT INTO `expense_logs` (`id`, `expense_id`, `action`, `details`, `user_id`, `created_at`) VALUES
(1, 1, 'create', 'دفع فاتورة فاتورة كهرباء', NULL, '2025-05-16 02:46:18'),
(2, 2, 'create', NULL, NULL, '2025-05-24 03:37:16'),
(3, 3, 'create', NULL, NULL, '2025-05-24 03:37:42'),
(4, 4, 'create', 'شراء من المورد ID: 4', NULL, '2025-05-25 02:58:34'),
(5, 5, 'create', 'شراء من المورد ID: 2', NULL, '2025-05-25 02:59:28'),
(6, 6, 'create', 'تم الشراء من المورد ID: 1', NULL, '2025-05-25 03:17:29'),
(7, 7, 'create', 'تم الشراء من المورد ID: 3', NULL, '2025-05-25 03:30:30'),
(8, 4, 'update', 'تم تعديل المصروف: النوع=purchases, المبلغ=25000', NULL, '2025-05-25 03:33:49'),
(9, 8, 'create', 'تم إضافة مصروف: ديزل', NULL, '2025-05-25 04:38:23');

-- --------------------------------------------------------

--
-- Table structure for table `invoices`
--

CREATE TABLE `invoices` (
  `id` int(11) NOT NULL,
  `booking_id` int(11) DEFAULT NULL,
  `No_room` int(11) NOT NULL,
  `amount` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `invoices`
--

INSERT INTO `invoices` (`id`, `booking_id`, `No_room`, `amount`, `created_at`) VALUES
(1, 5, 0, 30000, '2025-05-07 03:04:13'),
(2, 4, 0, 60000, '2025-05-07 03:18:23'),
(3, 5, 0, 3000, '2025-05-07 03:36:44'),
(4, 3, 101, 75000, '2025-05-15 16:07:00');

-- --------------------------------------------------------

--
-- Table structure for table `payment`
--

CREATE TABLE `payment` (
  `payment_id` int(11) NOT NULL,
  `booking_id` int(11) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `notes` text,
  `payment_method` varchar(50) NOT NULL,
  `revenue_type` enum('room','restaurant','services','other') NOT NULL DEFAULT 'room',
  `cash_transaction_id` int(11) DEFAULT NULL,
  `room_number` int(11) DEFAULT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `payment`
--

INSERT INTO `payment` (`payment_id`, `booking_id`, `amount`, `payment_date`, `notes`, `payment_method`, `revenue_type`, `cash_transaction_id`, `room_number`) VALUES
(13, 4, 15000.00, '2025-05-16 02:45:00', '', 'نقدي', 'room', NULL, NULL),
(12, 5, 10000.00, '2025-05-10 19:29:00', '', 'نقدي', 'room', NULL, NULL),
(11, 2, 90000.00, '2025-05-15 19:26:00', '', 'نقدي', 'room', NULL, NULL),
(14, 6, 35000.00, '2025-05-24 02:35:00', '', 'نقدي', 'room', NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `permissions`
--

CREATE TABLE `permissions` (
  `permission_id` int(11) NOT NULL,
  `permission_name` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `permission_description` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `permission_code` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `permissions`
--

INSERT INTO `permissions` (`permission_id`, `permission_name`, `permission_description`, `permission_code`) VALUES
(1, 'إدارة المستخدمين', 'إضافة وتعديل وحذف المستخدمين وإدارة صلاحياتهم', 'manage_users'),
(2, 'إدارة الغرف', 'إضافة وتعديل وحذف الغرف وإدارة أسعارها', 'manage_rooms'),
(3, 'إدارة الحجوزات', 'إضافة وتعديل وحذف الحجوزات', 'manage_bookings'),
(4, 'إدارة المدفوعات', 'تسجيل وإدارة المدفوعات', 'manage_payments'),
(5, 'إدارة المصروفات', 'تسجيل وإدارة المصروفات', 'manage_expenses'),
(6, 'عرض التقارير', 'عرض وطباعة التقارير المالية', 'view_reports'),
(7, 'إدارة الصندوق', 'إدارة حركة الصندوق اليومية', 'manage_cash'),
(8, 'إدارة الإعدادات', 'تعديل إعدادات النظام', 'manage_settings'),
(9, 'عرض لوحة التحكم', 'عرض لوحة التحكم الرئيسية', 'view_dashboard');

-- --------------------------------------------------------

--
-- Table structure for table `rooms`
--

CREATE TABLE `rooms` (
  `room_number` varchar(10) NOT NULL,
  `type` varchar(50) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `status` enum('شاغرة','محجوزة') NOT NULL DEFAULT 'شاغرة' COMMENT 'حالة الغرفة'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table `rooms`
--

INSERT INTO `rooms` (`room_number`, `type`, `price`, `status`) VALUES
('101', 'سرير عائلي', 15000.00, 'محجوزة'),
('102', 'سرير عائلي', 15000.00, 'محجوزة'),
('103', 'سرير عائلي', 15000.00, 'محجوزة'),
('104', 'سرير فردي ', 15000.00, 'محجوزة'),
('201', 'سرير فردي', 15000.00, 'محجوزة'),
('202', 'سرير عائلي', 10000.00, 'شاغرة'),
('203', 'سرير عائلي', 17000.00, 'شاغرة'),
('204', 'سرير فردي ', 15000.00, 'شاغرة'),
('301', 'سرير عائلي', 7000.00, 'شاغرة'),
('302', 'سرير فردي ', 14000.00, 'شاغرة'),
('303', 'سرير فردي', 12000.00, 'شاغرة'),
('304', 'سرير فردي ', 10000.00, 'شاغرة'),
('401', 'سرير فردي', 10000.00, 'شاغرة'),
('402', 'سرير فردي ', 10000.00, 'شاغرة'),
('403', 'سرير فردي', 12000.00, 'شاغرة'),
('404', 'سرير فردي ', 14000.00, 'شاغرة'),
('501', 'سرير فردي', 5000.00, 'شاغرة'),
('502', 'سرير فردي ', 7000.00, 'شاغرة');

-- --------------------------------------------------------

--
-- Table structure for table `salary_withdrawals`
--

CREATE TABLE `salary_withdrawals` (
  `id` int(11) NOT NULL,
  `employee_id` int(11) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `date` date NOT NULL,
  `notes` text,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

-- --------------------------------------------------------

--
-- Table structure for table `suppliers`
--

CREATE TABLE `suppliers` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table `suppliers`
--

INSERT INTO `suppliers` (`id`, `name`) VALUES
(1, 'مواد كهربائيات'),
(2, 'سباكة'),
(3, 'منظفات واكياس قمامة'),
(4, 'اخرى');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `user_id` int(11) NOT NULL,
  `username` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `full_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_type` enum('admin','employee') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'employee',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `last_login` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`user_id`, `username`, `password`, `full_name`, `email`, `phone`, `user_type`, `is_active`, `last_login`, `created_at`, `updated_at`) VALUES
(1, 'admin', '1234', 'مدير النظام', NULL, NULL, 'admin', 1, '2025-05-22 03:42:49', '2025-05-21 20:32:45', '2025-05-22 00:42:49'),
(3, 'm', '$2y$10$9inSwWnWFMIvOLwjMBoQ3O/nihrk1r6MlP2ksZ8cgsH9ro3ks11xO', 'محمد احمد', 'mohamed@gmail.com', '734587456', 'employee', 1, '2025-05-22 01:06:19', '2025-05-21 21:41:19', '2025-05-21 22:06:19');

-- --------------------------------------------------------

--
-- Table structure for table `user_permissions`
--

CREATE TABLE `user_permissions` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `permission_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `user_permissions`
--

INSERT INTO `user_permissions` (`id`, `user_id`, `permission_id`, `created_at`) VALUES
(16, 1, 1, '2025-05-21 21:39:57'),
(17, 1, 2, '2025-05-21 21:39:57'),
(18, 1, 3, '2025-05-21 21:39:57'),
(19, 1, 4, '2025-05-21 21:39:57'),
(20, 1, 5, '2025-05-21 21:39:57'),
(21, 1, 6, '2025-05-21 21:39:57'),
(22, 1, 7, '2025-05-21 21:39:57'),
(23, 1, 8, '2025-05-21 21:39:57'),
(24, 1, 9, '2025-05-21 21:39:57'),
(29, 3, 3, '2025-05-21 22:12:19'),
(30, 3, 4, '2025-05-21 22:12:19'),
(31, 3, 5, '2025-05-21 22:12:19'),
(32, 3, 6, '2025-05-21 22:12:19'),
(33, 3, 7, '2025-05-21 22:12:19'),
(34, 3, 8, '2025-05-21 22:12:19'),
(35, 3, 9, '2025-05-21 22:12:19');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `bookings`
--
ALTER TABLE `bookings`
  ADD PRIMARY KEY (`booking_id`),
  ADD KEY `guest_id` (`guest_id`),
  ADD KEY `idx_booking_status` (`status`),
  ADD KEY `fk_room` (`room_number`);

--
-- Indexes for table `booking_notes`
--
ALTER TABLE `booking_notes`
  ADD PRIMARY KEY (`note_id`),
  ADD KEY `booking_id` (`booking_id`);

--
-- Indexes for table `cash_register`
--
ALTER TABLE `cash_register`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `date` (`date`);

--
-- Indexes for table `cash_transactions`
--
ALTER TABLE `cash_transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `register_id` (`register_id`);

--
-- Indexes for table `employees`
--
ALTER TABLE `employees`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `expenses`
--
ALTER TABLE `expenses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `cash_transaction_id` (`cash_transaction_id`);

--
-- Indexes for table `expense_logs`
--
ALTER TABLE `expense_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `expense_id` (`expense_id`);

--
-- Indexes for table `invoices`
--
ALTER TABLE `invoices`
  ADD PRIMARY KEY (`id`),
  ADD KEY `booking_id` (`booking_id`);

--
-- Indexes for table `payment`
--
ALTER TABLE `payment`
  ADD PRIMARY KEY (`payment_id`),
  ADD KEY `booking_id` (`booking_id`),
  ADD KEY `cash_transaction_id` (`cash_transaction_id`);

--
-- Indexes for table `permissions`
--
ALTER TABLE `permissions`
  ADD PRIMARY KEY (`permission_id`),
  ADD UNIQUE KEY `permission_code` (`permission_code`);

--
-- Indexes for table `rooms`
--
ALTER TABLE `rooms`
  ADD PRIMARY KEY (`room_number`);

--
-- Indexes for table `salary_withdrawals`
--
ALTER TABLE `salary_withdrawals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `employee_id` (`employee_id`);

--
-- Indexes for table `suppliers`
--
ALTER TABLE `suppliers`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `username` (`username`);

--
-- Indexes for table `user_permissions`
--
ALTER TABLE `user_permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `user_permission` (`user_id`,`permission_id`),
  ADD KEY `permission_id` (`permission_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `bookings`
--
ALTER TABLE `bookings`
  MODIFY `booking_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `booking_notes`
--
ALTER TABLE `booking_notes`
  MODIFY `note_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `cash_register`
--
ALTER TABLE `cash_register`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `cash_transactions`
--
ALTER TABLE `cash_transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `employees`
--
ALTER TABLE `employees`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `expenses`
--
ALTER TABLE `expenses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `expense_logs`
--
ALTER TABLE `expense_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `invoices`
--
ALTER TABLE `invoices`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `payment`
--
ALTER TABLE `payment`
  MODIFY `payment_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT for table `permissions`
--
ALTER TABLE `permissions`
  MODIFY `permission_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `salary_withdrawals`
--
ALTER TABLE `salary_withdrawals`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `suppliers`
--
ALTER TABLE `suppliers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `user_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `user_permissions`
--
ALTER TABLE `user_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=36;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `bookings`
--
ALTER TABLE `bookings`
  ADD CONSTRAINT `bookings_ibfk_2` FOREIGN KEY (`room_number`) REFERENCES `rooms` (`room_number`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_room` FOREIGN KEY (`room_number`) REFERENCES `rooms` (`room_number`) ON UPDATE CASCADE;

--
-- Constraints for table `booking_notes`
--
ALTER TABLE `booking_notes`
  ADD CONSTRAINT `booking_notes_ibfk_1` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`booking_id`) ON DELETE CASCADE;

--
-- Constraints for table `cash_transactions`
--
ALTER TABLE `cash_transactions`
  ADD CONSTRAINT `cash_transactions_ibfk_1` FOREIGN KEY (`register_id`) REFERENCES `cash_register` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `expense_logs`
--
ALTER TABLE `expense_logs`
  ADD CONSTRAINT `expense_logs_ibfk_1` FOREIGN KEY (`expense_id`) REFERENCES `expenses` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `user_permissions`
--
ALTER TABLE `user_permissions`
  ADD CONSTRAINT `user_permissions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE,
  ADD CONSTRAINT `user_permissions_ibfk_2` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`permission_id`) ON DELETE CASCADE;

DELIMITER $$
--
-- Events
--
CREATE DEFINER=`root`@`localhost` EVENT `update_nights_calculation` ON SCHEDULE EVERY 1 DAY STARTS '2025-05-11 02:21:50' ON COMPLETION NOT PRESERVE ENABLE DO BEGIN
    UPDATE bookings
    SET calculated_nights = DATEDIFF(CURRENT_DATE(), DATE(checkin_date)) + 
                          (CASE WHEN TIME(CURRENT_TIME()) > '13:00:00' THEN 1 ELSE 0 END),
        last_calculation = CURRENT_TIMESTAMP
    WHERE status = 'محجوزة';
END$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
