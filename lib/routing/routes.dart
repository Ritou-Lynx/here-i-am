// Copyright 2024 The Memex team. All rights reserved.
// Aligned with Compass: route path constants for go_router.

/// Route path constants for [GoRouter].
/// ViewModels are created in route builders and passed to screens.
abstract final class AppRoutes {
  AppRoutes._();

  /// Home (main screen with tabs).
  static const String home = '/';

  /// User setup (onboarding).
  static const String userSetup = '/user-setup';

  /// Personal center (settings).
  static const String personalCenter = '/personal-center';

  /// Reading and games entry.
  static const String interests = '/interests';

  /// Dev Room.
  static const String devRoom = '/dev-room';

  /// Timeline card detail; push as '/card/$cardId'.
  static const String timelineCardDetail = '/card';

  /// Calendar (push with extra: DateTime initialDate).
  static const String calendar = '/calendar';

  /// Memory.
  static const String memory = '/memory';

  /// "关于 I" — minimal settings for the singleton companion (avatar, chat
  /// background). Replaces the multi-character config screen.
  static const String aboutI = '/about-i';

  /// Memory Center — unified entry for browsing, organizing and diagnosing
  /// the Memory V3 system. Replaces the old Memory V3 Lab hub.
  static const String memoryCenter = '/memory-center';

  /// Memory Center sub-routes (pushed from the hub).
  static const String memoryCenterCards = '/memory-center/cards';
  static const String memoryCenterFragments = '/memory-center/fragments';
  static const String memoryCenterEpisodes = '/memory-center/episodes';
  static const String memoryCenterSagas = '/memory-center/sagas';
  static const String memoryCenterQueryLog = '/memory-center/query-log';
  static const String memoryCenterRecallLog = '/memory-center/recall-log';
  static const String memoryCenterSkipRetry = '/memory-center/skip-retry';
  static const String memoryCenterDreaming = '/memory-center/dreaming';
}
