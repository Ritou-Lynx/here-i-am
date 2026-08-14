/// YouTube IFrame Player Adapter for Flutter Web.
///
/// Drives the official YouTube IFrame Player API directly from Dart via
/// `dart:js_interop`, embedding a `YT.Player` inside a platform view
/// (`HtmlElementView`). This is the MVP desktop playback path: Flutter Web
/// hosts the IFrame in Chrome, giving the研读 workflow a real controllable
/// player on desktop without a native Windows WebView dependency.
///
/// **Compliance**: Only uses the official YouTube IFrame Player API. Does
/// not download, remove DRM, bypass login/age/region restrictions, or access
/// private content. Platform-side restrictions render in the IFrame itself.
///
/// **Lifecycle**: Call [ensureYouTubeIframeApiReady] once per page (idempotent)
/// before constructing adapters. [load] creates the `YT.Player` for the given
/// video ID; [dispose] destroys it and stops polling.
///
/// **Platform**: Web only. On Android use [YouTubePlayerAdapter]
/// (`webview_flutter`). Construction on non-web platforms is a no-op stub —
/// callers should check [isAvailable] before relying on playback.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

/// Minimal static interop for `document` access on Flutter Web.
@JS('document')
external JSDocument get _jsDocument;

/// `document` interop — only the methods we use.
extension type JSDocument._(JSObject _) implements JSObject {
  external JSHTMLElement createElement(String tagName);
  external JSHTMLElement? querySelector(String selector);
  external JSHTMLElement? getElementById(String id);
  external JSHTMLHeadElement? get head;
}

extension type JSHTMLElement._(JSObject _) implements JSObject {
  external set id(String value);
  external JSCSSStyleDeclaration get style;
  @JS('src')
  external set src(String value);
  external JSHTMLHeadElement? get parent;
}

extension type JSHTMLHeadElement._(JSObject _) implements JSObject {
  external void appendChild(JSHTMLElement node);
}

extension type JSCSSStyleDeclaration._(JSObject _) implements JSObject {
  external set width(String value);
  external set height(String value);
}

/// Lazy access to `document`, guarded for non-web.
JSDocument? get webDocument {
  if (!kIsWeb) return null;
  return _jsDocument;
}

/// Global flag ensuring the IFrame API script + ready callback are wired once.
bool _ytApiReady = false;
final Completer<void> _ytApiCompleter = Completer<void>();

/// Ensures the YouTube IFrame API script is loaded and `onYouTubeIframeAPIReady`
/// has fired. Idempotent; safe to call repeatedly.
///
/// Must run on Flutter Web. On other platforms this returns immediately
/// without completing (callers guard with [kIsWeb] first).
Future<void> ensureYouTubeIframeApiReady() async {
  if (!kIsWeb) return;
  if (_ytApiReady && _ytApiCompleter.isCompleted) return;

  // Install the ready callback if not already present.
  final hasCallback = globalContext.has('onYouTubeIframeAPIReady');
  if (!hasCallback) {
    globalContext['onYouTubeIframeAPIReady'] = (() {
      if (!_ytApiCompleter.isCompleted) {
        _ytApiReady = true;
        _ytApiCompleter.complete();
      }
    }).toJS;
  }

  // Inject the IFrame API script if not already present.
  final doc = webDocument;
  if (doc != null) {
    final existing = doc.querySelector('script[src*="youtube.com/iframe_api"]');
    if (existing == null && !_ytApiCompleter.isCompleted) {
      final script = doc.createElement('script');
      script.src = 'https://www.youtube.com/iframe_api';
      doc.head!.appendChild(script);
    }
  }

  // If the API was already ready before this call, mark it so.
  if (!_ytApiCompleter.isCompleted) {
    final ytHolder = globalContext['YT'];
    final ytReady = ytHolder != null && (ytHolder as JSObject).has('Player');
    if (ytReady) {
      _ytApiReady = true;
      _ytApiCompleter.complete();
    }
  }

  await _ytApiCompleter.future;
}

/// YouTube IFrame Player Adapter for Flutter Web.
///
/// Embeds a `YT.Player` in a platform view identified by [viewTypeId].
/// The UI embeds this view via `HtmlElementView(viewType: viewTypeId)`.
class WebYouTubePlayerAdapter implements PlayerAdapter {
  final String viewTypeId;

  bool _isPlayerReady = false;
  int _durationMs = 0;
  int _positionMs = 0;
  String? _pendingVideoId;
  Timer? _pollTimer;
  JSObject? _player;

  final StreamController<PlayerTimeEvent> _timeController =
      StreamController<PlayerTimeEvent>.broadcast();

  static int _counter = 0;

  WebYouTubePlayerAdapter() : viewTypeId = 'yt-player-${++_counter}' {
    // Register the platform view factory up front (not deferred to load()).
    // Flutter web silently drops an HtmlElementView whose viewType has no
    // registered factory — if registration waits until load(), the widget's
    // first build renders nothing and the host div never appears in the DOM.
    _registerPlatformView();
  }

  @override
  String get providerId => 'youtube';

  @override
  PlayerCapability get capability =>
      ProviderCapabilityMatrix.capabilityFor('youtube');

  @override
  Stream<PlayerTimeEvent> get timeEvents => _timeController.stream;

  /// Whether this adapter can actually play video on the current platform.
  ///
  /// True only on Flutter Web where the IFrame API is available.
  bool get isAvailable => kIsWeb;

  /// Loads a YouTube video by video ID or watch URL.
  ///
  /// Platform view registration happens in the constructor so the
  /// [HtmlElementView] always finds a factory on its first build. The actual
  /// `YT.Player` creation is deferred — [ensureYouTubeIframeApiReady] loads
  /// the IFrame API, then `_ensurePlayerWhenReady` polls until the host div is
  /// in the DOM before constructing the player.
  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {
    if (!kIsWeb) return;
    final videoId = _extractVideoId(embedUrl);
    if (videoId == null) return;
    _pendingVideoId = videoId;

    await ensureYouTubeIframeApiReady();

    // Kick off async player creation — don't await it so the UI can render.
    _ensurePlayerWhenReady();
  }

  void _ensurePlayerWhenReady() {
    if (_player != null) return;
    final videoId = _pendingVideoId;
    if (videoId == null) return;

    final doc = webDocument;
    if (doc == null) return;

    final el = doc.getElementById(viewTypeId);
    if (el != null) {
      _createPlayer(videoId);
    } else {
      // Div not mounted yet — retry on the next microtask.
      Timer(const Duration(milliseconds: 30), _ensurePlayerWhenReady);
    }
  }

  void _registerPlatformView() {
    ui_web.platformViewRegistry.registerViewFactory(
      viewTypeId,
      (int viewId) {
        final doc = webDocument!;
        final div = doc.createElement('div');
        div.id = viewTypeId;
        div.style.width = '100%';
        div.style.height = '100%';
        return div as JSObject;
      },
    );
  }

  void _createPlayer(String videoId) {
    final ytHolder = globalContext['YT'] as JSObject;
    final playerCtor = ytHolder.getProperty<JSFunction>('Player'.toJS);

    final config = _buildPlayerConfig(videoId);
    // YT.Player(element, config): the first argument is the DOM element ID
    // (or the element itself) where the IFrame is attached; the second is the
    // config object. Passing config as the only argument makes the API treat it
    // as the element and read properties like `.toLowerCase()` on it → crash.
    _player = playerCtor.callAsConstructor<JSObject>(viewTypeId.toJS, config);
  }

  JSObject _buildPlayerConfig(String videoId) {
    final readyCallback = (() {
      _isPlayerReady = true;
      _timeController.add(PlayerTimeEvent(
        positionMs: 0,
        durationMs: 0,
        at: DateTime.now(),
      ));
      // Start continuous polling as soon as the player is ready so time
      // events keep flowing regardless of HOW playback starts (native iframe
      // button, our play(), auto-play, seek). Reverse highlight (playback →
      // subtitle) depends on this stream.
      _startPolling();
    }).toJS;

    // YT onStateChange passes an event object; state codes: -1 unstarted,
    // 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued.
    //
    // We keep the continuous polling loop running regardless of state so the
    // reverse highlight (playback → subtitle) always stays in sync, including
    // when the user controls the player from the iframe's own UI (native
    // play/pause/seek buttons), which never calls our play()/pause().
    final stateChangeCallback = ((JSAny? event) {
      final state = _readEventData(event);
      if (state == 0) {
        // Ended — flush the final position then keep polling (position stays).
        _flushPositionOnce();
      }
    }).toJS;

    final events = {
      'onReady': readyCallback,
      'onStateChange': stateChangeCallback,
    }.jsify() as JSObject;

    final playerVars = {
      'playsinline': 1,
      'modestbranding': 1,
      'rel': 0,
      // Hide YouTube's own controls so our overlay control bar (timeline,
      // play/pause, timecode) is the single control surface — otherwise the
      // iframe's native progress bar overlaps ours.
      'controls': 0,
    }.jsify() as JSObject;

    return {
      'videoId': videoId.toJS,
      'events': events,
      'playerVars': playerVars,
    }.jsify() as JSObject;
  }

  /// Reads the numeric `data` field from a YT onStateChange event object.
  int _readEventData(JSAny? event) {
    if (event == null) return -1;
    try {
      final obj = event as JSObject;
      final data = obj['data'];
      if (data is JSNumber) return data.toDartInt;
      // data may be a Dart num wrapped as JSAny.
      final asNum = data?.dartify();
      return (asNum as num?)?.toInt() ?? -1;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<void> play() async {
    if (!_isPlayerReady || _player == null) return;
    _player!.callMethod('playVideo'.toJS);
    _startPolling();
  }

  @override
  Future<void> pause() async {
    if (!_isPlayerReady || _player == null) return;
    _player!.callMethod('pauseVideo'.toJS);
    _stopPolling();
  }

  @override
  Future<int> currentPositionMs() async {
    if (!_isPlayerReady || _player == null) return _positionMs;
    try {
      final result = _player!.callMethod<JSNumber>('getCurrentTime'.toJS);
      final ms = (result.toDartDouble * 1000).round();
      _positionMs = ms;
      return ms;
    } catch (_) {
      return _positionMs;
    }
  }

  @override
  Future<int?> durationMs() async {
    if (!_isPlayerReady || _player == null) {
      return _durationMs > 0 ? _durationMs : null;
    }
    try {
      final result = _player!.callMethod<JSNumber>('getDuration'.toJS);
      final ms = (result.toDartDouble * 1000).round();
      _durationMs = ms;
      return ms;
    } catch (_) {
      return _durationMs > 0 ? _durationMs : null;
    }
  }

  @override
  Future<void> seekTo(int positionMs) async {
    if (!_isPlayerReady || _player == null) return;
    final seconds = (positionMs / 1000).toStringAsFixed(2);
    _player!.callMethod('seekTo'.toJS, seconds.toJS, true.toJS);
    _positionMs = positionMs;
    _timeController.add(PlayerTimeEvent(
      positionMs: _positionMs,
      durationMs: _durationMs > 0 ? _durationMs : null,
      at: DateTime.now(),
    ));
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_isPlayerReady || _player == null) return;
      try {
        final posResult = _player!.callMethod<JSNumber>('getCurrentTime'.toJS);
        final durResult = _player!.callMethod<JSNumber>('getDuration'.toJS);
        final posMs = (posResult.toDartDouble * 1000).round();
        final durMs = (durResult.toDartDouble * 1000).round();
        if (posMs >= 0) {
          _positionMs = posMs;
          if (durMs > 0) _durationMs = durMs;
          _timeController.add(PlayerTimeEvent(
            positionMs: _positionMs,
            durationMs: _durationMs > 0 ? _durationMs : null,
            at: DateTime.now(),
          ));
        }
      } catch (_) {
        // Player not ready yet — skip.
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Reads the current position once and emits a final time event.
  void _flushPositionOnce() {
    if (!_isPlayerReady || _player == null) return;
    try {
      final posResult = _player!.callMethod<JSNumber>('getCurrentTime'.toJS);
      final durResult = _player!.callMethod<JSNumber>('getDuration'.toJS);
      final posMs = (posResult.toDartDouble * 1000).round();
      final durMs = (durResult.toDartDouble * 1000).round();
      if (posMs >= 0) {
        _positionMs = posMs;
        if (durMs > 0) _durationMs = durMs;
        _timeController.add(PlayerTimeEvent(
          positionMs: _positionMs,
          durationMs: _durationMs > 0 ? _durationMs : null,
          at: DateTime.now(),
        ));
      }
    } catch (_) {
      // Ignore — polling loop will pick it up.
    }
  }

  String? _extractVideoId(String? url) {
    if (url == null || url.isEmpty) return null;
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;
    final watchMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (watchMatch != null) return watchMatch.group(1);
    final shortMatch = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (shortMatch != null) return shortMatch.group(1);
    final embedMatch = RegExp(r'embed/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (embedMatch != null) return embedMatch.group(1);
    return null;
  }

  /// Disposes the adapter: stops polling, destroys the YT.Player, closes stream.
  void dispose() {
    _stopPolling();
    if (_isPlayerReady && _player != null) {
      try {
        _player!.callMethod('destroy'.toJS);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
    _timeController.close();
  }
}