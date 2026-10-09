import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/repository_providers.dart';
import '../../../../services/auth_local_store.dart';
import '../../../../services/cloudflare_d1_app_users_source.dart';
import '../../../../services/cloudflare_d1_identity_repair.dart';
import '../../../../services/cloudflare_d1_identity_validator.dart';
import '../../../../services/cloudflare_d1_service.dart';
import '../../../../services/daos/outbox_dao.dart';

/// الجداول المحلية المطابقة لمجموعات Appwrite Cloud (collections) —
/// مشتقة من خريطة `_entityToCollectionId` في AppwriteSyncManager ومن دورة
/// السحب الفعلية. بيانات blacklist تُخزّن محلياً داخل shift_notes (بعد
/// فلترة createdBy='blacklist' — انظر kShiftNotesD1ExclusionWhere)، و
/// app_users يُرفع كجدول تركيبي (kD1SyntheticTables) لأنه بلا جدول Drift
/// محلي (AuthLocalStore في SharedPreferences).
const Set<String> kAppwriteSyncedTables = <String>{
  'rooms',
  'bookings',
  'booking_nights',
  'booking_notes',
  'booking_price_adjustments',
  'payments',
  'payment_voids',
  'price_adjustments',
  'expenses',
  'debts',
  'employees',
  'guest_infos',
  'cash_transactions',
  'shift_notes',
  'salary_cycles',
  'salary_payments',
  'salary_withdrawals',
  'salary_carry_over_logs',
  'audit_logs',
  'inventory_items',
  'inventory_transactions',
};

/// ✅ D1-path audit fix (2026-10-04) — الفجوة F1:
/// مرآة D1 لجدول shift_notes يجب أن تطابق محتوى مجموعة shift_notes على
/// Appwrite: صفوف القائمة السوداء (created_by='blacklist') تُستبعد من
/// الرفع لأن مزامنة Appwrite توجهها إلى مجموعة `blacklist` المستقلة،
/// بينما لا يوجد جدول blacklist في D1 — رفعها داخل shift_notes كان يُنشئ
/// تفرّعاً في المسار (وهو ما يعرض بيانات ضيوف القائمة السوداء في مرآة
/// مخصصة للملاحظات). الفلتر يُطبق في وضعي الرفع (جداول المزامنة والكل)
/// لأن الجدول فيزيائياً واحد.
const String kShiftNotesD1ExclusionWhere =
    "(created_by IS NULL OR created_by <> 'blacklist')";

/// الجداول التركيبية في مسار D1 — مجموعات Appwrite متزامنة بلا جدول Drift
/// محلي، تُبنى صفوفها من مصدرها المحلي الخاص بدلاً من SELECT *.
/// - app_users: من AuthLocalStore (custom_accounts + user_permissions +
///   best-effort سحابي) — انظر cloudflare_d1_app_users_source.dart.
const Set<String> kD1SyntheticTables = <String>{'app_users'};

/// تبويب رفع البيانات المحلية (المسحوبة من Appwrite) إلى Cloudflare D1.
///
/// المسار للقراءة فقط من القاعدة المحلية (SELECT) ثم UPSERT بالهوية الثابتة
/// إلى D1 — لا يمس حلقة مزامنة Appwrite ولا يحذف أي سجل بعيد.
/// القيود المطبقة (مثبتة تجريبياً): عبارات حرفية متعددة بلا معاملات في
/// النداء الواحد — دفعة 200 عبارة (مثبت: 800 عبارة/187KB نجحت بـ 635ms).
class CloudflareD1Tab extends ConsumerStatefulWidget {
  const CloudflareD1Tab({super.key});

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

  /// الافتراضي: جداول مزامنة Appwrite فقط (مطابقة للـ collections) —
  /// ويمكن إظهار جميع الجداول المحلية عبر المفتاح في بطاقة الجداول.
  bool _appwriteOnly = true;

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
      const excluded =
          "name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
          "AND name != 'room_master_table' AND name NOT LIKE '_cf_%'";
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND $excluded ORDER BY name",
          )
          .get();
      final names = rows
          .map((r) => r.data['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

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
        // ✅ F1 (2026-10-04): صفوف blacklist داخل shift_notes لا تُحسب
        // لأنها مستبعدة من الرفع (نفس فلتر readChunk أدناه).
        final countWhere = n == 'shift_notes'
            ? 'WHERE $kShiftNotesD1ExclusionWhere'
            : '';
        final countRows = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM "${n.replaceAll('"', '""')}" $countWhere',
            )
            .get();
        final count = (countRows.first.data['n'] as int?) ?? 0;
        tables.add(
          _LocalTableInfo(
            name: n,
            rowCount: count,
            createSqlList: ddlByTable[n] ?? const <String>[],
          ),
        );
      }

      // ✅ F2 (2026-10-04): app_users جدول تركيبي — مجموعته متزامنة مع
      // Appwrite لكنها بلا جدول Drift. يُعرض بعدد الصفوف المحلية (بلا
      // شبكة)، وعند الرفع يُجمع من جديد شاملاً الحسابات السحابية.
      if (names.contains('app_users')) {
        // غير متوقع — جدول Drift بنفس الاسم يغني عن التركيبي.
      } else {
        try {
          final appUsersRows = await AuthLocalStore().exportAppUsersD1Rows(
            includeCloud: false,
          );
          tables.add(
            _LocalTableInfo(
              name: 'app_users',
              rowCount: appUsersRows.length,
              createSqlList: const [kAppUsersD1CreateSql],
            ),
          );
        } catch (e) {
          // فشل التصدير لا يعطل بقية الجداول — يُسجل ويُتخطى.
          debugPrint('D1: تعذر تجهيز صفوف app_users التركيبية: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _localTables = tables;
        _selected
          ..clear()
          ..addAll(_visibleTables.map((t) => t.name));
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

  /// الجداول الظاهرة حسب وضع التصفية (مزامنة Appwrite فقط / الكل).
  /// تشمل الجداول التركيبية (app_users) في الوضعين — مجموعتها متزامنة.
  List<_LocalTableInfo> get _visibleTables {
    if (!_appwriteOnly) return _localTables;
    return _localTables
        .where(
          (t) =>
              kAppwriteSyncedTables.contains(t.name) ||
              kD1SyntheticTables.contains(t.name),
        )
        .toList();
  }

  void _selectAllVisible() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_visibleTables.map((t) => t.name));
    });
  }

  Future<void> _repairIdentity() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر جدولاً واحداً على الأقل أولاً')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إصلاح هوية السجلات والروابط'),
        content: const Text(
          'سيتم إنشاء local_uuid للسجلات القديمة التي تفتقده فقط، '
          'وربط employee_uuid وbooking_uuid والروابط المالية من المفاتيح '
          'المحلية الصريحة. لن يتم حذف أي سجل أو تغيير مبالغ أو تواريخ، '
          'ولن يتم لمس جداول المزامنة المحلية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إصلاح الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _uploading = true;
      _stage = 'إصلاح الهوية والروابط...';
      _result = null;
    });
    try {
      final result = await CloudflareD1IdentityRepair.repair(
        db: ref.read(databaseProvider),
        selectedTables: _selected,
      );
      await _loadLocalTables();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إصلاح ${result.identitiesRepaired} هوية و${result.linksRepaired} رابط. '
            'يمكنك الآن رفع البيانات إلى D1.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إصلاح الهوية: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _stage = '';
        });
      }
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
          'D1 المحددة. الجداول التي تحمل local_uuid تستخدم UPSERT على الهوية الثابتة، وليس INSERT OR REPLACE.\n\n'
          '• لا يُحذف أي سجل موجود في D1 غير موجود محلياً.\n'
          '• لا يتم اختراع employee_uuid أو إعادة ربط سجل بموظف بالتخمين.\n'
          '• قد تظهر تحذيرات للسجلات التاريخية التي تحتاج مراجعة.',
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
    final identityIssues = await CloudflareD1IdentityValidator.inspect(
      db: db,
      selectedTables: _selected,
    );
    if (identityIssues.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _logs
          ..clear()
          ..addAll(identityIssues);
        _stage = 'أُوقف الرفع قبل الاتصال بـ Cloudflare بسبب فشل التحقق';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لم يُرسل أي طلب إلى Cloudflare. أصلح هوية local_uuid وروابط UUID أولاً.',
          ),
        ),
      );
      return;
    }
    final service = CloudflareD1Service(_config);
    _activeService = service;

    final infoLogs = <String>[];
    final sources = <CloudflareD1SourceTable>[];

    // ✅ F2 (2026-10-04): الجدول التركيبي app_users — يُجمع قبل الرفع
    // (شاملاً الحسابات السحابية best-effot بمهلة قصيرة) ليعرف الرفع
    // عدد الصفوف الحقيقي مسبقاً (شرط حلقة الترقيم في uploadData).
    if (_selected.contains('app_users')) {
      try {
        final appUsersRows = await AuthLocalStore().exportAppUsersD1Rows(
          includeCloud: true,
        );
        infoLogs.add('app_users: ${appUsersRows.length} حساب (محلي + سحابي)');
        sources.add(
          CloudflareD1SourceTable(
            name: 'app_users',
            rowCount: appUsersRows.length,
            createSqlList: const [kAppUsersD1CreateSql],
            readChunk: (limit, offset) async =>
                sliceRows(appUsersRows, limit, offset),
          ),
        );
      } catch (e) {
        infoLogs.add('app_users: فشل التجهيز — طُلب من الرفع: $e');
      }
    }

    for (final t in _localTables) {
      if (!_selected.contains(t.name)) continue;
      if (t.name == 'app_users') continue; // تركيبي — عولج أعلاه
      final table = t;
      // ✅ F1 (2026-10-04): استبعاد صفوف blacklist من shift_notes
      // (تفصيل الفجوة F1 في توثيق kShiftNotesD1ExclusionWhere).
      final where = table.name == 'shift_notes'
          ? 'WHERE $kShiftNotesD1ExclusionWhere'
          : '';
      sources.add(
        CloudflareD1SourceTable(
          name: table.name,
          rowCount: table.rowCount,
          createSqlList: table.createSqlList,
          readChunk: (limit, offset) async {
            final rows = await db
                .customSelect(
                  'SELECT * FROM "${table.name.replaceAll('"', '""')}" $where '
                  'LIMIT ? OFFSET ?',
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
      _logs
        ..clear()
        ..addAll(infoLogs);
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
    } catch (e) {
      // أي استثناء غير متوقع (قراءة محلية/ذاكرة/غيره) يجب ألا يترك الحالة
      // عالقة على "جاري الرفع" — كل الأزرار معطلة أثناء _uploading.
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _stage = 'فشل الرفع بخطأ غير متوقع: $e';
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
          'ينقل هذا التبويب نسخة بيانات محلية إلى Cloudflare D1. هوية السجل '
          'المحمولة هي local_uuid، وعلاقات الموظفين تعتمد على employee_uuid؛ '
          'لا يتم استخدام id الرقمي المحلي/البعيد كهوية للمزامنة. الرفع يتم '
          'بـ UPSERT على local_uuid للجداول التي تحتويه، وليس REPLACE، لمنع '
          'حذف وإعادة إنشاء الصفوف وكسر العلاقات.',
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 10),
        Card(
          color: colorScheme.tertiaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'حارس الهوية: employees / expenses / salary_withdrawals وكيانات الرواتب يجب أن تحمل local_uuid، والروابط employee_uuid. أي سجل بلا هوية ثابتة لا يُعاد تعيينه اعتمادًا على id الرقمي.',
                  ),
                ),
              ],
            ),
          ),
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
                        'الجداول ($_selected/${_visibleTables.length} محددة — '
                        '$selectedRows صف)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _visibleTables.isEmpty
                          ? null
                          : _selectAllVisible,
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
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _appwriteOnly,
                  onChanged: _uploading
                      ? null
                      : (v) {
                          setState(() {
                            _appwriteOnly = v;
                            _selected
                              ..clear()
                              ..addAll(_visibleTables.map((t) => t.name));
                          });
                        },
                  title: const Text('جداول مزامنة Appwrite Cloud فقط'),
                  subtitle: const Text(
                    'المطابقة لمجموعات Appwrite (collections) — بدل جميع '
                    'الجداول المحلية',
                  ),
                ),
                if (missingInD1.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'تنبيه: ${missingInD1.length} جدولاً محدداً غير موجود في D1 '
                      '(سيُنشأ أثناء الرفع عند توفر صلاحية إنشاء الجداول): '
                      '${missingInD1.take(5).join('، ')}',
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
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      // ✅ تمرير داخلي مقصود: البطاقة مصغّرة (200px) لكن كل
                      // الجداول تظل قابلة للوصول — NeverScrollable كان يقتطع
                      // القائمة (21 جدولاً ≈ 1500px) ويخفي الجداول السفلية.
                      physics: const ClampingScrollPhysics(),
                      itemCount: _visibleTables.length,
                      itemBuilder: (context, i) {
                        final t = _visibleTables[i];
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
                OutlinedButton.icon(
                  onPressed: (_loadingTables || _uploading || _selected.isEmpty)
                      ? null
                      : _repairIdentity,
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text('إصلاح الهوية والروابط'),
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
