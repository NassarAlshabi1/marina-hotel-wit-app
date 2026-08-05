// ignore_for_file: directives_ordering, use_late_for_private_fields_and_variables, avoid_redundant_argument_values, discarded_futures, prefer_const_constructors
// ═══════════════════════════════════════════════════════════════
//  error_tracker_screen.dart — شاشة تتبع ونسخ الأخطاء
//  تجمع كل أخطاء النظام (مزامنة، migration، قاعدة بيانات، شبكة)
//  مع إمكانية البحث، الفلترة، النسخ، المشاركة، والتصدير
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/app_scaffold.dart';
import '../../services/appwrite_logger.dart';
import '../../services/logging/log_models.dart';

/// نوع الخطأ للفلترة
enum ErrorCategory {
  all('الكل', Icons.list, Colors.blue),
  sync('المزامنة', Icons.sync, Colors.purple),
  migration('الترحيل', Icons.cloud_upload, Colors.teal),
  network('الشبكة', Icons.wifi_off, Colors.orange),
  database('قاعدة البيانات', Icons.storage, Colors.red),
  auth('المصادقة', Icons.lock, Colors.indigo),
  rateLimit('تجاوز الحد', Icons.speed, Colors.deepOrange),
  unknown('أخرى', Icons.error_outline, Colors.grey);

  const ErrorCategory(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// نموذج خطأ موحد لكل أنواع الأخطاء
class TrackedError {
  const TrackedError({
    required this.timestamp,
    required this.category,
    required this.severity,
    required this.title,
    required this.message,
    this.source,
    this.statusCode,
    this.retryAfter,
    this.stackTrace,
  });

  final DateTime timestamp;
  final ErrorCategory category;
  final LogLevel severity;
  final String title;
  final String message;
  final String? source;
  final int? statusCode;
  final int? retryAfter; // Unix timestamp ms (for 429)
  final String? stackTrace;

  String get formattedTime =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

  String get shortTime => DateFormat('HH:mm:ss').format(timestamp);

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('════════════════════════════════════════');
    buffer.writeln('🔍 ${severity.name.toUpperCase()} — ${category.label}');
    buffer.writeln('📅 الوقت: $formattedTime');
    buffer.writeln('🏷️ العنوان: $title');
    if (statusCode != null) buffer.writeln('📡 HTTP: $statusCode');
    if (source != null) buffer.writeln('📂 المصدر: $source');
    if (retryAfter != null) {
      final retryTime = DateTime.fromMillisecondsSinceEpoch(retryAfter!);
      buffer.writeln('⏳ إعادة المحاولة بعد: ${DateFormat('HH:mm:ss').format(retryTime)}');
    }
    buffer.writeln('📝 التفاصيل:');
    buffer.writeln(message);
    if (stackTrace != null) {
      buffer.writeln('📋 Stack Trace:');
      buffer.writeln(stackTrace);
    }
    buffer.writeln('════════════════════════════════════════');
    return buffer.toString();
  }
}

/// مخزن الأخطاء المؤقت (in-memory + optional persistence)
class ErrorTrackerStore {
  ErrorTrackerStore._();
  static final ErrorTrackerStore instance = ErrorTrackerStore._();

  final List<TrackedError> _errors = [];
  final int _maxErrors = 500;

  List<TrackedError> get errors => List.unmodifiable(_errors);

  void addError(TrackedError error) {
    _errors.insert(0, error); // الأحدث أولاً
    if (_errors.length > _maxErrors) {
      _errors.removeRange(_maxErrors, _errors.length);
    }
  }

  void clear() => _errors.clear();

  void clearCategory(ErrorCategory category) {
    _errors.removeWhere((e) => e.category == category);
  }

  List<TrackedError> filter({
    ErrorCategory category = ErrorCategory.all,
    LogLevel? minSeverity,
    String searchQuery = '',
  }) {
    return _errors.where((e) {
      if (category != ErrorCategory.all && e.category != category) {
        return false;
      }
      if (minSeverity != null && e.severity.value < minSeverity.value) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        return e.title.toLowerCase().contains(q) ||
            e.message.toLowerCase().contains(q) ||
            (e.source?.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  Map<ErrorCategory, int> get counts {
    final map = <ErrorCategory, int>{};
    for (final e in _errors) {
      map[e.category] = (map[e.category] ?? 0) + 1;
    }
    return map;
  }
}

/// دالة مساعدة لتسجيل خطأ من HTTP response
void logHttpError({
  required String title,
  required int statusCode,
  required String responseBody,
  String? source,
  String? retryAfterRaw,
}) {
  ErrorCategory category;
  LogLevel severity;

  if (statusCode == 429) {
    category = ErrorCategory.rateLimit;
    severity = LogLevel.warning;
  } else if (statusCode >= 500) {
    category = ErrorCategory.network;
    severity = LogLevel.error;
  } else if (statusCode == 401 || statusCode == 403) {
    category = ErrorCategory.auth;
    severity = LogLevel.error;
  } else if (statusCode >= 400) {
    category = ErrorCategory.network;
    severity = LogLevel.warning;
  } else {
    category = ErrorCategory.unknown;
    severity = LogLevel.info;
  }

  int? retryAfterMs;
  if (retryAfterRaw != null) {
    retryAfterMs = int.tryParse(retryAfterRaw);
  }

  // Try to extract retry_after from response body (Cloudflare Worker format)
  if (retryAfterMs == null && responseBody.isNotEmpty) {
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      retryAfterMs = body['retry_after'] as int?;
    } catch (e) {
      debugPrint('⚠️ Swallowed error in error_tracker_screen.dart: ');
      // Not JSON, ignore
    }
  }

  ErrorTrackerStore.instance.addError(
    TrackedError(
      timestamp: DateTime.now(),
      category: category,
      severity: severity,
      title: title,
      message: responseBody.isEmpty ? '(no response body)' : responseBody,
      source: source,
      statusCode: statusCode,
      retryAfter: retryAfterMs,
    ),
  );
}

/// دالة مساعدة لتسجيل خطأ عام
void logError({
  required String title,
  required String message,
  ErrorCategory category = ErrorCategory.unknown,
  LogLevel severity = LogLevel.error,
  String? source,
  String? stackTrace,
}) {
  ErrorTrackerStore.instance.addError(
    TrackedError(
      timestamp: DateTime.now(),
      category: category,
      severity: severity,
      title: title,
      message: message,
      source: source,
      stackTrace: stackTrace,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
//  الشاشة الرئيسية
// ═══════════════════════════════════════════════════════════════

class ErrorTrackerScreen extends StatefulWidget {
  const ErrorTrackerScreen({super.key});

  @override
  State<ErrorTrackerScreen> createState() => _ErrorTrackerScreenState();
}

class _ErrorTrackerScreenState extends State<ErrorTrackerScreen> {
  final _store = ErrorTrackerStore.instance;
  ErrorCategory _selectedCategory = ErrorCategory.all;
  LogLevel? _minSeverity;
  String _searchQuery = '';
  Timer? _refreshTimer;
  List<TrackedError> _currentErrors = [];

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  List<TrackedError> _getFilteredErrors() {
    return _store.filter(
      category: _selectedCategory,
      minSeverity: _minSeverity,
      searchQuery: _searchQuery,
    );
  }

  Future<void> _copyError(TrackedError error) async {
    await Clipboard.setData(ClipboardData(text: error.toFormattedString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم نسخ الخطأ إلى الحافظة'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyAllErrors() async {
    final errors = _getFilteredErrors();
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أخطاء لنسخها')),
      );
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('🔍 تقرير الأخطاء — ${DateTime.now()}');
    buffer.writeln('📊 العدد: ${errors.length}');
    buffer.writeln('');
    for (final e in errors) {
      buffer.writeln(e.toFormattedString());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم نسخ ${errors.length} خطأ إلى الحافظة'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareErrors(List<TrackedError> errors) async {
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أخطاء للمشاركة')),
      );
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('🔍 تقرير أخطاء فندق مارينا — ${DateTime.now()}');
    buffer.writeln('📊 العدد: ${errors.length}');
    buffer.writeln('');
    for (final e in errors) {
      buffer.writeln(e.toFormattedString());
    }
    await Share.share(buffer.toString(), subject: 'تقرير أخطاء فندق مارينا');
  }

  Future<void> _exportErrors() async {
    final errors = _getFilteredErrors();
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أخطاء للتصدير')),
      );
      return;
    }
    final jsonList = errors.map((e) => {
      'timestamp': e.timestamp.toIso8601String(),
      'category': e.category.name,
      'severity': e.severity.name,
      'title': e.title,
      'message': e.message,
      'source': e.source,
      'statusCode': e.statusCode,
      'retryAfter': e.retryAfter,
      'stackTrace': e.stackTrace,
    }).toList();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonList);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم تصدير ${errors.length} خطأ بصيغة JSON إلى الحافظة'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _clearAllErrors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح كل الأخطاء'),
        content: const Text('هل أنت متأكد من مسح جميع الأخطاء المسجلة؟ '
            'لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _store.clear();
      setState(() {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم مسح جميع الأخطاء')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = _getFilteredErrors();
    _currentErrors = errors;
    final counts = _store.counts;

    return AppScaffold(
      title: 'تتبع الأخطاء',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
          onPressed: () => setState(() {}),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'copy_all':
                await _copyAllErrors();
              case 'share':
                await _shareErrors(_currentErrors);
              case 'export':
                await _exportErrors();
              case 'clear':
                await _clearAllErrors();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'copy_all',
              child: Row(children: [
                Icon(Icons.copy_all),
                SizedBox(width: 8),
                Text('نسخ جميع الأخطاء'),
              ]),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(children: [
                Icon(Icons.share),
                SizedBox(width: 8),
                Text('مشاركة التقرير'),
              ]),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(children: [
                Icon(Icons.file_download),
                SizedBox(width: 8),
                Text('تصدير JSON'),
              ]),
            ),
            const PopupMenuItem(
              value: 'clear',
              child: Row(children: [
                Icon(Icons.delete_sweep, color: Colors.red),
                SizedBox(width: 8),
                Text('مسح الكل', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ],
      body: Column(
        children: [
          // ─── شريط البحث ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'بحث في الأخطاء...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // ─── فلاتر الفئات (chips) ──────────────────────────
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: ErrorCategory.values.map((cat) {
                final count = cat == ErrorCategory.all
                    ? _store.errors.length
                    : (counts[cat] ?? 0);
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    label: Text('${cat.label} ($count)'),
                    avatar: Icon(cat.icon, size: 18),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    backgroundColor: cat.color.withValues(alpha: 0.1),
                    selectedColor: cat.color.withValues(alpha: 0.3),
                    labelStyle: TextStyle(
                      color: isSelected ? cat.color : Colors.grey[700],
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ─── فلتر الخطورة ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('الحد الأدنى للخطورة: ',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: _minSeverity == null,
                          onSelected: (_) => setState(() => _minSeverity = null),
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('⚠️ تحذير'),
                          selected: _minSeverity == LogLevel.warning,
                          onSelected: (_) =>
                              setState(() => _minSeverity = LogLevel.warning),
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('❌ خطأ'),
                          selected: _minSeverity == LogLevel.error,
                          onSelected: (_) =>
                              setState(() => _minSeverity = LogLevel.error),
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('🚨 حرج'),
                          selected: _minSeverity == LogLevel.critical,
                          onSelected: (_) =>
                              setState(() => _minSeverity = LogLevel.critical),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── إحصائيات سريعة ───────────────────────────────
          if (_store.errors.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.analytics, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الإجمالي: ${_store.errors.length} | '
                      'المعروض: ${errors.length} | '
                      'آخر خطأ: ${errors.isEmpty ? "-" : errors.first.shortTime}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // ─── قائمة الأخطاء ────────────────────────────────
          Expanded(
            child: errors.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: errors.length,
                    itemBuilder: (context, index) {
                      final error = errors[index];
                      return _ErrorCard(
                        error: error,
                        onTap: () => _showErrorDetails(error),
                        onCopy: () => _copyError(error),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isNotEmpty || _selectedCategory != ErrorCategory.all
                ? Icons.search_off
                : Icons.check_circle,
            size: 64,
            color: Colors.green.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _selectedCategory != ErrorCategory.all
                ? 'لا توجد أخطاء مطابقة للفلتر'
                : 'لا توجد أخطاء مسجلة',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'الأخطاء ستظهر هنا تلقائياً عند حدوثها',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showErrorDetails(TrackedError error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(error.category.icon, color: error.category.color),
            const SizedBox(width: 8),
            Expanded(child: Text(error.title)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('الوقت', error.formattedTime),
                _DetailRow('الفئة', error.category.label),
                _DetailRow('الخطورة', error.severity.name.toUpperCase()),
                if (error.statusCode != null)
                  _DetailRow('HTTP Status', error.statusCode.toString()),
                if (error.source != null)
                  _DetailRow('المصدر', error.source!),
                if (error.retryAfter != null)
                  _DetailRow(
                    'إعادة المحاولة',
                    DateFormat('yyyy-MM-dd HH:mm:ss').format(
                      DateTime.fromMillisecondsSinceEpoch(error.retryAfter!),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('التفاصيل:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    error.message,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                if (error.stackTrace != null) ...[
                  const SizedBox(height: 12),
                  const Text('Stack Trace:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      error.stackTrace!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _copyError(error);
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  بطاقة الخطأ
// ═══════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
    required this.onTap,
    required this.onCopy,
  });

  final TrackedError error;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  Color get _severityColor {
    switch (error.severity) {
      case LogLevel.critical:
        return Colors.red;
      case LogLevel.error:
        return Colors.deepOrange;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.debug:
        return Colors.grey;
    }
  }

  String get _severityEmoji {
    switch (error.severity) {
      case LogLevel.critical:
        return '🚨';
      case LogLevel.error:
        return '❌';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.debug:
        return '🔍';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // شريط الخطورة
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: _severityColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // أيقونة الفئة
              Icon(error.category.icon, color: error.category.color, size: 24),
              const SizedBox(width: 12),
              // المحتوى
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_severityEmoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            error.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (error.statusCode != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _severityColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'HTTP ${error.statusCode}',
                              style: TextStyle(
                                fontSize: 10,
                                color: _severityColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error.message,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          error.shortTime,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (error.source != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.folder,
                              size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              error.source!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (error.retryAfter != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.timer,
                              size: 12, color: Colors.deepOrange),
                          const SizedBox(width: 4),
                          Text(
                            '⏳ retry',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // زر النسخ السريع
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'نسخ',
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  صف تفاصيل
// ═══════════════════════════════════════════════════════════════

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
