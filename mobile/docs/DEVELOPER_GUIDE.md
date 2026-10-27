# 📘 دليل المطور - البنية الجديدة

## 🎯 نظرة سريعة

تم تحسين شاشات الإعدادات بالكامل! الكود الآن:
- ✅ منظم في مجلدات واضحة
- ✅ بدون تكرار
- ✅ سهل الصيانة
- ✅ قابل للاختبار

---

## 📁 هيكل المجلدات

```
lib/
├── core/                          👈 البنية التحتية المشتركة
│   ├── utils/                     
│   │   ├── date_time_formatter.dart
│   │   └── file_size_formatter.dart
│   ├── constants/
│   │   └── ui_constants.dart
│   ├── widgets/
│   │   └── common_widgets.dart
│   └── core.dart                  👈 استورد هذا الملف فقط!
│
└── screens/settings/
    ├── backup/                    👈 كل ما يتعلق بالنسخ الاحتياطي
    ├── sync/                      👈 كل ما يتعلق بالمزامنة
    ├── appwrite/                  👈 كل ما يتعلق بـ Appwrite
    └── logs/                      👈 كل السجلات
```

---

## 🚀 كيفية الاستخدام

### 1. استيراد Core

**❌ لا تفعل:**
```dart
import '../../core/utils/date_time_formatter.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/constants/ui_constants.dart';
```

**✅ افعل:**
```dart
import '../../core/core.dart';  // استيراد واحد فقط!
```

---

### 2. تنسيق التاريخ والوقت

**❌ القديم:**
```dart
String _formatDateTime(String? isoString) {
  if (isoString == null || isoString.isEmpty) return 'لا يوجد';
  try {
    final date = DateTime.parse(isoString);
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  } catch (e) {
    return 'تاريخ غير صالح';
  }
}

// استخدام
Text(_formatDateTime(lastSync))
```

**✅ الجديد:**
```dart
import '../../core/core.dart';

// استخدام مباشر
Text(DateTimeFormatter.formatDateTime(lastSync))
```

**الخيارات المتاحة:**
```dart
DateTimeFormatter.formatDateTime(iso);      // 2024-01-29 18:30
DateTimeFormatter.formatDate(iso);          // 2024-01-29
DateTimeFormatter.formatTime(iso);          // 18:30
DateTimeFormatter.formatArabicDate(iso);    // 29 يناير 2024
DateTimeFormatter.getRelativeTime(iso);     // منذ 5 دقائق
DateTimeFormatter.isToday(iso);             // true/false
```

---

### 3. تنسيق أحجام الملفات

**❌ القديم:**
```dart
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
```

**✅ الجديد:**
```dart
FileSizeFormatter.formatBytes(bytes)          // 15.5 ميجابايت
FileSizeFormatter.formatBytesShort(bytes)     // 15.5M
FileSizeFormatter.formatSpeed(bytesPerSec)    // 1.2 ميجابايت/ث
FileSizeFormatter.formatProgress(current, total) // 50 MB / 100 MB (50%)
```

---

### 4. الألوان والأيقونات

**❌ القديم:**
```dart
Color _getColorForStatus(String status) {
  switch (status) {
    case 'نشط': return Colors.green;
    case 'غير نشط': return Colors.red;
    case 'معلق': return Colors.orange;
    default: return Colors.grey;
  }
}

IconData _getIconForStatus(String status) {
  // ... 20+ سطر
}
```

**✅ الجديد:**
```dart
UIConstants.getColorForStatus('نشط')        // Colors.green
UIConstants.getIconForStatus('نشط')         // Icons.check_circle
UIConstants.getColorForLogLevel(LogLevel.error) // Colors.red
```

**ألوان ميزات محددة:**
```dart
UIConstants.employeeColor    // Purple
UIConstants.guestColor       // Teal
UIConstants.syncColor        // Blue
UIConstants.backupColor      // Green
```

---

### 5. Widgets الجاهزة

#### أ. InfoRow - عرض معلومة

**❌ القديم (~20 سطر):**
```dart
Widget _buildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
```

**✅ الجديد (سطر واحد):**
```dart
InfoRow(
  label: 'آخر مزامنة',
  value: DateTimeFormatter.formatDateTime(lastSync),
  icon: Icons.sync,
  iconColor: Colors.blue,
)
```

#### ب. StatCard - بطاقة إحصائية

**✅ الجديد:**
```dart
StatCard(
  title: 'الموظفون',
  value: '${employees.length}',
  icon: Icons.people,
  color: UIConstants.employeeColor,
  onTap: () => navigateToEmployees(),
  subtitle: 'نشط: ${activeCount}',
)
```

#### ج. StatusBadge - شارة الحالة

**✅ الجديد:**
```dart
StatusBadge(status: 'نشط')     // لون وأيقونة تلقائياً
StatusBadge(status: 'معلق')    // برتقالي تلقائياً
StatusBadge(status: 'خطأ')     // أحمر تلقائياً
```

#### د. SectionHeader - عنوان قسم

**✅ الجديد:**
```dart
SectionHeader(
  title: 'الموظفون',
  icon: Icons.people,
  action: IconButton(
    icon: Icon(Icons.add),
    onPressed: () {},
  ),
)
```

#### هـ. Empty/Loading/Error States

**✅ الجديد:**
```dart
// Empty
EmptyStateWidget(
  message: 'لا توجد بيانات',
  icon: Icons.inbox,
  actionLabel: 'إضافة',
  onAction: () {},
)

// Loading
LoadingStateWidget(message: 'جاري التحميل...')

// Error
ErrorStateWidget(
  message: 'حدث خطأ',
  onRetry: () => _retry(),
)
```

---

## 🔄 Migration Guide - دليل الترحيل

### مثال كامل: تحديث شاشة موجودة

**❌ قبل (القديم):**
```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MySettingsScreen extends StatelessWidget {
  // دوال مكررة
  String _formatDateTime(String? iso) { ... }
  String _formatBytes(int bytes) { ... }
  Color _getColorForStatus(String status) { ... }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(width: 16),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoRow('آخر مزامنة', _formatDateTime(lastSync)),
                  _buildInfoRow('حجم البيانات', _formatBytes(dataSize)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getColorForStatus(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(status),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

**✅ بعد (الجديد):**
```dart
import 'package:flutter/material.dart';
import '../../components/app_scaffold.dart';
import '../../core/core.dart';  // 👈 استيراد واحد فقط!

class MySettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'الإعدادات',
      body: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UIConstants.radiusLG),
            ),
            child: Padding(
              padding: const EdgeInsets.all(UIConstants.spacingMD),
              child: Column(
                children: [
                  InfoRow(
                    label: 'آخر مزامنة',
                    value: DateTimeFormatter.formatDateTime(lastSync),
                    icon: Icons.sync,
                  ),
                  InfoRow(
                    label: 'حجم البيانات',
                    value: FileSizeFormatter.formatBytes(dataSize),
                    icon: Icons.storage,
                  ),
                  StatusBadge(status: status),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

**الفرق:**
- ❌ القديم: ~80 سطر
- ✅ الجديد: ~35 سطر
- 🎉 توفير: **56%**

---

## 🎨 أمثلة عملية

### مثال 1: شاشة إحصائيات

```dart
import '../../core/core.dart';

Widget buildStatsSection() {
  return GridView.count(
    crossAxisCount: 2,
    children: [
      StatCard(
        title: 'الموظفون',
        value: '42',
        icon: UIConstants.employeeIcon,
        color: UIConstants.employeeColor,
      ),
      StatCard(
        title: 'الضيوف',
        value: '128',
        icon: UIConstants.guestIcon,
        color: UIConstants.guestColor,
      ),
      StatCard(
        title: 'الغرف',
        value: '50',
        icon: UIConstants.roomIcon,
        color: UIConstants.roomColor,
      ),
      StatCard(
        title: 'الحجوزات',
        value: '89',
        icon: Icons.event,
        color: Colors.purple,
      ),
    ],
  );
}
```

### مثال 2: قائمة بالحالات

```dart
Widget buildEmployeesList(List<Employee> employees) {
  return ListView.builder(
    itemCount: employees.length,
    itemBuilder: (context, index) {
      final employee = employees[index];
      return Card(
        child: ListTile(
          title: Text(employee.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(employee.position),
              Text(DateTimeFormatter.formatDate(employee.hireDate)),
            ],
          ),
          trailing: StatusBadge(status: employee.status),
        ),
      );
    },
  );
}
```

### مثال 3: معلومات مفصلة

```dart
Widget buildDetailsCard() {
  return Card(
    child: Padding(
      padding: EdgeInsets.all(UIConstants.spacingMD),
      child: Column(
        children: [
          SectionHeader(
            title: 'معلومات الموظف',
            icon: Icons.person,
          ),
          InfoRow(
            label: 'الاسم',
            value: employee.name,
            icon: Icons.badge,
          ),
          InfoRow(
            label: 'المنصب',
            value: employee.position,
            icon: Icons.work,
          ),
          InfoRow(
            label: 'الراتب',
            value: formatCurrency(employee.salary),
            icon: Icons.attach_money,
          ),
          InfoRow(
            label: 'تاريخ التعيين',
            value: DateTimeFormatter.formatArabicDate(employee.hireDate),
            icon: Icons.calendar_today,
          ),
        ],
      ),
    ),
  );
}
```

---

## 📋 Checklist للملفات الجديدة

عند إنشاء ملف settings جديد:

- [ ] استورد `../../core/core.dart`
- [ ] استخدم `AppScaffold` بدلاً من `Scaffold`
- [ ] استخدم `UIConstants` للمسافات والألوان
- [ ] استخدم `DateTimeFormatter` للتواريخ
- [ ] استخدم `FileSizeFormatter` للأحجام
- [ ] استخدم Widgets الجاهزة (`InfoRow`, `StatCard`, إلخ)
- [ ] لا تكرر الكود - ابحث في core/ أولاً
- [ ] اجعل الملف أقل من 400 سطر
- [ ] قسّم إلى tabs إذا تجاوز 500 سطر

---

## 🎯 Best Practices

### 1. التسمية
```dart
// ✅ جيد
unified_sync_settings_screen.dart
backup_overview_tab.dart
date_time_formatter.dart

// ❌ سيء
settings1.dart
tab1.dart
utils.dart
```

### 2. التنظيم
```dart
// ✅ منظم
lib/screens/settings/backup/tabs/...
lib/screens/settings/sync/...

// ❌ غير منظم
lib/screens/settings/... (كل شيء مختلط)
```

### 3. حجم الملفات
```dart
// ✅ مناسب
200-400 سطر لملف الشاشة الرئيسي
150-250 سطر لكل tab

// ❌ كبير جداً
> 500 سطر → قسّمه!
```

### 4. إعادة الاستخدام
```dart
// ✅ جيد - استخدم widgets موجودة
InfoRow(...)
StatCard(...)
StatusBadge(...)

// ❌ سيء - إنشاء widgets مكررة
Widget _buildMyInfoRow(...) { ... }
Widget _buildMyCard(...) { ... }
```

---

## 🔧 الملفات القديمة

### ما زالت موجودة (للمرجع):
- `comprehensive_backup_screen.dart` (1890 سطر)
- `appwrite_settings_screen.dart` (1361 سطر)

### استخدم النسخ الجديدة:
- ✅ `backup/comprehensive_backup_screen_v2.dart`
- ✅ `appwrite/appwrite_settings_screen_v2.dart`

**ملاحظة:** يمكن حذف الملفات القديمة بعد التأكد من عمل النسخ الجديدة.

---

## 🧪 الاختبار

### اختبار الـ Utilities:
```dart
// test/core/utils/date_time_formatter_test.dart
void main() {
  group('DateTimeFormatter', () {
    test('formatDateTime returns correct format', () {
      final result = DateTimeFormatter.formatDateTime('2024-01-29T18:30:00');
      expect(result, '2024-01-29 18:30');
    });
  });
}
```

### اختبار الـ Widgets:
```dart
// test/core/widgets/common_widgets_test.dart
void main() {
  testWidgets('InfoRow displays label and value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoRow(
            label: 'Test',
            value: 'Value',
          ),
        ),
      ),
    );
    
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
  });
}
```

---

## 🎉 الخلاصة

**الكود الآن:**
- ✅ منظم ونظيف
- ✅ سهل الفهم
- ✅ قابل للصيانة
- ✅ قابل للتوسع
- ✅ احترافي 100%

**استمتع بالتطوير! 🚀**
