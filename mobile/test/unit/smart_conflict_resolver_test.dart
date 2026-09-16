// test/unit/smart_conflict_resolver_test.dart
//
// ✅ اختبارات SmartConflictResolver (P1-8 إصلاح 2026-06-28)
// يغطي: دمج الحقول، استراتيجيات الحل، deduplication، max timestamp

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/smart_conflict_resolver.dart';
import 'package:marina_hotel_mobile/services/vector_clock_service.dart';

void main() {
  group('SmartConflictResolver', () {
    group('resolve() — no conflict cases', () {
      test('returns remoteWins when remote is causally newer', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1}',
            'status': 'old',
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 2}',
            'status': 'new',
            'lastModified': 2000,
          },
          commonAncestor: null,
        );
        expect(result.strategy, equals(ResolutionStrategy.remoteWins));
        expect(result.mergedData['status'], equals('new'));
      });

      test('returns localWins when local is causally newer', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 5}',
            'status': 'local',
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 2}',
            'status': 'remote',
            'lastModified': 2000,
          },
          commonAncestor: null,
        );
        expect(result.strategy, equals(ResolutionStrategy.localWins));
        expect(result.mergedData['status'], equals('local'));
      });

      test('returns localWins when VCs are equal', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {'vectorClock': '{"d1": 5}', 'status': 'local'},
          remoteData: {'vectorClock': '{"d1": 5}', 'status': 'remote'},
          commonAncestor: null,
        );
        expect(result.strategy, equals(ResolutionStrategy.localWins));
      });
    });

    group('resolve() — delete cases', () {
      test('deleteVsDelete returns localWins', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {'deletedAt': 1000},
          remoteData: {'deletedAt': 2000},
          commonAncestor: null,
        );
        expect(result.strategy, equals(ResolutionStrategy.localWins));
      });

      test('deleteVsUpdate returns localWins with pushedToRemote=true', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {'deletedAt': 1000, 'status': 'old'},
          remoteData: {'status': 'new'},
          commonAncestor: {'status': 'old'},
        );
        expect(result.strategy, equals(ResolutionStrategy.localWins));
        expect(result.pushedToRemote, isTrue);
        expect(result.warnings, isNotEmpty);
      });
    });

    group('resolve() — concurrent conflict auto-merge', () {
      test('concurrentDifferentFields auto-merges non-conflicting fields', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'status': 'active', // unchanged
            'cleaningStatus': 'dirty', // local changed
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'status': 'active',
            'cleaningStatus': 'clean', // remote didn't change (ancestor=clean)
            'price': 150.0, // remote changed
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'status': 'active',
            'cleaningStatus': 'clean',
            'price': 100.0,
            'lastModified': 500,
          },
        );
        expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
        // local changed cleaningStatus → keep local value
        expect(result.mergedData['cleaningStatus'], equals('dirty'));
        // remote changed price → take remote value
        expect(result.mergedData['price'], equals(150.0));
        // ✅ (2026-09-17) عقد snake_case: الدمج يكتب vector_clock لا
        // vectorClock — انظر حزمة «snake_case contract» أدناه.
        final mergedVc = VectorClock.fromString(
          result.mergedData['vector_clock'],
        );
        expect(mergedVc.get('d1'), equals(1));
        expect(mergedVc.get('d2'), equals(1));
        expect(result.pushedToRemote, isTrue);
      });

      test(
        'concurrentSameFields with non-critical field uses entity policy',
        () {
          final result = SmartConflictResolver.resolve(
            entity: 'rooms',
            localData: {
              'vectorClock': '{"d1": 1, "d2": 0}',
              'status': 'local_status', // both changed status
              'lastModified': 1000,
            },
            remoteData: {
              'vectorClock': '{"d1": 0, "d2": 1}',
              'status': 'remote_status',
              'lastModified': 2000,
            },
            commonAncestor: {
              'vectorClock': '{}',
              'status': 'original',
              'lastModified': 500,
            },
          );
          // rooms policy: status=newerWins
          // remote is newer (2000 > 1000) → remote status wins
          expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
          expect(result.mergedData['status'], equals('remote_status'));
        },
      );

      test(
        'concurrentSameFields with critical field resolves via LWW (not manual)',
        () {
          final result = SmartConflictResolver.resolve(
            entity: 'expenses',
            localData: {
              'vectorClock': '{"d1": 1, "d2": 0}',
              'amount': 100.0, // critical field, both changed
              'lastModified': 1000,
            },
            remoteData: {
              'vectorClock': '{"d1": 0, "d2": 1}',
              'amount': 200.0,
              'lastModified': 2000,
            },
            commonAncestor: {
              'vectorClock': '{}',
              'amount': 50.0,
              'lastModified': 500,
            },
          );
          expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
          // After commit fffa6a37 ("fully automatic conflict resolution"),
          // critical fields no longer escalate to manual. Instead they resolve
          // via LWW (Last Write Wins) inside fieldLevelMerge.
          // The remote has lastModified=2000 > local=1000, so remote value wins.
          expect(result.mergedData['amount'], equals(200.0));
          expect(result.warnings, isNotEmpty);
        },
      );
    });

    group('_autoMerge — P1-7 fix: max(localTs, remoteTs)', () {
      // ✅ إصلاح P1-7: استخدام max(localTs, remoteTs) بدلاً من DateTime.now()
      // لمنع كسر idempotency

      test('merged lastModified is max of local and remote', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'lastModified': 5000, // local is newer
            'cleaningStatus': 'dirty',
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'lastModified': 3000, // remote is older
            'price': 150.0,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'lastModified': 1000,
            'cleaningStatus': 'clean',
            'price': 100.0,
          },
        );
        expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
        // lastModified should be max(5000, 3000) = 5000
        // ✅ (2026-09-17) العقد snake_case: الدمج يكتب last_modified.
        expect(result.mergedData['last_modified'], equals(5000));
        expect(result.mergedData.containsKey('lastModified'), isFalse);
      });

      test('merged lastModified is remote when remote is newer', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'lastModified': 1000,
            'cleaningStatus': 'dirty',
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'lastModified': 9000, // remote is newer
            'price': 150.0,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'lastModified': 500,
            'cleaningStatus': 'clean',
            'price': 100.0,
          },
        );
        expect(result.mergedData['last_modified'], equals(9000));
      });

      test('version is incremented by 1', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'lastModified': 1000,
            'version': 5,
            'cleaningStatus': 'dirty',
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'lastModified': 2000,
            'version': 3,
            'price': 150.0,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'lastModified': 500,
            'version': 2,
            'cleaningStatus': 'clean',
            'price': 100.0,
          },
        );
        expect(result.mergedData['version'], equals(6)); // 5 + 1
      });
    });

    group('concat strategy — P2-12 fix: deduplication', () {
      // ✅ إصلاح P2-12: deduplication في concat لمنع تضخم النصوص

      test('concat merges two different notes', () {
        final result = SmartConflictResolver.resolve(
          entity: 'booking_notes',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'noteText': 'Local note',
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'noteText': 'Remote note',
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'noteText': '',
            'lastModified': 500,
          },
        );
        expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
        final merged = result.mergedData['noteText'] as String;
        expect(merged, contains('Local note'));
        expect(merged, contains('Remote note'));
      });

      test('concat does not duplicate identical notes', () {
        final result = SmartConflictResolver.resolve(
          entity: 'booking_notes',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'noteText': 'Same note',
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'noteText': 'Same note',
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'noteText': '',
            'lastModified': 500,
          },
        );
        final merged = result.mergedData['noteText'] as String;
        expect(merged, equals('Same note'));
      });

      test('concat deduplicates repeated entries across multiple merges', () {
        // Simulate: after first merge, text is "A\n---\nB"
        // Now merge again with a remote that has "A\n---\nC"
        // Result should be "A\n---\nB\n---\nC" (no duplicate A)
        final result = SmartConflictResolver.resolve(
          entity: 'booking_notes',
          localData: {
            'vectorClock': '{"d1": 2, "d2": 0}',
            'noteText': 'A\n---\nB',
            'lastModified': 3000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'noteText': 'A\n---\nC',
            'lastModified': 4000,
          },
          commonAncestor: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'noteText': 'A',
            'lastModified': 1000,
          },
        );
        final merged = result.mergedData['noteText'] as String;
        // Should contain A, B, C each exactly once
        expect(merged, contains('A'));
        expect(merged, contains('B'));
        expect(merged, contains('C'));
        // Count occurrences of 'A' — should be 1 (deduplicated)
        final aCount = 'A'.allMatches(merged).length;
        expect(aCount, equals(1));
      });
    });

    group('entity policies', () {
      test('rooms: status uses newerWins', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'status': 'local',
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'status': 'remote',
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'status': 'original',
            'lastModified': 500,
          },
        );
        // newerWins → remote (2000 > 1000)
        expect(result.mergedData['status'], equals('remote'));
      });

      test('rooms: price resolves via LWW (not manual)', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'price': 100.0,
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'price': 200.0,
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'price': 50.0,
            'lastModified': 500,
          },
        );
        expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
        // After commit fffa6a37, 'price' on rooms uses LWW instead of manual escalation.
        // Remote (lastModified=2000) is newer than local (lastModified=1000),
        // so the remote price (200.0) should win.
        expect(result.mergedData['price'], equals(200.0));
      });

      test('payments: amount resolves via LWW (not manual)', () {
        final result = SmartConflictResolver.resolve(
          entity: 'payments',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'amount': 100.0,
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'amount': 200.0,
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'amount': 50.0,
            'lastModified': 500,
          },
        );
        expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
        // After commit fffa6a37, 'amount' on payments uses LWW instead of manual escalation.
        // Remote (lastModified=2000) is newer than local (lastModified=1000),
        // so the remote amount (200.0) should win.
        expect(result.mergedData['amount'], equals(200.0));
      });

      test('debts: all fields resolve via LWW (not manual)', () {
        final result = SmartConflictResolver.resolve(
          entity: 'debts',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'totalAmount': 100.0,
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'totalAmount': 200.0,
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'totalAmount': 50.0,
            'lastModified': 500,
          },
        );
        expect(result.strategy, equals(ResolutionStrategy.fieldLevelMerge));
        // After commit fffa6a37, 'totalAmount' on debts uses LWW instead of manual escalation.
        // Remote (lastModified=2000) is newer than local (lastModified=1000),
        // so the remote totalAmount (200.0) should win.
        expect(result.mergedData['totalAmount'], equals(200.0));
      });

      test('unknown entity uses default policy (newerWins)', () {
        final result = SmartConflictResolver.resolve(
          entity: 'unknown_entity',
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'someField': 'local',
            'lastModified': 1000,
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'someField': 'remote',
            'lastModified': 2000,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'someField': 'original',
            'lastModified': 500,
          },
        );
        // Default policy: newerWins → remote wins (2000 > 1000)
        expect(result.mergedData['someField'], equals('remote'));
      });
    });

    group('VectorClock merge in _autoMerge', () {
      test('merged VC is union of local and remote with max values', () {
        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: {
            'vectorClock': '{"d1": 5, "d2": 3, "d3": 1}',
            'lastModified': 1000,
            'cleaningStatus': 'dirty',
          },
          remoteData: {
            'vectorClock': '{"d1": 2, "d2": 7, "d4": 4}',
            'lastModified': 2000,
            'price': 150.0,
          },
          commonAncestor: {
            'vectorClock': '{}',
            'lastModified': 500,
            'cleaningStatus': 'clean',
            'price': 100.0,
          },
        );
        final mergedVc = VectorClock.fromString(
          result.mergedData['vector_clock'],
        );
        expect(mergedVc.get('d1'), equals(5)); // max(5, 2)
        expect(mergedVc.get('d2'), equals(7)); // max(3, 7)
        expect(mergedVc.get('d3'), equals(1)); // only local
        expect(mergedVc.get('d4'), equals(4)); // only remote
      });
    });

    // ✅ (2026-09-17) اختبار انحدار عطل الإنتاج 2026-09-16:
    // «SqliteException(1): no such column: vectorClock» على app_users.
    // صف محلي Drift (snake_case كامل بترتيب الأعمدة الفيزيائية) + صف
    // سلك D1 (snake_case) بساعتين متزامنتين → الدمج يجب أن يُخرج مفاتيح
    // snake_case فقط صالحة لـ UPDATE خام مباشرة.
    group('snake_case contract — production app_users regression', () {
      test(
        'merged output has NO camelCase sync keys and merges real clocks',
        () {
          // صف محلي كما يقرأه Drift (existing.data) — snake_case فيزيائي.
          final localData = <String, dynamic>{
            'id': 7,
            'local_uuid': 'user_1',
            'server_id': 1,
            'created_at': 1788920188,
            'updated_at': 1789435400,
            'deleted_at': null,
            'last_modified': 1789435271,
            'created_at_iso': null,
            'updated_at_iso': null,
            'deleted_at_iso': null,
            'created_at_epoch': 0,
            'last_modified_epoch': 0,
            'version': 3,
            'origin': 'local',
            'vector_clock': '{"cf_dev_mu07yt34":2}',
            'device_id': 'cf_dev_mu07yt34',
            'sync_timestamp': 0,
            'idempotency_key': null,
            'username': '1',
            'password': null,
            'full_name': 'علي',
            'user_type': 'employee',
            'permissions': '[]',
            'active': 1,
            'last_login': 1789435300,
            'credentials_version': 0,
            'role': 'employee',
          };
          // صف سلك D1 (SELECT *) — ساعة جهاز آخر → متزامنة مع المحلية.
          final remoteData = <String, dynamic>{
            'id': 1,
            'local_uuid': 'user_1',
            'username': '1',
            'full_name': 'علي المنقّح',
            'user_type': 'employee',
            'permissions': '["dashboard"]',
            'active': 1,
            'last_login': 1789435400,
            'credentials_version': 0,
            'role': 'employee',
            'server_id': 1,
            'created_at': 1788920188,
            'updated_at': 1789435489,
            'deleted_at': null,
            'last_modified': 1789435344,
            'created_at_epoch': 0,
            'last_modified_epoch': 0,
            'version': 2,
            'origin': 'local',
            'vector_clock': '{"cf_dev_mttgnjm2":1}',
            'device_id': 'cf_dev_mu07yt34',
            'sync_timestamp': 0,
            'idempotency_key': null,
          };

          final result = SmartConflictResolver.resolve(
            entity: 'app_users',
            localData: localData,
            remoteData: remoteData,
            commonAncestor: null,
          );

          expect(
            result.strategy,
            equals(ResolutionStrategy.fieldLevelMerge),
            reason: 'ساعتان متزامنتان لمختلف الأجهزة → دمج على مستوى الحقل',
          );

          // العقد الحاسم: لا مفاتيح camelCase للمزامنة في الخرج — أي مفتاح
          // كهذا كان يُسقط UPDATE كاملاً بـ «no such column».
          expect(
            result.mergedData.containsKey('vectorClock'),
            isFalse,
            reason: 'camelCase vectorClock يكسر UPDATE المحلي',
          );
          expect(
            result.mergedData.containsKey('lastModified'),
            isFalse,
            reason: 'camelCase lastModified يكسر UPDATE المحلي',
          );

          // الساعة المدمجة تحتوي عدّادي كلا الجهازين (كانت تُدمج من '{}'
          // لأن الكود القديم قرأ المفاتيح camelCase غير الموجودة أصلاً).
          final mergedVc = VectorClock.fromString(
            result.mergedData['vector_clock'] as String,
          );
          expect(mergedVc.get('cf_dev_mu07yt34'), equals(2));
          expect(mergedVc.get('cf_dev_mttgnjm2'), equals(1));

          // last_modified = max(محلي 1789435271، بعيد 1789435344).
          expect(result.mergedData['last_modified'], equals(1789435344));

          // دمج الحقول: البعيد غيّر full_name و last_login فقط.
          expect(result.mergedData['full_name'], equals('علي المنقّح'));
          expect(result.mergedData['last_login'], equals(1789435400));
          // المحلي لم يُمسّ والمحتوى متطابق → يبقى.
          expect(result.mergedData['role'], equals('employee'));

          // version المحلي +1.
          expect(result.mergedData['version'], equals(4));
        },
      );

      test(
        'كل مفاتيح الخرج آمنة كأعمدة فيزيائية (لا camelCase مطلقاً)',
        () {
          final localData = <String, dynamic>{
            'id': 1,
            'local_uuid': 'r1',
            'note_text': 'محلي',
            'vector_clock': '{"a":1}',
            'last_modified': 100,
            'version': 1,
            'device_id': 'dev-a',
          };
          final remoteData = <String, dynamic>{
            'id': 9,
            'local_uuid': 'r1',
            'note_text': 'بعيد',
            'vector_clock': '{"b":1}',
            'last_modified': 200,
            'version': 1,
            'device_id': 'dev-b',
          };
          final result = SmartConflictResolver.resolve(
            entity: 'booking_notes',
            localData: localData,
            remoteData: remoteData,
            commonAncestor: null,
          );
          final camelKeys = result.mergedData.keys
              .where((k) => RegExp('[A-Z]').hasMatch(k))
              .toList();
          expect(
            camelKeys,
            isEmpty,
            reason: 'أي مفتاح بحرف كبير يهدد UPDATE الخام: $camelKeys',
          );
          // سياسة note_text (snake) تصيب قاعدة concat المكتوبة camelCase.
          final mergedNote = result.mergedData['note_text'] as String;
          expect(mergedNote, contains('محلي'));
          expect(mergedNote, contains('بعيد'));
        },
      );
    });
  });
}
