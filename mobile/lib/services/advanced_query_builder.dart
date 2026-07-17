import 'package:appwrite/appwrite.dart';

/// بناء استعلامات Appwrite بشكل متقدم
///
/// يوفر واجهة Fluent API لبناء استعلامات معقدة بسهولة
///
/// مثال:
/// ```dart
/// final queries = AdvancedQueryBuilder()
///     .where('status', 'شاغرة')
///     .whereBetween('price', 10000, 20000)
///     .search('room_number', '101')
///     .orderBy('price', desc: false)
///     .limit(25)
///     .offset(0)
///     .build();
/// ```
class AdvancedQueryBuilder {
  final List<String> _queries = [];

  /// إضافة شرط مساواة
  ///
  /// [attribute] - اسم الحقل
  /// [value] - القيمة المطلوبة
  AdvancedQueryBuilder where(String attribute, dynamic value) {
    _queries.add(Query.equal(attribute, value));
    return this;
  }

  /// إضافة شرط عدم مساواة
  ///
  /// [attribute] - اسم الحقل
  /// [value] - القيمة المستبعدة
  AdvancedQueryBuilder whereNot(String attribute, dynamic value) {
    _queries.add(Query.notEqual(attribute, value));
    return this;
  }

  /// إضافة شرط أكبر من
  ///
  /// [attribute] - اسم الحقل
  /// [value] - القيمة الدنيا (غير شاملة)
  AdvancedQueryBuilder whereGreaterThan(String attribute, dynamic value) {
    _queries.add(Query.greaterThan(attribute, value));
    return this;
  }

  /// إضافة شرط أكبر من أو يساوي
  ///
  /// [attribute] - اسم الحقل
  /// [value] - القيمة الدنيا (شاملة)
  AdvancedQueryBuilder whereGreaterThanOrEqual(String attribute, dynamic value) {
    _queries.add(Query.greaterThanEqual(attribute, value));
    return this;
  }

  /// إضافة شرط أصغر من
  ///
  /// [attribute] - اسم الحقل
  /// [value] - القيمة القصوى (غير شاملة)
  AdvancedQueryBuilder whereLessThan(String attribute, dynamic value) {
    _queries.add(Query.lessThan(attribute, value));
    return this;
  }

  /// إضافة شرط أصغر من أو يساوي
  ///
  /// [attribute] - اسم الحقل
  /// [value] - القيمة القصوى (شاملة)
  AdvancedQueryBuilder whereLessThanOrEqual(String attribute, dynamic value) {
    _queries.add(Query.lessThanEqual(attribute, value));
    return this;
  }

  /// إضافة شرط بين قيمتين
  ///
  /// [attribute] - اسم الحقل
  /// [min] - القيمة الدنيا
  /// [max] - القيمة القصوى
  AdvancedQueryBuilder whereBetween(String attribute, dynamic min, dynamic max) {
    _queries.add(Query.greaterThanEqual(attribute, min));
    _queries.add(Query.lessThanEqual(attribute, max));
    return this;
  }

  /// إضافة شرط IN (القيمة موجودة في قائمة)
  ///
  /// [attribute] - اسم الحقل
  /// [values] - قائمة القيم المسموحة
  AdvancedQueryBuilder whereIn(String attribute, List<dynamic> values) {
    for (final value in values) {
      _queries.add(Query.equal(attribute, value));
    }
    return this;
  }

  /// إضافة شرط بحث نصي
  ///
  /// [attribute] - اسم الحقل
  /// [searchTerm] - النص المراد البحث عنه
  AdvancedQueryBuilder search(String attribute, String searchTerm) {
    if (searchTerm.isNotEmpty) {
      _queries.add(Query.search(attribute, searchTerm));
    }
    return this;
  }

  /// إضافة شرط NULL
  ///
  /// [attribute] - اسم الحقل
  AdvancedQueryBuilder whereNull(String attribute) {
    _queries.add(Query.isNull(attribute));
    return this;
  }

  /// إضافة شرط NOT NULL
  ///
  /// [attribute] - اسم الحقل
  AdvancedQueryBuilder whereNotNull(String attribute) {
    _queries.add(Query.isNotNull(attribute));
    return this;
  }

  /// ترتيب النتائج تصاعدياً
  ///
  /// [attribute] - اسم الحقل للترتيب
  AdvancedQueryBuilder orderAsc(String attribute) {
    _queries.add(Query.orderAsc(attribute));
    return this;
  }

  /// ترتيب النتائج تنازلياً
  ///
  /// [attribute] - اسم الحقل للترتيب
  AdvancedQueryBuilder orderDesc(String attribute) {
    _queries.add(Query.orderDesc(attribute));
    return this;
  }

  /// ترتيب النتائج (تصاعدي أو تنازلي)
  ///
  /// [attribute] - اسم الحقل للترتيب
  /// [desc] - هل الترتيب تنازلي؟ (افتراضي: false)
  AdvancedQueryBuilder orderBy(String attribute, {bool desc = false}) {
    if (desc) {
      _queries.add(Query.orderDesc(attribute));
    } else {
      _queries.add(Query.orderAsc(attribute));
    }
    return this;
  }

  /// تحديد عدد النتائج
  ///
  /// [value] - عدد النتائج المطلوبة
  AdvancedQueryBuilder limit(int value) {
    _queries.add(Query.limit(value));
    return this;
  }

  /// تحديد نقطة البداية (للـ Pagination)
  ///
  /// [value] - عدد العناصر المتخطاة
  AdvancedQueryBuilder offset(int value) {
    _queries.add(Query.offset(value));
    return this;
  }

  /// اختيار حقول محددة فقط
  ///
  /// [attributes] - قائمة أسماء الحقول
  AdvancedQueryBuilder select(List<String> attributes) {
    _queries.add(Query.select(attributes));
    return this;
  }

  /// إضافة cursor للـ pagination (بديل لـ offset)
  ///
  /// [cursorId] - معرف العنصر الأخير من الصفحة السابقة
  AdvancedQueryBuilder cursorAfter(String cursorId) {
    _queries.add(Query.cursorAfter(cursorId));
    return this;
  }

  /// إضافة cursor للـ pagination العكسي
  ///
  /// [cursorId] - معرف العنصر الأول من الصفحة التالية
  AdvancedQueryBuilder cursorBefore(String cursorId) {
    _queries.add(Query.cursorBefore(cursorId));
    return this;
  }

  /// بناء الاستعلامات
  ///
  /// إرجاع قائمة الاستعلامات الجاهزة للاستخدام مع Appwrite
  List<String> build() => List.unmodifiable(_queries);

  /// الحصول على عدد الاستعلامات
  int get count => _queries.length;

  /// هل يوجد استعلامات؟
  bool get isEmpty => _queries.isEmpty;
  bool get isNotEmpty => _queries.isNotEmpty;

  /// مسح جميع الاستعلامات
  void clear() {
    _queries.clear();
  }

  /// نسخ Builder جديد مع نفس الاستعلامات
  AdvancedQueryBuilder clone() {
    final cloned = AdvancedQueryBuilder();
    cloned._queries.addAll(_queries);
    return cloned;
  }

  @override
  String toString() => 'AdvancedQueryBuilder(${_queries.length} queries)';
}

/// امتداد لـ Query لسهولة الاستخدام
extension QueryHelpers on Query {
  /// بناء query builder جديد
  static AdvancedQueryBuilder builder() => AdvancedQueryBuilder();
}
