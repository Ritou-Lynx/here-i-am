import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/video/bilibili_html_media_bridge.dart';

void main() {
  test('capability stays limited until read and no-op seek both verify',
      () async {
    final bridge = BilibiliHtmlMediaBridge();
    expect(bridge.capability.canEmbedPlayer, isTrue);
    expect(bridge.capability.canReadPosition, isFalse);

    final calls = <String>[];
    final verified = await bridge.verify((script) async {
      calls.add(script);
      if (script.contains('seekMs')) return true;
      return {'position_ms': 4200, 'duration_ms': 90000};
    });

    expect(verified, isTrue);
    expect(calls, hasLength(3));
    expect(bridge.capability.canReadPosition, isTrue);
    expect(bridge.capability.canReadDuration, isTrue);
    expect(bridge.capability.canSeek, isTrue);
    expect(bridge.capability.canCreateTimeAnchor, isTrue);
  });

  test('failed write verification keeps playable-but-limited capability',
      () async {
    final bridge = BilibiliHtmlMediaBridge();
    final verified = await bridge.verify((script) async {
      if (script.contains('seekMs')) return false;
      return {'position_ms': 1000, 'duration_ms': 2000};
    });

    expect(verified, isFalse);
    expect(bridge.capability.canEmbedPlayer, isTrue);
    expect(bridge.capability.canSeek, isFalse);
    expect(bridge.failure, contains('拒绝'));
  });

  test('only verified, well-formed bridge events update time', () async {
    final bridge = BilibiliHtmlMediaBridge();
    expect(
      bridge.acceptEvent({
        'type': 'hereiam:bilibili-media',
        'event': 'time',
        'position_ms': 1,
        'duration_ms': 2,
      }),
      isNull,
    );
    await bridge.verify((script) async => script.contains('seekMs')
        ? true
        : {'position_ms': 1000, 'duration_ms': 5000});

    expect(bridge.acceptEvent({'type': 'other'}), isNull);
    expect(
      bridge.acceptEvent({
        'type': 'hereiam:bilibili-media',
        'event': 'time',
        'position_ms': 2500,
        'duration_ms': 5000,
      })?.positionMs,
      2500,
    );
  });

  test('downgrade immediately revokes time capability', () async {
    final bridge = BilibiliHtmlMediaBridge();
    await bridge.verify((script) async => script.contains('seekMs')
        ? true
        : {'position_ms': 1000, 'duration_ms': 5000});
    bridge.downgrade('navigation left the video page');

    expect(bridge.capability.canReadPosition, isFalse);
    expect(bridge.capability.canSeek, isFalse);
    expect(bridge.failure, contains('navigation'));
  });

  test('injected script is narrowly gated and does not inspect cookies or urls',
      () {
    expect(bilibiliHtmlMediaBridgeScript,
        contains("location.hostname !== 'www.bilibili.com'"));
    expect(bilibiliHtmlMediaBridgeScript,
        contains("document.querySelector('video')"));
    expect(bilibiliHtmlMediaBridgeScript, isNot(contains('cookie')));
    expect(bilibiliHtmlMediaBridgeScript, isNot(contains('src')));
    expect(bilibiliHtmlMediaBridgeScript, isNot(contains('fetch(')));
  });

  test('element replacement unbinds listeners and announces a generation', () {
    expect(bilibiliHtmlMediaBridgeScript, contains('new MutationObserver'));
    expect(bilibiliHtmlMediaBridgeScript, contains('removeEventListener'));
    expect(bilibiliHtmlMediaBridgeScript, contains('generation += 1'));
    expect(bilibiliHtmlMediaBridgeScript, contains('sendCandidate()'));
    expect(bilibiliHtmlMediaBridgeScript, contains('await attached.play()'));
  });

  test('verification queues a replacement candidate and notifies every result',
      () async {
    final bridge = BilibiliHtmlMediaBridge();
    final firstReadStarted = Completer<void>();
    final releaseFirstRead = Completer<void>();
    var readCalls = 0;
    var settledCalls = 0;
    final coordinator = BilibiliBridgeVerificationCoordinator(
      bridge: bridge,
      execute: (script) async {
        if (script.contains('seekMs')) return true;
        readCalls++;
        if (readCalls == 1) {
          firstReadStarted.complete();
          await releaseFirstRead.future;
        }
        return {'position_ms': 1200, 'duration_ms': 6400};
      },
      onSettled: () => settledCalls++,
    );

    coordinator.candidate(1);
    await firstReadStarted.future;
    coordinator.candidate(2);
    releaseFirstRead.complete();
    await coordinator.waitForIdle();

    expect(readCalls, 3, reason: 'stale handshake plus a full queued retry');
    expect(settledCalls, 2, reason: 'stale and successful results both notify');
    expect(bridge.generation, 2);
    expect(bridge.isVerified, isTrue);
  });

  test('failed verification still emits capability state', () async {
    final bridge = BilibiliHtmlMediaBridge();
    var settledCalls = 0;
    final coordinator = BilibiliBridgeVerificationCoordinator(
      bridge: bridge,
      execute: (_) async => null,
      onSettled: () => settledCalls++,
    );
    coordinator.candidate(1);
    await coordinator.waitForIdle();

    expect(bridge.isVerified, isFalse);
    expect(settledCalls, 1);
    expect(bridge.failure, isNotNull);
  });
}
