/// Three-platform video provider capability matrix.
///
/// This file documents the compliant, publicly-available capabilities of
/// Xiaohongshu (小红书), Bilibili (哔哩哔哩), and YouTube for embedding,
/// playback control, subtitles, and time anchoring.
///
/// The matrix is derived from official API documentation and public player
/// behavior as of 2026-08. It is not a promise of indefinite availability —
/// platforms may change their APIs. When a capability is not confirmed via
/// official documentation, it is marked as [CapabilityVerdict.notConfirmed].
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
      name: 'Embeddable player (official)',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.partial,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame Player API is the official embedding method. '
          'Bilibili has an unofficial embed via player.bilibili.com but no '
          'documented public API for third-party control. Xiaohongshu does '
          'not offer an official web embed player.',
    ),
    CapabilityRow(
      name: 'Read current position',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.notConfirmed,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.getCurrentTime(). '
          'Bilibili embed player does not expose JS API for position. '
          'Xiaohongshu has no embeddable player API.',
    ),
    CapabilityRow(
      name: 'Read duration',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.notConfirmed,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.getDuration().',
    ),
    CapabilityRow(
      name: 'Seek to position',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.notConfirmed,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.seekTo(seconds, allowSeekAhead).',
    ),
    CapabilityRow(
      name: 'Play / pause control',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.notConfirmed,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube IFrame API: player.playVideo() / player.pauseVideo().',
    ),
    CapabilityRow(
      name: 'Platform-provided subtitles',
      xiaohongshu: CapabilityVerdict.notConfirmed,
      bilibili: CapabilityVerdict.partial,
      youtube: CapabilityVerdict.supported,
      evidence: 'YouTube provides timedtext API and caption tracks. '
          'Bilibili has AI subtitles on some videos via subtitle API, but '
          'not all videos have them. Xiaohongshu does not provide subtitle '
          'tracks for short videos.',
    ),
    CapabilityRow(
      name: 'User-imported SRT/VTT',
      xiaohongshu: CapabilityVerdict.supported,
      bilibili: CapabilityVerdict.supported,
      youtube: CapabilityVerdict.supported,
      evidence: 'User can import subtitle files for any platform — '
          'the player adapter overlays them without platform involvement.',
    ),
    CapabilityRow(
      name: 'Reverse highlight (playback → subtitle)',
      xiaohongshu: CapabilityVerdict.supported,
      bilibili: CapabilityVerdict.supported,
      youtube: CapabilityVerdict.supported,
      evidence: 'Reverse highlight is a local UI feature driven by '
          'PlayerSyncController; it does not require platform support, '
          'only a readable playback position.',
    ),
    CapabilityRow(
      name: 'Time anchor creation',
      xiaohongshu: CapabilityVerdict.supported,
      bilibili: CapabilityVerdict.supported,
      youtube: CapabilityVerdict.supported,
      evidence: 'Time anchors are local domain entities; they require a '
          'readable position but no platform API.',
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
  static PlayerCapability capabilityFor(String providerId) {
    switch (providerId) {
      case 'youtube':
        return const PlayerCapability(
          canSeek: true,
          canReadDuration: true,
          canReadPosition: true,
          hasTranscript: true,
          canEmbedPlayer: true,
          canReverseHighlight: true,
          canCreateTimeAnchor: true,
        );
      case 'bilibili':
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

  /// Gets the recommended initial provider for the playback study workflow.
  ///
  /// YouTube is the only platform that satisfies all hard requirements via
  /// official, public APIs. Bilibili and Xiaohongshu fall back to link-only
  /// mode (no embeddable player with controllable time axis).
  static String get recommendedProvider => 'youtube';

  /// Lists providers that are playback-study-capable.
  static List<String> get playbackStudyCapableProviders =>
      ['youtube', 'fixture'];

  /// Lists providers that support link-only mode.
  static List<String> get linkOnlyProviders => ['bilibili', 'xiaohongshu'];
}