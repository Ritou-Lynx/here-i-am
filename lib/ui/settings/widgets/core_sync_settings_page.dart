import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:memex/data/services/sync/core_sync_runtime_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/widgets/sleep_takeover_debug_page.dart';
import 'package:memex/utils/toast_helper.dart';

class CoreSyncSettingsPage extends StatefulWidget {
  const CoreSyncSettingsPage({super.key});

  @override
  State<CoreSyncSettingsPage> createState() => _CoreSyncSettingsPageState();
}

class _CoreSyncSettingsPageState extends State<CoreSyncSettingsPage> {
  final _runtime = CoreSyncRuntimeService.instance;
  final _urlController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runtime.addListener(_onStatusChanged);
    _runtime.refreshStatus();
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
