/// أدوات بناء تقارير PDF مشتركة
///
/// تُستخدم لتوحيد تنسيق التقارير المختلفة (المدفوعات، المصروفات، الديون، الدخل والمصروفات).
/// يوفر رأس التقرير الموحّد، تذييل الصفحات، واتجاه النص RTL.
library;

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'enhanced_pdf_utils.dart';

/// إعدادات تقرير PDF
///
/// يُمرّر كائن من هذا النوع إلى [ReportPdfBuilder] لإنشاء تقرير PDF موحّد.
/// كل تقرير يُهيّئ الإعدادات حسب احتياجاته ثم يستدعي
/// [ReportPdfBuilder.buildAndShare] أو [ReportPdfBuilder.buildDocument].
class ReportPdfConfig {
  /// إنشاء إعدادات تقرير PDF
  ReportPdfConfig({
    required this.title,
    this.extraHeaderLine,
    this.fromDate,
    this.toDate,
    this.customHeader,
    required this.buildContent,
    required this.fileName,
  });

  /// عنوان التقرير (مثال: 'مدفوعات النزلاء')
  final String title;

  /// سطر إضافي يظهر في الرأس (مثال: 'الغرفة: 101')
  final String? extraHeaderLine;

  /// تاريخ بداية الفترة
  final DateTime? fromDate;

  /// تاريخ نهاية الفترة
  final DateTime? toDate;

  /// رأس مخصص يتجاوز الرأس الافتراضي
  ///
  /// يُستخدم للتقارير ذات تنسيق الرأس الخاص (مثل تقرير الدخل والمصروفات).
  final pw.Widget Function(ArabicPdfFonts fonts)? customHeader;

  /// بناء محتوى التقرير
  ///
  /// تُمرّر الخطوط المحمّلة مسبقاً لبناء الجداول والملخصات.
  final List<pw.Widget> Function(ArabicPdfFonts fonts) buildContent;

  /// اسم ملف PDF الناتج
  final String fileName;
}

/// بنّاء تقارير PDF مشترك
///
/// يوفر بنية موحّدة لبناء تقارير PDF تتضمن:
/// - رأس التقرير مع اسم الفندق والعنوان والفترة
/// - تذييل الصفحات بأرقام الصفحات
/// - اتجاه النص من اليمين لليسار (RTL)
/// - مشاركة الملف مباشرة
class ReportPdfBuilder {
  // منع الإنشاء المباشر
  ReportPdfBuilder._();

  /// بناء مستند PDF كامل
  ///
  /// يُحمّل الخطوط، يبني الرأس والمحتوى والتذييل، ويعيد المستند جاهزاً.
  /// يُفيد في الحالات التي يحتاج فيها المستدعي للمستند قبل المشاركة
  /// (مثل الطباعة أو الحفظ المحلي).
  static Future<pw.Document> buildDocument(ReportPdfConfig config) async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();

    final header = config.customHeader != null
        ? config.customHeader!(fonts)
        : _buildDefaultHeader(fonts, config);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => buildPageFooter(fonts, context),
        build: (context) => [
          header,
          ...config.buildContent(fonts),
        ],
      ),
    );

    return doc;
  }

  /// بناء مستند PDF ومشاركته مباشرة
  ///
  /// يُنشئ التقرير ويعرض خيارات المشاركة (حفظ، مشاركة، طباعة).
  static Future<void> buildAndShare(ReportPdfConfig config) async {
    final doc = await buildDocument(config);
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: config.fileName,
    );
  }

  /// بناء رأس التقرير الافتراضي
  ///
  /// يعرض اسم الفندق، عنوان التقرير، الفترة الزمنية، وسطر إضافي اختياري.
  /// يمكن استخدامه مباشرة إذا احتاج تقرير لبناء رأس مخصص بمعلمات مختلفة:
  /// ```dart
  /// ReportPdfBuilder.buildReportHeader(
  ///   fonts: fonts,
  ///   title: 'عنوان مخصص',
  ///   periodText: 'الفترة من ... إلى ...',
  ///   extraHeaderLine: 'تصفية: ...',
  /// )
  /// ```
  static pw.Widget buildReportHeader({
    required ArabicPdfFonts fonts,
    required String title,
    required String periodText,
    String? extraHeaderLine,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(color: PdfColors.primary),
      padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'فندق مارينا بلازا',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 22,
              color: PdfColors.textWhite,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 20,
              color: PdfColors.textWhite,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            periodText,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 12,
              color: PdfColors.textWhite,
            ),
            textAlign: pw.TextAlign.center,
          ),
          if (extraHeaderLine != null && extraHeaderLine.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              extraHeaderLine,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 12,
                color: PdfColors.textWhite,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// تذييل الصفحات بأرقام الصفحات
  ///
  /// يمكن استخدامه مباشرة في بناء صفحات مخصصة:
  /// ```dart
  /// footer: (context) => ReportPdfBuilder.buildPageFooter(fonts, context),
  /// ```
  static pw.Widget buildPageFooter(ArabicPdfFonts fonts, pw.Context context) {
    return pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Text(
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        style: pw.TextStyle(font: fonts.regular, fontSize: 10),
      ),
    );
  }

  /// توليد اسم ملف PDF منسّق
  ///
  /// يُزيل المسافات من العنوان ويُضيف طابعاً زمنياً لضمان تفرد اسم الملف.
  /// مثال: `generateFileName('مدفوعات النزلاء')` → `مدفوعات-النزلاء-20250615_1430.pdf`
  static String generateFileName(String title) {
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final sanitizedTitle = title.replaceAll(RegExp(r'\s+'), '-');
    return '$sanitizedTitle-$timestamp.pdf';
  }

  // ======== طرق داخلية ========

  /// بناء رأس التقرير الافتراضي من الإعدادات
  static pw.Widget _buildDefaultHeader(
      ArabicPdfFonts fonts, ReportPdfConfig config) {
    final fromLabel = config.fromDate != null
        ? DateFormat('yyyy-MM-dd').format(config.fromDate!)
        : 'غير محدد';
    final toLabel = config.toDate != null
        ? DateFormat('yyyy-MM-dd').format(config.toDate!)
        : 'غير محدد';
    final periodText = 'الفترة من تاريخ $fromLabel إلى تاريخ $toLabel';

    return buildReportHeader(
      fonts: fonts,
      title: config.title,
      periodText: periodText,
      extraHeaderLine: config.extraHeaderLine,
    );
  }
}
