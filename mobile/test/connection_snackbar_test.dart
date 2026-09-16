// ✅ (2026-09-17) طلب المستخدم: «واشعار snake bar يجب ان يكون حقيقي في
// الشاشة الرئيسية» — اختبارات منطق إشعار الاتصال الحقيقي:
//  1. قرار العرض: أول فحص مكتمل يُعرض دائماً / تغيّر الحالة يُعرض /
//     نفس الحالة لا تُعرض / مهلة 10 ثوان تمنع التتابع السريع.
//  2. نوع الإشعار مشتق من نتيجة الفحص الفعلية فقط.
//  3. الرسائل تحمل القياسات الحقيقية (زمن D1 المقاس / سبب الفشل الفعلي)
//     — لا قيم مُزيّفة ولا ادّعاء D1 عند غياب الفحص (null).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/connection_snackbar.dart';

void main() {
  group('connectionSnackbarKindFor — من نتيجة الفحص الحقيقية', () {
    test('Worker ميت → unreachable', () {
      expect(
        connectionSnackbarKindFor(isConnected: false, isD1Connected: null),
        ConnectionSnackbarKind.unreachable,
      );
      expect(
        connectionSnackbarKindFor(isConnected: false, isD1Connected: false),
        ConnectionSnackbarKind.unreachable,
      );
    });

    test('Worker حي وD1 فاشل → d1Down', () {
      expect(
        connectionSnackbarKindFor(isConnected: true, isD1Connected: false),
        ConnectionSnackbarKind.d1Down,
      );
    });

    test('Worker حي وD1 يستجيب أو لم يُفحص بعد → connected', () {
      expect(
        connectionSnackbarKindFor(isConnected: true, isD1Connected: true),
        ConnectionSnackbarKind.connected,
      );
      // null = D1 لم يُفحص (لا جلسة) — ليس فشلاً ولا ادّعاء نجاح D1.
      expect(
        connectionSnackbarKindFor(isConnected: true, isD1Connected: null),
        ConnectionSnackbarKind.connected,
      );
    });
  });

  group('shouldShowConnectionSnackbar — قرار العرض', () {
    final t0 = DateTime(2026, 9, 17, 12, 0, 0);

    test('أول فحص مكتمل (previous=null) يُعرض دائماً', () {
      expect(
        shouldShowConnectionSnackbar(
          previous: null,
          current: (true, true),
          lastShownAt: null,
          now: t0,
        ),
        isTrue,
      );
    });

    test('نفس الحالة (دورة 60 ث) لا تُعرض', () {
      expect(
        shouldShowConnectionSnackbar(
          previous: (true, true),
          current: (true, true),
          lastShownAt: t0.subtract(const Duration(minutes: 1)),
          now: t0,
        ),
        isFalse,
      );
    });

    test('تغيّر الحالة بعد انقضاء المهلة يُعرض', () {
      expect(
        shouldShowConnectionSnackbar(
          previous: (true, true),
          current: (false, null),
          lastShownAt: t0.subtract(const Duration(minutes: 1)),
          now: t0,
        ),
        isTrue,
      );
    });

    test('تغيّر حالة D1 وحده (null→true) يُعرض — اكتمال أول فحص كامل', () {
      expect(
        shouldShowConnectionSnackbar(
          previous: (true, null),
          current: (true, true),
          lastShownAt: t0.subtract(const Duration(minutes: 1)),
          now: t0,
        ),
        isTrue,
      );
    });

    test('تغيّر الحالة داخل مهلة 10 ثوان يُكتم (منع التتابع)', () {
      expect(
        shouldShowConnectionSnackbar(
          previous: (true, true),
          current: (false, null),
          lastShownAt: t0.subtract(const Duration(seconds: 4)),
          now: t0,
        ),
        isFalse,
      );
      // عند حدّ المهلة تماماً (10 ث) يُسمح.
      expect(
        shouldShowConnectionSnackbar(
          previous: (true, true),
          current: (false, null),
          lastShownAt: t0.subtract(const Duration(seconds: 10)),
          now: t0,
        ),
        isTrue,
      );
    });
  });

  group('buildConnectionSnackbar — رسائل من القياسات الفعلية', () {
    test('متصل مع زمن D1 مقاس يحمله النص', () {
      final view = buildConnectionSnackbar(
        ConnectionSnackbarKind.connected,
        d1LatencyMs: 7,
      );
      expect(view.message, contains('D1 يستجيب (7 ms)'));
      expect(view.backgroundColor, isNot(Colors.red));
      expect(view.duration, const Duration(seconds: 3));
    });

    test('متصل بلا فحص D1 (null) لا يدّعي استجابة D1', () {
      final view = buildConnectionSnackbar(
        ConnectionSnackbarKind.connected,
        d1LatencyMs: null,
      );
      expect(view.message, contains('متصل بخادم Cloudflare'));
      expect(view.message, isNot(contains('D1 يستجيب')));
    });

    test('D1 متعطل يعرض السبب الحقيقي', () {
      final view = buildConnectionSnackbar(
        ConnectionSnackbarKind.d1Down,
        d1Error: 'انتهت صلاحية الجلسة — أعد تسجيل الدخول',
      );
      expect(view.message, contains('قاعدة البيانات لا تستجيب'));
      expect(view.message, contains('انتهت صلاحية الجلسة'));
    });

    test('خادم غير قابل للوصول يوضح العمل المحلي', () {
      final view = buildConnectionSnackbar(ConnectionSnackbarKind.unreachable);
      expect(view.message, contains('لا يوجد اتصال بخادم Cloudflare'));
      expect(view.message, contains('محلياً'));
      expect(view.duration, const Duration(seconds: 5));
    });
  });
}
