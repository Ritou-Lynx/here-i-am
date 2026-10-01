import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/ui/settings/view_models/phone_memory_connection_viewmodel.dart';
import 'package:memex/utils/command.dart';

/// Explicit P5 consent surface. It neither starts a server automatically nor
/// establishes an ADB forward: both are user-directed, short-lived actions.
class PhoneMemoryConnectionPage extends StatefulWidget {
  const PhoneMemoryConnectionPage({
    super.key,
    this.facade,
    this.desktopPlatformOverride,
  });

  final PhoneMemoryConnectionFacade? facade;

  /// Test seam. Production chooses the current platform.
  final bool? desktopPlatformOverride;

  @override
  State<PhoneMemoryConnectionPage> createState() =>
      _PhoneMemoryConnectionPageState();
}

class _PhoneMemoryConnectionPageState extends State<PhoneMemoryConnectionPage> {
  late final PhoneMemoryConnectionFacade _facade;
  late final PhoneMemoryConnectionViewModel _viewModel;
  late final bool _ownsFacade;
  final _codeController = TextEditingController();
  Timer? _clock;

  bool get _isDesktop =>
      widget.desktopPlatformOverride ??
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.macOS =>
          true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    _ownsFacade = widget.facade == null;
    _facade = widget.facade ?? LivePhoneMemoryConnectionFacade();
    _viewModel = PhoneMemoryConnectionViewModel(facade: _facade);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _codeController.dispose();
    _viewModel.dispose();
    if (_ownsFacade) _facade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('桌面记忆只读连接')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          _viewModel,
          _viewModel.startPhone,
          _viewModel.stopPhone,
          _viewModel.connect,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _isDesktop ? '从手机接入只读记忆' : '临时授权桌面读取记忆',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('连接不搬运整库，也不会在这里展示任何记忆正文。'),
            const SizedBox(height: 20),
            if (_isDesktop) _buildDesktop(context) else _buildPhone(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    final session = _viewModel.phoneSession;
    final active = _viewModel.isPhoneRunning &&
        session != null &&
        session.expiresAt.isAfter(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(
          key: const ValueKey('phone_memory_phone_status'),
          icon: active ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
          title: active ? '短时会话已开启' : '默认关闭',
          detail: active
              ? '到 ${_formatTime(session.expiresAt)} 自动关闭。'
              : '只有你手动开启后，桌面才能在这次会话中读取有限上下文。',
        ),
        const SizedBox(height: 16),
        if (active) ...[
          _InfoCard(
            icon: Icons.usb_rounded,
            title: '通过 USB 手动转发',
            detail: '在电脑上针对这台手机执行 adb forward。此页面不会自动建立 USB 转发，也不会监听局域网。',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('phone_memory_copy_code'),
            onPressed: () => _copyConnectionCode(session),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制连接码'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('phone_memory_stop'),
            onPressed: _viewModel.stopPhone.running
                ? null
                : () => _run(_viewModel.stopPhone, '已关闭本次只读会话'),
            child: const Text('关闭这次会话'),
          ),
        ] else
          FilledButton.icon(
            key: const ValueKey('phone_memory_start'),
            onPressed: _viewModel.startPhone.running
                ? null
                : () => _run(_viewModel.startPhone, '已开启 30 分钟只读会话'),
            icon: _viewModel.startPhone.running
                ? const _SmallProgress()
                : const Icon(Icons.lock_open_rounded),
            label: const Text('开启 30 分钟只读会话'),
          ),
        const SizedBox(height: 18),
        const Text('手机 App 退出后，服务会关闭；重新打开 App 后需要再次手动授权。'),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final configured = _viewModel.isDesktopConfigured;
    final expiry = _viewModel.desktopExpiresAt;
    final expired =
        configured && expiry != null && !expiry.isAfter(DateTime.now());
    final receiptUnavailable =
        _viewModel.lastReceipt?['status'] == 'unavailable';
    final usable = configured && !expired && !receiptUnavailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(
          key: const ValueKey('phone_memory_desktop_status'),
          icon: usable ? Icons.link_rounded : Icons.link_off_rounded,
          title: expired
              ? '本次会话已过期'
              : receiptUnavailable
                  ? '本次会话暂时不可用'
                  : configured
                      ? '已保存本次会话授权'
                      : '尚未连接',
          detail: expired
              ? '请在手机中重新手动授权；也可以先断开这份失效授权。'
              : receiptUnavailable
                  ? '手机或 USB 转发暂时不可用。桌面不会静默改用本地空数据。'
                  : configured
                      ? (expiry == null
                          ? '授权仍在本进程中保存。'
                          : '有效至 ${_formatTime(expiry)}。')
                      : '先在手机中手动开启短时会话，再复制连接码到这里。',
        ),
        const SizedBox(height: 16),
        if (!configured) ...[
          const _InfoCard(
            icon: Icons.usb_rounded,
            title: '准备 USB 转发',
            detail:
                '请保持手机 App 运行，并由你在电脑上对选定设备执行 adb forward --no-rebind tcp:47851 tcp:47851。此页面不会自动执行或伪装这一步。',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('phone_memory_connection_code'),
            controller: _codeController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _connect(),
            decoration: const InputDecoration(
              labelText: '粘贴连接码',
              hintText: '从手机复制后粘贴',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('phone_memory_connect'),
            onPressed: _viewModel.connect.running ? null : _connect,
            icon: _viewModel.connect.running
                ? const _SmallProgress()
                : const Icon(Icons.link_rounded),
            label: const Text('连接这次会话'),
          ),
        ] else ...[
          _LastReceipt(receipt: _viewModel.lastReceipt),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('phone_memory_disconnect'),
            onPressed: _viewModel.disconnect,
            child: const Text('断开连接'),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
            '你主动断开后，桌面会恢复原有本地来源。会话到期、手机关闭 App 或 USB 转发不可用时，桌面不会静默改用本地空数据；请重新授权连接。'),
      ],
    );
  }

  Future<void> _connect() async {
    final code = _codeController.text;
    _codeController.clear();
    await _run(_viewModel.connect, null, argument: code);
  }

  Future<void> _copyConnectionCode(PhoneMemoryConnectionSession session) async {
    await Clipboard.setData(ClipboardData(text: session.connectionCode));
    if (mounted) _message('连接码已复制；请粘贴到桌面。');
  }

  Future<void> _run<T>(Command<T> command, String? success,
      {Object? argument}) async {
    if (command is Command0<T>) {
      await command.execute();
    } else if (command is Command1<T, String> && argument is String) {
      await command.execute(argument);
    }
    if (!mounted) return;
    if (command.error) {
      _message('操作未完成。请确认手机 App、USB 转发和本次会话仍然有效。');
    } else if (command.completed && success != null) {
      _message(success);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _LastReceipt extends StatelessWidget {
  const _LastReceipt({required this.receipt});
  final Map<String, Object?>? receipt;

  @override
  Widget build(BuildContext context) {
    if (receipt == null || receipt!.isEmpty) {
      return const _InfoCard(
        icon: Icons.receipt_long_outlined,
        title: '尚无读取回执',
        detail: '读取发生后只会在这里显示来源、状态、条目计数和时间，不显示记忆正文。',
      );
    }
    final source = receipt!['source'] ?? 'phone_v3_live';
    final status = receipt!['status'] ?? '已完成';
    final counts = receipt!['counts'] ?? '—';
    final time = receipt!['captured_at'] ?? receipt!['time'] ?? '—';
    return _InfoCard(
      icon: Icons.receipt_long_outlined,
      title: '最近一次读取回执',
      detail: '来源：$source\n状态：$status\n条目：$counts\n时间：$time',
    );
  }
}

class _SmallProgress extends StatelessWidget {
  const _SmallProgress();
  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

String _formatTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
