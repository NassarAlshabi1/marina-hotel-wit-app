import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// خدمة ضغط البيانات باستخدام GZip
/// تقلل حجم النسخ الاحتياطية بنسبة تصل إلى 80%
class CompressionService {
  /// ضغط JSON إلى bytes مضغوطة باستخدام GZip
  static Uint8List compressJson(Map<String, dynamic> jsonData) {
    final stopwatch = Stopwatch()..start();
    
    try {
      // تحويل JSON إلى String
      final jsonString = jsonEncode(jsonData);
      final originalSize = utf8.encode(jsonString).length;
      
      debugPrint('📦 بدء ضغط البيانات...');
      debugPrint('   الحجم الأصلي: ${_formatBytes(originalSize)}');
      
      // تحويل String إلى bytes
      final bytes = utf8.encode(jsonString);
      
      // ضغط باستخدام GZip
      final compressed = GZipCodec(level: 6).encode(bytes);
      
      final compressedSize = compressed.length;
      final ratio = ((1 - (compressedSize / originalSize)) * 100).toStringAsFixed(1);
      
      stopwatch.stop();
      
      debugPrint('✅ تم الضغط بنجاح');
      debugPrint('   الحجم المضغوط: ${_formatBytes(compressedSize)}');
      debugPrint('   نسبة التوفير: $ratio%');
      debugPrint('   الوقت المستغرق: ${stopwatch.elapsedMilliseconds}ms');
      
      return Uint8List.fromList(compressed);
      
    } catch (e) {
      debugPrint('❌ خطأ في ضغط البيانات: $e');
      rethrow;
    }
  }
  
  /// فك ضغط bytes المضغوطة إلى JSON
  static Map<String, dynamic> decompressToJson(Uint8List compressedData) {
    final stopwatch = Stopwatch()..start();
    
    try {
      final compressedSize = compressedData.length;
      debugPrint('📦 بدء فك الضغط...');
      debugPrint('   الحجم المضغوط: ${_formatBytes(compressedSize)}');
      
      // فك الضغط
      final decompressed = GZipCodec().decode(compressedData);
      
      // تحويل bytes إلى String
      final jsonString = utf8.decode(decompressed);
      
      // تحويل String إلى JSON
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      final originalSize = decompressed.length;
      final ratio = ((originalSize / compressedSize) - 1) * 100;
      
      stopwatch.stop();
      
      debugPrint('✅ تم فك الضغط بنجاح');
      debugPrint('   الحجم الأصلي: ${_formatBytes(originalSize)}');
      debugPrint('   نسبة التوسع: ${ratio.toStringAsFixed(1)}%');
      debugPrint('   الوقت المستغرق: ${stopwatch.elapsedMilliseconds}ms');
      
      return jsonData;
      
    } catch (e) {
      debugPrint('❌ خطأ في فك ضغط البيانات: $e');
      rethrow;
    }
  }
  
  /// ضغط String مباشر (للنصوص الكبيرة)
  static Uint8List compressString(String text) {
    try {
      final bytes = utf8.encode(text);
      final compressed = GZipCodec(level: 6).encode(bytes);
      return Uint8List.fromList(compressed);
    } catch (e) {
      debugPrint('❌ خطأ في ضغط النص: $e');
      rethrow;
    }
  }
  
  /// فك ضغط إلى String
  static String decompressToString(Uint8List compressedData) {
    try {
      final decompressed = GZipCodec().decode(compressedData);
      return utf8.decode(decompressed);
    } catch (e) {
      debugPrint('❌ خطأ في فك ضغط النص: $e');
      rethrow;
    }
  }
  
  /// تقدير حجم البيانات بعد الضغط (بدون ضغط فعلي)
  static int estimateCompressedSize(Map<String, dynamic> jsonData) {
    try {
      final jsonString = jsonEncode(jsonData);
      final originalSize = utf8.encode(jsonString).length;
      
      // تقدير تقريبي: GZip عادة يضغط JSON بنسبة 70-80%
      return (originalSize * 0.25).round();
    } catch (e) {
      debugPrint('❌ خطأ في تقدير الحجم: $e');
      return 0;
    }
  }
  
  /// تنسيق حجم البيانات (bytes إلى KB/MB)
  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }
  
  /// فحص ما إذا كانت البيانات مضغوطة بالفعل
  static bool isCompressed(Uint8List data) {
    // GZip header يبدأ بـ 0x1f 0x8b
    if (data.length < 2) return false;
    return data[0] == 0x1f && data[1] == 0x8b;
  }
}
