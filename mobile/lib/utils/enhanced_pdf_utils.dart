import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;

/// ألوان مخصصة للـ PDF
class PdfColors {
  static const primary = PdfColor(1.0, 0.8, 0.502);
  static const secondary = PdfColor(0.85, 0.65, 0.13);
  static const accent = PdfColor(0.0, 0.48, 0.65);
  static const textDark = PdfColor(0.15, 0.15, 0.15);
  static const textLight = PdfColor(0.5, 0.5, 0.5);
  static const textWhite = PdfColor(1.0, 1.0, 1.0);
  static const backgroundLight = PdfColor(0.98, 0.98, 0.98);
  static const backgroundCard = PdfColor(0.95, 0.95, 0.95);
  static const success = PdfColor(0.0, 0.7, 0.3);
  static const warning = PdfColor(1.0, 0.6, 0.0);
  static const danger = PdfColor(0.9, 0.2, 0.2);
  static const info = PdfColor(0.1, 0.6, 0.9);
}

/// أنماط النصوص المخصصة
class PdfTextStyles {
  static pw.TextStyle heading1(pw.Font font) => pw.TextStyle(
    font: font,
    fontSize: 24,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.primary,
  );

  static pw.TextStyle heading2(pw.Font font) => pw.TextStyle(
    font: font,
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.textDark,
  );

  static pw.TextStyle heading3(pw.Font font) => pw.TextStyle(
    font: font,
    fontSize: 16,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.textDark,
  );

  static pw.TextStyle body(pw.Font font) =>
      pw.TextStyle(font: font, fontSize: 12, color: PdfColors.textDark);

  static pw.TextStyle bodySmall(pw.Font font) =>
      pw.TextStyle(font: font, fontSize: 10, color: PdfColors.textLight);

  static pw.TextStyle bodyBold(pw.Font font) => pw.TextStyle(
    font: font,
    fontSize: 12,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.textDark,
  );

  static pw.TextStyle caption(pw.Font font) =>
      pw.TextStyle(font: font, fontSize: 9, color: PdfColors.textLight);

  static pw.TextStyle whiteText(pw.Font font) =>
      pw.TextStyle(font: font, fontSize: 12, color: PdfColors.textWhite);

  static pw.TextStyle price(pw.Font font) => pw.TextStyle(
    font: font,
    fontSize: 14,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.secondary,
  );

  static pw.TextStyle tableHeader(pw.Font font) => pw.TextStyle(
    font: font,
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.textWhite,
  );

  static pw.TextStyle tableCell(pw.Font font) =>
      pw.TextStyle(font: font, fontSize: 10, color: PdfColors.textDark);
}

/// خطوط عربية محسنة
class ArabicPdfFonts {
  ArabicPdfFonts({
    required this.regular,
    required this.bold,
    required this.light,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font light;
}

/// أدوات PDF محسنة مع تصاميم احترافية
class EnhancedPdfUtils {
  static Future<ArabicPdfFonts> loadArabicFonts() async {
    final regularData = await rootBundle.load(
      'assets/fonts/Tajawal-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
    final lightData = regularData;

    return ArabicPdfFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
      light: pw.Font.ttf(lightData),
    );
  }

  static Future<pw.ImageProvider?> loadLogoImage() async {
    try {
      final data = await rootBundle.load('assets/images/hotel_logo.jpg');
      final Uint8List bytes = data.buffer.asUint8List();
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// بناء رأس الصفحة الاحترافي للفندق
  static pw.Widget buildProfessionalHeader({
    required ArabicPdfFonts fonts,
    pw.ImageProvider? logo,
    String title = '',
    String subtitle = '',
    bool showGradient = true,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        gradient: showGradient
            ? pw.LinearGradient(
                colors: const [PdfColors.primary, PdfColors.accent],
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
              )
            : null,
        color: showGradient ? null : PdfColors.primary,
      ),
      padding: const pw.EdgeInsets.all(20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'فندق مارينا بلازا',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 24,
                    color: PdfColors.textWhite,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'تجربة إقامة استثنائية',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 11,
                    color: PdfColors.textWhite,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(color: PdfColors.secondary),
                  child: pw.Text(
                    title.isNotEmpty ? title : 'وثيقة رسمية',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 14,
                      color: PdfColors.textWhite,
                    ),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    subtitle,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 10,
                      color: PdfColors.textWhite,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (logo != null)
            pw.Container(
              width: 80,
              height: 80,
              decoration: pw.BoxDecoration(color: PdfColors.textWhite),
              child: pw.Image(logo, fit: pw.BoxFit.cover),
            )
          else
            pw.Container(
              width: 80,
              height: 80,
              decoration: pw.BoxDecoration(color: PdfColors.secondary),
              child: pw.Center(
                child: pw.Text(
                  'M',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 32,
                    color: PdfColors.textWhite,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// بناء معلومات الاتصال في التذييل
  static pw.Widget buildContactFooter({required ArabicPdfFonts fonts}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: PdfColors.backgroundCard),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _buildContactItem(
                icon: '📍',
                label: 'العنوان',
                value: 'القاهرة - شارع احمد قاسم',
                fonts: fonts,
              ),
              _buildContactItem(
                icon: '📞',
                label: 'الهاتف',
                value: '02324457',
                fonts: fonts,
              ),
              _buildContactItem(
                icon: '📧',
                label: 'البريد الإلكتروني',
                value: 'info@marina-hotel.com',
                fonts: fonts,
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.textLight),
          pw.SizedBox(height: 4),
          pw.Text(
            'شكراً لاختياركم فندق مارينا بلازا • نتطلع إلى خدمتكم مرة أخرى',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9,
              color: PdfColors.textLight,
              fontStyle: pw.FontStyle.italic,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildContactItem({
    required String icon,
    required String label,
    required String value,
    required ArabicPdfFonts fonts,
  }) {
    return pw.Column(
      children: [
        pw.Text(icon, style: const pw.TextStyle(fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 9,
            color: PdfColors.textDark,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 8,
            color: PdfColors.textLight,
          ),
        ),
      ],
    );
  }

  /// بناء بطاقة معلومات أنيقة
  static pw.Widget buildInfoCard({
    required String title,
    required List<pw.Widget> content,
    required ArabicPdfFonts fonts,
    PdfColor? backgroundColor,
    PdfColor? borderColor,
    double? borderWidth,
  }) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: pw.BoxDecoration(
        color: backgroundColor ?? PdfColors.backgroundLight,
        border: pw.Border.all(
          color: borderColor ?? PdfColors.primary,
          width: borderWidth ?? 1,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: borderColor ?? PdfColors.primary,
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 14,
                color: PdfColors.textWhite,
              ),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: content,
            ),
          ),
        ],
      ),
    );
  }

  /// بناء جدول احترافي
  static pw.Widget buildProfessionalTable({
    required List<String> headers,
    required List<List<String>> data,
    required ArabicPdfFonts fonts,
    List<double>? columnWidths,
    PdfColor? headerColor,
    PdfColor? alternateRowColor,
  }) {
    final headerStyle = PdfTextStyles.tableHeader(fonts.bold);
    final cellStyle = PdfTextStyles.tableCell(fonts.regular);

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.textLight),
      ),
      child: pw.Table(
        columnWidths: columnWidths != null
            ? Map.fromIterables(
                List.generate(headers.length, (index) => index),
                columnWidths.map((w) => pw.FixedColumnWidth(w)),
              )
            : null,
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: headerColor ?? PdfColors.primary,
            ),
            children: headers
                .map(
                  (header) => pw.Padding(
                    padding: const pw.EdgeInsets.all(12),
                    child: pw.Text(
                      header,
                      style: headerStyle,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                )
                .toList(),
          ),
          ...data.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final isEven = index % 2 == 0;

            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: isEven
                    ? (alternateRowColor ?? PdfColors.backgroundLight)
                    : null,
              ),
              children: row
                  .map(
                    (cell) => pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Text(
                        cell,
                        style: cellStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  )
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  /// بناء صندوق إحصائيات
  static pw.Widget buildStatisticsBox({
    required String title,
    required String value,
    String? subtitle,
    required ArabicPdfFonts fonts,
    PdfColor? color,
    String? icon,
  }) {
    final baseColor = color ?? PdfColors.primary;
    // Replicate the old `flatten(PdfColors.textWhite, 0.2)` logic to maintain visual consistency.
    // This creates a lighter shade by mixing with 20% white.
    final secondaryColor = PdfColor(
      baseColor.red * 0.8 + 0.2,
      baseColor.green * 0.8 + 0.2,
      baseColor.blue * 0.8 + 0.2,
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [baseColor, secondaryColor],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
      ),
      child: pw.Column(
        children: [
          if (icon != null) ...[
            pw.Text(icon, style: const pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 8),
          ],
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 12,
              color: PdfColors.textWhite,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 20,
              color: PdfColors.textWhite,
            ),
            textAlign: pw.TextAlign.center,
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            pw.Text(
              subtitle,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 9,
                color: PdfColors.textWhite,
              ),
              textAlign: pw.TextAlign.center,
            ),
        ],
      ),
    );
  }

  /// تنسيق التاريخ والوقت
  static String formatDateTime(DateTime dateTime) {
    const List<String> arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    const List<String> arabicDays = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];

    final day = arabicDays[dateTime.weekday - 1];
    final month = arabicMonths[dateTime.month - 1];

    return '$day ${dateTime.day} $month ${dateTime.year} - ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// تنسيق المبلغ بالعملة
  static String formatCurrency(double amount) {
    return '${amount.toStringAsFixed(0)}';
  }

  /// تنسيق الأرقام بالفواصل
  static String formatNumber(double number) {
    return number
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match match) => '${match[1]},',
        );
  }

  /// بناء مربع نائب لـ QR Code
  static pw.Widget buildQRCodePlaceholder({
    required String data,
    required ArabicPdfFonts fonts,
    double size = 60,
  }) {
    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.textLight, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Center(
        child: pw.Text(
          'QR',
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 10,
            color: PdfColors.textLight,
          ),
        ),
      ),
    );
  }
}
