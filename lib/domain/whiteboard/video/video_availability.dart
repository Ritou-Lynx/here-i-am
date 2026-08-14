/// W4 runtime availability model.
///
/// Three distinct layers, previously conflated:
///
/// 1. **Static adapter capability** ([PlayerCapability], from
///    [ProviderCapabilityMatrix.capabilityFor]) — what the adapter's
///    implementation can do (seek, read position, embed, etc.).
/// 2. **Provider platform facts** ([ProviderCapabilityMatrix.rows]) — what
///    each platform may offer (embed, controllable interface, subtitles).
/// 3. **Runtime availability** (this file) — what is actually true for the
///    CURRENT source right now: whether a readable position exists AND a
///    usable subtitle track is loaded.
///
/// Reverse highlight and current-time anchors require a readable position;
/// full study readiness additionally requires a loaded subtitle track. No
/// static capability may claim these just because a platform *might* have
/// subtitles.
library;

import '../player_adapter.dart';
import 'provider_capability_matrix.dart';

/// Runtime study availability for a video source.
///
/// Combines the adapter's static capability with the actual subtitle-track
/// state of the current source.
class VideoStudyAvailability {
  /// Static capabilities declared by the adapter in use.
  final PlayerCapability capability;

  /// Whether the current source actually has a usable subtitle track
  /// (reliable cues loaded — platform-provided or user-imported).
  final bool hasUsableSubtitleTrack;

  const VideoStudyAvailability({
    required this.capability,
    this.hasUsableSubtitleTrack = false,
  });

  /// Convenience constructor from a matrix provider id + runtime track state.
  factory VideoStudyAvailability.fromProvider(
    String providerId, {
    bool hasUsableSubtitleTrack = false,
  }) {
    return VideoStudyAvailability(
      capability: ProviderCapabilityMatrix.capabilityFor(providerId),
      hasUsableSubtitleTrack: hasUsableSubtitleTrack,
    );
  }

  /// Whether a readable playback position exists at runtime.
  bool get hasReadablePosition => capability.canReadPosition;

  /// Whether playback can be controlled (seek + position + duration).
  bool get canControlPlayback =>
      capability.canSeek &&
      capability.canReadPosition &&
      capability.canReadDuration;

  /// Whether reverse highlighting is available NOW.
  ///
  /// Requires a readable position AND a loaded subtitle track. Without a
  /// readable position (Bilibili / Xiaohongshu) it is never available.
  bool get canReverseHighlightNow =>
      hasReadablePosition && hasUsableSubtitleTrack;

  /// Whether creating a current-position time anchor is available NOW.
  ///
  /// Requires a readable position. (An anchor for a specific imported cue is
  /// still gated on the position being readable.)
  bool get canCreateTimeAnchorNow => hasReadablePosition;

  /// Full study readiness: readable position + loaded subtitle track.
  ///
  /// This is the runtime replacement for statically claiming
  /// `isPlaybackStudyCapable`. A provider like YouTube with no loaded
  /// subtitle track is NOT study-ready until a track is imported or loaded.
  bool get isStudyReady =>
      hasReadablePosition && hasUsableSubtitleTrack;

  /// Whether the adapter exposes any playback surface at all
  /// (embed or position readback). Providers with neither are link-only.
  bool get hasAnyPlaybackSurface =>
      capability.canEmbedPlayer || capability.canReadPosition;
}

/// Consistency validation for a static capability declaration.
///
/// Reverse highlight and current-time anchors can only exist when the
/// position is readable. This prevents the matrix/adapters from claiming a
/// capability they cannot actually fulfill.
class CapabilityConsistency {
  CapabilityConsistency._();

  /// Returns null when [capability] is self-consistent, otherwise an error
  /// message describing the contradiction.
  static String? validate(PlayerCapability capability) {
    if (capability.canReverseHighlight && !capability.canReadPosition) {
      return 'canReverseHighlight requires canReadPosition';
    }
    if (capability.canCreateTimeAnchor && !capability.canReadPosition) {
      return 'canCreateTimeAnchor requires canReadPosition';
    }
    return null;
  }

  /// Throws if any production provider's static capability is inconsistent.
  static void validateProduction() {
    for (final id in ProviderCapabilityMatrix.productionProviders) {
      final error = validate(ProviderCapabilityMatrix.capabilityFor(id));
      if (error != null) {
        throw StateError('Provider $id: $error');
      }
    }
  }
}
