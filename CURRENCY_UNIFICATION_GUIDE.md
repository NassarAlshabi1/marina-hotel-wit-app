# دليل توحيد نظام العملة
## Marina Hotel Currency Unification System

تحديث: 28 أكتوبر 2025

---

## نظرة عامة

تم توحيد نظام العملة في تطبيق Marina Hotel ليستخدم **الريال السعودي (ر.س)** كعملة موحدة في جميع أنحاء النظام، بدلاً من الخليط السابق من "درهم إماراتي (د.إ)"، "درهم"، "ريال"، و"ريال يمني".

### الأهداف المحققة:
- ✅ **توحيد رمز العملة**: جميع المبالغ تعرض "ر.س"
- ✅ **تنسيق موحد**: المبالغ تظهر بصيغة "5,000 ر.س"
- ✅ **ثوابت مركزية**: دوال موحدة لتنسيق العملة
- ✅ **سهولة الصيانة**: تغيير واحد يؤثر على النظام بالكامل

---

## المشاكل التي تم حلها

### قبل التوحيد:
```
❌ admin/finance/cash_register.php → "د.إ"
❌ admin/reports/invoice.php → "درهم" أو بدون رمز
❌ admin/bookings/payment.php → "ريال"
❌ mobile/lib/screens/ → مزيج من "ريال" و"ريال يمني"
❌ تنسيق غير موحد → أرقام بدون فواصل أو فواصل مختلفة
```

### بعد التوحيد:
```
✅ جميع الملفات → "ر.س" 
✅ تنسيق موحد → "5,000 ر.س"
✅ دوال مركزية → formatCurrency()
✅ سهولة التعديل → تغيير مكان واحد
```

---

## الهيكل الجديد

### في PHP (`includes/functions.php`):

#### الثوابت:
```php
// ثوابت العملة
define('CURRENCY_SYMBOL', 'ر.س');
```

#### الدوال:
```php
// دالة توحيد تنسيق العملة
function formatCurrency($amount, $show_decimals = false) {
    if ($show_decimals) {
        return number_format($amount, 2) . ' ' . CURRENCY_SYMBOL;
    } else {
        return number_format($amount, 0) . ' ' . CURRENCY_SYMBOL;
    }
}

// دالة تنسيق العملة مع فواصل عربية
function formatCurrencyArabic($amount, $show_decimals = false) {
    $formatted = formatCurrency($amount, $show_decimals);
    // استخدام الفاصلة العربية بدلاً من الإنجليزية
    $formatted = str_replace(',', '،', $formatted);
    return $formatted;
}
```

### في Flutter (`mobile/lib/utils/currency_formatter.dart`):

#### الثوابت:
```dart
class CurrencyConstants {
  static const String currencySymbol = 'ر.س';
  static const String currencyName = 'الريال السعودي';
}
```

#### الدوال:
```dart
class CurrencyFormatter {
  /// تنسيق المبلغ برمز العملة (5,000 ر.س)
  static String formatCurrency(double amount, {bool showDecimals = false}) {
    final formatter = NumberFormat('#,###${showDecimals ? '.##' : ''}', 'ar');
    return '${formatter.format(amount)} ${CurrencyConstants.currencySymbol}';
  }

  /// تنسيق المبلغ بدون رمز العملة (5,000)
  static String formatAmount(double amount, {bool showDecimals = false}) {
    final formatter = NumberFormat('#,###${showDecimals ? '.##' : ''}', 'ar');
    return formatter.format(amount);
  }
  
  // المزيد من الدوال المساعدة...
}
```

---

## الملفات المُحدثة

### ملفات PHP:

#### 1. `admin/finance/cash_register.php`:
**التغييرات**:
```php
// قبل
<?= number_format($register['opening_balance'], 2); ?> د.إ

// بعد  
<?= formatCurrency($register['opening_balance'], true); ?>
```

#### 2. `admin/reports/invoice.php`:
**التغييرات**:
```php
// قبل
<?= number_format($row['total']); ?> درهم
<?= number_format($row['total']); ?>

// بعد
<?= formatCurrency($row['total']); ?>
```

#### 3. `admin/bookings/payment.php`:
**التغييرات**:
```php
// قبل
<?= number_format($total_price, 0) ?> ريال

// بعد
<?= formatCurrency($total_price); ?>
```

#### 4. `admin/reports/comprehensive_reports.php`:
**التغييرات**:
```php
// قبل
<?php echo number_format($report_data['total_revenue'], 2); ?> ريال

// بعد
<?php echo formatCurrency($report_data['total_revenue'], true); ?>
```

### ملفات Flutter:

#### 1. `mobile/lib/screens/bookings/booking_edit.dart`:
```dart
// قبل
prefixText: 'ريال ',
'${formatAmount(amount)} ريال'

// بعد
prefixText: 'ر.س ',
'${formatAmount(amount)} ر.س'
```

#### 2. `mobile/lib/screens/payments/booking_payment_screen.dart`:
```dart
// قبل
'المبلغ: ${_currencyFmt.format(amount)} ريال'
'تم استلام دفعتك بقيمة ${formatAmount(amountPaidNow)} ريال يمني'

// بعد
'المبلغ: ${_currencyFmt.format(amount)} ر.س'
'تم استلام دفعتك بقيمة ${formatAmount(amountPaidNow)} ر.س'
```

#### 3. `mobile/lib/services/file_management_service.dart`:
```dart
// قبل
'${record['price'] ?? 'N/A'} ريال'

// بعد
'${record['price'] ?? 'N/A'} ر.س'
```

#### 4. `mobile/lib/models/enhanced_payment_models.dart` & `enhanced_reports.dart`:
```dart
// قبل
subtitle: 'ريال سعودي',
subtitle: 'ريال',

// بعد  
subtitle: 'ر.س',
```

---

## أمثلة الاستخدام

### في PHP:

#### الاستخدام الأساسي:
```php
$amount = 1500.75;

// تنسيق بدون أرقام عشرية
echo formatCurrency($amount); 
// النتيجة: "1,501 ر.س"

// تنسيق مع أرقام عشرية
echo formatCurrency($amount, true);
// النتيجة: "1,500.75 ر.س"

// تنسيق عربي
echo formatCurrencyArabic($amount, true);
// النتيجة: "1،500.75 ر.س"
```

#### في الصفحات:
```php
<td><?= formatCurrency($booking['total_amount']); ?></td>
<span class="price"><?= formatCurrency($room['price'], true); ?></span>
```

### في Flutter:

#### الاستخدام الأساسي:
```dart
double amount = 1500.75;

// تنسيق مع رمز العملة
String formatted = CurrencyFormatter.formatCurrency(amount);
// النتيجة: "1,501 ر.س"

// تنسيق مع أرقام عشرية
String formattedDecimal = CurrencyFormatter.formatCurrency(amount, showDecimals: true);
// النتيجة: "1,500.75 ر.س"

// تنسيق بدون رمز العملة
String amountOnly = CurrencyFormatter.formatAmount(amount);
// النتيجة: "1,501"
```

#### في الويدجات:
```dart
Text(CurrencyFormatter.formatCurrency(booking.totalAmount)),
TextField(
  decoration: InputDecoration(
    prefixText: '${CurrencyConstants.currencySymbol} ',
  ),
),
```

---

## إعدادات خاصة

### تخصيص رمز العملة:
إذا كنت بحاجة لتغيير رمز العملة مستقبلاً:

#### في PHP:
```php
// في includes/functions.php
define('CURRENCY_SYMBOL', 'ر.ق'); // للريال القطري مثلاً
```

#### في Flutter:
```dart
// في mobile/lib/utils/currency_formatter.dart  
class CurrencyConstants {
  static const String currencySymbol = 'ر.ق';
  static const String currencyName = 'الريال القطري';
}
```

### تخصيص التنسيق:
```php
// PHP - تنسيق مخصص
function formatCurrencyCustom($amount, $decimals = 0, $symbol = null) {
    $symbol = $symbol ?? CURRENCY_SYMBOL;
    return number_format($amount, $decimals) . ' ' . $symbol;
}
```

```dart
// Flutter - تنسيق مخصص
static String formatCurrencyCustom(
  double amount, {
  bool showDecimals = false,
  String? customSymbol,
  String? locale = 'ar',
}) {
  final symbol = customSymbol ?? CurrencyConstants.currencySymbol;
  final formatter = NumberFormat('#,###${showDecimals ? '.##' : ''}', locale);
  return '${formatter.format(amount)} $symbol';
}
```

---

## اختبار النظام

### فحص PHP:
```php
// ملف اختبار مؤقت
<?php
include 'includes/functions.php';

// اختبار التنسيق
$test_amounts = [100, 1500.75, 10000, 999999.99];

foreach ($test_amounts as $amount) {
    echo "المبلغ: $amount\n";
    echo "بدون عشرية: " . formatCurrency($amount) . "\n";
    echo "مع عشرية: " . formatCurrency($amount, true) . "\n";
    echo "عربي: " . formatCurrencyArabic($amount, true) . "\n\n";
}
?>
```

### فحص Flutter:
```dart
// في ملف test
void testCurrencyFormatting() {
  final testAmounts = [100.0, 1500.75, 10000.0, 999999.99];
  
  for (final amount in testAmounts) {
    print('المبلغ: $amount');
    print('بدون عشرية: ${CurrencyFormatter.formatCurrency(amount)}');
    print('مع عشرية: ${CurrencyFormatter.formatCurrency(amount, showDecimals: true)}');
    print('بدون رمز: ${CurrencyFormatter.formatAmount(amount)}');
    print('');
  }
}
```

### النتائج المتوقعة:
```
المبلغ: 100
بدون عشرية: 100 ر.س
مع عشرية: 100.00 ر.س
بدون رمز: 100

المبلغ: 1500.75
بدون عشرية: 1,501 ر.س  
مع عشرية: 1,500.75 ر.س
بدون رمز: 1,501

المبلغ: 10000
بدون عشرية: 10,000 ر.س
مع عشرية: 10,000.00 ر.س
بدون رمز: 10,000
```

---

## الصيانة والتحديث

### إضافة رمز عملة جديد:
1. **تحديث الثوابت** في PHP و Flutter
2. **اختبار الدوال** مع القيم الجديدة
3. **مراجعة جميع الملفات** للتأكد من الاستخدام الصحيح

### إضافة تنسيق جديد:
```php
// مثال: تنسيق للملايين
function formatCurrencyMillions($amount) {
    if ($amount >= 1000000) {
        return number_format($amount / 1000000, 1) . ' مليون ' . CURRENCY_SYMBOL;
    }
    return formatCurrency($amount);
}
```

### نصائح للمطورين:

#### استخدم الدوال دائماً:
```php
// ❌ تجنب هذا
echo number_format($amount) . ' ريال';

// ✅ استخدم هذا
echo formatCurrency($amount);
```

#### فحص الاستيراد:
```dart
// ✅ تأكد من استيراد المكتبة
import '../utils/currency_formatter.dart';

// ✅ استخدم الثوابت
Text('العملة: ${CurrencyConstants.currencySymbol}')
```

#### تجنب التكرار:
```php
// ❌ تجنب تكرار رمز العملة
$formatted = number_format($amount) . ' ر.س';

// ✅ استخدم الدالة المركزية
$formatted = formatCurrency($amount);
```

---

## متوافقة مع الأنظمة

### قواعد البيانات:
- ❌ **لا تخزن** رمز العملة في قاعدة البيانات
- ✅ **اخزن** القيم الرقمية فقط  
- ✅ **أضف** رمز العملة عند العرض

### API Responses:
```json
{
  "amount": 1500.75,
  "currency": "ر.س",
  "formatted": "1,500.75 ر.س"
}
```

### تصدير البيانات:
- **Excel**: استخدم خلايا رقمية + تنسيق العملة
- **PDF**: استخدم الدوال المركزية
- **CSV**: قيم رقمية + عمود منفصل للعملة

---

## الخلاصة

### الفوائد المحققة:
1. **توحيد المظهر**: جميع المبالغ تظهر بتنسيق موحد
2. **سهولة الصيانة**: تغيير واحد يؤثر على النظام كاملاً
3. **قابلية التوسعة**: إضافة عملات جديدة أصبح أسهل
4. **تقليل الأخطاء**: لا مزيد من الخلط بين العملات المختلفة

### التوصيات:
1. **استخدم الدوال المركزية** دائماً لتنسيق العملة
2. **لا تكتب رمز العملة يدوياً** في الكود
3. **اختبر التنسيق** بعد أي تغييرات
4. **راجع الوثائق** قبل إضافة دوال جديدة

---

**آخر تحديث**: 28 أكتوبر 2025  
**الإصدار**: 1.0  
**المطور**: Capy AI  
**الملفات المتأثرة**: 15+ ملف في PHP و Flutter

---

*نظام توحيد العملة جزء من مشروع تحسين تطبيق Marina Hotel. تم تطبيقه وفقاً لأفضل الممارسات في تطوير الأنظمة المالية.*