import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
import 'appwrite_service.dart';

/// خدمة مزامنة إعدادات الواتساب مع Appwrite Console
/// تسمح برفع الإعدادات من الجهاز إلى السحابة وتنزيلها على جهاز آخر
/// تدعم الإنشاء التلقائي للمجموعة والحقول إذا لم تكن موجودة
class WhatsAppSettingsSync {
  static const String _docId = 'whatsapp_settings';
  static const String _collectionId = 'app_settings';

  final AppwriteService _appwrite;

  WhatsAppSettingsSync(this._appwrite);

  /// تعريف حقول المجموعة
  static const _fields = [
    _FieldDef('wa_api_type', 50, 'greenapi'),
    _FieldDef('wa_api_base_url', 500, ''),
    _FieldDef('wa_api_instance_id', 200, ''),
    _FieldDef('wa_api_token', 500, ''),
    _FieldDef('wa_custom_url_template', 1000, ''),
    _FieldDef('wa_sendzen_api_key', 500, ''),
    _FieldDef('wa_sendzen_from_number', 30, ''),
    _FieldDef('wa_template', 5000, ''),
  ];

  /// التحقق من وجود المجموعة وإنشائها تلقائياً
  Future<({bool success, String? error})> _ensureCollectionExists() async {
    final dbId = AppwriteConfigManager.databaseId;

    try {
      // التحقق من وجود المجموعة
      await _appwrite.databases.getCollection(
        databaseId: dbId,
        collectionId: _collectionId,
      );
      debugPrint('WhatsApp: app_settings collection exists');
      return (success: true, error: null);
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        debugPrint('WhatsApp: app_settings not found, creating...');
        return await _createCollection(dbId);
      }
      return (success: false, error: _parseAppwriteError(e));
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  /// إنشاء المجموعة والحقول
  Future<({bool success, String? error})> _createCollection(String dbId) async {
    try {
      // 1. إنشاء المجموعة
      await _appwrite.databases.createCollection(
        databaseId: dbId,
        collectionId: _collectionId,
        name: 'App Settings',
        permissions: [
          Permission.read(Role.any()),
          Permission.write(Role.any()),
        ],
        enabled: true,
      );
      debugPrint('WhatsApp: collection created');

      // 2. إنشاء الحقول (كل حقل يحتاج طلب منفصل)
      for (final field in _fields) {
        try {
          await _appwrite.databases.createStringAttribute(
            databaseId: dbId,
            collectionId: _collectionId,
            key: field.key,
            size: field.size,
            required: false,
            xdefault: field.defaultValue,
          );
          debugPrint('WhatsApp: attribute ${field.key} created');
        } on AppwriteException catch (e) {
          if (e.code != 409) {
            // تجاهل 409 (موجود مسبقاً)
            debugPrint(
              'WhatsApp: failed to create ${field.key}: ${e.message}',
            );
          }
        }
      }

      return (success: true, error: null);
    } on AppwriteException catch (e) {
      final msg = _parseAppwriteError(e);
      debugPrint('WhatsApp: collection creation failed: $msg');
      return (success: false, error: msg);
    } catch (e) {
      debugPrint('WhatsApp: collection creation error: $e');
      return (success: false, error: e.toString());
    }
  }

  /// رفع إعدادات الواتساب الحالية إلى Appwrite
  Future<({bool success, String? error})> uploadToCloud() async {
    try {
      await _appwrite.initialize();
      final prefs = await SharedPreferences.getInstance();

      final data = <String, dynamic>{
        'wa_api_type': prefs.getString('wa_api_type') ?? 'greenapi',
        'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
        'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
        'wa_api_token': prefs.getString('wa_api_token') ?? '',
        'wa_custom_url_template':
            prefs.getString('wa_custom_url_template') ?? '',
        'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
        'wa_sendzen_from_number':
            prefs.getString('wa_sendzen_from_number') ?? '',
        'wa_template': prefs.getString('whatsapp_template') ?? '',
      };

      // التأكد من وجود المجموعة
      final setupResult = await _ensureCollectionExists();
      if (!setupResult.success) {
        return (success: false, error: setupResult.error);
      }

      // محاولة تحديث المستند الموجود
      try {
        await _appwrite.databases.updateDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: _collectionId,
          documentId: _docId,
          data: data,
        );
      } catch (_) {
        // إذا لم يكن موجوداً، إنشاء مستند جديد
        await _appwrite.databases.createDocument(
          databaseId: AppwriteConfigManager.databaseId,
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
  Future<({bool success, String? error, Map<String, String>? settings})>
      downloadFromCloud() async {
    try {
      await _appwrite.initialize();

      // التأكد من وجود المجموعة
      final setupResult = await _ensureCollectionExists();
      if (!setupResult.success) {
        return (success: false, error: setupResult.error, settings: null);
      }

      final doc = await _appwrite.databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: _collectionId,
        documentId: _docId,
      );

      final prefs = await SharedPreferences.getInstance();

      final fields = [
        'wa_api_type',
        'wa_api_base_url',
        'wa_api_instance_id',
        'wa_api_token',
        'wa_custom_url_template',
        'wa_sendzen_api_key',
        'wa_sendzen_from_number',
        'wa_template',
      ];

      final saved = <String, String>{};
      for (final field in fields) {
        final value = doc.data[field];
        if (value != null && value.toString().isNotEmpty) {
          await prefs.setString(field, value.toString());
          // wa_template يحفظ بمفتاح مختلف
          if (field == 'wa_template') {
            await prefs.setString('whatsapp_template', value.toString());
          }
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

  /// التحقق من وجود المجموعة في Appwrite
  Future<bool> collectionExists() async {
    try {
      await _appwrite.initialize();
      await _appwrite.databases.getCollection(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: _collectionId,
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

/// تعريف حقل في المجموعة
class _FieldDef {
  final String key;
  final int size;
  final String defaultValue;
  const _FieldDef(this.key, this.size, this.defaultValue);
}
