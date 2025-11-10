import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'google_drive_backup_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// خدمة حفظ واستعادة جلسة التطبيق (Session State) في Google Drive
/// 
/// تسمح هذه الخدمة بحفظ حالة التطبيق الحالية وإعداداته في Google Drive
/// واستعادتها في أي وقت أو على أجهزة أخرى
class SessionStateManager {
  static final SessionStateManager _instance = SessionStateManager._internal();
  factory SessionStateManager() => _instance;
  SessionStateManager._internal();

  final String _sessionFileName = 'marina_hotel_session_state.json';
  final String _sessionFolderName = 'Marina Hotel Sessions';

  /// حفظ جلسة التطبيق الحالية في Google Drive
  Future<bool> saveSessionToDrive({
    required GoogleDriveBackupService driveService,
    String? sessionName,
  }) async {
    try {
      debugPrint('🔄 جاري حفظ جلسة التطبيق...');
      
      // جمع بيانات الجلسة
      final sessionData = await _collectSessionData();
      
      // إضافة معلومات إضافية
      sessionData['session_name'] = sessionName ?? 'Session ${DateTime.now().toIso8601String()}';
      sessionData['saved_at'] = DateTime.now().toIso8601String();
      sessionData['device_info'] = await _getDeviceInfo();
      
      // تحويل البيانات إلى JSON
      final jsonString = jsonEncode(sessionData);
      
      // رفع البيانات إلى Google Drive مباشرة
      final fileId = await driveService.uploadBackup(sessionData);
      
      if (fileId.isNotEmpty) {
        debugPrint('✅ تم حفظ الجلسة في Google Drive بنجاح');
        
        // حفظ معلومات آخر جلسة محفوظة
        await _saveLastSessionInfo('session_${DateTime.now().millisecondsSinceEpoch}.json', sessionData['saved_at']);
        
        return true;
      } else {
        throw Exception('فشل في رفع الملف');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في حفظ الجلسة: $e');
      if (kDebugMode) {
        debugPrint('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// استعادة جلسة محفوظة من Google Drive
  Future<bool> restoreSessionFromDrive({
    required GoogleDriveBackupService driveService,
    required String fileName,
  }) async {
    try {
      debugPrint('🔄 جاري استعادة الجلسة من Google Drive...');
      
      // البحث عن الملف في Drive
      final files = await driveService.listBackupFiles();
      final sessionFile = files.firstWhere(
        (f) => f.fileName == fileName,
        orElse: () => throw Exception('الملف غير موجود'),
      );
      
      // تنزيل البيانات مباشرة
      final sessionData = await driveService.downloadBackup(sessionFile.fileId);
      
      // استعادة البيانات
      await _restoreSessionData(sessionData);
      
      debugPrint('✅ تم استعادة الجلسة بنجاح');
      return true;
      
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في استعادة الجلسة: $e');
      if (kDebugMode) {
        debugPrint('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// الحصول على قائمة الجلسات المحفوظة في Google Drive
  Future<List<SessionInfo>> getAvailableSessions({
    required GoogleDriveBackupService driveService,
  }) async {
    try {
      debugPrint('🔄 جاري البحث عن الجلسات المحفوظة...');
      
      final files = await driveService.listBackupFiles();
      final sessionFiles = files.where((f) => 
        f.name.startsWith('session_') || f.name.endsWith('.json')
      ).toList();
      
      final sessions = <SessionInfo>[];
      
      for (final file in sessionFiles) {
        sessions.add(SessionInfo(
          fileName: file.fileName,
          fileId: file.fileId,
          savedAt: file.createdTime,
          size: file.size,
        ));
      }
      
      // ترتيب حسب التاريخ (الأحدث أولاً)
      sessions.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      
      debugPrint('✅ تم العثور على ${sessions.length} جلسة محفوظة');
      return sessions;
      
    } catch (e) {
      debugPrint('❌ خطأ في البحث عن الجلسات: $e');
      return [];
    }
  }

  /// حذف جلسة محفوظة من Google Drive
  Future<bool> deleteSession({
    required GoogleDriveBackupService driveService,
    required String fileId,
  }) async {
    try {
      debugPrint('🔄 جاري حذف الجلسة...');
      
      await driveService.deleteBackupFile(fileId);
      final deleted = true;
      
      if (deleted) {
        debugPrint('✅ تم حذف الجلسة بنجاح');
        return true;
      } else {
        throw Exception('فشل في حذف الملف');
      }
      
    } catch (e) {
      debugPrint('❌ خطأ في حذف الجلسة: $e');
      return false;
    }
  }

  /// جمع بيانات الجلسة الحالية
  Future<Map<String, dynamic>> _collectSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'app_version': '1.2.0',
      'preferences': {
        // الإعدادات العامة
        'theme_mode': prefs.getString('theme_mode') ?? 'system',
        'language': prefs.getString('language') ?? 'ar',
        
        // إعدادات النسخ الاحتياطي
        'auto_backup_enabled': prefs.getBool('auto_backup_enabled') ?? false,
        'backup_frequency': prefs.getString('backup_frequency') ?? 'daily',
        'max_backup_count': prefs.getInt('max_backup_count') ?? 25,
        'retention_days': prefs.getInt('retention_days') ?? 45,
        
        // إعدادات المزامنة
        'sync_on_startup': prefs.getBool('sync_on_startup') ?? true,
        'wifi_only_sync': prefs.getBool('wifi_only_sync') ?? false,
        
        // إعدادات Ditto
        'ditto_enabled': prefs.getBool('ditto_enabled') ?? false,
        'ditto_auto_sync': prefs.getBool('ditto_auto_sync') ?? true,
        
        // إعدادات العرض
        'show_room_images': prefs.getBool('show_room_images') ?? true,
        'compact_mode': prefs.getBool('compact_mode') ?? false,
        'notifications_enabled': prefs.getBool('notifications_enabled') ?? true,
        
        // إعدادات التقارير
        'default_report_format': prefs.getString('default_report_format') ?? 'pdf',
        'include_charts': prefs.getBool('include_charts') ?? true,
        
        // آخر تصفية مستخدمة
        'last_booking_filter': prefs.getString('last_booking_filter'),
        'last_room_filter': prefs.getString('last_room_filter'),
        'last_report_date_range': prefs.getString('last_report_date_range'),
      },
      'user_state': {
        'last_screen': prefs.getString('last_screen') ?? '/dashboard',
        'last_login': prefs.getString('last_login'),
      },
    };
  }

  /// استعادة بيانات الجلسة
  Future<void> _restoreSessionData(Map<String, dynamic> sessionData) async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      final preferences = sessionData['preferences'] as Map<String, dynamic>?;
      if (preferences != null) {
        // استعادة الإعدادات
        for (final entry in preferences.entries) {
          final key = entry.key;
          final value = entry.value;
          
          if (value == null) continue;
          
          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          }
        }
      }
      
      final userState = sessionData['user_state'] as Map<String, dynamic>?;
      if (userState != null) {
        for (final entry in userState.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is String) {
            await prefs.setString(key, value);
          }
        }
      }
      
      debugPrint('✅ تم استعادة ${preferences?.length ?? 0} إعداد');
      
    } catch (e) {
      debugPrint('⚠️ خطأ في استعادة بعض الإعدادات: $e');
    }
  }

  /// حفظ معلومات آخر جلسة محفوظة
  Future<void> _saveLastSessionInfo(String fileName, String savedAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_saved_session_file', fileName);
    await prefs.setString('last_saved_session_date', savedAt);
  }

  /// الحصول على معلومات آخر جلسة محفوظة
  Future<Map<String, String>?> getLastSavedSessionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fileName = prefs.getString('last_saved_session_file');
      final savedAt = prefs.getString('last_saved_session_date');
      
      if (fileName != null && savedAt != null) {
        return {
          'fileName': fileName,
          'savedAt': savedAt,
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في الحصول على معلومات الجلسة: $e');
      return null;
    }
  }

  /// الحصول على معلومات الجهاز
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    };
  }

  /// مسح جميع بيانات الجلسة المحلية
  Future<bool> clearLocalSessionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('✅ تم مسح بيانات الجلسة المحلية');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في مسح البيانات: $e');
      return false;
    }
  }
}

/// معلومات الجلسة المحفوظة
class SessionInfo {
  final String fileName;
  final String fileId;
  final DateTime savedAt;
  final int size;

  SessionInfo({
    required this.fileName,
    required this.fileId,
    required this.savedAt,
    required this.size,
  });

  String get formattedDate {
    return '${savedAt.day}/${savedAt.month}/${savedAt.year} - ${savedAt.hour}:${savedAt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (size < 1024) {
      return '$size بايت';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} كيلوبايت';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
    }
  }
}
