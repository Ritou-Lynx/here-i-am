/// Desktop shell scaffold — the persistent sidebar + workspace layout that
/// mirrors the web MVP shell (`desktop/whiteboard_mvp/index.html` +
/// `styles.css` `.hia-app`).
///
/// On desktop platforms (Windows / Linux / macOS) the whiteboard index, card
/// library and future home dashboard render inside this shell. On mobile the
/// shell is NOT used — those screens keep their existing Scaffold bodies so
/// the mobile app is unchanged.
///
/// The shell provides:
/// - A collapsible sidebar (brand mark, nav entries, status foot).
/// - A workspace slot on the right that the page fills.
/// - No persistent top AppBar — pages render their own page head inside the
///   workspace, per the whiteboard spine contract.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_shell_tokens.dart';

/// Whether the current platform should use the desktop shell.
bool isDesktopPlatform() =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// A single sidebar navigation entry.
class DesktopNavEntry {
  final String label;
  final String routePath;
  final IconData icon;

  const DesktopNavEntry({
    required this.label,
    required this.routePath,
    required this.icon,
  });
}

/// The desktop shell. Wraps [child] in a sidebar + workspace grid.
///
/// [activeRoute] is the current full route path (e.g. `/whiteboard`); used to
/// highlight the matching nav entry. Pages are built by the router and passed
/// as [child]; the shell itself does not navigate, it only renders chrome.
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.child,
    required this.activeRoute,
    this.entries = defaultNavEntries,
  });

  final Widget child;
  final String activeRoute;
  final List<DesktopNavEntry> entries;

  static const List<DesktopNavEntry> defaultNavEntries = [
    DesktopNavEntry(
      label: '首页',
      routePath: AppRoutes.home,
      icon: Icons.home_outlined,
    ),
    DesktopNavEntry(
      label: '白板',
      routePath: AppRoutes.whiteboard,
      icon: Icons.space_dashboard_outlined,
    ),
    DesktopNavEntry(
      label: '卡片库',
      routePath: AppRoutes.cardLibrary,
      icon: Icons.collections_bookmark_outlined,
    ),
  ];

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  bool _navCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesktopShellTokens.canvas,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    if (_navCollapsed) {
      return _buildCollapsedRail();
    }
    return _buildExpandedSidebar();
  }

  Widget _buildExpandedSidebar() {
    return Container(
      width: DesktopShellTokens.sidebarWidth,
      color: DesktopShellTokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                _BrandMark(),
                const SizedBox(width: 10),
                Text(
                  '故我在',
                  style: TextStyle(
                    fontSize: DesktopShellTokens.moduleTitle,
                    fontWeight: FontWeight.w600,
                    color: DesktopShellTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ...widget.entries.map(_buildNavEntry),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: DesktopShellTokens.greenMid,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '本地',
                  style: TextStyle(
                    fontSize: DesktopShellTokens.status,
                    color: DesktopShellTokens.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedRail() {
    return Container(
      width: 0,
      color: DesktopShellTokens.canvas,
    );
  }

  Widget _buildNavEntry(DesktopNavEntry entry) {
    final isActive = _routeMatches(widget.activeRoute, entry.routePath);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => context.go(entry.routePath),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  size: 18,
                  color: isActive
                      ? DesktopShellTokens.green
                      : DesktopShellTokens.textMuted,
                ),
                const SizedBox(width: 9),
                Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: DesktopShellTokens.content,
                    fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                    color: isActive
                        ? DesktopShellTokens.green
                        : DesktopShellTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `/whiteboard/:boardId` should still highlight the `白板` entry.
  bool _routeMatches(String current, String entryPath) {
    if (current == entryPath) return true;
    if (entryPath == AppRoutes.whiteboard) {
      return current.startsWith('/whiteboard');
    }
    if (entryPath == AppRoutes.cardLibrary) {
      return current.startsWith('/cards');
    }
    return false;
  }
}

/// The `i` plant brand mark — a small dark rounded square placeholder.
/// Replaced by the real SVG asset once asset bundling is wired; the shape
/// keeps the sidebar layout stable.
class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: DesktopShellTokens.textPrimary,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Center(
        child: Text(
          'i',
          style: TextStyle(
            color: DesktopShellTokens.canvas,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}