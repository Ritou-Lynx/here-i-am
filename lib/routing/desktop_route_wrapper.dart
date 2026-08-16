/// Desktop route wrapper: wraps a page in a Scaffold with a back-to-home
/// AppBar when running on desktop. On mobile, passes through unchanged.
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

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class DesktopRouteWrapper extends StatelessWidget {
  const DesktopRouteWrapper({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          tooltip: '返回首页',
          onPressed: () {
            // Use pop if we can, otherwise go to home.
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          title,
          style: whiteboardUiTextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: child,
    );
  }
}