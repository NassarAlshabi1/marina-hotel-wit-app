import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloudflare_config.dart';

/// خدمة رفع البيانات المحلية إلى Cloudflare D1 (نسخ احتياطي للقراءة فقط من
/// القاعدة المحلية — لا يمس حلقة مزامنة Appwrite إطلاقاً).
///
/// القيود المُثبتة تجريبياً على الحساب (مسبارات 2026-09-04):
/// - حد المعاملات: 100 لكل استعلام (99 ✓ 100 ✓ 101 ✗) — نستخدم ≤ 96 هامشاً.
/// - نقطة /query تقبل عبارات متعددة في نداء واحد لكن **بدون** params
///   (خطأ 7400: "params with multiple statements is not supported").
/// - compound SELECT (UNION) يفشل عند 6 عناصر — نتجنبه كلياً.
/// - الكتابة تتطلب توكناً بصلاحية D1 Edit وإلا رُفضت بـ SQLITE_AUTH.
class CloudflareD1Service {
  CloudflareD1Service(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';
  static const int maxParamsPerQuery = 100; // مُثبت تجريبياً
  static const int _paramSafetyMargin = 4;
  static const int paramsBudget = maxParamsPerQuery - _paramSafetyMargin; // 96

  /// إعدادات الاتصال (الحساب/القاعدة/التوكن).
  CloudflareD1Config config;

  final http.Client _client;

  // ════════════════════════════════════════════════════════════════
  //  طبقة HTTP
  // ════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Authorization': 'Bearer ${config.apiToken}',
      'Content-Type': 'application/json',
    };
    // إعادة محاولة واحدة عند أعطال الشبكة. مستخدمو هذه الطبقة في هذا
    // المسار تشخيصات قراءة فقط؛ الكتابة المباشرة معطلة أدناه.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final http.Response resp;
        if (method == 'GET') {
          resp = await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 90));
        } else {
          resp = await _client
              .post(
                uri,
                headers: headers,
                body: jsonEncode(body ?? <String, dynamic>{}),
              )
              .timeout(const Duration(seconds: 120));
        }
        final decoded =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        if (decoded['success'] != true) {
          final errors = decoded['errors'];
          throw CloudflareD1Exception(
            'فشل نداء Cloudflare (HTTP ${resp.statusCode})',
            details: errors?.toString(),
          );
        }
        return decoded;
      } on CloudflareD1Exception {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt == 0) continue;
      }
    }
    throw CloudflareD1Exception(
      'تعذر الاتصال بـ Cloudflare',
      details: lastError?.toString(),
    );
  }

  /// تنفيذ SQL وإرجاع كل مجموعات النتائج (متعددة العبارات → مجموعات متعددة).
  Future<List<Map<String, dynamic>>> _query(
    String sql, {
    List<Object?>? params,
  }) async {
    final body = <String, dynamic>{'sql': sql};
    if (params != null) body['params'] = params;
    final decoded = await _call(
      'POST',
      '/accounts/${config.accountId}/d1/database/${config.databaseId}/query',
      body: body,
    );
    final result = decoded['result'];
    if (result is List) {
      return result.cast<Map<String, dynamic>>();
    }
    return const <Map<String, dynamic>>[];
  }

  /// تنفيذ عبارات متعددة بلا معاملات في نداء واحد (نمط مُثبت أنه يعمل).
  Future<void> executeStatements(List<String> statements) async {
    if (statements.isEmpty) return;
    await _query(statements.join(';\n'));
  }

  // ════════════════════════════════════════════════════════════════
  //  الفحص والاكتشاف
  // ════════════════════════════════════════════════════════════════

  /// فحص التوكن + الوصول للقاعدة + صلاحيات الكتابة.
  ///
  /// مُثبت تجريبياً على هذا الحساب: DML (INSERT/UPDATE/DELETE) مصرّح به
  /// بينما DDL (CREATE TABLE) قد يُرفض بـ SQLITE_AUTH حسب صلاحية التوكن.
  /// لذلك الفحص يفصل بينهما: صلاحية DML كافية للرفع الكامل ما دام
  /// المخطط موجوداً في D1 (وهو موجود مسبقاً في marina-hotel-db).
  Future<CloudflareD1ProbeResult> probe() async {
    var tokenValid = false;
    var accountReachable = false;
    var databaseReachable = false;
    String? databaseName;
    var dmlAllowed = false;
    var ddlAllowed = false;
    String? dmlError;
    String? fatalError;
    final databases = <CloudflareD1DatabaseInfo>[];

    try {
      final verify = await _call(
        'GET',
        '/accounts/${config.accountId}/tokens/verify',
      );
      tokenValid =
          ((verify['result'] as Map<String, dynamic>?)?['status'] == 'active');
    } on CloudflareD1Exception catch (e) {
      // توكنات المستخدم (cfut_) تُفحص عبر نقطة /user/tokens/verify
      try {
        final verify = await _call('GET', '/user/tokens/verify');
        tokenValid =
            ((verify['result'] as Map<String, dynamic>?)?['status'] ==
            'active');
      } catch (e2) {
        fatalError = 'التوكن غير صالح: ${e.message} / $e2';
        return CloudflareD1ProbeResult(
          tokenValid: false,
          accountReachable: false,
          databaseReachable: false,
          databaseName: null,
          dmlAllowed: false,
          ddlAllowed: false,
          dmlError: null,
          databases: databases,
          fatalError: fatalError,
        );
      }
    }

    try {
      final list = await _call(
        'GET',
        '/accounts/${config.accountId}/d1/database?per_page=50',
      );
      accountReachable = true;
      final result = list['result'];
      final rows = (result is Map ? result['results'] : result) as List?;
      for (final row in (rows ?? const [])) {
        if (row is Map) {
          databases.add(
            CloudflareD1DatabaseInfo(
              uuid: row['uuid']?.toString() ?? '',
              name: row['name']?.toString() ?? '',
              fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
            ),
          );
          if (row['uuid']?.toString() == config.databaseId) {
            databaseReachable = true;
            databaseName = row['name']?.toString();
          }
        }
      }
    } on CloudflareD1Exception catch (e) {
      fatalError ??= 'تعذر عرض قواعد D1: ${e.message}';
    }

    if (databaseReachable) {
      // تشخيص اتصال للقراءة فقط. لا نستنتج صلاحيات DML/DDL ولا ننشئ
      // جداول مسبار، لأن مجرد فحص الإعدادات يجب ألا يغيّر D1.
      try {
        await _query('SELECT 1 AS ok');
      } on CloudflareD1Exception catch (e) {
        fatalError =
            'تعذر تنفيذ فحص القراءة: ${e.message}'
            '${e.details != null ? ' — ${e.details}' : ''}';
      }
      dmlAllowed = false;
      ddlAllowed = false;
      dmlError = 'الكتابة الإدارية المباشرة معطّلة؛ استخدم Worker sync';
    }

    return CloudflareD1ProbeResult(
      tokenValid: tokenValid,
      accountReachable: accountReachable,
      databaseReachable: databaseReachable,
      databaseName: databaseName,
      dmlAllowed: dmlAllowed,
      ddlAllowed: ddlAllowed,
      dmlError: dmlError,
      databases: databases,
      fatalError: fatalError,
    );
  }

  /// أسماء الجداول الموجودة في D1 (لمقارنة التغطية مع الجداول المحلية).
  Future<List<String>> listD1Tables() async {
    final sets = await _query(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    if (sets.isEmpty) return const <String>[];
    final rows = (sets.first['results'] as List?) ?? const [];
    return rows.map((r) => (r as Map)['name'].toString()).toList();
  }

  // ════════════════════════════════════════════════════════════════
  //  الرفع
  // ════════════════════════════════════════════════════════════════

  /// الرفع الإداري المباشر إلى D1 معطّل نهائياً.
  ///
  /// كان هذا المسار يكتب `INSERT OR REPLACE` خارج عقد المزامنة، ولذلك كان
  /// يستطيع استبدال صف أحدث وحذف معلومات الساعة المتجهة/الإصدار. الكتابة
  /// السحابية المسموحة تمر حصراً عبر CloudflareD1PushMirror وWorker sync.
  /// يفشل هذا الأسلوب قبل قراءة الجداول أو توليد SQL أو إجراء أي طلب HTTP.
  Future<CloudflareD1UploadResult> uploadData({
    required List<CloudflareD1SourceTable> tables,
    String? deviceLabel,
    void Function(CloudflareD1Progress progress)? onProgress,
  }) {
    throw UnsupportedError(
      'الرفع المباشر إلى D1 معطّل لحماية سلامة البيانات؛ '
      'استخدم مزامنة Worker الآمنة.',
    );
  }

  /// تحويل صف shift_notes موسوم created_by='blacklist' إلى صف بأعمدة
  /// جدول blacklist في D1 (worker/schema.sql — نفس اتجاه مسار المزامنة:
  /// outbox entity='blacklist' → جدول blacklist).
  ///
  /// تخزين القائمة السوداء المحلي (repositories/blacklist_repository.dart):
  /// الاسم في `title` وبقية الحقول JSON في `content`. القيم الافتراضية
  /// مطابقة لسلوك المستودع (reportedBy='police'، active=true). الأعمدة
  /// السحابية القديمة (guest_name/guest_phone/guest_id_number/is_active/
  /// added_date/added_by) تُترك لقيم D1 الافتراضية كما يفعل payload
  /// المزامنة الذي لا يحملها.
  static Map<String, Object?> blacklistRowFromShiftNote(
    Map<String, Object?> row,
  ) {
    Map<String, dynamic> payload = const <String, dynamic>{};
    final raw = row['content'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {
        // محتوى غير صالح — تُعتمد القيم الافتراضية (نفس سلوك المستودع).
      }
    }
    final active = payload['active'] is bool ? payload['active'] as bool : true;
    return <String, Object?>{
      'local_uuid': row['local_uuid'],
      'name': row['title'],
      'nationality': payload['nationality'] as String? ?? '',
      'national_id': payload['nationalId'] as String?,
      'phone': payload['phone'] as String?,
      'reason': payload['reason'] as String?,
      'notes': payload['notes'] as String?,
      'reported_by': payload['reportedBy'] as String? ?? 'police',
      'active': active ? 1 : 0,
      'server_id': row['server_id'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
      'deleted_at': row['deleted_at'],
      'last_modified': row['last_modified'],
      'created_at_iso': row['created_at_iso'],
      'updated_at_iso': row['updated_at_iso'],
      'deleted_at_iso': row['deleted_at_iso'],
      'created_at_epoch': row['created_at_epoch'],
      'last_modified_epoch': row['last_modified_epoch'],
      'version': row['version'],
      'origin': row['origin'],
      'vector_clock': row['vector_clock'],
      'device_id': row['device_id'],
      'idempotency_key': row['idempotency_key'],
    };
  }

  /// استعلام مصدر صفوف القائمة السوداء من التخزين المحلي (shift_notes
  /// الموسومة) — يُستخدم في تبويب الرفع ومسار الترحيل الشامل.
  static const String blacklistSourceSql =
      "SELECT * FROM shift_notes WHERE created_by = 'blacklist'";

  /// استعلام مصدر صفوف shift_notes الحقيقية (مطابقة مجموعة shift_notes
  /// في Appwrite Cloud) — يستبعد صفوف القائمة السوداء لأن المزامنة
  /// ترسلها ككيان blacklist منفصل (blacklist_repository.dart يُنشئ
  /// outbox entity='blacklist' فقط).
  static const String shiftNotesSourceSql =
      "SELECT * FROM shift_notes WHERE created_by != 'blacklist'";

  /// الاتجاه العكسي (سحب): تحويل صف blacklist من D1 إلى صف shift_notes
  /// موسوم created_by='blacklist' — يُستخدم في _applyChange عند سحب
  /// كيان 'blacklist' لأن القائمة السوداء بلا جدول Drift محلي.
  ///
  /// المرآة الكاملة لـ blacklistRowFromShiftNote: الاسم يرجع إلى `title`
  /// وحقول JSON ترجع إلى `content`، وأعمدة SyncFields تُمرر كما هي
  /// (local_uuid نفسه يربط الصفين عبر الاتجاهين). يعيد null إذا كان
  /// الصف بلا local_uuid (لا يمكن تطبيقه محلياً).
  static Map<String, Object?>? blacklistShiftNoteRowFromD1(
    Map<String, Object?> record,
  ) {
    final localUuid = record['local_uuid'];
    if (localUuid is! String || localUuid.isEmpty) return null;

    final content = jsonEncode(<String, Object?>{
      'nationality': record['nationality'],
      'nationalId': record['national_id'],
      'phone': record['phone'],
      'reason': record['reason'],
      'notes': record['notes'],
      'reportedBy': record['reported_by'],
      'active': record['active'] == null
          ? true
          : (record['active'] as num? ?? 1) != 0,
    });

    return <String, Object?>{
      'local_uuid': localUuid,
      'title': (record['name'] as String?) ?? '',
      'content': content,
      'priority': 'medium',
      'shift_type': 'all',
      'is_read': 0,
      'expires_at': null,
      'created_by': CloudflareConfig.blacklistStorageTag,
      'server_id': record['server_id'],
      'created_at': record['created_at'],
      'updated_at': record['updated_at'],
      'deleted_at': record['deleted_at'],
      'last_modified': record['last_modified'],
      'created_at_iso': record['created_at_iso'],
      'updated_at_iso': record['updated_at_iso'],
      'deleted_at_iso': record['deleted_at_iso'],
      'created_at_epoch': record['created_at_epoch'],
      'last_modified_epoch': record['last_modified_epoch'],
      'version': record['version'],
      'origin': record['origin'],
      'vector_clock': record['vector_clock'],
      'device_id': record['device_id'],
      'idempotency_key': record['idempotency_key'],
    };
  }
}

// ══════════════════════════════════════════════════════════════════
//  النماذج
// ══════════════════════════════════════════════════════════════════

class CloudflareD1Config {
  const CloudflareD1Config({
    required this.accountId,
    required this.databaseId,
    required this.apiToken,
  });

  final String accountId;
  final String databaseId;
  final String apiToken;

  bool get isComplete =>
      accountId.trim().isNotEmpty &&
      databaseId.trim().isNotEmpty &&
      apiToken.trim().isNotEmpty;
}

class CloudflareD1DatabaseInfo {
  const CloudflareD1DatabaseInfo({
    required this.uuid,
    required this.name,
    required this.fileSize,
  });

  final String uuid;
  final String name;
  final int fileSize;
}

class CloudflareD1ProbeResult {
  const CloudflareD1ProbeResult({
    required this.tokenValid,
    required this.accountReachable,
    required this.databaseReachable,
    required this.databaseName,
    required this.dmlAllowed,
    required this.ddlAllowed,
    required this.dmlError,
    required this.databases,
    this.fatalError,
  });

  final bool tokenValid;
  final bool accountReachable;
  final bool databaseReachable;
  final String? databaseName;

  /// صلاحية INSERT/UPDATE/DELETE — الكافية للرفع الكامل.
  final bool dmlAllowed;

  /// صلاحية CREATE/DROP — مطلوبة فقط لإضافة جداول جديدة غير موجودة في D1.
  final bool ddlAllowed;
  final String? dmlError;
  final List<CloudflareD1DatabaseInfo> databases;
  final String? fatalError;
}

class CloudflareD1Progress {
  const CloudflareD1Progress({
    required this.stage,
    required this.currentTable,
    required this.tableIndex,
    required this.tableCount,
    required this.rowsDone,
    required this.rowsTotal,
  });

  final String stage;
  final String currentTable;
  final int tableIndex;
  final int tableCount;
  final int rowsDone;
  final int rowsTotal;

  double get tableFraction => tableCount == 0
      ? 0
      : ((tableIndex + (rowsTotal > 0 ? (rowsDone / rowsTotal) : 1)) /
            tableCount);
}

class CloudflareD1UploadResult {
  const CloudflareD1UploadResult({
    required this.ok,
    required this.cancelled,
    required this.tablesDone,
    required this.rowsUploaded,
    required this.apiCalls,
    required this.errors,
    required this.warnings,
    required this.elapsed,
  });

  final bool ok;
  final bool cancelled;
  final int tablesDone;
  final int rowsUploaded;
  final int apiCalls;
  final List<String> errors;
  final List<String> warnings;
  final Duration elapsed;
}

class CloudflareD1Exception implements Exception {
  CloudflareD1Exception(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() =>
      'CloudflareD1Exception: $message${details != null ? ' ($details)' : ''}';
}

/// جدول مصدر مجرد عن قاعدة drift — تُنشئه الشاشة من AppDatabase.
class CloudflareD1SourceTable {
  const CloudflareD1SourceTable({
    required this.name,
    required this.rowCount,
    required this.readChunk,
    this.createSqlList = const [],
  });

  final String name;
  final int rowCount;

  /// CREATE TABLE/INDEX من sqlite_master المحلي (تُنقل بصيغة IF NOT EXISTS).
  final List<String> createSqlList;

  /// قراءة دفعة صفوف (خام بنمط SQLite: int/double/String/Uint8List/null).
  final Future<List<Map<String, Object?>>> Function(int limit, int offset)
  readChunk;
}

// ══════════════════════════════════════════════════════════════════
//  تخزين الإعدادات: التوكن في Secure Storage والمعرفات في Prefs
// ══════════════════════════════════════════════════════════════════

class CloudflareD1Settings {
  static const _tokenKey = 'cf_d1_api_token';
  static const _accountKey = 'cf_d1_account_id';
  static const _databaseKey = 'cf_d1_database_id';
  static const _deviceLabelKey = 'cf_d1_device_label';

  /// القيم المعروفة من الحساب (تُستخدم كقيم ابتدائية للحقول فقط).
  static const String knownAccountId = '81a73bba9acc1de5693ff929d0a372ce';
  static const String knownDatabaseId = '607f1090-83b1-4281-975f-d81b8f6154e7';

  static const _secure = FlutterSecureStorage();

  static Future<CloudflareD1Config> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _secure.read(key: _tokenKey);
    return CloudflareD1Config(
      accountId: prefs.getString(_accountKey) ?? knownAccountId,
      databaseId: prefs.getString(_databaseKey) ?? knownDatabaseId,
      apiToken: token ?? '',
    );
  }

  static Future<void> save(
    CloudflareD1Config config, {
    String? deviceLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, config.accountId.trim());
    await prefs.setString(_databaseKey, config.databaseId.trim());
    if (config.apiToken.trim().isEmpty) {
      await _secure.delete(key: _tokenKey);
    } else {
      await _secure.write(key: _tokenKey, value: config.apiToken.trim());
    }
    if (deviceLabel != null) {
      await prefs.setString(_deviceLabelKey, deviceLabel);
    }
  }

  static Future<String> deviceLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceLabelKey) ?? '';
  }
}
