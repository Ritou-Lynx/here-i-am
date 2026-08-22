/// Video study screen — the full playback + subtitle + annotation workspace.
///
/// Layout: video player on the left (65%), ContextDock on the right (35%).
/// The ContextDock can be toggled to bottom orientation. The split ratio
/// is draggable and persisted.
///
/// Visual: Palm Lieflat — warm paper canvas, coffee-tone text, low-saturation
/// green for actions, amber for single focus. Time codes use Cascadia Code
/// (monospace). No permanent top bar or side bar.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:memex/data/whiteboard/repository_video_annotation_store.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import 'session_store.dart';
import 'view_models/video_study_view_model.dart';
import 'widgets/video_player_panel.dart';
import 'widgets/context_dock.dart';

/// Entry point for the video study screen.
///
/// [adapter] must be already constructed (FixturePlayerAdapter for desktop,
/// YouTubePlayerAdapter for Android, etc.).
/// [sourceId] and [sourceVersionId] identify the video source.
/// [embedUrl] is the platform-specific URL or video ID.
/// [sessionStore] (optional) persists the session for restart recovery.
/// [timedTextService] (optional) overrides the platform-subtitle fetcher
/// (defaults to an HTTP-backed YouTube timedtext service).
class VideoStudyScreen extends StatefulWidget {
  final PlayerAdapter adapter;
  final String sourceId;
  final String sourceVersionId;
  final String? embedUrl;
  final TimedTextTrack? initialTrack;
  final String? providerId;
  final VideoSessionStore? sessionStore;
  final YouTubeTimedTextService? timedTextService;
  final BilibiliTimedTextService? bilibiliTimedTextService;
  final RepositoryVideoAnnotationStore? annotationStore;
  final bool runtimePlayerAvailable;
  final VoidCallback? onBack;

  const VideoStudyScreen({
    super.key,
    required this.adapter,
    required this.sourceId,
    required this.sourceVersionId,
    this.embedUrl,
    this.initialTrack,
    this.providerId,
    this.sessionStore,
    this.timedTextService,
    this.bilibiliTimedTextService,
    this.annotationStore,
    this.runtimePlayerAvailable = true,
    this.onBack,
  });

  @override
  State<VideoStudyScreen> createState() => _VideoStudyScreenState();
}

class _VideoStudyScreenState extends State<VideoStudyScreen> {
  late VideoStudyViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = VideoStudyViewModel(
      adapter: widget.adapter,
      sourceId: widget.sourceId,
      sourceVersionId: widget.sourceVersionId,
      providerId: widget.providerId ?? widget.adapter.providerId,
      initialTrack: widget.initialTrack,
      sessionStore: widget.sessionStore,
      timedTextService: widget.timedTextService,
      bilibiliTimedTextService: widget.bilibiliTimedTextService,
      annotationStore: widget.annotationStore,
      runtimePlayerAvailable: widget.runtimePlayerAvailable,
    );
    _viewModel.initialize(embedUrl: widget.embedUrl).then((_) {
      _viewModel.restoreSession(currentVersionId: widget.sourceVersionId);
    });
  }

  @override
  void dispose() {
    // The save-confirmation timer lives in the view model. Clear the visible
    // confirmation before disposal so its delayed callback becomes a no-op
    // when the user leaves or restarts immediately after saving.
    _viewModel.dismissSaveConfirmation();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Builder(
        builder: (context) {
          final tokens = DesktopWorkspaceTokens.of(context);
          return Scaffold(
            backgroundColor: tokens.dark,
            body: Stack(
              children: [
                Positioned.fill(
                  child: Consumer<VideoStudyViewModel>(
                    builder: (context, vm, _) {
                      if (!vm.isLoaded) {
                        return _LoadingView(
                          errorMessage: vm.errorMessage,
                          onRetry: vm.retryLoad,
                        );
                      }
                      return _VideoStudyBody(
                        viewModel: vm,
                        embedUrl: widget.embedUrl,
                      );
                    },
                  ),
                ),
                if (widget.onBack != null)
                  Positioned(
                    left: 16,
                    top: 16,
                    child: _MediaOverlayButton(
                      key: const ValueKey('video_back_action'),
                      tooltip: '返回来源',
                      onPressed: widget.onBack!,
                      icon: Icons.chevron_left_rounded,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String? errorMessage;
  final Future<void> Function() onRetry;
  const _LoadingView({this.errorMessage, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage == null)
            CircularProgressIndicator(
              color: tokens.actionSecondary,
              strokeWidth: 2,
            )
          else
            Icon(Icons.cloud_off_outlined, color: tokens.textFaint, size: 36),
          const SizedBox(height: 16),
          Text(
            errorMessage ?? '加载中…',
            style: whiteboardUiTextStyle(color: tokens.textFaint, fontSize: 14),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey('video_retry_load'),
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('重试加载'),
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoStudyBody extends StatelessWidget {
  static const double _autoBottomBreakpoint = 760;

  final VideoStudyViewModel viewModel;
  final String? embedUrl;

  const _VideoStudyBody({required this.viewModel, this.embedUrl});

  @override
  Widget build(BuildContext context) {
    if (!viewModel.hasRuntimePlaybackSurface) {
      return _LinkOnlyView(viewModel: viewModel, embedUrl: embedUrl);
    }

    if (!viewModel.dockVisible) {
      return Stack(
        children: [
          Positioned.fill(
            child: SizedBox.expand(
              key: const ValueKey('video_player_region'),
              child: VideoPlayerPanel(viewModel: viewModel),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: _MediaOverlayButton(
              key: const ValueKey('video_open_dock'),
              tooltip: '打开字幕与标注',
              onPressed: () => viewModel.setDockVisible(true),
              icon: Icons.subtitles_outlined,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final autoBottom = constraints.maxWidth < _autoBottomBreakpoint;
        final effectiveOrientation = autoBottom
            ? DockOrientation.bottom
            : viewModel.dockOrientation;
        if (effectiveOrientation == DockOrientation.right) {
          return _HorizontalLayout(viewModel: viewModel);
        }
        return _VerticalLayout(
          viewModel: viewModel,
          orientationLocked: autoBottom,
        );
      },
    );
  }
}

/// Horizontal layout: player left (65%), dock right (35%).
class _HorizontalLayout extends StatelessWidget {
  static const double _splitterExtent = 8;
  static const double _minimumPlayerWidth = 420;
  static const double _minimumDockWidth = 320;

  final VideoStudyViewModel viewModel;

  const _HorizontalLayout({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth - _splitterExtent;
        final dockWidth = _resolveDockExtent(
          totalExtent: totalWidth,
          preferredRatio: viewModel.dockRatio,
          minimumDockExtent: _minimumDockWidth,
          minimumMainExtent: _minimumPlayerWidth,
        );
        final playerWidth = totalWidth - dockWidth;

        return KeyedSubtree(
          key: const ValueKey('video_layout_right'),
          child: Row(
            children: [
              SizedBox(
                key: const ValueKey('video_player_region'),
                width: playerWidth,
                child: VideoPlayerPanel(viewModel: viewModel),
              ),
              _DockDivider(
                axis: Axis.vertical,
                extent: _splitterExtent,
                onDrag: (delta) {
                  final requestedDockWidth = dockWidth - delta;
                  viewModel.setDockRatio(requestedDockWidth / totalWidth);
                },
              ),
              SizedBox(
                key: const ValueKey('video_context_dock_region'),
                width: dockWidth,
                child: ContextDock(viewModel: viewModel),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Vertical layout: player top (70%), dock bottom (30%).
class _VerticalLayout extends StatelessWidget {
  static const double _splitterExtent = 8;
  static const double _minimumPlayerHeight = 300;
  static const double _minimumDockHeight = 220;
  static const double _defaultBottomRatio = 0.30;

  final VideoStudyViewModel viewModel;
  final bool orientationLocked;

  const _VerticalLayout({
    required this.viewModel,
    required this.orientationLocked,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight - _splitterExtent;
        final preferredRatio = (viewModel.dockRatio - 0.35).abs() < 0.0001
            ? _defaultBottomRatio
            : viewModel.dockRatio;
        final dockHeight = _resolveDockExtent(
          totalExtent: totalHeight,
          preferredRatio: preferredRatio,
          minimumDockExtent: _minimumDockHeight,
          minimumMainExtent: _minimumPlayerHeight,
        );
        final playerHeight = totalHeight - dockHeight;

        return KeyedSubtree(
          key: const ValueKey('video_layout_bottom'),
          child: Column(
            children: [
              SizedBox(
                key: const ValueKey('video_player_region'),
                height: playerHeight,
                child: VideoPlayerPanel(viewModel: viewModel),
              ),
              _DockDivider(
                axis: Axis.horizontal,
                extent: _splitterExtent,
                onDrag: (delta) {
                  final requestedDockHeight = dockHeight - delta;
                  viewModel.setDockRatio(requestedDockHeight / totalHeight);
                },
              ),
              SizedBox(
                key: const ValueKey('video_context_dock_region'),
                height: dockHeight,
                child: ContextDock(
                  viewModel: viewModel,
                  displayOrientation: DockOrientation.bottom,
                  orientationLocked: orientationLocked,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Draggable divider between player and dock.
class _DockDivider extends StatelessWidget {
  final Axis axis;
  final double extent;
  final void Function(double delta) onDrag;

  const _DockDivider({
    required this.axis,
    required this.extent,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final horizontal = axis == Axis.horizontal;
    return GestureDetector(
      key: const ValueKey('video_dock_splitter'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        if (horizontal) {
          onDrag(details.delta.dy);
        } else {
          onDrag(details.delta.dx);
        }
      },
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeRow
            : SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: horizontal ? double.infinity : extent,
          height: horizontal ? extent : double.infinity,
          child: Center(
            child: ColoredBox(
              color: tokens.divider,
              child: SizedBox(
                width: horizontal ? double.infinity : 1,
                height: horizontal ? 1 : double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Link-only view for providers that don't support playback study.
class _LinkOnlyView extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final String? embedUrl;

  const _LinkOnlyView({required this.viewModel, required this.embedUrl});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final externalUri = _externalUri(embedUrl);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_rounded, size: 48, color: tokens.textFaint),
              const SizedBox(height: 16),
              Text(
                '当前为链接模式',
                style: whiteboardUiTextStyle(
                  color: tokens.canvas,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_providerLabel(viewModel.providerId)} 没有稳定的 '
                'current / duration / seek 接口。\n'
                '原链接仍然保留；这里不会伪装播放器、时间轴或字幕能力。',
                textAlign: TextAlign.center,
                style: whiteboardUiTextStyle(
                  color: tokens.textFaint,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              if (embedUrl?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 16),
                SelectableText(
                  embedUrl!.trim(),
                  textAlign: TextAlign.center,
                  style: whiteboardUiTextStyle(
                    color: tokens.actionSoft,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
              if (externalUri != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('open_video_source_link'),
                  onPressed: () => _openExternal(context, externalUri),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('在浏览器打开原链接'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.action,
                    foregroundColor: tokens.canvas,
                    minimumSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Uri? _externalUri(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  static String _providerLabel(String providerId) => switch (providerId) {
    'bilibili' => '哔哩哔哩',
    'xiaohongshu' => '小红书',
    'unknown' => '这个来源',
    _ => providerId,
  };

  static Future<void> _openExternal(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || launched) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开原链接，请复制链接后重试。')));
  }
}

double _resolveDockExtent({
  required double totalExtent,
  required double preferredRatio,
  required double minimumDockExtent,
  required double minimumMainExtent,
}) {
  if (!totalExtent.isFinite || totalExtent <= 0) return 0;
  final maximumDockExtent = totalExtent - minimumMainExtent;
  if (maximumDockExtent < minimumDockExtent) {
    return (totalExtent / 2).clamp(0.0, totalExtent).toDouble();
  }
  return (totalExtent * preferredRatio)
      .clamp(minimumDockExtent, maximumDockExtent)
      .toDouble();
}

class _MediaOverlayButton extends StatelessWidget {
  const _MediaOverlayButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.dark.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.canvas.withValues(alpha: 0.18)),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: tokens.canvas,
        hoverColor: tokens.canvas.withValues(alpha: 0.10),
      ),
    );
  }
}
