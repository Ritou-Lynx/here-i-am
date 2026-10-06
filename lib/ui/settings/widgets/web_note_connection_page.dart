import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/ui/settings/view_models/web_note_connection_viewmodel.dart';

class WebNoteConnectionPage extends StatefulWidget {
  const WebNoteConnectionPage({super.key, this.service});
  final ClaudeWebNoteFeedService? service;
  @override
  State<WebNoteConnectionPage> createState() => _WebNoteConnectionPageState();
}

class _WebNoteConnectionPageState extends State<WebNoteConnectionPage> {
  late final WebNoteConnectionViewModel _viewModel;
  final _url = TextEditingController();
  final _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel = WebNoteConnectionViewModel(
        widget.service ?? context.read<ClaudeWebNoteFeedService>());
    _viewModel.load.execute().then((_) {
      if (mounted) _url.text = _viewModel.baseUrl ?? '';
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('网页端记录通道')),
        body: ListenableBuilder(
          listenable: Listenable.merge([
            _viewModel,
            _viewModel.load,
            _viewModel.save,
            _viewModel.sync,
            _viewModel.disconnect
          ]),
          builder: (context, _) {
            final busy = _viewModel.load.running ||
                _viewModel.save.running ||
                _viewModel.sync.running ||
                _viewModel.disconnect.running;
            return ListView(padding: const EdgeInsets.all(20), children: [
              Text(_viewModel.status,
                  key: const ValueKey('web_notes_status'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('在网页端明确交给林埃记下的内容，会直接整理成记忆卡。修改和删除也会同步到手机。'),
              const SizedBox(height: 20),
              TextField(
                  controller: _url,
                  enabled: !busy,
                  key: const ValueKey('web_notes_url'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                      labelText: 'Tailscale 地址',
                      hintText: 'https://你的电脑.ts.net:47863')),
              const SizedBox(height: 12),
              TextField(
                  controller: _token,
                  enabled: !busy,
                  obscureText: true,
                  key: const ValueKey('web_notes_token'),
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                      labelText: '手机令牌',
                      hintText: _viewModel.baseUrl == null
                          ? '粘贴电脑签发的令牌'
                          : '已安全保存；更换时填写新令牌')),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: busy ? null : _save,
                  key: const ValueKey('web_notes_save'),
                  child: const Text('保存并同步')),
              if (_viewModel.baseUrl != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: busy ? null : () => _viewModel.sync.execute(),
                    key: const ValueKey('web_notes_sync'),
                    child: const Text('立即同步')),
                TextButton(
                    onPressed:
                        busy ? null : () => _viewModel.disconnect.execute(),
                    key: const ValueKey('web_notes_disconnect'),
                    child: const Text('断开连接')),
              ],
              if (busy)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator())),
              if (_viewModel.load.error ||
                  _viewModel.save.error ||
                  _viewModel.disconnect.error)
                const Text('连接未完成，请检查地址、令牌和本机安全存储。'),
              const SizedBox(height: 12),
              const Text('地址和令牌保存在这台设备的安全存储中。打开 App、回到前台或点击同步时会拉取新记录。'),
            ]);
          },
        ),
      );

  Future<void> _save() async {
    final input = WebNoteConnectionInput(_url.text.trim(), _token.text.trim());
    _token.clear();
    await _viewModel.save.execute(input);
    if (mounted && _viewModel.save.completed) await _viewModel.sync.execute();
  }
}
