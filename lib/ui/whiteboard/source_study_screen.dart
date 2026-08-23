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
import 'package:memex/domain/whiteboard/video/windows_bilibili_player_adapter.dart';
import 'package:memex/domain/whiteboard/video/windows_youtube_player_adapter.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory.dart';
import 'package:memex/domain/whiteboard/video/youtube_player_adapter.dart';
import 'package:memex/domain/whiteboard/video/youtube_timedtext_service.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import 'package:memex/ui/whiteboard/video/session_store.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';
import 'package:memex/ui/whiteboard/widgets/card_tag_field.dart';

class SourceStudyScreen extends StatefulWidget {
  const SourceStudyScreen({
    super.key,
    required this.sourceId,
    this.repository,
    this.adapterFactory,
    this.initialTrack,
    this.timedTextService,
  });

  final String sourceId;
  final UnifiedCardRepository? repository;
  final PlayerAdapter Function(String provider)? adapterFactory;
  final TimedTextTrack? initialTrack;
  final YouTubeTimedTextService? timedTextService;

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
    final tagSuggestions = await repository.listDistinctTags();
    final object = currentVersion == null
        ? null
        : await repository.getSourceObject(currentVersion);
    return _SourceStudyData(
      repository: repository,
      source: source,
      currentVersion: currentVersion,
      versions: versions,
      card: card,
      tagSuggestions: tagSuggestions,
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
        final tokens = DesktopWorkspaceTokens.of(context);
        if (snapshot.hasError) {
          return _SourceFailure(
            title: '来源加载失败',
            detail: snapshot.error.toString(),
            onBack: _back,
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            backgroundColor: tokens.canvas,
            body: Center(
              child: CircularProgressIndicator(
                color: tokens.action,
                strokeWidth: 2,
              ),
            ),
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
    final adapter =
        widget.adapterFactory?.call(provider) ?? _adapterFor(provider);
    final studyScreen = VideoStudyScreen(
      adapter: adapter,
      sourceId: source.sourceId,
      sourceVersionId: data.currentVersion!.versionId,
      providerId: provider,
      embedUrl: _embedUrl(source, provider),
      runtimePlayerAvailable: _runtimePlayerAvailable(adapter),
      initialTrack: widget.initialTrack,
      timedTextService: widget.timedTextService,
      sessionStore: createVideoSessionStore(sourceId: source.sourceId),
      annotationStore: RepositoryVideoAnnotationStore(data.repository),
      onBack: _back,
      onEditTags: data.card == null
          ? null
          : () => _openVideoTags(
                repository: data.repository,
                card: data.card!,
                suggestions: data.tagSuggestions,
              ),
    );
    return studyScreen;
  }

  Future<void> _openVideoTags({
    required UnifiedCardRepository repository,
    required CardContract card,
    required List<String> suggestions,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('视频卡标签')),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SourceTagEditor(
                  repository: repository,
                  card: card,
                  suggestions: suggestions,
                ),
              ],
            ),
          ),
        ),
      ),
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
        'bilibili' => defaultTargetPlatform == TargetPlatform.windows && !kIsWeb
            ? WindowsBilibiliPlayerAdapter()
            : BilibiliPlayerAdapter(),
        'xiaohongshu' => XiaohongshuPlayerAdapter(),
        _ => _UnsupportedVideoPlayerAdapter(provider),
      };

  static bool _runtimePlayerAvailable(PlayerAdapter adapter) {
    if (kIsWeb) return adapter.providerId == 'youtube';
    if (adapter is WindowsYouTubePlayerAdapter) return adapter.isAvailable;
    if (adapter is WindowsBilibiliPlayerAdapter) return adapter.isAvailable;
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
    this.tagSuggestions = const [],
    this.object,
  });

  final UnifiedCardRepository repository;
  final SourceContent? source;
  final SourceVersion? currentVersion;
  final List<SourceVersion> versions;
  final CardContract? card;
  final List<String> tagSuggestions;
  final SourceObjectRecord? object;
}

class _OrdinarySourceView extends StatelessWidget {
  const _OrdinarySourceView({required this.data, required this.onBack});

  static const double _readingColumnMinWidth = 680;
  static const double _readingColumnMaxWidth = 760;

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
    final tokens = DesktopWorkspaceTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = (constraints.maxWidth - 64)
                .clamp(0.0, _readingColumnMaxWidth)
                .toDouble();
            final readingWidth =
                constraints.maxWidth >= _readingColumnMinWidth + 64
                    ? availableWidth
                        .clamp(_readingColumnMinWidth, _readingColumnMaxWidth)
                        .toDouble()
                    : availableWidth;
            final sourceLine = _sourceLine(source);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 48),
              child: Center(
                child: SizedBox(
                  key: const ValueKey('source_reading_column'),
                  width: readingWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('source_back_action'),
                        onPressed: onBack,
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        label: const Text('卡片库'),
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.textMuted,
                          minimumSize: const Size(36, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: whiteboardUiTextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '来源研读',
                        style: whiteboardUiTextStyle(
                          color: tokens.textFaint,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        source.title.isEmpty ? '未命名来源' : source.title,
                        style: whiteboardUiTextStyle(
                          color: tokens.textPrimary,
                          fontSize: 24,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sourceLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          sourceLine,
                          style: whiteboardUiTextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (data.card != null) ...[
                        const SizedBox(height: 18),
                        _SourceTagEditor(
                          repository: data.repository,
                          card: data.card!,
                          suggestions: data.tagSuggestions,
                        ),
                      ],
                      const SizedBox(height: 24),
                      SelectableText(
                        body.isEmpty ? '这个来源没有可显示的正文。' : body,
                        style: richTextBodyTextStyle(
                          color: body.isEmpty
                              ? tokens.textFaint
                              : tokens.textPrimary,
                          fontSize: 14,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _SourceDetails(
                        version: data.currentVersion!,
                        versionCount: data.versions.length,
                        objectState: object?.state,
                        metadata: {...source.metadata, ...?object?.metadata},
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _sourceLine(SourceContent source) => [
        source.metadata['site_name'],
        source.metadata['author'],
        source.provider,
      ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
}

class _SourceTagEditor extends StatefulWidget {
  const _SourceTagEditor({
    required this.repository,
    required this.card,
    required this.suggestions,
  });

  final UnifiedCardRepository repository;
  final CardContract card;
  final List<String> suggestions;

  @override
  State<_SourceTagEditor> createState() => _SourceTagEditorState();
}

class _SourceTagEditorState extends State<_SourceTagEditor> {
  late List<String> _tags = List.of(widget.card.tags);
  late List<String> _suggestions = List.of(widget.suggestions);
  bool _saving = false;
  String? _message;
  bool _failed = false;

  Future<void> _save(List<String> tags) async {
    if (_saving) return;
    final previous = List<String>.of(_tags);
    setState(() {
      _tags = List.of(tags);
      _saving = true;
      _message = null;
      _failed = false;
    });
    try {
      final updated = await widget.repository.updateCardMetadata(
        widget.card.cardId,
        tags: tags,
      );
      final suggestions = await widget.repository.listDistinctTags();
      if (!mounted) return;
      setState(() {
        _tags = List.of(updated.tags);
        _suggestions = suggestions;
        _saving = false;
        _message = '标签已保存';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tags = previous;
        _saving = false;
        _failed = true;
        _message = '标签保存失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardTagField(
          tags: _tags,
          suggestions: _suggestions,
          enabled: !_saving,
          onChanged: _save,
        ),
        if (_saving || _message != null) ...[
          const SizedBox(height: 6),
          Text(
            _saving ? '正在保存标签…' : _message!,
            key: const ValueKey('source-tag-save-state'),
            style: whiteboardUiTextStyle(
              color: _failed ? tokens.error : tokens.textFaint,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceDetails extends StatelessWidget {
  const _SourceDetails({
    required this.version,
    required this.versionCount,
    required this.objectState,
    required this.metadata,
  });

  final SourceVersion version;
  final int versionCount;
  final SourceObjectState? objectState;
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: tokens.divider),
            bottom: BorderSide(color: tokens.divider),
          ),
        ),
        child: ExpansionTile(
          key: const ValueKey('source_details_expansion'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          iconColor: tokens.action,
          collapsedIconColor: tokens.textFaint,
          title: Text(
            '来源信息',
            style: whiteboardUiTextStyle(
              color: tokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${_objectStateLabel(objectState)} · 版本链 $versionCount',
            style: whiteboardUiTextStyle(
              color: tokens.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          children: [
            _VersionStatus(
              version: version,
              versionCount: versionCount,
              objectState: objectState,
            ),
            const SizedBox(height: 16),
            _MetadataView(metadata: metadata),
          ],
        ),
      ),
    );
  }

  static String _objectStateLabel(SourceObjectState? state) => switch (state) {
        SourceObjectState.available => '正文对象可用',
        SourceObjectState.missing => '正文对象缺失，已使用卡片投影',
        SourceObjectState.corrupt => '正文对象损坏，已使用卡片投影',
        null => '没有正文对象',
      };
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
    final tokens = DesktopWorkspaceTokens.of(context);
    final state = _SourceDetails._objectStateLabel(objectState);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        Text(
          '当前版本 ${version.versionId}',
          style: whiteboardUiTextStyle(color: tokens.textMuted, fontSize: 11),
        ),
        Text(
          '版本链 $versionCount',
          style: whiteboardUiTextStyle(color: tokens.textMuted, fontSize: 11),
        ),
        Text(
          state,
          style: whiteboardUiTextStyle(color: tokens.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _MetadataView extends StatelessWidget {
  const _MetadataView({required this.metadata});

  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final entries = metadata.entries
        .where((entry) => entry.value != null && entry.key != 'body_text')
        .take(12)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '来源元数据',
          style: whiteboardUiTextStyle(
            color: tokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${entry.key}: ',
                    style: whiteboardUiTextStyle(
                      color: tokens.textFaint,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: '${entry.value}',
                    style: whiteboardUiTextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
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
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 40,
                color: tokens.textFaint,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: whiteboardUiTextStyle(
                  color: tokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                label: const Text('返回卡片库'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.action,
                  foregroundColor: tokens.canvas,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
