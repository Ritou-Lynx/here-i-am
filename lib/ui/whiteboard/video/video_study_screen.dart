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

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
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
    );
    _viewModel.initialize(embedUrl: widget.embedUrl).then((_) {
      _viewModel.restoreSession();
    });
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: const Color(0xFF1C1C1A),
        body: Consumer<VideoStudyViewModel>(
          builder: (context, vm, _) {
            if (!vm.isLoaded) {
              return _LoadingView(errorMessage: vm.errorMessage);
            }
            return _VideoStudyBody(
              viewModel: vm,
              embedUrl: widget.embedUrl,
            );
          },
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String? errorMessage;
  const _LoadingView({this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: SpringRainUiTokens.daylightAccent,
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            errorMessage ?? '加载中…',
            style: const TextStyle(
              color: SpringRainUiTokens.daylightTextTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoStudyBody extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final String? embedUrl;

  const _VideoStudyBody({required this.viewModel, this.embedUrl});

  @override
  Widget build(BuildContext context) {
    if (!viewModel.hasAnyPlaybackSurface) {
      return _LinkOnlyView(viewModel: viewModel);
    }

    if (viewModel.dockOrientation == DockOrientation.right) {
      return _HorizontalLayout(viewModel: viewModel, embedUrl: embedUrl);
    } else {
      return _VerticalLayout(viewModel: viewModel, embedUrl: embedUrl);
    }
  }
}

/// Horizontal layout: player left (65%), dock right (35%).
class _HorizontalLayout extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final String? embedUrl;

  const _HorizontalLayout({required this.viewModel, this.embedUrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 4.0;
        final totalWidth = constraints.maxWidth - dividerWidth;
        final dockWidth = totalWidth * viewModel.dockRatio;
        final playerWidth = totalWidth - dockWidth;

        return Row(
          children: [
            SizedBox(
              width: playerWidth,
              child: VideoPlayerPanel(viewModel: viewModel),
            ),
            _DockDivider(
              isHorizontal: false,
              ratio: viewModel.dockRatio,
              onDrag: (delta) {
                final newRatio =
                    viewModel.dockRatio + delta / totalWidth;
                viewModel.setDockRatio(newRatio);
              },
            ),
            SizedBox(
              width: dockWidth,
              child: ContextDock(viewModel: viewModel),
            ),
          ],
        );
      },
    );
  }
}

/// Vertical layout: player top (70%), dock bottom (30%).
class _VerticalLayout extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final String? embedUrl;

  const _VerticalLayout({required this.viewModel, this.embedUrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerHeight = 4.0;
        final totalHeight = constraints.maxHeight - dividerHeight;
        final dockHeight = totalHeight * viewModel.dockRatio;
        final playerHeight = totalHeight - dockHeight;

        return Column(
          children: [
            SizedBox(
              height: playerHeight,
              child: VideoPlayerPanel(viewModel: viewModel),
            ),
            _DockDivider(
              isHorizontal: true,
              ratio: viewModel.dockRatio,
              onDrag: (delta) {
                final newRatio =
                    viewModel.dockRatio + delta / totalHeight;
                viewModel.setDockRatio(newRatio);
              },
            ),
            SizedBox(
              height: dockHeight,
              child: ContextDock(viewModel: viewModel),
            ),
          ],
        );
      },
    );
  }
}

/// Draggable divider between player and dock.
class _DockDivider extends StatelessWidget {
  final bool isHorizontal;
  final double ratio;
  final void Function(double delta) onDrag;

  const _DockDivider({
    required this.isHorizontal,
    required this.ratio,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        if (isHorizontal) {
          onDrag(details.delta.dy);
        } else {
          onDrag(-details.delta.dx);
        }
      },
      child: MouseRegion(
        cursor: isHorizontal
            ? SystemMouseCursors.resizeRow
            : SystemMouseCursors.resizeColumn,
        child: Container(
          width: isHorizontal ? double.infinity : 4,
          height: isHorizontal ? 4 : double.infinity,
          color: const Color(0x33F0EFEB),
        ),
      ),
    );
  }
}

/// Link-only view for providers that don't support playback study.
class _LinkOnlyView extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  const _LinkOnlyView({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.link,
              size: 48,
              color: SpringRainUiTokens.daylightTextTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              '此平台不支持研读播放',
              style: TextStyle(
                color: SpringRainUiTokens.daylightSurfaceRaised,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${viewModel.providerId} 当前为链接模式\n'
              '请使用 YouTube 播放器进行完整字幕研读与时间标注',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SpringRainUiTokens.daylightTextTertiary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}