// Copyright 2024 The Memex team. All rights reserved.
// Compass-aligned: GoRouter for declarative routing.
// ViewModels are created in route builders and passed to screens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/repositories/memex_router.dart';

import 'package:memex/ui/character/widgets/about_i_screen.dart';
import 'package:memex/ui/calendar/view_models/calendar_viewmodel.dart';
import 'package:memex/ui/calendar/widgets/calendar_screen.dart';
import 'package:memex/ui/character/widgets/persona_chat_navigation.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/interest/widgets/interest_hub_screen.dart';
import 'package:memex/ui/dev_agent/widgets/dev_room_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/ui/memory/widgets/memory_center_screen.dart';
import 'package:memex/ui/memory/widgets/memory_card_list_page.dart';
import 'package:memex/ui/memory/widgets/lab/fragments_page.dart';
import 'package:memex/ui/memory/widgets/lab/episodes_page.dart';
import 'package:memex/ui/memory/widgets/lab/sagas_page.dart';
import 'package:memex/ui/memory/widgets/lab/query_log_page.dart';
import 'package:memex/ui/memory/widgets/lab/recall_log_page.dart';
import 'package:memex/ui/memory/widgets/lab/skip_retry_page.dart';
import 'package:memex/ui/memory/widgets/lab/dreaming_debug_page.dart';
import 'package:memex/routing/routes.dart';

/// Creates the app [GoRouter]. Root content is built by [rootBuilder].
GoRouter createAppRouter(
  GlobalKey<NavigatorState> navigatorKey,
  Widget Function() rootBuilder,
) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutes.home,
    observers: [personaChatNavigatorObserver],
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => rootBuilder(),
      ),
      GoRoute(
        path: AppRoutes.userSetup,
        builder: (context, state) => UserSetupScreen(
          onUserCreated: () {
            context.go(AppRoutes.home);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.aboutI,
        builder: (_, __) => const AboutIScreen(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenter,
        builder: (_, __) => const MemoryCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterCards,
        builder: (_, __) => const MemoryCardListPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterFragments,
        builder: (_, __) => const LabFragmentsPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterEpisodes,
        builder: (_, __) => const LabEpisodesPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterSagas,
        builder: (_, __) => const LabSagasPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterQueryLog,
        builder: (_, __) => const LabQueryLogPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterRecallLog,
        builder: (_, __) => const LabRecallLogPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterSkipRetry,
        builder: (_, __) => const LabSkipRetryPage(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterDreaming,
        builder: (_, __) => const LabDreamingDebugPage(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, state) {
          final initialDate = state.extra as DateTime? ?? DateTime.now();
          final vm = CalendarViewModel(
            router: context.read<MemexRouter>(),
            initialDate: initialDate,
          );
          vm.fetchMonthData(DateTime(initialDate.year, initialDate.month));
          return CalendarScreen(initialDate: initialDate, viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.personalCenter,
        builder: (_, __) => const PersonalCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.interests,
        builder: (_, __) => const InterestHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.devRoom,
        builder: (_, __) => const DevRoomScreen(),
      ),
    ],
  );
}
