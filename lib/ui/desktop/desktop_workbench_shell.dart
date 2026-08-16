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
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

import 'view_models/desktop_home_view_model.dart';
import 'widgets/desktop_chat_overlay.dart';
import 'widgets/desktop_module_grid.dart';
import 'widgets/desktop_sidebar.dart';

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
  bool _sidebarCollapsed = false;

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
    const tokens = SpringRainUiTokens.daylight;
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: ChangeNotifierProvider.value(
        value: _viewModel,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopSidebar(collapsed: _sidebarCollapsed),
            _SidebarHandle(
              collapsed: _sidebarCollapsed,
              onToggle: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            ),
            Expanded(child: _buildContent(tokens)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SpringRainUiTokens tokens) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Text(
                  '首页',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                    height: 1.28,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _todayLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textTertiary,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Consumer<DesktopHomeViewModel>(
                builder: (context, vm, _) {
                  if (vm.isLoading) return const _WorkbenchLoading();
                  final error = vm.error;
                  if (error != null) {
                    return _WorkbenchError(
                      error: error,
                      onRetry: () => vm.load(),
                    );
                  }
                  final data = vm.data;
                  if (data == null) {
                    return const _WorkbenchLoading();
                  }
                  return WorkbenchModuleGrid(
                    data: data,
                    callbacks: _callbacks,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}';
  }
}

/// 侧栏收回 / 展开把手（收起时 36px，不压旧边界、无绿色残影）。
class _SidebarHandle extends StatelessWidget {
  const _SidebarHandle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    const tokens = SpringRainUiTokens.daylight;
    return Container(
      width: 36,
      color: tokens.canvas,
      alignment: Alignment.center,
      child: IconButton(
        key: const ValueKey('desktop_sidebar_handle'),
        onPressed: onToggle,
        icon: Icon(
          collapsed
              ? Icons.chevron_right_rounded
              : Icons.chevron_left_rounded,
          size: 18,
        ),
        color: tokens.textTertiary,
        tooltip: collapsed ? '展开侧栏' : '收起侧栏',
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _WorkbenchLoading extends StatelessWidget {
  const _WorkbenchLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: SpringRainUiTokens.daylightAccent,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '正在读取工作台…',
            style: TextStyle(
              fontSize: 14,
              color: SpringRainUiTokens.daylightTextSecondary,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '工作台数据暂时没有读出来，重试即可继续。',
            style: TextStyle(
              fontSize: 14,
              color: SpringRainUiTokens.daylightTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: SpringRainUiTokens.daylightTextTertiary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: SpringRainUiTokens.daylightAccent,
              minimumSize: const Size(0, 36),
            ),
            child: const Text('重试', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
