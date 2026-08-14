import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/growth_pact_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late GrowthPactService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    GrowthPactService.init(db);
    service = GrowthPactService.instance;
  });

  tearDown(() async {
    await db.close();
  });

  group('penalty settlement', () {
    test('settlePenalties writes penaltyLedgerId on unsettled miss checks',
        () async {
      final pactId = await service.createPact(
        kind: 'habit',
        domain: 'schedule',
        description: '11点前睡',
        status: 'active',
        stakes: {
          'penaltyPerMiss': 10,
        },
      );

      // Record 3 misses
      for (var i = 0; i < 3; i++) {
        await service.recordCheck(
          pactId: pactId,
          result: 'miss',
          sourceType: 'checkin',
        );
      }

      // Settle 2 of them
      final settled = await service.settlePenalties(
        pactId: pactId,
        penaltyLedgerId: 'ledger-001',
        settleCount: 2,
      );

      expect(settled, 2);

      // Verify snapshot shows only 1 outstanding miss
      final section = await service.buildSnapshotSection();
      expect(section, contains('misses this week: 1'));
      expect(section, contains('penalty due: 1 × 10 CNY'));
    });

    test('settlePenalties with 0 count is a no-op', () async {
      final pactId = await service.createPact(
        kind: 'habit',
        domain: 'schedule',
        description: '11点前睡',
        status: 'active',
        stakes: {'penaltyPerMiss': 10},
      );

      final settled = await service.settlePenalties(
        pactId: pactId,
        penaltyLedgerId: 'ledger-001',
        settleCount: 0,
      );

      expect(settled, 0);
    });

    test('settlePenalties does not touch miss checks that are already settled',
        () async {
      final pactId = await service.createPact(
        kind: 'habit',
        domain: 'schedule',
        description: '11点前睡',
        status: 'active',
        stakes: {'penaltyPerMiss': 10},
      );

      // Record 2 misses
      await service.recordCheck(pactId: pactId, result: 'miss');
      await service.recordCheck(pactId: pactId, result: 'miss');

      // Settle 1
      await service.settlePenalties(
        pactId: pactId,
        penaltyLedgerId: 'ledger-A',
        settleCount: 1,
      );

      // Try to settle 2 more - should only settle 1 remaining
      final settled = await service.settlePenalties(
        pactId: pactId,
        penaltyLedgerId: 'ledger-B',
        settleCount: 2,
      );

      expect(settled, 1);
    });

    test('buildSnapshotSection shows no penalty due when all misses are settled',
        () async {
      final pactId = await service.createPact(
        kind: 'habit',
        domain: 'schedule',
        description: '11点前睡',
        status: 'active',
        stakes: {'penaltyPerMiss': 10},
      );

      // Record 2 misses
      await service.recordCheck(pactId: pactId, result: 'miss');
      await service.recordCheck(pactId: pactId, result: 'miss');

      // Settle both
      await service.settlePenalties(
        pactId: pactId,
        penaltyLedgerId: 'ledger-001',
        settleCount: 2,
      );

      final section = await service.buildSnapshotSection();
      expect(section, isNot(contains('penalty due')));
      expect(section, isNot(contains('misses this week')));
    });

    test('buildSnapshotSection includes pactId for the AI to use', () async {
      final pactId = await service.createPact(
        kind: 'habit',
        domain: 'schedule',
        description: '11点前睡',
        status: 'active',
        stakes: {'penaltyPerMiss': 10},
      );

      await service.recordCheck(pactId: pactId, result: 'miss');

      final section = await service.buildSnapshotSection();
      expect(section, contains('pactId: $pactId'));
    });
  });
}
