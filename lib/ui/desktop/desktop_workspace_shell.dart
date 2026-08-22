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
      child: Builder(
        builder: (context) {
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
        },
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!collapsed)
              CustomPaint(
                key: const ValueKey('desktop_sidebar_paper_seam'),
                painter: _PaperSeamPainter(tokens.divider),
              ),
            Center(
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
          ],
        ),
      ),
    );
  }
}

/// A two-dimensional paper seam: it fades horizontally into the canvas and
/// vertically before reaching either window edge. Unlike the previous
/// rectangular gradient, it has no clipped top/bottom endpoints.
class _PaperSeamPainter extends CustomPainter {
  const _PaperSeamPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final seamRect = Rect.fromCenter(
      center: Offset(0, size.height / 2),
      width: size.width * 1.7,
      height: size.height * 0.78,
    );
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1,
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.42, 1],
      ).createShader(seamRect);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _PaperSeamPainter oldDelegate) =>
      oldDelegate.color != color;
}
