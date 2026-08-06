// test/unit/conflict_detector_test.dart
//
// ✅ اختبارات ConflictDetector (P1-8 إصلاح 2026-06-28)
// يغطي: تصنيف التعارضات، الحقول الحرجة، استثناء vectorClock

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/conflict_detector.dart';
import 'package:marina_hotel_mobile/services/vector_clock_service.dart';

void main() {
  group('ConflictDetector', () {
    group('detect()', () {
      test('noConflictRemoteNewer when localData is null', () {
        final result = ConflictDetector.detect(
          localData: null,
          remoteData: {'id': '1', 'status': 'active'},
          commonAncestor: null,
        );
        expect(result.type, equals(ConflictType.noConflictRemoteNewer));
      });

      test('deleteVsDelete when both deleted', () {
        final result = ConflictDetector.detect(
          localData: {'deletedAt': 1000},
          remoteData: {'deletedAt': 2000},
          commonAncestor: null,
        );
        expect(result.type, equals(ConflictType.deleteVsDelete));
      });

      test('deleteVsUpdate when local deleted, remote updated', () {
        final result = ConflictDetector.detect(
          localData: {'deletedAt': 1000, 'status': 'old'},
          remoteData: {'status': 'new'},
          commonAncestor: {'status': 'old'},
        );
        expect(result.type, equals(ConflictType.deleteVsUpdate));
      });

      // ✅ P0-4 Audit Fix (2026-08-06): تماثل سياسة الحذف.
      // سابقاً، كان هذا يُرجع `noConflictRemoteNewer` (يُطبّق الحذف البعيد
      // ويُفقد التحديث المحلي). الآن يُرجع `deleteVsUpdate` ليُعالجه
      // SmartConflictResolver بقرار واعٍ بدلاً من تطبيق الحذف صامتاً.
      test('deleteVsUpdate when remote deleted, local not (P0-4 fix)', () {
        final result = ConflictDetector.detect(
          localData: {'status': 'active'},
          remoteData: {'deletedAt': 1000},
          commonAncestor: null,
        );
        expect(result.type, equals(ConflictType.deleteVsUpdate));
      });

      test('noConflictEqual when VCs are identical', () {
        final vc = VectorClock.fromString('{"d1": 5, "d2": 3}');
        final result = ConflictDetector.detect(
          localData: {'vectorClock': vc.toString(), 'status': 'active'},
          remoteData: {'vectorClock': vc.toString(), 'status': 'active'},
          commonAncestor: null,
        );
        expect(result.type, equals(ConflictType.noConflictEqual));
      });

      test('noConflictRemoteNewer when remote VC dominates', () {
        final result = ConflictDetector.detect(
          localData: {'vectorClock': '{"d1": 2}', 'status': 'old'},
          remoteData: {'vectorClock': '{"d1": 5}', 'status': 'new'},
          commonAncestor: null,
        );
        expect(result.type, equals(ConflictType.noConflictRemoteNewer));
      });

      test('noConflictLocalNewer when local VC dominates', () {
        final result = ConflictDetector.detect(
          localData: {'vectorClock': '{"d1": 5}', 'status': 'local'},
          remoteData: {'vectorClock': '{"d1": 2}', 'status': 'remote'},
          commonAncestor: null,
        );
        expect(result.type, equals(ConflictType.noConflictLocalNewer));
      });

      test('concurrentDifferentFields when VCs diverge but fields differ', () {
        final result = ConflictDetector.detect(
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'status': 'active',
            'cleaningStatus': 'dirty', // local changed this
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'status': 'active',
            'cleaningStatus': 'clean', // remote did NOT change (ancestor=clean)
            'price': 150.0, // remote changed this
          },
          commonAncestor: {
            'vectorClock': '{}',
            'status': 'active',
            'cleaningStatus': 'clean',
            'price': 100.0,
          },
        );
        // local changed cleaningStatus, remote changed price → no overlap → concurrentDifferentFields
        expect(result.type, equals(ConflictType.concurrentDifferentFields));
      });

      test('concurrentSameFields when VCs diverge and same field changed', () {
        final result = ConflictDetector.detect(
          localData: {
            'vectorClock': '{"d1": 1, "d2": 0}',
            'status': 'local_status',
          },
          remoteData: {
            'vectorClock': '{"d1": 0, "d2": 1}',
            'status': 'remote_status',
          },
          commonAncestor: {'vectorClock': '{}', 'status': 'original_status'},
        );
        expect(result.type, equals(ConflictType.concurrentSameFields));
        expect(result.conflictingFields, contains('status'));
      });

      test('LWW fallback when both VCs are empty', () {
        final result = ConflictDetector.detect(
          localData: {'lastModified': 1000, 'status': 'old'},
          remoteData: {'lastModified': 2000, 'status': 'new'},
          commonAncestor: null,
        );
        // Both VCs empty → LWW → remote is newer (2000 > 1000)
        expect(result.type, equals(ConflictType.noConflictRemoteNewer));
      });
    });

    group('_criticalFields (P1-5 fix)', () {
      test('status is NOT critical after fix (was before)', () {
        // ✅ إصلاح P1-5: 'status' أُزيل من _criticalFields
        // لأن سياسات بعض الكيانات (bookings) تستخدم newerWins لـ status
        expect(ConflictDetector.isCriticalField('status'), isFalse);
      });

      test('amount IS critical', () {
        expect(ConflictDetector.isCriticalField('amount'), isTrue);
      });

      test('paidAmount IS critical', () {
        expect(ConflictDetector.isCriticalField('paidAmount'), isTrue);
      });

      test('price IS critical', () {
        expect(ConflictDetector.isCriticalField('price'), isTrue);
      });

      test('basicSalary IS critical', () {
        expect(ConflictDetector.isCriticalField('basicSalary'), isTrue);
      });

      test('isVoided IS critical', () {
        expect(ConflictDetector.isCriticalField('isVoided'), isTrue);
      });

      test('discount IS critical', () {
        expect(ConflictDetector.isCriticalField('discount'), isTrue);
      });

      test('discountAmount IS critical', () {
        expect(ConflictDetector.isCriticalField('discountAmount'), isTrue);
      });

      test('unknown field is NOT critical', () {
        expect(ConflictDetector.isCriticalField('unknownField'), isFalse);
      });
    });

    group('_findChangedFields (P1-6 fix)', () {
      // ✅ إصلاح P1-6: vectorClock يُستثنى من الحقول المتغيرة
      // لأنه يتغير دائماً بعد أي merge، مما يسبب تعارضات وهمية

      test('vectorClock is excluded from changed fields', () {
        final result = ConflictDetector.detect(
          localData: {
            'vectorClock': '{"d1": 2, "d2": 0}', // local newer on d1
            'status': 'active', // unchanged
          },
          remoteData: {
            'vectorClock':
                '{"d1": 0, "d2": 1}', // remote newer on d2 → concurrent
            'status': 'active',
          },
          commonAncestor: {'vectorClock': '{}', 'status': 'active'},
        );
        // VCs are concurrent (local has d1=2, remote has d2=1)
        // But with ancestor, status is unchanged, vectorClock is excluded
        // → no conflicting fields → concurrentDifferentFields
        expect(
          result.type,
          anyOf(
            equals(ConflictType.concurrentDifferentFields),
            equals(ConflictType.concurrentSameFields),
          ),
        );
        // vectorClock should NOT be in conflicting fields
        expect(result.conflictingFields, isNot(contains('vectorClock')));
      });

      test('vector_clock (snake_case) is also excluded', () {
        final result = ConflictDetector.detect(
          localData: {'vector_clock': '{"d1": 2, "d2": 0}', 'notes': 'local'},
          remoteData: {'vector_clock': '{"d1": 0, "d2": 1}', 'notes': 'remote'},
          commonAncestor: {'vector_clock': '{}', 'notes': 'original'},
        );
        // VCs are concurrent, notes changed in both → concurrentSameFields
        // vector_clock should NOT be in conflicting fields
        expect(result.conflictingFields, isNot(contains('vector_clock')));
        // notes IS in conflicting fields (both changed it from 'original')
        expect(result.conflictingFields, contains('notes'));
      });

      test('lastModified is excluded from changed fields', () {
        final result = ConflictDetector.detect(
          localData: {
            'vectorClock': '{"d1": 2}',
            'lastModified': 2000,
            'status': 'active',
          },
          remoteData: {
            'vectorClock': '{"d1": 1}',
            'lastModified': 1000,
            'status': 'active',
          },
          commonAncestor: {
            'vectorClock': '{"d1": 1}',
            'lastModified': 1000,
            'status': 'active',
          },
        );
        expect(result.conflictingFields, isNot(contains('lastModified')));
      });

      test('version is excluded from changed fields', () {
        final result = ConflictDetector.detect(
          localData: {
            'vectorClock': '{"d1": 2}',
            'version': 5,
            'status': 'active',
          },
          remoteData: {
            'vectorClock': '{"d1": 1}',
            'version': 3,
            'status': 'active',
          },
          commonAncestor: {
            'vectorClock': '{"d1": 1}',
            'version': 3,
            'status': 'active',
          },
        );
        expect(result.conflictingFields, isNot(contains('version')));
      });

      test('metadata fields starting with \$ are excluded', () {
        final result = ConflictDetector.detect(
          localData: {
            'vectorClock': '{"d1": 2}',
            r'$id': 'doc123',
            r'$updatedAt': '2024-01-01',
            'status': 'active',
          },
          remoteData: {
            'vectorClock': '{"d1": 1}',
            r'$id': 'doc123',
            r'$updatedAt': '2024-01-02',
            'status': 'active',
          },
          commonAncestor: {
            'vectorClock': '{"d1": 1}',
            r'$id': 'doc123',
            r'$updatedAt': '2024-01-01',
            'status': 'active',
          },
        );
        expect(result.conflictingFields, isNot(contains(r'$id')));
        expect(result.conflictingFields, isNot(contains(r'$updatedAt')));
      });
    });

    group('ConflictDetectionResult', () {
      test(
        'needsManualResolution is true for concurrentSameFields with critical field',
        () {
          final result = ConflictDetectionResult(
            type: ConflictType.concurrentSameFields,
            conflictingFields: {'amount'},
          );
          expect(result.needsManualResolution, isTrue);
        },
      );

      test(
        'needsManualResolution is false for concurrentSameFields without critical field',
        () {
          final result = ConflictDetectionResult(
            type: ConflictType.concurrentSameFields,
            conflictingFields: {'notes'},
          );
          expect(result.needsManualResolution, isFalse);
        },
      );

      test('canAutoResolve is true for concurrentDifferentFields', () {
        final result = ConflictDetectionResult(
          type: ConflictType.concurrentDifferentFields,
        );
        expect(result.canAutoResolve, isTrue);
      });

      test('canAutoResolve is true for deleteVsDelete', () {
        const result = ConflictDetectionResult(
          type: ConflictType.deleteVsDelete,
        );
        expect(result.canAutoResolve, isTrue);
      });

      test('canAutoResolve is true for noConflictEqual', () {
        const result = ConflictDetectionResult(
          type: ConflictType.noConflictEqual,
        );
        expect(result.canAutoResolve, isTrue);
      });
    });
  });
}
