import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Spring Rain Daydream opening animation used while the app is bootstrapping.
class AppOpeningSplash extends StatefulWidget {
  const AppOpeningSplash({
    super.key,
    this.statusText,
    this.playVideo = true,
  });

  /// Exact decoded frame zero from [videoAssetPath], used during video startup.
  static const assetPath =
      'assets/images/spring_rain_daydream_splash_v6_poster.png';
  static const sourceAssetPath =
      'assets/images/spring_rain_daydream_splash_v6.webp';
  static const videoAssetPath =
      'assets/images/spring_rain_daydream_splash_v6.mp4';
  static const backgroundColor = Color(0xFFF3F3EC);
  static const mediaHorizontalShiftFraction = 0.04;

  static VideoPlayerController? _preloadedVideoController;
  static Future<void>? _preloadFuture;
  static int _preloadedVideoUsers = 0;

  /// Prepares a decoded, paused zero frame before Flutter renders its first UI.
  /// The Android LaunchTheme remains visible while this runs.
  static Future<void> preloadVideo() {
    return _preloadFuture ??= _createPreloadedVideo();
  }

  static Future<void> _createPreloadedVideo() async {
    final controller = VideoPlayerController.asset(
      videoAssetPath,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      // Force Android to allocate the texture and decode pixels while the
      // native launch window is still covering Flutter.
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await controller.pause();
      await controller.seekTo(Duration.zero);
      _preloadedVideoController = controller;
    } catch (error) {
      await controller.dispose();
      debugPrint('Opening splash video preload failed: $error');
    }
  }

  static void _registerPreloadedUser() {
    _preloadedVideoUsers++;
  }

  static void _unregisterPreloadedUser() {
    _preloadedVideoUsers--;
    if (_preloadedVideoUsers <= 0) {
      _preloadedVideoUsers = 0;
      final controller = _preloadedVideoController;
      if (controller != null && controller.value.isPlaying) {
        unawaited(controller.pause());
      }
    }
  }

  final String? statusText;
  final bool playVideo;

  @override
  State<AppOpeningSplash> createState() => _AppOpeningSplashState();
}

class _AppOpeningSplashState extends State<AppOpeningSplash> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _usesPreloadedVideo = false;

  @override
  void initState() {
    super.initState();
    if (!widget.playVideo) return;
    final preloadedController = AppOpeningSplash._preloadedVideoController;
    if (preloadedController != null &&
        preloadedController.value.isInitialized) {
      _videoController = preloadedController;
      _videoReady = true;
      _usesPreloadedVideo = true;
      AppOpeningSplash._registerPreloadedUser();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _videoController;
        if (mounted && controller != null && !controller.value.isPlaying) {
          unawaited(controller.play());
        }
      });
      return;
    }

    // Non-Here-I-am entry points and preload failures keep a safe local
    // fallback, with the PNG poster visible until the texture is ready.
    _videoController = VideoPlayerController.asset(
      AppOpeningSplash.videoAssetPath,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    unawaited(_initializeFallbackVideo());
  }

  Future<void> _initializeFallbackVideo() async {
    final controller = _videoController;
    if (controller == null) return;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(0);
      // Pre-roll once so the platform texture has decoded pixels, then return
      // to the exact poster frame before exposing the video. Previously the
      // video played for 80 ms behind the poster and appeared two frames ahead,
      // which looked like a single positional shake during startup.
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await controller.pause();
      await controller.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() => _videoReady = true);
      // Render the decoded zero frame first. Motion starts only after that
      // frame has replaced the byte-identical PNG poster on screen.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await controller.play();
    } catch (error) {
      debugPrint('Opening splash video initialization failed: $error');
    }
  }

  @override
  void dispose() {
    final controller = _videoController;
    if (_usesPreloadedVideo) {
      AppOpeningSplash._unregisterPreloadedUser();
    } else if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  Widget _positionedMedia(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: Transform.translate(
            offset: Offset(
              constraints.maxWidth *
                  AppOpeningSplash.mediaHorizontalShiftFraction,
              0,
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    return Scaffold(
      backgroundColor: AppOpeningSplash.backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_videoReady)
            _positionedMedia(
              Image.asset(
                AppOpeningSplash.assetPath,
                key: const ValueKey('app_opening_animation'),
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
            ),
          if (_videoReady && videoController != null)
            Positioned.fill(
              child: _positionedMedia(
                FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: videoController.value.size.width,
                    height: videoController.value.size.height,
                    child: VideoPlayer(
                      videoController,
                      key: const ValueKey('app_opening_video'),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.statusText case final text?)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6E704E),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
