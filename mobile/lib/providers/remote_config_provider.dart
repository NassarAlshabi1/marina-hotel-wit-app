// lib/providers/remote_config_provider.dart
// Riverpod Provider لـ Remote Config

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/remote_config_service.dart';

/// Provider لخدمة Remote Config
final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  return RemoteConfigService.instance;
});

/// Provider لجميع قيم Remote Config كخريطة
final remoteConfigValuesProvider = Provider<Map<String, dynamic>>((ref) {
  return ref.watch(remoteConfigServiceProvider).getAllValues();
});

/// Provider لمعلومات تشخيص Remote Config
final remoteConfigDiagnosticsProvider = Provider<Map<String, dynamic>>((ref) {
  return ref.watch(remoteConfigServiceProvider).diagnostics;
});

/// Provider لساعة تسجيل الخروج
final checkoutHourProvider = Provider<int>((ref) {
  return ref.watch(remoteConfigServiceProvider).checkoutHour;
});

/// Provider لحد الديون المتأخرة
final latePaymentThresholdProvider = Provider<int>((ref) {
  return ref.watch(remoteConfigServiceProvider).latePaymentThresholdDays;
});

/// Provider لتفعيل WhatsApp
final whatsappEnabledProvider = Provider<bool>((ref) {
  return ref.watch(remoteConfigServiceProvider).whatsappEnabled;
});
