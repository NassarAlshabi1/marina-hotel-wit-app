import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncPerformanceMetrics {
  final DateTime syncTime;
  final int uploadedRecords;
  final int downloadedRecords;
  final int durationMs;
  final double dataSizeKb;
  final String syncType;
  final bool success;
  final String? errorMessage;

  SyncPerformanceMetrics({
    required this.syncTime,
    required this.uploadedRecords,
    required this.downloadedRecords,
    required this.durationMs,
    required this.dataSizeKb,
    required this.syncType,
    required this.success,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'sync_time': syncTime.toIso8601String(),
        'uploaded_records': uploadedRecords,
        'downloaded_records': downloadedRecords,
        'duration_ms': durationMs,
        'data_size_kb': dataSizeKb,
        'sync_type': syncType,
        'success': success,
        'error_message': errorMessage,
      };

  factory SyncPerformanceMetrics.fromJson(Map<String, dynamic> json) {
    return SyncPerformanceMetrics(
      syncTime: DateTime.parse(json['sync_time']),
      uploadedRecords: json['uploaded_records'],
      downloadedRecords: json['downloaded_records'],
      durationMs: json['duration_ms'],
      dataSizeKb: (json['data_size_kb'] as num).toDouble(),
      syncType: json['sync_type'],
      success: json['success'],
      errorMessage: json['error_message'],
    );
  }
}

class SyncPerformanceTracker {
  static const String _metricsKey = 'sync_performance_history';
  static const int _maxHistorySize = 100;

  static Future<void> recordMetrics(SyncPerformanceMetrics metrics) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_metricsKey);

      List<Map<String, dynamic>> history = [];
      if (historyJson != null) {
        final decoded = jsonDecode(historyJson) as List<dynamic>;
        history = decoded.cast<Map<String, dynamic>>();
      }

      history.insert(0, metrics.toJson());

      if (history.length > _maxHistorySize) {
        history = history.sublist(0, _maxHistorySize);
      }

      await prefs.setString(_metricsKey, jsonEncode(history));

      debugPrint('📊 تم تسجيل مقاييس الأداء');
      _printMetricsSummary(metrics);
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل المقاييس: $e');
    }
  }

  static Future<List<SyncPerformanceMetrics>> getRecentMetrics({int limit = 10}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_metricsKey);

      if (historyJson == null) return [];

      final decoded = jsonDecode(historyJson) as List<dynamic>;
      final metrics = decoded
          .take(limit)
          .map((json) => SyncPerformanceMetrics.fromJson(json))
          .toList();

      return metrics;
    } catch (e) {
      debugPrint('❌ خطأ في جلب المقاييس: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> getAveragePerformance() async {
    try {
      final metrics = await getRecentMetrics(limit: 20);

      if (metrics.isEmpty) {
        return {'error': 'لا توجد بيانات'};
      }

      final successfulMetrics = metrics.where((m) => m.success).toList();

      if (successfulMetrics.isEmpty) {
        return {'error': 'لا توجد مزامنات ناجحة'};
      }

      final avgDuration = successfulMetrics
              .map((m) => m.durationMs)
              .reduce((a, b) => a + b) /
          successfulMetrics.length;

      final avgDataSize = successfulMetrics
              .map((m) => m.dataSizeKb)
              .reduce((a, b) => a + b) /
          successfulMetrics.length;

      final successRate = (successfulMetrics.length / metrics.length * 100);

      return {
        'avg_duration_ms': avgDuration.round(),
        'avg_data_size_kb': avgDataSize.toStringAsFixed(2),
        'success_rate': '${successRate.toStringAsFixed(1)}%',
        'total_syncs': metrics.length,
        'successful_syncs': successfulMetrics.length,
      };
    } catch (e) {
      debugPrint('❌ خطأ في حساب المتوسط: $e');
      return {'error': 'خطأ في الحساب'};
    }
  }

  static void _printMetricsSummary(SyncPerformanceMetrics metrics) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📊 ملخص أداء المزامنة');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('⏰ الوقت: ${metrics.syncTime}');
    debugPrint('📤 سجلات مرفوعة: ${metrics.uploadedRecords}');
    debugPrint('📥 سجلات محملة: ${metrics.downloadedRecords}');
    debugPrint('⏱️  المدة: ${metrics.durationMs} ms');
    debugPrint('💾 حجم البيانات: ${metrics.dataSizeKb.toStringAsFixed(2)} KB');
    debugPrint('🔄 نوع المزامنة: ${metrics.syncType}');
    debugPrint('✅ النتيجة: ${metrics.success ? "نجح" : "فشل"}');
    if (metrics.errorMessage != null) {
      debugPrint('❌ الخطأ: ${metrics.errorMessage}');
    }
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
}
