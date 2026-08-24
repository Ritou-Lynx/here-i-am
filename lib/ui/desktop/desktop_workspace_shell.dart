/// Shared desktop shell for ordinary and immersive work surfaces.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_page_title.dart';
import 'package:memex/ui/desktop/widgets/desktop_sidebar.dart';

enum DesktopWorkspaceMode {
  /// Ordinary work surface: collapsible navigation plus optional page title.
  standard,

  /// Canvas / reading / media surface: no persistent navigation or top bar.
  immersive,
}

class DesktopWorkspaceShell extends StatefulWidget {
  const DesktopWorkspaceShell({
    super.key,
    required this.title,
    required this.child,
    this.mode = DesktopWorkspaceMode.standard,
    this.meta,
    this.actions = const [],
    this.onBack,
    this.showPageTitle = true,
    this.initialSidebarCollapsed = false,
    this.activePath,
  });

  final String title;
  final Widget child;
  final DesktopWorkspaceMode mode;
  final String? meta;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showPageTitle;
  final bool initialSidebarCollapsed;
  final String? activePath;

  @override
  State<DesktopWorkspaceShell> createState() => _DesktopWorkspaceShellState();
}

/// Marks descendants that already live inside the persistent desktop shell.
///
/// Route wrappers use this seam to avoid mounting a second sidebar when a
/// standard work surface is hosted by the persistent desktop routing shell.
class DesktopWorkspaceScope extends InheritedWidget {
  const DesktopWorkspaceScope({
    super.key,
    required super.child,
  });

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopWorkspaceScope>() !=
      null;

  @override
  bool updateShouldNotify(DesktopWorkspaceScope oldWidget) => false;
}

class _DesktopWorkspaceShellState extends State<DesktopWorkspaceShell> {
  late bool _sidebarCollapsed;

  @override
  void initState() {
    super.initState();
    _sidebarCollapsed = widget.initialSidebarCollapsed;
  }

  @override
  void didUpdateWidget(covariant DesktopWorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode &&
        widget.mode == DesktopWorkspaceMode.standard) {
      _sidebarCollapsed = widget.initialSidebarCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DesktopWorkspaceTheme(
      // MaterialApp owns a root ScaffoldMessenger above this scoped theme.
      // Desktop feedback must instead be inserted below DesktopWorkspaceTheme
      // so SnackBar overlays inherit the Lieflat Palm colors and typography.
      child: ScaffoldMessenger(
        key: const ValueKey('desktop_workspace_scaffold_messenger'),
        child: Builder(builder: (context) {
          final tokens = DesktopWorkspaceTokens.of(context);
          if (widget.mode == DesktopWorkspaceMode.immersive) {
            return Scaffold(
              key: const ValueKey('desktop_immersive_shell'),
              backgroundColor: tokens.canvas,
              body: widget.child,
            );
          }
          return DesktopWorkspaceScope(
            child: Scaffold(
              key: const ValueKey('desktop_standard_shell'),
              backgroundColor: tokens.canvas,
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopSidebar(
                    collapsed: _sidebarCollapsed,
                    currentPath: widget.activePath,
                  ),
                  _DesktopSidebarHandle(
                    collapsed: _sidebarCollapsed,
                    onToggle: () => setState(
                      () => _sidebarCollapsed = !_sidebarCollapsed,
                    ),
                  ),
                  Expanded(
                    key: const ValueKey('desktop_workspace_content'),
                    child: ColoredBox(
                      color: tokens.canvas,
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.showPageTitle)
                              DesktopPageTitle(
                                title: widget.title,
                                meta: widget.meta,
                                actions: widget.actions,
                                onBack: widget.onBack,
                              ),
                            Expanded(child: widget.child),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DesktopSidebarHandle extends StatelessWidget {
  const _DesktopSidebarHandle({
    required this.collapsed,
    required this.onToggle,
  });

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return SizedBox(
      key: const ValueKey('desktop_sidebar_handle'),
      width: DesktopWorkspaceTokens.sidebarHandleWidth,
      child: ColoredBox(
        color: tokens.canvas,
        // The shared canvas and this narrow strip are the seam. Do not paint a
        // full-height divider or a rectangular shadow behind the toggle.
        child: Center(
          child: IconButton(
            key: const ValueKey('desktop_sidebar_toggle'),
            onPressed: onToggle,
            icon: Icon(
              collapsed
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
              size: 18,
            ),
            color: tokens.textFaint,
            tooltip: collapsed ? '展开侧栏' : '收起侧栏',
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}
