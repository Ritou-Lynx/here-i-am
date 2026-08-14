/// Three-platform video provider capability matrix.
///
/// This file documents the compliant, publicly-available capabilities of
/// Xiaohongshu (小红书), Bilibili (哔哩哔哩), and YouTube for embedding,
/// playback control, subtitles, and time anchoring.
///
/// The matrix distinguishes several independent dimensions that were
/// previously conflated:
///
/// 1. **Embeddability** — can a player be embedded at all (even if not
///    controllable)? Bilibili CAN be embedded via `player.bilibili.com`
///    external links; that is different from having controllable playback.
/// 2. **Controllable playback interface** — is there a stable, public
///    third-party interface to read position / duration and seek?
/// 3. **Readable position / duration** — the runtime capability that reverse
///    highlight and current-time anchors actually depend on.
/// 4. **Platform-provided subtitles** — whether the platform *may* expose
///    subtitles (not whether the current source has loaded a usable track).
/// 5. **User-imported SRT/VTT** — a local capability independent of the
///    platform.
/// 6. **Current source has a usable subtitle track** — a runtime state that
///    cannot be statically claimed; it is evaluated by
///    [VideoStudyAvailability].
/// 7. **Full study readiness** — derived from readable position + a loaded
///    subtitle track. Never statically "supported" just because a platform
///    *might* have subtitles.
///
/// **Compliance boundary**: None of these adapters bypass DRM, login walls,
/// payment restrictions, or platform-internal access controls. The adapters
/// only use officially supported embedding and public subtitle endpoints.
library;

import '../player_adapter.dart';

/// The verdict on a specific capability for a specific platform.
enum CapabilityVerdict {
  /// Officially documented and available.
  supported,

  /// Partially available — works in some cases but not all.
  partial,

  /// Not available or not confirmed via official channels.
  notConfirmed,

  /// Confirmed unavailable.
  unsupported,
}

/// A single row in the capability matrix.
class CapabilityRow {
  final String name;
  final CapabilityVerdict xiaohongshu;
  final CapabilityVerdict bilibili;
  final CapabilityVerdict youtube;
  final String? evidence;

  const CapabilityRow({
    required this.name,
    required this.xiaohongshu,
    required this.bilibili,
    required this.youtube,
    this.evidence,
  });
}

/// The full three-platform capability matrix.
class ProviderCapabilityMatrix {
  ProviderCapabilityMatrix._();

  /// All capability rows.
  static const rows = [
    CapabilityRow(
      name: 'Embeddable player',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.partial,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame Player API is the official embedding method. '
          'Bilibili has an external-link embed (player.bilibili.com/player.html) '
          'but it is not an official, stable, documented third-party embed API. '
          'Xiaohongshu does not offer an official web embed player.',
    ),
    CapabilityRow(
      name: 'Controllable playback interface (public, stable)',
      xiaohongshu: CapabilityVerdict.unsupported,
      bilibili: CapabilityVerdict.unsupported,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API exposes a stable public control API '
          '(playVideo / pauseVideo / seekTo / getCurrentTime / getDuration). '
          'Bilibili\'s embeddable player does NOT expose a stable public '
          'third-party control API suitable for this product — embeddability '
          'and controllability are separate facts. Xiaohongshu has no '
          'embeddable player at all.',
    ),
    CapabilityRow(
      name: 'Read current position + duration',
      xiaohongshu: CapabilityVerdict.unsupported,
      bilibili: CapabilityVerdict.unsupported,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.getCurrentTime() / getDuration(). '
          'Without a controllable interface there is no reliable position or '
          'duration readback on Bilibili / Xiaohongshu.',
    ),
    CapabilityRow(
      name: 'Seek to position',
      xiaohongshu: CapabilityVerdict.unsupported,
      bilibili: CapabilityVerdict.unsupported,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.seekTo(seconds, allowSeekAhead).',
    ),
    CapabilityRow(
      name: 'Play / pause control',
      xiaohongshu: CapabilityVerdict.unsupported,
      bilibili: CapabilityVerdict.unsupported,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.playVideo() / player.pauseVideo().',
    ),
    CapabilityRow(
      name: 'Platform may provide subtitles',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.partial,
      youtube: CapabilityVerdict.supported,
      evidence: 'This is about whether the platform CAN provide subtitles, '
          'NOT whether the current source has loaded one. YouTube provides '
          'timedtext / caption tracks. Bilibili has AI subtitles on SOME '
          'videos via its subtitle API. Xiaohongshu does not provide subtitle '
          'tracks for short videos. Loading is a runtime concern — see '
          'VideoStudyAvailability.',
    ),
    CapabilityRow(
      name: 'User-imported SRT/VTT',
      xiaohongshu: CapabilityVerdict.supported,
      bilibili: CapabilityVerdict.supported,
      youtube: CapabilityVerdict.supported,
      evidence: 'User can import subtitle files for any platform — the local '
          'parser overlays them without platform involvement. This is a LOCAL '
          'capability and does not imply the platform provides subtitles.',
    ),
    CapabilityRow(
      name: 'Current source has a usable subtitle track',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.notConfirmed,
      youtube: CapabilityVerdict.notConfirmed,
      evidence: 'A RUNTIME state, never a static capability. It becomes true '
          'only after a reliable track is loaded for the current source '
          '(platform-provided or user-imported SRT/VTT). Until then the UI '
          'shows "需要字幕".',
    ),
    CapabilityRow(
      name: 'Reverse highlight (playback → subtitle)',
      xiaohongshu: CapabilityVerdict.unsupported,
      bilibili: CapabilityVerdict.unsupported,
      youtube: CapabilityVerdict.partial,
      evidence: 'Reverse highlight is a local UI feature but REQUIRES a '
          'readable playback position AND a loaded subtitle track. Bilibili / '
          'Xiaohongshu cannot read position, so reverse highlight is NOT '
          'available there. YouTube can read position but still needs a '
          'loaded subtitle track at runtime — hence partial, not supported.',
    ),
    CapabilityRow(
      name: 'Time anchor creation (current position)',
      xiaohongshu: CapabilityVerdict.unsupported,
      bilibili: CapabilityVerdict.unsupported,
      youtube: CapabilityVerdict.partial,
      evidence: 'Creating an anchor at the CURRENT playback position requires '
          'a readable position. Bilibili / Xiaohongshu cannot, so anchors are '
          'NOT available there. YouTube can, subject to a readable position '
          'at runtime — partial.',
    ),
    CapabilityRow(
      name: 'Compliant playback (no DRM bypass)',
      xiaohongshu: CapabilityVerdict.supported,
      bilibili: CapabilityVerdict.supported,
      youtube: CapabilityVerdict.supported,
      evidence: 'All adapters use only official embedding or link-only mode. '
          'No download, no DRM removal, no watermark removal.',
    ),
  ];

  /// Gets the [PlayerCapability] for a given provider.
  ///
  /// This is the STATIC adapter capability. It deliberately does NOT set
  /// `hasTranscript` for YouTube: platform-subtitle auto-fetch is not yet
  /// implemented, so the static declaration must not let YouTube pass the
  /// full study gate on its own. Study readiness is evaluated at runtime by
  /// [VideoStudyAvailability] (adapter capability × loaded subtitle track).
  static PlayerCapability capabilityFor(String providerId) {
    switch (providerId) {
      case 'youtube':
        // canEmbedPlayer/canSeek/canReadPosition/canReadDuration are real
        // (official IFrame API). hasTranscript stays false until platform
        // subtitle auto-fetch is implemented; reverse highlight and
        // current-time anchors depend on a loaded subtitle track at runtime.
        return const PlayerCapability(
          canSeek: true,
          canReadDuration: true,
          canReadPosition: true,
          hasTranscript: false,
          canEmbedPlayer: true,
          canReverseHighlight: false,
          canCreateTimeAnchor: false,
        );
      case 'bilibili':
        // Embeddable via external link but NO stable public control
        // interface — position/duration/seek are not readable.
        return const PlayerCapability(
          canSeek: false,
          canReadDuration: false,
          canReadPosition: false,
          hasTranscript: false,
          canEmbedPlayer: true,
          canReverseHighlight: false,
          canCreateTimeAnchor: false,
        );
      case 'xiaohongshu':
        // No official embeddable player; link-only mode.
        return const PlayerCapability(
          canSeek: false,
          canReadDuration: false,
          canReadPosition: false,
          hasTranscript: false,
          canEmbedPlayer: false,
          canReverseHighlight: false,
          canCreateTimeAnchor: false,
        );
      case 'fixture':
        // Test / demo provider — NOT a production platform. It declares full
        // capabilities so the fixture closed loop is testable, but it must
        // never appear in the production provider list.
        return const PlayerCapability(
          canSeek: true,
          canReadDuration: true,
          canReadPosition: true,
          hasTranscript: true,
          canEmbedPlayer: true,
          canReverseHighlight: true,
          canCreateTimeAnchor: true,
        );
      default:
        return const PlayerCapability();
    }
  }

  /// Production platforms only (fixture excluded).
  static const List<String> productionProviders = [
    'youtube',
    'bilibili',
    'xiaohongshu',
  ];

  /// Test / demo providers only — never offered to the user.
  static const List<String> testProviders = ['fixture'];

  /// Gets the recommended initial provider for the playback study workflow.
  ///
  /// YouTube is the only production platform with a stable public control
  /// interface. Bilibili and Xiaohongshu fall back to link-only mode (no
  /// controllable playback).
  static String get recommendedProvider => 'youtube';

  /// Lists production providers that support link-only mode.
  static List<String> get linkOnlyProviders => ['bilibili', 'xiaohongshu'];
}
