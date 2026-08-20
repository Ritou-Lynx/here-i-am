/// Desktop route wrapper: installs either the ordinary shared workbench shell
/// or the immersive canvas / reading shell. On mobile it passes through.
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

import 'package:memex/ui/desktop/desktop_workspace_shell.dart';

class DesktopRouteWrapper extends StatelessWidget {
  const DesktopRouteWrapper({
    super.key,
    required this.title,
    required this.child,
    this.mode = DesktopWorkspaceMode.standard,
    this.childOwnsPageTitle = false,
  });

  final String title;
  final Widget child;
  final DesktopWorkspaceMode mode;

  /// F0–F4 pages keep their existing AppBar until their dedicated UI stage.
  /// The shared shell still owns navigation and surface behavior meanwhile.
  final bool childOwnsPageTitle;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;
    return DesktopWorkspaceShell(
      title: title,
      mode: mode,
      activePath: GoRouterState.of(context).uri.path,
      showPageTitle: !childOwnsPageTitle,
      onBack:
          mode == DesktopWorkspaceMode.immersive ? null : () => _back(context),
      child: child,
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
