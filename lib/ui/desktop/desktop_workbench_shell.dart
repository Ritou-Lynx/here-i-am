/// Desktop whiteboard workbench shell.
///
/// Desktop and phone are independent app surfaces. This home only exposes
/// desktop-native whiteboard and card-library work loops.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/app_startup_visibility.dart';
import 'package:memex/ui/desktop/desktop_workspace_shell.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

import 'view_models/desktop_home_view_model.dart';
import 'widgets/desktop_module_grid.dart';

/// Desktop workbench home. It never embeds a phone page.
class DesktopWorkbenchShell extends StatefulWidget {
  const DesktopWorkbenchShell({
    super.key,
    required this.characterId,
    this.initialVoiceMode = false,
    this.viewModel,
    this.embeddedInWorkspaceShell = false,
  });

  final String characterId;
  final bool initialVoiceMode;
  final DesktopHomeViewModel? viewModel;
  final bool embeddedInWorkspaceShell;

  @override
  State<DesktopWorkbenchShell> createState() => _DesktopWorkbenchShellState();
}

class _DesktopWorkbenchShellState extends State<DesktopWorkbenchShell> {
  late final DesktopHomeViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel =
        widget.viewModel ?? DesktopHomeViewModel(db: AppDatabase.instance);
    _viewModel.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppStartupVisibilityController.markInteractive();
    });
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  WorkbenchModuleCallbacks get _callbacks {
    return WorkbenchModuleCallbacks(
      onOpenBoard: (boardId) =>
          context.go(AppRoutes.whiteboardCanvasPath(boardId)),
      onOpenBoards: () => context.go(AppRoutes.whiteboard),
      onOpenCardLibrary: () => context.go(AppRoutes.cardLibrary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = ChangeNotifierProvider.value(
      value: _viewModel,
      child: _DesktopWorkbenchContent(callbacks: _callbacks),
    );
    if (widget.embeddedInWorkspaceShell ||
        DesktopWorkspaceScope.contains(context)) {
      return content;
    }
    return DesktopWorkspaceShell(
      title: '首页',
      meta: desktopWorkbenchTodayLabel(),
      activePath: AppRoutes.home,
      child: content,
    );
  }
}

String desktopWorkbenchTodayLabel([DateTime? value]) {
  final now = value ?? DateTime.now();
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}';
}

class _DesktopWorkbenchContent extends StatelessWidget {
  const _DesktopWorkbenchContent({required this.callbacks});

  final WorkbenchModuleCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Consumer<DesktopHomeViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const _WorkbenchLoading();
          final error = vm.error;
          if (error != null) {
            return _WorkbenchError(error: error, onRetry: vm.load);
          }
          final data = vm.data;
          if (data == null) return const _WorkbenchLoading();
          return WorkbenchModuleGrid(data: data, callbacks: callbacks);
        },
      ),
    );
  }
}

class _WorkbenchLoading extends StatelessWidget {
  const _WorkbenchLoading();

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: tokens.action,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '正在读取工作台…',
            style: whiteboardUiTextStyle(fontSize: 14, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _WorkbenchError extends StatelessWidget {
  const _WorkbenchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '工作台数据暂时没有读出来，重试即可继续。',
            style: whiteboardUiTextStyle(fontSize: 14, color: tokens.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: whiteboardUiTextStyle(fontSize: 11, color: tokens.textFaint),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.action,
              minimumSize: const Size(0, 36),
            ),
            child: Text('重试', style: whiteboardUiTextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
