/// Full-screen whiteboard canvas route loader (W6 integration base).
///
/// Loads the board snapshot from the Drift-backed store, builds the
/// [WhiteboardCanvasViewModel] with Drift persistence wired as the default
/// save target, and renders [WhiteboardCanvasScreen]. Loading / missing /
/// error states are handled here; the canvas itself stays full-screen with no
/// persistent top bar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

/// Route screen for `/whiteboard/:boardId`. [store] is injectable for tests.
class WhiteboardCanvasRouteScreen extends StatefulWidget {
  final String boardId;
  final WhiteboardDriftStore? store;

  const WhiteboardCanvasRouteScreen({
    super.key,
    required this.boardId,
    this.store,
  });

  @override
  State<WhiteboardCanvasRouteScreen> createState() =>
      _WhiteboardCanvasRouteScreenState();
}

class _WhiteboardCanvasRouteScreenState
    extends State<WhiteboardCanvasRouteScreen> {
  late final WhiteboardDriftStore _store =
      widget.store ?? WhiteboardDriftStore(AppDatabase.instance);

  WhiteboardCanvasViewModel? _viewModel;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final WhiteboardDriftStore store;
    try {
      store = _store;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '存储不可用：$e';
        _loaded = true;
      });
      return;
    }
    try {
      final result = await store.load(widget.boardId);
      if (!mounted) return;
      if (result.isSuccess && result.snapshot != null) {
        final vm = WhiteboardCanvasViewModel(
          initialSnapshot: result.snapshot!,
          boardId: widget.boardId,
        );
        vm.onSaveRequested = () => unawaited(_save(vm));
        setState(() {
          _viewModel = vm;
          _error = null;
          _loaded = true;
        });
      } else {
        setState(() {
          _error = result.error ?? '加载白板失败';
          _loaded = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载白板失败：$e';
        _loaded = true;
      });
    }
  }

  Future<void> _save(WhiteboardCanvasViewModel vm) async {
    await _store.save(vm.boardId, vm.exportForSave());
  }

  void _handleExit(BuildContext context) {
    final vm = _viewModel;
    if (vm != null) {
      unawaited(_save(vm));
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        body: Center(
          child: CircularProgressIndicator(
            color: WhiteboardCanvasTokens.action,
            strokeWidth: 2,
          ),
        ),
      );
    }
    final vm = _viewModel;
    if (vm == null || _error != null) {
      return Scaffold(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: WhiteboardCanvasTokens.orphanedBorder,
                size: 36,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error ?? '白板不存在',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    return WhiteboardCanvasScreen(
      viewModel: vm,
      onExit: () => _handleExit(context),
    );
  }
}
