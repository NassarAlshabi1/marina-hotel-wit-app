import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

class ArabicPdfFonts {
  ArabicPdfFonts({required this.base, required this.bold});

  final pw.Font base;
  final pw.Font bold;
}

class PdfUtils {
  /// يحمّل عائلة خطوط NotoNaskhArabic لتقارير PDF.
  ///
  /// الخطان من نسخة Google Noto الرسمية (full — تشمل الحروف اللاتينية
  /// والأرقام) لضمان عرض النصوص العربية والأرقام والبريد الإلكتروني
  /// داخل التقارير دون مربعات فارغة.
  static Future<ArabicPdfFonts> loadArabicFonts() async {
    final baseData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Bold.ttf',
    );
    return ArabicPdfFonts(
      base: pw.Font.ttf(baseData),
      bold: pw.Font.ttf(boldData),
    );
  }

  static Future<pw.ImageProvider?> loadLogoImage() async {
    try {
      final data = await rootBundle.load('assets/images/hotel_logo.jpg');
      final Uint8List bytes = data.buffer.asUint8List();
      return pw.MemoryImage(bytes);
    } catch (e) {
      debugPrint('⚠️ Swallowed error in pdf_utils.dart: ');
      return null;
    }
  }
}
