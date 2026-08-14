/// TimedTextTrack and PlayerAdapter contracts.
///
/// `TimedTextTrack` models subtitle/caption tracks with reliability and
/// rights status. `PlayerAdapter` is the capability interface that all video
/// providers must implement — W4 will implement concrete adapters for
/// Xiaohongshu, Bilibili, and YouTube.
library;

/// The source kind of a timed text track.
enum TimedTextSourceKind {
  platform,
  creator,
  userImport,
  asr;

  static TimedTextSourceKind fromString(String? raw) {
    switch (raw) {
      case 'platform':
        return TimedTextSourceKind.platform;
      case 'creator':
        return TimedTextSourceKind.creator;
      case 'user_import':
        return TimedTextSourceKind.userImport;
      case 'asr':
        return TimedTextSourceKind.asr;
      default:
        return TimedTextSourceKind.platform;
    }
  }

  String get name {
    switch (this) {
      case TimedTextSourceKind.userImport:
        return 'user_import';
      default:
        return toString().split('.').last;
    }
  }
}

/// The reliability level of a timed text track.
enum TimedTextReliability {
  reliable,
  partial,
  unavailable;

  static TimedTextReliability fromString(String? raw) {
    switch (raw) {
      case 'reliable':
        return TimedTextReliability.reliable;
      case 'partial':
        return TimedTextReliability.partial;
      case 'unavailable':
        return TimedTextReliability.unavailable;
      default:
        return TimedTextReliability.reliable;
    }
  }
}

/// A single cue (subtitle segment) in a timed text track.
class TimedTextCue {
  final String cueId;
  final int startMs;
  final int endMs;
  final String text;
  final String? speaker;
  final double? confidence;

  const TimedTextCue({
    required this.cueId,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.speaker,
    this.confidence,
  });

  factory TimedTextCue.fromJson(Map<String, dynamic> json) {
    return TimedTextCue(
      cueId: json['cue_id'] as String,
      startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
      endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      speaker: json['speaker'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'cue_id': cueId,
        'start_ms': startMs,
        'end_ms': endMs,
        'text': text,
        if (speaker != null) 'speaker': speaker,
        if (confidence != null) 'confidence': confidence,
      };
}

/// A timed text track (subtitle/caption track) for a video source.
///
/// Contains track metadata, cue list, reliability, and rights status. When no
/// reliable track is available, the UI must show "需要字幕" rather than
/// fabricating one.
class TimedTextTrack {
  final String trackId;
  final String sourceId;
  final String? sourceVersionId;
  final TimedTextSourceKind sourceKind;
  final String language;
  final String? format;
  final String? segmentsRef;
  final int? trackVersion;
  final DateTime? generatedAt;
  final TimedTextReliability reliability;
  final String? rightsPolicy;
  final List<TimedTextCue> cues;

  const TimedTextTrack({
    required this.trackId,
    required this.sourceId,
    this.sourceVersionId,
    this.sourceKind = TimedTextSourceKind.platform,
    this.language = 'zh',
    this.format,
    this.segmentsRef,
    this.trackVersion,
    this.generatedAt,
    this.reliability = TimedTextReliability.reliable,
    this.rightsPolicy,
    this.cues = const [],
  });

  factory TimedTextTrack.fromJson(Map<String, dynamic> json) {
    return TimedTextTrack(
      trackId: json['track_id'] as String,
      sourceId: json['source_id'] as String,
      sourceVersionId: json['source_version_id'] as String?,
      sourceKind:
          TimedTextSourceKind.fromString(json['source_kind'] as String?),
      language: json['language'] as String? ?? 'zh',
      format: json['format'] as String?,
      segmentsRef: json['segments_ref'] as String?,
      trackVersion: (json['track_version'] as num?)?.toInt(),
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'] as String)
          : null,
      reliability:
          TimedTextReliability.fromString(json['reliability'] as String?),
      rightsPolicy: json['rights_policy'] as String?,
      cues: (json['cues'] as List<dynamic>?)
          ?.map((c) => TimedTextCue.fromJson(c as Map<String, dynamic>))
          .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'track_id': trackId,
        'source_id': sourceId,
        if (sourceVersionId != null) 'source_version_id': sourceVersionId,
        'source_kind': sourceKind.name,
        'language': language,
        if (format != null) 'format': format,
        if (segmentsRef != null) 'segments_ref': segmentsRef,
        if (trackVersion != null) 'track_version': trackVersion,
        if (generatedAt != null)
          'generated_at': generatedAt!.toUtc().toIso8601String(),
        'reliability': reliability.name,
        if (rightsPolicy != null) 'rights_policy': rightsPolicy,
        if (cues.isNotEmpty) 'cues': cues.map((c) => c.toJson()).toList(),
      };
}

/// The capability declaration of a video player adapter.
///
/// Different providers (Xiaohongshu, Bilibili, YouTube) have different
/// capabilities. The UI reads this declaration — it never guesses.
class PlayerCapability {
  final bool canSeek;
  final bool canReadDuration;
  final bool canReadPosition;
  final bool hasTranscript;
  final bool canEmbedPlayer;
  final bool canReverseHighlight;
  final bool canCreateTimeAnchor;

  const PlayerCapability({
    this.canSeek = false,
    this.canReadDuration = false,
    this.canReadPosition = false,
    this.hasTranscript = false,
    this.canEmbedPlayer = false,
    this.canReverseHighlight = false,
    this.canCreateTimeAnchor = false,
  });

  /// Only when all research-playback capabilities are present does the
  /// provider qualify as "formally supported" (研读播放级).
  bool get isPlaybackStudyCapable =>
      canSeek &&
      canReadDuration &&
      canReadPosition &&
      hasTranscript &&
      canReverseHighlight &&
      canCreateTimeAnchor;
}

/// A time position event from the player.
class PlayerTimeEvent {
  final int positionMs;
  final int? durationMs;
  final DateTime at;

  const PlayerTimeEvent({
    required this.positionMs,
    this.durationMs,
    required this.at,
  });
}

/// The abstract capability interface for video player adapters.
///
/// W4 will implement concrete adapters for each provider. Engine-private IDs
/// only exist in the adapter's internal mapping — they never leak into the
/// product domain.
///
/// This is an abstract class (not an interface) to allow shared adapter
/// utilities in the future. W4 implementations override the methods.
abstract class PlayerAdapter {
  /// The provider identifier (e.g. 'bilibili', 'youtube', 'xiaohongshu').
  String get providerId;

  /// The declared capabilities of this adapter.
  PlayerCapability get capability;

  /// Loads a video source by its [sourceId] and optional [embedUrl].
  ///
  /// Returns a [Future] that completes when the player is ready.
  Future<void> load(String sourceId, {String? embedUrl});

  /// Starts playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Returns the current playback position in milliseconds.
  Future<int> currentPositionMs();

  /// Returns the total duration in milliseconds, or null if unavailable.
  Future<int?> durationMs();

  /// Seeks to [positionMs] milliseconds.
  Future<void> seekTo(int positionMs);

  /// Stream of time position events during playback.
  ///
  /// W4 will implement this with a real stream. The base contract here
  /// returns an empty stream so tests can run without a real player.
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();
}