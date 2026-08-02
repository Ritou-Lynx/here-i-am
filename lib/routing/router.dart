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
import 'package:memex/ui/chat/view_models/chat_viewmodel.dart';
import 'package:memex/ui/chat/widgets/chat_history_screen.dart';
import 'package:memex/ui/character/widgets/persona_chat_navigation.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/interest/widgets/interest_hub_screen.dart';
import 'package:memex/ui/dev_agent/widgets/dev_room_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
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
        path: AppRoutes.chatHistory,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final agentName = extra['agentName'] as String?;
          final title = extra['title'] as String?;
          final vm = ChatViewModel(
            router: context.read<MemexRouter>(),
            agentName: agentName,
          );
          return ChatHistoryScreen(
            viewModel: vm,
            agentName: agentName,
            title: title,
          );
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
