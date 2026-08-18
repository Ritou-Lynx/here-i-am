// Copyright 2024 The Memex team. All rights reserved.
// Aligned with Compass: route path constants for go_router.

/// Route path constants for [GoRouter].
/// ViewModels are created in route builders and passed to screens.
abstract final class AppRoutes {
  AppRoutes._();

  /// Home (main screen with tabs).
  static const String home = '/';

  /// Desktop home dashboard (desktop platforms only).
  static const String desktopHome = '/desktop-home';

  /// Personal center (settings).
  static const String personalCenter = '/personal-center';

  /// Reading and games entry.
  static const String interests = '/interests';

  /// Blind, on-device book TTS voice bakeoff.
  static const String bookTtsVoiceLab = '/book-tts-voice-lab';

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

  // ── Whiteboard production routes (W6 integration base — signatures frozen) ──
  // Parallel windows must NOT edit these paths or parameters; they only fill
  // the placeholder screens.

  /// Whiteboard index (board list / create).
  static const String whiteboard = '/whiteboard';

  /// Full-screen canvas for one board; param: boardId.
  static const String whiteboardCanvas = '/whiteboard/:boardId';

  /// The single card library.
  static const String cardLibrary = '/cards';

  /// Card rich text editor; param: cardId.
  static const String cardEdit = '/cards/:cardId';

  /// Per-source study view (video / reading); param: sourceId.
  static const String sourceStudy = '/sources/:sourceId';

  /// Link ingestion entry.
  static const String linkImport = '/import';

  /// Expands the frozen [whiteboardCanvas] path with a concrete [boardId].
  static String whiteboardCanvasPath(String boardId) =>
      whiteboardCanvas.replaceFirst(':boardId', boardId);

  /// Expands the frozen [cardEdit] path with a concrete [cardId].
  static String cardEditPath(String cardId) =>
      cardEdit.replaceFirst(':cardId', cardId);

  /// Expands the frozen [sourceStudy] path with a concrete [sourceId].
  static String sourceStudyPath(String sourceId) =>
      sourceStudy.replaceFirst(':sourceId', sourceId);
}
