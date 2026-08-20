/// 桌面工作台外壳（Task S）— spine-contract §3.2 首页模块网格。
///
/// 桌面首页不再是手机聊天页套壳：144–148px 可回收侧栏 + 高密度模块网格
/// 一屏读懂全貌；林埃对话改为按需悬浮、可收起（spine-contract §3.5）。
/// 数据与手机完全同源：全部来自现有 repository / service，不复制实体。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/companion/widgets/companion_life_space_screen.dart';
import 'package:memex/ui/core/app_startup_visibility.dart';
import 'package:memex/ui/desktop/desktop_workspace_shell.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

import 'view_models/desktop_home_view_model.dart';
import 'widgets/desktop_module_grid.dart';

/// Desktop workbench home: the module-grid workbench replacing the mobile
/// chat page on desktop windows (spine-contract §2.9 桌面与手机同源但改变
/// 呈现密度).
class DesktopWorkbenchShell extends StatefulWidget {
  const DesktopWorkbenchShell({
    super.key,
    required this.characterId,
    this.initialVoiceMode = false,
  });

  final String characterId;
  final bool initialVoiceMode;

  @override
  State<DesktopWorkbenchShell> createState() => _DesktopWorkbenchShellState();
}

class _DesktopWorkbenchShellState extends State<DesktopWorkbenchShell> {
  late final DesktopHomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DesktopHomeViewModel(db: AppDatabase.instance);
    _viewModel.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppStartupVisibilityController.markInteractive();
    });
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  WorkbenchModuleCallbacks get _callbacks {
    return WorkbenchModuleCallbacks(
      onOpenObservation: _openLifeSpace,
      onOpenSchedule: () => context.go(AppRoutes.calendar),
      onOpenBoard: (boardId) =>
          context.go(AppRoutes.whiteboardCanvasPath(boardId)),
      onOpenTaskCenter: () => context.go(AppRoutes.devRoom),
      onOpenCardLibrary: () => context.go(AppRoutes.cardLibrary),
      onOpenMemoryCenter: () => context.go(AppRoutes.memoryCenter),
      onContinueChat: () {}, // Global overlay handles chat; no-op here.
    );
  }

  void _openLifeSpace() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const CompanionLifeSpaceScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: DesktopWorkspaceShell(
        title: '首页',
        meta: _todayLabel(),
        activePath: AppRoutes.home,
        child: _DesktopWorkbenchContent(callbacks: _callbacks),
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}';
  }
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
          return WorkbenchModuleGrid(
            data: data,
            callbacks: callbacks,
          );
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
            style: whiteboardUiTextStyle(
              fontSize: 14,
              color: tokens.textMuted,
            ),
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
            style: whiteboardUiTextStyle(
              fontSize: 14,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: whiteboardUiTextStyle(
              fontSize: 11,
              color: tokens.textFaint,
            ),
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
