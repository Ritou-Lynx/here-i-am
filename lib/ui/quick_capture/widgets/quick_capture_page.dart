import 'package:flutter/material.dart';
import 'package:memex/utils/result.dart';
import '../../../data/personal_data_hub/quick_capture_models.dart';
import '../../../data/personal_data_hub/quick_capture_service.dart';
import '../../../data/personal_data_hub/quick_capture_speech.dart';
import '../view_models/quick_capture_view_model.dart';

class QuickCapturePage extends StatefulWidget {
  const QuickCapturePage({
    super.key,
    required this.service,
    this.speech,
    this.restored,
    this.onClose,
    this.recent,
    this.onOpenOutput,
  });
  final QuickCaptureService service;
  final QuickCaptureSpeech? speech;
  final QuickCaptureDraft? restored;
  final VoidCallback? onClose;
  final Future<List<QuickCaptureResult>> Function()? recent;
  final void Function(String processor, String id)? onOpenOutput;
  @override
  State<QuickCapturePage> createState() => _QuickCapturePageState();
}

class _QuickCapturePageState extends State<QuickCapturePage>
    with WidgetsBindingObserver {
  late final QuickCaptureViewModel vm;
  late final TextEditingController text;
  List<QuickCaptureResult> recent = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vm = QuickCaptureViewModel(
      widget.service,
      speech: widget.speech,
      restored: widget.restored,
    )..addListener(changed);
    text = TextEditingController(text: vm.draft.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.restored == null) vm.voice.execute();
      loadRecent();
    });
  }

  Future<void> loadRecent() async {
    if (widget.recent == null) return;
    final result = await runResult(widget.recent!);
    if (mounted && result is Ok<List<QuickCaptureResult>>) {
      setState(() => recent = result.value);
    }
  }

  void changed() {
    if (!mounted) return;
    if (text.text != vm.draft.text) {
      text.value = TextEditingValue(
        text: vm.draft.text,
        selection: TextSelection.collapsed(offset: vm.draft.text.length),
      );
    }
    setState(() {});
  }

  Future<void> close() async {
    await vm.cancel();
    if (!mounted) return;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> send() async {
    await vm.send.execute();
    if (!mounted || vm.result == null) return;
    await loadRecent();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(vm.result!.deliveryMessage)));
    if (widget.onClose != null) await close();
  }

  List<Widget> receipt(QuickCaptureResult result) => [
        Text(result.deliveryMessage),
        Text(result.organizerMessage ?? '生活记录：待处理'),
        for (var i = 0; i < result.organizerOutputs.length; i++)
          TextButton(
              onPressed: widget.onOpenOutput == null
                  ? null
                  : () => widget.onOpenOutput!(
                      'organizer', result.organizerOutputs[i]),
              child: Text('查看生活记录 ${i + 1}')),
        Text(result.plannerMessage ?? '待办与时间：待处理'),
        for (var i = 0; i < result.plannerOutputs.length; i++)
          TextButton(
              onPressed: widget.onOpenOutput == null
                  ? null
                  : () =>
                      widget.onOpenOutput!('planner', result.plannerOutputs[i]),
              child: Text('查看规划 ${i + 1}')),
        ...result.pendingIssues.map(Text.new),
      ];
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm.removeListener(changed);
    vm.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        vm.recording) {
      vm.keyboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = vm.send.running || vm.finishVoice.running || vm.voice.running;
    return PopScope(
      canPop: !vm.send.running,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) vm.cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('记一下')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: text,
              enabled: !busy && !vm.recording,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              onChanged: vm.setText,
              decoration: const InputDecoration(
                hintText: '说完或写下要记的事',
                border: OutlineInputBorder(),
              ),
            ),
            if (vm.notice != null) Text(vm.notice!),
            if (vm.error != null) Text(vm.error!),
            if (vm.recording)
              TextButton(
                onPressed: busy ? null : vm.keyboard,
                child: const Text('完成录音，编辑文字'),
              ),
            TextButton(
              onPressed: busy ? null : vm.keyboard,
              child: const Text('键盘输入'),
            ),
            FilledButton(
              onPressed: busy || vm.recording || vm.draft.text.trim().isEmpty
                  ? null
                  : send,
              child: Text(vm.send.running ? '保存中…' : '发送'),
            ),
            TextButton(
              onPressed: vm.send.running ? null : close,
              child: const Text('取消'),
            ),
            if (vm.result != null) ...receipt(vm.result!),
            if (recent.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text('最近记录'),
              ),
            for (final result in recent) ...[
              const Divider(),
              Text(result.text),
              ...receipt(result),
            ],
          ],
        ),
      ),
    );
  }
}
