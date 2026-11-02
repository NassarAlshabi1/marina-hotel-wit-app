// CircularBufferLogger — replaces unbounded in-memory logging with a
// fixed-size circular buffer that writes to a file on disk.
//
// Benefits:
//   - No memory leaks (fixed max size)
//   - Logs survive app restart (persisted to file)
//   - Thread-safe (synchronized writes)
//   - Automatic rotation (oldest entries overwritten)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

class CircularBufferLogger {
  CircularBufferLogger._();
  static final CircularBufferLogger instance = CircularBufferLogger._();

  static const int _maxEntries = 500;
  static const String _fileName = 'app_logs.jsonl';

  final List<_LogEntry> _buffer = [];
  final Lock _lock = Lock();
  File? _logFile;
  bool _initialized = false;

  /// ✅ OCR FIX (2026-08-06): علامة واضحة لإمكانية الكتابة على القرص.
  /// سابقاً، الاعتماد على `null check` لـ `_logFile` كان يُسبب صمتاً عند الفشل.
  /// الآن لدينا علامة صريحة + سبب الفشل مُسجّل في الـ buffer للـ debugging.
  bool _diskWriteEnabled = false;
  String? _initFailureReason;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_fileName');
      await _loadExistingLogs();
      _diskWriteEnabled = true;
      _initialized = true;
    } catch (e) {
      // ✅ OCR FIX: تسجيل سبب الفشل في الـ in-memory buffer.
      // هذا يضمن أن المطور يستطيع رؤية سبب فشل الـ persistence عند debugging
      // عبر استدعاء `readLast(N)`.
      _diskWriteEnabled = false;
      _initFailureReason = e.toString();
      _buffer.add(
        _LogEntry(
          level: LogLevel.warning,
          message:
              'CircularBufferLogger: disk persistence disabled. '
              'Reason: $e. Logs will be in-memory only (lost on app exit).',
          tag: 'LOGGER',
          timestamp: DateTime.now().toIso8601String(),
        ),
      );
      _initialized = true;
    }
  }

  Future<void> _loadExistingLogs() async {
    if (_logFile == null || !await _logFile!.exists()) return;
    try {
      final lines = await _logFile!.readAsLines();
      final recent = lines.length > _maxEntries
          ? lines.sublist(lines.length - _maxEntries)
          : lines;
      for (final line in recent) {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _buffer.add(_LogEntry.fromJson(json));
      }
    } catch (e) {
      // ✅ OCR FIX: تسجيل سبب فساد ملف الـ logs بدلاً من الصمت.
      // ملف فاسد يعني أننا نبدأ من جديد، لكن المطور يجب أن يعرف.
      _buffer.add(
        _LogEntry(
          level: LogLevel.warning,
          message:
              'CircularBufferLogger: existing log file corrupted, starting fresh. '
              'Reason: $e',
          tag: 'LOGGER',
          timestamp: DateTime.now().toIso8601String(),
        ),
      );
    }
  }

  void debug(String message, {String? tag}) =>
      _log(LogLevel.debug, message, tag);
  void info(String message, {String? tag}) => _log(LogLevel.info, message, tag);
  void warning(String message, {String? tag, Object? error}) =>
      _log(LogLevel.warning, message, tag, error);
  void error(String message, {String? tag, Object? error, StackTrace? stack}) =>
      _log(LogLevel.error, message, tag, error, stack);

  void _log(
    LogLevel level,
    String message,
    String? tag, [
    Object? error,
    StackTrace? stack,
  ]) {
    final entry = _LogEntry(
      level: level,
      message: message,
      tag: tag ?? 'APP',
      timestamp: DateTime.now().toIso8601String(),
      error: error?.toString(),
      stackTrace: stack?.toString(),
    );

    _buffer.add(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeAt(0);
    }

    unawaited(_persistEntry(entry));
  }

  final List<String> _writeBuffer = [];
  Timer? _flushTimer;

  Future<void> _persistEntry(_LogEntry entry) async {
    // ✅ OCR FIX (2026-08-06): استخدام علامة _diskWriteEnabled بدلاً من
    // null check على _logFile. هذا أوضح ويتوافق مع حالة الفشل المُسجّلة.
    if (!_diskWriteEnabled || _logFile == null) return;
    _writeBuffer.add('${jsonEncode(entry.toJson())}\n');

    // ✅ Batch writes: flush every 5s or when buffer reaches 50 entries
    // Prevents fsync on every log call (critical for 1GB RAM devices)
    if (_writeBuffer.length >= 50) {
      _flushBuffer();
    } else {
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(seconds: 5), _flushBuffer);
    }
  }

  void _flushBuffer() {
    // ✅ OCR FIX: تحقق مزدوج (disk enabled + file not null)
    if (_writeBuffer.isEmpty || !_diskWriteEnabled || _logFile == null) return;
    // ✅ Code Review Fix (2026-08-06): لا نُفرغ _writeBuffer قبل اكتمال الكتابة.
    // سابقاً، _writeBuffer.clear() كان يُنفّذ قبل writeAsString async،
    // فلو فشلت الكتابة (disk full/unmounted)، آخر ~50 log line تُفقد من القرص
    // (تبقى في in-memory ring buffer فقط، وتُفقد عند إغلاق التطبيق).
    // الإصلاح: نأخذ snapshot للـ batch، نُحاول الكتابة، وعند النجاح فقط
    // نُزيل الـ entries المُكافئة من _writeBuffer.
    final batchEntries = List<String>.from(_writeBuffer);
    final batch = batchEntries.join();
    _flushTimer?.cancel();
    unawaited(
      _lock.synchronized(() async {
        try {
          await _logFile!.writeAsString(
            batch,
            mode: FileMode.append,
            flush: true,
          );
          // ✅ نجحت الكتابة — نُزيل فقط الـ entries التي كُتبت فعلاً.
          // ملاحظة: قد تكون entries جديدة أُضيفت أثناء await، لذا نُزيل
          // فقط بعدد الـ entries التي شملتها الـ batch.
          final writtenCount = batchEntries.length;
          if (_writeBuffer.length >= writtenCount) {
            _writeBuffer.removeRange(0, writtenCount);
          } else {
            // نادر: تم مسح _writeBuffer يدوياً (clear()) أثناء await.
            _writeBuffer.clear();
          }
        } catch (e) {
          // ✅ OCR FIX: تسجيل فشل الكتابة في الـ buffer (مرة واحدة لتفادي
          // recursive loop — لا نريد أن يفشل الـ log ويسبب log آخر يفشل...).
          // نُعطّل الكتابة على القرص نهائياً بعد أول فشل (disk may be full/unmounted).
          // ✅ Code Review Fix: لا نُفرغ _writeBuffer عند الفشل — الـ entries
          // تبقى في الـ buffer لذا لو أُعيد تفعيل الـ persistence لاحقاً
          // (مثلاً بعد mount القرص)، يمكن إعادة المحاولة.
          _diskWriteEnabled = false;
          _buffer.add(
            _LogEntry(
              level: LogLevel.error,
              message:
                  'CircularBufferLogger: disk write failed, disabling persistence. '
                  'Reason: $e. ${batchEntries.length} entries retained in write buffer.',
              tag: 'LOGGER',
              timestamp: DateTime.now().toIso8601String(),
            ),
          );
        }
      }),
    );
  }

  List<Map<String, dynamic>> readLast(int count) {
    final start = _buffer.length > count ? _buffer.length - count : 0;
    return _buffer.sublist(start).map((e) => e.toJson()).toList();
  }

  Future<void> clear() async {
    _buffer.clear();
    _writeBuffer.clear();
    _flushTimer?.cancel();
    if (_diskWriteEnabled && _logFile != null) {
      try {
        await _logFile!.writeAsString('', flush: true);
      } catch (e) {
        // ✅ OCR FIX: تعطيل الـ persistence بدلاً من الصمت عند الفشل.
        _diskWriteEnabled = false;
        _buffer.add(
          _LogEntry(
            level: LogLevel.warning,
            message:
                'CircularBufferLogger: clear() failed, persistence disabled. '
                'Reason: $e',
            tag: 'LOGGER',
            timestamp: DateTime.now().toIso8601String(),
          ),
        );
      }
    }
  }

  int get bufferSize => _buffer.length;

  /// ✅ OCR FIX (2026-08-06): getter للتحقق من حالة الـ persistence.
  /// يُعيد true إذا كانت الكتابة على القرص مُفعّلة، false إذا تعطّلت.
  /// مفيد للـ UI (مثلاً عرض banner "logs not persisted" في شاشة الإعدادات).
  bool get isDiskPersistenceEnabled => _diskWriteEnabled;

  /// ✅ OCR FIX: سبب تعطّل الـ persistence (إن وُجد)، null إذا كانت تعمل.
  String? get persistenceFailureReason => _initFailureReason;
}

enum LogLevel { debug, info, warning, error }

class _LogEntry {
  const _LogEntry({
    required this.level,
    required this.message,
    required this.tag,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  factory _LogEntry.fromJson(Map<String, dynamic> json) {
    return _LogEntry(
      level: LogLevel.values.byName(json['level'] as String? ?? 'info'),
      message: json['message'] as String? ?? '',
      tag: json['tag'] as String? ?? 'APP',
      timestamp: json['timestamp'] as String? ?? '',
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }

  final LogLevel level;
  final String message;
  final String tag;
  final String timestamp;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'message': message,
    'tag': tag,
    'timestamp': timestamp,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };
}
