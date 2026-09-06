import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/repository_providers.dart';
import '../../../../services/cloudflare_config.dart';
import '../../../../services/cloudflare_d1_service.dart';
import '../../../../services/daos/outbox_dao.dart';
import '../../../../widgets/cloudflare_auto_connection_card.dart';

/// تبويب رفع بيانات جداول المزامنة (المطابقة لمجموعات Appwrite Cloud)
/// إلى Cloudflare D1.
///
/// المسار للقراءة فقط من القاعدة المحلية (SELECT) ثم INSERT OR REPLACE
/// إلى D1 — لا يمس حلقة مزامنة Appwrite ولا يحذف أي سجل بعيد.
/// النطاق: [CloudflareConfig.d1BackupTables] = كيانات النطاق الافتراضي
/// للمزامنة حصراً (migrationOrder — 24 كياناً بتأكيد المستخدم
/// 2026-09-05 الذي أضاف user_app/app_users ثم devices)، ومعها يُجسَّد كيان
/// blacklist افتراضياً من shift_notes الموسومة created_by='blacklist'
/// عبر CloudflareD1Service.blacklistRowFromShiftNote (لا جدول Drift
/// محلي له). app_users له جدول Drift محلي (schemaVersion 66) فيمرّ
/// كأي جدول فيزيائي. hotel_day_ledger جدول محلي-فقط (تأكيد المستخدم)
/// وجداول البنية المحلية — كلها مستبعدة.
/// القيود المطبقة (مثبتة تجريبياً): ≤ 96 معاملاً لكل استعلام،
/// وعبارات متعددة بلا معاملات في النداء الواحد.
class CloudflareD1Tab extends ConsumerStatefulWidget {
  const CloudflareD1Tab({super.key});

  /// ✅ حصر نطاق الرفع على [CloudflareConfig.d1BackupTables] = كيانات
  /// النطاق الافتراضي للمزامنة حصراً (migrationOrder — نفس
  /// ENTITY_TABLES في worker/src/database.ts).
  ///
  /// أي جدول محلي بلا مقابل في النطاق (outbox، sync_remote_meta،
  /// sync_state، sync_log، hotel_day_ledger المحلي-فقط بتأكيد
  /// المستخدم 2026-09-05، custom_list_items، جداول Room
  /// الداخلية…) يُستبعد هنا، وكيان blacklist (بلا جدول محلي)
  /// يُتخطى في الفلترة الفيزيائية — ويُجسَّد افتراضياً من
  /// shift_notes الموسومة في [_loadLocalTables]. app_users له جدول
  /// محلي (AppUsers، schemaVersion 66) فيمرّ في الفلترة الفيزيائية.
  @visibleForTesting
  static List<String> scopeSyncTables(Iterable<String> existingTables) {
    final existing = existingTables.toSet();
    return CloudflareConfig.d1BackupTables.where(existing.contains).toList();
  }

  @override
  ConsumerState<CloudflareD1Tab> createState() => _CloudflareD1TabState();
}

class _LocalTableInfo {
  _LocalTableInfo({
    required this.name,
    required this.rowCount,
    required this.createSqlList,
  });

  final String name;
  final int rowCount;
  final List<String> createSqlList;
}

class _CloudflareD1TabState extends ConsumerState<CloudflareD1Tab> {
  final _accountIdCtrl = TextEditingController();
  final _databaseIdCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _deviceLabelCtrl = TextEditingController();

  bool _obscureToken = true;
  bool _loadingSettings = true;
  bool _probing = false;
  bool _loadingTables = false;
  bool _uploading = false;

  CloudflareD1ProbeResult? _probeResult;
  List<String>? _d1Tables;
  List<_LocalTableInfo> _localTables = const [];
  final Set<String> _selected = <String>{};

  double _progress = 0;
  String _stage = '';
  final List<String> _logs = <String>[];
  CloudflareD1UploadResult? _result;
  CloudflareD1Service? _activeService;
  int _outboxPending = 0;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
    _loadLocalTables();
    _loadOutboxInfo();
  }

  @override
  void dispose() {
    _accountIdCtrl.dispose();
    _databaseIdCtrl.dispose();
    _tokenCtrl.dispose();
    _deviceLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreSettings() async {
    final cfg = await CloudflareD1Settings.load();
    final label = await CloudflareD1Settings.deviceLabel();
    if (!mounted) return;
    setState(() {
      _accountIdCtrl.text = cfg.accountId;
      _databaseIdCtrl.text = cfg.databaseId;
      _tokenCtrl.text = cfg.apiToken;
      _deviceLabelCtrl.text = label;
      _loadingSettings = false;
    });
  }

  Future<void> _loadOutboxInfo() async {
    try {
      final db = ref.read(databaseProvider);
      final pending = await OutboxDao(db).countUndeliveredToPrimary();
      if (!mounted) return;
      setState(() => _outboxPending = pending);
    } catch (_) {
      // معلومة استشارية فقط — لا تعطل الشاشة
    }
  }

  Future<void> _save() async {
    await CloudflareD1Settings.save(
      CloudflareD1Config(
        accountId: _accountIdCtrl.text.trim(),
        databaseId: _databaseIdCtrl.text.trim(),
        apiToken: _tokenCtrl.text.trim(),
      ),
      deviceLabel: _deviceLabelCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات Cloudflare D1')),
    );
  }

  CloudflareD1Config get _config => CloudflareD1Config(
    accountId: _accountIdCtrl.text.trim(),
    databaseId: _databaseIdCtrl.text.trim(),
    apiToken: _tokenCtrl.text.trim(),
  );

  Future<void> _probe() async {
    if (!_config.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أكمل الحقول: معرف الحساب ومعرف القاعدة والتوكن'),
        ),
      );
      return;
    }
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    try {
      final service = CloudflareD1Service(_config);
      final result = await service.probe();
      List<String> d1Tables;
      try {
        d1Tables = await service.listD1Tables();
      } on CloudflareD1Exception {
        d1Tables = const <String>[];
      }
      if (!mounted) return;
      setState(() {
        _probeResult = result;
        _d1Tables = d1Tables;
      });
    } on CloudflareD1Exception catch (e) {
      if (!mounted) return;
      setState(() => _probeResult = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الفحص: ${e.message}')));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _loadLocalTables() async {
    setState(() => _loadingTables = true);
    try {
      final db = ref.read(databaseProvider);
      // ✅ نطاق الرفع: CloudflareConfig.d1BackupTables = كيانات النطاق
      // الافتراضي للمزامنة (migrationOrder — 24 كياناً بتأكيد المستخدم
      // 2026-09-05). لا يُرفع قاعدة البيانات المحلية كاملة. الكيانات
      // بلا جدول Drift محلي (blacklist — سحابية فقط) تُتخطى بفحص
      // sqlite_master ثم تُجسَّد افتراضياً أدناه من shift_notes
      // الموسومة created_by='blacklist'. app_users له جدول محلي
      // (AppUsers، schemaVersion 66) فيُكتشف فيزيائياً كأي جدول.
      // hotel_day_ledger (محلي-فقط بتأكيد المستخدم 2026-09-05)
      // وجداول البنية المحلية (outbox, sync_remote_meta, sync_state,
      // sync_log, custom_list_items، ...) مستبعدة عمداً — لا مقابل
      // لها في النطاق الافتراضي.
      const wanted = CloudflareConfig.d1BackupTables;
      final existingRows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
            "(${List.filled(wanted.length, '?').join(',')})",
            variables: wanted.map(Variable.withString).toList(),
          )
          .get();
      final names = CloudflareD1Tab.scopeSyncTables(
        existingRows.map((r) => r.data['name']?.toString() ?? ''),
      );

      // جلب DDL (جداول + فهارس) مرتبة: الجداول أولاً ثم فهارسها.
      final ddlRows = await db
          .customSelect(
            "SELECT type, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL "
            "AND name NOT LIKE 'sqlite_%' AND type IN ('table','index') "
            "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END",
          )
          .get();
      final ddlByTable = <String, List<String>>{};
      for (final r in ddlRows) {
        final tbl = r.data['tbl_name']?.toString() ?? '';
        final sql = r.data['sql']?.toString() ?? '';
        if (tbl.isEmpty || sql.isEmpty) continue;
        (ddlByTable[tbl] ??= <String>[]).add(sql);
      }

      final tables = <_LocalTableInfo>[];
      for (final n in names) {
        // shift_notes: العدّ يستبعد صفوف القائمة السوداء الموسومة
        // (تُرفع ككيان blacklist مستقل — مطابقة المجموعات).
        final countSql = n == 'shift_notes'
            ? "SELECT COUNT(*) AS n FROM shift_notes WHERE created_by != "
                  "'${CloudflareConfig.blacklistStorageTag}'"
            : 'SELECT COUNT(*) AS n FROM "${n.replaceAll('"', '""')}"';
        final countRows = await db.customSelect(countSql).get();
        final count = (countRows.first.data['n'] as int?) ?? 0;
        tables.add(
          _LocalTableInfo(
            name: n,
            rowCount: count,
            createSqlList: ddlByTable[n] ?? const <String>[],
          ),
        );
      }

      // ✅ تجسيد blacklist افتراضياً (كيان عقد Appwrite بلا جدول Drift
      // محلي — صفوفها مخزنة في shift_notes الموسومة
      // created_by='blacklist'، انظر repositories/blacklist_repository).
      // يُرفع إلى جدول blacklist في D1 عبر تحويل
      // CloudflareD1Service.blacklistRowFromShiftNote؛ جدول D1 موجود
      // مسبقاً من worker/schema.sql فلا DDL مطلوب.
      final blCountRows = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM shift_notes WHERE created_by = "
            "'${CloudflareConfig.blacklistStorageTag}'",
          )
          .get();
      tables.add(
        _LocalTableInfo(
          name: 'blacklist',
          rowCount: (blCountRows.first.data['n'] as int?) ?? 0,
          createSqlList: const <String>[],
        ),
      );
      if (!mounted) return;
      setState(() {
        _localTables = tables;
        _selected
          ..clear()
          ..addAll(tables.map((t) => t.name));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر قراءة الجداول المحلية: $e')));
    } finally {
      if (mounted) setState(() => _loadingTables = false);
    }
  }

  Future<void> _confirmAndUpload() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر جدولاً واحداً على الأقل')),
      );
      return;
    }
    final totalRows = _localTables
        .where((t) => _selected.contains(t.name))
        .fold<int>(0, (a, t) => a + t.rowCount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الرفع إلى Cloudflare D1'),
        content: Text(
          'سيتم رفع ${_selected.length} جدولاً ($totalRows صفاً) إلى قاعدة '
          'D1 المحددة باستخدام INSERT OR REPLACE.\n\n'
          '• لا يُحذف أي سجل موجود في D1 غير موجود محلياً.\n'
          '• إعادة الرفع آمنة (نفس البيانات تستبدل نفسها).\n'
          '• يُنصح بعدد صفوف كبير بألا تكون هناك عمليات كتابة كثيرة أثناء الرفع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('رفع الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _upload();
  }

  Future<void> _upload() async {
    final db = ref.read(databaseProvider);
    final service = CloudflareD1Service(_config);
    _activeService = service;

    final sources = <CloudflareD1SourceTable>[];
    for (final t in _localTables) {
      if (!_selected.contains(t.name)) continue;
      final table = t;
      sources.add(
        CloudflareD1SourceTable(
          name: table.name,
          rowCount: table.rowCount,
          createSqlList: table.createSqlList,
          readChunk: (limit, offset) async {
            // blacklist: مصدره shift_notes الموسومة → تحويل إلى أعمدة
            // جدول D1 (نفس اتجاه مسار المزامنة entity='blacklist').
            if (table.name == 'blacklist') {
              final rows = await db
                  .customSelect(
                    '${CloudflareD1Service.blacklistSourceSql} LIMIT ? OFFSET ?',
                    variables: [
                      Variable.withInt(limit),
                      Variable.withInt(offset),
                    ],
                  )
                  .get();
              return rows
                  .map(
                    (r) =>
                        CloudflareD1Service.blacklistRowFromShiftNote(r.data),
                  )
                  .toList();
            }
            // shift_notes: يستبعد صفوف القائمة السوداء (كيان blacklist
            // منفصل — مطابقة مجموعة shift_notes في Appwrite Cloud).
            final sourceSql = table.name == 'shift_notes'
                ? CloudflareD1Service.shiftNotesSourceSql
                : 'SELECT * FROM "${table.name.replaceAll('"', '""')}"';
            final rows = await db
                .customSelect(
                  '$sourceSql LIMIT ? OFFSET ?',
                  variables: [
                    Variable.withInt(limit),
                    Variable.withInt(offset),
                  ],
                )
                .get();
            return rows.map((r) => r.data).toList();
          },
        ),
      );
    }

    setState(() {
      _uploading = true;
      _progress = 0;
      _stage = 'بدء الرفع...';
      _result = null;
      _logs.clear();
    });

    try {
      final label = _deviceLabelCtrl.text.trim();
      final result = await service.uploadData(
        tables: sources,
        deviceLabel: label.isEmpty ? null : label,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p.tableFraction.clamp(0.0, 1.0);
            _stage =
                '${p.currentTable} '
                '(${p.tableIndex + 1}/${p.tableCount}) — '
                '${p.rowsDone}/${p.rowsTotal} صف';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _uploading = false;
        _stage = result.cancelled ? 'أُوقف الرفع' : 'اكتمل الرفع';
      });
      if (result.errors.isNotEmpty) {
        setState(() {
          _logs
            ..clear()
            ..addAll(result.errors.take(10));
        });
      }
    } on CloudflareD1Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _stage = 'فشل الرفع: ${e.message}';
      });
    } finally {
      _activeService = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final d1Set = _d1Tables?.toSet();
    final selectedRows = _localTables
        .where((t) => _selected.contains(t.name))
        .fold<int>(0, (a, t) => a + t.rowCount);
    final missingInD1 = d1Set == null
        ? const <String>[]
        : _selected.where((n) => !d1Set.contains(n)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CloudflareAutoConnectionCard(),
        const SizedBox(height: 8),
        Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.dns),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'رفع البيانات إلى Cloudflare D1',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'ينقل هذا التبويب بيانات جداول المزامنة (كيانات مزامنة '
          'Cloudflare حصراً) إلى قاعدة Cloudflare D1 كنسخة استشارية على '
          'السحابة. '
          'القراءة من القاعدة المحلية فقط، والكتابة بأسلوب INSERT OR '
          'REPLACE الآمن. القائمة السوداء blacklist كيان بلا جدول '
          'محلي فتُجسَّد من ملاحظات الورديات الموسومة إلى جدولها في '
          'D1، أما hotel_day_ledger (محلي-فقط) وجداول البنية المحلية '
          '(outbox، sync_remote_meta، sync_state، sync_log، …) '
          'فتُستبعد كلياً.',
          textAlign: TextAlign.start,
        ),
        if (_outboxPending > 0) ...[
          const SizedBox(height: 8),
          Text(
            'تنبيه استشاري: توجد $_outboxPending عملية في Outbox غير مُسلّمة — '
            'يمكنك المتابعة لكن يُفضّل تفريغ الرفع الاعتيادي أولاً.',
            style: TextStyle(color: Colors.orange.shade800),
          ),
        ],
        const SizedBox(height: 16),

        // ── الإعدادات ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إعدادات الاتصال',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _accountIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Account ID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _databaseIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Database ID (uuid)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'API Token (صلاحية D1 Edit يُنصح بها)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deviceLabelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'وسم الجهاز (اختياري — يُسجل مع النسخة)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (_probing || _uploading || _loadingSettings)
                          ? null
                          : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('حفظ'),
                    ),
                    FilledButton.icon(
                      onPressed: (_probing || _uploading || _loadingSettings)
                          ? null
                          : _probe,
                      icon: _probing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('فحص الاتصال والصلاحيات'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_probeResult != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _probeRow(
                    _probeResult!.tokenValid,
                    'التوكن صالح وفعّال',
                    'التوكن غير صالح',
                  ),
                  _probeRow(
                    _probeResult!.databaseReachable,
                    'القاعدة متاحة: ${_probeResult!.databaseName ?? _databaseIdCtrl.text}',
                    'القاعدة غير موجودة في الحساب',
                  ),
                  _probeRow(
                    _probeResult!.dmlAllowed,
                    'صلاحية الكتابة (DML) متاحة — الرفع ممكن',
                    'صلاحية الكتابة (DML) محجوبة',
                    detail: _probeResult!.dmlError,
                  ),
                  _probeRow(
                    _probeResult!.ddlAllowed,
                    'صلاحية إنشاء الجداول (DDL) متاحة',
                    'إنشاء الجداول (DDL) محجوب — لا يمنع الرفع؛ المخطط موجود مسبقاً',
                  ),
                  if (_d1Tables != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'جداول D1: ${_d1Tables!.length} — '
                        'مغطاة محلياً: ${_localTables.where((t) => d1Set!.contains(t.name)).length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // ── الجداول المحلية ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'جداول المزامنة السحابية '
                        '($_selected/${_localTables.length} محددة — '
                        '$selectedRows صف)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _localTables.isEmpty
                          ? null
                          : () => setState(
                              () => _selected
                                ..clear()
                                ..addAll(_localTables.map((t) => t.name)),
                            ),
                      child: const Text('الكل'),
                    ),
                    TextButton(
                      onPressed: _localTables.isEmpty
                          ? null
                          : () => setState(() => _selected.clear()),
                      child: const Text('لا شيء'),
                    ),
                  ],
                ),
                if (missingInD1.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'تنبيه: ${missingInD1.length} جدولاً محدداً غير موجود في D1 '
                      '(ستفشل): ${missingInD1.take(5).join('، ')}',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                if (_loadingTables)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _localTables.length,
                      itemBuilder: (context, i) {
                        final t = _localTables[i];
                        final existsInD1 =
                            d1Set == null || d1Set.contains(t.name);
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(t.name),
                          onChanged: _uploading
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(t.name);
                                  } else {
                                    _selected.remove(t.name);
                                  }
                                }),
                          title: Text(t.name),
                          subtitle: Text(
                            '${t.rowCount} صف'
                            '${existsInD1 ? '' : ' — غير موجود في D1'}',
                          ),
                        );
                      },
                    ),
                  ),
                TextButton.icon(
                  onPressed: (_loadingTables || _uploading)
                      ? null
                      : _loadLocalTables,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث قائمة الجداول والأعداد'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── الرفع ──
        if (_uploading) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 10),
          Text(_stage, textAlign: TextAlign.center),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    (_uploading ||
                        _localTables.isEmpty ||
                        !(_probeResult?.dmlAllowed ?? false))
                    ? null
                    : _confirmAndUpload,
                icon: _uploading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  _uploading ? 'جاري الرفع...' : 'رفع البيانات المحددة الآن',
                ),
              ),
            ),
            if (_uploading) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _activeService?.cancel(),
                icon: const Icon(Icons.stop),
                label: const Text('إيقاف'),
              ),
            ],
          ],
        ),
        if (!(_probeResult?.dmlAllowed ?? false) && _probeResult != null) ...[
          const SizedBox(height: 8),
          Text(
            'لا يمكن الرفع: صلاحية الكتابة غير متاحة بالتوكن الحالي.',
            style: TextStyle(color: colorScheme.error),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          Card(
            color: _result!.ok ? Colors.green.shade50 : Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _result!.cancelled
                        ? 'أُوقف الرفع جزئياً'
                        : _result!.ok
                        ? 'اكتمل الرفع بنجاح'
                        : 'اكتمل مع أخطاء',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'جداول: ${_result!.tablesDone} — صفوف: ${_result!.rowsUploaded} — '
                    'نداءات: ${_result!.apiCalls} — '
                    'الزمن: ${_result!.elapsed.inSeconds}ث',
                  ),
                  for (final w in _result!.warnings.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        w,
                        style: TextStyle(color: Colors.orange.shade800),
                      ),
                    ),
                  for (final e in _result!.errors.take(5))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        e,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _logs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        line,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _probeRow(bool ok, String okText, String failText, {String? detail}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: ok ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? okText : failText),
                if (!ok && detail != null && detail.isNotEmpty)
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
