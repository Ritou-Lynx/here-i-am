import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';

import 'package:memex/data/services/sync/config_sync_crypto.dart';
import 'package:memex/data/services/sync/config_sync_passphrase_store.dart';
import 'package:memex/data/services/sync/config_sync_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';

/// Export/import an encrypted configuration package (LLM configs, personas,
/// prefs). Step one of config cloud sync: a manual export/import closed loop.
class ConfigSyncPage extends StatefulWidget {
  const ConfigSyncPage({super.key});

  @override
  State<ConfigSyncPage> createState() => _ConfigSyncPageState();
}

class _ConfigSyncPageState extends State<ConfigSyncPage> {
  static final Logger _logger = getLogger('ConfigSyncPage');

  final ConfigSyncPassphraseStore _passphraseStore =
      ConfigSyncPassphraseStore.instance;

  bool _hasPassphrase = false;
  bool _isBusy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final has = await _passphraseStore.hasPassphrase();
    if (mounted) setState(() => _hasPassphrase = has);
  }

  /// Ensure a passphrase exists, prompting to set one if needed.
  /// Returns the passphrase, or null if the user cancelled.
  Future<String?> _ensurePassphrase() async {
    final existing = await _passphraseStore.read();
    if (existing != null) return existing;
    final entered = await _promptSetPassphrase();
    if (entered == null) return null;
    await _passphraseStore.save(entered);
    if (mounted) setState(() => _hasPassphrase = true);
    return entered;
  }

  /// Prompt the user to create a sync passphrase (with confirmation).
  Future<String?> _promptSetPassphrase() {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('设置同步口令'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '这个口令是解密配置包的唯一钥匙，请牢记。'
                  '忘记后无法恢复，至少 ${ConfigSyncCrypto.minPassphraseLength} 位。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '口令'),
                ),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '再输一次',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final p = controller.text;
                  if (p.length < ConfigSyncCrypto.minPassphraseLength) {
                    setLocal(() => error =
                        '至少 ${ConfigSyncCrypto.minPassphraseLength} 位');
                    return;
                  }
                  if (p != confirmController.text) {
                    setLocal(() => error = '两次输入不一致');
                    return;
                  }
                  Navigator.pop(context, p);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Prompt for a passphrase to open an imported package.
  Future<String?> _promptEnterPassphrase() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入口令'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: '配置包的口令'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    if (_isBusy) return;
    final passphrase = await _ensurePassphrase();
    if (passphrase == null) return;

    setState(() {
      _isBusy = true;
      _status = '正在打包配置...';
    });
    try {
      final packagePath =
          await ConfigSyncService.exportPackage(passphrase: passphrase);
      if (!mounted) return;
      setState(() => _status = '');

      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(packagePath)],
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : const Rect.fromLTWH(0, 0, 100, 100),
      );
    } catch (e, stack) {
      _logger.severe('Config export failed: $e', e, stack);
      if (mounted) ToastHelper.showError(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _import() async {
    if (_isBusy) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!ConfigSyncService.isConfigPackageFile(path)) {
      if (mounted) {
        ToastHelper.showError(
          context,
          '请选择 ${ConfigSyncService.fileExtension} 配置包',
        );
      }
      return;
    }

    final passphrase = await _promptEnterPassphrase();
    if (passphrase == null || passphrase.isEmpty) return;

    setState(() {
      _isBusy = true;
      _status = '正在导入配置...';
    });
    try {
      final result = await ConfigSyncService.importPackage(
        packagePath: path,
        passphrase: passphrase,
      );
      if (!mounted) return;
      setState(() => _status = '');
      ToastHelper.showSuccess(
        context,
        '已导入 ${result.settings} 项设置、${result.characters} 个角色、'
        '${result.agentConfigs} 个 agent 配置。重启应用后生效。',
      );
    } on ConfigSyncDecryptException {
      if (mounted) ToastHelper.showError(context, '口令错误或文件已损坏');
    } on ConfigSyncFormatException catch (e) {
      if (mounted) ToastHelper.showError(context, '配置包格式无效：${e.message}');
    } catch (e, stack) {
      _logger.severe('Config import failed: $e', e, stack);
      if (mounted) ToastHelper.showError(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _changePassphrase() async {
    final entered = await _promptSetPassphrase();
    if (entered == null) return;
    await _passphraseStore.save(entered);
    if (mounted) {
      setState(() => _hasPassphrase = true);
      ToastHelper.showSuccess(context, '口令已更新');
    }
  }

  @override
  Widget build(BuildContext context) => _buildScaffold(context);

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置同步'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '把 LLM 配置、人设和偏好设置打包成一个加密文件，'
            '换设备或重装后导入即可恢复。聊天记录和记忆不在此列（属于数据同步）。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          _buildActionCard(
            icon: Icons.lock_outline,
            title: '同步口令',
            description: _hasPassphrase
                ? '已设置。这是解密配置包的唯一钥匙，忘记无法恢复。'
                : '尚未设置。首次导出时会要求设置。',
            buttonText: _hasPassphrase ? '更换口令' : '设置口令',
            onPressed: _isBusy ? null : _changePassphrase,
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            icon: Icons.upload_file_outlined,
            title: '导出加密配置包',
            description: '生成 ${ConfigSyncService.fileExtension} 文件，'
                '可分享到网盘、AirDrop 或本地保存。',
            buttonText: '导出',
            onPressed: _isBusy ? null : _export,
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            icon: Icons.download_outlined,
            title: '从配置包导入',
            description: '选择一个 ${ConfigSyncService.fileExtension} 文件并输入口令，'
                '覆盖当前配置。导入后请重启应用。',
            buttonText: '导入',
            onPressed: _isBusy ? null : _import,
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(_status),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback? onPressed,
  }) {
    return Card(
      elevation: 0,
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
