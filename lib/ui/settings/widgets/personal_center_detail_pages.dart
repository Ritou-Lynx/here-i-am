import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/media_service.dart';
import 'package:memex/data/services/proactive_outing_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_color_controller.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_tokens.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/widgets/early_update_settings_card.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  String? _language;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locale = await UserStorage.getLocale();
    if (mounted) setState(() => _language = locale.languageCode);
  }

  Future<void> _select(String code) async {
    if (_language == code) return;
    await UserStorage.setLocale(Locale(code));
    await UserStorage.initL10n();
    if (!mounted) return;
    setState(() => _language = code);
    _showSaved(context, '语言设置已保存');
  }

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '语言',
      children: [
        const _PageIntro(
          title: '界面与回复语言',
          body: '选择应用界面使用的语言。新的设置会同时用于林埃的系统提示语言。',
        ),
        const SizedBox(height: 20),
        if (_language == null)
          const Center(child: CircularProgressIndicator())
        else
          _SettingsSurface(
            child: Column(
              children: [
                _ChoiceRow(
                  title: '简体中文',
                  subtitle: '中文界面与中文系统提示',
                  selected: _language == 'zh',
                  onTap: () => _select('zh'),
                ),
                const Divider(),
                _ChoiceRow(
                  title: 'English',
                  subtitle: 'English interface and system prompts',
                  selected: _language == 'en',
                  onTap: () => _select('en'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '外观',
      children: [
        const _PageIntro(
          title: '春雨昼眠',
          body: '这是当前唯一生效的视觉方向。已废弃的旧主题不再提供切换。',
        ),
        const SizedBox(height: 20),
        _SettingsSurface(
          child: Column(
            children: [
              _AppearanceRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: '聊天外观',
                subtitle: '聊天背景与用户消息文字颜色',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChatAppearanceSettingsPage(),
                  ),
                ),
              ),
              const Divider(),
              const _AppearanceRow(
                icon: Icons.water_drop_outlined,
                title: '生活空间',
                subtitle: '雨玻璃底图与黄绿色局部承载层',
              ),
              const Divider(),
              const _AppearanceRow(
                icon: Icons.tune_rounded,
                title: '设置与详情',
                subtitle: '偏白偏黄的暖雾昼面，不使用蓝紫色主题',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatAppearanceSettingsPage extends StatefulWidget {
  const ChatAppearanceSettingsPage({super.key});

  @override
  State<ChatAppearanceSettingsPage> createState() =>
      _ChatAppearanceSettingsPageState();
}

class _ChatAppearanceSettingsPageState
    extends State<ChatAppearanceSettingsPage> {
  CharacterModel? _character;
  String? _chatBackgroundPreview;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = await UserStorage.getUserId();
    final character = userId == null
        ? null
        : await CharacterService.instance.getPrimaryCompanion(userId);
    if (!mounted) return;
    setState(() {
      _character = character;
      _chatBackgroundPreview = character?.chatBackground;
      _isLoading = false;
    });
  }

  Future<void> _pickChatBackground() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (picked == null) return;
      final userId = await UserStorage.getUserId();
      final character = _character;
      if (userId == null || character == null) return;
      final imported = await MediaService.instance.importImage(
        userId: userId,
        sourcePath: picked.path,
      );
      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: character.id,
        updates: {'chat_background': imported.relativePath},
      );
      if (!mounted || updated == null) return;
      setState(() {
        _character = updated;
        _chatBackgroundPreview = updated.chatBackground;
      });
      _showSaved(context, '聊天背景已更新');
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.operationFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _restoreDefaultBackground() async {
    final userId = await UserStorage.getUserId();
    final character = _character;
    if (userId == null || character == null) return;
    try {
      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: character.id,
        updates: {'chat_background': null},
      );
      if (!mounted || updated == null) return;
      setState(() {
        _character = updated;
        _chatBackgroundPreview = null;
      });
      _showSaved(context, '已恢复春雨昼眠默认背景');
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.operationFailed(e.toString()),
        );
      }
    }
  }

  bool get _hasCustomBackground {
    final path = _chatBackgroundPreview;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '聊天外观',
      children: [
        const _PageIntro(
          title: '你们聊天时看到的空间',
          body: '默认使用春雨昼眠。选择自己的图片后，只会覆盖当前林埃聊天页的背景。',
        ),
        const SizedBox(height: 20),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else ...[
          _SettingsSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('聊天背景',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _buildBackgroundPreview(),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed:
                      _character == null ? null : _pickChatBackground,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_hasCustomBackground ? '更换图片' : '从相册选择'),
                ),
                if (_hasCustomBackground) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _restoreDefaultBackground,
                    child: const Text('恢复春雨昼眠默认背景'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _SettingsSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('用户消息文字颜色',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '只调整你在 Chat 中发送的文字，不改变林埃的文字与其他界面。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _buildUserColorPicker(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundPreview() {
    final path = _chatBackgroundPreview;
    final custom = _hasCustomBackground;
    final tokens = context.springRainUi;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius14),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (custom && path != null)
              Image.file(File(path), fit: BoxFit.cover)
            else
              Image.asset(
                'assets/images/spring_rain_daydream_chat_bg.png',
                fit: BoxFit.cover,
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3090B09)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text(
                custom ? '自定义背景' : '春雨昼眠 · 默认',
                style: const TextStyle(
                  color: Color(0xFFF5EEE0),
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserColorPicker() {
    final controller = context.watch<SpringRainChatColorController>();
    const chat = SpringRainChatTokens.springRainDaydream;
    const options = SpringRainChatColorController.options;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _UserColorSwatch(
              option: options[i],
              chat: chat,
              selected: controller.selectedId == options[i].id,
              onTap: () => controller.select(options[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _UserColorSwatch extends StatelessWidget {
  const _UserColorSwatch({
    required this.option,
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  final SpringRainUserColorOption option;
  final SpringRainChatTokens chat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: SpringRainUiTokens.motionFast,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: chat.background,
          borderRadius: BorderRadius.circular(tokens.radius14),
          border: Border.all(
            color: selected ? tokens.accent : tokens.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '用户消息',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: chat.fontFamily,
                color: option.color,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle, size: 14, color: tokens.accent),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          selected ? tokens.textPrimary : tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class VersionUpdateSettingsPage extends StatelessWidget {
  const VersionUpdateSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '版本更新',
      children: [
        const _PageIntro(
          title: '保持当前版本',
          body: '这里仅管理更新检查与安装偏好，不再混入语言、语音或其他设置。',
        ),
        const SizedBox(height: 20),
        if (Platform.isAndroid && AppFlavor.isEarly)
          EarlyUpdateSettingsCard()
        else
          const _SettingsSurface(
            child: _StatusMessage(
              icon: Icons.system_update_alt_rounded,
              title: '当前渠道不支持应用内更新',
              body: '请使用与你当前渠道一致的安装包进行覆盖安装。',
            ),
          ),
      ],
    );
  }
}

class AboutHereIamPage extends StatefulWidget {
  const AboutHereIamPage({super.key});

  @override
  State<AboutHereIamPage> createState() => _AboutHereIamPageState();
}

class _AboutHereIamPageState extends State<AboutHereIamPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((value) {
      if (mounted) setState(() => _info = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return _DetailPage(
      title: '故我在 V3',
      children: [
        const _PageIntro(
          title: 'Here I am',
          body: '一个本地优先、围绕持续陪伴与共同记忆构建的应用。',
        ),
        const SizedBox(height: 20),
        _SettingsSurface(
          child: Column(
            children: [
              _ValueRow(
                label: '版本',
                value: info == null
                    ? '读取中'
                    : '${info.version} (${info.buildNumber})',
              ),
              const Divider(),
              const _ValueRow(label: '开发通道', value: 'v3-lab'),
              const Divider(),
              _ValueRow(
                label: '包名',
                value: info?.packageName ?? 'com.memexlab.hereiam.v3',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSurface(
          child: _ActionRow(
            icon: Icons.description_outlined,
            title: '开源许可',
            subtitle: '查看 Flutter 与第三方组件许可',
            onTap: () => showLicensePage(
              context: context,
              applicationName: '故我在 V3',
              applicationVersion:
                  info == null ? null : '${info.version} (${info.buildNumber})',
            ),
          ),
        ),
      ],
    );
  }
}

class VoicePlaybackSettingsPage extends StatefulWidget {
  const VoicePlaybackSettingsPage({super.key});

  @override
  State<VoicePlaybackSettingsPage> createState() =>
      _VoicePlaybackSettingsPageState();
}

class _VoicePlaybackSettingsPageState extends State<VoicePlaybackSettingsPage> {
  final _elevenLabsController = TextEditingController();
  final _miniMaxController = TextEditingController();
  final _miniMaxGroupController = TextEditingController();
  String? _provider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object?>([
      UserStorage.getTtsProvider(),
      UserStorage.getElevenLabsApiKey(),
      UserStorage.getMiniMaxApiKey(),
      UserStorage.getMiniMaxGroupId(),
    ]);
    if (!mounted) return;
    _elevenLabsController.text = values[1] as String? ?? '';
    _miniMaxController.text = values[2] as String? ?? '';
    _miniMaxGroupController.text = values[3] as String? ?? '';
    setState(() => _provider = values[0]! as String);
  }

  @override
  void dispose() {
    _elevenLabsController.dispose();
    _miniMaxController.dispose();
    _miniMaxGroupController.dispose();
    super.dispose();
  }

  Future<void> _selectProvider(String provider) async {
    await UserStorage.setTtsProvider(provider);
    if (!mounted) return;
    setState(() => _provider = provider);
  }

  Future<void> _save() async {
    if (_provider == 'minimax') {
      await UserStorage.setMiniMaxApiKey(_miniMaxController.text.trim());
      await UserStorage.setMiniMaxGroupId(_miniMaxGroupController.text.trim());
    } else {
      await UserStorage.setElevenLabsApiKey(
        _elevenLabsController.text.trim(),
      );
    }
    if (mounted) _showSaved(context, '语音播放设置已保存');
  }

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '语音播放',
      children: [
        const _PageIntro(
          title: 'TTS 服务',
          body: '这里只配置全局语音服务与凭证；林埃自己的 Voice ID 仍在“关于林埃”里编辑。',
        ),
        const SizedBox(height: 20),
        if (_provider == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          _SettingsSurface(
            child: Column(
              children: [
                _ChoiceRow(
                  title: 'ElevenLabs',
                  subtitle: '使用 ElevenLabs API 生成语音',
                  selected: _provider == 'elevenlabs',
                  onTap: () => _selectProvider('elevenlabs'),
                ),
                const Divider(),
                _ChoiceRow(
                  title: 'MiniMax',
                  subtitle: '使用 MiniMax 语音服务',
                  selected: _provider == 'minimax',
                  onTap: () => _selectProvider('minimax'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSurface(
            child: Column(
              children: [
                if (_provider == 'elevenlabs')
                  TextField(
                    controller: _elevenLabsController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'ElevenLabs API Key'),
                  )
                else ...[
                  TextField(
                    controller: _miniMaxController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'MiniMax API Key'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _miniMaxGroupController,
                    decoration:
                        const InputDecoration(labelText: 'MiniMax Group ID'),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class ProactiveCompanionshipSettingsPage extends StatefulWidget {
  const ProactiveCompanionshipSettingsPage({super.key});

  @override
  State<ProactiveCompanionshipSettingsPage> createState() =>
      _ProactiveCompanionshipSettingsPageState();
}

class _ProactiveCompanionshipSettingsPageState
    extends State<ProactiveCompanionshipSettingsPage> {
  bool? _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    CheckinService.instance.isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _setEnabled(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    await CheckinService.instance.setEnabled(value);
    if (value) {
      await CheckinService.instance.ensureCheckinTaskRegistered();
      await ProactiveOutingService.instance.refreshSchedule();
    } else {
      await CheckinService.instance.cancelCheckinTask();
      await ProactiveOutingService.instance.cancelPendingCheckpoints();
    }
    if (!mounted) return;
    setState(() {
      _enabled = value;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '主动陪伴',
      children: [
        const _PageIntro(
          title: '让林埃在合适时机主动出现',
          body: '开启后，林埃可以根据日程、节律和已确认的提醒主动发来消息；关闭后会取消待执行的主动检查。',
        ),
        const SizedBox(height: 20),
        _SettingsSurface(
          child: _enabled == null
              ? const SizedBox(
                  height: 52,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许主动联系'),
                  subtitle: Text(_enabled! ? '已开启' : '已关闭'),
                  value: _enabled!,
                  onChanged: _saving ? null : _setEnabled,
                ),
        ),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static final Uri _policyUri = Uri.parse(
    'https://github.com/memex-lab/memex/blob/main/PRIVACY_POLICY.md',
  );

  @override
  Widget build(BuildContext context) {
    return _DetailPage(
      title: '隐私政策',
      children: [
        const _PageIntro(
          title: '本地优先',
          body: '你的聊天、记忆和生活数据默认保存在本机。只有你明确配置并使用的模型、同步或外部服务才会接收完成该功能所需的数据。',
        ),
        const SizedBox(height: 20),
        const _SettingsSurface(
          child: Column(
            children: [
              _AppearanceRow(
                icon: Icons.storage_outlined,
                title: '本机数据',
                subtitle: '应用数据、记忆与附件由你控制',
              ),
              Divider(),
              _AppearanceRow(
                icon: Icons.cloud_outlined,
                title: '外部服务',
                subtitle: '仅在你配置并调用时传输必要内容',
              ),
              Divider(),
              _AppearanceRow(
                icon: Icons.lock_outline_rounded,
                title: '备份与同步',
                subtitle: '加密同步由你主动开启并保管口令',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSurface(
          child: _ActionRow(
            icon: Icons.open_in_new_rounded,
            title: '查看完整隐私政策',
            subtitle: '在浏览器中打开当前政策文档',
            onTap: () => launchUrl(
              _policyUri,
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SpringRainUiScope(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Container(
      padding: EdgeInsets.all(tokens.space16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radius18),
        border: Border.all(color: tokens.divider),
      ),
      child: child,
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: AnimatedContainer(
        duration: SpringRainUiTokens.motionFast,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? tokens.accent : Colors.transparent,
          border: Border.all(color: selected ? tokens.accent : tokens.outline),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 15, color: tokens.textOnAccent)
            : null,
      ),
      onTap: onTap,
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.accentSoft,
          borderRadius: BorderRadius.circular(tokens.radius14),
        ),
        child: Icon(icon, size: 20, color: tokens.accent),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing:
          onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tokens.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

void _showSaved(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
