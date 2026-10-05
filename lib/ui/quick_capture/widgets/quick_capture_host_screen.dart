import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/data/personal_data_hub/quick_capture_speech.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/ui/planning/widgets/planning_screen.dart';
import 'package:memex/utils/result.dart';
import '../quick_capture_launch_bridge.dart';
import 'quick_capture_page.dart';

/// App-owned runtime, screen-owned draft and microphone. The caller must mount
/// this screen only after the app lock has cleared, including cold capture.
class QuickCaptureHostScreen extends StatefulWidget {
  const QuickCaptureHostScreen({super.key, this.independentTask = false});
  final bool independentTask;

  @override
  State<QuickCaptureHostScreen> createState() => _QuickCaptureHostScreenState();
}

class _QuickCaptureHostScreenState extends State<QuickCaptureHostScreen> {
  late final _speech = LocalQuickCaptureSpeech();
  final _bridge = QuickCaptureLaunchBridge();
  bool _closing = false;
  String? _closeError;

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final result = await runResultVoid(() async {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _bridge.close();
      }
    });
    if (!mounted) return;
    if (widget.independentTask) {
      if (result is Error<void>) {
        setState(() {
          _closing = false;
          _closeError = '暂时无法关闭，可以使用系统返回键。';
        });
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(_closeError!)));
      }
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _openOutput(
      PersonalDataHubRuntime runtime, String processor, String id) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => processor == 'organizer'
            ? MemoryCardDetailScreenV3(
                cardId: id,
                queryService: MemoryCardQueryService(runtime.db),
                organizerService: RecordOrganizerServiceV3(runtime.db))
            : PlanningScreen(service: runtime)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<Result<PersonalDataHubRuntime>?>();
    return switch (state) {
      Ok(:final value) => QuickCapturePage(
          service: value.quickCaptureService,
          speech: _speech,
          recent: value.recent,
          changes: value.changes,
          onClose: _close,
          onOpenOutput: (processor, id) => _openOutput(value, processor, id)),
      _ => Scaffold(
          appBar: AppBar(title: const Text('记一下')),
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (state == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('正在打开记录入口…'),
            ] else
              const Text('记录入口暂时无法打开，请返回后重试'),
            if (_closeError != null) Text(_closeError!),
            TextButton(onPressed: _close, child: const Text('关闭')),
          ]))),
    };
  }
}
