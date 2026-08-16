/// Desktop workbench sidebar — visual-rules §8.1：短横线 + 文字导航。
///
/// 展开 144px、可完全收回到 0px（只留 36px 打开把手）；活动项用
/// 左深右浅的淡绿水墨笔触（不用左侧实线）；收起时内容区真正回收。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

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
  if (currentPath == itemPath) return true;
  return currentPath.startsWith('$itemPath/');
}

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({super.key, this.collapsed = false});

  /// true = 完全收起到 0 宽度（把手由父级提供）。
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    const tokens = SpringRainUiTokens.daylight;
    if (collapsed) return const SizedBox.shrink();
    return Container(
      width: 144,
      color: tokens.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            // 品牌区：正式 `i` 标志资产在 assets/branding，这里只放名称。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '故我在',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final item in _navItems) _SidebarItem(item: item),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                '工作台',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textTertiary,
                  height: 1.4,
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
  const _SidebarItem({required this.item});

  final _NavItem item;

  @override
  Widget build(BuildContext context) {
    const tokens = SpringRainUiTokens.daylight;
    final currentPath = GoRouterState.of(context).uri.path;
    final active = _matches(currentPath, item.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: () => context.go(item.path),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: active
              ? BoxDecoration(
                  // 活动水墨：左深右浅、边缘不规则（不用左侧实线）。
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      tokens.accentSoft.withValues(alpha: 0.9),
                      tokens.accentSoft.withValues(alpha: 0.35),
                      tokens.surface.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
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
                  color: active ? tokens.accent : tokens.textTertiary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: active ? tokens.textPrimary : tokens.textSecondary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
