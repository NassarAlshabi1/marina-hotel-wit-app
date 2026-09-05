import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة رفع البيانات المحلية إلى Cloudflare D1 (نسخ احتياطي للقراءة فقط من
/// القاعدة المحلية — لا يمس حلقة مزامنة Appwrite إطلاقاً).
///
/// القيود المُثبتة تجريبياً على الحساب (مسبارات 2026-09-04/05):
/// - نقطة /query تقبل عبارات متعددة في نداء واحد لكن **بدون** params
///   (خطأ 7400: "params with multiple statements is not supported")؛
///   والنمط الحرفي نجح بـ 800 عبارة (187KB) في النداء الواحد (635ms) —
///   الرفع الموحد الآن عبارات حرفية بدفعة 200 (_statementBatch).
/// - compound SELECT (UNION) يفشل عند 6 عناصر — نتجنبه كلياً.
/// - الكتابة تتطلب توكناً بصلاحية كتابة وإلا رُفضت بـ SQLITE_AUTH؛
///   ومُثبت أن ALTER TABLE ADD COLUMN يُسمح به أحياناً بينما CREATE
///   TABLE يُرفض — لذا تُصالَح أعمدة الجداول الموجودة تلقائياً.
class CloudflareD1Service {
  CloudflareD1Service(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';

  /// ✅ تسريع الرفع (مُثبت تجريبياً على هذا الحساب 2026-09-05):
  /// النمط الحرفي (عبارات INSERT بلا معاملات، منضمة بـ ";\n") نجح بـ 800
  /// عبارة (187KB) في نداء واحد خلال 635ms — والزمن شبه ثابت من 50 حتى
  /// 800 عبارة (يقوده RTT لا الحجم). لذلك توحيد كل الجداول على النمط
  /// الحرفي بدفعة 200 عبارة (~46KB نموذجياً — هامش أمان كبير للصفوف
  /// العريضة) بدل نمط المعاملات الذي كان يرسل 96÷عدد الأعمدة صفاً
  /// لكل نداء (3-5 صفوف فقط للجداول المتزامنة → آلاف النداءات).
  static const int _statementBatch = 200;

  /// إعدادات الاتصال (الحساب/القاعدة/التوكن).
  CloudflareD1Config config;

  final http.Client _client;
  bool _cancelled = false;

  /// طلب إيقاف الرفع (يُفحص بين الدفعات).
  void cancel() => _cancelled = true;

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
    // إعادة محاولة واحدة عند أعطال الشبكة — آمنة لأن كل الكتابات
    // INSERT OR REPLACE (idempotent).
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
      tokenValid = (verify['result']?['status'] == 'active');
    } on CloudflareD1Exception catch (e) {
      // توكنات المستخدم (cfut_) تُفحص عبر نقطة /user/tokens/verify
      try {
        final verify = await _call('GET', '/user/tokens/verify');
        tokenValid = (verify['result']?['status'] == 'active');
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
      // DML: محاولة INSERT على جدول غير موجود — إن كان الخطأ "no such table"
      // فهذا يعني أن العبارة اجتازت طبقة التصريح (لا شيء يُكتب فعلياً).
      try {
        await _query('INSERT INTO _cf_probe_missing_table (a) VALUES (1)');
        dmlAllowed = true; // نظرياً لا يحدث — الجدول غير موجود
      } on CloudflareD1Exception catch (e) {
        final blob = '${e.message} ${e.details ?? ''}'.toLowerCase();
        if (blob.contains('no such table') || blob.contains('sqlite_error')) {
          dmlAllowed = true;
        } else {
          dmlError =
              '${e.message}${e.details != null ? ' — ${e.details}' : ''}';
        }
      }
      // DDL: إنشاء/حذف جدول اختبار حقيقي.
      try {
        await executeStatements(const [
          'CREATE TABLE IF NOT EXISTS _cf_write_probe (id INTEGER)',
          'DROP TABLE IF EXISTS _cf_write_probe',
        ]);
        ddlAllowed = true;
      } on CloudflareD1Exception catch (_) {
        ddlAllowed = false; // ليس قاتلاً — المخطط موجود مسبقاً في D1
      }
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

  /// رفع الجداول المحددة إلى D1 (مخطط + بيانات) بأسلوب INSERT OR REPLACE
  /// — الإعادة آمنة (idempotent) ولا تحذف أي سجل بعيد غير موجود محلياً.
  Future<CloudflareD1UploadResult> uploadData({
    required List<CloudflareD1SourceTable> tables,
    String? deviceLabel,
    void Function(CloudflareD1Progress progress)? onProgress,
  }) async {
    _cancelled = false;
    final sw = Stopwatch()..start();
    var rowsUploaded = 0;
    final errors = <String>[];
    final warnings = <String>[];
    final doneTables = <String>[];
    var callCount = 0;

    // 1) نقل المخطط (CREATE ... IF NOT EXISTS) — قد يُرفض DDL بصلاحية
    //    قراءة فقط؛ هذا ليس قاتلاً لأن مخطط D1 موجود مسبقاً، والجداول
    //    الغائبة ستُرصد كأخطاء لكل جدول في مرحلة البيانات.
    final ddl = <String>[];
    for (final t in tables) {
      for (final s in t.createSqlList) {
        final rewritten = _toIfNotExists(s);
        if (rewritten != null) ddl.add(rewritten);
      }
    }
    for (var i = 0; i < ddl.length; i += 40) {
      if (_cancelled) break;
      final chunk = ddl.sublist(i, (i + 40).clamp(0, ddl.length));
      try {
        await executeStatements(chunk);
        callCount++;
      } on CloudflareD1Exception catch (e) {
        warnings.add('تخطي نقل المخطط (DDL): ${e.message}');
        break; // DDL محجوب — لا داعي لمحاولة الدفعات الباقية
      }
    }

    // 2) بيانات الجداول.
    final totalTables = tables.length;
    for (var ti = 0; ti < totalTables; ti++) {
      if (_cancelled) break;
      final t = tables[ti];
      onProgress?.call(
        CloudflareD1Progress(
          stage: 'نقل المخطط والبيانات',
          currentTable: t.name,
          tableIndex: ti,
          tableCount: totalTables,
          rowsDone: 0,
          rowsTotal: t.rowCount,
        ),
      );

      if (t.rowCount == 0) {
        doneTables.add(t.name);
        continue;
      }

      try {
        var offset = 0;
        List<Map<String, Object?>>? firstChunk;
        List<String> columns = const [];
        var rowsForTable = 0;
        // عدد الأعمدة يُستنتج من أول دفعة (أسماء الأعمدة من SELECT *).
        while (offset < t.rowCount) {
          if (_cancelled) break;
          final chunk = await t.readChunk(_chunkSize, offset);
          if (chunk.isEmpty) break;
          firstChunk ??= chunk;
          if (columns.isEmpty) {
            columns = firstChunk.first.keys.toList();
            // مصالحة المخطط قبل أول INSERT: أعمدة محلية غائبة عن D1 تُضاف
            // بـ ALTER (مخطط D1 قد يكون أقدم من المخطط المحلي).
            await _reconcileSchema(t, columns, warnings);
          }
          final colCount = columns.length;
          if (colCount <= 0) {
            offset += chunk.length;
            continue;
          }
          // نمط موحد لكل الجداول: عبارات INSERT OR REPLACE حرفية بلا
          // معاملات — دفعات _statementBatch في النداء الواحد (مُثبت أعلاه).
          final statements = <String>[];
          for (final row in chunk) {
            final values = columns.map((c) => _sqlLiteral(row[c])).join(',');
            statements.add(
              'INSERT OR REPLACE INTO "${_quoteIdent(t.name)}" '
              '(${columns.map(_quoteIdent).join(',')}) VALUES ($values)',
            );
          }
          for (var i = 0; i < statements.length; i += _statementBatch) {
            if (_cancelled) break;
            final end = (i + _statementBatch).clamp(0, statements.length);
            await executeStatements(statements.sublist(i, end));
            callCount++;
            rowsForTable += end - i;
            onProgress?.call(
              CloudflareD1Progress(
                stage: 'رفع البيانات',
                currentTable: t.name,
                tableIndex: ti,
                tableCount: totalTables,
                rowsDone: rowsForTable,
                rowsTotal: t.rowCount,
              ),
            );
          }
          offset += chunk.length;
        }
        rowsUploaded += rowsForTable;
        doneTables.add(t.name);
      } on CloudflareD1Exception catch (e) {
        errors.add(
          '${t.name}: ${e.message}${e.details != null ? ' — ${e.details}' : ''}',
        );
      }
    }

    // 3) كتابة سجل metadata آخر عملية رفع.
    if (!_cancelled && errors.isEmpty && doneTables.isNotEmpty) {
      try {
        await executeStatements(const [
          'CREATE TABLE IF NOT EXISTS _cf_backup_meta ('
              'id INTEGER PRIMARY KEY CHECK (id = 1), '
              'uploaded_at TEXT NOT NULL, '
              'tables_count INTEGER NOT NULL, '
              'rows_count INTEGER NOT NULL, '
              'device_label TEXT)',
        ]);
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final label = _sqlLiteral(deviceLabel ?? '');
        await executeStatements([
          "INSERT OR REPLACE INTO _cf_backup_meta "
              "(id, uploaded_at, tables_count, rows_count, device_label) "
              "VALUES (1, '$nowIso', ${doneTables.length}, $rowsUploaded, $label)",
        ]);
        callCount++;
      } on CloudflareD1Exception catch (e) {
        errors.add('_cf_backup_meta: ${e.message}');
      }
    }

    sw.stop();
    return CloudflareD1UploadResult(
      ok: errors.isEmpty && !_cancelled,
      cancelled: _cancelled,
      tablesDone: doneTables.length,
      rowsUploaded: rowsUploaded,
      apiCalls: callCount,
      errors: errors,
      warnings: warnings,
      elapsed: sw.elapsed,
    );
  }

  static const int _chunkSize = 1000;

  // ════════════════════════════════════════════════════════════════
  //  مصالحة المخطط (Schema Reconciliation)
  // ════════════════════════════════════════════════════════════════

  /// أعمدة جدول في D1 عبر pragma_table_info (مُثبت أنه يعمل على D1).
  Future<List<String>> _d1TableColumns(String table) async {
    final safe = table.replaceAll("'", "''");
    final sets = await _query("SELECT name FROM pragma_table_info('$safe')");
    if (sets.isEmpty) return const <String>[];
    final rows = (sets.first['results'] as List?) ?? const [];
    return rows.map((r) => (r as Map)['name'].toString()).toList();
  }

  /// قبل رفع بيانات الجدول: إن كانت أعمدة محلية غائبة عن D1 (مخطط D1
  /// أقدم من المحلي) تُضاف بـ ALTER TABLE ADD COLUMN مشتقة من DDL الجهاز
  /// المحلي نفسه — بلا تصلّب ولا تخمين.
  ///
  /// مُثبت تجريبياً على هذا الحساب (2026-09-05): ALTER TABLE ADD COLUMN
  /// يُسمح به لتوكن بصلاحية DML فقط بينما CREATE TABLE يُرفض بـ SQLITE_AUTH
  /// — لذا الجداول الغائبة كلياً تُنشأ فقط عبر مرحلة DDL أعلاه.
  Future<void> _reconcileSchema(
    CloudflareD1SourceTable t,
    List<String> columns,
    List<String> warnings,
  ) async {
    try {
      final d1Cols = await _d1TableColumns(t.name);
      // قائمة فارغة = الجدول غير موجود أصلاً؛ تُنشئه مرحلة DDL.
      if (d1Cols.isEmpty) return;
      final missing = columns.where((c) => !d1Cols.contains(c)).toList();
      if (missing.isEmpty) return;
      String? createSql;
      for (final s in t.createSqlList) {
        if (s.trim().toUpperCase().startsWith('CREATE TABLE')) {
          createSql = s;
          break;
        }
      }
      if (createSql == null) return;
      final frags = _columnFragments(createSql);
      final alters = <String>[];
      for (final c in missing) {
        final raw = frags[c];
        if (raw == null) continue;
        final add = _toAddColumnFragment(raw);
        if (add == null) continue;
        alters.add('ALTER TABLE "${_quoteIdent(t.name)}" ADD COLUMN "$c" $add');
      }
      if (alters.isEmpty) return;
      for (var i = 0; i < alters.length; i += 40) {
        await executeStatements(
          alters.sublist(i, (i + 40).clamp(0, alters.length)),
        );
      }
      warnings.add(
        'مصالحة مخطط: أُضيف ${alters.length} عموداً غائباً في ${t.name}',
      );
    } on CloudflareD1Exception catch (e) {
      // بلا صلاحية كتابة: يُسجّل تحذيراً ويفشل الجدول المتأثر بخطأ واضح.
      warnings.add('تعذر مصالحة مخطط ${t.name}: ${e.message}');
    }
  }

  /// استخراج تعريفات الأعمدة من CREATE TABLE محلي (اسم → نص التعريف).
  /// قيود الجدول (PRIMARY KEY/UNIQUE/CHECK/FOREIGN KEY) تُتجاهل لأنها
  /// لا تبدأ باسم عمود مقتبس.
  static Map<String, String> _columnFragments(String createSql) {
    final open = createSql.indexOf('(');
    final close = createSql.lastIndexOf(')');
    if (open < 0 || close <= open) return const <String, String>{};
    final body = createSql.substring(open + 1, close);
    final frags = <String, String>{};
    final buffer = StringBuffer();
    var depth = 0;
    var inQuote = false;
    void flush() {
      final f = buffer.toString().trim();
      buffer.clear();
      if (f.isEmpty) return;
      final m = RegExp(r'^"([^"]+)"\s+(.*)$', dotAll: true).firstMatch(f);
      if (m != null) frags[m.group(1)!] = m.group(2)!.trim();
    }

    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == "'") inQuote = !inQuote;
      if (inQuote) {
        buffer.write(ch);
        continue;
      }
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      } else if (ch == ',' && depth == 0) {
        flush();
        continue;
      }
      buffer.write(ch);
    }
    flush();
    return frags;
  }

  /// تجهيز تعريف عمود لـ ADD COLUMN: تجريد ما يرفضه SQLite في ALTER
  /// (PRIMARY KEY/UNIQUE/REFERENCES، وNOT NULL بلا DEFAULT).
  /// القيم الفعلية تُرفع دائماً لكل الأعمدة NOT NULL فلا فقدان بيانات.
  static String? _toAddColumnFragment(String fragment) {
    var f = fragment
        .replaceFirst(RegExp(r'\bPRIMARY\s+KEY\b', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\bUNIQUE\b', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'\bREFERENCES\b.*$', caseSensitive: false, dotAll: true),
          '',
        )
        .trim();
    final hasDefault = RegExp(r'\bDEFAULT\b', caseSensitive: false).hasMatch(f);
    final hasNotNull = RegExp(
      r'\bNOT\s+NULL\b',
      caseSensitive: false,
    ).hasMatch(f);
    if (hasNotNull && !hasDefault) {
      f = f.replaceFirst(RegExp(r'\bNOT\s+NULL\b', caseSensitive: false), '');
    }
    f = f.replaceAll(RegExp(r'\s+'), ' ').trim();
    return f.isEmpty ? null : f;
  }

  // ════════════════════════════════════════════════════════════════
  //  أدوات مساعدة
  // ════════════════════════════════════════════════════════════════

  static String _quoteIdent(String name) => name.replaceAll('"', '""');

  /// تحويل قيمة SQLite خام إلى literal آمن (للجداول العريضة فقط).
  static String _sqlLiteral(Object? v) {
    if (v == null) return 'NULL';
    if (v is int) return v.toString();
    if (v is double) {
      if (v.isNaN || v.isInfinite) return 'NULL'; // SQLite لا يدعم NaN/Inf
      return v.toString();
    }
    if (v is bool) return v ? '1' : '0';
    if (v is Uint8List) {
      return "X'${v.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'";
    }
    if (v is List<int>) {
      return "X'${v.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'";
    }
    final s = v.toString().replaceAll("'", "''");
    return "'$s'";
  }

  /// إعادة صياغة CREATE → CREATE ... IF NOT EXISTS (للجداول والفهارس).
  static String? _toIfNotExists(String ddl) {
    final m = RegExp(
      r'^\s*CREATE\s+(TABLE|UNIQUE\s+INDEX|INDEX|VIEW|TRIGGER)\s+(IF\s+NOT\s+EXISTS\s+)?',
      caseSensitive: false,
    ).firstMatch(ddl);
    if (m == null) return null; // DDL غير مدعوم — تجاهل بأمان
    if (m.group(2) != null) return ddl.trim();
    return 'CREATE ${m.group(1)!} IF NOT EXISTS ${ddl.substring(m.end)}'.trim();
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
    this.createSqlList = const [],
    required this.readChunk,
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
