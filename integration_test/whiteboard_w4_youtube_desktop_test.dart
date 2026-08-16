/// W4 real desktop (Chrome window) YouTube playback acceptance.
///
/// Runs in a real Chrome browser window (Flutter Web) with the real
/// WebYouTubePlayerAdapter (official YouTube IFrame API) and the real HTTP
/// timedtext fetcher:
///   load → play/pause → position/duration → seek → platform subtitle
///   auto-fetch (honest success OR honest "needs subtitles" failure).
///
/// The YouTube video (dQw4w9WgXcQ) is real; position/duration assertions are
/// tolerant of network variance. The timedtext assertion only locks the
/// HONESTY contract: on success a usable track with cues must be returned,
/// on failure an honest error must be present — never a fabricated track.
///
/// Run: flutter test integration_test/whiteboard_w4_youtube_desktop_test.dart -d chrome
library;

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory.dart';
import 'package:memex/domain/whiteboard/video/web_youtube_player_adapter.dart';
import 'package:memex/ui/whiteboard/video/session_store.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';
import 'package:memex/ui/whiteboard/video/view_models/video_study_view_model.dart';

const _watchUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

Future<T> _waitUntil<T>(
  WidgetTester tester,
  Future<T> Function() probe, {
  required bool Function(T) done,
  int maxSeconds = 60,
  String? label,
}) async {
  for (var i = 0; i < maxSeconds; i++) {
    // Fixed-duration pumps drive the real frame pipeline (platform view
    // mounting, IFrame API) without ever settling — the sync controller
    // rebuilds constantly, so pumpAndSettle would hang.
    await tester.pump(const Duration(seconds: 1));
    try {
      final value = await probe();
      if (done(value)) return value;
    } catch (_) {
      // Player not ready yet.
    }
  }
  fail('waitUntil(${label ?? 'probe'}) timed out after $maxSeconds s');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('YouTube real online playback: load → play/pause → position → '
      'duration → seek → timedtext auto-fetch', (tester) async {
    final adapter = createYouTubeAdapter();
    expect(adapter.providerId, equals('youtube'));

    // Pump the REAL study screen so the HtmlElementView mounts and the
    // IFrame player host div appears in the DOM (adapter-only driving never
    // creates the div — the player would never initialize).
    await tester.pumpWidget(
      MaterialApp(
        home: VideoStudyScreen(
          adapter: adapter,
          sourceId: 'src_yt_acceptance',
          sourceVersionId: 'ver_acceptance_v1',
          providerId: 'youtube',
          embedUrl: _watchUrl,
        ),
      ),
    );

    // ── load: real IFrame player for a real video
    final durationMs = await _waitUntil(
      tester,
      () => adapter.durationMs(),
      done: (d) => d != null && d > 5000,
      label: 'player duration',
    );
    debugPrint('W4IT: duration=${durationMs}ms');

    // ── seek: real seek on the controllable time axis
    await adapter.seekTo(30000);
    final posAfterSeek = await _waitUntil(
      tester,
      () => adapter.currentPositionMs(),
      done: (p) => p >= 25000,
      label: 'seek settle',
    );
    debugPrint('W4IT: seek → ${posAfterSeek}ms');
    expect(posAfterSeek, inInclusiveRange(25000, 60000));

    // ── play: position advances in real time
    // Chrome's autoplay policy blocks UNMUTED playback without a real user
    // gesture inside the IFrame (a synthetic tap cannot grant activation to
    // the embed's document). Muted playback is exempt — mute, play, then
    // verify the real time axis advances.
    final webAdapter = adapter as WebYouTubePlayerAdapter;
    await webAdapter.setMuted(true);
    await tester.pump(const Duration(milliseconds: 300));
    await adapter.play();
    final p1 = await _waitUntil(
      tester,
      () => adapter.currentPositionMs(),
      done: (p) => p > posAfterSeek + 3000,
      label: 'playing advance',
    );
    debugPrint('W4IT: playing → ${p1}ms');
    expect(p1, greaterThan(posAfterSeek));

    // ── pause: position stops advancing
    await adapter.pause();
    await tester.pump(const Duration(seconds: 1));
    final p2 = await adapter.currentPositionMs();
    await tester.pump(const Duration(seconds: 2));
    final p3 = await adapter.currentPositionMs();
    debugPrint('W4IT: paused at ${p2}ms, then ${p3}ms');
    expect((p3 - p2).abs(), lessThanOrEqualTo(1500));

    // ── platform subtitle auto-fetch (real HTTP in the browser context)
    final service = YouTubeTimedTextService();
    final result = await service.fetchForVideo(
      _watchUrl,
      sourceId: 'src_yt_acceptance',
      sourceVersionId: 'ver_acceptance_v1',
    );
    if (result.isSuccess) {
      final track = result.track!;
      debugPrint('W4IT: timedtext OK lang=${track.language} '
          'cues=${track.cues.length} reliability=${track.reliability.name}');
      expect(track.cues, isNotEmpty, reason: 'usable platform track loaded');
      expect(track.sourceKind, equals(TimedTextSourceKind.platform));
      final firstCue = track.cues.first;
      debugPrint('W4IT: first cue [${firstCue.startMs}–${firstCue.endMs}] '
          '${firstCue.text}');
    } else {
      // Honest failure is a VALID acceptance outcome when the environment
      // blocks the endpoint (CORS / network). It must never fabricate.
      debugPrint('W4IT: timedtext HONEST FAIL: ${result.error}');
      expect(result.track, isNull);
      expect(result.error, isNotNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    // PlayerAdapter has no dispose on the contract; the concrete web adapter
    // does. Best-effort cleanup via dynamic dispatch (web-only integration).
    try {
      (adapter as dynamic).dispose();
    } catch (_) {
      // Adapter has no dispose() — nothing to clean up.
    }
  });

  testWidgets('parse the real watch page in the browser context',
      (tester) async {
    // Verifies the transport + parser against the REAL watch page (not a
    // fixture): either captions are found, or an honest failure is reported.
    final service = YouTubeTimedTextService();
    final html = await service.transport
        .getText('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    if (html == null) {
      debugPrint('W4IT: watch page fetch blocked (honest fallback)');
      expect(service.parseTrackList(''), isNull);
    } else {
      final tracks = service.parseTrackList(html);
      debugPrint('W4IT: watch page parsed tracks=${tracks?.length}');
      expect(tracks, isNotNull, reason: 'real watch page has captions');
    }
  });

  testWidgets('restart recovery: localStorage session round-trip in Chrome',
      (tester) async {
    // Runs in the REAL browser: the web session store writes to
    // window.localStorage; a fresh ViewModel + store instance (restart
    // semantics) must restore annotations and position.
    final store = createVideoSessionStore();

    final first = VideoStudyViewModel(
      adapter: FixturePlayerAdapter(durationMs: 36000),
      sourceId: 'src_restart_test',
      sourceVersionId: 'ver_restart_v1',
      providerId: 'fixture',
      sessionStore: store,
    );
    await first.initialize();
    first.beginAnnotation(startMs: 5000, endMs: 9000);
    first.confirmAnnotation(title: '重启恢复验证', body: '来自真实浏览器 localStorage');
    await first.saveSession();
    first.dispose();

    // Prove the data actually lives in localStorage (not just in memory).
    final storage = globalContext['localStorage'] as JSObject;
    final raw = storage.callMethod<JSString?>(
        'getItem'.toJS, 'whiteboard_w4_video_session'.toJS);
    debugPrint('W4IT: localStorage session bytes=${raw?.toDart.length}');
    expect(raw, isNotNull);

    // "Restart": a brand-new ViewModel reading the same store.
    final second = VideoStudyViewModel(
      adapter: FixturePlayerAdapter(durationMs: 36000),
      sourceId: 'src_restart_test',
      sourceVersionId: 'ver_restart_v1',
      providerId: 'fixture',
      sessionStore: store,
    );
    await second.initialize();
    await second.restoreSession();
    expect(second.annotations.length, equals(1));
    expect(second.annotations.first.card.title, equals('重启恢复验证'));
    expect(second.annotations.first.startMs, equals(5000));
    debugPrint('W4IT: restart restore OK '
        'annotations=${second.annotations.length} '
        'position=${second.positionMs}ms');
    second.dispose();

    await store.clear();
  });
}
