import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:memex/data/workbench_ai/product/workbench_task_product_close.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import '../view_models/p6_r7_product_chat_view_model.dart';
import 'p6_r7_product_chat_surface.dart';

/// OS exit is intercepted at the root; detached remains best effort only.
class P6R7ProductApp extends StatefulWidget {
  const P6R7ProductApp(
      {super.key, required this.viewModel, required this.close});
  final P6R7ProductChatViewModel viewModel;
  final WorkbenchTaskProductClose close;

  @override
  State<P6R7ProductApp> createState() => P6R7ProductAppState();
}

class P6R7ProductAppState extends State<P6R7ProductApp>
    with WidgetsBindingObserver {
  Future<ui.AppExitResponse>? _exit;
  bool _closing = false;
  bool _unknown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() {
    final active = _exit;
    if (active != null) return active;
    setState(() {
      _closing = true;
      _unknown = false;
    });
    final result = widget.close.close();
    late final Future<ui.AppExitResponse> attempt;
    attempt = result.then((closed) {
      if (mounted) setState(() => _unknown = !closed);
      return closed ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
    }).whenComplete(() {
      if (identical(_exit, attempt)) _exit = null;
    });
    return _exit = attempt;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // No exit or witness claim is inferred from this notification itself.
      unawaited(widget.close.close());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const tokens = DesktopWorkspaceTokens.lieflatPalm;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: tokens.canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: tokens.action),
        extensions: const [tokens],
      ),
      home: Scaffold(
          body: SafeArea(
              child: Column(children: [
        if (_closing)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_unknown ? '关闭尚未确认，窗口已保留。请稍后再次关闭。' : '正在等待对话与任务安全关闭…'),
          ),
        Expanded(
            child: AbsorbPointer(
          absorbing: _closing,
          child: P6R7ProductChatSurface(viewModel: widget.viewModel),
        )),
      ]))),
    );
  }
}
