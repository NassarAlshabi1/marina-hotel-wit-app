# Ditto Database Schema Setup Queries
# نظام إدارة فندق مارينا - إعداد قاعدة البيانات

## 1. إنشاء جدول الغرف (Rooms)
```dql
-- إنشاء جدول الغرف
CREATE TABLE IF NOT EXISTS rooms (
  _id TEXT PRIMARY KEY,
  room_number TEXT UNIQUE NOT NULL,
  room_type TEXT NOT NULL DEFAULT 'standard',
  floor INTEGER,
  price_per_night REAL NOT NULL,
  capacity INTEGER DEFAULT 2,
  status TEXT DEFAULT 'available',
  amenities TEXT,
  description TEXT,
  created_at TEXT,
  updated_at TEXT,
  updated_by TEXT
);

-- إنشاء مؤشرات للغرف
CREATE INDEX IF NOT EXISTS idx_rooms_number ON rooms(room_number);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status);
CREATE INDEX IF NOT EXISTS idx_rooms_type ON rooms(room_type);
```

## 2. إنشاء جدول الحجوزات (Bookings)
```dql
-- إنشاء جدول الحجوزات
CREATE TABLE IF NOT EXISTS bookings (
  _id TEXT PRIMARY KEY,
  guest_name TEXT NOT NULL,
  guest_phone TEXT,
  guest_email TEXT,
  guest_id_number TEXT,
  room_number TEXT NOT NULL,
  checkin_date TEXT NOT NULL,
  checkout_date TEXT,
  actual_checkin TEXT,
  actual_checkout TEXT,
  nights INTEGER,
  total_amount REAL NOT NULL,
  paid_amount REAL DEFAULT 0,
  remaining_amount REAL DEFAULT 0,
  status TEXT DEFAULT 'محجوزة',
  payment_status TEXT DEFAULT 'pending',
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  created_by TEXT,
  updated_by TEXT,
  device_id TEXT,
  FOREIGN KEY (room_number) REFERENCES rooms(room_number)
);

-- إنشاء مؤشرات للحجوزات
CREATE INDEX IF NOT EXISTS idx_bookings_room ON bookings(room_number);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_dates ON bookings(checkin_date, checkout_date);
CREATE INDEX IF NOT EXISTS idx_bookings_guest ON bookings(guest_name);
CREATE INDEX IF NOT EXISTS idx_bookings_created ON bookings(created_at);
```

## 3. إنشاء جدول المدفوعات (Payments)
```dql
-- إنشاء جدول المدفوعات
CREATE TABLE IF NOT EXISTS payments (
  _id TEXT PRIMARY KEY,
  booking_id TEXT NOT NULL,
  amount REAL NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'cash',
  payment_type TEXT DEFAULT 'booking_payment',
  reference_number TEXT,
  notes TEXT,
  payment_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  created_by TEXT,
  device_id TEXT,
  FOREIGN KEY (booking_id) REFERENCES bookings(_id)
);

-- إنشاء مؤشرات للمدفوعات
CREATE INDEX IF NOT EXISTS idx_payments_booking ON payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_payments_method ON payments(payment_method);
CREATE INDEX IF NOT EXISTS idx_payments_created ON payments(created_at);
```

## 4. إنشاء جدول الموظفين (Employees)
```dql
-- إنشاء جدول الموظفين
CREATE TABLE IF NOT EXISTS employees (
  _id TEXT PRIMARY KEY,
  employee_id TEXT UNIQUE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  position TEXT,
  department TEXT,
  salary REAL,
  hire_date TEXT,
  status TEXT DEFAULT 'active',
  permissions TEXT, -- JSON string للصلاحيات
  created_at TEXT NOT NULL,
  updated_at TEXT,
  created_by TEXT,
  updated_by TEXT
);

-- إنشاء مؤشرات للموظفين
CREATE INDEX IF NOT EXISTS idx_employees_id ON employees(employee_id);
CREATE INDEX IF NOT EXISTS idx_employees_name ON employees(name);
CREATE INDEX IF NOT EXISTS idx_employees_status ON employees(status);
CREATE INDEX IF NOT EXISTS idx_employees_position ON employees(position);
```

## 5. إنشاء جدول المصروفات (Expenses)
```dql
-- إنشاء جدول المصروفات
CREATE TABLE IF NOT EXISTS expenses (
  _id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT,
  amount REAL NOT NULL,
  expense_date TEXT NOT NULL,
  receipt_number TEXT,
  vendor TEXT,
  payment_method TEXT DEFAULT 'cash',
  status TEXT DEFAULT 'approved',
  created_at TEXT NOT NULL,
  updated_at TEXT,
  created_by TEXT,
  approved_by TEXT,
  device_id TEXT
);

-- إنشاء مؤشرات للمصروفات
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category);
CREATE INDEX IF NOT EXISTS idx_expenses_status ON expenses(status);
CREATE INDEX IF NOT EXISTS idx_expenses_created ON expenses(created_at);
```

## 6. إنشاء جدول الملاحظات (Notes)
```dql
-- إنشاء جدول الملاحظات
CREATE TABLE IF NOT EXISTS notes (
  _id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  type TEXT DEFAULT 'general',
  priority TEXT DEFAULT 'normal',
  status TEXT DEFAULT 'active',
  target_date TEXT,
  assigned_to TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  created_by TEXT,
  completed_at TEXT,
  completed_by TEXT
);

-- إنشاء مؤشرات للملاحظات
CREATE INDEX IF NOT EXISTS idx_notes_status ON notes(status);
CREATE INDEX IF NOT EXISTS idx_notes_type ON notes(type);
CREATE INDEX IF NOT EXISTS idx_notes_priority ON notes(priority);
CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(created_at);
CREATE INDEX IF NOT EXISTS idx_notes_target ON notes(target_date);
```

## 7. إنشاء جدول المستخدمين (Users) - للمصادقة
```dql
-- إنشاء جدول المستخدمين
CREATE TABLE IF NOT EXISTS users (
  _id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  user_type TEXT DEFAULT 'employee',
  permissions TEXT, -- JSON string للصلاحيات
  last_login TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT,
  created_by TEXT
);

-- إنشاء مؤشرات للمستخدمين
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_type ON users(user_type);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
```

## 8. إنشاء جدول إعدادات النظام (Settings)
```dql
-- إنشاء جدول الإعدادات
CREATE TABLE IF NOT EXISTS settings (
  _id TEXT PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value TEXT,
  type TEXT DEFAULT 'string',
  category TEXT DEFAULT 'general',
  description TEXT,
  updated_at TEXT,
  updated_by TEXT
);

-- إنشاء مؤشرات للإعدادات
CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);
CREATE INDEX IF NOT EXISTS idx_settings_category ON settings(category);
```

## 9. إدراج البيانات الأساسية (Seed Data)

### إدراج غرف نموذجية
```dql
-- إدراج غرف الفندق
INSERT INTO rooms DOCUMENTS [
  {
    "_id": "room_101",
    "room_number": "101",
    "room_type": "single",
    "floor": 1,
    "price_per_night": 150.0,
    "capacity": 1,
    "status": "available",
    "amenities": "مكيف، تلفزيون، إنترنت مجاني",
    "description": "غرفة فردية مريحة",
    "created_at": "2025-01-01T00:00:00Z"
  },
  {
    "_id": "room_102",
    "room_number": "102",
    "room_type": "double",
    "floor": 1,
    "price_per_night": 200.0,
    "capacity": 2,
    "status": "available",
    "amenities": "مكيف، تلفزيون، إنترنت مجاني، ثلاجة صغيرة",
    "description": "غرفة مزدوجة واسعة",
    "created_at": "2025-01-01T00:00:00Z"
  },
  {
    "_id": "room_201",
    "room_number": "201",
    "room_type": "suite",
    "floor": 2,
    "price_per_night": 350.0,
    "capacity": 4,
    "status": "available",
    "amenities": "جاكوزي، شرفة، غرفة معيشة منفصلة",
    "description": "جناح فاخر مع إطلالة على البحر",
    "created_at": "2025-01-01T00:00:00Z"
  }
];
```

### إدراج مستخدم إداري افتراضي
```dql
-- إدراج مستخدم admin افتراضي
INSERT INTO users DOCUMENTS [{
  "_id": "user_admin_001",
  "username": "admin",
  "email": "admin@marina-hotel.com",
  "password_hash": "hashed_password_here",
  "full_name": "مدير النظام",
  "user_type": "admin",
  "permissions": "[\"all\"]",
  "status": "active",
  "created_at": "2025-01-01T00:00:00Z"
}];
```

### إدراج إعدادات النظام الأساسية
```dql
-- إدراج إعدادات النظام الأساسية
INSERT INTO settings DOCUMENTS [
  {
    "_id": "setting_hotel_name",
    "key": "hotel_name",
    "value": "فندق مارينا",
    "type": "string",
    "category": "general",
    "description": "اسم الفندق"
  },
  {
    "_id": "setting_currency",
    "key": "currency",
    "value": "SAR",
    "type": "string", 
    "category": "financial",
    "description": "العملة الأساسية"
  },
  {
    "_id": "setting_tax_rate",
    "key": "tax_rate",
    "value": "15",
    "type": "number",
    "category": "financial", 
    "description": "نسبة الضريبة (%)"
  },
  {
    "_id": "setting_check_in_time",
    "key": "check_in_time", 
    "value": "14:00",
    "type": "time",
    "category": "operations",
    "description": "وقت تسجيل الدخول"
  },
  {
    "_id": "setting_check_out_time",
    "key": "check_out_time",
    "value": "12:00", 
    "type": "time",
    "category": "operations",
    "description": "وقت تسجيل الخروج"
  }
];
```

## 10. Views مفيدة للاستعلامات

### عرض الحجوزات النشطة
```dql
-- إنشاء view للحجوزات النشطة
CREATE VIEW IF NOT EXISTS active_bookings AS
SELECT 
  b._id,
  b.guest_name,
  b.room_number,
  r.room_type,
  b.checkin_date,
  b.checkout_date,
  b.total_amount,
  b.paid_amount,
  b.status,
  b.created_at
FROM bookings b
JOIN rooms r ON b.room_number = r.room_number
WHERE b.status IN ('محجوزة', 'تم الدخول');
```

### عرض حالة الغرف
```dql
-- إنشاء view لحالة الغرف
CREATE VIEW IF NOT EXISTS rooms_status AS  
SELECT
  r.room_number,
  r.room_type,
  r.price_per_night,
  r.status as room_status,
  CASE 
    WHEN b.status = 'تم الدخول' THEN 'occupied'
    WHEN b.status = 'محجوزة' THEN 'reserved' 
    ELSE 'available'
  END as booking_status,
  b.guest_name,
  b.checkout_date
FROM rooms r
LEFT JOIN bookings b ON r.room_number = b.room_number 
  AND b.status IN ('محجوزة', 'تم الدخول');
```

## تشغيل الـ Queries في التطبيق

### في ditto_cloud_sync_service.dart
```dart
/// تهيئة قاعدة البيانات وإنشاء الجداول
Future<void> initializeDatabase() async {
  if (!_isInitialized || _ditto == null) {
    throw Exception('Ditto غير مهيء');
  }

  try {
    // تعطيل DQL strict mode أولاً
    await _ditto!.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = false");
    
    // إنشاء الجداول
    await _createTables();
    
    // إدراج البيانات الأساسية إذا كانت فارغة
    await _seedInitialData();
    
    debugPrint('✅ تم تهيئة قاعدة البيانات بنجاح');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة قاعدة البيانات: $e');
    rethrow;
  }
}

Future<void> _createTables() async {
  final tables = [
    // جدول الغرف
    '''CREATE TABLE IF NOT EXISTS rooms (
      _id TEXT PRIMARY KEY,
      room_number TEXT UNIQUE NOT NULL,
      room_type TEXT NOT NULL DEFAULT 'standard',
      floor INTEGER,
      price_per_night REAL NOT NULL,
      capacity INTEGER DEFAULT 2,
      status TEXT DEFAULT 'available',
      amenities TEXT,
      description TEXT,
      created_at TEXT,
      updated_at TEXT,
      updated_by TEXT
    )''',
    
    // جدول الحجوزات
    '''CREATE TABLE IF NOT EXISTS bookings (
      _id TEXT PRIMARY KEY,
      guest_name TEXT NOT NULL,
      guest_phone TEXT,
      room_number TEXT NOT NULL,
      checkin_date TEXT NOT NULL,
      checkout_date TEXT,
      total_amount REAL NOT NULL,
      paid_amount REAL DEFAULT 0,
      status TEXT DEFAULT 'محجوزة',
      notes TEXT,
      created_at TEXT NOT NULL,
      created_by TEXT,
      device_id TEXT
    )''',
    
    // المزيد من الجداول...
  ];
  
  for (final tableQuery in tables) {
    await _ditto!.store.execute(tableQuery);
  }
}
```