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
import 'package:memex/ui/book/book_tts_voice_lab_screen.dart';
import 'package:memex/ui/dev_agent/widgets/dev_room_screen.dart';
import 'package:memex/ui/memory/widgets/memory_center_screen.dart';
import 'package:memex/ui/memory/widgets/memory_card_list_page.dart';
import 'package:memex/ui/memory/widgets/lab/fragments_page.dart';
import 'package:memex/ui/memory/widgets/lab/episodes_page.dart';
import 'package:memex/ui/memory/widgets/lab/sagas_page.dart';
import 'package:memex/ui/memory/widgets/lab/query_log_page.dart';
import 'package:memex/ui/memory/widgets/lab/recall_log_page.dart';
import 'package:memex/ui/memory/widgets/lab/skip_retry_page.dart';
import 'package:memex/ui/memory/widgets/lab/dreaming_debug_page.dart';
// Whiteboard production routes (W6 integration base — signatures frozen).
// Parallel windows fill the placeholder screens; they do NOT edit router.dart.
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';
import 'package:memex/ui/whiteboard/link_import_screen.dart';
import 'package:memex/ui/whiteboard/source_study_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';
import 'package:memex/routing/desktop_route_wrapper.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/desktop_workspace_shell.dart';

/// Creates the app [GoRouter]. Root content is built by [rootBuilder].
GoRouter createAppRouter(
    GlobalKey<NavigatorState> navigatorKey, Widget Function() rootBuilder,
    {bool? desktopPlatformOverride}) {
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
        path: AppRoutes.aboutI,
        builder: (_, __) => const AboutIScreen(),
      ),
      GoRoute(
        path: AppRoutes.memoryCenter,
        builder: (_, __) => const DesktopRouteWrapper(
          title: '记忆',
          child: MemoryCenterScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterCards,
        builder: (_, __) => const DesktopRouteWrapper(
          title: '记忆卡片',
          child: MemoryCardListPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterFragments,
        builder: (_, __) => const DesktopRouteWrapper(
          title: '片段',
          child: LabFragmentsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterEpisodes,
        builder: (_, __) => const DesktopRouteWrapper(
          title: '情节',
          child: LabEpisodesPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.memoryCenterSagas,
        builder: (_, __) => const DesktopRouteWrapper(
          title: '故事',
          child: LabSagasPage(),
        ),
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
          return DesktopRouteWrapper(
            title: '日程',
            child: CalendarScreen(initialDate: initialDate, viewModel: vm),
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
        path: AppRoutes.bookTtsVoiceLab,
        builder: (_, __) => const BookTtsVoiceLabScreen(),
      ),
      GoRoute(
        path: AppRoutes.devRoom,
        builder: (_, __) => const DesktopRouteWrapper(
          title: '任务中心',
          child: DevRoomScreen(),
        ),
      ),
      // ── Whiteboard production routes (W6 integration base) ──────────────
      // Route paths and parameter signatures are frozen once here; parallel
      // windows (W1 interactions / W2 rich text / W3 link ingestion / W4
      // video) only replace placeholder screen bodies, never these entries.
      GoRoute(
        path: AppRoutes.whiteboard,
        builder: (_, __) => DesktopRouteWrapper(
          title: '白板',
          childOwnsPageTitle: true,
          desktopOnly: true,
          desktopPlatformOverride: desktopPlatformOverride,
          childBuilder: (_) => const WhiteboardIndexScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.whiteboardCanvas,
        builder: (context, state) => DesktopRouteWrapper(
          title: '白板',
          mode: DesktopWorkspaceMode.immersive,
          desktopOnly: true,
          desktopPlatformOverride: desktopPlatformOverride,
          childBuilder: (_) => WhiteboardCanvasRouteScreen(
            boardId: state.pathParameters['boardId']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.cardLibrary,
        builder: (_, __) => DesktopRouteWrapper(
          title: '卡片库',
          childOwnsPageTitle: true,
          desktopOnly: true,
          desktopPlatformOverride: desktopPlatformOverride,
          childBuilder: (_) => const CardLibraryScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.cardEdit,
        builder: (context, state) => DesktopRouteWrapper(
          title: '卡片编辑',
          childOwnsPageTitle: true,
          desktopOnly: true,
          desktopPlatformOverride: desktopPlatformOverride,
          childBuilder: (_) => CardRichTextEditorScreen(
            cardId: state.pathParameters['cardId']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.sourceStudy,
        builder: (context, state) => DesktopRouteWrapper(
          title: '来源研读',
          mode: DesktopWorkspaceMode.immersive,
          desktopOnly: true,
          desktopPlatformOverride: desktopPlatformOverride,
          childBuilder: (_) => SourceStudyScreen(
            sourceId: state.pathParameters['sourceId']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.linkImport,
        builder: (_, __) => DesktopRouteWrapper(
          title: '导入链接',
          childOwnsPageTitle: true,
          desktopOnly: true,
          desktopPlatformOverride: desktopPlatformOverride,
          childBuilder: (_) => const LinkImportScreen(),
        ),
      ),
    ],
  );
}
