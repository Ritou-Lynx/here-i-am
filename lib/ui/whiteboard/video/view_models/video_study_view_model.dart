/// ViewModel for the video study screen.
///
/// Manages the full lifecycle: adapter setup, subtitle loading, playback
/// control, bidirectional sync, annotation creation/restoration, and session
/// persistence. Uses [ChangeNotifier] following the project's MVVM pattern.
library;

import 'package:flutter/foundation.dart';

import 'package:memex/data/whiteboard/repository_video_annotation_store.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';
import '../session_store.dart';

/// Dock orientation for the ContextDock (subtitle/annotation panel).
enum DockOrientation { right, bottom }

/// Status of the platform-subtitle auto-fetch (YouTube timedtext).
enum SubtitleAutoFetchStatus { idle, fetching, loaded, failed, skipped }

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
  final RepositoryVideoAnnotationStore? annotationStore;
  final bool runtimePlayerAvailable;

  /// Optional session persistence for restart recovery. When null, session
  /// save/restore is skipped (in-memory only).
  final VideoSessionStore? sessionStore;

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

  SubtitleAutoFetchStatus _subtitleFetchStatus = SubtitleAutoFetchStatus.idle;
  String? _subtitleFetchMessage;
  YouTubeTimedTextFailureKind? _subtitleFailureKind;
  List<YouTubeCaptionTrack> _availableCaptionTracks = const [];
  YouTubeCaptionTrack? _selectedCaptionTrack;
  late YouTubeTimedTextService _timedTextService;
  late bool _ownsTimedTextService;

  final List<UIAnnotation> _annotations = [];
  final Map<String, String> _anchorToCard = {};

  DockOrientation _dockOrientation = DockOrientation.right;
  double _dockRatio = 0.35; // ContextDock gets 35% (player gets 65%)

  String? _pendingAnnotationCueId;
  int? _pendingAnnotationStartMs;
  int? _pendingAnnotationEndMs;
  int? _rangeSelectionStartMs;
  bool _showSaveConfirmation = false;
  bool _isSavingAnnotation = false;
  bool _dockVisible = true;

  VideoStudyViewModel({
    required this.adapter,
    required this.sourceId,
    required this.sourceVersionId,
    required this.providerId,
    TimedTextTrack? initialTrack,
    this.sessionStore,
    this.annotationStore,
    this.runtimePlayerAvailable = true,
    YouTubeTimedTextService? timedTextService,
  }) {
    _track = initialTrack;
    _needsSubtitle = initialTrack == null ||
        initialTrack.reliability == TimedTextReliability.unavailable ||
        initialTrack.cues.isEmpty;
    _ownsTimedTextService = timedTextService == null;
    _timedTextService = timedTextService ?? YouTubeTimedTextService();
    _subtitleFetchStatus = _track?.cues.isNotEmpty == true
        ? SubtitleAutoFetchStatus.loaded
        : SubtitleAutoFetchStatus.idle;
    _updateAvailability();
  }

  // ─── Track ───

  TimedTextTrack? get track => _track;
  bool get needsSubtitle => _needsSubtitle;
  String? get errorMessage => _errorMessage;

  /// Status of the platform-subtitle auto-fetch (YouTube timedtext).
  SubtitleAutoFetchStatus get subtitleFetchStatus => _subtitleFetchStatus;

  /// Honest reason when auto-fetch failed, or a note when it loaded.
  String? get subtitleFetchMessage => _subtitleFetchMessage;
  YouTubeTimedTextFailureKind? get subtitleFailureKind => _subtitleFailureKind;
  List<YouTubeCaptionTrack> get availableCaptionTracks =>
      List.unmodifiable(_availableCaptionTracks);
  YouTubeCaptionTrack? get selectedCaptionTrack => _selectedCaptionTrack;

  // ─── Playback ───

  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  bool get isPlaying => _isPlaying;
  bool get isLoaded => _isLoaded;
  bool get canSeek => adapter.capability.canSeek;
  bool get canReadPosition => adapter.capability.canReadPosition;
  bool get canReadDuration => adapter.capability.canReadDuration;

  /// Static adapter capability declaration (from the W0 contract).
  bool get isPlaybackStudyCapable => adapter.capability.isPlaybackStudyCapable;

  // ─── Runtime availability (W4 model) ───

  late VideoStudyAvailability _availability;

  /// Whether a readable playback position exists at runtime.
  bool get hasReadablePosition => _availability.hasReadablePosition;

  /// Whether playback can be controlled (seek + position + duration).
  bool get canControlPlayback => _availability.canControlPlayback;

  /// Whether the current source has a usable subtitle track loaded.
  bool get hasUsableSubtitleTrack => _availability.hasUsableSubtitleTrack;

  /// Reverse highlight is available NOW (readable position + loaded track).
  bool get canReverseHighlightNow => _availability.canReverseHighlightNow;

  /// Current-position time anchor creation is available NOW.
  bool get canCreateTimeAnchorNow => _availability.canCreateTimeAnchorNow;

  /// Full study readiness (runtime): readable position + loaded subtitle track.
  bool get isStudyReady => _availability.isStudyReady;

  /// Whether the adapter exposes any playback surface (embed or position
  /// readback). Providers with neither are link-only.
  bool get hasAnyPlaybackSurface => _availability.hasAnyPlaybackSurface;

  void _updateAvailability() {
    final hasUsable = _track != null &&
        _track!.reliability != TimedTextReliability.unavailable &&
        _track!.cues.isNotEmpty;
    _availability = VideoStudyAvailability(
      capability: adapter.capability,
      hasUsableSubtitleTrack: hasUsable,
    );
  }

  // ─── Sync ───

  int get activeCueIndex => _activeCueIndex;

  // ─── Annotations ───

  List<UIAnnotation> get annotations => List.unmodifiable(_annotations);

  // ─── Dock ───

  DockOrientation get dockOrientation => _dockOrientation;
  double get dockRatio => _dockRatio;
  bool get dockVisible => _dockVisible;
  bool get isSavingAnnotation => _isSavingAnnotation;

  bool get hasRuntimePlaybackSurface =>
      runtimePlayerAvailable && hasAnyPlaybackSurface;

  void setDockVisible(bool visible) {
    _dockVisible = visible;
    notifyListeners();
    saveSession();
  }

  void setDockOrientation(DockOrientation orientation) {
    _dockOrientation = orientation;
    notifyListeners();
    saveSession();
  }

  void setDockRatio(double ratio) {
    _dockRatio = ratio.clamp(0.20, 0.50);
    notifyListeners();
    saveSession();
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

      // Auto-fetch platform subtitles (YouTube timedtext) when the provider
      // supports it on this platform and no usable track is loaded yet. The
      // static capability declaration stays conservative; study readiness is
      // decided at runtime after this attempt.
      _maybeAutoFetchSubtitles(embedUrl);
    } catch (e) {
      _errorMessage = '加载失败：$e';
      notifyListeners();
    }
  }

  /// Whether platform-subtitle auto-fetch should run for the current setup.
  bool get _canAutoFetchSubtitles =>
      providerId == 'youtube' &&
      (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows) &&
      (_track?.cues.isEmpty != false);

  void _maybeAutoFetchSubtitles(String? embedUrl) {
    if (!_canAutoFetchSubtitles) {
      _subtitleFetchStatus = SubtitleAutoFetchStatus.skipped;
      return;
    }
    _subtitleFetchStatus = SubtitleAutoFetchStatus.fetching;
    notifyListeners();
    // Fire and forget — the UI observes subtitleFetchStatus.
    _fetchPlatformSubtitles(embedUrl);
  }

  Future<void> _fetchPlatformSubtitles(String? embedUrl) async {
    final videoRef = embedUrl ?? sourceId;
    final result = await _timedTextService.fetchForVideo(
      videoRef,
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
    );
    _availableCaptionTracks = result.availableTracks;
    _selectedCaptionTrack = result.selectedTrack;
    if (result.isSuccess && result.track != null) {
      _setTrack(result.track!);
      _subtitleFetchStatus = SubtitleAutoFetchStatus.loaded;
      _subtitleFetchMessage = '已自动获取平台字幕（${result.track!.language}）';
      _subtitleFailureKind = null;
    } else {
      _subtitleFetchStatus = SubtitleAutoFetchStatus.failed;
      _subtitleFetchMessage = result.error ?? '自动获取字幕失败';
      _subtitleFailureKind = result.failureKind;
      _needsSubtitle = true;
    }
    notifyListeners();
  }

  /// Loads a subtitle track from raw SRT/VTT content.
  void loadSubtitleFromText(
    String raw, {
    TimedTextSourceKind sourceKind = TimedTextSourceKind.userImport,
  }) {
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
    if (track.sourceKind == TimedTextSourceKind.platform &&
        !_needsSubtitle &&
        _subtitleFetchStatus != SubtitleAutoFetchStatus.loaded) {
      _subtitleFetchStatus = SubtitleAutoFetchStatus.loaded;
    }
    _updateAvailability();

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
    // Persist position for restart recovery (best-effort).
    saveSession();
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
    if (!canCreateTimeAnchorNow) return;
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

  /// Loads a user-selected platform CC track without changing source/card
  /// identity. SRT/VTT import remains available if this request fails.
  Future<void> selectPlatformSubtitleTrack(
    YouTubeCaptionTrack selected,
  ) async {
    if (providerId != 'youtube' ||
        _subtitleFetchStatus == SubtitleAutoFetchStatus.fetching) {
      return;
    }
    _subtitleFetchStatus = SubtitleAutoFetchStatus.fetching;
    _selectedCaptionTrack = selected;
    _subtitleFetchMessage = '正在加载 ${selected.label}…';
    notifyListeners();
    final result = await _timedTextService.fetchTrack(
      selected,
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      availableTracks: _availableCaptionTracks,
    );
    if (result.isSuccess && result.track != null) {
      _setTrack(result.track!);
      _subtitleFetchStatus = SubtitleAutoFetchStatus.loaded;
      _subtitleFetchMessage = '已切换到 ${selected.label}';
      _subtitleFailureKind = null;
    } else {
      _subtitleFetchStatus = SubtitleAutoFetchStatus.failed;
      _subtitleFetchMessage = result.error ?? '字幕轨加载失败';
      _subtitleFailureKind = result.failureKind;
      _needsSubtitle = _track == null || _track!.cues.isEmpty;
    }
    notifyListeners();
  }

  /// Opens a point-annotation draft at the player's readable current time.
  /// This path never depends on a subtitle cue being present.
  void beginPointAnnotationAtCurrent() {
    if (!canCreateTimeAnchorNow) return;
    _rangeSelectionStartMs = null;
    beginAnnotation(startMs: _positionMs, endMs: _positionMs);
  }

  /// Captures the first boundary of a subtitle-independent time range.
  void beginRangeSelectionAtCurrent() {
    if (!canCreateTimeAnchorNow) return;
    _rangeSelectionStartMs = _positionMs;
    notifyListeners();
  }

  /// Captures the second boundary and opens an annotation draft.
  void finishRangeSelectionAtCurrent() {
    final first = _rangeSelectionStartMs;
    if (!canCreateTimeAnchorNow || first == null) return;
    final second = _positionMs;
    _rangeSelectionStartMs = null;
    final start = first <= second ? first : second;
    final end = first <= second ? second : first;
    beginAnnotation(startMs: start, endMs: end);
  }

  void cancelRangeSelection() {
    if (_rangeSelectionStartMs == null) return;
    _rangeSelectionStartMs = null;
    notifyListeners();
  }

  /// Confirms and saves an annotation.
  Future<bool> confirmAnnotation({
    required String title,
    required String body,
    String? quote,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    if (_pendingAnnotationStartMs == null || _isSavingAnnotation) return false;

    final spec = _pendingAnnotationStartMs == _pendingAnnotationEndMs
        ? TimeRangeAnchorSpec.point(
            _pendingAnnotationStartMs!,
            cueId: _pendingAnnotationCueId,
          )
        : TimeRangeAnchorSpec.range(
            _pendingAnnotationStartMs!,
            _pendingAnnotationEndMs!,
            cueId: _pendingAnnotationCueId,
          );

    final request = AnnotationCreationRequest(
      spec: spec,
      title: title,
      body: body,
      quote: quote,
      createdBy: createdBy,
    );
    _isSavingAnnotation = true;
    _errorMessage = null;
    notifyListeners();
    late VideoAnnotationResult result;
    try {
      result = annotationStore == null
          ? _annotationService.createAnnotation(
              sourceId: sourceId,
              sourceVersionId: sourceVersionId,
              request: request,
            )
          : await annotationStore!.createAnnotation(
              sourceId: sourceId,
              sourceVersionId: sourceVersionId,
              request: request,
            );
    } catch (error) {
      _errorMessage = '标注保存失败：$error';
      _isSavingAnnotation = false;
      notifyListeners();
      return false;
    }

    _annotations.add(UIAnnotation(anchor: result.anchor, card: result.card));
    _anchorToCard[result.anchor.anchorId] = result.card.cardId;
    _pendingAnnotationCueId = null;
    _pendingAnnotationStartMs = null;
    _pendingAnnotationEndMs = null;
    _showSaveConfirmation = true;
    _isSavingAnnotation = false;
    notifyListeners();

    // Persist the session immediately so the annotation survives a restart.
    saveSession();

    // Auto-dismiss the confirmation after a short delay.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_showSaveConfirmation) {
        _showSaveConfirmation = false;
        notifyListeners();
      }
    });
    return true;
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
  int? get rangeSelectionStartMs => _rangeSelectionStartMs;
  bool get hasRangeSelectionStart => _rangeSelectionStartMs != null;

  /// Whether the annotation-saved confirmation should be shown.
  bool get showSaveConfirmation => _showSaveConfirmation;

  // ─── Session persistence ───

  /// Saves the current session via [sessionStore] (best-effort, never throws).
  ///
  /// Skipped when no store is configured (in-memory demo).
  Future<void> saveSession() async {
    final store = sessionStore;
    if (store == null) return;
    try {
      final session = _annotationService.saveSession(
        sourceId: sourceId,
        sourceVersionId: sourceVersionId,
        lastPositionMs: _positionMs,
        anchors: _annotations.map((a) => a.anchor).toList(),
        annotationCards: _annotations.map((a) => a.card).toList(),
        anchorToCard: _anchorToCard,
        dockOrientation: _dockOrientation.name,
        dockRatio: _dockRatio,
      );
      await store.save(session);
    } catch (_) {
      // Persistence is best-effort for the study workflow.
    }
  }

  /// Restores the session from [sessionStore] (if any), re-resolving anchors
  /// against [currentVersionId] when it differs from the saved version.
  Future<void> restoreSession({String? currentVersionId}) async {
    final store = sessionStore;
    if (store == null) return;
    try {
      final saved = await store.load();
      if (saved != null) {
        restoreFromSession(saved, currentVersionId: currentVersionId);
      }
      final persisted = await annotationStore?.listAnnotations(
        sourceId: sourceId,
        currentVersionId: currentVersionId ?? sourceVersionId,
        currentDurationMs: _durationMs > 0 ? _durationMs : null,
      );
      if (persisted != null) {
        _annotations
          ..clear()
          ..addAll(
            persisted.map(
              (result) =>
                  UIAnnotation(anchor: result.anchor, card: result.card),
            ),
          );
        _anchorToCard
          ..clear()
          ..addEntries(
            persisted.map(
              (result) => MapEntry(result.anchor.anchorId, result.card.cardId),
            ),
          );
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = '恢复失败：$e';
      notifyListeners();
    }
  }

  /// Restores from an in-memory [VideoAnnotationSession].
  void restoreFromSession(
    VideoAnnotationSession session, {
    String? currentVersionId,
  }) {
    var effective = session;
    if (currentVersionId != null &&
        currentVersionId != session.sourceVersionId) {
      effective = _annotationService.restoreSession(
        saved: session,
        currentVersionId: currentVersionId,
      );
    }

    // Legacy/demo sessions may carry cards. Production restore replaces this
    // list from UnifiedCardRepository immediately after restoring UI state.
    if (annotationStore == null) {
      _annotations.clear();
      _anchorToCard.clear();
      for (var i = 0; i < effective.anchors.length; i++) {
        final anchor = effective.anchors[i];
        final card = effective.annotationCards.length > i
            ? effective.annotationCards[i]
            : null;
        if (card != null) {
          _annotations.add(UIAnnotation(anchor: anchor, card: card));
          _anchorToCard[anchor.anchorId] = card.cardId;
        }
      }
    }

    _dockOrientation = effective.dockOrientation == 'bottom'
        ? DockOrientation.bottom
        : DockOrientation.right;
    _dockRatio = effective.dockRatio.clamp(0.20, 0.50);

    // Restore playback position
    if (canSeek && effective.lastPositionMs > 0) {
      // Fire-and-forget: seek settles as the player finishes loading.
      seekTo(effective.lastPositionMs);
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
    if (_ownsTimedTextService) {
      _timedTextService.dispose();
    }
    // Dispose the adapter if it exposes a dispose() method (FixturePlayerAdapter,
    // YouTubePlayerAdapter, and WebYouTubePlayerAdapter all do). Using dynamic
    // avoids importing the Web adapter (which depends on dart:js_interop and
    // is not available in the VM test environment).
    final a = adapter;
    if (a is FixturePlayerAdapter) {
      a.dispose();
    } else if (a is YouTubePlayerAdapter) {
      a.dispose();
    } else {
      // WebYouTubePlayerAdapter or any other adapter with a dispose method.
      try {
        (a as dynamic).dispose();
      } catch (_) {
        // Adapter has no dispose() — nothing to clean up.
      }
    }
    super.dispose();
  }
}
