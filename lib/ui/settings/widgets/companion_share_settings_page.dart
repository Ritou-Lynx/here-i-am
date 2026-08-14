import 'package:flutter/material.dart';
import 'package:memex/data/services/companion_share_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

class CompanionShareSettingsPage extends StatefulWidget {
  const CompanionShareSettingsPage({super.key});

  @override
  State<CompanionShareSettingsPage> createState() =>
      _CompanionShareSettingsPageState();
}

class _CompanionShareSettingsPageState
    extends State<CompanionShareSettingsPage> {
  final _service = CompanionShareService.instance;
  late final AppLifecycleListener _lifecycleListener;

  bool _enabled = false;
  bool _connected = false;
  bool _loading = true;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await _service.isAccessibilityServiceEnabled();
    final connected = await _service.isServiceConnected();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _connected = connected;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    await _service.openAccessibilitySettings();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _enabled && _connected;
    return Scaffold(
      backgroundColor: SpringRainUiTokens.daylightCanvas,
      appBar: AppBar(
        title: Text(_zh ? '交给林埃' : 'Share with i'),
        backgroundColor: SpringRainUiTokens.daylightCanvas,
        surfaceTintColor: SpringRainUiTokens.daylightCanvas,
        foregroundColor: SpringRainUiTokens.daylightTextPrimary,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            ready
                                ? Icons.check_circle
                                : Icons.touch_app_outlined,
                            color: ready ? SpringRainUiTokens.daylightSuccess : SpringRainUiTokens.daylightAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              ready
                                  ? (_zh
                                      ? '悬浮球已经可以使用'
                                      : 'The share bubble is ready')
                                  : (_zh
                                      ? '需要开启“交给林埃”无障碍服务'
                                      : 'Enable the Share with i accessibility service'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _zh
                            ? '开启后，浏览其他 App 时屏幕边缘会显示一个 i 悬浮球。轻点分享当前截图；长按分享刚复制的链接。'
                            : 'A small i bubble appears while you use other apps. Tap it to share the current screen, or hold it to share a copied link.',
                        style: TextStyle(color: SpringRainUiTokens.daylightTextSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.accessibility_new),
                          label: Text(
                            ready
                                ? (_zh ? '打开系统设置' : 'Open system settings')
                                : (_zh ? '去开启' : 'Enable'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _zh ? '怎么使用' : 'How it works',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _instruction(
                        Icons.photo_camera_outlined,
                        _zh ? '轻点悬浮球' : 'Tap the bubble',
                        _zh
                            ? '截取当前可见画面，作为图片草稿交给林埃。'
                            : 'Capture the visible screen as an image draft.',
                      ),
                      const SizedBox(height: 14),
                      _instruction(
                        Icons.link_rounded,
                        _zh ? '长按悬浮球' : 'Hold the bubble',
                        _zh
                            ? '先在小红书等 App 里复制链接，再长按悬浮球。'
                            : 'Copy a link in another app, then hold the bubble.',
                      ),
                      const SizedBox(height: 14),
                      _instruction(
                        Icons.open_with_rounded,
                        _zh ? '拖动悬浮球' : 'Drag the bubble',
                        _zh
                            ? '把它放到不遮挡内容的位置。'
                            : 'Move it somewhere that does not cover content.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.privacy_tip_outlined,
                          color: SpringRainUiTokens.daylightAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _zh
                              ? '只有你主动轻点时才会截屏；服务不会读取其他 App 的页面结构。截图和链接会先进入发送草稿，由你确认。'
                              : 'A screenshot is taken only after you tap. The service does not inspect the page structure of other apps. Shares open as drafts for your confirmation.',
                          style:
                              TextStyle(color: SpringRainUiTokens.daylightTextSecondary, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _instruction(
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: SpringRainUiTokens.daylightAccent, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(description, style: TextStyle(color: SpringRainUiTokens.daylightTextSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SpringRainUiTokens.daylightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpringRainUiTokens.daylightDivider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
