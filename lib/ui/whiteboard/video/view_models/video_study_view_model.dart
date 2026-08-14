/// ViewModel for the video study screen.
///
/// Manages the full lifecycle: adapter setup, subtitle loading, playback
/// control, bidirectional sync, annotation creation/restoration, and session
/// persistence. Uses [ChangeNotifier] following the project's MVVM pattern.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';

/// Dock orientation for the ContextDock (subtitle/annotation panel).
enum DockOrientation { right, bottom }

/// The state of a single video annotation in the UI.
class UIAnnotation {
  final AnchorContract anchor;
  final CardContract card;

  const UIAnnotation({required this.anchor, required this.card});

  int get startMs => anchor.positionSpec['start_ms'] as int? ?? 0;
  int get endMs => anchor.positionSpec['end_ms'] as int? ?? 0;
  bool get isPoint => anchor.positionSpec['is_point'] as bool? ?? false;
}

/// ViewModel for video study — the complete playback → annotation pipeline.
class VideoStudyViewModel extends ChangeNotifier {
  final PlayerAdapter adapter;
  final String sourceId;
  final String sourceVersionId;
  final String providerId;

  PlayerSyncController? _syncController;
  final VideoAnnotationService _annotationService = VideoAnnotationService();

  TimedTextTrack? _track;
  int _activeCueIndex = -1;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _isPlaying = false;
  bool _isLoaded = false;
  bool _needsSubtitle = false;
  String? _errorMessage;

  final List<UIAnnotation> _annotations = [];
  final Map<String, String> _anchorToCard = {};

  DockOrientation _dockOrientation = DockOrientation.right;
  double _dockRatio = 0.35; // ContextDock gets 35% (player gets 65%)

  String? _pendingAnnotationCueId;
  int? _pendingAnnotationStartMs;
  int? _pendingAnnotationEndMs;
  bool _showSaveConfirmation = false;

  VideoStudyViewModel({
    required this.adapter,
    required this.sourceId,
    required this.sourceVersionId,
    required this.providerId,
    TimedTextTrack? initialTrack,
  }) {
    _track = initialTrack;
    _needsSubtitle = initialTrack == null ||
        initialTrack.reliability == TimedTextReliability.unavailable ||
        initialTrack.cues.isEmpty;
  }

  // ─── Track ───

  TimedTextTrack? get track => _track;
  bool get needsSubtitle => _needsSubtitle;
  String? get errorMessage => _errorMessage;

  // ─── Playback ───

  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  bool get isPlaying => _isPlaying;
  bool get isLoaded => _isLoaded;
  bool get canSeek => adapter.capability.canSeek;
  bool get canReadPosition => adapter.capability.canReadPosition;
  bool get canReadDuration => adapter.capability.canReadDuration;
  bool get isPlaybackStudyCapable => adapter.capability.isPlaybackStudyCapable;

  // ─── Sync ───

  int get activeCueIndex => _activeCueIndex;

  // ─── Annotations ───

  List<UIAnnotation> get annotations => List.unmodifiable(_annotations);

  // ─── Dock ───

  DockOrientation get dockOrientation => _dockOrientation;
  double get dockRatio => _dockRatio;

  void setDockOrientation(DockOrientation orientation) {
    _dockOrientation = orientation;
    notifyListeners();
  }

  void setDockRatio(double ratio) {
    _dockRatio = ratio.clamp(0.20, 0.50);
    notifyListeners();
  }

  // ─── Lifecycle ───

  /// Loads the video and starts the sync controller.
  Future<void> initialize({String? embedUrl}) async {
    try {
      await adapter.load(sourceId, embedUrl: embedUrl);
      _isLoaded = true;

      if (_track != null && _track!.cues.isNotEmpty) {
        _syncController = PlayerSyncController(
          adapter: adapter,
          track: _track!,
          onActiveCueChanged: (idx) {
            _activeCueIndex = idx;
            notifyListeners();
          },
          onPositionChanged: (ms) {
            _positionMs = ms;
            notifyListeners();
          },
          onDurationChanged: (ms) {
            _durationMs = ms;
            notifyListeners();
          },
        );
        _syncController!.start();
      } else if (canReadPosition) {
        // No subtitle track but player still emits time events.
        _syncController = PlayerSyncController(
          adapter: adapter,
          track: const TimedTextTrack(
            trackId: 'empty',
            sourceId: '',
            reliability: TimedTextReliability.unavailable,
          ),
          onPositionChanged: (ms) {
            _positionMs = ms;
            notifyListeners();
          },
          onDurationChanged: (ms) {
            _durationMs = ms;
            notifyListeners();
          },
        );
        _syncController!.start();
      }

      if (canReadDuration) {
        _durationMs = await adapter.durationMs() ?? 0;
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = '加载失败：$e';
      notifyListeners();
    }
  }

  /// Loads a subtitle track from raw SRT/VTT content.
  void loadSubtitleFromText(String raw, {TimedTextSourceKind sourceKind = TimedTextSourceKind.userImport}) {
    final result = SubtitleParser.parse(
      raw,
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      sourceKind: sourceKind,
    );
    if (result.isSuccess && result.track != null) {
      _setTrack(result.track!);
    } else {
      _errorMessage = result.error ?? '字幕解析失败';
      _needsSubtitle = true;
      notifyListeners();
    }
  }

  /// Sets a platform-provided track.
  void setTrack(TimedTextTrack track) {
    _setTrack(track);
  }

  void _setTrack(TimedTextTrack track) {
    _track = track;
    _needsSubtitle = track.reliability == TimedTextReliability.unavailable ||
        track.cues.isEmpty;
    _errorMessage = null;

    _syncController?.dispose();
    if (_isLoaded && !_needsSubtitle) {
      _syncController = PlayerSyncController(
        adapter: adapter,
        track: track,
        onActiveCueChanged: (idx) {
          _activeCueIndex = idx;
          notifyListeners();
        },
        onPositionChanged: (ms) {
          _positionMs = ms;
          notifyListeners();
        },
        onDurationChanged: (ms) {
          _durationMs = ms;
          notifyListeners();
        },
      );
      _syncController!.start();
    }

    notifyListeners();
  }

  // ─── Playback control ───

  Future<void> play() async {
    if (!canReadPosition) return;
    await adapter.play();
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    await adapter.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekTo(int ms) async {
    if (!canSeek) return;
    await _syncController?.seekToPosition(ms);
    notifyListeners();
  }

  Future<void> seekToCue(int cueIndex) async {
    if (!canSeek || _track == null) return;
    await _syncController?.seekToCue(cueIndex);
    notifyListeners();
  }

  // ─── Annotations ───

  /// Starts creating an annotation at the current position or a specific cue.
  void beginAnnotation({int? cueIndex, int? startMs, int? endMs}) {
    if (cueIndex != null && _track != null && cueIndex < _track!.cues.length) {
      final cue = _track!.cues[cueIndex];
      _pendingAnnotationCueId = cue.cueId;
      _pendingAnnotationStartMs = cue.startMs;
      _pendingAnnotationEndMs = cue.endMs;
    } else {
      _pendingAnnotationStartMs = startMs ?? _positionMs;
      _pendingAnnotationEndMs = endMs ?? _positionMs;
    }
    notifyListeners();
  }

  /// Confirms and saves an annotation.
  void confirmAnnotation({required String title, required String body, String? quote}) {
    if (_pendingAnnotationStartMs == null) return;

    final spec = _pendingAnnotationStartMs == _pendingAnnotationEndMs
        ? TimeRangeAnchorSpec.point(_pendingAnnotationStartMs!,
            cueId: _pendingAnnotationCueId)
        : TimeRangeAnchorSpec.range(
            _pendingAnnotationStartMs!,
            _pendingAnnotationEndMs!,
            cueId: _pendingAnnotationCueId);

    final result = _annotationService.createAnnotation(
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      request: AnnotationCreationRequest(
        spec: spec,
        title: title,
        body: body,
        quote: quote,
      ),
    );

    _annotations.add(UIAnnotation(anchor: result.anchor, card: result.card));
    _anchorToCard[result.anchor.anchorId] = result.card.cardId;
    _pendingAnnotationCueId = null;
    _pendingAnnotationStartMs = null;
    _pendingAnnotationEndMs = null;
    _showSaveConfirmation = true;
    notifyListeners();

    // Auto-dismiss the confirmation after a short delay.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_showSaveConfirmation) {
        _showSaveConfirmation = false;
        notifyListeners();
      }
    });
  }

  /// Dismisses the save confirmation immediately.
  void dismissSaveConfirmation() {
    _showSaveConfirmation = false;
    notifyListeners();
  }

  /// Cancels a pending annotation.
  void cancelAnnotation() {
    _pendingAnnotationCueId = null;
    _pendingAnnotationStartMs = null;
    _pendingAnnotationEndMs = null;
    notifyListeners();
  }

  bool get hasPendingAnnotation => _pendingAnnotationStartMs != null;
  int? get pendingAnnotationStartMs => _pendingAnnotationStartMs;

  /// Whether the annotation-saved confirmation should be shown.
  bool get showSaveConfirmation => _showSaveConfirmation;

  // ─── Session persistence ───

  /// Saves the current session to a JSON file at [path].
  Future<void> saveSession(String path) async {
    final session = _annotationService.saveSession(
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      lastPositionMs: _positionMs,
      anchors: _annotations.map((a) => a.anchor).toList(),
      annotationCards: _annotations.map((a) => a.card).toList(),
      anchorToCard: _anchorToCard,
    );
    final file = File(path);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  /// Restores a session from a JSON file at [path].
  Future<void> restoreSession(String path, {String? currentVersionId}) async {
    try {
      final file = File(path);
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      var session = VideoAnnotationSession.fromJson(json);

      if (currentVersionId != null && currentVersionId != session.sourceVersionId) {
        session = _annotationService.restoreSession(
          saved: session,
          currentVersionId: currentVersionId,
        );
      }

      _annotations.clear();
      _anchorToCard.clear();
      for (var i = 0; i < session.anchors.length; i++) {
        final anchor = session.anchors[i];
        final card = session.annotationCards.length > i
            ? session.annotationCards[i]
            : null;
        if (card != null) {
          _annotations.add(UIAnnotation(anchor: anchor, card: card));
          _anchorToCard[anchor.anchorId] = card.cardId;
        }
      }

      // Restore playback position
      if (canSeek && session.lastPositionMs > 0) {
        await seekTo(session.lastPositionMs);
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = '恢复失败：$e';
      notifyListeners();
    }
  }

  /// Restores from an in-memory [VideoAnnotationSession].
  void restoreFromSession(VideoAnnotationSession session) {
    _annotations.clear();
    _anchorToCard.clear();
    for (var i = 0; i < session.anchors.length; i++) {
      final anchor = session.anchors[i];
      final card = session.annotationCards.length > i
          ? session.annotationCards[i]
          : null;
      if (card != null) {
        _annotations.add(UIAnnotation(anchor: anchor, card: card));
        _anchorToCard[anchor.anchorId] = card.cardId;
      }
    }
    notifyListeners();
  }

  // ─── Helpers ───

  /// Formats milliseconds as MM:SS or HH:MM:SS.
  static String formatTimecode(int ms) {
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _syncController?.dispose();
    if (adapter is FixturePlayerAdapter) {
      (adapter as FixturePlayerAdapter).dispose();
    } else if (adapter is YouTubePlayerAdapter) {
      (adapter as YouTubePlayerAdapter).dispose();
    }
    super.dispose();
  }
}