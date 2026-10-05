import 'package:flutter/material.dart';
import 'quick_capture_controller.dart';
import '../../data/personal_data_hub/quick_capture_models.dart';

class QuickCapturePage extends StatefulWidget {
  const QuickCapturePage({super.key, required this.controller});
  final QuickCaptureController controller;
  @override State<QuickCapturePage> createState() => _QuickCapturePageState();
}
class _QuickCapturePageState extends State<QuickCapturePage> {
  late final TextEditingController _text;
  @override void initState() { super.initState(); _text = TextEditingController(); widget.controller.addListener(_changed); }
  void _changed() { if (mounted) setState(() {}); }
  @override void dispose() { widget.controller.removeListener(_changed); _text.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final c = widget.controller; final busy = c.state == QuickCaptureState.sending;
    return Scaffold(appBar: AppBar(title: const Text('记一下')), body: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _text, autofocus: true, maxLines: 8, onChanged: c.setText, decoration: const InputDecoration(hintText: '说完或写下要记的事', border: OutlineInputBorder())),
      const SizedBox(height: 12), if (c.state == QuickCaptureState.saved) const Text('已保存到收件箱'),
      if (c.result?.organizerMessage != null) Text(c.result!.organizerMessage!), if (c.result?.plannerMessage != null) Text(c.result!.plannerMessage!),
      ...?c.result?.pendingIssues.map(Text.new), if (c.error != null) Text(c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), const Spacer(),
      ElevatedButton(onPressed: busy ? null : c.send, child: Text(busy ? '保存中…' : '完成')),
    ])));
  }
}
