/// File Size Formatting Utilities
/// 
/// مركز موحد لجميع عمليات تنسيق أحجام الملفات
class FileSizeFormatter {
  FileSizeFormatter._();

  /// Format bytes to human readable format (KB, MB, GB)
  static String formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return '0 بايت';

    const suffixes = ['بايت', 'كيلوبايت', 'ميجابايت', 'جيجابايت', 'تيرابايت'];
    final i = (bytes.bitLength - 1) ~/ 10;
    
    if (i >= suffixes.length) {
      return '${(bytes / (1 << ((suffixes.length - 1) * 10))).toStringAsFixed(decimals)} ${suffixes.last}';
    }
    
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Format bytes to English format (KB, MB, GB)
  static String formatBytesEnglish(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes.bitLength - 1) ~/ 10;
    
    if (i >= suffixes.length) {
      return '${(bytes / (1 << ((suffixes.length - 1) * 10))).toStringAsFixed(decimals)} ${suffixes.last}';
    }
    
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Format bytes to short format (5.2M, 1.3G)
  static String formatBytesShort(int bytes) {
    if (bytes <= 0) return '0';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }

  /// Convert MB to bytes
  static int mbToBytes(double mb) {
    return (mb * 1024 * 1024).round();
  }

  /// Convert bytes to MB
  static double bytesToMb(int bytes) {
    return bytes / (1024 * 1024);
  }

  /// Convert GB to bytes
  static int gbToBytes(double gb) {
    return (gb * 1024 * 1024 * 1024).round();
  }

  /// Convert bytes to GB
  static double bytesToGb(int bytes) {
    return bytes / (1024 * 1024 * 1024);
  }

  /// Format download/upload speed (KB/s, MB/s)
  static String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond بايت/ث';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} كيلوبايت/ث';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} ميجابايت/ث';
    }
  }

  /// Calculate percentage
  static String formatPercentage(int current, int total, {int decimals = 1}) {
    if (total == 0) return '0%';
    final percentage = (current / total * 100);
    return '${percentage.toStringAsFixed(decimals)}%';
  }

  /// Format progress (50 MB / 100 MB - 50%)
  static String formatProgress(int current, int total) {
    final currentStr = formatBytes(current);
    final totalStr = formatBytes(total);
    final percentage = formatPercentage(current, total);
    return '$currentStr / $totalStr ($percentage)';
  }
}
