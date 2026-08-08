/// Thin wrapper that pushes [CompanionReviewScreen] as a standalone page
/// with an AppBar, so Memory Center can reuse the user-facing card list
/// (spring rain skin, detail -> MemoryCardDetailScreenV3) instead of the
/// diagnostic [LabCardsPage].
///
/// [CompanionReviewScreen] is normally embedded inside Life Space tab0
/// without its own AppBar; here we add a minimal chrome so the back stack
/// works when navigated from Memory Center.
library;

import 'package:flutter/material.dart';
import 'package:memex/ui/companion/widgets/companion_review_screen.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

class MemoryCardListPage extends StatelessWidget {
  const MemoryCardListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.springRainUi;
    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        title: const Text('记忆卡片'),
        backgroundColor: t.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        elevation: 0,
      ),
      body: const CompanionReviewScreen(),
    );
  }
}
