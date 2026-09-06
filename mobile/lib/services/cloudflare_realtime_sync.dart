// ═══════════════════════════════════════════════════════════════
//  cloudflare_realtime_sync.dart — Realtime via SyncLockDO WebSocket
//
//  خطة الانتقال — المرحلة 3: تنفيذ CloudflareRealtimeSync الكاملة
//  (كانت stub فارغاً في cloudflare_sync_manager.dart:54-60).
//
//  المسار الوحيد المقبول لـ Remote → Local (نفس عقد Appwrite:
//  appwrite_realtime_sync.dart على فرع perf):
//    WS event 'change' → طابور الأحداث المُجدول أدناه → Delta Pull
//    → merge → Drift. لا تطبيق مباشر من الحمولة أبداً — الحدث إشارة
//    فقط، والبيانات تأتي من مسار السحب الموثوق (P0-C checkpoint).
//
//  ضبط المعدل (نفس أرقام فرع perf المثبتة):
//    - debounce 500ms: دفعة أحداث متتالية = حدث واحد
//    - cooldown 15s (SyncConstants.realtimeEventPullCooldown): حد أقصى
//      نظري 4 دورات/دقيقة تحت عاصفة مستمرة
//    - حارس in-flight + طابور trailing: لا سحوبات متزامنة إطلاقاً
//    - echo filter: حدث الدفع الذاتي يُتجاهل (الخادم يبث لكل الجلسات)
//    - recovery pull: حدث واحد بعد كل انقطاع يستدراك المفقود دلتاً
//
//  إعادة الاتصال: أُسّية 1s→60s، حد أقصى 6 محاولات ثم استسلام حتى
//  ensureStarted() (عند عودة التطبيق للواجهة — نمط lifecycle 3.3).
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../utils/debug_log.dart';
import 'cloudflare_dual_run_service.dart';

/// callback السحب الفعلي المُحقن من main.dart — نفس عقد فرع perf:
/// العائد `true` = السحب أُكمل فعلاً؛ `false` = تخطّى/فشل (outbox
/// غير مفرّغ، sync قيد التنفيذ، full sync غير مكتمل…) فتُجدول
/// محاولة متابعة بدل اعتبار التغييرات مُطبّقة.
typedef RemoteChangePull = Future<bool> Function();

/// مرآة `RealtimeMessage` الخادمية (worker/src/sync-lock.ts:23-31).
@visibleForTesting
class CloudflareRealtimeMessage {
  const CloudflareRealtimeMessage({
    required this.type,
    required this.entity,
    required this.entityId,
    required this.timestamp,
    this.operation,
    this.deviceId,
  });

  final String type; // change | lock | unlock | presence
  final String entity;
  final String entityId;
  final String? operation;
  final String? deviceId;
  final int timestamp;

  /// تحليل متسامح: أي شكل غير متوقع → null (تُتجاهل بهدوء —
  /// رسالة مشوهة لا يصح أن تُسقط اتصالاً سليماً).
  static CloudflareRealtimeMessage? tryParse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final Object? type = decoded['type'];
      final Object? entity = decoded['entity'];
      if (type is! String || entity is! String) return null;
      return CloudflareRealtimeMessage(
        type: type,
        entity: entity,
        entityId: (decoded['entityId'] as String?) ?? '',
        operation: decoded['operation'] as String?,
        deviceId: decoded['deviceId'] as String?,
        timestamp: (decoded['timestamp'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Realtime عميل Cloudflare — WebSocket على `/api/realtime` (SyncLockDO).
///
/// Singleton (نمط AppwriteRealtimeSync في فرع perf) — main.dart يحقن
/// نفس المثال في FcmService (شارة UI) ويضبط trigger السحب.
class CloudflareRealtimeSync {
  factory CloudflareRealtimeSync() => _instance;
  CloudflareRealtimeSync._internal();
  static final CloudflareRealtimeSync _instance =
      CloudflareRealtimeSync._internal();

  // ─── شارة UI (نفس عقد الـ stub السابق — FcmService يستخدمهما) ──
  final pendingRemoteChangesCount = ValueNotifier<int>(0);
  final hasRemoteChanges = ValueNotifier<bool>(false);

  /// حالة الاتصال للمراقبة/الاختبارات.
  final connected = ValueNotifier<bool>(false);

  // ─── إعدادات الاتصال (تُضبط من main.dart بعد login المدير) ────
  String? _baseUrl;
  Future<String?> Function()? _tokenProvider;
  String? _currentDeviceId;

  // ─── حالة الـ socket ──────────────────────────────────────────
  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  bool _isListening = false;
  bool _intentionallyStopped = false;
  bool _connectInFlight = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  // ─── محرّك السحب (طابور أحداث بنمط فرع perf) ──────────────────
  RemoteChangePull? _syncTrigger;
  Timer? _debounceTimer;
  Timer? _trailingTimer;
  bool _triggerInFlight = false;
  bool _pullQueued = false;
  DateTime? _lastFireAt;
  bool _recoveryPullPending = false;

  // ثوابت مثبتة من فرع perf (appwrite_realtime_sync.dart:
  // debounce 500ms موثق في ترويسة الملف؛ cooldown 15s =
  // SyncConstants.realtimeEventPullCooldown:168).
  static const Duration _debounceInterval = Duration(milliseconds: 500);
  static const Duration _cooldown = Duration(seconds: 15);
  static const Duration _baseBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 60);

  /// نفس سقف فرع perf (appwrite_realtime_sync.dart:610).
  static const int _maxReconnectAttempts = 6;

  /// Heartbeat 30s (خطة المرحلة 3.1): ping على مستوى البروتوكول —
  /// workerd يجيب تلقائياً، والمقابس الميتة تُكشف خلال pingInterval.
  static const Duration _heartbeat = Duration(seconds: 30);

  bool get isListening => _isListening;

  bool get isConnected =>
      _channel != null && _channel!.closeCode == null && connected.value;

  /// تأخير إعادة الاتصال الأُسّي: 1s, 2s, 4s… بسقف 60s (المرحلة 3.1).
  @visibleForTesting
  static Duration computeBackoffDelay(int attempt) {
    final int shift = attempt < 0 ? 0 : (attempt > 10 ? 10 : attempt);
    final int seconds = _baseBackoff.inSeconds * (1 << shift);
    return Duration(
      seconds: seconds > _maxBackoff.inSeconds
          ? _maxBackoff.inSeconds
          : seconds,
    );
  }

  // ─── التهيئة والتوصيل ────────────────────────────────────────

  /// توافق مع عقد الـ stub السابق (main.dart/FCM كانا يستدعيانها).
  Future<void> initialize({String? deviceId}) async {
    _currentDeviceId = deviceId;
  }

  /// يُستدعى مرة واحدة من wiring التطبيق — token يُجلب حديثاً عند كل
  /// اتصال (JWT صلاحيته 24h والمدير يعيد login تلقائياً).
  void configure({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
  }) {
    _baseUrl = baseUrl;
    _tokenProvider = tokenProvider;
  }

  /// حقن مسار السحب الفعلي (delta-only من المدير).
  void setSyncTrigger(RemoteChangePull trigger) {
    _syncTrigger = trigger;
  }

  /// بدء الاستماع (idempotent).
  Future<void> start() async {
    // ✅ المرحلة 6 (Dual-Run): المفتاح البعيد يعطّل Realtime أيضاً
    if (!await CloudflareDualRunService().isCloudflareSyncEnabled()) {
      dwarn(() => 'realtime: disabled remotely (kill switch) — not starting');
      return;
    }
    if (_isListening && !_intentionallyStopped) return;
    _isListening = true;
    _intentionallyStopped = false;
    await _connect();
  }

  /// إيقاف مقصود (background — المرحلة 3.3): لا إعادة اتصال بعده.
  /// (Future<void> لتوافق perf call-sites التي تعمل await realtime.stop()).
  Future<void> stop() async {
    _intentionallyStopped = true;
    _isListening = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _trailingTimer?.cancel();
    _trailingTimer = null;
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    try {
      unawaited(_channel?.sink.close());
    } catch (_) {
      // مقبس ميت بالفعل — الإغلاق ليس عملية حرجة هنا
    }
    _channel = null;
    connected.value = false;
    resetRemoteChangesFlag();
  }

  /// تصفير شارة الـ UI بعد نجاح السحب — نفس عقد فرع perf
  /// (appwrite_realtime_sync.dart:602-607).
  void resetRemoteChangesFlag() {
    hasRemoteChanges.value = false;
    pendingRemoteChangesCount.value = 0;
  }

  /// عزل حالة الـ singleton بين الاختبارات (لا يُستدعى في الإنتاج).
  @visibleForTesting
  void resetForTest() {
    unawaited(stop());
    _reconnectAttempt = 0;
    _recoveryPullPending = false;
    _triggerInFlight = false;
    _pullQueued = false;
    _lastFireAt = null;
    _syncTrigger = null;
    _baseUrl = null;
    _tokenProvider = null;
    _currentDeviceId = null;
    connected.value = false;
    hasRemoteChanges.value = false;
    pendingRemoteChangesCount.value = 0;
  }

  /// استئناف بعد stop()/استسلام إعادة الاتصال (foreground — 3.3):
  /// يصفّر عدّاد المحاولات ويجرّب فوراً.
  Future<void> ensureStarted() async {
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_intentionallyStopped || !_isListening) {
      _intentionallyStopped = false;
      _isListening = true;
    }
    if (isConnected || _connectInFlight) return;
    await _connect();
  }

  Future<void> _connect() async {
    if (!_isListening || _intentionallyStopped || _connectInFlight) return;

    final String? token = await _tokenProvider?.call();
    if (!_isListening || _intentionallyStopped) return;
    final String baseUrl = _baseUrl ?? '';
    if (token == null || token.isEmpty || baseUrl.isEmpty) {
      // لم يكتمل login بعد — أعادة محاولة بأُسّية (start() بعد login
      // عبر ensureStarted() يقطع الطريق أيضاً).
      dwarn('realtime: connect skipped (no token/url yet)');
      _scheduleReconnect();
      return;
    }

    _connectInFlight = true;
    try {
      final Uri uri = Uri.parse('$baseUrl/api/realtime').replace(
        queryParameters: <String, String>{
          'deviceId': _currentDeviceId ?? 'unknown',
          'entity': '*',
        },
      );
      final IOWebSocketChannel channel = IOWebSocketChannel.connect(
        uri,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        pingInterval: _heartbeat,
      );
      // يُخزَّن فوراً حتى لو فشل ready — مسار الخطأ يلغيه صراحةً
      // (يلبي cancel_subscriptions بلا تسريب).
      _socketSub = channel.stream.listen(
        _onData,
        onDone: _onSocketClosed,
        onError: (Object error) => _onSocketClosed(),
      );
      try {
        await channel.ready;
      } catch (_) {
        await _socketSub?.cancel();
        _socketSub = null;
        rethrow;
      }
      _channel = channel;
      _reconnectAttempt = 0;
      connected.value = true;
      debugPrint('✅ Cloudflare realtime connected (${uri.host})');
      await _onSubscriptionEstablished();
    } catch (e, st) {
      dwarn(() => 'realtime: connect failed: $e\n$st');
      connected.value = false;
      _scheduleReconnect();
    } finally {
      _connectInFlight = false;
    }
  }

  // ─── معالجة الرسائل ──────────────────────────────────────────

  void _onData(dynamic data) {
    final CloudflareRealtimeMessage? msg = CloudflareRealtimeMessage.tryParse(
      data,
    );
    if (msg == null) return;
    handleIncomingMessage(msg);
  }

  /// نواة القرار القابلة للاختبار بلا شبكة.
  @visibleForTesting
  void handleIncomingMessage(CloudflareRealtimeMessage msg) {
    // echo filter: الخادم يبث أحداث change لكل الجلسات شاملاً
    // جهاز الدفع نفسه — حدثنا الذاتي لا يُطلق سحباً.
    if (msg.deviceId != null && msg.deviceId == _currentDeviceId) return;

    if (msg.type == 'change') {
      // شارة UI (عقد FcmService:262-264) + حماية فيضان بنمط perf
      if (!hasRemoteChanges.value) {
        hasRemoteChanges.value = true;
      }
      pendingRemoteChangesCount.value++;
      _onChangeEvent();
    }
    // presence/lock/unlock: لا سحب — الأقفال تُدار خادمياً،
    // والانضمام/المغادرة ليست تغيّر بيانات.
  }

  // ─── طابور أحداث السحب ───────────────────────────────────────

  void _onChangeEvent() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceInterval, _firePull);
  }

  Duration _cooldownRemaining() {
    final DateTime? last = _lastFireAt;
    if (last == null) return Duration.zero;
    // clock.now() (لا DateTime.now()) — قابل للحقن في الاختبار
    // (FakeAsync) ومتسق مع وقت المنطقة الموحّد.
    final Duration elapsed = clock.now().difference(last);
    return elapsed >= _cooldown ? Duration.zero : _cooldown - elapsed;
  }

  Future<void> _firePull() async {
    if (_syncTrigger == null) return;
    if (_triggerInFlight) {
      _pullQueued = true;
      return;
    }
    final Duration remaining = _cooldownRemaining();
    if (remaining > Duration.zero) {
      _pullQueued = true;
      _trailingTimer?.cancel();
      _trailingTimer = Timer(remaining, _fireTrailingPull);
      return;
    }
    await _executePull();
  }

  Future<void> _fireTrailingPull() async {
    if (_triggerInFlight || !_pullQueued) return;
    final Duration remaining = _cooldownRemaining();
    if (remaining > Duration.zero) {
      _trailingTimer?.cancel();
      _trailingTimer = Timer(remaining, _fireTrailingPull);
      return;
    }
    await _executePull();
  }

  Future<void> _executePull() async {
    _triggerInFlight = true;
    _pullQueued = false;
    _lastFireAt = clock.now();
    final RemoteChangePull? trigger = _syncTrigger;
    try {
      if (trigger != null) {
        final bool ok = await trigger();
        if (!ok) {
          dwarn(() => 'realtime: pull skipped/failed — follow-up queued');
          // فشل السحب لا يهضم الحدث: نجدول متابعة بعد cooldown
          _pullQueued = true;
        } else {
          // نجاح السحب يستهلك الشارة (نفس عقد perf)
          resetRemoteChangesFlag();
        }
      }
    } catch (e, st) {
      dwarn(() => 'realtime: pull error: $e\n$st');
      _pullQueued = true;
    } finally {
      _triggerInFlight = false;
    }
    if (_pullQueued) {
      final Duration remaining = _cooldownRemaining();
      if (remaining > Duration.zero) {
        _trailingTimer?.cancel();
        _trailingTimer = Timer(remaining, _fireTrailingPull);
      } else {
        await _executePull();
      }
    }
  }

  // ─── الاسترداد وإعادة الاتصال ────────────────────────────────

  Future<void> _onSubscriptionEstablished() async {
    if (_recoveryPullPending) {
      _recoveryPullPending = false;
      // حدث واحد يستدراك كل ما فات أثناء الانقطاع (delta pull
      // يجلب كل التغييرات منذ المؤشر — الدمج آمن).
      _onChangeEvent();
    }
  }

  void _onSocketClosed() {
    connected.value = false;
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    _channel = null;
    if (_intentionallyStopped || !_isListening) return;
    // انقطاع غير مقصود — استرداد + إعادة اتصال
    _recoveryPullPending = true;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionallyStopped || !_isListening) return;
    if (_reconnectTimer != null || _connectInFlight) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      dwarn(
        () =>
            'realtime: giving up after $_reconnectAttempt attempts — '
            'ensureStarted() on app resume will retry',
      );
      return;
    }
    final Duration delay = computeBackoffDelay(_reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }
}
