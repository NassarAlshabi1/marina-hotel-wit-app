// lib/utils/connection_snackbar.dart
//
// ✅ (2026-09-17) طلب المستخدم: «واشعار snake bar يجب ان يكون حقيقي في
// الشاشة الرئيسية» — إشعار SnackBar حقيقي في الشاشة الرئيسية يعرض نتيجة
// فحص الاتصال التلقائي مع Cloudflare Worker D1 (المهمة 7) — لا قيم
// مُزيّفة ولا نصوص عامة: الرسالة تُبنى من نتيجة الفحص الفعلية (حالة
// الـ Worker + حالة D1 + زمن الاستجابة المقاس + سبب الفشل).
//
// المنطق نقيّ وقابل للاختبار (بلا Flutter) — HomeShell يستمع إلى
// connectionStatusProvider ويقرر عبر هذه الدوال متى يُعرض الإشعار:
// - أول فحص مكتمل بعد فتح التطبيق (أو العودة من الخلفية) → إشعار دائماً.
// - تغيّر الحالة الفعلية (اتصال/انقطاع/تغيّر حالة D1) → إشعار.
// - دورة 60 ثانية بنفس الحالة → لا إشعار (منع الإزعاج).
// - مهلة 10 ثوان بين إشعارين على الأقل (تفادي تتابع سريع).

import 'package:flutter/material.dart';

/// نوع إشعار الاتصال — مشتق من نتيجة الفحص الحقيقية فقط.
enum ConnectionSnackbarKind {
  /// الـ Worker حي (وD1 إما يستجيب أو لم يُفحص بعد لغياب الجلسة).
  connected,

  /// الـ Worker حي لكن قاعدة D1 لا تستجيب عبر /api/health/d1.
  d1Down,

  /// الـ Worker نفسه غير قابل للوصول.
  unreachable,
}

/// بصمة الحالة الفعلية — أساس قرار «تغيّرت الحالة؟».
///
/// isD1Connected null = لم يُفحص D1 بعد (لا جلسة دخول أو الـ Worker
/// مُتوقف) — تمييزه عن true/false ضروري: null→true يعني اكتمال أول فحص
/// حقيقي للمسار الكامل ويستحق إشعاراً.
typedef ConnectionSignature = (bool isConnected, bool? isD1Connected);

/// نوع الإشعار المناسب لنتيجة فحص حقيقية.
ConnectionSnackbarKind connectionSnackbarKindFor({
  required bool isConnected,
  required bool? isD1Connected,
}) {
  if (!isConnected) {
    return ConnectionSnackbarKind.unreachable;
  }
  if (isD1Connected == false) {
    return ConnectionSnackbarKind.d1Down;
  }
  return ConnectionSnackbarKind.connected;
}

/// قرار عرض الإشعار — نقيّ وقابل للاختبار بلا Flutter.
///
/// [previous] البصمة المعروضة آخر مرة (null = لم يُعرض شيء بعد).
/// [current] بصمة نتيجة الفحص المكتملة الحالية.
/// [lastShownAt] وقت آخر إشعار معروض (null = أبداً).
/// [now] الوقت الحالي (لحساب مهلة الإزعاج).
/// [minInterval] الحد الأدنى بين إشعارين (10 ثوان افتراضياً).
bool shouldShowConnectionSnackbar({
  required ConnectionSignature? previous,
  required ConnectionSignature current,
  required DateTime? lastShownAt,
  required DateTime now,
  Duration minInterval = const Duration(seconds: 10),
}) {
  // أول فحص مكتمل — يُعرض دائماً (طلب المستخدم: إشعار حقيقي عند الفتح).
  if (previous == null) {
    return true;
  }
  // نفس الحالة الفعلية — لا إشعار (دورة 60 ثانية صامتة).
  if (previous == current) {
    return false;
  }
  // الحالة تغيّرت — احترم مهلة الإزعاج فقط.
  if (lastShownAt != null && now.difference(lastShownAt).abs() < minInterval) {
    return false;
  }
  return true;
}

/// بيانات عرض الإشعار — الرسائل تُبنى من القياسات الفعلية.
class ConnectionSnackbarView {
  const ConnectionSnackbarView({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.duration,
  });
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final Duration duration;
}

/// بناء رسالة الإشعار من نتيجة الفحص الحقيقية.
///
/// [d1LatencyMs] زمن استجابة D1 المقاس خادمياً (يُعرض فقط عند توفره).
/// [d1Error] سبب فشل D1 الحقيقي (يُعرض عند فشل D1 فقط).
ConnectionSnackbarView buildConnectionSnackbar(
  ConnectionSnackbarKind kind, {
  int? d1LatencyMs,
  String? d1Error,
}) {
  switch (kind) {
    case ConnectionSnackbarKind.connected:
      final d1Part = d1LatencyMs == null
          ? ''
          : ' — D1 يستجيب ($d1LatencyMs ms)';
      return ConnectionSnackbarView(
        message: '☁️ متصل بخادم Cloudflare$d1Part',
        backgroundColor: const Color(0xFF2E7D32),
        icon: Icons.cloud_done,
        duration: const Duration(seconds: 3),
      );
    case ConnectionSnackbarKind.d1Down:
      final reason = (d1Error == null || d1Error.isEmpty) ? '' : ' ($d1Error)';
      return ConnectionSnackbarView(
        message: '⚠️ الخادم يعمل لكن قاعدة البيانات لا تستجيب$reason',
        backgroundColor: const Color(0xFFEF6C00),
        icon: Icons.cloud_queue,
        duration: const Duration(seconds: 5),
      );
    case ConnectionSnackbarKind.unreachable:
      return const ConnectionSnackbarView(
        message:
            '📡 لا يوجد اتصال بخادم Cloudflare — '
            'البيانات تعمل محلياً حتى عودة الاتصال',
        backgroundColor: Color(0xFFC62828),
        icon: Icons.cloud_off,
        duration: Duration(seconds: 5),
      );
  }
}
