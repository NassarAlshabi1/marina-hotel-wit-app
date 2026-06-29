import 'dart:convert';

class SecureStorage {
  static const _staticSecret = 'marina_hotel_sync_secret_2024';
  static const _prefix = 'ENC:';

  static String getEncryptionKey(String? deviceId) {
    // For shared settings synced across devices, use constant key
    // SECURITY: XOR is obfuscation only - use encrypt package for production
    final bytes = utf8.encode(_staticSecret);
    final keyBytes = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      keyBytes.add((bytes[i] * 7 + i * 13) % 256);
    }
    return base64.encode(keyBytes.sublist(0, 32));
  }

  static String encryptValue(String plain, String key) {
    final keyBytes = utf8.encode(key);
    final plainBytes = utf8.encode(plain);
    final encrypted = <int>[];
    for (var i = 0; i < plainBytes.length; i++) {
      encrypted.add(plainBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return '$_prefix${base64.encode(encrypted)}';
  }

  static String decryptValue(String value, String key) {
    if (!value.startsWith(_prefix)) {
      return value;
    }
    final cipherText = value.substring(_prefix.length);
    try {
      final keyBytes = utf8.encode(key);
      final cipherBytes = base64.decode(cipherText);
      final decrypted = <int>[];
      for (var i = 0; i < cipherBytes.length; i++) {
        decrypted.add(cipherBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      return utf8.decode(decrypted);
    } catch (e) {
      return value;
    }
  }
}
