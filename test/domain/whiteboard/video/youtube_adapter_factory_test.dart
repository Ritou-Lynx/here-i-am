/// Tests for [createYouTubeAdapter] platform routing.
///
/// On the Dart VM (no `dart:js_interop`), this verifies the factory returns a
/// [StubYouTubePlayerAdapter] (no-op stub with YouTube capability declarations).
/// On Flutter Web, a separate test file exercises the [WebYouTubePlayerAdapter]
/// via conditional import.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/video/youtube_adapter_factory.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory_stub.dart';

void main() {
  group('createYouTubeAdapter (non-web)', () {
    test('returns a PlayerAdapter with youtube providerId', () {
      final adapter = createYouTubeAdapter();
      expect(adapter.providerId, equals('youtube'));
    });

    test('returns a StubYouTubePlayerAdapter on non-web', () {
      final adapter = createYouTubeAdapter();
      expect(adapter, isA<StubYouTubePlayerAdapter>());
    });

    test('stub isAvailable is false', () {
      final adapter = createYouTubeAdapter() as StubYouTubePlayerAdapter;
      expect(adapter.isAvailable, isFalse);
    });

    test('load is a no-op on the stub', () async {
      final adapter = createYouTubeAdapter() as StubYouTubePlayerAdapter;
      // Should not throw; load returns silently.
      await adapter.load('src_test',
          embedUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('capability declares youtube matrix values', () {
      final adapter = createYouTubeAdapter();
      final cap = adapter.capability;
      // YouTube static capability: controllable but no auto-transcript.
      expect(cap.canSeek, isTrue);
      expect(cap.canReadPosition, isTrue);
      expect(cap.canReadDuration, isTrue);
      expect(cap.canEmbedPlayer, isTrue);
      expect(cap.hasTranscript, isFalse);
    });

    test('play/pause/seek/position/duration are no-ops on the stub', () async {
      final adapter = createYouTubeAdapter() as StubYouTubePlayerAdapter;
      await adapter.play();
      await adapter.pause();
      await adapter.seekTo(5000);
      expect(await adapter.currentPositionMs(), equals(0));
      expect(await adapter.durationMs(), isNull);
    });

    test('timeEvents is empty on the stub', () async {
      final adapter = createYouTubeAdapter() as StubYouTubePlayerAdapter;
      expect(await adapter.timeEvents.isEmpty, isTrue);
    });
  });
}