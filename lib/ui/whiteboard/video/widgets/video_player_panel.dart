/// Video player panel — the left/top portion of the video study screen.
///
/// On desktop (fixture adapter), shows a simulated player surface with
/// playback controls. On Android (YouTube adapter), embeds the WebView.
/// On Flutter Web (WebYouTubePlayerAdapter), embeds a `HtmlElementView` that
/// hosts the YouTube IFrame. Player controls are always visible during
/// development — they fade out in production when idle.
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/domain/whiteboard/video/windows_youtube_player_adapter.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import 'web_player_surface.dart'
    if (dart.library.js_interop) 'web_player_surface_web.dart'
    as player_surface;
import '../view_models/video_study_view_model.dart';

class VideoPlayerPanel extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final double controlBarHeight = 52;

  const VideoPlayerPanel({super.key, required this.viewModel});

  /// Whether the underlying player provides its own native controls
  /// (YouTube IFrame on web, webview_flutter on Android). When true, we must
  /// NOT overlay our own control bar on top — the native progress bar, CC /
  /// fullscreen / settings buttons are the primary surface and overlapping
  /// would duplicate the progress bar.
  bool get _usesNativeControls {
    final adapter = viewModel.adapter;
    if (player_surface.buildWebYouTubeSurface(adapter) != null) return true;
    if (adapter is WindowsYouTubePlayerAdapter && adapter.isAvailable) {
      return true;
    }
    if (adapter is WindowsBilibiliPlayerAdapter && adapter.isAvailable) {
      return true;
    }
    if (adapter is YouTubePlayerAdapter && adapter.isAvailable) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final nativeControls = _usesNativeControls;
    return Container(
      color: tokens.dark,
      child: Stack(
        children: [
          // Player surface
          Positioned.fill(child: _PlayerSurface(viewModel: viewModel)),
          if (viewModel.adapter case final WindowsBilibiliPlayerAdapter adapter)
            Positioned(
              top: 16,
              right: 16,
              child: _BilibiliPlaybackActions(
                adapter: adapter,
                viewModel: viewModel,
              ),
            ),
          // Bottom gradient + controls + timeline (only for players WITHOUT
          // native controls, e.g. the fixture simulator / link-only stubs).
          if (!nativeControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PlayerControls(viewModel: viewModel),
            ),
        ],
      ),
    );
  }
}

class _PlayerSurface extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  const _PlayerSurface({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final adapter = viewModel.adapter;

    // Flutter Web — YouTube IFrame embedded via HtmlElementView (conditional)
    final webSurface = player_surface.buildWebYouTubeSurface(adapter);
    if (webSurface != null) {
      return webSurface;
    }

    // Windows Desktop — native Edge WebView2 hosting the YouTube IFrame API.
    if (adapter is WindowsYouTubePlayerAdapter && adapter.isAvailable) {
      final controller = adapter.webviewController;
      if (controller != null && controller.value.isInitialized) {
        return Webview(
          controller,
          permissionRequested: (_, __, ___) => WebviewPermissionDecision.deny,
        );
      }
    }

    // Windows Desktop — Bilibili's platform-allowed external player. It is
    // genuinely playable in-app but has no supported current/duration/seek
    // bridge, so the surrounding UI labels it as time-study limited.
    if (adapter is WindowsBilibiliPlayerAdapter && adapter.isAvailable) {
      final controller = adapter.webviewController;
      if (controller != null && controller.value.isInitialized) {
        return Webview(
          controller,
          permissionRequested: (_, __, ___) => WebviewPermissionDecision.deny,
        );
      }
    }

    // YouTube adapter with WebView (Android)
    if (adapter is YouTubePlayerAdapter && adapter.isAvailable) {
      final controller = adapter.webViewController;
      if (controller != null) {
        return WebViewWidget(controller: controller);
      }
    }

    // Fixture adapter — simulated dark surface
    if (adapter is FixturePlayerAdapter) {
      return Container(
        color: tokens.dark,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                viewModel.isPlaying
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                size: 64,
                color: tokens.canvas.withValues(alpha: 0.56),
              ),
              const SizedBox(height: 12),
              Text(
                'Fixture Player',
                style: richTextCodeTextStyle(
                  color: tokens.canvas.withValues(alpha: 0.56),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                VideoStudyViewModel.formatTimecode(viewModel.positionMs),
                style: richTextCodeTextStyle(
                  color: tokens.canvas.withValues(alpha: 0.76),
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Link-only providers that expose a (non-controllable) embed surface:
    // show an honest placeholder, not a fake fixture player.
    return Container(
      color: tokens.dark,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link,
              size: 48,
              color: tokens.canvas.withValues(alpha: 0.56),
            ),
            const SizedBox(height: 12),
            Text(
              '${viewModel.providerId} 当前为链接模式',
              style: whiteboardUiTextStyle(
                color: tokens.canvas.withValues(alpha: 0.56),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '无可控播放接口，请使用 YouTube 研读播放',
              style: whiteboardUiTextStyle(
                color: tokens.canvas.withValues(alpha: 0.42),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BilibiliPlaybackActions extends StatefulWidget {
  const _BilibiliPlaybackActions({
    required this.adapter,
    required this.viewModel,
  });

  final WindowsBilibiliPlayerAdapter adapter;
  final VideoStudyViewModel viewModel;

  @override
  State<_BilibiliPlaybackActions> createState() =>
      _BilibiliPlaybackActionsState();
}

class _BilibiliPlaybackActionsState extends State<_BilibiliPlaybackActions> {
  bool _busy = false;

  Future<void> _openLoginWithNotice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开 Bilibili 登录页？'),
        content: const Text(
          '当前沿用 WebView 默认会话，平台可能保留登录状态；应用不会读取或记录密码、Cookie。'
          '固定登录 profile 与清除站点数据尚未获得授权。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续打开'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(widget.adapter.openLoginPage);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bilibili 页面操作失败，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.dark.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.canvas.withValues(alpha: 0.18)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.adapter.hasVerifiedTimeBridge
                    ? '可播放 · 时间桥已验证'
                    : '可播放 · 时间研读受限',
                key: ValueKey(widget.adapter.hasVerifiedTimeBridge
                    ? 'video_playback_level_timed'
                    : 'video_playback_level_limited'),
                style: whiteboardUiTextStyle(
                  color: tokens.canvas,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '登录仅由平台嵌入页处理；应用不读取或保存登录态',
                key: const ValueKey('bilibili_login_boundary'),
                style: whiteboardUiTextStyle(
                  color: tokens.canvas.withValues(alpha: 0.68),
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('bilibili_retry_player'),
                    tooltip: '重新加载嵌入播放器',
                    onPressed: _busy ? null : widget.viewModel.retryLoad,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    color: tokens.canvas,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  TextButton(
                    key: const ValueKey('bilibili_open_login'),
                    onPressed: _busy ? null : _openLoginWithNotice,
                    child: const Text('登录页'),
                  ),
                  TextButton(
                    key: const ValueKey('bilibili_return_video'),
                    onPressed:
                        _busy ? null : () => _run(widget.adapter.returnToVideo),
                    child: const Text('返回视频'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  const _PlayerControls({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.dark.withValues(alpha: 0),
            tokens.dark.withValues(alpha: 0.90),
          ],
        ),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Control row (timeline/anchors live in the ContextDock so they
          // never overlap a native player's progress bar)
          Row(
            children: [
              // Play/pause
              _ControlButton(
                icon: viewModel.isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: viewModel.togglePlayPause,
              ),
              const SizedBox(width: 8),
              // Time display
              Text(
                VideoStudyViewModel.formatTimecode(viewModel.positionMs),
                style: richTextCodeTextStyle(
                  color: tokens.canvas.withValues(alpha: 0.90),
                  fontSize: 13,
                ),
              ),
              Text(
                ' / ',
                style: richTextCodeTextStyle(
                  color: tokens.canvas.withValues(alpha: 0.56),
                  fontSize: 13,
                ),
              ),
              Text(
                VideoStudyViewModel.formatTimecode(viewModel.durationMs),
                style: richTextCodeTextStyle(
                  color: tokens.canvas.withValues(alpha: 0.56),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _ControlButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: tokens.canvas.withValues(alpha: 0.90),
        hoverColor: tokens.canvas.withValues(alpha: 0.12),
        onPressed: onPressed,
      ),
    );
  }
}
