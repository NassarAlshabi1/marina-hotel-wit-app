import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;

/// ألوان مخصصة للـ PDF
class PdfColors {
  static const primary = PdfColor(0.706, 0.420, 0.0); // #b46b00
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

  // ── نظام التصميم المضغوط (تقارير A4 RTL) ──
  /// نص ثانوي خافت للعناوين الفرعية والنصوص الصغيرة.
  static const textMuted = PdfColor(0.42, 0.42, 0.45);

  /// خلفية البطاقات والجداول (أبيض مائل للرمادي البارد).
  static const cardBackground = PdfColor(0.982, 0.982, 0.985);

  /// حدود البطاقات والفواصل الداخلية للجداول.
  static const border = PdfColor(0.82, 0.82, 0.85);

  /// تظليل الصفوف الزوجية (striping) خفيف لا يشوش على النص 12pt.
  static const tableStripe = PdfColor(0.955, 0.955, 0.965);
}

/// خطوط عربية محسنة (NotoNaskhArabic لتقارير PDF)
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

/// أنماط النصوص المخصصة — نظام مضغوط للورقة A4 مع اتجاه RTL.
class PdfTextStyles {
  PdfTextStyles._();

  static pw.TextStyle coverHotelName(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 22,
      color: PdfColors.textWhite,
    );
  }

  static pw.TextStyle coverTitle(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 17,
      color: PdfColors.textWhite,
    );
  }

  static pw.TextStyle reportTitle(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 18,
      color: PdfColors.textDark,
    );
  }

  static pw.TextStyle sectionTitle(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 13,
      color: PdfColors.primary,
    );
  }

  static pw.TextStyle sectionSubtitle(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.regular,
      fontSize: 9,
      color: PdfColors.textMuted,
    );
  }

  static pw.TextStyle body(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.regular,
      fontSize: 10,
      lineSpacing: 1.8,
      color: PdfColors.textDark,
    );
  }

  static pw.TextStyle bodyBold(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 10,
      color: PdfColors.textDark,
    );
  }

  static pw.TextStyle small(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.regular,
      fontSize: 8,
      color: PdfColors.textMuted,
    );
  }

  /// عناوين الأعمدة.
  static pw.TextStyle tableHeader(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 11,
      color: PdfColors.textWhite,
    );
  }

  /// نص الصفوف: 12 عريض حسب المواصفة المعتمدة.
  static pw.TextStyle tableCell(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 12,
      color: PdfColors.textDark,
    );
  }

  static pw.TextStyle metricTitle(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.regular,
      fontSize: 8,
      color: PdfColors.textWhite,
    );
  }

  static pw.TextStyle metricValue(ArabicPdfFonts fonts) {
    return pw.TextStyle(
      font: fonts.bold,
      fontSize: 15,
      color: PdfColors.textWhite,
    );
  }
}

/// عنصر حجز مُلخّص لجدول الحجوزات في تقارير PDF.
class ReservationReportItem {
  ReservationReportItem({
    required this.bookingNumber,
    required this.guestName,
    required this.roomNumber,
    required this.roomType,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.status,
    required this.total,
  });

  final String bookingNumber;
  final String guestName;
  final String roomNumber;
  final String roomType;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final String status;
  final double total;
}

/// أدوات PDF محسنة مع تصاميم احترافية مضغوطة (A4 / RTL)
class EnhancedPdfUtils {
  /// يحمّل عائلة خطوط NotoNaskhArabic لتقارير PDF.
  ///
  /// regular و light يستخدمان النسخة العادية، وbold النسخة السميكة —
  /// من نسخة Google Noto الرسمية (full — تشمل الحروف اللاتينية والأرقام).
  /// لا يوجد ملف Light مطلوب؛ يستخدم العادي للنصوص الثانوية.
  static Future<ArabicPdfFonts> loadArabicFonts() async {
    final regularData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );

    final boldData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Bold.ttf',
    );

    return ArabicPdfFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
      light: pw.Font.ttf(regularData),
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

  /// خلط لون مع الأبيض لتوليد درجة أفتح للتدرجات.
  static PdfColor _mixWithWhite(
    PdfColor color, {
    required double whiteRatio,
  }) {
    return PdfColor(
      color.red + (1.0 - color.red) * whiteRatio,
      color.green + (1.0 - color.green) * whiteRatio,
      color.blue + (1.0 - color.blue) * whiteRatio,
    );
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
            ? const pw.LinearGradient(
                colors: [PdfColors.primary, PdfColors.accent],
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
                  style: PdfTextStyles.coverHotelName(fonts),
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
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.secondary,
                  ),
                  child: pw.Text(
                    title.isNotEmpty ? title : 'وثيقة رسمية',
                    style: PdfTextStyles.coverTitle(fonts),
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
              decoration: const pw.BoxDecoration(color: PdfColors.textWhite),
              child: pw.Image(logo, fit: pw.BoxFit.cover),
            )
          else
            pw.Container(
              width: 80,
              height: 80,
              decoration: const pw.BoxDecoration(color: PdfColors.secondary),
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
      decoration: const pw.BoxDecoration(color: PdfColors.backgroundCard),
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

  /// بطاقة إحصاءات مضغوطة (ارتفاع 64) — توفّر مساحة A4 للجداول.
  static pw.Widget buildStatisticsBox({
    required String title,
    required String value,
    required ArabicPdfFonts fonts,
    String? subtitle,
    PdfColor color = PdfColors.primary,
  }) {
    final lighterColor = _mixWithWhite(color, whiteRatio: 0.12);

    return pw.Container(
      height: 64,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 7,
      ),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [color, lighterColor],
          begin: pw.Alignment.topRight,
          end: pw.Alignment.bottomLeft,
        ),
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            title,
            style: PdfTextStyles.metricTitle(fonts),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: PdfTextStyles.metricValue(fonts),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              subtitle,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 6.8,
                color: PdfColors.textWhite,
              ),
              textAlign: pw.TextAlign.center,
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
  }

  /// شبكة بطاقات إحصاءات بعرض ثابت مضغوط لكل بطاقة.
  static pw.Widget buildStatisticsGrid({
    required List<pw.Widget> items,
  }) {
    return pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((item) {
        return pw.SizedBox(
          width: 120,
          child: item,
        );
      }).toList(),
    );
  }

  /// بطاقة معلومات منخفضة الارتفاع (شريط لوني جانبي + padding صغير).
  static pw.Widget buildInfoCard({
    required String title,
    required List<pw.Widget> content,
    required ArabicPdfFonts fonts,
    PdfColor color = PdfColors.primary,
  }) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.cardBackground,
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(4),
        ),
        border: pw.Border.all(
          color: PdfColors.border,
          width: 0.5,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: 4,
            color: color,
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(
                10,
                8,
                10,
                9,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: PdfTextStyles.sectionTitle(fonts),
                  ),
                  pw.SizedBox(height: 5),
                  ...content,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// صف مفتاح/قيمة مضغوط داخل بطاقات المعلومات.
  static pw.Widget buildKeyValueRow({
    required ArabicPdfFonts fonts,
    required String label,
    required String value,
    bool valueLtr = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 88,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 9.5,
                color: PdfColors.textDark,
              ),
            ),
          ),
          pw.Expanded(
            child: valueLtr
                ? pw.Directionality(
                    textDirection: pw.TextDirection.ltr,
                    child: pw.Text(
                      value,
                      style: PdfTextStyles.body(fonts),
                      textAlign: pw.TextAlign.right,
                    ),
                  )
                : pw.Text(
                    value,
                    style: PdfTextStyles.body(fonts),
                    textAlign: pw.TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }

  /// جدول احترافي مضغوط: نص صفوف 12pt عريض، فواصل بين كل صف وعمود،
  /// تظليل صفوف خفيف، واتجاه RTL إجباري.
  ///
  /// [headerColor] و[alternateRowColor] اختياريان للتوافق مع الاستدعاءات
  /// السابقة — الافتراضي: اللون الرئيسي للتقرير وتظليل [PdfColors.tableStripe].
  static pw.Widget buildProfessionalTable({
    required List<String> headers,
    required List<List<String>> data,
    required ArabicPdfFonts fonts,
    List<double>? columnFlex,
    List<pw.TextAlign>? alignments,
    PdfColor? headerColor,
    PdfColor? alternateRowColor,
  }) {
    assert(
      columnFlex == null || columnFlex.length == headers.length,
      'يجب أن يطابق عدد columnFlex عدد headers',
    );

    assert(
      alignments == null || alignments.length == headers.length,
      'يجب أن يطابق عدد alignments عدد headers',
    );

    final columnWidths = <int, pw.TableColumnWidth>{};

    if (columnFlex != null) {
      for (var index = 0; index < columnFlex.length; index++) {
        columnWidths[index] = pw.FlexColumnWidth(columnFlex[index]);
      }
    }

    pw.TextAlign getAlignment(int index) {
      if (alignments != null && index < alignments.length) {
        return alignments[index];
      }

      return pw.TextAlign.right;
    }

    const insideBorder = pw.BorderSide(
      color: PdfColors.border,
      width: 0.55,
    );

    const outsideBorder = pw.BorderSide(
      color: PdfColors.primary,
      width: 0.75,
    );

    final effectiveHeaderColor = headerColor ?? PdfColors.primary;
    final effectiveStripeColor = alternateRowColor ?? PdfColors.tableStripe;

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          color: PdfColors.cardBackground,
          borderRadius: pw.BorderRadius.all(
            pw.Radius.circular(3),
          ),
        ),
        child: pw.Table(
          columnWidths: columnWidths.isEmpty ? null : columnWidths,

          /// خطوط خارجية وداخلية كاملة.
          border: const pw.TableBorder(
            top: outsideBorder,
            right: outsideBorder,
            bottom: outsideBorder,
            left: outsideBorder,

            /// فاصل بين الصفوف.
            horizontalInside: insideBorder,

            /// فاصل بين الأعمدة.
            verticalInside: insideBorder,
          ),

          children: [
            /// رأس الجدول.
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: effectiveHeaderColor,
              ),
              children: List.generate(headers.length, (columnIndex) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: pw.Text(
                    headers[columnIndex],
                    style: PdfTextStyles.tableHeader(fonts),
                    textAlign: getAlignment(columnIndex),
                    maxLines: 2,
                  ),
                );
              }),
            ),

            /// صفوف البيانات.
            ...data.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final row = entry.value;

              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: rowIndex.isEven
                      ? effectiveStripeColor
                      : PdfColors.cardBackground,
                ),
                children: List.generate(headers.length, (columnIndex) {
                  final value = columnIndex < row.length
                      ? row[columnIndex]
                      : '';

                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: pw.Text(
                      value,
                      style: PdfTextStyles.tableCell(fonts),
                      textAlign: getAlignment(columnIndex),
                      maxLines: 2,
                      overflow: pw.TextOverflow.clip,
                    ),
                  );
                }),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// يبني قائمة صفوف طويلة كعدّة جداول متتالية بدل جدول واحد ضخم.
  ///
  /// [buildProfessionalTable] يرسم كل `data` في `pw.Table` واحد؛ لتقارير
  /// بمدى تاريخي واسع (مئات/آلاف الصفوف) هذا بطيء جداً وقد يُجمّد التطبيق.
  /// هذه الدالة تقسّم `data` لعدة جداول متتالية بحجم [chunkSize] صف كحد
  /// أقصى لكل جدول — كل الصفوف تظهر بالكامل بدون اقتصاص، فقط موزّعة على
  /// عدة جداول/صفحات. استخدم `widgets.addAll(...)` مع النتيجة بدل
  /// `widgets.add(...)`.
  static List<pw.Widget> buildChunkedTable({
    required List<String> headers,
    required List<List<String>> data,
    required ArabicPdfFonts fonts,
    List<double>? columnFlex,
    List<pw.TextAlign>? alignments,
    PdfColor? headerColor,
    PdfColor? alternateRowColor,
    int chunkSize = 200,
  }) {
    if (data.isEmpty) {
      return [
        buildProfessionalTable(
          headers: headers,
          data: data,
          fonts: fonts,
          columnFlex: columnFlex,
          alignments: alignments,
          headerColor: headerColor,
          alternateRowColor: alternateRowColor,
        ),
      ];
    }
    final widgets = <pw.Widget>[];
    for (var start = 0; start < data.length; start += chunkSize) {
      final end = (start + chunkSize < data.length)
          ? start + chunkSize
          : data.length;
      if (start > 0) {
        widgets.add(pw.SizedBox(height: 4));
      }
      widgets.add(
        buildProfessionalTable(
          headers: headers,
          data: data.sublist(start, end),
          fonts: fonts,
          columnFlex: columnFlex,
          alignments: alignments,
          headerColor: headerColor,
          alternateRowColor: alternateRowColor,
        ),
      );
    }
    return widgets;
  }

  /// ترتيب الحجوزات زمنياً (الأقدم أولاً) ثم برقم الحجز —
  /// ترتيب حتمي قابل للتدقيق في التقارير المالية.
  static List<ReservationReportItem> sortReservations(
    List<ReservationReportItem> reservations,
  ) {
    final sorted = List<ReservationReportItem>.from(reservations);
    sorted.sort((a, b) {
      final byCheckIn = a.checkIn.compareTo(b.checkIn);
      if (byCheckIn != 0) return byCheckIn;
      return a.bookingNumber.compareTo(b.bookingNumber);
    });
    return sorted;
  }

  /// تاريخ مختصر dd/MM/yyyy — يوفّر مساحة داخل خلايا الجدول.
  static String formatDateShort(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  /// رؤوس جدول الحجوزات — 8 أعمدة (دمج "النوع" مع "الغرفة").
  static const List<String> reservationHeaders = [
    'رقم الحجز',
    'اسم النزيل',
    'الغرفة / النوع',
    'الدخول',
    'الخروج',
    'الليالي',
    'الحالة',
    'الإجمالي',
  ];

  /// تحويل عنصر حجز إلى صف جدول.
  static List<String> reservationToRow(
    ReservationReportItem reservation,
  ) {
    return [
      reservation.bookingNumber,
      reservation.guestName,
      '${reservation.roomNumber}\n${reservation.roomType}',
      formatDateShort(reservation.checkIn),
      formatDateShort(reservation.checkOut),
      reservation.nights.toString(),
      reservation.status,
      formatCurrency(reservation.total),
    ];
  }

  /// جدول الحجوزات المحدث — 8 أعمدة بتوزيع مناسب لحجم 12 عريض في A4.
  static pw.Widget buildReservationsTable({
    required ArabicPdfFonts fonts,
    required List<ReservationReportItem> reservations,
  }) {
    final sortedReservations = sortReservations(reservations);

    final rows = sortedReservations.map(reservationToRow).toList();

    return buildProfessionalTable(
      fonts: fonts,
      headers: reservationHeaders,
      data: rows,

      /// توزيع مناسب لحجم 12 عريض في ورقة A4.
      columnFlex: const [
        1.05, // رقم الحجز
        1.85, // اسم النزيل
        1.30, // الغرفة / النوع
        1.08, // الدخول
        1.08, // الخروج
        0.62, // الليالي
        0.95, // الحالة
        1.15, // الإجمالي
      ],

      alignments: const [
        pw.TextAlign.center,
        pw.TextAlign.right,
        pw.TextAlign.center,
        pw.TextAlign.center,
        pw.TextAlign.center,
        pw.TextAlign.center,
        pw.TextAlign.center,
        pw.TextAlign.center,
      ],
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

    return '$day ${dateTime.day} $month ${dateTime.year} - '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// تنسيق المبلغ بالعملة مع فواصل الآلاف
  static String formatCurrency(double amount) {
    return formatNumber(amount);
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
        border: pw.Border.all(color: PdfColors.textLight),
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
