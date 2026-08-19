/// Product consumption route for a persisted Source.
///
/// `/sources/:sourceId` resolves Source + current SourceVersion + Card only
/// through UnifiedCardRepository. Video sources enter the W4 study surface;
/// ordinary sources render their real body, metadata, and version state.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/repository_video_annotation_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/player_adapter.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/video/platform_player_adapters.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory.dart';
import 'package:memex/domain/whiteboard/video/youtube_player_adapter.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/whiteboard/video/session_store.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';

class SourceStudyScreen extends StatefulWidget {
  const SourceStudyScreen({super.key, required this.sourceId, this.repository});

  final String sourceId;
  final UnifiedCardRepository? repository;

  @override
  State<SourceStudyScreen> createState() => _SourceStudyScreenState();
}

class _SourceStudyScreenState extends State<SourceStudyScreen> {
  late final Future<_SourceStudyData> _data = _load();

  Future<_SourceStudyData> _load() async {
    final repository = widget.repository ??
        await WhiteboardDataBootstrap.productionRepository();
    final source = await repository.getSource(widget.sourceId);
    if (source == null) return _SourceStudyData(repository: repository);
    final versions = await repository.listSourceVersions(widget.sourceId);
    SourceVersion? currentVersion;
    for (final version in versions) {
      if (version.versionId == source.currentVersionId) {
        currentVersion = version;
        break;
      }
    }
    final card = await repository.getCardForSource(widget.sourceId);
    final object = currentVersion == null
        ? null
        : await repository.getSourceObject(currentVersion);
    return _SourceStudyData(
      repository: repository,
      source: source,
      currentVersion: currentVersion,
      versions: versions,
      card: card,
      object: object,
    );
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.cardLibrary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SourceStudyData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SourceFailure(
            title: '来源加载失败',
            detail: snapshot.error.toString(),
            onBack: _back,
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final source = data.source;
        if (source == null) {
          return _SourceFailure(
            title: '找不到这个来源',
            detail: widget.sourceId,
            onBack: _back,
          );
        }
        if (data.currentVersion == null) {
          return _SourceFailure(
            title: '来源版本不可用',
            detail: source.currentVersionId == null
                ? '该来源还没有当前版本。'
                : '当前版本 ${source.currentVersionId} 不在版本链中。',
            onBack: _back,
          );
        }
        if (source.mediaType == SourceMediaType.video) {
          return _buildVideo(data);
        }
        return _OrdinarySourceView(data: data, onBack: _back);
      },
    );
  }

  Widget _buildVideo(_SourceStudyData data) {
    final source = data.source!;
    final provider = _providerId(source);
    final adapter = _adapterFor(provider);
    return VideoStudyScreen(
      adapter: adapter,
      sourceId: source.sourceId,
      sourceVersionId: data.currentVersion!.versionId,
      providerId: provider,
      embedUrl: _embedUrl(source, provider),
      runtimePlayerAvailable: _runtimePlayerAvailable(adapter),
      sessionStore: createVideoSessionStore(sourceId: source.sourceId),
      annotationStore: RepositoryVideoAnnotationStore(data.repository),
      onBack: _back,
    );
  }

  static String _providerId(SourceContent source) {
    final raw =
        (source.provider ?? source.metadata['provider'] as String? ?? '')
            .trim()
            .toLowerCase();
    if (raw.contains('youtube') || raw == 'youtu.be') return 'youtube';
    if (raw.contains('bilibili') || raw == 'b23.tv') return 'bilibili';
    if (raw.contains('xiaohongshu') || raw == 'xhs') return 'xiaohongshu';
    return raw.isEmpty ? 'unknown' : raw;
  }

  static String? _embedUrl(SourceContent source, String provider) {
    final explicit = source.metadata['embed_url'] as String?;
    if (explicit?.trim().isNotEmpty == true) return explicit!.trim();
    final canonical = source.metadata['canonical_url'] as String?;
    if (canonical?.trim().isNotEmpty == true) return canonical!.trim();
    final id = source.canonicalId?.trim();
    if (id == null || id.isEmpty) return null;
    return switch (provider) {
      'youtube' => 'https://www.youtube.com/watch?v=$id',
      'bilibili' => 'https://www.bilibili.com/video/$id',
      _ => id,
    };
  }

  static PlayerAdapter _adapterFor(String provider) => switch (provider) {
        'youtube' => createYouTubeAdapter(),
        'bilibili' => BilibiliPlayerAdapter(),
        'xiaohongshu' => XiaohongshuPlayerAdapter(),
        _ => _UnsupportedVideoPlayerAdapter(provider),
      };

  static bool _runtimePlayerAvailable(PlayerAdapter adapter) {
    if (kIsWeb) return adapter.providerId == 'youtube';
    if (adapter is YouTubePlayerAdapter) return adapter.isAvailable;
    return false;
  }
}

class _SourceStudyData {
  const _SourceStudyData({
    required this.repository,
    this.source,
    this.currentVersion,
    this.versions = const [],
    this.card,
    this.object,
  });

  final UnifiedCardRepository repository;
  final SourceContent? source;
  final SourceVersion? currentVersion;
  final List<SourceVersion> versions;
  final CardContract? card;
  final SourceObjectRecord? object;
}

class _OrdinarySourceView extends StatelessWidget {
  const _OrdinarySourceView({required this.data, required this.onBack});

  final _SourceStudyData data;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final source = data.source!;
    final object = data.object;
    final body = object?.bodyText?.trim().isNotEmpty == true
        ? object!.bodyText!.trim()
        : (data.card?.body.trim().isNotEmpty == true
            ? data.card!.body.trim()
            : (source.metadata['description'] as String? ?? '').trim());
    final tokens = Theme.of(context).extension<SpringRainUiTokens>() ??
        SpringRainUiTokens.daylight;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        leading: IconButton(
          tooltip: '返回卡片库',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('来源研读'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.title.isEmpty ? '未命名来源' : source.title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 24,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _sourceLine(source),
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _VersionStatus(
                  version: data.currentVersion!,
                  versionCount: data.versions.length,
                  objectState: object?.state,
                ),
                const SizedBox(height: 24),
                Text(
                  body.isEmpty ? '这个来源没有可显示的正文。' : body,
                  style: TextStyle(
                    color:
                        body.isEmpty ? tokens.textTertiary : tokens.textPrimary,
                    fontSize: 14,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 28),
                _MetadataView(
                  metadata: {...source.metadata, ...?object?.metadata},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _sourceLine(SourceContent source) => [
        source.metadata['site_name'],
        source.metadata['author'],
        source.provider,
        source.metadata['canonical_url'],
      ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
}

class _VersionStatus extends StatelessWidget {
  const _VersionStatus({
    required this.version,
    required this.versionCount,
    required this.objectState,
  });

  final SourceVersion version;
  final int versionCount;
  final SourceObjectState? objectState;

  @override
  Widget build(BuildContext context) {
    final state = switch (objectState) {
      SourceObjectState.available => '正文对象可用',
      SourceObjectState.missing => '正文对象缺失，已使用卡片投影',
      SourceObjectState.corrupt => '正文对象损坏，已使用卡片投影',
      null => '没有正文对象',
    };
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        Text('当前版本 ${version.versionId}', style: const TextStyle(fontSize: 11)),
        Text('版本链 $versionCount', style: const TextStyle(fontSize: 11)),
        Text(state, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _MetadataView extends StatelessWidget {
  const _MetadataView({required this.metadata});

  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final entries = metadata.entries
        .where((entry) => entry.value != null && entry.key != 'body_text')
        .take(12)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '来源元数据',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${entry.key}: ${entry.value}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _SourceFailure extends StatelessWidget {
  const _SourceFailure({
    required this.title,
    required this.detail,
    required this.onBack,
  });
  final String title;
  final String detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, size: 40),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(detail, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onBack, child: const Text('返回卡片库')),
              ],
            ),
          ),
        ),
      );
}

class _UnsupportedVideoPlayerAdapter implements PlayerAdapter {
  _UnsupportedVideoPlayerAdapter(this.providerId);
  @override
  final String providerId;
  @override
  PlayerCapability get capability => const PlayerCapability();
  @override
  Stream<PlayerTimeEvent> get timeEvents => const Stream.empty();
  @override
  Future<int> currentPositionMs() async => 0;
  @override
  Future<int?> durationMs() async => null;
  @override
  Future<void> load(String sourceId, {String? embedUrl}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> seekTo(int positionMs) async {}
}
