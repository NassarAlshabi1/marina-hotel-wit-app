import 'package:flutter/material.dart';

/// Log Level Constants
enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

/// UI Constants for different log levels and statuses
class UIConstants {
  UIConstants._();

  // ===== Log Level Colors =====
  static Color getColorForLogLevel(LogLevel? level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.critical:
        return Colors.purple.shade900;
      default:
        return Colors.grey;
    }
  }

  // ===== Log Level Icons =====
  static IconData getIconForLogLevel(LogLevel? level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warning:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
      case LogLevel.critical:
        return Icons.dangerous;
      default:
        return Icons.help_outline;
    }
  }

  // ===== Status Colors =====
  static Color getColorForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'نشط':
      case 'active':
      case 'متاح':
      case 'available':
      case 'مكتمل':
      case 'completed':
      case 'نجح':
      case 'success':
        return Colors.green;
      
      case 'غير نشط':
      case 'inactive':
      case 'مشغول':
      case 'occupied':
      case 'ملغي':
      case 'cancelled':
      case 'فشل':
      case 'failed':
      case 'خطأ':
      case 'error':
        return Colors.red;
      
      case 'معلق':
      case 'pending':
      case 'قيد الانتظار':
      case 'waiting':
        return Colors.orange;
      
      case 'صيانة':
      case 'maintenance':
      case 'قيد التنفيذ':
      case 'in_progress':
        return Colors.blue;
      
      default:
        return Colors.grey;
    }
  }

  // ===== Status Icons =====
  static IconData getIconForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'نشط':
      case 'active':
      case 'متاح':
      case 'available':
        return Icons.check_circle;
      
      case 'مكتمل':
      case 'completed':
      case 'نجح':
      case 'success':
        return Icons.check_circle_outline;
      
      case 'غير نشط':
      case 'inactive':
        return Icons.cancel;
      
      case 'مشغول':
      case 'occupied':
        return Icons.block;
      
      case 'ملغي':
      case 'cancelled':
        return Icons.close;
      
      case 'فشل':
      case 'failed':
      case 'خطأ':
      case 'error':
        return Icons.error;
      
      case 'معلق':
      case 'pending':
      case 'قيد الانتظار':
      case 'waiting':
        return Icons.pending;
      
      case 'صيانة':
      case 'maintenance':
        return Icons.build;
      
      case 'قيد التنفيذ':
      case 'in_progress':
        return Icons.sync;
      
      default:
        return Icons.help_outline;
    }
  }

  // ===== Sync Status Colors =====
  static Color getColorForSyncStatus(String status) {
    switch (status.toLowerCase()) {
      case 'synced':
      case 'مزامن':
        return Colors.green;
      case 'pending':
      case 'معلق':
        return Colors.orange;
      case 'syncing':
      case 'جاري المزامنة':
        return Colors.blue;
      case 'error':
      case 'خطأ':
        return Colors.red;
      case 'conflict':
      case 'تعارض':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // ===== Priority Colors =====
  static Color getColorForPriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'عالية':
        return Colors.red;
      case 'medium':
      case 'متوسطة':
        return Colors.orange;
      case 'low':
      case 'منخفضة':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // ===== Connection Status Colors =====
  static Color getColorForConnectionStatus(bool isConnected) {
    return isConnected ? Colors.green : Colors.red;
  }

  // ===== Battery Level Colors =====
  static Color getColorForBatteryLevel(double level) {
    if (level > 0.5) return Colors.green;
    if (level > 0.2) return Colors.orange;
    return Colors.red;
  }

  // ===== Progress Colors =====
  static Color getColorForProgress(double progress) {
    if (progress >= 0.8) return Colors.green;
    if (progress >= 0.5) return Colors.blue;
    if (progress >= 0.3) return Colors.orange;
    return Colors.red;
  }

  // ===== Feature Colors =====
  static const Color employeeColor = Color(0xFF673AB7); // Purple
  static const Color guestColor = Color(0xFF009688); // Teal
  static const Color roomColor = Color(0xFF3F51B5); // Indigo
  static const Color userColor = Color(0xFF9C27B0); // Purple
  static const Color maintenanceColor = Color(0xFFFF9800); // Orange
  static const Color syncColor = Color(0xFF2196F3); // Blue
  static const Color backupColor = Color(0xFF4CAF50); // Green

  // ===== Common Icons =====
  static const IconData employeeIcon = Icons.people;
  static const IconData guestIcon = Icons.person;
  static const IconData roomIcon = Icons.hotel;
  static const IconData userIcon = Icons.admin_panel_settings;
  static const IconData maintenanceIcon = Icons.build;
  static const IconData syncIcon = Icons.sync;
  static const IconData backupIcon = Icons.backup;
  static const IconData settingsIcon = Icons.settings;
  static const IconData securityIcon = Icons.security;
  static const IconData databaseIcon = Icons.storage;
  static const IconData cloudIcon = Icons.cloud;
  static const IconData downloadIcon = Icons.download;
  static const IconData uploadIcon = Icons.upload;

  // ===== Spacing =====
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 16.0;
  static const double spacingLG = 24.0;
  static const double spacingXL = 32.0;

  // ===== Border Radius =====
  static const double radiusSM = 4.0;
  static const double radiusMD = 8.0;
  static const double radiusLG = 12.0;
  static const double radiusXL = 16.0;

  // ===== Icon Sizes =====
  static const double iconSizeSM = 16.0;
  static const double iconSizeMD = 24.0;
  static const double iconSizeLG = 32.0;
  static const double iconSizeXL = 48.0;

  // ===== Animation Durations =====
  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
}
