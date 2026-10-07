import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/personal_data_hub/core_domain_workflow.dart';
import 'package:memex/data/services/sync/core_sync_runtime_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/widgets/sleep_takeover_debug_page.dart';
import 'package:memex/utils/toast_helper.dart';

class CoreSyncSettingsPage extends StatefulWidget {
  const CoreSyncSettingsPage({super.key, this.domainWorkflow});

  final CoreDomainWorkflow? domainWorkflow;

  @override
  State<CoreSyncSettingsPage> createState() => _CoreSyncSettingsPageState();
}

class _CoreSyncSettingsPageState extends State<CoreSyncSettingsPage> {
  final _runtime = CoreSyncRuntimeService.instance;
  final _urlController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;
  late final CoreDomainWorkflow _domainWorkflow;
  CoreDomainWorkflowStatus? _domainStatus;

  @override
  void initState() {
    super.initState();
    _domainWorkflow =
        widget.domainWorkflow ?? CoreDomainWorkflowService.production();
    _runtime.addListener(_onStatusChanged);
    _runtime.refreshStatus();
    _refreshDomainStatus();
  }

  @override
  void dispose() {
    _runtime.removeListener(_onStatusChanged);
    _urlController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (mounted) setState(() {});
    _refreshDomainStatus();
  }

  Future<void> _refreshDomainStatus() async {
    try {
      final status = await _domainWorkflow.readStatus();
      if (mounted) setState(() => _domainStatus = status);
    } catch (_) {
      if (mounted) setState(() => _domainStatus = null);
    }
  }

  Future<String?> _jsonDialog({
    required String title,
    required String label,
    required String action,
    bool secret = false,
    String? explanation,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (explanation != null) ...[
                Text(explanation),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                obscureText: secret,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: secret ? 1 : 9,
                decoration: InputDecoration(labelText: label),
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
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _runDomainAction(
      Future<String?> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final detail = await action();
      if (mounted) {
        ToastHelper.showSuccess(
            context, detail == null ? success : '$success；$detail');
      }
    } on CoreDomainWorkflowFailure catch (error) {
      if (mounted) ToastHelper.showError(context, error.message);
    } catch (_) {
      if (mounted) ToastHelper.showError(context, '操作未完整结束，请刷新状态后重试');
    } finally {
      await _refreshDomainStatus();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importDomainGrant() async {
    final source = await _jsonDialog(
      title: '导入领域授权',
      label: '受保护的授权 JSON',
      action: '导入并重建运行时',
      secret: true,
      explanation: '只接受核心所有者工具导出的授权文件。内容包含独立凭据，导入成功后会尝试清空剪贴板，且不会在页面或日志中显示。',
    );
    if (source == null || source.trim().isEmpty) return;
    await _runDomainAction(() async {
      final result = await _domainWorkflow.importGrant(source);
      try {
        if ((await Clipboard.getData(Clipboard.kTextPlain))?.text == source) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        // The grant is already in secure storage; never echo clipboard errors
        // or authorization material into logs or UI diagnostics.
      }
      if (result.routeBindingBlocked) return '既有核心路由保持原绑定并已暂停';
      return result.rotated ? '凭据已轮换' : null;
    }, '领域授权已导入');
  }

  Future<void> _copyGrantBinding() => _runDomainAction(() async {
        final exported = await _domainWorkflow.exportGrantBinding();
        await Clipboard.setData(ClipboardData(text: exported));
        return '交给核心所有者工具生成当前手机的独立授权';
      }, '授权绑定信息已复制');

  Future<void> _revokeDomainGrant() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销本机领域授权？'),
        content: const Text('这会立刻停止后续领域请求并重建运行时。聊天配对、现有数据和权威路由不会改变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销授权'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runDomainAction(() async {
      await _domainWorkflow.revokeGrant();
      return null;
    }, '领域授权已撤销');
  }

  Future<void> _freezeCaptureMigration() => _runDomainAction(() async {
        final exported = await _domainWorkflow.freezeCaptureMigration();
        await Clipboard.setData(ClipboardData(text: exported));
        return '冻结清单已复制，请交给核心所有者工具验证';
      }, '捕获迁移已冻结');

  Future<void> _copyFrozenManifest() => _runDomainAction(() async {
        final exported = await _domainWorkflow.exportFrozenCaptureManifest();
        await Clipboard.setData(ClipboardData(text: exported));
        return null;
      }, '冻结清单已复制');

  Future<void> _commitCaptureMigration() async {
    final source = await _jsonDialog(
      title: '提交核心接管证明',
      label: '核心接管证明 JSON',
      action: '重新核验并提交',
      explanation: 'App 会重新查询每条核心回执、核对当前记录与冻结清单，并在同一事务中切换所有者和路由。',
    );
    if (source == null || source.trim().isEmpty) return;
    await _runDomainAction(() async {
      await _domainWorkflow.commitCaptureMigration(source);
      return null;
    }, '捕获来源已由核心接管');
  }

  Future<void> _abortCaptureMigration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('中止这次迁移？'),
        content: const Text('冻结清单会被丢弃，旧手机消费者继续保持权威。核心中已有的候选记录不会被当作已接管。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('中止迁移'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runDomainAction(() async {
      await _domainWorkflow.abortCaptureMigration();
      return null;
    }, '迁移已中止，旧消费者继续工作');
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _runtime.pair(
        baseUrl: _urlController.text,
        pairingCode: _codeController.text,
        displayName: _nameController.text,
      );
      _codeController.clear();
      if (mounted) ToastHelper.showSuccess(context, '这台设备已连接到林埃核心');
    } catch (error) {
      if (mounted) ToastHelper.showError(context, '连接失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _runtime.syncNow();
      if (mounted) ToastHelper.showSuccess(context, '同步完成');
    } catch (_) {
      if (mounted) {
        ToastHelper.showError(
          context,
          _runtime.status.message ?? '同步失败，消息已保留在本机',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开这台设备？'),
        content: const Text('本机聊天不会删除；尚未发送的消息仍会保留，重新配对后可继续同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _runtime.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final status = _runtime.status;
    return Scaffold(
      backgroundColor: SpringRainUiTokens.daylightCanvas,
      appBar: AppBar(
        title: const Text('林埃核心'),
        backgroundColor: SpringRainUiTokens.daylightCanvas,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusCard(status: status),
          const SizedBox(height: 10),
          const Text(
            '当前是第一个窄切版本：只同步你发出的文字消息。'
            '林埃回复、图片和 Memory V3 还未接入核心。',
            style: TextStyle(
              color: SpringRainUiTokens.daylightTextSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          if (!status.isConfigured) ...[
            const Text(
              '连接这台设备',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '先在私人电脑启动林埃核心并生成一次性配对码。远程地址必须使用 Tailscale HTTPS。',
              style: TextStyle(
                color: SpringRainUiTokens.daylightTextSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '核心地址',
                hintText: 'https://你的设备名.ts.net',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '这台设备的名字（可选）',
                hintText: '主力手机',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '一次性配对码'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _pair,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded),
              label: const Text('连接'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: status.phase == CoreSyncRuntimePhase.syncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: const Text('立即同步'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _disconnect,
              child: const Text('断开这台设备'),
            ),
            const SizedBox(height: 12),
            const Divider(),
            _DomainAccessAndMigrationCard(
              status: _domainStatus,
              busy: _busy,
              onImport: _importDomainGrant,
              onCopyBinding: _copyGrantBinding,
              onRevoke: _revokeDomainGrant,
              onFreeze: _freezeCaptureMigration,
              onCopyManifest: _copyFrozenManifest,
              onCommit: _commitCaptureMigration,
              onAbort: _abortCaptureMigration,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('睡眠接管邮件测试'),
                subtitle: const Text('固定“哄睡聊天”邮件 · 仅手动 · 不接睡眠判断'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SleepTakeoverDebugPage(),
                          ),
                        ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DomainAccessAndMigrationCard extends StatelessWidget {
  const _DomainAccessAndMigrationCard({
    required this.status,
    required this.busy,
    required this.onImport,
    required this.onCopyBinding,
    required this.onRevoke,
    required this.onFreeze,
    required this.onCopyManifest,
    required this.onCommit,
    required this.onAbort,
  });

  final CoreDomainWorkflowStatus? status;
  final bool busy;
  final VoidCallback onImport,
      onCopyBinding,
      onRevoke,
      onFreeze,
      onCopyManifest,
      onCommit,
      onAbort;

  @override
  Widget build(BuildContext context) {
    final value = status;
    final grant = value?.grant;
    final frozen = value?.frozenMigrationId != null;
    final coreOwner = value?.captureOwner == 'core';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '领域授权与捕获迁移',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          grant == null
              ? '尚未导入独立领域授权。聊天连接不会自动获得领域权限。'
              : '已授权：${grant.coreInstanceId} · ${grant.principalId} · 第 ${grant.credentialGeneration} 代',
          style: const TextStyle(
            color: SpringRainUiTokens.daylightTextSecondary,
            height: 1.45,
          ),
        ),
        if (value?.routeBindingBlocked == true) ...[
          const SizedBox(height: 6),
          const Text(
            '凭据绑定已变化，既有核心路由保持原绑定并暂停。需要单独的路由迁移证明。',
            style: TextStyle(color: SpringRainUiTokens.daylightWarning),
          ),
        ],
        if (coreOwner && grant == null) ...[
          const SizedBox(height: 6),
          const Text(
            '核心权威记录仍保留，但领域访问已停止；App 不会自动回退到旧消费者。',
            style: TextStyle(color: SpringRainUiTokens.daylightWarning),
          ),
        ],
        const SizedBox(height: 12),
        if (value?.installationId != null) ...[
          Text(
            '当前安装：${value!.installationId}',
            style: const TextStyle(
              color: SpringRainUiTokens.daylightTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed:
                  busy || value?.installationId == null ? null : onCopyBinding,
              icon: const Icon(Icons.content_copy_rounded),
              label: const Text('复制授权绑定信息'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onImport,
              icon: const Icon(Icons.key_rounded),
              label: Text(grant == null ? '导入领域授权' : '导入轮换授权'),
            ),
            if (grant != null)
              TextButton(
                onPressed: busy ? null : onRevoke,
                child: const Text('撤销领域授权'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          coreOwner
              ? '捕获消费者：核心已接管'
              : frozen
                  ? '捕获消费者：旧消费者已冻结，等待核心证明'
                  : '捕获消费者：手机旧消费者',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (!coreOwner && !frozen)
          FilledButton.tonalIcon(
            onPressed: busy || grant == null ? null : onFreeze,
            icon: const Icon(Icons.pause_circle_outline_rounded),
            label: const Text('冻结并复制迁移清单'),
          ),
        if (!coreOwner && frozen)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onCopyManifest,
                child: const Text('再次复制冻结清单'),
              ),
              FilledButton(
                onPressed: busy || grant == null ? null : onCommit,
                child: const Text('导入证明并提交接管'),
              ),
              TextButton(
                onPressed: busy ? null : onAbort,
                child: const Text('中止迁移'),
              ),
            ],
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final CoreSyncRuntimeStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, title, color) = switch (status.phase) {
      CoreSyncRuntimePhase.notConfigured => (
          Icons.cloud_off_outlined,
          '尚未连接',
          SpringRainUiTokens.daylightTextSecondary,
        ),
      CoreSyncRuntimePhase.syncing => (
          Icons.sync_rounded,
          '正在同步',
          SpringRainUiTokens.daylightAccent,
        ),
      CoreSyncRuntimePhase.error => (
          Icons.cloud_off_rounded,
          '核心暂时不可用',
          SpringRainUiTokens.daylightError,
        ),
      CoreSyncRuntimePhase.idle => (
          Icons.cloud_done_outlined,
          status.pendingMessages == 0
              ? '已连接'
              : '${status.pendingMessages} 条待发送',
          status.pendingMessages == 0
              ? SpringRainUiTokens.daylightSuccess
              : SpringRainUiTokens.daylightWarning,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpringRainUiTokens.daylightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpringRainUiTokens.daylightDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (status.message != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    status.message!,
                    style: const TextStyle(
                      color: SpringRainUiTokens.daylightTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (status.baseUrl != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    status.baseUrl!,
                    style: const TextStyle(
                      color: SpringRainUiTokens.daylightTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
