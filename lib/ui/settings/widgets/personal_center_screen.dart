import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/media_service.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/app_lock/widgets/app_lock_settings_page.dart';
import 'package:memex/ui/core/widgets/avatar_picker.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/view_models/settings_search_viewmodel.dart';
import 'package:memex/ui/settings/widgets/asr_config_page.dart';
import 'package:memex/ui/settings/widgets/async_task_list_page.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/ui/settings/widgets/config_sync_page.dart';
import 'package:memex/ui/settings/widgets/coros_connect_page.dart';
import 'package:memex/ui/settings/widgets/core_sync_settings_page.dart';
import 'package:memex/ui/settings/widgets/custom_agent_config_page.dart';
import 'package:memex/ui/settings/widgets/data_storage_page.dart';
import 'package:memex/ui/settings/widgets/device_app_blocker_settings_page.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/ui/settings/widgets/companion_share_settings_page.dart';
import 'package:memex/ui/settings/widgets/image_generation_settings_page.dart';
import 'package:memex/ui/settings/widgets/heart_rate_device_settings_page.dart';
import 'package:memex/ui/settings/widgets/log_viewer_page.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/ui/settings/widgets/model_stats_page.dart';
import 'package:memex/ui/settings/widgets/personal_center_detail_pages.dart';
import 'package:memex/ui/settings/widgets/settings_search_screen.dart';
import 'package:memex/ui/settings/widgets/shopping_config_page.dart';
import 'package:memex/ui/settings/widgets/skills_management_page.dart';
import 'package:memex/ui/settings/widgets/system_authorization_page.dart';
import 'package:memex/ui/settings/widgets/task_model_assignment_page.dart';
import 'package:memex/ui/settings/widgets/toy_config_page.dart';
import 'package:memex/ui/settings/widgets/xhs_connect_page.dart';
import 'package:memex/utils/permission_utils.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

enum PersonalCenterSection {
  ai,
  voice,
  connections,
  data,
  app,
  advanced,
}

/// Fixed user/settings entry opened from Chat.
///
/// This screen intentionally does not live inside the Life Space tabs. The
/// header carries user identity; application settings are grouped by purpose
/// on one warm, continuous surface.
class PersonalCenterScreen extends StatefulWidget {
  const PersonalCenterScreen({super.key, this.initialSection});

  final PersonalCenterSection? initialSection;

  @override
  State<PersonalCenterScreen> createState() => _PersonalCenterScreenState();
}

class _PersonalCenterScreenState extends State<PersonalCenterScreen> {
  static const _backgroundAsset = 'assets/images/雨玻璃.jpg';
  static const _warmSurface = SpringRainUiTokens.daylightCanvas;
  static const _warmIcon = SpringRainUiTokens.daylightSurfaceMuted;
  static const _text = SpringRainUiTokens.daylightTextPrimary;
  static const _secondary = SpringRainUiTokens.daylightTextSecondary;
  static const _accent = SpringRainUiTokens.daylightAccent;
  static const _gold = SpringRainUiTokens.daylightGold;
  static const _divider = SpringRainUiTokens.daylightDivider;

  final MemexRouter _router = MemexRouter();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  String? _userId;
  String? _userEmail;
  String? _userAvatar;
  bool _showPermissionBadge = false;
  bool _isClearingData = false;
  bool _isRebuildingIndex = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _checkPermissionBadge();
  }

  Future<void> _loadUserInfo() async {
    final userId = await UserStorage.getUserId();
    final avatar = await _router.getUserAvatar();
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _userEmail = userId == null ? null : '$userId@memex.local';
      _userAvatar = avatar;
    });
  }

  Future<void> _checkPermissionBadge() async {
    final granted = await PermissionUtils.isFitnessPermissionGranted();
    if (mounted) setState(() => _showPermissionBadge = !granted);
  }

  Future<String?> _pickUserAvatarFromGallery() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;
    final pickedPath = await pickAvatarImageFromGallery();
    if (pickedPath == null) return null;
    final imported = await MediaService.instance.importImage(
      userId: userId,
      sourcePath: pickedPath,
    );
    return imported.relativePath;
  }

  Future<void> _changeAvatar() async {
    final picked = await showAvatarPicker(
      context,
      _userAvatar ?? UserStorage.defaultAvatarSeed,
      onPickGallery: _pickUserAvatarFromGallery,
    );
    if (picked == null || !mounted) return;
    await _router.updateUserAvatar(picked);
    final resolved = await _router.getUserAvatar();
    if (mounted) setState(() => _userAvatar = resolved);
  }

  Future<T?> _push<T>(Widget page) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) => SpringRainUiScope(child: page),
      ),
    );
  }

  Future<void> _openSearch() async {
    await _push(
      SettingsSearchScreen(
        viewModel: SettingsSearchViewModel(router: _router),
      ),
    );
  }

  Future<void> _rebuildSearchIndex() async {
    if (_isRebuildingIndex) return;
    setState(() => _isRebuildingIndex = true);
    try {
      await _router.rebuildAllFtsIndexes();
      if (mounted) {
        ToastHelper.showSuccessWithKey(_messengerKey, '搜索索引已重建');
      }
    } catch (_) {
      if (mounted) {
        ToastHelper.showErrorWithKey(_messengerKey, '重建搜索索引失败');
      }
    } finally {
      if (mounted) setState(() => _isRebuildingIndex = false);
    }
  }

  Future<void> _clearLocalData() async {
    if (_isClearingData) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重置本机数据'),
        content: const Text('这会清除本机应用数据，且无法撤销。账号身份与云端副本不会自动删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF98645E),
            ),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isClearingData = true);
    try {
      await _router.clearData();
      if (mounted) ToastHelper.showSuccessWithKey(_messengerKey, '本机数据已清除');
    } catch (_) {
      if (mounted) ToastHelper.showErrorWithKey(_messengerKey, '清除本机数据失败');
    } finally {
      if (mounted) setState(() => _isClearingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialSection = widget.initialSection;
    if (initialSection != null) {
      return ScaffoldMessenger(
        key: _messengerKey,
        child: _buildSectionPage(initialSection),
      );
    }

    return ScaffoldMessenger(
      key: _messengerKey,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: _warmSurface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF243029),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Image.asset(
                  _backgroundAsset,
                  key: const ValueKey('personal_center_rain_glass_background'),
                  width: double.infinity,
                  height: 300,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.25),
                  filterQuality: FilterQuality.high,
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildTopBar(),
                    _buildProfileHeader(),
                    Expanded(child: _buildSettingsSurface()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 10),
          _HeaderCircleButton(
            key: const ValueKey('personal_center_back_button'),
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.maybePop(context),
          ),
          const Expanded(
            child: Text(
              '个人中心',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF8FBF8),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
              ),
            ),
          ),
          _HeaderCircleButton(
            key: const ValueKey('personal_center_search_button'),
            icon: Icons.search_rounded,
            tooltip: '搜索设置',
            onTap: _openSearch,
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return SizedBox(
      key: const ValueKey('personal_center_profile'),
      height: 142,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 22, 26),
        child: Row(
          children: [
            Container(
              width: 66,
              height: 66,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x55F1F6F1),
                border: Border.all(color: const Color(0xB8FFFFFF)),
              ),
              child: ClipOval(
                child: CharacterAvatar(
                  avatar: _userAvatar ?? UserStorage.defaultAvatarSeed,
                  name: _userId ?? '',
                  size: 62,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userId ?? '你的名字',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF8FBF8),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userEmail ?? '账号与本机资料',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xEAF8FBF8),
                      fontSize: 12,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 7)],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('personal_center_edit_profile'),
              onPressed: _changeAvatar,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF8FBF8),
                backgroundColor: const Color(0x593A5146),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('编辑资料'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSurface() {
    final groups = [
      const _HomeSection(
        section: PersonalCenterSection.ai,
        icon: Icons.auto_awesome_outlined,
        title: 'AI 与模型',
        subtitle: '任务模型、服务商与图片生成',
      ),
      const _HomeSection(
        section: PersonalCenterSection.voice,
        icon: Icons.graphic_eq_rounded,
        title: '声音与互动',
        subtitle: '语音输入、播放与主动陪伴',
      ),
      _HomeSection(
        section: PersonalCenterSection.connections,
        icon: Icons.devices_other_rounded,
        title: '设备与连接',
        subtitle: '系统权限、位置与外部服务',
        status: _showPermissionBadge ? '1 项待处理' : null,
        warning: _showPermissionBadge,
      ),
      const _HomeSection(
        section: PersonalCenterSection.data,
        icon: Icons.shield_outlined,
        title: '数据与安全',
        subtitle: '备份、同步、存储与隐私',
      ),
      const _HomeSection(
        section: PersonalCenterSection.app,
        icon: Icons.tune_rounded,
        title: '应用设置',
        subtitle: '语言、外观、更新与版本',
      ),
    ];

    return Container(
      key: const ValueKey('personal_center_warm_surface'),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _warmSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ListView(
        key: const ValueKey('personal_center_settings_list'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '设置',
                style: TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text('按用途整理', style: TextStyle(color: _secondary)),
            ],
          ),
          const SizedBox(height: 8),
          for (final group in groups) _buildHomeRow(group),
          const SizedBox(height: 10),
          InkWell(
            key: const ValueKey('personal_center_advanced'),
            onTap: () => _openSection(PersonalCenterSection.advanced),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.construction_outlined,
                      color: _secondary, size: 19),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '开发与诊断',
                      style: TextStyle(color: _secondary),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _secondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeRow(_HomeSection item) {
    return InkWell(
      key: ValueKey('personal_center_section_${item.section.name}'),
      onTap: () => _openSection(item.section),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _warmIcon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: _accent, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(item.subtitle,
                      style: const TextStyle(color: _secondary)),
                ],
              ),
            ),
            if (item.status != null) ...[
              if (item.warning)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: _gold,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 5),
              Text(
                item.status!,
                style: TextStyle(
                  color: item.warning ? const Color(0xFF9A702E) : _secondary,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right_rounded, color: _secondary),
          ],
        ),
      ),
    );
  }

  void _openSection(PersonalCenterSection section) {
    _push(_buildSectionPage(section)).then((_) {
      if (section == PersonalCenterSection.connections) {
        _checkPermissionBadge();
      }
    });
  }

  Widget _buildSectionPage(PersonalCenterSection section) {
    final data = _sectionData(section);
    return _PersonalSectionPage(
      title: data.title,
      intro: data.intro,
      groups: data.groups,
    );
  }

  _SectionData _sectionData(PersonalCenterSection section) {
    void open(Widget page) => _push(page);

    return switch (section) {
      PersonalCenterSection.ai => _SectionData(
          title: 'AI 与模型',
          intro: '同一套模型分配可以按用途批量调整，也可以按 Agent 精确切换。',
          groups: [
            _DestinationGroup('模型分配', [
              _Destination(
                icon: Icons.account_tree_outlined,
                title: '模型分配',
                subtitle: '按用途批量设置，或按 Agent 精确切换',
                status: '统一入口',
                onTap: () => open(const TaskModelAssignmentPage()),
              ),
            ]),
            _DestinationGroup('模型能力', [
              _Destination(
                icon: Icons.hub_outlined,
                title: '模型服务',
                subtitle: 'API、地址与模型列表',
                onTap: () => open(const ModelConfigListPage()),
              ),
              _Destination(
                icon: Icons.palette_outlined,
                title: '图片生成',
                subtitle: '通义万相、自定义或本地 ComfyUI',
                onTap: () => open(const ImageGenerationSettingsPage()),
              ),
            ]),
          ],
        ),
      PersonalCenterSection.voice => _SectionData(
          title: '声音与互动',
          intro: '这里管理全局语音能力；林埃自己的 Voice ID 仍在“关于林埃”。',
          groups: [
            _DestinationGroup('语音', [
              _Destination(
                icon: Icons.mic_none_rounded,
                title: '语音输入',
                subtitle: '识别服务、麦克风与媒体键',
                onTap: () => open(const AsrConfigPage()),
              ),
              _Destination(
                icon: Icons.volume_up_outlined,
                title: '语音播放',
                subtitle: 'TTS 服务与 API 凭证',
                onTap: () => open(const VoicePlaybackSettingsPage()),
              ),
            ]),
            _DestinationGroup('互动', [
              _Destination(
                icon: Icons.waving_hand_outlined,
                title: '主动陪伴',
                subtitle: '在合适时机主动发来消息',
                onTap: () => open(const ProactiveCompanionshipSettingsPage()),
              ),
            ]),
          ],
        ),
      PersonalCenterSection.connections => _SectionData(
          title: '设备与连接',
          intro: '系统权限、位置能力和外部服务在这里集中查看。',
          groups: [
            _DestinationGroup('系统能力', [
              _Destination(
                icon: Icons.security_outlined,
                title: '系统权限',
                subtitle: '照片、相机、麦克风、日历与通知',
                status: _showPermissionBadge ? '1 项待处理' : null,
                warning: _showPermissionBadge,
                onTap: () => open(const SystemAuthorizationPage()),
              ),
              _Destination(
                icon: Icons.ios_share_rounded,
                title: '交给林埃',
                subtitle: '从其他 App 分享截图或复制的链接',
                onTap: () => open(const CompanionShareSettingsPage()),
              ),
              _Destination(
                icon: Icons.location_on_outlined,
                title: '位置服务',
                subtitle: '位置、地图、天气与路线陪跑',
                onTap: () => open(const LocationContextSettingsPage()),
              ),
              _Destination(
                icon: Icons.do_not_disturb_on_outlined,
                title: '专注与应用限制',
                subtitle: 'Android 设备应用阻止器',
                onTap: () => open(const DeviceAppBlockerSettingsPage()),
              ),
            ]),
            _DestinationGroup('外部连接', [
              _Destination(
                icon: Icons.favorite_outline_rounded,
                title: '实时心率设备',
                subtitle: '标准蓝牙 HRS · 后台持续接收',
                onTap: () => open(const HeartRateDeviceSettingsPage()),
              ),
              _Destination(
                icon: Icons.cloud_sync_outlined,
                title: '林埃核心',
                subtitle: '试验性同步多设备的用户文字消息',
                onTap: () => open(const CoreSyncSettingsPage()),
              ),
              _Destination(
                icon: Icons.watch_outlined,
                title: 'COROS 高驰',
                subtitle: '运动与健康数据',
                onTap: () => open(const CorosConnectPage()),
              ),
              _Destination(
                icon: Icons.bookmark_border_rounded,
                title: '小红书',
                subtitle: '读取你保存的笔记',
                onTap: () => open(const XhsConnectPage()),
              ),
              _Destination(
                icon: Icons.shopping_bag_outlined,
                title: '购物助手',
                subtitle: '预算、付款确认与下单桥接',
                onTap: () => open(const ShoppingConfigPage()),
              ),
              _Destination(
                icon: Icons.toys_outlined,
                title: '玩具控制',
                subtitle: 'Intiface 与蓝牙设备',
                onTap: () => open(const ToyConfigPage()),
              ),
            ]),
          ],
        ),
      PersonalCenterSection.data => _SectionData(
          title: '数据与安全',
          intro: '备份、同步、迁移和可读数据导出使用清晰不同的入口。',
          groups: [
            _DestinationGroup('数据管理', [
              _Destination(
                icon: Icons.backup_outlined,
                title: '完整备份与恢复',
                subtitle: '包含角色头像、背景和本机数据',
                onTap: () => open(const BackupRestorePage()),
              ),
              _Destination(
                icon: Icons.sync_lock_outlined,
                title: '同步与迁移',
                subtitle: '加密配置包、数据快照与 S3',
                onTap: () => open(const ConfigSyncPage()),
              ),
              const _Destination(
                icon: Icons.file_download_outlined,
                title: '导出生活记录',
                subtitle: 'User-truth JSON / CSV',
                status: '待接入',
              ),
              _Destination(
                icon: Icons.folder_outlined,
                title: '数据存储位置',
                subtitle: '本机、自定义目录或 iCloud',
                onTap: () => open(const DataStoragePage()),
              ),
            ]),
            _DestinationGroup('安全', [
              _Destination(
                icon: Icons.lock_outline_rounded,
                title: '应用锁',
                subtitle: '生物识别与离开应用后的锁定',
                onTap: () => open(const AppLockSettingsPage()),
              ),
              _Destination(
                icon: Icons.privacy_tip_outlined,
                title: '隐私政策',
                subtitle: '查看数据与权限说明',
                onTap: () => open(const PrivacyPolicyPage()),
              ),
              const _Destination(
                icon: Icons.person_remove_outlined,
                title: '删除账号与本机数据',
                subtitle: '需要再次确认账号身份',
                status: '待接入',
                danger: true,
              ),
            ]),
          ],
        ),
      PersonalCenterSection.app => _SectionData(
          title: '应用设置',
          intro: '只保留影响整个应用的通用偏好。',
          groups: [
            _DestinationGroup('偏好', [
              _Destination(
                icon: Icons.language_rounded,
                title: '语言',
                subtitle: '界面语言',
                status: '简体中文',
                onTap: () => open(const LanguageSettingsPage()),
              ),
              _Destination(
                icon: Icons.wb_sunny_outlined,
                title: '外观',
                subtitle: '春雨昼眠主题与显示方式',
                status: '春雨昼眠',
                onTap: () => open(const AppearanceSettingsPage()),
              ),
              _Destination(
                icon: Icons.system_update_alt_rounded,
                title: '版本更新',
                subtitle: '检查、下载与安装偏好',
                onTap: () => open(const VersionUpdateSettingsPage()),
              ),
            ]),
            _DestinationGroup('关于', [
              _Destination(
                icon: Icons.info_outline_rounded,
                title: '故我在 V3',
                subtitle: '版本、许可与开源信息',
                status: 'v3-lab',
                onTap: () => open(const AboutHereIamPage()),
              ),
            ]),
          ],
        ),
      PersonalCenterSection.advanced => _SectionData(
          title: '开发与诊断',
          intro: '普通使用不需要进入这一层。',
          groups: [
            _DestinationGroup('开发工具', [
              _Destination(
                icon: Icons.developer_mode_outlined,
                title: 'Dev Room',
                subtitle: '开发任务与运行记录',
                onTap: () => context.push(AppRoutes.devRoom),
              ),
              _Destination(
                icon: Icons.bar_chart_outlined,
                title: '模型用量',
                subtitle: '请求统计与调用详情',
                onTap: () => open(const ModelStatsPage()),
              ),
              _Destination(
                icon: Icons.pending_actions_outlined,
                title: '异步任务',
                subtitle: '后台任务状态',
                onTap: () => open(const AsyncTaskListPage()),
              ),
              _Destination(
                icon: Icons.extension_outlined,
                title: '自定义 Agent',
                subtitle: '非主线的自定义能力',
                onTap: () => open(const CustomAgentConfigPage()),
              ),
              _Destination(
                icon: Icons.folder_special_outlined,
                title: 'Skills',
                subtitle: '本机技能目录与编辑',
                onTap: () => open(const SkillsManagementPage()),
              ),
            ]),
            _DestinationGroup('诊断', [
              _Destination(
                icon: Icons.receipt_long_outlined,
                title: '日志',
                subtitle: '查看本机运行日志',
                onTap: () => open(const LogViewerPage()),
              ),
              _Destination(
                icon: Icons.manage_search_outlined,
                title: '重建搜索索引',
                subtitle: '只在检索结果异常时使用',
                status: _isRebuildingIndex ? '处理中' : null,
                onTap: _isRebuildingIndex ? null : _rebuildSearchIndex,
              ),
              _Destination(
                icon: Icons.delete_sweep_outlined,
                title: '重置本机数据',
                subtitle: '清除前必须再次确认',
                status: _isClearingData ? '处理中' : null,
                danger: true,
                onTap: _isClearingData ? null : _clearLocalData,
              ),
            ]),
          ],
        ),
    };
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x473A5146),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: const Color(0xFFF8FBF8)),
          ),
        ),
      ),
    );
  }
}

class _PersonalSectionPage extends StatelessWidget {
  const _PersonalSectionPage({
    required this.title,
    required this.intro,
    required this.groups,
  });

  final String title;
  final String intro;
  final List<_DestinationGroup> groups;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _PersonalCenterScreenState._warmSurface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF243029),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Image.asset(
                _PersonalCenterScreenState._backgroundAsset,
                width: double.infinity,
                height: 170,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.25),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 58,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        _HeaderCircleButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onTap: () => Navigator.maybePop(context),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFF8FBF8),
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black45, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 54),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      key: ValueKey('personal_center_detail_${title.hashCode}'),
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: _PersonalCenterScreenState._warmSurface,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                        children: [
                          Text(
                            intro,
                            style: const TextStyle(
                              color: _PersonalCenterScreenState._secondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final group in groups) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Text(
                                group.label,
                                style: const TextStyle(
                                  color: _PersonalCenterScreenState._secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            for (final destination in group.destinations)
                              _DestinationRow(destination: destination),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.destination});

  final _Destination destination;

  @override
  Widget build(BuildContext context) {
    final enabled = destination.onTap != null;
    return InkWell(
      onTap: destination.onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _PersonalCenterScreenState._divider),
          ),
        ),
        child: Row(
          children: [
            Icon(
              destination.icon,
              size: 21,
              color: destination.danger
                  ? const Color(0xFF98645E)
                  : enabled
                      ? _PersonalCenterScreenState._accent
                      : _PersonalCenterScreenState._secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.title,
                    style: TextStyle(
                      color: destination.danger
                          ? const Color(0xFF98645E)
                          : _PersonalCenterScreenState._text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destination.subtitle,
                    style: const TextStyle(
                      color: _PersonalCenterScreenState._secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (destination.warning)
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: SizedBox.square(
                  dimension: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _PersonalCenterScreenState._gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            if (destination.status != null)
              Text(
                destination.status!,
                style: TextStyle(
                  color: destination.warning
                      ? const Color(0xFF9A702E)
                      : _PersonalCenterScreenState._secondary,
                  fontSize: 11,
                ),
              ),
            if (enabled) ...[
              const SizedBox(width: 3),
              const Icon(
                Icons.chevron_right_rounded,
                color: _PersonalCenterScreenState._secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeSection {
  const _HomeSection({
    required this.section,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.status,
    this.warning = false,
  });

  final PersonalCenterSection section;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? status;
  final bool warning;
}

class _SectionData {
  const _SectionData({
    required this.title,
    required this.intro,
    required this.groups,
  });

  final String title;
  final String intro;
  final List<_DestinationGroup> groups;
}

class _DestinationGroup {
  const _DestinationGroup(this.label, this.destinations);

  final String label;
  final List<_Destination> destinations;
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.status,
    this.warning = false,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? status;
  final bool warning;
  final bool danger;
  final VoidCallback? onTap;
}
