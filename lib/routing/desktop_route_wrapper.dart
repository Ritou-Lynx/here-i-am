/// Desktop route wrapper: installs either the ordinary shared workbench shell
/// or the immersive canvas / reading shell. Ordinary routes pass through on
/// mobile; desktop-only routes render one Spring Rain unavailable surface.
///
/// Usage in GoRoute builder:
///   builder: (_, state) => desktopRouteWrapper(
///     title: '记忆',
///     child: const MemoryCenterScreen(),
///   ),
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/widgets/here_iam_rain_layer.dart';
import 'package:memex/ui/desktop/desktop_workspace_shell.dart';

class DesktopRouteWrapper extends StatelessWidget {
  const DesktopRouteWrapper({
    super.key,
    required this.title,
    this.child,
    this.childBuilder,
    this.mode = DesktopWorkspaceMode.standard,
    this.childOwnsPageTitle = false,
    this.desktopOnly = false,
    this.desktopPlatformOverride,
  })  : assert(child != null || childBuilder != null),
        assert(child == null || childBuilder == null);

  final String title;
  final Widget? child;
  final WidgetBuilder? childBuilder;
  final DesktopWorkspaceMode mode;

  /// F0–F4 pages keep their existing AppBar until their dedicated UI stage.
  /// The shared shell still owns navigation and surface behavior meanwhile.
  final bool childOwnsPageTitle;

  /// Keeps a route registered with its frozen path while declining to mount
  /// its desktop business surface on Android and iOS.
  final bool desktopOnly;

  /// Test-only platform seam. Production callers leave this null.
  final bool? desktopPlatformOverride;

  bool get _isDesktop =>
      desktopPlatformOverride ??
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop && desktopOnly) {
      return _DesktopOnlyUnavailableScreen(title: title);
    }
    final routeChild = childBuilder?.call(context) ?? child!;
    if (!_isDesktop) return routeChild;
    return DesktopWorkspaceShell(
      title: title,
      mode: mode,
      activePath: GoRouterState.of(context).uri.path,
      showPageTitle: !childOwnsPageTitle,
      onBack:
          mode == DesktopWorkspaceMode.immersive ? null : () => _back(context),
      child: routeChild,
    );
  }

  void _back(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }
}

class _DesktopOnlyUnavailableScreen extends StatelessWidget {
  const _DesktopOnlyUnavailableScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = context.hereIamTheme;
    return Scaffold(
      key: const ValueKey('desktop_only_unavailable'),
      backgroundColor: tokens.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HereIamRainLayer(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
                  decoration: BoxDecoration(
                    color: tokens.glassFill,
                    borderRadius: BorderRadius.circular(tokens.cardRadius),
                    border: Border.all(color: tokens.glassStroke),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.desktop_windows_outlined,
                        size: 34,
                        color: tokens.accent,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '$title目前仅在桌面端提供',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '请在 Windows、macOS 或 Linux 设备上打开。你的卡片和来源不会在这里创建副本。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        key: const ValueKey('desktop_only_return_home'),
                        onPressed: () => context.go('/'),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('返回首页'),
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.background,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
