import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/domain/models/settings_item.dart';
import 'package:memex/ui/settings/widgets/personal_center_detail_pages.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/settings/widgets/data_storage_page.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/ui/settings/widgets/image_generation_settings_page.dart';
import 'package:memex/utils/user_storage.dart';

/// Settings registry. Maintains a static list of all searchable settings items.
/// Organized by feature module, extensible for new entries.
class SettingsRegistry {
  SettingsRegistry._();

  /// All registered settings items.
  /// Uses getters so l10n strings resolve to the current locale at access time.
  static List<SettingsItem> get allItems => [
        ..._personalCenterItems,
        ..._settingsPageItems,
      ];

  // ---------------------------------------------------------------------------
  // PersonalCenterScreen level items
  // ---------------------------------------------------------------------------

  static List<SettingsItem> get _personalCenterItems => [
        SettingsItem(
          id: 'personal.ai_models',
          titleGetter: () => 'AI 与模型',
          descriptionGetter: () => '任务模型、模型服务与图片生成',
          keywords: const [
            'AI',
            '模型',
            '聊天',
            '记忆整理',
            '日程分析',
            '内容分析',
            '游戏',
            'API',
            '图片生成',
            'model',
            'llm',
            'provider',
          ],
          icon: Icons.auto_awesome_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PersonalCenterScreen(
              initialSection: PersonalCenterSection.ai,
            ),
          ),
          parentPathGetter: () => [UserStorage.l10n.personalCenter],
        ),
        SettingsItem(
          id: 'personal.image_generation',
          titleGetter: () => '图片生成',
          descriptionGetter: () => '通义万相、MiniMax、OpenAI 兼容或本地 ComfyUI',
          keywords: const [
            '图片生成',
            '绘图',
            '通义万相',
            'MiniMax',
            'ComfyUI',
            'OpenAI image',
            'image generation',
          ],
          icon: Icons.palette_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const ImageGenerationSettingsPage(),
          ),
          parentPathGetter: () => [
            UserStorage.l10n.personalCenter,
            'AI 与模型',
          ],
        ),
        SettingsItem(
          id: 'personal.voice_interaction',
          titleGetter: () => '声音与互动',
          descriptionGetter: () => '语音输入、播放与主动陪伴',
          keywords: const [
            '语音',
            'ASR',
            'TTS',
            '麦克风',
            '媒体键',
            '主动陪伴',
            'voice',
          ],
          icon: Icons.graphic_eq_rounded,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PersonalCenterScreen(
              initialSection: PersonalCenterSection.voice,
            ),
          ),
          parentPathGetter: () => [UserStorage.l10n.personalCenter],
        ),
        SettingsItem(
          id: 'personal.devices_connections',
          titleGetter: () => '设备与连接',
          descriptionGetter: () => '系统权限、位置与外部服务',
          keywords: const [
            '权限',
            '定位',
            '位置',
            'COROS',
            '小红书',
            '购物',
            '玩具',
            '专注',
            'permission',
            'location',
            'device',
            'connection',
          ],
          icon: Icons.devices_other_rounded,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PersonalCenterScreen(
              initialSection: PersonalCenterSection.connections,
            ),
          ),
          parentPathGetter: () => [UserStorage.l10n.personalCenter],
        ),
        SettingsItem(
          id: 'personal.data_security',
          titleGetter: () => '数据与安全',
          descriptionGetter: () => '备份、同步、存储与隐私',
          keywords: const [
            '备份',
            '恢复',
            '同步',
            '迁移',
            '导出',
            '存储',
            '应用锁',
            '隐私',
            'backup',
            'sync',
            'export',
            'storage',
            'privacy',
            'security',
          ],
          icon: Icons.shield_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PersonalCenterScreen(
              initialSection: PersonalCenterSection.data,
            ),
          ),
          parentPathGetter: () => [UserStorage.l10n.personalCenter],
        ),
        SettingsItem(
          id: 'personal.app_settings',
          titleGetter: () => '应用设置',
          descriptionGetter: () => '语言、外观、更新与版本',
          keywords: const [
            '语言',
            '外观',
            '主题',
            '更新',
            '版本',
            '许可',
            'settings',
            'theme',
          ],
          icon: Icons.tune_rounded,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PersonalCenterScreen(
              initialSection: PersonalCenterSection.app,
            ),
          ),
          parentPathGetter: () => [UserStorage.l10n.personalCenter],
        ),
        SettingsItem(
          id: 'personal.advanced',
          titleGetter: () => '开发与诊断',
          descriptionGetter: () => 'Dev Room、用量、异步任务、日志与索引',
          keywords: const [
            '开发',
            '诊断',
            'Dev Room',
            '日志',
            '索引',
            '模型用量',
            '异步任务',
            'developer',
            'debug',
            'logs',
            'index',
          ],
          icon: Icons.construction_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PersonalCenterScreen(
              initialSection: PersonalCenterSection.advanced,
            ),
          ),
          parentPathGetter: () => [UserStorage.l10n.personalCenter],
        ),
      ];

  // ---------------------------------------------------------------------------
  // SettingsPage level items
  // ---------------------------------------------------------------------------

  static List<SettingsItem> get _settingsPageItems => [
        SettingsItem(
          id: 'settings.language',
          titleGetter: () => UserStorage.l10n.languageSettings,
          descriptionGetter: () => UserStorage.l10n.languageSettingsDesc,
          keywords: const [
            '语言',
            '中文',
            '英文',
            '切换语言',
            '界面语言',
            '翻译',
            'language',
            'english',
            'chinese',
            'locale',
            'switch language',
            'i18n',
          ],
          icon: Icons.language,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const LanguageSettingsPage(),
          ),
          parentPathGetter: () =>
              [UserStorage.l10n.personalCenter, UserStorage.l10n.settings],
        ),
        if (Platform.isAndroid && AppFlavor.isEarly)
          SettingsItem(
            id: 'settings.early_updates',
            titleGetter: () => UserStorage.l10n.earlyUpdateSettingsTitle,
            descriptionGetter: () => UserStorage.l10n.earlyUpdateSettingsDesc,
            keywords: const [
              '更新',
              '自动更新',
              'Early',
              '预发布',
              '内测',
              'APK',
              'GitHub',
              'Wi-Fi',
              'update',
              'auto update',
              'pre-release',
              'prerelease',
              'download',
              'install',
              'wifi',
            ],
            icon: Icons.system_update_alt,
            navigationTarget: NavigationTarget(
              pageBuilder: (_) => const VersionUpdateSettingsPage(),
            ),
            parentPathGetter: () =>
                [UserStorage.l10n.personalCenter, UserStorage.l10n.settings],
          ),
        SettingsItem(
          id: 'settings.data_storage',
          titleGetter: () => UserStorage.l10n.dataStorage,
          descriptionGetter: () => UserStorage.l10n.dataStorageDescriptionIOS,
          keywords: const [
            '存储',
            '数据',
            '路径',
            'iCloud',
            '存储位置',
            '文件',
            '空间',
            '迁移',
            'storage',
            'data',
            'path',
            'icloud',
            'location',
            'file',
            'space',
            'migrate',
          ],
          icon: Icons.folder_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const DataStoragePage(),
          ),
          parentPathGetter: () =>
              [UserStorage.l10n.personalCenter, UserStorage.l10n.settings],
        ),
        SettingsItem(
          id: 'settings.location_context',
          titleGetter: () => UserStorage.l10n.location,
          descriptionGetter: () => UserStorage.l10n.locationContextDescription,
          keywords: const [
            '定位',
            '位置',
            '地理位置',
            '当前位置',
            '逆地理编码',
            '高德',
            'OpenStreetMap',
            'GPS',
            '城市',
            '街区',
            'location',
            'current location',
            'geocoding',
            'reverse geocoding',
            'amap',
            'osm',
            'city',
            'neighborhood',
          ],
          icon: Icons.my_location_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const LocationContextSettingsPage(),
          ),
          parentPathGetter: () =>
              [UserStorage.l10n.personalCenter, UserStorage.l10n.settings],
        ),
        SettingsItem(
          id: 'settings.backup_restore',
          titleGetter: () => UserStorage.l10n.backupAndRestore,
          descriptionGetter: () => UserStorage.l10n.backupDescription,
          keywords: const [
            '备份',
            '恢复',
            '自动备份',
            '快照',
            '时间点',
            '导出',
            '导入',
            '数据迁移',
            '换手机',
            '同步',
            'backup',
            'restore',
            'automatic backup',
            'snapshot',
            'restore point',
            'export',
            'import',
            'migrate',
            'sync',
            'transfer',
          ],
          icon: Icons.backup_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const BackupRestorePage(),
          ),
          parentPathGetter: () =>
              [UserStorage.l10n.personalCenter, UserStorage.l10n.settings],
        ),
        SettingsItem(
          id: 'settings.privacy_policy',
          titleGetter: () => UserStorage.l10n.privacyPolicy,
          descriptionGetter: () => UserStorage.l10n.privacyPolicyDesc,
          keywords: const [
            '隐私',
            '政策',
            '条款',
            '协议',
            '数据安全',
            '用户协议',
            'privacy',
            'policy',
            'terms',
            'agreement',
            'data safety',
          ],
          icon: Icons.privacy_tip_outlined,
          navigationTarget: NavigationTarget(
            pageBuilder: (_) => const PrivacyPolicyPage(),
          ),
          parentPathGetter: () =>
              [UserStorage.l10n.personalCenter, UserStorage.l10n.settings],
        ),
      ];
}
