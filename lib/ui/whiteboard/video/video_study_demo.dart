/// Desktop verification demo for the W4 video study workflow.
///
/// Run with:
///   flutter run -d chrome -t lib/ui/whiteboard/video/video_study_demo.dart
///
/// On Flutter Web: uses [WebYouTubePlayerAdapter] (YouTube IFrame via
/// `dart:js_interop`) — the MVP desktop playback path. Loads a real YouTube
/// video so the playback → seek → subtitle → annotation loop is real.
/// On Android: uses [YouTubePlayerAdapter] (webview_flutter).
/// On other desktop platforms: uses [FixturePlayerAdapter] (simulated).
///
/// Web fallback: session file persistence is skipped on web since dart:io is
/// unavailable there.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/domain/whiteboard/video/youtube_adapter_factory.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

import 'session_path_stub.dart'
    if (dart.library.io) 'session_path_io.dart' as session_path;

const _sampleSrt = '''
1
00:00:02,000 --> 00:00:05,000
灯光切换，夜场开始

2
00:00:06,000 --> 00:00:09,500
舞台中央升起烟雾

3
00:00:10,000 --> 00:00:14,000
第一段副歌开始
灯光随节拍变化

4
00:00:15,000 --> 00:00:19,000
鼓点加强

5
00:00:20,000 --> 00:00:25,000
合唱进入高潮

6
00:00:26,000 --> 00:00:30,000
间奏，光线变暗

7
00:00:31,000 --> 00:00:36,000
第二段主歌开始
''';

void main() {
  runApp(const VideoStudyDemoApp());
}

class VideoStudyDemoApp extends StatelessWidget {
  const VideoStudyDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'W4 视频研读 Demo',
      theme: ThemeData(
        useMaterial3: true,
        extensions: [SpringRainUiTokens.daylight],
      ),
      home: const VideoStudyDemoScreen(),
    );
  }
}

class VideoStudyDemoScreen extends StatefulWidget {
  const VideoStudyDemoScreen({super.key});

  @override
  State<VideoStudyDemoScreen> createState() => _VideoStudyDemoScreenState();
}

class _VideoStudyDemoScreenState extends State<VideoStudyDemoScreen> {
  PlayerAdapter? _adapter;
  String? _embedUrl;
  String _providerId = 'fixture';
  final String? _sessionPath = session_path.resolveSessionPath();

  @override
  void initState() {
    super.initState();
    // Auto-open the study view immediately (this is a demo). Kept behind a
    // post-frame callback so the first frame can render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _adapter == null) _openStudy();
    });
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _adapter;
    if (adapter == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0EFEB),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_circle_outline,
                size: 64,
                color: Color(0xFF77835A),
              ),
              const SizedBox(height: 16),
              const Text(
                'W4 视频研读闭环 Demo',
                style: TextStyle(
                  color: Color(0xFF58402E),
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '播放器 + 字幕双向同步 + 时间标注 + 重启恢复',
                style: TextStyle(
                  color: Color(0xFF8F8E88),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _platformHint(),
                style: const TextStyle(
                  color: Color(0xFF8F8E88),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _openStudy,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开视频研读'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF43593B),
                  foregroundColor: const Color(0xFFF0EFEB),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return VideoStudyScreen(
      adapter: adapter,
      sourceId: 'src_demo_concert',
      sourceVersionId: 'ver_demo_concert_v1',
      embedUrl: _embedUrl,
      initialTrack: _demoTrack,
      sessionPath: _sessionPath,
      providerId: _providerId,
    );
  }

  String _platformHint() {
    if (kIsWeb) {
      return 'Flutter Web → YouTube IFrame Player（MVP 桌面路线）';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'Android → webview_flutter YouTube IFrame';
    }
    return '桌面无 WebView → Fixture 模拟播放器';
  }

  TimedTextTrack get _demoTrack {
    final result = SubtitleParser.parse(
      _sampleSrt,
      sourceId: 'src_demo_concert',
      sourceVersionId: 'ver_demo_concert_v1',
    );
    return result.track!;
  }

  void _openStudy() {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      // Real YouTube playback: Web uses IFrame via dart:js_interop, Android
      // uses webview_flutter. The factory picks the right implementation.
      final adapter = createYouTubeAdapter();
      _adapter = adapter;
      _embedUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      _providerId = 'youtube';
      setState(() {});
    } else {
      // Other desktop platforms: fixture (no real WebView available).
      final fixture = FixturePlayerAdapter(durationMs: 36000);
      _adapter = fixture;
      _embedUrl = null;
      _providerId = 'fixture';
      setState(() {});
    }
  }
}