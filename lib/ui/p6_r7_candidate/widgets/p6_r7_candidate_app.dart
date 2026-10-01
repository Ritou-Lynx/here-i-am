import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/ui/p6_r7_candidate/view_models/p6_r7_candidate_view_model.dart';

/// Root for the independently composed P6/R7 candidate target.
/// The owner and view model are supplied by that target and survive page
/// navigation; detached is best-effort, while an OS exit request waits for close.
class P6R7CandidateApp extends StatefulWidget {
  const P6R7CandidateApp({
    super.key,
    required this.viewModel,
    required this.lifecycleOwner,
    this.closeOwnedHost,
    this.closeSession,
  });

  final P6R7CandidateViewModel viewModel;
  final WorkbenchTaskQueueLifecycleOwner lifecycleOwner;

  /// Closes the candidate host process owned by this App instance. A false or
  /// failed close leaves the window open so the same owned host can be retried.
  final Future<bool> Function()? closeOwnedHost;
  final Future<P6R7CandidateSessionCloseResult> Function()? closeSession;

  @override
  State<P6R7CandidateApp> createState() => _P6R7CandidateAppState();
}

class _P6R7CandidateAppState extends State<P6R7CandidateApp>
    with WidgetsBindingObserver {
  Future<ui.AppExitResponse>? _exitRequest;
  Future<bool>? _ownedHostClose;
  bool _ownedHostClosed = false;
  bool _lifecycleClosed = false;
  Future<P6R7CandidateSessionCloseResult>? _sessionClose;
  bool _exitRequested = false;
  bool _exitCloseFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.viewModel.restoreExactTask();
    widget.viewModel.startStatusObservation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(didRequestAppExit());
    }
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() {
    final active = _exitRequest;
    if (active != null) return active;

    late final Future<ui.AppExitResponse> request;
    request = _closeForExit().whenComplete(() {
      if (identical(_exitRequest, request)) _exitRequest = null;
    });
    _exitRequest = request;
    _exitRequested = true;
    _exitCloseFailed = false;
    if (mounted) setState(() {});
    return request;
  }

  Future<ui.AppExitResponse> _closeForExit() async {
    try {
      await widget.viewModel.quiesceForExit();
      if (!_lifecycleClosed) {
        _lifecycleClosed = await widget.lifecycleOwner.closeForHostLifecycle();
      }
      if (_lifecycleClosed &&
          await _closeOwnedHost() &&
          await _closeSession()) {
        return ui.AppExitResponse.exit;
      }
    } on Object {
      // A failed lifecycle close must keep the window open for a later retry.
    }
    if (mounted) setState(() => _exitCloseFailed = true);
    return ui.AppExitResponse.cancel;
  }

  Future<bool> _closeSession() async {
    final close = widget.closeSession;
    if (close == null) return true;
    // Cache failure as well as success. Re-invoking a partly closed Store must
    // never manufacture a successful second result.
    _sessionClose ??= Future<P6R7CandidateSessionCloseResult>.sync(close)
        .onError((Object _, StackTrace __) =>
            P6R7CandidateSessionCloseResult.unknown);
    return (await _sessionClose!).closed;
  }

  Future<bool> _closeOwnedHost() {
    final close = widget.closeOwnedHost;
    if (close == null || _ownedHostClosed) return Future<bool>.value(true);
    final active = _ownedHostClose;
    if (active != null) return active;

    late final Future<bool> attempt;
    attempt = Future<bool>.sync(close).then((closed) {
      if (closed) _ownedHostClosed = true;
      return closed;
    }).whenComplete(() {
      if (identical(_ownedHostClose, attempt)) _ownedHostClose = null;
    });
    _ownedHostClose = attempt;
    return attempt;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.viewModel.stopStatusObservation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff56675a),
            surface: const Color(0xfff1efe7),
          ),
          scaffoldBackgroundColor: const Color(0xffe6e3da),
          useMaterial3: true,
        ),
        builder: (context, child) => _ExitStatusOverlay(
          exitRequested: _exitRequested,
          exitCloseFailed: _exitCloseFailed,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _CandidateHome(
          viewModel: widget.viewModel,
          exitRequested: _exitRequested,
        ),
      );
}

class _CandidateHome extends StatelessWidget {
  const _CandidateHome({
    required this.viewModel,
    required this.exitRequested,
  });

  final P6R7CandidateViewModel viewModel;
  final bool exitRequested;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('公开文字验收'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _RetainedStatePage(viewModel: viewModel),
                ),
              ),
              child: const Text('查看持续状态'),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    minHeight: constraints.maxHeight,
                  ),
                  child: ListenableBuilder(
                    listenable: viewModel,
                    builder: (context, _) => _CandidateCard(
                      viewModel: viewModel,
                      exitRequested: exitRequested,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _ExitStatusOverlay extends StatelessWidget {
  const _ExitStatusOverlay({
    required this.exitRequested,
    required this.exitCloseFailed,
    required this.child,
  });

  final bool exitRequested;
  final bool exitCloseFailed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          child,
          if (exitRequested)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  elevation: 4,
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child:
                        Text(exitCloseFailed ? '任务停止未确认；可再次关闭重试。' : '正在停止任务…'),
                  ),
                ),
              ),
            ),
        ],
      );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.viewModel,
    required this.exitRequested,
  });

  final P6R7CandidateViewModel viewModel;
  final bool exitRequested;

  @override
  Widget build(BuildContext context) {
    final task = viewModel.snapshot;
    return Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('隔离验收 · 测试数据', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 16),
            const Text(P6R7CandidateViewModel.goal),
            const SizedBox(height: 20),
            Text('当前状态：${viewModel.statusLabel}'),
            if (task?.currentStep case final step?) Text('进度：$step'),
            if (task?.resultPreview case final preview?) ...[
              const SizedBox(height: 8),
              Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (viewModel.errorMessage case final message?) ...[
              const SizedBox(height: 12),
              Text(message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!viewModel.hasTask)
                  FilledButton(
                    onPressed: viewModel.isBusy || exitRequested
                        ? null
                        : viewModel.enqueue.execute,
                    child: const Text('创建验收任务'),
                  ),
                if (viewModel.hasTask) ...[
                  FilledButton(
                      onPressed: viewModel.isBusy || exitRequested
                          ? null
                          : viewModel.start.execute,
                      child: const Text('开始')),
                  OutlinedButton(
                      onPressed: viewModel.isBusy || exitRequested
                          ? null
                          : viewModel.refresh.execute,
                      child: const Text('读取状态')),
                  OutlinedButton(
                      onPressed: viewModel.isBusy || exitRequested
                          ? null
                          : viewModel.pause.execute,
                      child: const Text('暂停')),
                  OutlinedButton(
                      onPressed: viewModel.isBusy || exitRequested
                          ? null
                          : viewModel.resume.execute,
                      child: const Text('继续')),
                  OutlinedButton(
                      onPressed: viewModel.isBusy || exitRequested
                          ? null
                          : viewModel.retry.execute,
                      child: const Text('重试')),
                  TextButton(
                      onPressed: viewModel.isBusy || exitRequested
                          ? null
                          : viewModel.cancel.execute,
                      child: const Text('取消')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RetainedStatePage extends StatelessWidget {
  const _RetainedStatePage({required this.viewModel});

  final P6R7CandidateViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('持续状态')),
        body: Center(
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => Text('当前状态：${viewModel.statusLabel}'),
          ),
        ),
      );
}
