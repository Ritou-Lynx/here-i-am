/// Desktop workbench sidebar — visual-rules §8.1：短横线 + 文字导航。
///
/// 展开 144px、可完全收回到 0px（只留 36px 打开把手）；活动项用
/// 左深右浅的淡绿水墨笔触（不用左侧实线）；收起时内容区真正回收。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_brand_mark.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// 侧栏导航项。
class _NavItem {
  const _NavItem(this.path, this.label);

  final String path;
  final String label;
}

const _navItems = [
  _NavItem(AppRoutes.home, '首页'),
  _NavItem(AppRoutes.cardLibrary, '卡片库'),
  _NavItem(AppRoutes.whiteboard, '白板'),
  _NavItem(AppRoutes.memoryCenter, '记忆'),
  _NavItem(AppRoutes.interests, '阅读'),
  _NavItem(AppRoutes.devRoom, '任务中心'),
];

/// 判断当前路由是否命中某个导航项（白板画布 / 卡片编辑等子路径命中父级）。
bool _matches(String currentPath, String itemPath) {
  if (itemPath == AppRoutes.home) return currentPath == AppRoutes.home;
  if (itemPath == AppRoutes.cardLibrary &&
      currentPath == AppRoutes.linkImport) {
    return true;
  }
  if (currentPath == itemPath) return true;
  return currentPath.startsWith('$itemPath/');
}

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    this.collapsed = false,
    this.currentPath,
  });

  /// true = 完全收起到 0 宽度（把手由父级提供）。
  final bool collapsed;

  /// Optional seam for shell tests and embedding outside a GoRouter builder.
  final String? currentPath;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    if (collapsed) return const SizedBox.shrink();
    final path = currentPath ?? GoRouterState.of(context).uri.path;
    return SizedBox(
      key: const ValueKey('desktop_sidebar'),
      width: DesktopWorkspaceTokens.sidebarExpandedWidth,
      child: ColoredBox(
        color: tokens.canvas,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: DesktopBrandLockup(),
                  ),
                  const SizedBox(height: 16),
                  for (final item in _navItems)
                    _SidebarItem(item: item, currentPath: path),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      '工作台',
                      style: whiteboardUiTextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: tokens.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // A short, fading paper seam replaces a full-height divider.
            Positioned(
              right: 0,
              top: 48,
              bottom: 48,
              width: 16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        tokens.canvas.withValues(alpha: 0),
                        tokens.divider.withValues(alpha: 0.28),
                        tokens.canvas.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.currentPath});

  final _NavItem item;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final active = _matches(currentPath, item.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Semantics(
        key: ValueKey('desktop_sidebar_nav_${item.label}'),
        selected: active,
        button: true,
        child: InkWell(
          onTap: () => context.go(item.path),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: active
                ? BoxDecoration(
                    // Active ink: dense at left, fading into the paper.
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        tokens.actionSoft.withValues(alpha: 0.72),
                        tokens.actionSoft.withValues(alpha: 0.28),
                        tokens.canvas.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.58, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 2,
                  decoration: BoxDecoration(
                    color: active ? tokens.action : tokens.textFaint,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: whiteboardUiTextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: active ? tokens.textPrimary : tokens.textMuted,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
