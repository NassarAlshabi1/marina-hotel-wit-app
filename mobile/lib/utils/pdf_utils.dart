import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show debugPrint;

class ArabicPdfFonts {
  ArabicPdfFonts({required this.base, required this.bold});

  final pw.Font base;
  final pw.Font bold;
}

class PdfUtils {
  static Future<ArabicPdfFonts> loadArabicFonts() async {
    final baseData = await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
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
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in pdf_utils.dart: ');
      return null;
    }
  }
}
