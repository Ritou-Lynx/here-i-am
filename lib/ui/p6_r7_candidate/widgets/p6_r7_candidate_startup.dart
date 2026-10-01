import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum P6R7CandidateStartupStage {
  configurationCheck('配置检查'),
  startingOwnedHost('启动专用服务'),
  waitingForAdmission('等待隔离凭据'),
  verifyingOwnedHost('核对专用服务'),
  preparingCandidateData('准备测试数据');

  const P6R7CandidateStartupStage(this.label);
  final String label;
}

/// Keeps the original host reachable on startup failure, including window close
/// while preflight is still in progress. Raw errors never reach the UI.
class P6R7CandidateStartup extends StatefulWidget {
  const P6R7CandidateStartup(
      {super.key, required this.prepare, required this.closeOwnedHost});
  final Future<Widget> Function(void Function(P6R7CandidateStartupStage))
      prepare;
  final Future<bool> Function() closeOwnedHost;

  @override
  State<P6R7CandidateStartup> createState() => _P6R7CandidateStartupState();
}

class _P6R7CandidateStartupState extends State<P6R7CandidateStartup>
    with WidgetsBindingObserver {
  late final Future<void> _preparing;
  Future<ui.AppExitResponse>? _exitRequest;
  Widget? _ready;
  bool _failed = false;
  bool _exiting = false;
  bool _closeFailed = false;
  bool _observing = true;
  var _stage = P6R7CandidateStartupStage.configurationCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preparing = _prepare();
  }

  Future<void> _prepare() async {
    try {
      final ready = await widget.prepare(_reportStage);
      if (!mounted) return;
      // An in-flight exit retains the startup owner; no task UI can start work.
      if (!_exiting) {
        setState(() => _ready = ready);
        // Transfer only after the ready root has mounted its own exit observer.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_exiting) {
            WidgetsBinding.instance.removeObserver(this);
            _observing = false;
          }
        });
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _reportStage(P6R7CandidateStartupStage stage) {
    if (!mounted || _exiting || _ready != null || _stage == stage) return;
    setState(() => _stage = stage);
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() {
    // During the handoff frame the ready root may already own a lifecycle gate.
    // Flutter still visits that observer after this cancel. Never remove that
    // root or close its host here; before mount, cancel closes the observer gap.
    if (_ready != null) return Future.value(ui.AppExitResponse.cancel);
    final active = _exitRequest;
    if (active != null) return active;
    _exiting = true;
    _closeFailed = false;
    if (mounted) setState(() {});
    late final Future<ui.AppExitResponse> attempt;
    attempt = _close().whenComplete(() {
      if (identical(_exitRequest, attempt)) _exitRequest = null;
    });
    _exitRequest = attempt;
    return attempt;
  }

  Future<ui.AppExitResponse> _close() async {
    // Signal the same owner immediately: it cancels admission polling and waits
    // for any in-flight spawn before requesting shutdown. Observe errors now,
    // even if preparation takes longer to settle.
    final close = Future<bool>.sync(widget.closeOwnedHost)
        .then((value) => value, onError: (Object _) => false);
    await _preparing;
    if (await close) return ui.AppExitResponse.exit;
    if (mounted) setState(() => _closeFailed = true);
    return ui.AppExitResponse.cancel;
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ??
      MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text(
          _closeFailed
              ? '停止尚未确认；可再次关闭重试。'
              : _exiting
                  ? '正在等待准备结束并停止专用服务…'
                  : _failed
                      ? '隔离验收尚未就绪。\n当前阶段：${_stage.label}\n关闭窗口时将确认专用服务停止。'
                      : '正在准备隔离验收…\n当前阶段：${_stage.label}',
          textAlign: TextAlign.center,
        ))),
      );
}
