# 🎨 نظام PDF المحسّن - Marina Hotel

## ✨ المميزات الجديدة

تم تطوير نظام PDF احترافي وجميل ليحل محل التصاميم البسيطة السابقة. النظام الجديد يوفر:

### 🎯 تصاميم احترافية
- **رأس صفحة متدرج** مع شعار الفندق وألوان جذابة
- **بطاقات معلومات أنيقة** بحواف منحنية وظلال
- **جداول احترافية** مع تلوين متناوب للصفوف
- **إحصائيات بصرية** مع أيقونات وألوان مميزة
- **تذييل متكامل** مع معلومات الاتصال

### 🌈 ألوان وهوية بصرية موحدة
- **أزرق غامق (Primary)**: للعناوين الرئيسية
- **ذهبي (Secondary)**: للأسعار والمبالغ المهمة
- **أزرق فاتح (Accent)**: للعناصر التفاعلية
- **أخضر**: للمبالغ والأرباح
- **أحمر**: للخسائر والمصروفات

### 📱 أنواع PDF المحسّنة
1. **إيصالات الدفع** - تصميم أنيق مع QR Code
2. **الفواتير الضريبية** - متوافقة مع المعايير السعودية
3. **تقارير المدفوعات** - مع إحصائيات تفصيلية
4. **تقارير المصروفات** - مع تحليل الفئات
5. **التقرير الشامل** - ملخص كامل للفندق

## 🚀 كيفية الاستخدام

### 1. استيراد النظام الجديد

```dart
import '../utils/enhanced_pdf_utils.dart';
import '../models/enhanced_payment_models.dart';
import '../models/enhanced_reports.dart';
import '../utils/enhanced_pdf_helper.dart';
```

### 2. إنشاء إيصال دفع محسّن

```dart
// بدلاً من الطريقة القديمة
await oldReceipt.generatePDF();

// استخدم الطريقة الجديدة
await EnhancedPdfHelper.generateEnhancedReceipt(
  payment: payment,
  booking: booking,
  receivedBy: 'أحمد محمد',
);
```

### 3. إنشاء فاتورة احترافية

```dart
await EnhancedPdfHelper.generateEnhancedInvoice(
  booking: booking,
  payments: paymentsList,
  roomPrice: 250.0,
  additionalServices: [
    InvoiceItem(
      description: 'إفطار',
      quantity: 2,
      unitPrice: 35.0,
    ),
    InvoiceItem(
      description: 'خدمة غسيل',
      quantity: 1,
      unitPrice: 50.0,
    ),
  ],
);
```

### 4. إنشاء تقرير مدفوعات محسّن

```dart
await EnhancedPdfHelper.generateEnhancedPaymentsReport(
  payments: paymentsList,
  relatedBookings: bookingsList,
  fromDate: DateTime(2024, 1, 1),
  toDate: DateTime(2024, 12, 31),
  roomFilter: '101', // اختياري
  generatedBy: 'مدير النظام',
);
```

### 5. تقرير شامل للفندق

```dart
await EnhancedPdfHelper.generateHotelSummaryReport(
  fromDate: DateTime(2024, 1, 1),
  toDate: DateTime(2024, 12, 31),
  bookings: allBookings,
  payments: allPayments,
  expenses: allExpenses,
  generatedBy: 'المدير العام',
);
```

### 6. معاينة PDF قبل الطباعة

```dart
PdfPreviewHelper.openEnhancedPaymentReceiptPreview(
  context,
  payment: payment,
  booking: booking,
  receivedBy: 'المحاسب',
);
```

## 🎨 مكونات التصميم المتاحة

### 1. رأس الصفحة الاحترافي

```dart
EnhancedPdfUtils.buildProfessionalHeader(
  fonts: fonts,
  logo: logo,
  title: 'عنوان الوثيقة',
  subtitle: 'وصف إضافي',
  showGradient: true, // خلفية متدرجة
);
```

### 2. بطاقات المعلومات

```dart
EnhancedPdfUtils.buildInfoCard(
  title: '🏨 بيانات العميل',
  fonts: fonts,
  borderColor: PdfColors.accent,
  content: [
    pw.Text('محتوى البطاقة...'),
  ],
);
```

### 3. جداول احترافية

```dart
EnhancedPdfUtils.buildProfessionalTable(
  headers: ['العمود 1', 'العمود 2', 'العمود 3'],
  data: [
    ['قيمة 1', 'قيمة 2', 'قيمة 3'],
    ['قيمة 4', 'قيمة 5', 'قيمة 6'],
  ],
  fonts: fonts,
  headerColor: PdfColors.primary,
);
```

### 4. صناديق الإحصائيات

```dart
EnhancedPdfUtils.buildStatisticsBox(
  title: 'إجمالي المبيعات',
  value: '15,450',
  subtitle: 'ريال سعودي',
  fonts: fonts,
  color: PdfColors.success,
  icon: '💰',
);
```

### 5. تذييل الاتصال

```dart
EnhancedPdfUtils.buildContactFooter(fonts: fonts);
```

## 🛠️ أدوات التنسيق

### تنسيق التواريخ
```dart
EnhancedPdfUtils.formatDateTime(DateTime.now());
// النتيجة: "الأحد 27 أكتوبر 2024 - 14:30"
```

### تنسيق العملة
```dart
EnhancedPdfUtils.formatCurrency(1250.50);
// النتيجة: "1,251 ر.س"
```

### تنسيق الأرقام
```dart
EnhancedPdfUtils.formatNumber(123456.789);
// النتيجة: "123,457"
```

## 📊 أنماط النصوص المتاحة

```dart
PdfTextStyles.heading1(fonts.bold)     // عنوان رئيسي كبير
PdfTextStyles.heading2(fonts.bold)     // عنوان ثانوي  
PdfTextStyles.heading3(fonts.bold)     // عنوان فرعي
PdfTextStyles.body(fonts.regular)      // نص عادي
PdfTextStyles.bodyBold(fonts.bold)     // نص عادي غامق
PdfTextStyles.bodySmall(fonts.regular) // نص صغير
PdfTextStyles.caption(fonts.regular)   // تعليق توضيحي
PdfTextStyles.price(fonts.bold)        // أسعار (لون ذهبي)
PdfTextStyles.tableHeader(fonts.bold)  // رؤوس جداول
PdfTextStyles.tableCell(fonts.regular) // خلايا جداول
```

## 🌈 ألوان النظام

```dart
PdfColors.primary      // أزرق غامق للعناوين
PdfColors.secondary    // ذهبي للأسعار والمبالغ
PdfColors.accent       // أزرق فاتح للتمييز
PdfColors.success      // أخضر للنجاح والأرباح
PdfColors.warning      // برتقالي للتحذيرات
PdfColors.danger       // أحمر للأخطاء والخسائر
PdfColors.info         // أزرق للمعلومات
PdfColors.textDark     // نص غامق
PdfColors.textLight    // نص فاتح
PdfColors.textWhite    // نص أبيض
```

## 🔧 تطبيق النظام الجديد على الملفات الموجودة

### 1. تحديث payment_models.dart

```dart
// قديم
Future<void> generatePDF() async {
  final fonts = await PdfUtils.loadArabicFonts();
  // ... تصميم بسيط
}

// جديد
Future<void> generatePDF() async {
  await EnhancedPdfHelper.generateEnhancedReceipt(
    payment: this,
    booking: relatedBooking,
    receivedBy: receivedByUser,
  );
}
```

### 2. تحديث التقارير

```dart
// في expenses_report_screen.dart قديم
Future<void> _exportPdf() async {
  final fonts = await PdfUtils.loadArabicFonts();
  // ... جدول بسيط
}

// جديد
Future<void> _exportPdf() async {
  await EnhancedPdfHelper.generateEnhancedExpensesReport(
    expenses: _expenses,
    fromDate: _fromDate,
    toDate: _toDate,
    generatedBy: 'مدير النظام',
  );
}
```

## 📱 أمثلة على الاستخدام في الواجهات

### في شاشة المدفوعات
```dart
FloatingActionButton(
  onPressed: () => PdfPreviewHelper.openEnhancedPaymentReceiptPreview(
    context,
    payment: selectedPayment,
    booking: relatedBooking,
    receivedBy: currentUser.name,
  ),
  child: Icon(Icons.picture_as_pdf),
  tooltip: 'إيصال محسّن',
)
```

### في شاشة التقارير
```dart
ElevatedButton.icon(
  onPressed: () async {
    await EnhancedPdfHelper.generateHotelSummaryReport(
      fromDate: startDate,
      toDate: endDate,
      bookings: bookingsList,
      payments: paymentsList,
      expenses: expensesList,
      generatedBy: 'تقرير تلقائي',
    );
  },
  icon: Icon(Icons.analytics),
  label: Text('تقرير شامل محسّن'),
)
```

## 🎯 النتائج المتوقعة

بعد تطبيق هذا النظام، ستحصل على:

### ✅ إيصالات احترافية
- تصميم أنيق مع ألوان الفندق
- معلومات واضحة ومنظمة
- QR Code للتحقق السريع
- تذييل مع معلومات الاتصال

### ✅ فواتير ضريبية متكاملة  
- متوافقة مع المعايير السعودية
- تحسب ضريبة القيمة المضافة تلقائياً
- تاريخ مفصل للمدفوعات
- شروط وأحكام واضحة

### ✅ تقارير تفصيلية وجميلة
- إحصائيات بصرية جذابة
- جداول منسقة وملونة
- تحليل تفصيلي للبيانات
- مخططات بيانية (placeholder)

### ✅ تحسين تجربة المستخدم
- معاينة PDF قبل الطباعة
- مشاركة سهلة للملفات
- رسائل أخطاء واضحة
- واجهات سلسة وسريعة

## 🔄 خطوات التطبيق

1. **استبدال imports** القديمة بالجديدة
2. **تحديث دوال generatePDF** لاستخدام النظام المحسّن
3. **إضافة أزرار معاينة** في الواجهات
4. **اختبار التصاميم** على أجهزة مختلفة
5. **تخصيص الألوان** حسب هوية الفندق

---

**🎉 تهانينا!** أصبح لديك الآن نظام PDF الأجمل والأكثر احترافية لتطبيقات إدارة الفنادق!