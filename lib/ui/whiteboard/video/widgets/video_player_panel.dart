/// Video player panel — the left/top portion of the video study screen.
///
/// On desktop (fixture adapter), shows a simulated player surface with
/// playback controls. On Android (YouTube adapter), embeds the WebView.
/// On Flutter Web (WebYouTubePlayerAdapter), embeds a `HtmlElementView` that
/// hosts the YouTube IFrame. Player controls are always visible during
/// development — they fade out in production when idle.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'web_player_surface.dart'
    if (dart.library.js_interop) 'web_player_surface_web.dart'
    as player_surface;
import '../view_models/video_study_view_model.dart';
import 'timeline_anchor_bar.dart';

class VideoPlayerPanel extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final double controlBarHeight = 52;

  const VideoPlayerPanel({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1C1C1A),
      child: Stack(
        children: [
          // Player surface
          Positioned.fill(
            child: _PlayerSurface(viewModel: viewModel),
          ),
          // Bottom gradient + controls + timeline
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
    final adapter = viewModel.adapter;

    // Flutter Web — YouTube IFrame embedded via HtmlElementView (conditional)
    final webSurface = player_surface.buildWebYouTubeSurface(adapter);
    if (webSurface != null) {
      return webSurface;
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
        color: const Color(0xFF1C1C1A),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                viewModel.isPlaying ? Icons.play_circle_outline : Icons.pause_circle_outline,
                size: 64,
                color: const Color(0xFF8F8E88),
              ),
              const SizedBox(height: 12),
              Text(
                'Fixture Player',
                style: TextStyle(
                  color: const Color(0xFF8F8E88),
                  fontSize: 12,
                  fontFamily: 'Cascadia Code',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                VideoStudyViewModel.formatTimecode(viewModel.positionMs),
                style: TextStyle(
                  color: const Color(0xFFB0AFA9),
                  fontSize: 20,
                  fontFamily: 'Cascadia Code',
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
      color: const Color(0xFF1C1C1A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.link,
              size: 48,
              color: Color(0xFF8F8E88),
            ),
            const SizedBox(height: 12),
            Text(
              '${viewModel.providerId} 当前为链接模式',
              style: const TextStyle(
                color: Color(0xFF8F8E88),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '无可控播放接口，请使用 YouTube 研读播放',
              style: TextStyle(
                color: Color(0xFF6A6963),
                fontSize: 12,
              ),
            ),
          ],
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x001C1C1A), Color(0xE61C1C1A)],
        ),
      ),
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Timeline anchor bar
          if (viewModel.canReadPosition)
            TimelineAnchorBar(viewModel: viewModel),
          const SizedBox(height: 8),
          // Control row
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
                style: const TextStyle(
                  color: Color(0xFFD8D7D1),
                  fontSize: 13,
                  fontFamily: 'Cascadia Code',
                ),
              ),
              Text(
                ' / ',
                style: TextStyle(
                  color: const Color(0xFF8F8E88),
                  fontSize: 13,
                  fontFamily: 'Cascadia Code',
                ),
              ),
              Text(
                VideoStudyViewModel.formatTimecode(viewModel.durationMs),
                style: const TextStyle(
                  color: Color(0xFF8F8E88),
                  fontSize: 13,
                  fontFamily: 'Cascadia Code',
                ),
              ),
              const Spacer(),
              // Dock orientation toggle
              _ControlButton(
                icon: viewModel.dockOrientation == DockOrientation.right
                    ? Icons.view_stream
                    : Icons.view_column,
                size: 18,
                onPressed: () {
                  viewModel.setDockOrientation(
                    viewModel.dockOrientation == DockOrientation.right
                        ? DockOrientation.bottom
                        : DockOrientation.right,
                  );
                },
              ),
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
  final double size;

  const _ControlButton({
    required this.icon,
    this.onPressed,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, size: size),
        color: const Color(0xFFD8D7D1),
        hoverColor: const Color(0x33F0EFEB),
        onPressed: onPressed,
      ),
    );
  }
}