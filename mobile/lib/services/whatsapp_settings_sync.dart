import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_config_manager.dart';
import 'appwrite_service.dart';

/// خدمة مزامنة إعدادات الواتساب مع Appwrite Console
/// تسمح برفع الإعدادات من الجهاز إلى السحابة وتنزيلها على جهاز آخر
/// ملاحظة: المجموعة app_settings تُنشأ عبر سكربت Python (create_app_settings_collection.py)
class WhatsAppSettingsSync {
  WhatsAppSettingsSync(this._appwrite);
  static const String _docId = 'whatsapp_settings';
  static const String _collectionId = 'app_settings';

  final AppwriteService _appwrite;

  /// رفع إعدادات الواتساب الحالية إلى Appwrite
  Future<({bool success, String? error})> uploadToCloud() async {
    try {
      await _appwrite.initialize();
      final prefs = await SharedPreferences.getInstance();

      final data = <String, dynamic>{
        'wa_api_type': prefs.getString('wa_api_type') ?? 'custom',
        'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
        'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
        'wa_api_token': prefs.getString('wa_api_token') ?? '',
        'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
      };

      final dbId = AppwriteConfigManager.databaseId;

      // محاولة تحديث المستند الموجود
      try {
        // ignore: deprecated_member_use
        await _appwrite.databases.updateDocument(
          databaseId: dbId,
          collectionId: _collectionId,
          documentId: _docId,
          data: data,
        );
      } catch (_) {
        // إذا لم يكن موجوداً، إنشاء مستند جديد
        // ignore: deprecated_member_use
        await _appwrite.databases.createDocument(
          databaseId: dbId,
          collectionId: _collectionId,
          documentId: _docId,
          data: data,
        );
      }

      debugPrint('WhatsApp settings uploaded to Appwrite successfully');
      return (success: true, error: null);
    } on AppwriteException catch (e) {
      final msg = _parseAppwriteError(e);
      debugPrint('WhatsApp settings upload failed: $msg');
      return (success: false, error: msg);
    } catch (e) {
      debugPrint('WhatsApp settings upload error: $e');
      return (success: false, error: e.toString());
    }
  }

  /// تنزيل إعدادات الواتساب من Appwrite وحفظها محلياً
  Future<({bool success, String? error, Map<String, String>? settings})> downloadFromCloud() async {
    try {
      await _appwrite.initialize();

      // ignore: deprecated_member_use
      final doc = await _appwrite.databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: _collectionId,
        documentId: _docId,
      );

      final prefs = await SharedPreferences.getInstance();

      final fields = ['wa_api_type', 'wa_api_base_url', 'wa_api_instance_id', 'wa_api_token', 'wa_custom_url_template'];

      final saved = <String, String>{};
      for (final field in fields) {
        final value = doc.data[field];
        if (value != null && value.toString().isNotEmpty) {
          await prefs.setString(field, value.toString());

          saved[field] = value.toString();
        }
      }

      debugPrint('WhatsApp settings downloaded from Appwrite successfully');
      return (success: true, error: null, settings: saved);
    } on AppwriteException catch (e) {
      final msg = _parseAppwriteError(e);
      debugPrint('WhatsApp settings download failed: $msg');
      return (success: false, error: msg, settings: null);
    } catch (e) {
      debugPrint('WhatsApp settings download error: $e');
      return (success: false, error: e.toString(), settings: null);
    }
  }

  /// التحقق من وجود إعدادات في السحابة
  Future<bool> existsInCloud() async {
    try {
      await _appwrite.initialize();
      // ignore: deprecated_member_use
      await _appwrite.databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: _collectionId,
        documentId: _docId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _parseAppwriteError(AppwriteException e) {
    if (e.code == 404) {
      return 'لا توجد إعدادات محفوظة في السحابة بعد.\nارفع الإعدادات من هذا الجهاز أولاً.';
    }
    if (e.code == 401) {
      return 'غير مصرح بالوصول.\nتحقق من مفتاح API في إعدادات Appwrite.';
    }
    return 'خطأ ${e.code}: ${e.message ?? "حدث خطأ غير معروف"}';
  }
}
