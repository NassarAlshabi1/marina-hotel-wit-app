import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/secure_storage.dart';

void main() {
  const testKey = 'VQngYXPLjdebdGvs+QMdXsiDKySEJBhlks5zDTUxTLk=';

  group('SecureStorage', () {
    group('getEncryptionKey', () {
      test('should return a non-empty base64 key', () {
        final key = SecureStorage.getEncryptionKey('device-123');
        expect(key, isNotEmpty);
        // Base64 encoded SHA-256 = 44 chars
        expect(key.length, 44);
      });

      test('should return same key for same secret regardless of deviceId', () {
        final key1 = SecureStorage.getEncryptionKey('device-1');
        final key2 = SecureStorage.getEncryptionKey('device-2');
        expect(key1, equals(key2));
      });
    });

    group('encryptValue / decryptValue (AES)', () {
      test('should encrypt and decrypt a simple string', () {
        const plain = 'Hello World';
        final encrypted = SecureStorage.encryptValue(plain, testKey);
        final decrypted = SecureStorage.decryptValue(encrypted, testKey);
        expect(decrypted, equals(plain));
      });

      test('should encrypt and decrypt Arabic text', () {
        const plain = 'فندق مارينا — حجز جديد';
        final encrypted = SecureStorage.encryptValue(plain, testKey);
        final decrypted = SecureStorage.decryptValue(encrypted, testKey);
        expect(decrypted, equals(plain));
      });

      test('should encrypt and decrypt a long string', () {
        final plain = 'A' * 1000;
        final encrypted = SecureStorage.encryptValue(plain, testKey);
        final decrypted = SecureStorage.decryptValue(encrypted, testKey);
        expect(decrypted, equals(plain));
      });

      test(
        'should produce different ciphertexts for same plaintext (random IV)',
        () {
          const plain = 'same text';
          final enc1 = SecureStorage.encryptValue(plain, testKey);
          final enc2 = SecureStorage.encryptValue(plain, testKey);
          expect(enc1, isNot(equals(enc2)));
        },
      );

      test('encrypted value should start with ENC:AES: prefix', () {
        final encrypted = SecureStorage.encryptValue('test', testKey);
        expect(encrypted.startsWith('ENC:AES:'), isTrue);
      });
    });

    group('decryptValue backward compat', () {
      test('should return non-encrypted values as-is', () {
        const plain = 'plain text without encryption';
        final result = SecureStorage.decryptValue(plain, testKey);
        expect(result, equals(plain));
      });

      test('should handle empty string', () {
        final result = SecureStorage.decryptValue('', testKey);
        expect(result, equals(''));
      });
    });

    group('isEncrypted', () {
      test('should return true for AES encrypted values', () {
        final encrypted = SecureStorage.encryptValue('test', testKey);
        expect(SecureStorage.isEncrypted(encrypted), isTrue);
        expect(SecureStorage.isAesEncrypted(encrypted), isTrue);
      });

      test('should return false for plain text', () {
        expect(SecureStorage.isEncrypted('plain text'), isFalse);
        expect(SecureStorage.isAesEncrypted('plain text'), isFalse);
      });
    });
  });
}
