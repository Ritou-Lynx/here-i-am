/// Official Here I am plant-i brand components for desktop surfaces.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class DesktopBrandMark extends StatelessWidget {
  const DesktopBrandMark({super.key, this.size = 40});

  static const assetPath =
      'assets/branding/hereiam_v3_logo/logo_foreground_ink_green_1024.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '故我在 i 品牌标志',
      image: true,
      child: SizedBox.square(
        key: const ValueKey('desktop_brand_mark'),
        dimension: size,
        child: ClipRect(
          child: Transform.scale(
            // The Android-ready source keeps generous adaptive-icon safety
            // padding. Crop only at presentation time; keep the formal plant
            // artwork itself untouched.
            scale: 2.15,
            child: const Image(
              key: ValueKey('desktop_brand_asset'),
              image: AssetImage(assetPath),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopBrandLockup extends StatelessWidget {
  const DesktopBrandLockup({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DesktopBrandMark(size: 36),
        const SizedBox(width: 8),
        Text(
          '故我在',
          style: whiteboardUiTextStyle(
            fontSize: 15,
            height: 1.35,
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
