import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/call_lifecycle_policy.dart';

void main() {
  group('resolvePendingCallOpening', () {
    test('preserves the queued opening for the answered character', () {
      expect(
        resolvePendingCallOpening(
          characterId: 'i',
          pending: (characterId: 'i', opening: '  Lynx，想听听你的声音。  '),
        ),
        'Lynx，想听听你的声音。',
      );
    });

    test('ordinary user dialing has no opening', () {
      expect(
        resolvePendingCallOpening(characterId: 'i', pending: null),
        isNull,
      );
    });

    test('rejects another character and a blank opening', () {
      expect(
        resolvePendingCallOpening(
          characterId: 'i',
          pending: (characterId: 'other', opening: 'hello'),
        ),
        isNull,
      );
      expect(
        resolvePendingCallOpening(
          characterId: 'i',
          pending: (characterId: 'i', opening: '   '),
        ),
        isNull,
      );
    });
  });

  group('CallGenerationTracker', () {
    test('three repeated starts are idempotent', () {
      final tracker = CallGenerationTracker();

      expect(tracker.shouldStart(10), isTrue);
      expect(tracker.shouldStart(10), isFalse);
      expect(tracker.shouldStart(10), isFalse);
      expect(tracker.activeGeneration, 10);
    });

    test('a terminated generation cannot reopen from a late start', () {
      final tracker = CallGenerationTracker();

      expect(tracker.shouldStart(10), isTrue);
      expect(tracker.shouldEnd(10), isTrue);
      expect(tracker.shouldStart(10), isFalse);
      expect(tracker.activeGeneration, isNull);
    });

    test('end arriving before start permanently terminates that generation',
        () {
      final tracker = CallGenerationTracker();

      expect(tracker.shouldEnd(10), isFalse);
      expect(tracker.shouldStart(10), isFalse);
      expect(tracker.terminatedWatermark, 10);
    });

    test('old start and end cannot overwrite a newer active call', () {
      final tracker = CallGenerationTracker();

      expect(tracker.shouldStart(10), isTrue);
      expect(tracker.shouldEnd(10), isTrue);
      expect(tracker.shouldStart(11), isTrue);
      expect(tracker.shouldStart(10), isFalse);
      expect(tracker.shouldEnd(10), isFalse);
      expect(tracker.activeGeneration, 11);
    });

    test('newer start can succeed on retry after active call ends', () {
      final tracker = CallGenerationTracker();

      expect(tracker.shouldStart(10), isTrue);
      expect(tracker.shouldStart(11), isFalse);
      expect(tracker.watermark, 11);
      expect(tracker.shouldEnd(10), isTrue);
      expect(tracker.shouldStart(11), isTrue);
    });

    test('generation-less legacy end still force-ends the active call', () {
      final tracker = CallGenerationTracker();

      expect(tracker.shouldStart(10), isTrue);
      expect(tracker.shouldEnd(null), isTrue);
      expect(tracker.activeGeneration, isNull);
      expect(tracker.shouldStart(10), isFalse);
    });
  });

  group('CallLifecycleQueue', () {
    test('a new start waits until the previous teardown completes', () async {
      final queue = CallLifecycleQueue();
      final cleanup = Completer<void>();
      var start2Ran = false;

      final end1 = queue.enqueue(() => cleanup.future);
      final start2 = queue.enqueue(() async => start2Ran = true);
      await Future<void>.delayed(Duration.zero);

      expect(start2Ran, isFalse);
      cleanup.complete();
      await end1;
      await start2;
      expect(start2Ran, isTrue);
    });

    test('end-before-queued-start terminates it without deadlock', () async {
      final tracker = CallGenerationTracker();
      final queue = CallLifecycleQueue();
      final cleanup = Completer<void>();
      var start2Ran = false;

      expect(tracker.shouldStart(1), isTrue);
      expect(tracker.shouldEnd(1), isTrue);
      final end1 = queue.enqueue(() => cleanup.future);

      expect(tracker.shouldStart(2), isTrue);
      final start2 = queue.enqueue(() async {
        if (tracker.activeGeneration == 2) start2Ran = true;
      });
      expect(tracker.shouldEnd(2), isTrue);

      cleanup.complete();
      await end1;
      await start2;
      expect(start2Ran, isFalse);
      expect(tracker.shouldStart(2), isFalse);
    });
  });

  group('isLoadableCallAvatar', () {
    test('legacy i seed and empty values use the fallback', () {
      expect(isLoadableCallAvatar('i'), isFalse);
      expect(isLoadableCallAvatar(''), isFalse);
      expect(isLoadableCallAvatar(null), isFalse);
    });

    test('accepts valid remote URLs and local image paths', () {
      expect(isLoadableCallAvatar('https://example.com/i.png'), isTrue);
      expect(isLoadableCallAvatar('/data/user/0/app/avatar.png'), isTrue);
      expect(isLoadableCallAvatar(r'C:/Users/USER'), isTrue);
      expect(isLoadableCallAvatar('avatar.jpg'), isTrue);
    });

    test('rejects malformed remote URLs and bare names', () {
      expect(isLoadableCallAvatar('https://'), isFalse);
      expect(isLoadableCallAvatar('Lin Ai'), isFalse);
    });
  });
}
