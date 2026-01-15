import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/conflict_resolver.dart';
import 'package:marina_hotel_mobile/services/vector_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConflictContext ctx({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    DateTime? localTs,
    DateTime? remoteTs,
    int localPriority = 100,
    int remotePriority = 100,
    VectorClock? localClock,
    VectorClock? remoteClock,
    String table = 'bookings',
  }) {
    final now = DateTime.utc(2025, 1, 1, 0, 0, 0);
    return ConflictContext(
      table: table,
      uuid: 'u1',
      localData: local,
      remoteData: remote,
      localVectorClock: localClock,
      remoteVectorClock: remoteClock,
      localTimestamp: localTs ?? now,
      remoteTimestamp: remoteTs ?? now,
      localDeviceId: 'local',
      remoteDeviceId: 'remote',
      localDevicePriority: localPriority,
      remoteDevicePriority: remotePriority,
    );
  }

  test('lastWriteWins picks newer timestamp', () {
    final resolver = EnhancedConflictResolver(
        defaultStrategy: ConflictStrategy.lastWriteWins);

    final local = {'status': 'local'};
    final remote = {'status': 'remote'};

    final context = ctx(
      local: local,
      remote: remote,
      localTs: DateTime.utc(2025, 1, 2),
      remoteTs: DateTime.utc(2025, 1, 1),
    );

    final result = resolver.resolve(context);
    expect(result.strategy, ConflictStrategy.lastWriteWins);
    expect(result.winner, local);
  });

  test('firstWriteWins picks older timestamp', () {
    final resolver = EnhancedConflictResolver(
        defaultStrategy: ConflictStrategy.firstWriteWins);

    final local = {'status': 'local'};
    final remote = {'status': 'remote'};

    final context = ctx(
      local: local,
      remote: remote,
      localTs: DateTime.utc(2025, 1, 1),
      remoteTs: DateTime.utc(2025, 1, 2),
    );

    final result = resolver.resolve(context);
    expect(result.strategy, ConflictStrategy.firstWriteWins);
    expect(result.winner, local);
  });

  test('lastWriteWins falls back to device priority when timestamps equal', () {
    final resolver = EnhancedConflictResolver(
        defaultStrategy: ConflictStrategy.lastWriteWins);

    final local = {'status': 'local'};
    final remote = {'status': 'remote'};

    final context = ctx(
      local: local,
      remote: remote,
      localTs: DateTime.utc(2025, 1, 1),
      remoteTs: DateTime.utc(2025, 1, 1),
      localPriority: 200,
      remotePriority: 100,
    );

    final result = resolver.resolve(context);
    expect(result.strategy, ConflictStrategy.customPriority);
    expect(result.winner, local);
  });

  test('vector clock before/after overrides strategy selection', () {
    final resolver = EnhancedConflictResolver(
        defaultStrategy: ConflictStrategy.firstWriteWins);

    final local = {'status': 'local'};
    final remote = {'status': 'remote'};

    final contextLocalAfter = ctx(
      local: local,
      remote: remote,
      localClock: VectorClock({'d1': 2}),
      remoteClock: VectorClock({'d1': 1}),
      localTs: DateTime.utc(2025, 1, 1),
      remoteTs: DateTime.utc(2025, 1, 2),
    );

    final r1 = resolver.resolve(contextLocalAfter);
    expect(r1.strategy, ConflictStrategy.lastWriteWins);
    expect(r1.winner, local);

    final contextLocalBefore = ctx(
      local: local,
      remote: remote,
      localClock: VectorClock({'d1': 1}),
      remoteClock: VectorClock({'d1': 2}),
      localTs: DateTime.utc(2025, 1, 2),
      remoteTs: DateTime.utc(2025, 1, 1),
    );

    final r2 = resolver.resolve(contextLocalBefore);
    expect(r2.strategy, ConflictStrategy.lastWriteWins);
    expect(r2.winner, remote);
  });

  test('concurrent vector clocks with small time diff uses field-level merge',
      () {
    final resolver = EnhancedConflictResolver(
        defaultStrategy: ConflictStrategy.lastWriteWins);

    final local = {
      'status': 'local',
      'notes': null,
      'guestName': 'Local Name',
    };
    final remote = {
      'status': 'remote',
      'notes': 'Remote note',
      'guestName': 'Remote Name',
    };

    final context = ctx(
      local: local,
      remote: remote,
      table: 'bookings',
      localClock: VectorClock({'a': 1}),
      remoteClock: VectorClock({'b': 1}),
      localTs: DateTime.utc(2025, 1, 1, 0, 0, 0),
      remoteTs: DateTime.utc(2025, 1, 1, 0, 0, 10),
    );

    final result = resolver.resolve(context);
    expect(result.strategy, ConflictStrategy.fieldLevel);
    expect(result.mergedData, isNotNull);
    expect(result.winner, result.mergedData);

    final merged = result.mergedData!;
    expect(merged['status'], 'remote');
    expect(merged['notes'], 'Remote note');
    expect(merged['guestName'], 'Remote Name');
    expect(merged['updated_at'], isA<int>());
    expect(merged['updated_at_iso'], isA<String>());
  });
}
