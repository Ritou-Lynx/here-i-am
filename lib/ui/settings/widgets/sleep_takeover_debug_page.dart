import 'package:flutter/material.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/shortcut_mail_trigger_client.dart';

/// Debug-only entry point for the explicit iOS Shortcut email smoke test.
/// The settings router decides whether this page is reachable in a build.
class SleepTakeoverDebugPage extends StatefulWidget {
  const SleepTakeoverDebugPage({super.key});

  @override
  State<SleepTakeoverDebugPage> createState() => _SleepTakeoverDebugPageState();
}

class _SleepTakeoverDebugPageState extends State<SleepTakeoverDebugPage> {
  final _tokenController = TextEditingController();
  final _tokenStore = ShortcutMailTestTokenStore();
  final _requestStore = ShortcutMailTestRequestStore();

  bool _loading = true;
  bool _busy = false;
  String? _lastRequestId;
  ShortcutMailReceipt? _receipt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStoredValues();
  }

  Future<void> _loadStoredValues() async {
    final connection = await CoreSyncConnectionStore.instance.read();
    final token = connection == null
        ? null
        : await _tokenStore.readForCore(connection.coreNodeId);
    final requestId = connection == null || token == null
        ? null
        : await _requestStore.readForScope(
            coreNodeId: connection.coreNodeId,
            scopedTestToken: token,
          );
    if (!mounted) return;
    setState(() {
      _tokenController.text = token ?? '';
      _lastRequestId = requestId;
      _loading = false;
    });
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showMessage('请先填写测试 token。');
      return;
    }
    final connection = await CoreSyncConnectionStore.instance.read();
    if (connection == null) {
      _showMessage('请先在核心同步设置中完成连接。');
      return;
    }
    await _requestStore.prepareScope(
      coreNodeId: connection.coreNodeId,
      scopedTestToken: token,
    );
    await _tokenStore.saveForCore(
      token: token,
      coreNodeId: connection.coreNodeId,
    );
    final pending = await _requestStore.readForScope(
      coreNodeId: connection.coreNodeId,
      scopedTestToken: token,
    );
    if (!mounted) return;
    setState(() {
      _lastRequestId = pending;
      _receipt = null;
      _error = null;
    });
    _showMessage(
        pending == null ? '新测试 token 已安全保存。' : '测试 token 已保存；原 request 仍保留。');
  }

  Future<void> _clearToken() async {
    await _tokenStore.clear();
    if (!mounted) return;
    setState(() => _tokenController.clear());
    _showMessage('测试 token 已清除。');
  }

  Future<void> _confirmAndSend() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showMessage('请先填写并保存测试 token。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送手动测试？'),
        content: const Text(
          '这会发起一次主题固定为“哄睡聊天”的手动快捷指令邮件测试。它不会开启睡眠监测，也不会创建自动任务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认发送'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final connection = await CoreSyncConnectionStore.instance.read();
      if (connection == null) {
        throw const ShortcutMailTriggerException(message: '请先在核心同步设置中完成连接。');
      }
      final savedToken = await _tokenStore.readForCore(connection.coreNodeId);
      if (savedToken != token) {
        throw const ShortcutMailTriggerException(
            message: 'token 有变化，请先点“安全保存 token”再发送。');
      }
      final client = ShortcutMailTriggerClient(
        baseUrl: connection.baseUrl,
        scopedTestToken: token,
        requestScope: connection.coreNodeId,
        requestStore: _requestStore,
      );
      final receipt = await client.sendManualTest();
      _lastRequestId = receipt.idempotencyKey;
      _receipt = receipt;
      if (receipt.status == ShortcutMailReceiptStatus.providerAccepted) {
        await _tokenStore.clear();
        if (mounted) _tokenController.clear();
      }
    });
  }

  Future<void> _queryLastReceipt() async {
    final token = _tokenController.text.trim();
    final key = _lastRequestId;
    if (token.isEmpty || key == null || key.isEmpty) {
      _showMessage('需要已保存的测试 token 和 request id 才能查询。');
      return;
    }
    await _run(() async {
      final connection = await CoreSyncConnectionStore.instance.read();
      if (connection == null) {
        throw const ShortcutMailTriggerException(message: '请先在核心同步设置中完成连接。');
      }
      final client = ShortcutMailTriggerClient(
        baseUrl: connection.baseUrl,
        scopedTestToken: token,
        requestScope: connection.coreNodeId,
        requestStore: _requestStore,
      );
      _receipt = await client.queryReceipt(key);
      if (_receipt!.status == ShortcutMailReceiptStatus.providerAccepted) {
        await _tokenStore.clear();
        if (mounted) _tokenController.clear();
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ShortcutMailTriggerException catch (error) {
      if (error.requestId != null && error.requestId!.isNotEmpty) {
        _lastRequestId = error.requestId;
      }
      if (error.code == 'token_expired') {
        await _tokenStore.clear();
        if (mounted) _tokenController.clear();
      }
      _error = error.message;
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = '操作未完成，请使用保留的 request id 查询回执。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('睡眠接管邮件手动测试')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '这是一次性、短时有效的测试凭据，只允许一个新的发送请求。不会开启睡眠监测、不会建立自动任务，也不会自动重试。',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _tokenController,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Scoped test token',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _saveToken,
                      child: const Text('安全保存 token'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _clearToken,
                      child: const Text('清除 token'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _confirmAndSend,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('发送手动测试'),
                ),
                if (_lastRequestId != null) ...[
                  const SizedBox(height: 16),
                  SelectableText('Request id: $_lastRequestId'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _queryLastReceipt,
                    child: const Text('查询此 request 的回执'),
                  ),
                ],
                if (_receipt != null) _ReceiptCard(receipt: _receipt!),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});
  final ShortcutMailReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receipt id: ${receipt.receiptId}'),
            Text('Subject code: ${receipt.subjectCode}'),
            Text('回执状态：${_statusText(receipt.status)}'),
            Text('Replay: ${receipt.replay ? '是' : '否'}'),
            if (receipt.recipientHint != null)
              Text('Recipient hint: ${receipt.recipientHint}'),
            if (receipt.message != null) Text(receipt.message!),
            const SizedBox(height: 8),
            const Text(
              '“Provider 已接受”只表示邮件服务商已接受发送请求；不表示 iCloud 已收到，也不表示快捷指令已执行。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusText(ShortcutMailReceiptStatus status) =>
      switch (status) {
        ShortcutMailReceiptStatus.reserved => '已保留（尚未发送）',
        ShortcutMailReceiptStatus.sendStarted => '已开始发送',
        ShortcutMailReceiptStatus.providerAccepted => 'Provider 已接受发送请求',
        ShortcutMailReceiptStatus.failedBeforeSend => '发送前失败',
        ShortcutMailReceiptStatus.outcomeUnknown => '结果未知，请查询回执',
      };
}
