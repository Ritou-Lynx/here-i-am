import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/themes/here_iam_theme_controller.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/ui/settings/widgets/shopping_config_page.dart';
import 'package:memex/ui/settings/widgets/toy_config_page.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/ui/settings/widgets/coros_connect_page.dart';
import 'package:memex/ui/settings/widgets/xhs_connect_page.dart';
import 'package:memex/data/services/reading/xhs/xhs_cookie_repository.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/ui/settings/widgets/data_storage_page.dart';
import 'package:memex/ui/settings/widgets/device_app_blocker_settings_page.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/ui/settings/widgets/early_update_settings_card.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/main.dart' show rootShellKey;
import 'package:memex/domain/models/llm_config.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentLang = 'en';
  bool _corosConnected = false;
  bool _checkinEnabled = false;
  final _elevenLabsApiKeyController = TextEditingController();
  final _miniMaxApiKeyController = TextEditingController();
  final _miniMaxGroupIdController = TextEditingController();
  String _ttsProvider = 'elevenlabs';
  String _imageGenProvider = 'tongyi_wanxiang';
  String? _imageGenLlmConfigKey;
  List<LLMConfig> _llmConfigs = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final locale = await UserStorage.getLocale();
    final userId = await UserStorage.getUserId();
    var corosConnected = false;
    if (userId != null) {
      corosConnected = await McpTokenStorage(userId: userId).hasToken();
      _checkinEnabled = await CheckinService.instance.isEnabled();
      final apiKey = await UserStorage.getElevenLabsApiKey();
      if (apiKey != null) {
        _elevenLabsApiKeyController.text = apiKey;
      }
      final ttsProvider = await UserStorage.getTtsProvider();
      final miniMaxApiKey = await UserStorage.getMiniMaxApiKey();
      final miniMaxGroupId = await UserStorage.getMiniMaxGroupId();
      if (miniMaxApiKey != null) _miniMaxApiKeyController.text = miniMaxApiKey;
      if (miniMaxGroupId != null) {
        _miniMaxGroupIdController.text = miniMaxGroupId;
      }
      if (mounted) setState(() => _ttsProvider = ttsProvider);
      final imageGenProvider = await UserStorage.getImageGenProvider();
      final imageGenLlmConfigKey = await UserStorage.getImageGenLlmConfigKey();
      final llmConfigs = await UserStorage.getLLMConfigs();
      if (mounted) {
        setState(() {
          _imageGenProvider = imageGenProvider;
          _imageGenLlmConfigKey = imageGenLlmConfigKey;
          _llmConfigs = llmConfigs;
        });
      }
    }
    if (mounted) {
      setState(() {
        _currentLang = locale.languageCode == 'zh' ? 'zh' : 'en';
        _corosConnected = corosConnected;
      });
    }
  }

  Future<bool> _refreshCorosConnectionStatus() async {
    final userId = await UserStorage.getUserId();
    final connected = userId != null
        ? await McpTokenStorage(userId: userId).hasToken()
        : false;
    if (mounted) {
      setState(() => _corosConnected = connected);
    }
    return connected;
  }

  Future<void> _changeLanguage(String langCode) async {
    if (_currentLang == langCode) return;
    final locale = Locale(langCode);
    await UserStorage.setLocale(locale);
    await UserStorage.initL10n();
    if (mounted) {
      setState(() => _currentLang = langCode);
    }
  }

  Future<void> _saveElevenLabsApiKey() async {
    final key = _elevenLabsApiKeyController.text.trim();
    await UserStorage.setElevenLabsApiKey(key);
  }

  Future<void> _setTtsProvider(String provider) async {
    setState(() => _ttsProvider = provider);
    await UserStorage.setTtsProvider(provider);
  }

  Future<void> _setImageGenProvider(String provider) async {
    setState(() => _imageGenProvider = provider);
    await UserStorage.setImageGenProvider(provider);
  }

  Future<void> _setImageGenLlmConfigKey(String configKey) async {
    setState(() => _imageGenLlmConfigKey = configKey);
    await UserStorage.setImageGenLlmConfigKey(configKey);
  }

  Future<void> _saveMiniMaxApiKey() async {
    await UserStorage.setMiniMaxApiKey(_miniMaxApiKeyController.text.trim());
  }

  Future<void> _saveMiniMaxGroupId() async {
    await UserStorage.setMiniMaxGroupId(_miniMaxGroupIdController.text.trim());
  }

  @override
  void dispose() {
    _elevenLabsApiKeyController.dispose();
    _miniMaxApiKeyController.dispose();
    _miniMaxGroupIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(UserStorage.l10n.settings),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Language
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textSecondary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.language, color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.languageSettings,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.languageSettingsDesc,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildLangChip('English', 'en'),
                    const SizedBox(width: 10),
                    _buildLangChip('中文', 'zh'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildVisualThemeCard(),
          const SizedBox(height: 16),
          // TTS 语音
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textSecondary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.record_voice_over_outlined,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TTS 语音',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '为角色对话启用语音播放，在角色设置中填写 Voice ID',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Provider selector
                Row(
                  children: [
                    _ttsProviderChip('ElevenLabs', 'elevenlabs'),
                    const SizedBox(width: 8),
                    _ttsProviderChip('MiniMax', 'minimax'),
                  ],
                ),
                const SizedBox(height: 16),
                if (_ttsProvider == 'elevenlabs') ...[
                  TextField(
                    controller: _elevenLabsApiKeyController,
                    obscureText: true,
                    onChanged: (_) => _saveElevenLabsApiKey(),
                    decoration: InputDecoration(
                      hintText: 'ElevenLabs API Key',
                      hintStyle:
                          TextStyle(fontSize: 14, color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _miniMaxApiKeyController,
                    obscureText: true,
                    onChanged: (_) => _saveMiniMaxApiKey(),
                    decoration: InputDecoration(
                      hintText: 'MiniMax API Key',
                      hintStyle:
                          TextStyle(fontSize: 14, color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _miniMaxGroupIdController,
                    onChanged: (_) => _saveMiniMaxGroupId(),
                    decoration: InputDecoration(
                      hintText: 'MiniMax Group ID',
                      hintStyle:
                          TextStyle(fontSize: 14, color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Image Generation ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.image_outlined,
                        size: 20, color: AppColors.textPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '图片生成',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '在角色对话中启用 AI 图像生成，复用已有 API key',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _imageGenProviderChip('通义万相', 'tongyi_wanxiang'),
                    _imageGenProviderChip('MiniMax', 'minimax'),
                    _imageGenProviderChip('自定义', 'openai_compatible'),
                  ],
                ),
                if (_imageGenProvider == 'openai_compatible') ...[
                  const SizedBox(height: 12),
                  _buildLlmConfigSelector(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (Platform.isAndroid && AppFlavor.isEarly) ...[
            EarlyUpdateSettingsCard(),
            const SizedBox(height: 16),
          ],
          // Data Storage (iOS only — Android has no storage options to choose)
          if (Platform.isIOS) ...[
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DataStoragePage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textSecondary.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              UserStorage.l10n.dataStorage,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              UserStorage.l10n.dataStorageDescriptionIOS,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LocationContextSettingsPage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.location,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.locationContextDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Backup & Restore
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BackupRestorePage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.backup_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.backupAndRestore,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.backupDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // COROS Connect
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final connected = await _refreshCorosConnectionStatus();
                if (!context.mounted) return;
                await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CorosConnectPage(
                      initiallyConnected: connected,
                    ),
                  ),
                );
                if (mounted) {
                  await _refreshCorosConnectionStatus();
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.watch_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'COROS 高驰',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _corosConnected ? '已连接' : '连接手表获取运动数据',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  _corosConnected ? Colors.green : Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_corosConnected)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.check_circle,
                            color: Colors.green, size: 20),
                      ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 小红书 Connect (Reading Companion)
          ValueListenableBuilder<bool>(
            valueListenable: XhsCookieRepository.instance.isLoggedIn,
            builder: (context, xhsConnected, _) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    if (xhsConnected) {
                      // Offer disconnect when already connected.
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('断开小红书连接'),
                          content: const Text('断开后 TA 将无法在后台抓取你存的小红书笔记。要继续吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('断开'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await XhsCookieRepository.instance.clear();
                      }
                      return;
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const XhsConnectPage(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.textSecondary.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bookmark_border_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '小红书',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                xhsConnected
                                    ? '已连接 · TA 可以替你打开收藏的笔记'
                                    : '连接账号后 TA 才能打开你存的笔记',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      xhsConnected ? Colors.green : Colors.grey,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (xhsConnected)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.check_circle,
                                color: Colors.green, size: 20),
                          ),
                        const Icon(Icons.chevron_right,
                            color: Color(0xFFCBD5E1)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Shopping assistant config
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ShoppingConfigPage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        color: AppColors.primary, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '购物助手',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '配置预算、付款确认和自动下单桥接',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (Platform.isAndroid) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const DeviceAppBlockerSettingsPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textSecondary.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.app_blocking_outlined,
                          color: AppColors.primary, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Device App Blocker',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Allow companions to use Android focus lock when you authorize it',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Toy control config
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ToyConfigPage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.vibration, color: AppColors.primary, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '玩具控制',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '接入 Lovense，让 AI 角色在对话中直接控制玩具',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Agent Check-in Toggle
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textSecondary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active_outlined,
                              color: AppColors.primary, size: 22),
                          const SizedBox(width: 12),
                          const Text(
                            '主动推送',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _checkinEnabled ? '已开启' : 'AI 会在合适时机主动推送消息',
                        style: TextStyle(
                          fontSize: 13,
                          color: _checkinEnabled ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _checkinEnabled,
                  onChanged: (v) async {
                    await CheckinService.instance.setEnabled(v);
                    if (v) {
                      await CheckinService.instance
                          .ensureCheckinTaskRegistered();
                    } else {
                      await CheckinService.instance.cancelCheckinTask();
                    }
                    setState(() => _checkinEnabled = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Privacy Policy
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                launchUrl(
                  Uri.parse(
                    'https://github.com/memex-lab/memex/blob/main/PRIVACY_POLICY.md',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.privacyPolicy,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.privacyPolicyDesc,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new,
                      color: Color(0xFFCBD5E1),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Delete Account
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showDeleteAccountDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_forever_outlined,
                      color: Colors.red,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserStorage.l10n.deleteAccount,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            UserStorage.l10n.deleteAccountDesc,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final l10n = UserStorage.l10n;
    final userId = await UserStorage.getUserId() ?? '';
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMatch = controller.text == userId;
            final showError = controller.text.isNotEmpty && !isMatch;
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text(l10n.deleteAccountConfirmTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.deleteAccountConfirmMessage),
                  const SizedBox(height: 16),
                  Text(
                    l10n.deleteAccountTypeName(userId),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: l10n.deleteAccountTypeHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText:
                          showError ? l10n.deleteAccountTypeName(userId) : null,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(UserStorage.l10n.cancel),
                ),
                TextButton(
                  onPressed:
                      isMatch ? () => Navigator.pop(context, true) : null,
                  child: Text(
                    l10n.deleteAccount,
                    style: TextStyle(color: isMatch ? Colors.red : Colors.grey),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    // Perform deletion
    try {
      // 1. Stop background services that use the database
      LocalTaskExecutor.instance.stop();
      await EventBusService.instance.disconnect();

      // 2. Close and delete database
      if (AppDatabase.isInitialized) {
        await AppDatabase.instance.close();
      }

      // 3. Delete workspace files
      try {
        final dataRoot = FileSystemService.instance.dataRoot;
        final dir = Directory(dataRoot);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // workspace may not exist
      }

      // 4. Clear all SharedPreferences
      await UserStorage.clearAllData();

      // 5. Navigate back to home and let RootShell re-check user state
      if (mounted) {
        // Pop settings page first so we're back at the main screen
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Then tell RootShell to re-check — it will find no user and show setup
        rootShellKey.currentState?.resetAndRecheck();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserStorage.l10n.operationFailed('$e'))),
        );
      }
    }
  }

  Widget _ttsProviderChip(String label, String provider) {
    final isSelected = _ttsProvider == provider;
    return GestureDetector(
      onTap: () => _setTtsProvider(provider),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualThemeCard() {
    final themeController = context.watch<HereIamThemeController>();
    final selectedId = themeController.tokens.id;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.textSecondary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '视觉主题',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '切换聊天窗口的玫瑰雾 / 暮雨玫瑰视觉效果',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildThemeChip(
                tokens: HereIamThemeTokens.duskyRoseRain,
                selectedId: selectedId,
                onTap: themeController.selectTheme,
              ),
              _buildThemeChip(
                tokens: HereIamThemeTokens.roseMistDay,
                selectedId: selectedId,
                onTap: themeController.selectTheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeChip({
    required HereIamThemeTokens tokens,
    required String selectedId,
    required ValueChanged<String> onTap,
  }) {
    final isSelected = selectedId == tokens.id;
    return GestureDetector(
      onTap: () => onTap(tokens.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? tokens.accent : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    tokens.background,
                    tokens.surface,
                    tokens.accentSoft,
                  ],
                ),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tokens.nameZh,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? (tokens.brightness == Brightness.dark
                        ? tokens.background
                        : Colors.white)
                    : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLangChip(String label, String langCode) {
    final isSelected = _currentLang == langCode;
    return GestureDetector(
      onTap: () => _changeLanguage(langCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildLlmConfigSelector() {
    if (_llmConfigs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '请先在模型配置中添加一个 OpenAI 兼容的模型配置',
          style: TextStyle(fontSize: 13, color: Colors.orange[700]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择模型配置：',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          DropdownButton<String>(
            value: _imageGenLlmConfigKey,
            isExpanded: true,
            hint: const Text('选择一个模型配置'),
            items: _llmConfigs.map((config) {
              return DropdownMenuItem(
                value: config.key,
                child: Text(
                  '${config.key} (${config.modelId})',
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                _setImageGenLlmConfigKey(value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _imageGenProviderChip(String label, String provider) {
    final isSelected = _imageGenProvider == provider;
    return GestureDetector(
      onTap: () => _setImageGenProvider(provider),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}
