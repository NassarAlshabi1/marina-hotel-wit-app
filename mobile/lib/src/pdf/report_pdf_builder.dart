/// أدوات بناء تقارير PDF مشتركة
///
/// تُستخدم لتوحيد تنسيق التقارير المختلفة (المدفوعات، المصروفات، الديون، الدخل والمصروفات).
/// يوفر رأس التقرير الموحّد، تذييل الصفحات، واتجاه النص RTL.
library;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
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
    required this.buildContent,
    required this.fileName,
    this.extraHeaderLine,
    this.fromDate,
    this.toDate,
    this.customHeader,
    this.compactHeader = false,
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

  /// رأس مضغوط (≈44pt) للتقارير العملية المختصرة (مثل تقرير المدفوعات).
  ///
  /// عند true يُستخدم رأس صف واحد محدود الارتفاع بدل الرأس الكبير —
  /// يُحافظ على اسم الفندق وعنوان التقرير والفترة دون هدر مساحة A4.
  /// الافتراضي false — لا يؤثر على التقارير الموجودة.
  final bool compactHeader;

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
        : config.compactHeader
        ? _buildCompactHeader(fonts, config)
        : _buildDefaultHeader(fonts, config);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(32, 42, 32, 48),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => buildPageFooter(fonts, context),
        build: (context) => [header, ...config.buildContent(fonts)],
      ),
    );

    return doc;
  }

  /// بناء مستند PDF ومشاركته مباشرة
  ///
  /// يُنشئ التقرير ويعرض خيارات المشاركة (حفظ، مشاركة، طباعة).
  static Future<void> buildAndShare(ReportPdfConfig config) async {
    final doc = await buildDocument(config);
    await Printing.sharePdf(bytes: await doc.save(), filename: config.fileName);
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
    final createdAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.border, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تاريخ الإنشاء: $createdAt',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.textMuted,
            ),
          ),
          pw.Text(
            'وثيقة داخلية',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.textMuted,
            ),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.textMuted,
            ),
          ),
        ],
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

  /// رأس مضغوط (≈44pt): العنوان والفترة يميناً، واسم الفندق وتاريخ
  /// الإنشاء يساراً — للتقارير العملية المختصرة فقط (compactHeader: true).
  static pw.Widget _buildCompactHeader(
    ArabicPdfFonts fonts,
    ReportPdfConfig config,
  ) {
    final fromLabel = config.fromDate != null
        ? DateFormat('yyyy-MM-dd').format(config.fromDate!)
        : 'غير محدد';
    final toLabel = config.toDate != null
        ? DateFormat('yyyy-MM-dd').format(config.toDate!)
        : 'غير محدد';
    final periodText = 'الفترة من $fromLabel إلى $toLabel';
    final extra = (config.extraHeaderLine ?? '').trim();
    final contextLine = extra.isEmpty ? periodText : '$periodText • $extra';
    final createdAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(color: PdfColors.primary),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                config.title,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: PdfColors.textWhite,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                contextLine,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 7.5,
                  color: PdfColors.textWhite,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'فندق مارينا بلازا',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: PdfColors.textWhite,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تاريخ الإنشاء: $createdAt',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 7.5,
                  color: PdfColors.textWhite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// بناء رأس التقرير الافتراضي من الإعدادات
  static pw.Widget _buildDefaultHeader(
    ArabicPdfFonts fonts,
    ReportPdfConfig config,
  ) {
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
