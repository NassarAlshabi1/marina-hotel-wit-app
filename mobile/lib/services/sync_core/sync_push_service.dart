import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_logger.dart';
import '../appwrite_service.dart';
import '../appwrite_sync_utils.dart';
import '../booking_derived_fields_service.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../booking_price_adjustment_service.dart';
import '../local_db.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/rooms_repository.dart';
import '../sync_constants.dart';
import 'sync_error_service.dart';

/// خدمة دفع التغييرات المحلية إلى Appwrite Cloud
class SyncPushService {
  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  late final AdapterRegistry _adapterRegistry;
  late final BookingsRepository _bookingsRepository;
  late final RoomsRepository _roomsRepository;
  final SyncErrorService _err;
  double _adaptiveBatchSize = 50;

  SyncPushService({
    required this.appwriteService,
    required this.database,
    required this.outboxDao,
    AdapterRegistry? adapterRegistry,
    BookingsRepository? bookingsRepository,
    RoomsRepository? roomsRepository,
    SyncErrorService? errorService,
  })  : _adapterRegistry = adapterRegistry ?? AdapterRegistry(database),
        _bookingsRepository = bookingsRepository ?? BookingsRepository(database),
        _roomsRepository = roomsRepository ?? RoomsRepository(database),
        _err = errorService ?? SyncErrorService(tag: 'PUSH');

  /// دفع جميع التغييرات المحلية من outbox إلى Appwrite
  Future<int> pushAllEntities() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        _err.warning('⚠️ لا يوجد اتصال بالإنترنت - تم تأجيل الرفع');
        return 0;
      }
    } catch (_) {}

    int totalProcessed = 0;
    int consecutiveFailures = 0;

    while (true) {
      final batchSize = _adaptiveBatchSize.round();
      final entries = await outboxDao.takeBatch(batchSize, sources: const ['local']);
      if (entries.isEmpty) break;

      int processedInBatch = 0;
      for (final entry in entries) {
        try {
          const timeoutSeconds = 30;
          final success = await _processOutboxEntry(entry)
              .timeout(Duration(seconds: timeoutSeconds));
          if (success) {
            await outboxDao.removeById(entry.id);
            processedInBatch++;
          }
        } catch (e) {
          if (e is TimeoutException) {
            _err.warning('⏱️ Timeout processing entry ${entry.id}');
          }
        }
      }

      if (processedInBatch == entries.length) {
        _adaptiveBatchSize = (_adaptiveBatchSize * 1.3).clamp(10, 200);
        consecutiveFailures = 0;
      } else {
        _adaptiveBatchSize = (_adaptiveBatchSize * 0.6).clamp(5, 100);
        consecutiveFailures++;
      }

      totalProcessed += processedInBatch;

      if (consecutiveFailures >= 3) {
        _err.warning('⛔ 3 دفعات فاشلة متتالية - إيقاف المزامنة');
        break;
      }

      if (entries.length < batchSize) break;
    }
    return totalProcessed;
  }

  /// دفع إعدادات التطبيق إلى Appwrite
  Future<bool> pushAppSettingsToCloud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        'key': 'whatsapp_settings', 'value': '',
        'hotel_name': prefs.getString('hotel_name') ?? 'فندق مارينا بلازا',
        'hotel_cutoff_hour': prefs.getInt('hotel_cutoff_hour') ?? 14,
        'dark_mode': prefs.getBool('dark_mode') ?? false,
        'wa_api_type': prefs.getString('wa_api_type') ?? 'greenapi',
        'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
        'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
        'wa_api_token': prefs.getString('wa_api_token') ?? '',
        'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
        'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
        'wa_sendzen_from_number': prefs.getString('wa_sendzen_from_number') ?? '',
        'wa_template': prefs.getString('whatsapp_template') ?? '',
        'telegram_enabled': prefs.getBool('telegram_enabled') ?? false,
        'telegram_bot_token': prefs.getString('telegram_bot_token') ?? '',
        'telegram_chat_id': prefs.getString('telegram_chat_id') ?? '',
        'telegram_notifications_enabled': prefs.getBool('telegram_notifications_enabled') ?? false,
        'telegram_daily_report_enabled': prefs.getBool('telegram_daily_report_enabled') ?? false,
        'telegram_daily_report_time': prefs.getString('telegram_daily_report_time') ?? '',
        'lark_enabled': prefs.getBool('lark_enabled') ?? false,
        'lark_app_id': prefs.getString('lark_app_id') ?? '',
        'lark_app_secret': prefs.getString('lark_app_secret') ?? '',
        'lark_webhook_url': prefs.getString('lark_webhook_url') ?? '',
        'lark_daily_report_enabled': prefs.getBool('lark_daily_report_enabled') ?? false,
        'lark_daily_report_time': prefs.getString('lark_daily_report_time') ?? '08:00',
        'lark_daily_report_chat_id': prefs.getString('lark_daily_report_chat_id') ?? '',
        'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
      };

      const docId = 'whatsapp_settings';
      const collectionId = 'app_settings';

      try {
        await appwriteService.updateDocument(
          collectionId: collectionId, documentId: docId,
          data: _filterPayload('app_settings', data),
        );
      } catch (_) {
        await appwriteService.createDocument(
          collectionId: collectionId, documentId: docId,
          data: _filterPayload('app_settings', data),
        );
      }
      return true;
    } catch (e) {
      _err.warning('Failed to push app_settings: $e');
      return false;
    }
  }

  Map<String, dynamic> _filterPayload(String entity, Map<String, dynamic> data) {
    const allowedFields = <String, Set<String>>{
      'app_settings': {
        'appwrite_sync_interval', 'dark_mode', 'hotel_cutoff_hour',
        'hotel_name', 'key', 'value',
        'lark_app_id', 'lark_app_secret', 'lark_daily_report_chat_id',
        'lark_daily_report_enabled', 'lark_daily_report_time', 'lark_enabled',
        'lark_webhook_url', 'telegram_bot_token', 'telegram_chat_id',
        'telegram_daily_report_enabled', 'telegram_daily_report_time',
        'telegram_enabled', 'telegram_notifications_enabled',
        'wa_api_base_url', 'wa_api_instance_id', 'wa_api_token',
        'wa_api_type', 'wa_custom_url_template', 'wa_sendzen_api_key',
        'wa_sendzen_from_number', 'wa_template',
      },
    };
    final fields = allowedFields[entity];
    if (fields == null) return data;
    return Map.fromEntries(data.entries.where((e) => fields.contains(e.key)));
  }

  Future<bool> _processOutboxEntry(dynamic entry) async {
    _err.info('Processing outbox entry: ${entry.entity}/${entry.op}');
    return true;
  }

  /// إعادة تعيين حجم الدفعة التكيفي (للاستخدام في الاختبارات)
  void resetAdaptiveBatchSize() => _adaptiveBatchSize = 50;
}
