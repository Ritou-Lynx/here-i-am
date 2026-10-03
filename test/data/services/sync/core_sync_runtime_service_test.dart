import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/core_sync_runtime_service.dart';

void main() {
  for (final joiningReason in ['manual', 'paired']) {
    test('automatic failure reaches joining $joiningReason caller', () async {
      final pass = Completer<void>();
      final reasons = <String>[];
      final service = CoreSyncRuntimeService.forTesting(syncPass: (reason) {
        reasons.add(reason);
        return pass.future;
      });
      addTearDown(service.dispose);
      final failure = StateError('synthetic failure');

      final automatic = service.syncNow(reason: 'foreground_poll');
      final joined = service.syncNow(reason: joiningReason);
      final failed = expectLater(joined, throwsA(same(failure)));
      pass.completeError(failure);

      await automatic;
      await failed;
      expect(reasons, ['foreground_poll']);
    });
  }

  test('joining automatic caller does not swallow manual failure', () async {
    final pass = Completer<void>();
    var calls = 0;
    final service = CoreSyncRuntimeService.forTesting(syncPass: (_) {
      calls++;
      return pass.future;
    });
    addTearDown(service.dispose);
    final failure = StateError('synthetic failure');

    final manual = service.syncNow();
    final automatic = service.syncNow(reason: 'resume');
    final failed = expectLater(manual, throwsA(same(failure)));
    pass.completeError(failure);

    await automatic;
    await failed;
    expect(calls, 1);
  });

  test('unawaited automatic callers handle their own failures', () async {
    final pass = Completer<void>();
    final service = CoreSyncRuntimeService.forTesting(
      syncPass: (_) => pass.future,
    );
    addTearDown(service.dispose);

    unawaited(service.syncNow(reason: 'startup'));
    unawaited(service.syncNow(reason: 'message_added'));
    pass.completeError(StateError('synthetic failure'));
    // flutter_test fails this test if any returned future leaks an error.
    await Future<void>.delayed(Duration.zero);
  });

  test('all callers share one successful pass', () async {
    final pass = Completer<void>();
    var calls = 0;
    final service = CoreSyncRuntimeService.forTesting(syncPass: (_) {
      calls++;
      return pass.future;
    });
    addTearDown(service.dispose);

    final automatic = service.syncNow(reason: 'foreground_poll');
    final manual = service.syncNow();
    final paired = service.syncNow(reason: 'paired');
    expect(identical(manual, paired), isTrue);
    expect(calls, 1);
    pass.complete();
    await Future.wait([automatic, manual, paired]);
    expect(calls, 1);
  });

  test('failed shared pass is cleared so the next pass can recover', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    var calls = 0;
    final service = CoreSyncRuntimeService.forTesting(syncPass: (_) {
      calls++;
      return calls == 1 ? first.future : second.future;
    });
    addTearDown(service.dispose);
    final failure = StateError('synthetic failure');

    final automatic = service.syncNow(reason: 'foreground_poll');
    final failed = expectLater(service.syncNow(), throwsA(same(failure)));
    first.completeError(failure);
    await automatic;
    await failed;

    final recovered = service.syncNow();
    expect(calls, 2);
    second.complete();
    await recovered;
  });

  test('synchronous pass failure becomes a shared future and clears', () async {
    var calls = 0;
    final failure = StateError('synthetic synchronous failure');
    final service = CoreSyncRuntimeService.forTesting(syncPass: (_) {
      calls++;
      if (calls == 1) throw failure;
      return Future<void>.value();
    });
    addTearDown(service.dispose);

    final automatic = service.syncNow(reason: 'startup');
    final failed = expectLater(service.syncNow(), throwsA(same(failure)));
    await automatic;
    await failed;
    expect(calls, 1);

    await service.syncNow();
    expect(calls, 2);
  });
}
