import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';

import 'package:memex/data/services/sync/config_sync_crypto.dart';
import 'package:memex/data/services/sync/config_sync_passphrase_store.dart';
import 'package:memex/data/services/sync/config_sync_s3.dart';
import 'package:memex/data/services/sync/config_sync_s3_credentials.dart';
import 'package:memex/data/services/sync/config_sync_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';

/// Export/import an encrypted configuration package (LLM configs, personas,
/// prefs). Supports both manual file transport and S3-compatible cloud sync.
class ConfigSyncPage extends StatefulWidget {
  const ConfigSyncPage({super.key});

  @override
  State<ConfigSyncPage> createState() => _ConfigSyncPageState();
}

class _ConfigSyncPageState extends State<ConfigSyncPage> {
  static final Logger _logger = getLogger('ConfigSyncPage');

  final ConfigSyncPassphraseStore _passphraseStore =
      ConfigSyncPassphraseStore.instance;
  final ConfigSyncS3Credentials _s3Store = ConfigSyncS3Credentials.instance;

  bool _hasPassphrase = false;
  bool _hasS3 = false;
  bool _isBusy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final has = await _passphraseStore.hasPassphrase();
    final hasS3 = await _s3Store.hasCredentials();
    if (mounted) setState(() {
      _hasPassphrase = has;
      _hasS3 = hasS3;
    });
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

  // ─── S3 Cloud ───

  Future<void> _configureS3() async {
    final existing = await _s3Store.read();
    final result = await _promptS3Config(existing);
    if (result == null) return;
    await _s3Store.save(result);
    if (mounted) {
      setState(() => _hasS3 = true);
      ToastHelper.showSuccess(context, 'S3 配置已保存');
    }
  }

  Future<S3Config?> _promptS3Config([S3Config? initial]) {
    final epCtl = TextEditingController(text: initial?.endpoint ?? '');
    final bucketCtl = TextEditingController(text: initial?.bucket ?? '');
    final akCtl = TextEditingController(text: initial?.accessKey ?? '');
    final skCtl = TextEditingController(text: initial?.secretKey ?? '');
    final regionCtl = TextEditingController(text: initial?.region ?? '');
    var useSSL = initial?.useSSL ?? true;

    return showDialog<S3Config>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('S3 存储配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '支持 AWS S3、Cloudflare R2、阿里云 OSS、MinIO 等兼容存储。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: epCtl,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint',
                    hintText: 'play.min.io',
                  ),
                ),
                TextField(
                  controller: bucketCtl,
                  decoration: const InputDecoration(
                    labelText: 'Bucket',
                    hintText: 'my-config-backup',
                  ),
                ),
                TextField(
                  controller: akCtl,
                  decoration: const InputDecoration(labelText: 'Access Key'),
                ),
                TextField(
                  controller: skCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Secret Key'),
                ),
                TextField(
                  controller: regionCtl,
                  decoration: const InputDecoration(
                    labelText: 'Region (可选)',
                    hintText: 'us-east-1',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('HTTPS', style: TextStyle(fontSize: 14)),
                  value: useSSL,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setLocal(() => useSSL = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final ep = epCtl.text.trim();
                final bucket = bucketCtl.text.trim();
                final ak = akCtl.text.trim();
                final sk = skCtl.text.trim();
                if (ep.isEmpty || bucket.isEmpty || ak.isEmpty || sk.isEmpty) {
                  return;
                }
                Navigator.pop(context, S3Config(
                  endpoint: ep,
                  bucket: bucket,
                  accessKey: ak,
                  secretKey: sk,
                  region: regionCtl.text.trim().isEmpty
                      ? null
                      : regionCtl.text.trim(),
                  useSSL: useSSL,
                ));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cloudUpload() async {
    if (_isBusy) return;
    final passphrase = await _ensurePassphrase();
    if (passphrase == null) return;
    final s3 = await _s3Store.read();
    if (s3 == null) {
      if (mounted) ToastHelper.showError(context, '请先配置 S3 存储');
      return;
    }

    setState(() { _isBusy = true; _status = '正在加密并上传...'; });
    try {
      final payload = await ConfigSyncService.collectPayload();
      final envelope = await ConfigSyncCrypto.seal(payload, passphrase);
      await ConfigSyncS3.upload(s3, envelope);
      if (!mounted) return;
      setState(() => _status = '');
      ToastHelper.showSuccess(context, '配置已上传到云端');
    } on ConfigSyncS3Exception catch (e) {
      if (mounted) ToastHelper.showError(context, e.message);
    } catch (e, stack) {
      _logger.severe('Cloud upload failed: $e', e, stack);
      if (mounted) ToastHelper.showError(context, '上传失败：$e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _cloudDownload() async {
    if (_isBusy) return;
    final passphrase = await _ensurePassphrase();
    if (passphrase == null) return;
    final s3 = await _s3Store.read();
    if (s3 == null) {
      if (mounted) ToastHelper.showError(context, '请先配置 S3 存储');
      return;
    }

    setState(() { _isBusy = true; _status = '正在从云端下载...'; });
    try {
      final envelope = await ConfigSyncS3.download(s3);
      if (!mounted) return;
      setState(() => _status = '正在解密并导入...');
      final decoded = await ConfigSyncCrypto.open(envelope, passphrase);
      if (decoded is! Map<String, dynamic>) {
        throw const ConfigSyncFormatException('config payload is malformed');
      }
      if (decoded['kind'] != ConfigSyncService.payloadKind) {
        throw const ConfigSyncFormatException('not a here-i-am config package');
      }

      final result = await ConfigSyncService.importFromPayload(decoded);
      if (!mounted) return;
      setState(() => _status = '');
      ToastHelper.showSuccess(
        context,
        '已从云端导入 ${result.settings} 项设置、${result.characters} 个角色、'
        '${result.agentConfigs} 个 agent 配置。重启应用后生效。',
      );
    } on ConfigSyncS3Exception catch (e) {
      if (mounted) ToastHelper.showError(context, e.message);
    } on ConfigSyncDecryptException {
      if (mounted) ToastHelper.showError(context, '口令错误或云端文件已损坏');
    } on ConfigSyncFormatException catch (e) {
      if (mounted) ToastHelper.showError(context, '配置包格式无效：${e.message}');
    } catch (e, stack) {
      _logger.severe('Cloud download failed: $e', e, stack);
      if (mounted) ToastHelper.showError(context, '下载失败：$e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _clearS3() async {
    await _s3Store.clear();
    if (mounted) {
      setState(() => _hasS3 = false);
      ToastHelper.showSuccess(context, 'S3 配置已清除');
    }
  }

  // ─── Build ───

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
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '云同步',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '配置 S3 兼容存储后，可一键把加密配置包推送到云端或从云端拉取。'
            '支持 AWS S3、Cloudflare R2、阿里云 OSS、MinIO 等。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            icon: Icons.cloud_outlined,
            title: 'S3 存储',
            description: _hasS3 ? '已配置。凭据安全存储在设备内。' : '尚未配置。',
            buttonText: _hasS3 ? '修改配置' : '配置',
            onPressed: _isBusy ? null : _configureS3,
            secondaryButtonText: _hasS3 ? '清除' : null,
            onSecondaryPressed: _hasS3 && !_isBusy ? _clearS3 : null,
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            icon: Icons.cloud_upload_outlined,
            title: '上传到云端',
            description: '加密当前配置并推送到 S3，覆盖云端旧版本。',
            buttonText: '上传',
            onPressed: _isBusy || !_hasS3 ? null : _cloudUpload,
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            icon: Icons.cloud_download_outlined,
            title: '从云端下载',
            description: '从 S3 拉取加密配置包并解密导入，覆盖本地配置。导入后请重启。',
            buttonText: '下载',
            onPressed: _isBusy || !_hasS3 ? null : _cloudDownload,
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
    String? secondaryButtonText,
    VoidCallback? onSecondaryPressed,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (secondaryButtonText != null)
                  TextButton(
                    onPressed: onSecondaryPressed,
                    child: Text(secondaryButtonText),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onPressed,
                  child: Text(buttonText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
