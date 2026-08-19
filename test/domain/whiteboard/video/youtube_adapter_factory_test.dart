/// Tests for [createYouTubeAdapter] platform routing.
///
/// On Windows this verifies the factory selects the WebView2 adapter. Other
/// native desktop platforms retain the honest unavailable stub.
/// On Flutter Web, a separate test file exercises the [WebYouTubePlayerAdapter]
/// via conditional import.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/video/youtube_adapter_factory.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory_stub.dart';
import 'package:memex/domain/whiteboard/video/windows_youtube_player_adapter.dart';

void main() {
  group('createYouTubeAdapter (non-web)', () {
    test('returns a PlayerAdapter with youtube providerId', () {
      final adapter = createYouTubeAdapter();
      expect(adapter.providerId, equals('youtube'));
    });

    test('routes Windows to WebView2 and other desktop to the stub', () {
      final adapter = createYouTubeAdapter();
      if (Platform.isWindows) {
        expect(adapter, isA<WindowsYouTubePlayerAdapter>());
      } else {
        expect(adapter, isA<StubYouTubePlayerAdapter>());
      }
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

    test('Windows URL parsing accepts official YouTube shapes', () {
      expect(
        WindowsYouTubePlayerAdapter.extractVideoId(
          'https://www.youtube.com/watch?v=M7lc1UVf-VE',
        ),
        'M7lc1UVf-VE',
      );
      expect(
        WindowsYouTubePlayerAdapter.extractVideoId(
          'https://youtu.be/M7lc1UVf-VE?t=2',
        ),
        'M7lc1UVf-VE',
      );
      expect(
        WindowsYouTubePlayerAdapter.extractVideoId(
          'https://www.youtube.com/embed/M7lc1UVf-VE',
        ),
        'M7lc1UVf-VE',
      );
      expect(
        WindowsYouTubePlayerAdapter.extractVideoId('https://example.com/x'),
        isNull,
      );
    });

    test('Windows failures stay explicit for runtime, network, and embedding',
        () {
      expect(
        WindowsYouTubePlayerAdapter.runtimeFailureMessage(null),
        contains('WebView2 Runtime'),
      );
      expect(
        WindowsYouTubePlayerAdapter.pageLoadFailureMessage('connectionAborted'),
        contains('connectionAborted'),
      );
      expect(
        WindowsYouTubePlayerAdapter.youtubeErrorMessage(101),
        contains('禁止'),
      );
      expect(
        WindowsYouTubePlayerAdapter.youtubeErrorMessage(150),
        contains('嵌入'),
      );
    });
  });
}
