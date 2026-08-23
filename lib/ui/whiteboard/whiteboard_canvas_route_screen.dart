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
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';

/// Route screen for `/whiteboard/:boardId`. [store] is injectable for tests.
class WhiteboardCanvasRouteScreen extends StatefulWidget {
  final String boardId;
  final WhiteboardDriftStore? store;
  final UnifiedCardRepository? cardRepository;
  final Future<UnifiedCardRepository> Function()? repositoryLoader;
  final Future<bool> Function(String boardId, WhiteboardSnapshot snapshot)?
      saveSnapshot;

  const WhiteboardCanvasRouteScreen({
    super.key,
    required this.boardId,
    this.store,
    this.cardRepository,
    this.repositoryLoader,
    this.saveSnapshot,
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
  UnifiedCardRepository? _cardRepository;
  String? _error;
  String? _saveError;
  bool _loaded = false;
  bool _saving = false;
  final Object _workbenchSurfaceOwner = Object();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _viewModel?.selection.removeListener(_syncWorkbenchSelection);
    WhiteboardWorkbenchSurfaceController.instance
        .detach(_workbenchSurfaceOwner);
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loaded = false;
        _error = null;
      });
    }
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
      if (!result.isSuccess || result.snapshot == null) {
        if (!mounted) return;
        setState(() {
          _error = result.error ?? '加载白板失败';
          _loaded = true;
        });
        return;
      }

      final repository = widget.cardRepository ??
          await (widget.repositoryLoader?.call() ??
              WhiteboardDataBootstrap.productionRepository());
      final snapshot = await _hydrateFromRepository(
        result.snapshot!,
        repository,
      );
      if (!mounted) return;
      final oldViewModel = _viewModel;
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: snapshot,
        boardId: widget.boardId,
      );
      vm.onSaveRequested = () => unawaited(_save(vm, announce: true));
      vm.selection.addListener(_syncWorkbenchSelection);
      setState(() {
        _viewModel = vm;
        _cardRepository = repository;
        _error = null;
        _saveError = null;
        _loaded = true;
      });
      oldViewModel?.selection.removeListener(_syncWorkbenchSelection);
      oldViewModel?.dispose();
      _attachWorkbenchSurface(vm);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载白板失败：$e';
        _loaded = true;
      });
    }
  }

  void _attachWorkbenchSurface(WhiteboardCanvasViewModel vm) {
    WhiteboardWorkbenchSurfaceController.instance.attach(
      owner: _workbenchSurfaceOwner,
      boardId: widget.boardId,
      selectedItemIds: vm.selection.selectedItemIds,
      flush: () => _save(vm),
      reload: _reloadWorkbenchSurface,
    );
  }

  /// Reloads an externally-mutated board without tearing down the visible
  /// canvas route. Keeping the existing ViewModel and widget tree avoids a
  /// loading-screen flash and preserves stable Windows accessibility parents
  /// while workbench actions replace the persisted board snapshot.
  Future<void> _reloadWorkbenchSurface() async {
    final vm = _viewModel;
    if (vm == null) {
      await _load();
      return;
    }
    try {
      final result = await _store.load(widget.boardId);
      if (!result.isSuccess || result.snapshot == null) {
        if (!mounted) return;
        setState(() => _saveError = result.error ?? '重新加载白板失败，请重试。');
        return;
      }
      final repository = _cardRepository ??
          widget.cardRepository ??
          await (widget.repositoryLoader?.call() ??
              WhiteboardDataBootstrap.productionRepository());
      final snapshot = await _hydrateFromRepository(
        result.snapshot!,
        repository,
      );
      if (!mounted || !identical(vm, _viewModel)) return;
      vm.loadFromSnapshot(snapshot);
      setState(() {
        _cardRepository = repository;
        _error = null;
        _saveError = null;
      });
      _attachWorkbenchSurface(vm);
    } catch (_) {
      if (!mounted || !identical(vm, _viewModel)) return;
      setState(() => _saveError = '重新加载白板失败，请重试。');
    }
  }

  void _syncWorkbenchSelection() {
    final vm = _viewModel;
    if (vm == null) return;
    WhiteboardWorkbenchSurfaceController.instance.updateSelection(
      _workbenchSurfaceOwner,
      vm.selection.selectedItemIds,
    );
  }

  Future<WhiteboardSnapshot> _hydrateFromRepository(
    WhiteboardSnapshot layout,
    UnifiedCardRepository repository,
  ) async {
    final records = await repository.listCards();
    final sources = {
      for (final record in records)
        if (record.source != null) record.source!.sourceId: record.source!,
    };
    final versions = {
      for (final record in records)
        if (record.currentSourceVersion != null)
          record.currentSourceVersion!.versionId: record.currentSourceVersion!,
    };
    return WhiteboardSnapshot(
      schemaVersion: layout.schemaVersion,
      sources: sources.values.toList(growable: false),
      sourceVersions: versions.values.toList(growable: false),
      cards: records.map((record) => record.card).toList(growable: false),
      boards: layout.boards,
      boardItems: layout.boardItems,
      groups: layout.groups,
      groupMembers: layout.groupMembers,
      edges: layout.edges,
      viewport: layout.viewport,
      updatedAt: layout.updatedAt,
    );
  }

  WhiteboardSnapshot _layoutOnly(WhiteboardSnapshot snapshot) {
    return WhiteboardSnapshot(
      schemaVersion: snapshot.schemaVersion,
      boards: snapshot.boards,
      boardItems: snapshot.boardItems,
      groups: snapshot.groups,
      groupMembers: snapshot.groupMembers,
      edges: snapshot.edges,
      viewport: snapshot.viewport,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<bool> _save(
    WhiteboardCanvasViewModel vm, {
    bool announce = false,
  }) async {
    if (_saving) return false;
    if (mounted) {
      setState(() {
        _saving = true;
        _saveError = null;
      });
    }
    var succeeded = false;
    try {
      final snapshot = _layoutOnly(vm.exportForSave());
      succeeded = await (widget.saveSnapshot?.call(vm.boardId, snapshot) ??
          _store.save(vm.boardId, snapshot));
    } catch (_) {
      succeeded = false;
    }
    if (!mounted) return succeeded;
    setState(() {
      _saving = false;
      _saveError = succeeded ? null : '白板没有保存成功，请重试。';
    });
    if (announce) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(succeeded ? '白板已保存' : _saveError!)),
      );
    }
    return succeeded;
  }

  Future<void> _handleExit() async {
    final vm = _viewModel;
    if (vm != null && !await _save(vm)) {
      return;
    }
    if (mounted) context.go(AppRoutes.whiteboard);
  }

  Future<void> _openCard(CardContract card) async {
    final vm = _viewModel;
    if (vm == null || !await _save(vm)) return;
    if (!mounted) return;
    final sourceId = card.sourceId;
    final target = card.cardKind == CardKind.source &&
            sourceId != null &&
            sourceId.isNotEmpty
        ? AppRoutes.sourceStudyPath(sourceId)
        : AppRoutes.cardEditPath(card.cardId);
    await context.push(target);
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
                onPressed: () => context.go(AppRoutes.whiteboard),
                child: const Text('返回'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('whiteboard_canvas_retry'),
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        WhiteboardCanvasScreen(
          viewModel: vm,
          cardRepository: _cardRepository,
          onOpenCard: (card) => unawaited(_openCard(card)),
          onPersistSnapshot: () => _save(vm),
          onExit: () => unawaited(_handleExit()),
        ),
        if (_saving)
          const Positioned(
            right: 16,
            bottom: 16,
            child: SizedBox(
              key: ValueKey('whiteboard_saving'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_saveError != null)
          Positioned(
            key: const ValueKey('whiteboard_save_error'),
            right: 16,
            bottom: 16,
            child: Material(
              color: WhiteboardCanvasTokens.panelSurface,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _saveError!,
                      style: const TextStyle(
                        color: WhiteboardCanvasTokens.orphanedBorder,
                        fontSize: WhiteboardCanvasTokens.metaSize,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => unawaited(_save(vm, announce: true)),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
