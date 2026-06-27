// test/unit/password_hasher_test.dart
//
// ✅ اختبارات PasswordHasher (P2 إصلاح 2026-06-28)
// يغطي: hash, verify, migration (plaintext → PBKDF2), timing attack resistance

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/password_hasher.dart';

void main() {
  group('PasswordHasher', () {
    group('hash()', () {
      test('produces a non-empty string with correct format', () {
        final hashed = PasswordHasher.hash('mypassword');
        expect(hashed, isNotEmpty);
        // Format: pbkdf2_sha256$<iterations>$<salt_b64>$<hash_b64>
        expect(hashed.startsWith('pbkdf2_sha256\$'), isTrue);
        final parts = hashed.split(r'$');
        expect(parts.length, equals(4));
        expect(parts[0], equals('pbkdf2_sha256'));
        expect(int.parse(parts[1]), greaterThan(0)); // iterations
        expect(parts[2], isNotEmpty); // salt
        expect(parts[3], isNotEmpty); // hash
      });

      test('produces different hashes for the same password (random salt)', () {
        final hash1 = PasswordHasher.hash('samepassword');
        final hash2 = PasswordHasher.hash('samepassword');
        expect(hash1, isNot(equals(hash2)));
      });

      test('produces different hashes for different passwords', () {
        final hash1 = PasswordHasher.hash('password1');
        final hash2 = PasswordHasher.hash('password2');
        expect(hash1, isNot(equals(hash2)));
      });

      test('supports custom iterations', () {
        final hashed = PasswordHasher.hash('test', iterations: 50000);
        final parts = hashed.split(r'$');
        expect(int.parse(parts[1]), equals(50000));
      });
    });

    group('verify()', () {
      test('verifies correct password against its hash', () {
        final password = 'mySecretPassword123';
        final hashed = PasswordHasher.hash(password);
        expect(PasswordHasher.verify(password, hashed), isTrue);
      });

      test('rejects wrong password', () {
        final hashed = PasswordHasher.hash('correctPassword');
        expect(PasswordHasher.verify('wrongPassword', hashed), isFalse);
      });

      test('rejects empty password', () {
        final hashed = PasswordHasher.hash('somepassword');
        expect(PasswordHasher.verify('', hashed), isFalse);
      });

      test('rejects empty stored hash', () {
        expect(PasswordHasher.verify('password', ''), isFalse);
      });

      test('handles different iterations in stored hash', () {
        final password = 'testPassword';
        final hashed = PasswordHasher.hash(password, iterations: 50000);
        expect(PasswordHasher.verify(password, hashed), isTrue);
      });

      test('rejects malformed hash gracefully', () {
        expect(PasswordHasher.verify('password', 'malformed'), isFalse);
        expect(PasswordHasher.verify('password', 'pbkdf2_sha256\$abc'), isFalse);
        expect(
          PasswordHasher.verify('password', 'pbkdf2_sha256\$abc\$def\$ghi\$extra'),
          isFalse,
        );
      });

      test('rejects corrupted base64 in hash', () {
        final password = 'testPassword';
        // Build a hash with invalid base64
        final corrupted = 'pbkdf2_sha256\$100000\$!!!invalidbase64!!!\$abc';
        expect(PasswordHasher.verify(password, corrupted), isFalse);
      });
    });

    group('Legacy plaintext compatibility (migration support)', () {
      test('verifies plaintext password (legacy support)', () {
        // للتوافق مع الإصدارات السابقة — كلمات المرور القديمة المخزّنة كنص صريح
        expect(PasswordHasher.verify('mypassword', 'mypassword'), isTrue);
      });

      test('rejects wrong plaintext password', () {
        expect(PasswordHasher.verify('wrong', 'mypassword'), isFalse);
      });

      test('isHashed returns false for plaintext', () {
        expect(PasswordHasher.isHashed('mypassword'), isFalse);
        expect(PasswordHasher.isHashed(''), isFalse);
      });

      test('isHashed returns true for PBKDF2 hash', () {
        final hashed = PasswordHasher.hash('test');
        expect(PasswordHasher.isHashed(hashed), isTrue);
      });
    });

    group('Migration scenario (plaintext → PBKDF2)', () {
      test('hash then verify roundtrip works', () {
        // محاكاة سيناريو الترحيل:
        // 1. كلمة المرور القديمة كانت 'oldpassword' (نص صريح)
        // 2. verify نجح لأنها نص صريح
        // 3. نُهاشها ونُخزّن الجديد
        // 4. verify الجديد يجب أن يعمل
        const oldPassword = 'oldpassword';
        const storedLegacy = 'oldpassword';

        // Step 1: verify legacy
        expect(PasswordHasher.verify(oldPassword, storedLegacy), isTrue);
        expect(PasswordHasher.isHashed(storedLegacy), isFalse);

        // Step 2: migrate
        final newHashed = PasswordHasher.hash(oldPassword);
        expect(PasswordHasher.isHashed(newHashed), isTrue);

        // Step 3: verify with new hash
        expect(PasswordHasher.verify(oldPassword, newHashed), isTrue);

        // Step 4: wrong password should still fail
        expect(PasswordHasher.verify('wrongpassword', newHashed), isFalse);
      });
    });

    group('Timing attack resistance', () {
      test('constant-time comparison rejects different-length hashes', () {
        // محاولة مع hash صحيح البادئة لكن خاطئ الطول
        final password = 'test';
        final realHash = PasswordHasher.hash(password);
        final parts = realHash.split(r'$');
        // قصّ الـ hash الناتج ليكون أقصر
        final shortHash = '${parts[0]}\$${parts[1]}\$${parts[2]}\$${parts[3].substring(0, 10)}';
        expect(PasswordHasher.verify(password, shortHash), isFalse);
      });
    });

    group('Multiple users with same password', () {
      test('different users with same password have different hashes', () {
        // حتى لو استخدم مستخدمان نفس كلمة المرور، الـ hash يختلف بسبب salt
        final hash1 = PasswordHasher.hash('sharedPassword');
        final hash2 = PasswordHasher.hash('sharedPassword');
        expect(hash1, isNot(equals(hash2)));
        // لكن كلاهما يتحقق من نفس كلمة المرور
        expect(PasswordHasher.verify('sharedPassword', hash1), isTrue);
        expect(PasswordHasher.verify('sharedPassword', hash2), isTrue);
      });
    });

    group('Performance (sanity check)', () {
      test('hash completes within reasonable time (< 3 seconds)', () {
        final stopwatch = Stopwatch()..start();
        PasswordHasher.hash('performancetest');
        stopwatch.stop();
        // 100K iterations of PBKDF2-SHA256 should be well under 3s on any device
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      });
    });

    group('sha256Hex helper', () {
      test('produces consistent hex digest', () {
        final hex1 = PasswordHasher.sha256Hex('test');
        final hex2 = PasswordHasher.sha256Hex('test');
        expect(hex1, equals(hex2));
        expect(hex1.length, equals(64)); // SHA-256 = 32 bytes = 64 hex chars
      });

      test('produces different digest for different input', () {
        final hex1 = PasswordHasher.sha256Hex('test1');
        final hex2 = PasswordHasher.sha256Hex('test2');
        expect(hex1, isNot(equals(hex2)));
      });
    });
  });
}
