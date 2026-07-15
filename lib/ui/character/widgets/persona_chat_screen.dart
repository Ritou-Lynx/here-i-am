import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/routing/routes.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:memex/agent/built_in_tools/asset_analysis_tool.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/asr/media_button_service.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/data/services/active_persona_chat_service.dart';
import 'package:memex/data/services/bad_case_collector.dart';
import 'package:memex/data/services/tts_service.dart';
import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/magic_motion_flamingo_controller.dart';
import 'package:memex/data/services/svakom_toy_controller.dart';
import 'package:memex/data/services/toy_control_service.dart'
    show ToyControlService, ToyController;
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/persona_chat_open_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/media_input_attachment.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/reading/reading_share_parser.dart';
import 'package:memex/ui/character/widgets/addenda/message_addendum_renderer.dart';
import 'package:memex/ui/character/widgets/voice_input_button.dart';
import 'package:memex/ui/character/widgets/chat_task_capsule.dart';
import 'package:memex/ui/companion/widgets/companion_media_tray.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/widgets/toast.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/ui/core/widgets/here_iam_glass_surface.dart';
import 'package:memex/ui/core/widgets/here_iam_rain_layer.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:intl/intl.dart';

Color get _personaStageInk => HereIamThemeRuntime.current.background;
Color get _personaPanel => HereIamThemeRuntime.current.surfaceSoft;
Color get _personaPanelSoft => HereIamThemeRuntime.current.surface;
Color get _personaText => HereIamThemeRuntime.current.textPrimary;
Color get _personaTextMuted => HereIamThemeRuntime.current.textSecondary;
Color get _personaAccent => HereIamThemeRuntime.current.accent;
Color get _personaAccentCool => HereIamThemeRuntime.current.accentSoft;
Color get _personaLine => HereIamThemeRuntime.current.surfaceDeep;

const _voiceModeIdleFollowUpSilenceTimeout = Duration(seconds: 10);
const _voiceModeMaxRecordingDuration = Duration(seconds: 120);
const _voiceModeMaxSilentFollowUps = 8;
const _composerStaleGuardPollDelays = <Duration>[
  Duration(milliseconds: 50),
  Duration(milliseconds: 150),
  Duration(milliseconds: 300),
  Duration(milliseconds: 600),
  Duration(milliseconds: 1000),
  Duration(milliseconds: 1500),
];

String _chatUiText({required String zh, required String en}) {
  return UserStorage.l10n.localeName.toLowerCase().startsWith('zh') ? zh : en;
}

const _personaChatImageAttachmentPathKeys = <String>[
  'sourcePath',
  'originalPath',
  'filePath',
  'path',
  'localPath',
];

@visibleForTesting
String? personaChatRecoverableImageAttachmentPath(
  Map<dynamic, dynamic> attachment,
) {
  for (final key in _personaChatImageAttachmentPathKeys) {
    final raw = attachment[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    if (raw.startsWith('file://')) {
      try {
        return Uri.parse(raw).toFilePath();
      } catch (_) {
        return raw.replaceFirst('file://', '');
      }
    }
    return raw;
  }
  return null;
}

bool _personaChatAttachmentLooksLikeImage(Map<dynamic, dynamic> attachment) {
  final mimeType = attachment['mimeType']?.toString().toLowerCase().trim();
  if (mimeType != null && mimeType.startsWith('image/')) return true;
  final sourcePath = personaChatRecoverableImageAttachmentPath(attachment);
  return sourcePath != null && _personaChatMimeTypeFromPath(sourcePath) != null;
}

@visibleForTesting
bool personaChatImageAttachmentCanBeRecorded(Map<dynamic, dynamic> attachment) {
  if (!_personaChatAttachmentLooksLikeImage(attachment)) return false;
  final base64 = attachment['base64']?.toString();
  return (base64 != null && base64.isNotEmpty) ||
      personaChatRecoverableImageAttachmentPath(attachment) != null;
}

String _personaChatImageMimeTypeForAttachment(
  Map<dynamic, dynamic> attachment,
) {
  final mimeType = attachment['mimeType']?.toString().toLowerCase().trim();
  if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
  final sourcePath = personaChatRecoverableImageAttachmentPath(attachment);
  return _personaChatMimeTypeFromPath(sourcePath ?? '') ?? 'image/jpeg';
}

String? _personaChatMimeTypeFromPath(String sourcePath) {
  final path = sourcePath.split('?').first.split('#').first.toLowerCase();
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.webp')) return 'image/webp';
  if (path.endsWith('.gif')) return 'image/gif';
  if (path.endsWith('.heic')) return 'image/heic';
  if (path.endsWith('.heif')) return 'image/heif';
  if (path.endsWith('.bmp')) return 'image/bmp';
  if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}

@visibleForTesting
bool personaChatVoiceIdleFollowUpShouldForceClose(
  int followUpIndex, {
  int maxFollowUps = _voiceModeMaxSilentFollowUps,
}) {
  return followUpIndex >= maxFollowUps;
}

@visibleForTesting
String personaChatVoiceIdleFollowUpPrompt({
  required int followUpIndex,
  required bool forceClose,
}) {
  if (forceClose) {
    return '[The user has been silent for about 60 seconds again in chat voice '
        'mode. This is silent follow-up $followUpIndex. They may have fallen '
        'asleep. Say a very soft, brief goodnight or closing line, then call '
        '`end_voice_mode` in this same turn. Do not use markdown, action text, '
        'or parenthetical thoughts.]';
  }
  return '[The user has been silent for about 60 seconds in chat voice mode. '
      'This is silent follow-up $followUpIndex. React naturally in one or two '
      'short spoken sentences. If the recent conversation is about sleep, '
      'bedtime, rest, or the user wanting company while falling asleep, keep '
      'speaking softly and do not require them to answer. Otherwise gently ask '
      'if they are still there or continue the topic. Vary your wording. Do '
      'not use markdown, action text, or parenthetical thoughts.]';
}

@visibleForTesting
bool personaChatComposerTextLooksLikeSentRemnant({
  required String currentText,
  required String sentText,
}) {
  final current = _normalizeComposerGuardText(currentText);
  final sent = _normalizeComposerGuardText(sentText);
  if (current.isEmpty || sent.isEmpty) return false;
  if (current == sent) return true;

  final currentCore = _stripComposerGuardEdgePunctuation(current);
  final sentCore = _stripComposerGuardEdgePunctuation(sent);
  if (currentCore.isEmpty || sentCore.isEmpty) return false;
  if (currentCore == sentCore) return true;

  // Chinese IMEs and speech input can commit only the final phrase after the
  // app has already cleared the composer. Guard only non-trivial suffixes so a
  // quick new reply like "好" is not swallowed.
  final currentRunes = currentCore.runes.toList(growable: false);
  if (currentRunes.length >= 3 && sentCore.endsWith(currentCore)) return true;

  // A delayed IME commit may also rewrite the boundary at the start of the
  // restored tail (for example "走一段嘛，现在" becomes "走一段。现在"). Treat
  // it as stale when a sufficiently long ending still covers most of the
  // current value. Requiring both six runes and 70% coverage avoids swallowing
  // an unrelated new draft that merely ends with a common short phrase.
  final sentRunes = sentCore.runes.toList(growable: false);
  var commonSuffixLength = 0;
  while (commonSuffixLength < currentRunes.length &&
      commonSuffixLength < sentRunes.length &&
      currentRunes[currentRunes.length - 1 - commonSuffixLength] ==
          sentRunes[sentRunes.length - 1 - commonSuffixLength]) {
    commonSuffixLength++;
  }
  return commonSuffixLength >= 6 &&
      commonSuffixLength / currentRunes.length >= 0.7;
}

String _normalizeComposerGuardText(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

String _stripComposerGuardEdgePunctuation(String text) {
  return text
      .replaceAll(RegExp(r'^[\s，。！？；：,.!?;:、]+'), '')
      .replaceAll(RegExp(r'[\s，。！？；：,.!?;:、]+$'), '');
}

/// Keeps a sent composer value quarantined until the next genuine edit.
///
/// Some Android IMEs commit the old composing region well after the field was
/// cleared (sometimes after the two-second window used by the old guard). An
/// elapsed-time cutoff therefore cannot reliably distinguish that stale commit
/// from a new draft. Empty notifications keep the guard armed; the first
/// non-matching edit proves that a new input session has started and disarms it.
@visibleForTesting
class PersonaChatComposerStaleGuard {
  String? _sentText;

  bool get isArmed => _sentText != null;

  void arm(String? sentText) {
    final normalized = _normalizeComposerGuardText(sentText ?? '');
    _sentText = normalized.isEmpty ? null : normalized;
  }

  void disarm() => _sentText = null;

  bool shouldClear(String currentText) {
    final sentText = _sentText;
    if (sentText == null || currentText.trim().isEmpty) return false;
    if (personaChatComposerTextLooksLikeSentRemnant(
      currentText: currentText,
      sentText: sentText,
    )) {
      return true;
    }

    disarm();
    return false;
  }
}

/// 1-on-1 chat screen with an AI companion character.
class PersonaChatScreen extends StatefulWidget {
  final String characterId;
  final bool embedded;
  final bool enableRichCapture;
  final bool initialVoiceMode;
  final VoidCallback? onOpenSpaces;

  const PersonaChatScreen({
    super.key,
    required this.characterId,
    this.embedded = false,
    this.enableRichCapture = false,
    this.initialVoiceMode = false,
    this.onOpenSpaces,
  });

  @override
  State<PersonaChatScreen> createState() => _PersonaChatScreenState();
}

class _PendingPersonaChatMessage {
  const _PendingPersonaChatMessage({
    required this.characterId,
    required this.character,
    required this.messageId,
    required this.timestamp,
    required this.text,
    required this.images,
  });

  final String characterId;
  final CharacterModel? character;
  final int messageId;
  final DateTime timestamp;
  final String text;
  final List<XFile> images;
}

class _VoiceModeOpening {
  const _VoiceModeOpening({required this.text, required this.playbackId});

  final String text;
  final String playbackId;
}

class _PersonaChatScreenState extends State<PersonaChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatService = PersonaChatService.instance;
  final _voiceController = VoiceInputController();

  late String _currentCharacterId = widget.characterId;
  CharacterModel? _character;
  String? _userId;
  String? _userAvatar;
  List<PersonaChatMessage> _messages = [];
  bool _isSelecting = false;
  final Set<int> _selectedMessageIds = {};
  int? _lastBadCaseSaved;
  bool _isLoading = true;
  bool _isStreaming = false;
  String _streamingText = '';
  int _sendSerial = 0;
  int? _activeSendSerial;
  int? _activeUserMessageId;
  String? _activeStreamingCharacterId;
  final Set<int> _canceledSendSerials = {};
  final Set<int> _retractedUserMessageIds = {};
  final Set<int> _recordingMessageIds = {};

  // Pending message queue: user can compose the next message while the
  // character is still generating a response. It auto-sends when streaming ends.
  final List<_PendingPersonaChatMessage> _pendingMessages = [];

  bool _isMediaTrayOpen = false;

  // Image attachment state, moved up from CompanionMediaTray.
  final _selectedImages = <XFile>[];
  bool _isCompressingImages = false;

  // TTS playback state
  final _audioPlayer = AudioPlayer();
  final Object _mediaButtonOwner = Object();
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<PlayerState>? _audioStateSub;
  StreamSubscription<PersonaChatOpenRequest>? _openRequestSub;
  Timer? _messageRefreshTimer;
  Timer? _rememberedNoticeTimer;
  OverlayEntry? _rememberedNoticeEntry;
  String? _playingMessageId;
  String? _lastAutoReadMessageId;
  DateTime? _autoReadWatermarkAt;
  int? _autoReadWatermarkId;
  bool _isTtsLoading = false;
  bool _autoReadEnabled = false;
  bool _isInlineVoiceMode = false;
  bool _voiceModeStartQueued = false;
  bool _voiceModeOpeningInProgress = false;
  bool _endVoiceModeAfterCurrentReply = false;
  int _voiceModeSilentFollowUps = 0;
  int _voiceModeOpeningSerial = 0;
  int _voiceModeIdleFollowUpSerial = 0;
  int _ttsRequestSerial = 0;

  bool _isAppInBackground = false;
  bool _mediaButtonsActive = false;
  bool _mediaButtonsActivating = false;
  bool _refreshingMessages = false;
  int _composerClearToken = 0;
  final _composerStaleGuard = PersonaChatComposerStaleGuard();
  bool _isProgrammaticComposerClear = false;
  final _messageKeys = <int, GlobalKey>{};
  Timer? _highlightTimer;
  int? _highlightedMessageId;
  bool _isHeaderActionsOpen = false;
  bool _showJumpToLatest = false;

  ToyController? _toyControlService;
  bool _toyConnected = false;
  bool _toyConnecting = false;

  // Pagination state: WeChat/WhatsApp style, load older messages on scroll-up.
  static const int _pageSize = 30;
  static const Duration _recallGracePeriod = Duration(milliseconds: 900);
  bool _hasMoreHistory = true;
  bool _isLoadingMore = false;
  // True while showing a history window jumped-to from search. Suppresses the
  // periodic refresh timer (which reloads the latest page and would yank the
  // scroll position away from the searched message).
  bool _viewingHistoryWindow = false;

  MarkdownStyleSheet get _messageMarkdownStyle {
    final tokens = HereIamThemeRuntime.current;
    final codeBackground = tokens.brightness == Brightness.dark
        ? const Color(0xFF241615)
        : tokens.glassFillSoft;

    return MarkdownStyleSheet(
      p: TextStyle(fontSize: 15, height: 1.68, color: tokens.textPrimary),
      strong: TextStyle(fontWeight: FontWeight.w700, color: tokens.textPrimary),
      em: const TextStyle(fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: tokens.accent),
      code: TextStyle(
        fontSize: 13,
        color: tokens.textPrimary,
        backgroundColor: codeBackground,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  bool get _isStreamingCurrentCharacter =>
      _isStreaming && _activeStreamingCharacterId == _currentCharacterId;

  bool get _isVoiceReplyActive =>
      _isStreaming || _isTtsLoading || _playingMessageId != null;

  bool get _isRoleVoiceActive => _isTtsLoading || _playingMessageId != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInBackground =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (_isAppInBackground) {
      unawaited(
        ActivePersonaChatService.instance.clear(
          characterId: _currentCharacterId,
        ),
      );
      unawaited(_stopTtsPlayback());
      unawaited(_voiceController.cancel());
      _releaseMediaButtons();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(
        ActivePersonaChatService.instance.markActive(_currentCharacterId),
      );
      unawaited(NotificationService.instance.cancelAgentNotification());
      unawaited(_initMediaButtons());
      // Rebuild the toy controller on resume: BLE handles can go stale when a
      // toy is powered off/on or tested from settings.
      unawaited(_tryConnectToy(forceRefresh: true));
      _queueVoiceModeRecordingStart();
    }
  }

  Future<void> _tryConnectToy({bool forceRefresh = false}) async {
    await _ensureToyConnected(
      timeout: const Duration(seconds: 22),
      forceRefresh: forceRefresh,
    );
  }

  ToyController? _readyToyControlService() {
    final service = _toyControlService;
    if (service == null || !service.isReady) {
      return null;
    }
    if (mounted && !_toyConnected) {
      setState(() => _toyConnected = true);
    }
    return service;
  }

  void _connectToyInBackground({
    Duration timeout = const Duration(seconds: 8),
  }) {
    if (_toyConnecting) return;

    final service = _toyControlService;
    if (service != null && service.isReady) {
      if (mounted && !_toyConnected) {
        setState(() => _toyConnected = true);
      }
      return;
    }

    unawaited(
      _ensureToyConnected(timeout: timeout).catchError((e) {
        debugPrint('Toy background connection failed: $e');
        return null;
      }),
    );
  }

  bool _didFirstDependencies = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didFirstDependencies) {
      _didFirstDependencies = true;
      return; // skip first call (same as initState)
    }
    // Called when returning from a pushed route (e.g. settings page). Always
    // rebuild so the chat uses the newly selected direct-BLE device.
    if (!_isLoading) {
      unawaited(_tryConnectToy(forceRefresh: true));
    }
  }

  @override
  void initState() {
    super.initState();
    _isInlineVoiceMode = widget.initialVoiceMode;
    _voiceController.onAutoRecognitionComplete =
        _onAutoVoiceRecognitionComplete;
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(_onComposerTextChanged);
    unawaited(
      ActivePersonaChatService.instance.markActive(_currentCharacterId),
    );
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    CharacterService.instance.addListener(_onCharacterUpdated);
    unawaited(_initMediaButtons());
    _init();
    _startMessageRefreshTimer();
    _scrollController.addListener(_onScroll);
    EventBusService.instance.addHandler(
      EventBusMessageType.personaChatMessageAdded,
      _onPersonaChatMessageAdded,
    );
    EventBusService.instance.addHandler(
      EventBusMessageType.conversationCaptureRemembered,
      _onConversationCaptureRemembered,
    );
    _openRequestSub = PersonaChatOpenService.instance.requests.listen(
      _onPersonaChatOpenRequest,
    );
    if (_isInlineVoiceMode) {
      _queueVoiceModeOpening();
    }
  }

  @override
  void didUpdateWidget(covariant PersonaChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.initialVoiceMode && widget.initialVoiceMode) {
      unawaited(_setInlineVoiceMode(true));
    }
  }

  void _onPersonaChatOpenRequest(PersonaChatOpenRequest request) {
    if (request.characterId != _currentCharacterId) return;
    if (!request.startVoiceMode) return;
    unawaited(_setInlineVoiceMode(true));
  }

  void _onCharacterUpdated() {
    unawaited(_reloadCurrentCharacter());
  }

  Future<void> _reloadCurrentCharacter() async {
    final userId = _userId ?? await UserStorage.getUserId();
    if (userId == null) return;
    final character = await CharacterService.instance.getCharacter(
      userId,
      _currentCharacterId,
      returnPlaceholder: false,
    );
    if (!mounted || character == null) return;
    setState(() => _character = character);
  }

  /// Hardware key handler for Bluetooth page-turner.
  ///
  /// "Down" keys (PageDown / ArrowDown / DPadDown / MediaNext) = toggle recording.
  /// "Up" keys (PageUp / ArrowUp / DPadUp / MediaPrevious) = cancel.
  ///
  /// Returns true to consume so the event doesn't reach scrollables.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Diagnostic: log every key down so we can see what the page-turner sends.
    // Look at logcat for "VoiceInputKey" to confirm key codes.
    debugPrint(
      'VoiceInputKey: logical=${event.logicalKey.debugName} '
      'physical=${event.physicalKey.debugName} '
      'char=${event.character}',
    );

    // Volume keys deliberately excluded; they conflict with TTS volume control.
    final key = event.logicalKey;
    final isDown = key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.mediaTrackNext;
    final isUp = key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.mediaTrackPrevious;

    if (isDown) {
      _onVoiceToggle();
      return true;
    }
    if (isUp) {
      _voiceController.cancel();
      return true;
    }
    return false;
  }

  /// Toggle voice recording. If we just stopped a recording and got text back,
  /// fill the input and auto-send.
  Future<void> _onVoiceToggle() async {
    if (_isInlineVoiceMode && _isStreaming && !_voiceController.isRecording) {
      return;
    }
    if (_isInlineVoiceMode &&
        _isRoleVoiceActive &&
        !_voiceController.isRecording) {
      await _interruptRoleVoiceAndStartRecording();
      return;
    }

    final result = await _voiceController.toggle(
      autoStop: true,
      initialSilenceTimeout:
          _isInlineVoiceMode ? _voiceModeIdleFollowUpSilenceTimeout : null,
      maxRecordingDuration:
          _isInlineVoiceMode ? _voiceModeMaxRecordingDuration : null,
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      _textController.text = result;
      await _sendMessage();
    } else if (_voiceController.lastError != null) {
      final err = _voiceController.lastError!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> _interruptRoleVoiceAndStartRecording() async {
    await _stopTtsPlayback();
    if (!mounted || !_isInlineVoiceMode) return;
    await _voiceController.start(
      autoStop: true,
      initialSilenceTimeout: _voiceModeIdleFollowUpSilenceTimeout,
      maxRecordingDuration: _voiceModeMaxRecordingDuration,
    );
    if (!mounted) return;
    final error = _voiceController.lastError;
    if (error != null && _voiceController.state == VoiceInputState.idle) {
      _showVoiceInputError(error);
    }
  }

  void _showVoiceInputError(String error) {
    if (!mounted || error.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), duration: const Duration(seconds: 3)),
    );
  }

  Tool _buildEndVoiceModeTool() {
    return Tool(
      name: 'end_voice_mode',
      description:
          '''End the current chat voice mode after your current spoken reply.

Use this when the user asks to hang up/end the call, or when you naturally
decide to end the voice conversation after saying a brief goodbye. Call this
only after you have written the goodbye you want the user to hear.''',
      parameters: {
        'type': 'object',
        'properties': {
          'reason': {
            'type': 'string',
            'description': 'Short internal reason for ending voice mode.',
          },
        },
      },
      executable: ([String? reason]) async {
        _endVoiceModeAfterCurrentReply = true;
        return 'Voice mode will end after this reply is spoken.';
      },
    );
  }

  Future<void> _onAutoVoiceRecognitionComplete(String? text) async {
    if (!mounted || !_isInlineVoiceMode) return;
    final recognized = text?.trim() ?? '';
    if (recognized.isNotEmpty) {
      _voiceModeSilentFollowUps = 0;
      _textController.text = recognized;
      await _sendMessage();
      return;
    }
    if (!mounted || !_isInlineVoiceMode || _isVoiceReplyActive) return;
    await _runVoiceModeIdleFollowUp();
  }

  Future<void> _runVoiceModeIdleFollowUp() async {
    if (!mounted || !_isInlineVoiceMode || _isAppInBackground) return;
    if (_isStreaming || _isRoleVoiceActive) {
      _queueVoiceModeRecordingStart(delay: const Duration(milliseconds: 600));
      return;
    }

    final followUpIndex = ++_voiceModeSilentFollowUps;
    final forceClose = personaChatVoiceIdleFollowUpShouldForceClose(
      followUpIndex,
    );
    final serial = ++_voiceModeIdleFollowUpSerial;
    final text = await _generateVoiceModeIdleFollowUp(
      serial: serial,
      followUpIndex: followUpIndex,
      forceClose: forceClose,
    );

    if (!mounted ||
        !_isInlineVoiceMode ||
        serial != _voiceModeIdleFollowUpSerial) {
      return;
    }

    final spoken = text?.trim();
    if (spoken == null || spoken.isEmpty) {
      _queueVoiceModeRecordingStart(delay: const Duration(milliseconds: 600));
      return;
    }

    if (forceClose) {
      _endVoiceModeAfterCurrentReply = true;
    }
    final followUp = await _persistVoiceModeOpening(spoken);
    if (!mounted ||
        !_isInlineVoiceMode ||
        serial != _voiceModeIdleFollowUpSerial) {
      return;
    }
    _lastAutoReadMessageId = followUp.playbackId;
    await _handleTtsPlay(
      followUp.playbackId,
      followUp.text,
      autoTriggered: false,
    );
  }

  void _queueVoiceModeRecordingStart({Duration delay = Duration.zero}) {
    if (_voiceModeStartQueued) return;
    _voiceModeStartQueued = true;
    unawaited(
      Future<void>.delayed(delay).then((_) {
        _voiceModeStartQueued = false;
        unawaited(_startVoiceModeRecordingIfReady());
      }),
    );
  }

  void _queueVoiceModeOpening() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startVoiceModeWithRoleOpening());
    });
  }

  Future<void> _startVoiceModeRecordingIfReady() async {
    if (!mounted ||
        !_isInlineVoiceMode ||
        _isAppInBackground ||
        _isVoiceReplyActive ||
        _voiceController.state != VoiceInputState.idle) {
      return;
    }

    await _voiceController.start(
      autoStop: true,
      initialSilenceTimeout: _voiceModeIdleFollowUpSilenceTimeout,
      maxRecordingDuration: _voiceModeMaxRecordingDuration,
    );
    if (!mounted) return;
    final error = _voiceController.lastError;
    if (error != null && _voiceController.state == VoiceInputState.idle) {
      _showVoiceInputError(error);
    }
  }

  Future<void> _startVoiceModeWithRoleOpening() async {
    if (!mounted || !_isInlineVoiceMode || _isAppInBackground) return;
    if (_isLoading || _character == null || _userId == null) {
      Future<void>.delayed(const Duration(milliseconds: 80)).then((_) {
        if (mounted && _isInlineVoiceMode) {
          unawaited(_startVoiceModeWithRoleOpening());
        }
      });
      return;
    }
    if (_voiceModeOpeningInProgress || _isStreaming || _isRoleVoiceActive) {
      return;
    }

    final serial = ++_voiceModeOpeningSerial;
    _voiceModeOpeningInProgress = true;
    _voiceModeStartQueued = false;
    await _voiceController.cancel();
    await _stopTtsPlayback();

    try {
      final opening = await _prepareVoiceModeOpening(serial);
      if (!mounted ||
          !_isInlineVoiceMode ||
          serial != _voiceModeOpeningSerial ||
          opening == null ||
          opening.text.trim().isEmpty) {
        return;
      }

      _lastAutoReadMessageId = opening.playbackId;
      await _handleTtsPlay(
        opening.playbackId,
        opening.text,
        autoTriggered: false,
      );
    } finally {
      if (serial == _voiceModeOpeningSerial) {
        _voiceModeOpeningInProgress = false;
      }
      if (mounted &&
          _isInlineVoiceMode &&
          !_isRoleVoiceActive &&
          !_voiceController.isRecording) {
        _queueVoiceModeRecordingStart();
      }
    }
  }

  Future<_VoiceModeOpening?> _prepareVoiceModeOpening(int serial) async {
    final pending = await readPendingCall();
    if (pending?.characterId == _currentCharacterId &&
        pending!.opening.trim().isNotEmpty) {
      await clearPendingCall(characterId: _currentCharacterId);
      return _persistVoiceModeOpening(pending.opening.trim());
    }

    final generated = await _generateVoiceModeOpening(serial);
    if (generated != null && generated.trim().isNotEmpty) {
      return _persistVoiceModeOpening(generated.trim());
    }

    for (final message in _messages) {
      if (_isUnreadableAutoReadCandidate(message)) {
        return _VoiceModeOpening(
          text: message.content,
          playbackId: personaChatTtsPlaybackIdForMessage(message),
        );
      }
    }
    return null;
  }

  Future<_VoiceModeOpening> _persistVoiceModeOpening(String text) async {
    final id = await _chatService.addCharacterMessage(
      _currentCharacterId,
      text,
      isRead: true,
      timestamp: DateTime.now(),
    );
    final updated = await _chatService.getMessages(
      _currentCharacterId,
      limit: _messages.length + 5,
    );
    if (mounted) {
      setState(() => _messages = updated);
      _scrollToBottom();
    }
    PersonaChatMessage? message;
    for (final item in updated) {
      if (item.id == id) {
        message = item;
        break;
      }
    }
    return _VoiceModeOpening(
      text: text,
      playbackId: message != null
          ? personaChatTtsPlaybackIdForMessage(message)
          : 'voice-opening-$id',
    );
  }

  Future<String?> _generateVoiceModeOpening(int serial) async {
    final userId = _userId ?? await UserStorage.getUserId();
    if (userId == null) return null;

    final character = _character;
    final fallbackFirstMessage = character?.firstMessage?.trim();
    const prompt =
        '[The user has just entered chat voice mode. You speak first. '
        'Open naturally in one or two short spoken sentences. Do not ask why '
        'they called; this is not a phone call screen. Do not use markdown, '
        'action text, or parenthetical thoughts.]';

    final previousStreaming = _isStreaming;
    final previousActiveCharacterId = _activeStreamingCharacterId;
    String lastChunk = '';
    if (mounted) {
      setState(() {
        _isStreaming = true;
        _streamingText = '';
        _activeStreamingCharacterId = _currentCharacterId;
      });
    }

    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      await for (final chunk in CompanionAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: _currentCharacterId,
        userMessage: prompt,
        debugErrorOutput: true,
        voiceMode: true,
      )) {
        if (!mounted ||
            !_isInlineVoiceMode ||
            serial != _voiceModeOpeningSerial) {
          return null;
        }
        lastChunk = chunk;
        setState(() => _streamingText = chunk);
        _scrollToBottom();
      }
    } catch (_) {
      if (fallbackFirstMessage != null && fallbackFirstMessage.isNotEmpty) {
        return TavernMacro.resolve(
          fallbackFirstMessage,
          userName: userId,
          charName: character?.name ?? '',
        );
      }
      return null;
    } finally {
      if (mounted && serial == _voiceModeOpeningSerial) {
        setState(() {
          _isStreaming = previousStreaming;
          _streamingText = '';
          _activeStreamingCharacterId = previousActiveCharacterId;
        });
      }
    }

    final text = lastChunk.trim();
    if (text.isNotEmpty) return text;
    if (fallbackFirstMessage != null && fallbackFirstMessage.isNotEmpty) {
      return TavernMacro.resolve(
        fallbackFirstMessage,
        userName: userId,
        charName: character?.name ?? '',
      );
    }
    return null;
  }

  Future<String?> _generateVoiceModeIdleFollowUp({
    required int serial,
    required int followUpIndex,
    required bool forceClose,
  }) async {
    final userId = _userId ?? await UserStorage.getUserId();
    if (userId == null) return null;

    final previousStreaming = _isStreaming;
    final previousActiveCharacterId = _activeStreamingCharacterId;
    String lastChunk = '';
    if (mounted) {
      setState(() {
        _isStreaming = true;
        _streamingText = '';
        _activeStreamingCharacterId = _currentCharacterId;
      });
    }

    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      await for (final chunk in CompanionAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: _currentCharacterId,
        userMessage: personaChatVoiceIdleFollowUpPrompt(
          followUpIndex: followUpIndex,
          forceClose: forceClose,
        ),
        debugErrorOutput: true,
        voiceMode: true,
        extraTools: [_buildEndVoiceModeTool()],
      )) {
        if (!mounted ||
            !_isInlineVoiceMode ||
            serial != _voiceModeIdleFollowUpSerial) {
          return null;
        }
        lastChunk = chunk;
        setState(() => _streamingText = chunk);
        _scrollToBottom();
      }
    } catch (e) {
      return forceClose ? '我先不吵你了，闭上眼睛好好睡。晚安。' : '我在呢。你不用说话，闭上眼睛，慢慢放松就好。';
    } finally {
      if (mounted && serial == _voiceModeIdleFollowUpSerial) {
        setState(() {
          _isStreaming = previousStreaming;
          _streamingText = '';
          _activeStreamingCharacterId = previousActiveCharacterId;
        });
      }
    }

    final text = lastChunk.trim();
    if (text.isNotEmpty) return text;
    return forceClose ? '我先不吵你了，闭上眼睛好好睡。晚安。' : '我在呢。你不用说话，闭上眼睛，慢慢放松就好。';
  }

  Future<void> _initMediaButtons() async {
    if (_mediaButtonsActive || _mediaButtonsActivating || _isAppInBackground) {
      return;
    }

    _mediaButtonsActivating = true;
    final enabled = await AsrConfig.getUseMediaKeys();
    if (!mounted || !enabled || _isAppInBackground) {
      _mediaButtonsActivating = false;
      return;
    }

    final mediaButtons = MediaButtonService.instance;
    mediaButtons.setOnToggle(
      () => unawaited(_onVoiceToggle()),
      owner: _mediaButtonOwner,
    );
    mediaButtons.setOnCancel(
      () => unawaited(_voiceController.cancel()),
      owner: _mediaButtonOwner,
    );
    try {
      await mediaButtons.activate(owner: _mediaButtonOwner);
      if (!mounted || _isAppInBackground) {
        await mediaButtons.deactivate(owner: _mediaButtonOwner);
        mediaButtons.clearCallbacks(owner: _mediaButtonOwner);
        return;
      }
      _mediaButtonsActive = true;
    } catch (e) {
      debugPrint('MediaButtonService activate failed: $e');
      mediaButtons.clearCallbacks(owner: _mediaButtonOwner);
    } finally {
      _mediaButtonsActivating = false;
    }
  }

  void _releaseMediaButtons() {
    final mediaButtons = MediaButtonService.instance;
    mediaButtons.clearCallbacks(owner: _mediaButtonOwner);
    if (!_mediaButtonsActive) return;

    _mediaButtonsActive = false;
    unawaited(
      mediaButtons.deactivate(owner: _mediaButtonOwner).catchError(
            (e) => debugPrint('MediaButtonService deactivate failed: $e'),
          ),
    );
  }

  Future<void> _init() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await UserStorage.setLastActiveCompanionCharacterId(
      userId,
      _currentCharacterId,
    );
    final userAvatar = await MemexRouter().getUserAvatar();

    final character = await CharacterService.instance.getCharacter(
      userId,
      _currentCharacterId,
    );
    final autoReadEnabled = await UserStorage.getCompanionAutoReadEnabled();

    final messages = await _chatService.getMessages(
      _currentCharacterId,
      limit: _pageSize,
    );
    await _markCurrentChatRead();

    // If this is the first chat and the character has a greeting, deliver it.
    if (messages.isEmpty &&
        character != null &&
        character.firstMessage != null &&
        character.firstMessage!.trim().isNotEmpty) {
      final greeting = TavernMacro.resolve(
        character.firstMessage!,
        userName: userId,
        charName: character.name,
      );
      await _chatService.addCharacterMessage(
        _currentCharacterId,
        greeting,
        isRead: true,
      );
      // Reload after inserting greeting.
      final updatedMessages = await _chatService.getMessages(
        _currentCharacterId,
        limit: _pageSize,
      );
      if (mounted) {
        _advanceAutoReadWatermark(updatedMessages);
        setState(() {
          _character = character;
          _userId = userId;
          _userAvatar = userAvatar;
          _messages = updatedMessages;
          _autoReadEnabled = autoReadEnabled;
          _hasMoreHistory = updatedMessages.length >= _pageSize;
          _isLoading = false;
        });
        _scrollToBottom();
      }
      return;
    }

    if (mounted) {
      _advanceAutoReadWatermark(messages);
      setState(() {
        _character = character;
        _userId = userId;
        _userAvatar = userAvatar;
        _messages = messages;
        _autoReadEnabled = autoReadEnabled;
        _hasMoreHistory = messages.length >= _pageSize;
        _isLoading = false;
        _toyControlService = null;
        _toyConnected = false;
      });
      _scrollToBottom();

      // Connect the configured toy backend in background. Flamingo/Svakom are
      // direct BLE controllers; Intiface is only used for Buttplug devices.
      unawaited(_tryConnectToy());
    }
  }

  Future<ToyController?> _ensureToyConnected({
    Duration timeout = const Duration(seconds: 8),
    bool forceRefresh = false,
  }) async {
    final existing = _toyControlService;
    if (!forceRefresh && existing != null && existing.isReady) {
      if (mounted && !_toyConnected) {
        setState(() => _toyConnected = true);
      }
      return existing;
    }

    if (existing != null) {
      existing.dispose();
      if (mounted) {
        setState(() {
          _toyControlService = null;
          _toyConnected = false;
        });
      }
    }

    if (_toyConnecting) {
      final deadline = DateTime.now().add(timeout);
      while (_toyConnecting && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final connected = _toyControlService;
      return connected != null && connected.isReady ? connected : null;
    }

    _toyConnecting = true;
    if (mounted) {
      setState(() {});
    }
    ToyController? toyService;
    try {
      toyService = await ToyControlService.fromPrefs();
      if (toyService == null) {
        if (mounted) {
          setState(() {
            _toyControlService = null;
            _toyConnected = false;
          });
        }
        return null;
      }

      await _connectToyController(toyService).timeout(timeout);
      if (!mounted) {
        toyService.dispose();
        return null;
      }
      if (toyService.isReady) {
        setState(() {
          _toyControlService = toyService;
          _toyConnected = true;
        });
        return toyService;
      }
    } catch (e) {
      debugPrint('Toy connection failed: $e');
    } finally {
      _toyConnecting = false;
      if (mounted) {
        setState(() {});
      }
    }

    toyService?.dispose();
    if (mounted) {
      setState(() {
        if (identical(_toyControlService, toyService)) {
          _toyControlService = null;
        }
        _toyConnected = false;
      });
    }
    return null;
  }

  Future<void> _connectToyController(ToyController toyService) async {
    if (toyService is ButtplugToyController) {
      await toyService.connect();
    } else if (toyService is SvakomToyController) {
      await toyService.connect();
    } else if (toyService is MagicMotionFlamingoController) {
      await toyService.connect();
    }
  }

  @override
  void dispose() {
    // Auto-capture is gone; record button + floating ball are the only paths now.
    unawaited(
      ActivePersonaChatService.instance.clear(characterId: _currentCharacterId),
    );
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    CharacterService.instance.removeListener(_onCharacterUpdated);
    _releaseMediaButtons();
    EventBusService.instance.removeHandler(
      EventBusMessageType.personaChatMessageAdded,
      _onPersonaChatMessageAdded,
    );
    EventBusService.instance.removeHandler(
      EventBusMessageType.conversationCaptureRemembered,
      _onConversationCaptureRemembered,
    );
    _scrollController.removeListener(_onScroll);
    _textController.removeListener(_onComposerTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _audioCompleteSub?.cancel();
    _audioStateSub?.cancel();
    _openRequestSub?.cancel();
    _messageRefreshTimer?.cancel();
    _hideRememberedNotice();
    _audioPlayer.dispose();
    _voiceController.dispose();
    _toyControlService?.dispose();
    _imageByteCache.clear();
    super.dispose();
  }

  /// Triggered when user scrolls toward the top (older messages).
  /// Since the list is reversed, maxScrollExtent = oldest direction.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final shouldShowJump = pos.pixels > 180;
    if (shouldShowJump != _showJumpToLatest && mounted) {
      debugPrint(
        '[JumpButton] _onScroll pixels=${pos.pixels.toStringAsFixed(0)} '
        'shouldShow=$shouldShowJump was=$_showJumpToLatest',
      );
      setState(() => _showJumpToLatest = shouldShowJump);
    }
    if (!_hasMoreHistory || _isLoadingMore) return;
    // Trigger load when within 20% of the top (maxScrollExtent in reversed list)
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      _loadMoreHistory();
    }
  }

  /// Loads the next page of older messages and prepends them to the list.
  Future<void> _loadMoreHistory() async {
    if (_isLoadingMore || !_hasMoreHistory) return;
    setState(() => _isLoadingMore = true);

    final olderMessages = await _chatService.getMessages(
      _currentCharacterId,
      limit: _pageSize,
      offset: _messages.length,
    );

    if (!mounted) return;
    setState(() {
      _messages = [..._messages, ...olderMessages];
      _hasMoreHistory = olderMessages.length >= _pageSize;
      _isLoadingMore = false;
    });
  }

  void _onPersonaChatMessageAdded(EventBusMessage message) {
    if (message is! PersonaChatMessageAddedMessage) return;
    if (message.characterId != _currentCharacterId) return;
    if (!mounted) return;
    // Viewing a searched history window: ignore live updates so the window and
    // scroll position stay put until the user returns to latest.
    if (_viewingHistoryWindow) return;
    if (_refreshPersonaChatMessageAdded()) return;
    final previousMessages = List<PersonaChatMessage>.of(_messages);
    // New message arrived; reload the latest page and keep any older
    // messages that were already loaded via pagination.
    _chatService
        .getMessages(_currentCharacterId, limit: _messages.length + 5)
        .then((updated) {
      if (!mounted) return;
      setState(() => _messages = updated);
      if (_autoReadEnabled || _isInlineVoiceMode) {
        _autoReadNewestCharacterMessage(
          previousMessages: previousMessages,
          updatedMessages: updated,
        );
      } else {
        _advanceAutoReadWatermark(updated);
      }
      _scrollToBottom();
    });
  }

  void _onConversationCaptureRemembered(EventBusMessage message) {
    if (message is! ConversationCaptureRememberedMessage ||
        message.characterId != _currentCharacterId ||
        !mounted) {
      return;
    }
    _showRememberedNotice(
      onUndo: () => unawaited(
        SharedLifeMemoryService.instance.undoOperations(message.operationIds),
      ),
    );
  }

  void _showRememberedNotice({required VoidCallback onUndo}) {
    _hideRememberedNotice();
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => ConversationCaptureRememberedNotice(
        onUndo: () {
          _hideRememberedNotice();
          onUndo();
        },
      ),
    );
    _rememberedNoticeEntry = entry;
    overlay.insert(entry);
    _rememberedNoticeTimer = Timer(
      const Duration(seconds: 3),
      _hideRememberedNotice,
    );
  }

  void _hideRememberedNotice() {
    _rememberedNoticeTimer?.cancel();
    _rememberedNoticeTimer = null;
    _rememberedNoticeEntry?.remove();
    _rememberedNoticeEntry = null;
  }

  bool _refreshPersonaChatMessageAdded() {
    unawaited(
      _refreshMessagesFromStore(
        autoRead: _autoReadEnabled,
        scrollToBottom: true,
      ),
    );
    return true;
  }

  void _startMessageRefreshTimer() {
    _messageRefreshTimer?.cancel();
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isLoading || _isStreaming || _isAppInBackground) return;
      // While viewing a searched history window, don't reload the latest page —
      // it would replace the window and yank the scroll away from the target.
      if (_viewingHistoryWindow) return;
      unawaited(
        _refreshMessagesFromStore(
          autoRead: _autoReadEnabled,
          scrollToBottom: false,
        ),
      );
    });
  }

  Future<void> _refreshMessagesFromStore({
    required bool autoRead,
    required bool scrollToBottom,
  }) async {
    if (_refreshingMessages || !mounted) return;
    _refreshingMessages = true;

    final previousMessages = List<PersonaChatMessage>.of(_messages);
    // Use current depth as the query limit. New messages are always at the
    // front of the DESC-ordered result so they are included automatically.
    // Adding +5 here caused the limit to grow by 5 every 2-second tick,
    // which silently loaded all history into memory. History pagination is
    // handled explicitly by _loadMoreHistory() on scroll.
    final limit = _messages.length < _pageSize ? _pageSize : _messages.length;

    try {
      final updated = await _chatService.getMessages(
        _currentCharacterId,
        limit: limit,
      );
      if (!mounted) return;

      if (_sameMessages(previousMessages, updated)) {
        _advanceAutoReadWatermark(updated);
        return;
      }

      setState(() => _messages = updated);
      unawaited(_markCurrentChatRead());

      if (autoRead) {
        _autoReadNewestCharacterMessage(
          previousMessages: previousMessages,
          updatedMessages: updated,
        );
      } else {
        _advanceAutoReadWatermark(updated);
      }
      if (scrollToBottom) {
        _scrollToBottom();
      }
    } finally {
      _refreshingMessages = false;
    }
  }

  Future<void> _markCurrentChatRead() async {
    await _chatService.markAllRead(_currentCharacterId);
    await NotificationService.instance.cancelAgentNotification();
  }

  bool _sameMessages(
    List<PersonaChatMessage> previous,
    List<PersonaChatMessage> updated,
  ) {
    if (previous.length != updated.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].id != updated[i].id ||
          previous[i].content != updated[i].content ||
          previous[i].messageType != updated[i].messageType ||
          previous[i].attachmentsJson != updated[i].attachmentsJson) {
        return false;
      }
    }
    return true;
  }

  Future<void> _sendMessage({
    String? forcedCharacterId,
    CharacterModel? forcedCharacter,
    _PendingPersonaChatMessage? queuedMessage,
    String? syntheticInput,
  }) async {
    final isQueuedMessage = queuedMessage != null;
    final isSynthetic = syntheticInput != null;
    final text = isSynthetic
        ? syntheticInput!
        : (queuedMessage?.text ?? _textController.text.trim());
    final hasText = text.isNotEmpty;
    final queuedImages = queuedMessage?.images;
    final hasImages = queuedImages?.isNotEmpty ?? _selectedImages.isNotEmpty;
    if (!hasText && !hasImages) return;

    final sendCharacterId =
        queuedMessage?.characterId ?? forcedCharacterId ?? _currentCharacterId;
    final sendCharacter = queuedMessage?.character ??
        (forcedCharacterId == null ? _character : forcedCharacter);

    // While the character is still typing, queue the message; it will be sent
    // automatically when the current response finishes streaming.
    if (_isStreaming && !isQueuedMessage) {
      final imagesToQueue = List<XFile>.from(_selectedImages);
      _clearComposerText(staleText: text);
      _clearImages();
      final queued = await _persistVisibleQueuedUserMessage(
        characterId: sendCharacterId,
        character: sendCharacter,
        text: text,
        images: imagesToQueue,
      );
      if (queued != null) {
        _pendingMessages.add(queued);
      }
      return;
    }

    // Capture state before clearing
    final imagesToSend = queuedImages != null
        ? List<XFile>.from(queuedImages)
        : List<XFile>.from(_selectedImages);
    final textToSend = text;
    if (_isInlineVoiceMode && hasText) {
      _voiceModeSilentFollowUps = 0;
    }
    if (!isQueuedMessage) {
      _clearComposerText(staleText: textToSend);
      _clearImages();
    }

    await _stopTtsPlayback();

    final userMessageTime = queuedMessage?.timestamp ?? DateTime.now();

    // Compress images for chat bubble display and DB storage.
    List<Map<String, String>>? compressedAttachments;
    if (hasImages && !isQueuedMessage) {
      setState(() => _isCompressingImages = true);
      compressedAttachments = <Map<String, String>>[];
      for (final image in imagesToSend) {
        compressedAttachments.add(await _compressImageForChat(image));
      }
      if (mounted) setState(() => _isCompressingImages = false);
    }

    // Persist user message with attachments (skip for synthetic inputs).
    final userMessageId = isSynthetic
        ? -(DateTime.now().millisecondsSinceEpoch)
        : (queuedMessage?.messageId ??
            await _chatService.addUserMessage(
              sendCharacterId,
              textToSend,
              timestamp: userMessageTime,
              attachments: compressedAttachments,
              appendTimeline: false,
            ));
    final sendSerial = ++_sendSerial;
    _activeSendSerial = sendSerial;
    _activeUserMessageId = userMessageId;
    _activeStreamingCharacterId = sendCharacterId;

    // Reload messages to show user's message (preserve loaded history depth).
    // Synthetic inputs don't add a visible user message, so don't increase limit.
    final messages = await _chatService.getMessages(
      sendCharacterId,
      limit: isSynthetic ? _messages.length : _messages.length + 1,
    );
    final isStillViewingSendCharacter = _currentCharacterId == sendCharacterId;
    setState(() {
      if (isStillViewingSendCharacter) {
        _messages = messages;
      }
      _isStreaming = true;
      _streamingText = '';
    });
    if (isStillViewingSendCharacter) {
      _scrollToBottom();
    }

    await Future<void>.delayed(_recallGracePeriod);
    if (_isSendCanceled(sendSerial, userMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }
    await _chatService.appendUserMessageTimeline(
      sendCharacterId,
      userMessageId,
    );
    if (_isSendCanceled(sendSerial, userMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }

    // 鈹€鈹€ Image analysis via vision model 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
    // Uses the analyze_assets agent's separately-configured model so
    // the character (e.g. text-only DeepSeek) can understand images.
    // Analysis runs once and feeds the chat context. Explicit recording uses
    // RecordOrganizerService so media lands in the SharedLife card system.
    String? imageAnalysisText;
    if (hasImages && imagesToSend.isNotEmpty) {
      try {
        final analysisResources = await UserStorage.getAgentLLMResources(
          AgentDefinitions.analyzeAssets,
          defaultClientKey: LLMConfig.defaultClientKey,
        );
        if (_isSendCanceled(sendSerial, userMessageId)) {
          _finishCanceledSend(sendSerial);
          return;
        }
        final analysisTool = AssetAnalysisTool(
          client: analysisResources.client,
          modelConfig: analysisResources.modelConfig,
        );
        final analyses = <String>[];
        for (final image in imagesToSend) {
          if (_isSendCanceled(sendSerial, userMessageId)) {
            _finishCanceledSend(sendSerial);
            return;
          }
          final result = await analysisTool.tool(
            assetPath: image.path,
            prompt: '用1-2句中文简要描述这张图片的内容。'
                '关注画面中可见的人、物体、文字、场景。'
                '简洁客观。',
          );
          // Strip the "#Asset ... analysis result\n:" prefix.
          final cleaned = result
              .replaceFirst(RegExp(r'^#Asset .+ analysis result\n:'), '')
              .trim();
          if (cleaned.isNotEmpty) analyses.add(cleaned);
        }
        if (analyses.isNotEmpty) {
          imageAnalysisText = analyses.join(' | ');
          // Persist each analysis into the attachments so Record Organizer
          // can reuse them later instead of re-running the vision model.
          try {
            await _chatService.enrichAttachmentsWithAnalysis(
              userMessageId,
              analyses,
            );
          } catch (e) {
            debugPrint('Failed to persist image analyses to attachments: $e');
          }
        }
      } catch (e) {
        debugPrint('Image analysis failed, falling back to hint: $e');
      }
    }
    if (_isSendCanceled(sendSerial, userMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }

    // Get LLM resources
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _finishCanceledSend(sendSerial);
      return;
    }

    String lastChunk = '';
    var responsePersisted = false;

    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      if (_isSendCanceled(sendSerial, userMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }

      // Build user message; inject image analysis when available.
      final imageCount = imagesToSend.length;
      final String chatMessage;
      if (imageAnalysisText != null && imageAnalysisText.isNotEmpty) {
        chatMessage = textToSend.isNotEmpty
            ? '[Image analysis: $imageAnalysisText]\n\n$textToSend'
            : '[Image analysis: $imageAnalysisText]';
      } else if (hasImages && imageCount > 0) {
        chatMessage = textToSend.isNotEmpty
            ? '[The user attached $imageCount image(s) to this message.]\n\n$textToSend'
            : '[The user sent $imageCount image(s) without text.]';
      } else {
        chatMessage = textToSend;
      }
      final linkContext = _buildLinkConversationContext(textToSend);
      final chatMessageWithContext =
          linkContext == null ? chatMessage : '$linkContext\n\n$chatMessage';

      final toyControlService = _readyToyControlService();
      if (toyControlService == null) {
        _connectToyInBackground();
      }

      await for (final chunk in CompanionAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: sendCharacterId,
        userMessage: chatMessageWithContext,
        // Images are only passed to the LLM when it supports vision.
        // For text-only models, the image hint above lets the character
        // acknowledge the images without seeing their contents.
        images: null,
        userMessageId: userMessageId,
        userMessageTime: userMessageTime,
        debugErrorOutput: true,
        voiceMode: _isInlineVoiceMode,
        toyControlService: toyControlService,
        extraTools: _isInlineVoiceMode ? [_buildEndVoiceModeTool()] : const [],
      )) {
        if (_isSendCanceled(sendSerial, userMessageId)) {
          break;
        }
        lastChunk = chunk;
        if (mounted) {
          setState(() => _streamingText = chunk);
          if (_currentCharacterId == sendCharacterId) {
            _scrollToBottom();
          }
        }
      }
      if (mounted && toyControlService != null) {
        setState(() => _toyConnected = toyControlService.isReady);
      }
      if (_isSendCanceled(sendSerial, userMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }

      // Persist character response
      final fullResponse = lastChunk.trim();
      if (fullResponse.isNotEmpty) {
        if (_isSendCanceled(sendSerial, userMessageId)) {
          _finishCanceledSend(sendSerial);
          return;
        }
        // Strip leaked reasoning tags before persisting.
        final cleanResponse = PersonaReplySanitizer.stripLeakedReasoning(
          fullResponse,
        );
        await _chatService.addCharacterMessage(
          sendCharacterId,
          cleanResponse,
          isRead: !_isAppInBackground,
          timestamp: DateTime.now(),
        );
        responsePersisted = true;

        if (_isAppInBackground && sendCharacter != null) {
          final preview = cleanResponse.length > 100
              ? '${cleanResponse.substring(0, 100)}...'
              : cleanResponse;
          await NotificationService.instance.showAgentNotification(
            title: sendCharacter.name,
            body: preview,
            payload: sendCharacterId,
          );
        }
      }

      // Reload messages
      if (_isSendCanceled(sendSerial, userMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }
      final updated = await _chatService.getMessages(
        sendCharacterId,
        limit: messages.length + 20,
      );
      if (mounted) {
        final isViewingSendCharacter = _currentCharacterId == sendCharacterId;
        setState(() {
          if (isViewingSendCharacter) {
            _messages = updated;
          }
          _isStreaming = false;
          _streamingText = '';
        });
        _finishActiveSend(sendSerial);
        if (isViewingSendCharacter) {
          if (_autoReadEnabled || _isInlineVoiceMode) {
            _autoReadNewestCharacterMessage(
              previousMessages: messages,
              updatedMessages: updated,
            );
          } else {
            _advanceAutoReadWatermark(updated);
          }
          // Active sends should keep the reversed list pinned to the latest
          // edge. Message-level focusing belongs to explicit search jumps; using
          // it here can pull the view up to an older part of the conversation.
          _scrollToBottom();
        } else {
          unawaited(
            _refreshMessagesFromStore(
              autoRead: _autoReadEnabled,
              scrollToBottom: false,
            ),
          );
        }
        _sendPendingMessage();
        // Fire-and-forget lightweight dreaming tick after each reply.
        if (AppDatabase.isInitialized) {
          unawaited(DreamingSchedulerService.triggerLightweightTickStatic(
            AppDatabase.instance,
          ));
        }
      }
    } on CompanionApiException catch (e) {
      // API/connection failure (quota exhausted, 4xx/5xx, timeout). Nothing was
      // yielded, so there is no partial reply to persist — and critically, we do
      // NOT write the raw error as a character message (that would both look bad
      // and pollute Dreaming extraction). Full detail goes to logs only; the
      // user sees a transient toast with a Retry action.
      debugPrint('CompanionApiException during send: ${e.cause}');
      if (_isSendCanceled(sendSerial, userMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _streamingText = '';
        });
        _finishActiveSend(sendSerial);
        final isViewingSendCharacter = _currentCharacterId == sendCharacterId;
        // Only offer retry for a real persisted user message (id > 0). Synthetic
        // turns (negative id) have no stored message to regenerate from.
        final canRetry = isViewingSendCharacter && userMessageId > 0;
        ScaffoldMessenger.of(context).showToast(
          _chatUiText(
            zh: '连接不太稳，消息没发出去',
            en: 'Connection unstable, message not sent',
          ),
          duration: const Duration(seconds: 5),
          actionLabel: canRetry ? _chatUiText(zh: '重试', en: 'Retry') : null,
          onAction: canRetry
              ? () => _retryLastSend(
                    characterId: sendCharacterId,
                    character: sendCharacter,
                    userMessageId: userMessageId,
                    text: textToSend,
                    timestamp: userMessageTime,
                  )
              : null,
        );
        _sendPendingMessage();
      }
    } catch (e) {
      if (_isSendCanceled(sendSerial, userMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }
      final partialResponse = lastChunk.trim();
      if (partialResponse.isNotEmpty && !responsePersisted) {
        if (_isSendCanceled(sendSerial, userMessageId)) {
          _finishCanceledSend(sendSerial);
          return;
        }
        await _chatService.addCharacterMessage(
          sendCharacterId,
          partialResponse,
          isRead: !_isAppInBackground,
          timestamp: DateTime.now(),
        );
      }

      final updated = await _chatService.getMessages(
        sendCharacterId,
        limit: messages.length + 20,
      );
      if (mounted) {
        final isViewingSendCharacter = _currentCharacterId == sendCharacterId;
        setState(() {
          if (isViewingSendCharacter) {
            _messages = updated;
          }
          _isStreaming = false;
          _streamingText = '';
        });
        _finishActiveSend(sendSerial);
        if (partialResponse.isNotEmpty && isViewingSendCharacter) {
          if (_autoReadEnabled || _isInlineVoiceMode) {
            _autoReadNewestCharacterMessage(
              previousMessages: messages,
              updatedMessages: updated,
            );
          } else {
            _advanceAutoReadWatermark(updated);
          }
          _scrollToBottom();
        } else if (partialResponse.isEmpty && isViewingSendCharacter) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to get response: $e')));
        } else if (!isViewingSendCharacter) {
          unawaited(
            _refreshMessagesFromStore(
              autoRead: _autoReadEnabled,
              scrollToBottom: false,
            ),
          );
        }
        _sendPendingMessage();
      }
    }
  }

  /// Regenerates a character reply for an already-persisted user message after
  /// an API failure. Reuses the queued-message path so the user message is not
  /// re-persisted (no duplicate) and history/recall see it exactly once.
  void _retryLastSend({
    required String characterId,
    required CharacterModel? character,
    required int userMessageId,
    required String text,
    required DateTime timestamp,
  }) {
    if (_isStreaming) return;
    final retryMessage = _PendingPersonaChatMessage(
      characterId: characterId,
      character: character,
      messageId: userMessageId,
      timestamp: timestamp,
      text: text,
      images: const [],
    );
    unawaited(_sendMessage(queuedMessage: retryMessage));
  }

  void _clearComposerText({String? staleText}) {
    final token = ++_composerClearToken;
    _armComposerStaleGuard(staleText);
    // Replace text, selection, and composing range atomically. Calling
    // clearComposing() first emits an intermediate controller value; Gboard and
    // other IMEs can respond by restoring that composing region.
    _setComposerTextEmpty();

    // IMEs (especially Chinese) can restore composing text across multiple
    // frames with timing that varies by device and keyboard. Keep a short
    // stale-text guard so the sent message, or its final phrase, cannot be
    // committed back into the composer after the send.
    void clearIfTextReappeared() {
      if (!mounted || token != _composerClearToken) return;
      _clearComposerIfStaleText();
    }

    scheduleMicrotask(clearIfTextReappeared);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      clearIfTextReappeared();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => clearIfTextReappeared(),
      );
    });
    for (final delay in _composerStaleGuardPollDelays) {
      unawaited(
        Future<void>.delayed(delay).then((_) => clearIfTextReappeared()),
      );
    }
  }

  void _setComposerTextEmpty() {
    _isProgrammaticComposerClear = true;
    try {
      _textController.value = const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    } finally {
      _isProgrammaticComposerClear = false;
    }
  }

  void _armComposerStaleGuard(String? staleText) {
    _composerStaleGuard.arm(staleText);
  }

  void _onComposerTextChanged() {
    if (_isProgrammaticComposerClear) return;
    _clearComposerIfStaleText();
  }

  bool _clearComposerIfStaleText() {
    final currentText = _textController.text;
    if (!_composerStaleGuard.shouldClear(currentText)) return false;

    _setComposerTextEmpty();
    return true;
  }

  Future<_PendingPersonaChatMessage?> _persistVisibleQueuedUserMessage({
    required String characterId,
    required CharacterModel? character,
    required String text,
    required List<XFile> images,
  }) async {
    if (text.trim().isEmpty && images.isEmpty) return null;

    List<Map<String, String>>? compressedAttachments;
    if (images.isNotEmpty) {
      setState(() => _isCompressingImages = true);
      compressedAttachments = <Map<String, String>>[];
      for (final image in images) {
        compressedAttachments.add(await _compressImageForChat(image));
      }
      if (mounted) setState(() => _isCompressingImages = false);
    }

    final timestamp = DateTime.now();
    final messageId = await _chatService.addUserMessage(
      characterId,
      text,
      timestamp: timestamp,
      attachments: compressedAttachments,
      appendTimeline: false,
    );

    if (mounted && _currentCharacterId == characterId) {
      final messages = await _chatService.getMessages(
        characterId,
        limit: _messages.length + 1,
      );
      if (mounted && _currentCharacterId == characterId) {
        setState(() => _messages = messages);
        _scrollToBottom();
      }
    }

    return _PendingPersonaChatMessage(
      characterId: characterId,
      character: character,
      messageId: messageId,
      timestamp: timestamp,
      text: text,
      images: List<XFile>.from(images),
    );
  }

  /// If the user queued a message while the character was streaming, send it
  /// now that the response has finished.
  void _sendPendingMessage() {
    if (_pendingMessages.isEmpty) return;
    final pending = _pendingMessages.removeAt(0);
    unawaited(
      _sendMessage(
        forcedCharacterId: pending.characterId,
        forcedCharacter: pending.character,
        queuedMessage: pending,
      ),
    );
  }

  // 鈹€鈹€ Image selection management 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  void _onImagesPicked(List<XFile> images) {
    setState(() {
      for (final image in images) {
        if (!_selectedImages.any((i) => i.path == image.path)) {
          _selectedImages.add(image);
        }
      }
      // Close the picker tray after selection.
      _isMediaTrayOpen = false;
    });
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _clearImages() {
    setState(() => _selectedImages.clear());
  }

  /// Compresses an image for chat display and LLM vision input.
  ///
  /// Tries WebP compression at 2048px first. If that fails (common on certain
  /// Android devices or HEIC images), falls back to reading the raw file bytes
  /// so [attachmentsJson] is always populated — without it the Record Organizer
  /// cannot save media blocks.
  Future<Map<String, String>> _compressImageForChat(XFile image) async {
    final sourcePath = image.path;
    // --- primary path: WebP compression ---
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        sourcePath,
        minWidth: 2048,
        minHeight: 2048,
        quality: 85,
        format: CompressFormat.webp,
        autoCorrectionAngle: true,
        keepExif: false,
      );
      if (compressed != null) {
        final base64 = base64Encode(compressed);
        return {
          'mimeType': 'image/webp',
          'base64': base64,
          'sourcePath': sourcePath,
        };
      }
    } catch (e) {
      debugPrint('Image compress failed, falling back to raw bytes: $e');
    }

    // --- fallback: read raw file bytes ---
    try {
      final file = File(sourcePath);
      if (!file.existsSync()) {
        debugPrint('Image file not found for fallback: $sourcePath');
        // Return a stub entry so the record path can still attempt recovery.
        return {
          'mimeType': 'image/jpeg',
          'base64': '',
          'sourcePath': sourcePath,
        };
      }
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);
      final ext = sourcePath.split('.').last.toLowerCase();
      final mimeType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        'bmp' => 'image/bmp',
        _ => 'image/jpeg',
      };
      debugPrint(
        'Image fallback: read ${bytes.length} raw bytes, mime=$mimeType',
      );
      return {'mimeType': mimeType, 'base64': base64, 'sourcePath': sourcePath};
    } catch (e) {
      debugPrint('Image raw fallback also failed: $e');
      return {'mimeType': 'image/jpeg', 'base64': '', 'sourcePath': sourcePath};
    }
  }

  // Tapping "back to latest": if we're in a searched history window, reload the
  // real latest page first, then scroll to bottom. Otherwise just scroll.
  Future<void> _returnToLatest() async {
    if (_viewingHistoryWindow) {
      final messages = await _chatService.getMessages(
        _currentCharacterId,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _hasMoreHistory = messages.length >= _pageSize;
        _viewingHistoryWindow = false;
        _highlightedMessageId = null;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_showJumpToLatest && mounted) {
      setState(() => _showJumpToLatest = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openChatSearch() async {
    final selected = await showModalBottomSheet<PersonaChatMessage>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PersonaChatSearchSheet(
        characterId: _currentCharacterId,
        chatService: _chatService,
        characterName: _character?.name,
      ),
    );
    if (selected == null || !mounted) return;
    // Wait for the bottom sheet dismiss animation (~300ms) to finish before
    // scrolling, otherwise ensureVisible fires while the modal overlay is still
    // covering the chat list and the scroll is silently swallowed.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _jumpToMessage(selected);
  }

  Future<void> _jumpToMessage(PersonaChatMessage message) async {
    final newerCount = await _chatService.countMessagesNewerThan(
      _currentCharacterId,
      message,
    );
    // Load a window of messages around the target instead of the entire tail.
    // This bounds the scroll estimation error to ~windowHalf * avgHeightError
    // instead of newerCount * avgHeightError (which fails for long histories).
    const windowSize = 60;
    const windowHalf = 30;
    final windowOffset = newerCount <= windowHalf ? 0 : newerCount - windowHalf;
    final messages = await _chatService.getMessages(
      _currentCharacterId,
      limit: windowSize,
      offset: windowOffset,
    );
    if (!mounted) return;
    final targetIndexInWindow = newerCount - windowOffset;
    _highlightTimer?.cancel();
    setState(() {
      _messages = messages;
      _hasMoreHistory = messages.length >= windowSize;
      _highlightedMessageId = message.id;
      _showJumpToLatest = true;
      // windowOffset > 0 means this is a deep history window, not the latest
      // page; suppress auto-refresh so the target stays put.
      _viewingHistoryWindow = windowOffset > 0;
    });
    _scrollToMessage(message.id, newerCount: targetIndexInWindow);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  void _scrollToMessage(int messageId,
      {double alignment = 0.45, int newerCount = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      const avgItemHeight = 80.0;
      final estimated = (newerCount * avgItemHeight)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(estimated);
      _ensureVisibleWithRetry(messageId, alignment: alignment, retriesLeft: 3);
    });
  }

  void _ensureVisibleWithRetry(int messageId,
      {double alignment = 0.45, int retriesLeft = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messageContext = _messageKeys[messageId]?.currentContext;
      if (messageContext != null && messageContext.mounted) {
        unawaited(
          Scrollable.ensureVisible(
            messageContext,
            alignment: alignment,
          ),
        );
        return;
      }
      if (retriesLeft <= 0 || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final nudge = pos.viewportDimension * 0.8;
      final next = (pos.pixels + nudge).clamp(0.0, pos.maxScrollExtent);
      _scrollController.jumpTo(next);
      _ensureVisibleWithRetry(messageId,
          alignment: alignment, retriesLeft: retriesLeft - 1);
    });
  }

  Future<void> _recordMessage(PersonaChatMessage message) async {
    if (!RecordOrganizerServiceV3.isInitialized) return;
    // Guard against rapid double-taps re-firing while a record is in flight.
    if (!_recordingMessageIds.add(message.id)) return;

    final userId = _userId ?? await UserStorage.getUserId();
    if (userId == null) {
      _recordingMessageIds.remove(message.id);
      return;
    }
    if (!mounted) {
      _recordingMessageIds.remove(message.id);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    // Show a long-lived toast above the input bar; replaced when the result lands.
    final progress = messenger.showToast(
      _chatUiText(zh: '正在记录…', en: 'Recording…'),
      duration: const Duration(seconds: 30),
    );

    try {
      // ── Pre-process media attachments ──────────────────────────
      final media = <MediaInputAttachment>[];
      final attachmentsJson = message.attachmentsJson;
      debugPrint(
        '[Record] msg#${message.id} attachmentsJson '
        '${attachmentsJson != null ? "present (${attachmentsJson.length} chars)" : "null"}',
      );
      if (attachmentsJson != null && attachmentsJson.trim().isNotEmpty) {
        try {
          final List<dynamic> attachments = jsonDecode(attachmentsJson);
          debugPrint(
            '[Record] msg#${message.id} parsed ${attachments.length} attachment(s)',
          );
          // Extract existing analysis text from the [Image analysis: ...] prefix
          // that was injected into message.content during send.
          final existingAnalyses = _extractImageAnalyses(message.content);
          debugPrint(
            '[Record] msg#${message.id} prefix analyses extracted: ${existingAnalyses.length}',
          );
          final fsService = FileSystemService.instance;

          // Close the initial "Recording…" snackbar once before processing images.
          try {
            progress.close();
          } catch (_) {}

          for (var i = 0; i < attachments.length; i++) {
            final att = attachments[i];
            if (att is! Map) continue;
            final attachment = Map<dynamic, dynamic>.from(att);
            if (!_personaChatAttachmentLooksLikeImage(attachment)) continue;
            final mimeType = _personaChatImageMimeTypeForAttachment(attachment);
            final base64 = attachment['base64']?.toString();
            final recoveryPath = personaChatRecoverableImageAttachmentPath(
              attachment,
            );
            if (!personaChatImageAttachmentCanBeRecorded(attachment)) {
              debugPrint(
                '[Record] msg#${message.id} image#$i has neither base64 nor sourcePath',
              );
              media.add(
                const MediaInputAttachment(
                  error: 'image attachment has neither bytes nor sourcePath',
                ),
              );
              continue;
            }

            try {
              final analyzing = messenger.showToast(
                _chatUiText(
                  zh: '正在分析图片${attachments.length > 1 ? "(${i + 1}/${attachments.length})" : ""}…',
                  en: 'Analyzing image${attachments.length > 1 ? " (${i + 1}/${attachments.length})" : ""}…',
                ),
                duration: const Duration(seconds: 25),
              );
              try {
                final ext = _imageExtForMime(mimeType);
                File? tempFile;
                late final String sourcePathForSave;
                if (base64 != null && base64.isNotEmpty) {
                  try {
                    final bytes = base64Decode(base64);
                    final tempDir = Directory.systemTemp;
                    tempFile = File(
                      '${tempDir.path}${Platform.pathSeparator}record_${message.id}_$i.$ext',
                    );
                    await tempFile.writeAsBytes(bytes);
                    sourcePathForSave = tempFile.path;
                  } catch (e) {
                    if (recoveryPath == null) rethrow;
                    debugPrint(
                      '[Record] msg#${message.id} image#$i base64 decode failed; '
                      'recovering from sourcePath: $e',
                    );
                    sourcePathForSave = recoveryPath;
                  }
                } else {
                  sourcePathForSave = recoveryPath!;
                  debugPrint(
                    '[Record] msg#${message.id} image#$i recovering from sourcePath',
                  );
                }
                final sourceFile = File(sourcePathForSave);
                if (!await sourceFile.exists()) {
                  throw FileSystemException(
                    'Image source not found for record attachment',
                    sourcePathForSave,
                  );
                }

                // factId is required by saveAssetFromFile for filename generation.
                // Use a synthetic factId from the current timestamp since the
                // companion-first record path does not own a Memex factId.
                final now = DateTime.now();
                final factId =
                    '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}.md'
                    '#ts_${now.microsecondsSinceEpoch}';
                late final String relativePath;
                try {
                  final (_, savedRelativePath) =
                      await fsService.saveAssetFromFile(
                    userId: userId,
                    sourcePath: sourcePathForSave,
                    assetType: 'img',
                    index: i + 1,
                    format: ext,
                    factId: factId,
                  );
                  relativePath = savedRelativePath;
                } finally {
                  if (tempFile != null) {
                    try {
                      await tempFile.delete();
                    } catch (_) {}
                  }
                }
                debugPrint(
                  '[Record] msg#${message.id} image#$i saved: $relativePath',
                );

                // 3. Get or run image analysis (3-tier priority)
                String? analysisText;
                // Tier 1: from the [Image analysis: ...] prefix in message content
                if (i < existingAnalyses.length) {
                  analysisText = existingAnalyses[i];
                  debugPrint(
                    '[Record] msg#${message.id} image#$i analysis from prefix',
                  );
                }
                // Tier 2: from attachment.analysis stored during send
                if (analysisText == null || analysisText.trim().isEmpty) {
                  final storedAnalysis = attachment['analysis']?.toString();
                  if (storedAnalysis != null &&
                      storedAnalysis.trim().isNotEmpty) {
                    analysisText = storedAnalysis.trim();
                    debugPrint(
                      '[Record] msg#${message.id} image#$i analysis from attachment '
                      '(${analysisText.length} chars)',
                    );
                  }
                }
                // Tier 3: run inline AssetAnalysisTool
                if (analysisText == null || analysisText.trim().isEmpty) {
                  try {
                    debugPrint(
                      '[Record] msg#${message.id} image#$i running inline AssetAnalysisTool…',
                    );
                    final analysisResources =
                        await UserStorage.getAgentLLMResources(
                      AgentDefinitions.analyzeAssets,
                      defaultClientKey: LLMConfig.defaultClientKey,
                    );
                    final analysisTool = AssetAnalysisTool(
                      client: analysisResources.client,
                      modelConfig: analysisResources.modelConfig,
                    );
                    final absPath = fsService.toAbsolutePath(relativePath);
                    final result = await analysisTool.tool(
                      assetPath: absPath,
                      prompt: '用1-2句中文简要描述这张图片的内容。'
                          '关注画面中可见的人、物体、文字、场景。'
                          '简洁客观。',
                    );
                    // Strip the "#Asset ... analysis result\n:" prefix
                    analysisText = result
                        .replaceFirst(
                          RegExp(r'^#Asset .+ analysis result\n:'),
                          '',
                        )
                        .trim();
                    debugPrint(
                      '[Record] msg#${message.id} image#$i inline analysis done '
                      '(${analysisText.length} chars)',
                    );
                  } catch (e) {
                    debugPrint(
                      '[Record] msg#${message.id} image#$i inline analysis FAILED: $e',
                    );
                  }
                }

                media.add(
                  MediaInputAttachment(
                    savedRelativePath: relativePath,
                    analysisText: analysisText,
                    kind: 'image',
                  ),
                );
                debugPrint(
                  '[Record] msg#${message.id} image#$i → media (usable=${media.last.isUsable}, '
                  'hasAnalysis=${analysisText != null && analysisText.isNotEmpty})',
                );
              } finally {
                analyzing.close();
              }
            } catch (e) {
              debugPrint(
                '[Record] msg#${message.id} image#$i PROCESSING FAILED: $e',
              );
              media.add(MediaInputAttachment(error: e.toString()));
            }
          }
        } catch (e) {
          debugPrint(
            '[Record] msg#${message.id} parse attachmentsJson FAILED: $e',
          );
        }
      }

      // ── Strip [Image analysis: ...] prefix from content ────────
      final cleanedContent = message.content
          .replaceFirst(RegExp(r'^\[Image analysis:.*?\](\n\n?)?'), '')
          .trim();
      debugPrint(
        '[Record] msg#${message.id} content="$cleanedContent", '
        'mediaCount=${media.where((m) => m.isUsable).length}',
      );

      // Restore progress toast before the LLM call.
      try {
        progress.close();
      } catch (_) {}
      final recordProgress = messenger.showToast(
        _chatUiText(zh: '正在记录…', en: 'Recording…'),
        duration: const Duration(seconds: 30),
      );

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final inputMedia = media.isNotEmpty
          ? media
              .map(
                (m) => {
                  'kind': m.kind,
                  if (m.savedRelativePath != null) 'path': m.savedRelativePath!,
                  if (m.analysisText != null) 'analysis': m.analysisText!,
                },
              )
              .toList()
          : null;
      final result = await RecordOrganizerServiceV3.instance.organizeAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        source: RecordSource(
          sourceKind: 'record_button',
          rawInput:
              cleanedContent.isNotEmpty ? cleanedContent : message.content,
        ),
        inputMedia: inputMedia,
      );

      recordProgress.close();
      if (!mounted) return;
      if (result.isEmpty) {
        messenger.showToast(
          _chatUiText(zh: '未识别到可记录内容', en: 'Nothing to record'),
          duration: const Duration(seconds: 2),
        );
      } else {
        final count = result.cardIds.length;
        messenger.showToast(
          _chatUiText(zh: '已记录 $count 张卡片', en: 'Recorded $count card(s)'),
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e, stack) {
      progress.close();
      debugPrint('[Record] msg#${message.id} failed: $e\n$stack');
      if (mounted) {
        messenger.showToast(
          _chatUiText(zh: '记录失败：$e', en: 'Record failed: $e'),
          duration: const Duration(seconds: 3),
        );
      }
    } finally {
      _recordingMessageIds.remove(message.id);
    }
  }

  void _exitSelectMode() {
    setState(() {
      _isSelecting = false;
      _selectedMessageIds.clear();
    });
  }

  Future<void> _batchRecordSelectedMessages() async {
    if (!RecordOrganizerServiceV3.isInitialized) return;
    if (_selectedMessageIds.isEmpty) return;

    final userId = _userId ?? await UserStorage.getUserId();
    if (userId == null) return;
    if (!mounted) return;

    // Build ordered list of selected messages
    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (selected.isEmpty) return;

    // Build combined input
    final buffer = StringBuffer();
    for (final msg in selected) {
      if (msg.isFromCharacter) {
        buffer.writeln('林埃: ${msg.content}');
      } else {
        buffer.writeln('用户: ${msg.content}');
      }
    }
    final combinedText = buffer.toString().trim();
    if (combinedText.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final progress = messenger.showToast(
      _chatUiText(zh: '正在记录…', en: 'Recording…'),
      duration: const Duration(seconds: 30),
    );

    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

      final result = await RecordOrganizerServiceV3.instance.organizeAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        source: RecordSource(
          sourceKind: 'record_button',
          rawInput: combinedText,
        ),
      );

      progress.close();
      if (!mounted) return;
      if (result.isEmpty) {
        messenger.showToast(
          _chatUiText(zh: '未识别到可记录内容', en: 'Nothing to record'),
          duration: const Duration(seconds: 2),
        );
      } else {
        final count = result.cardIds.length;
        messenger.showToast(
          _chatUiText(zh: '已记录 $count 张卡片', en: 'Recorded $count card(s)'),
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e, stack) {
      progress.close();
      debugPrint('[BatchRecord] failed: $e\n$stack');
      if (mounted) {
        messenger.showToast(
          _chatUiText(zh: '记录失败：$e', en: 'Record failed: $e'),
          duration: const Duration(seconds: 3),
        );
      }
    }

    _exitSelectMode();
  }

  Future<void> _batchDeleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_chatUiText(zh: '删除消息', en: 'Delete messages')),
        content: Text(_chatUiText(
          zh: '确定要删除选中的 ${_selectedMessageIds.length} 条消息吗？删除后将不会被提取到记忆中。',
          en: 'Delete ${_selectedMessageIds.length} selected message(s)? They will not be extracted into memory.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_chatUiText(zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _chatUiText(zh: '删除', en: 'Delete'),
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (final id in _selectedMessageIds) {
        await _chatService.deleteMessage(_currentCharacterId, id);
      }
      await _refreshMessagesFromStore(autoRead: false, scrollToBottom: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showToast(
          _chatUiText(zh: '已删除', en: 'Deleted'),
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      debugPrint('batchDeleteMessages failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showToast(
          _chatUiText(zh: '删除失败', en: 'Delete failed'),
          duration: const Duration(seconds: 2),
        );
      }
    }

    _exitSelectMode();
  }

  /// Maps a mime type (e.g. "image/png") to a file extension (e.g. "png").
  /// Image extension helper for media pre-processing.
  String _imageExtForMime(String mimeType) {
    final lower = mimeType.toLowerCase();
    if (lower.contains('webp')) return 'webp';
    if (lower.contains('png')) return 'png';
    if (lower.contains('gif')) return 'gif';
    if (lower.contains('heic')) return 'heic';
    if (lower.contains('heif')) return 'heif';
    return 'jpg';
  }

  /// Extracts per-image analysis texts from the [Image analysis: ...] prefix
  /// that was injected into message content during send.  Analyses are joined
  /// by " | " so we split on that delimiter.
  List<String> _extractImageAnalyses(String content) {
    final match = RegExp(r'^\[Image analysis:\s*(.*?)\]').firstMatch(content);
    if (match == null) return const [];
    final body = match.group(1)?.trim() ?? '';
    if (body.isEmpty) return const [];
    return body
        .split(' | ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String? _buildLinkConversationContext(String text) {
    final parsed = parseReadingShare(text, extractCapturedNote: true);
    if (parsed == null) return null;

    final label = switch (parsed.platform) {
      'xiaohongshu' => '小红书',
      'wechat_mp' => '微信公众号',
      _ => '网页',
    };
    final title = parsed.title?.trim();
    final note = parsed.capturedNote?.trim();

    final buffer = StringBuffer()
      ..writeln('[Link context]')
      ..writeln('The user sent a $label link: ${parsed.url}.');
    if (title != null && title.isNotEmpty) {
      buffer.writeln('Parsed title: $title.');
    }
    if (note != null && note.isNotEmpty) {
      buffer.writeln('User note around the link: $note.');
    }
    buffer
      ..writeln('Treat this as chat material, not as a save request.')
      ..writeln('Do not say it has been saved or recorded.')
      ..write(
        'If saving would be useful, ask whether the user wants it saved.',
      );
    return buffer.toString();
  }

  bool _isSendCanceled(int sendSerial, int userMessageId) {
    return _canceledSendSerials.contains(sendSerial) ||
        _retractedUserMessageIds.contains(userMessageId);
  }

  void _finishActiveSend(int sendSerial) {
    if (_activeSendSerial == sendSerial) {
      _activeSendSerial = null;
      _activeUserMessageId = null;
      _activeStreamingCharacterId = null;
    }
    _canceledSendSerials.remove(sendSerial);
  }

  void _finishCanceledSend(int sendSerial) {
    final wasActive = _activeSendSerial == sendSerial;
    _finishActiveSend(sendSerial);
    if (wasActive && mounted) {
      setState(() {
        _isStreaming = false;
        _streamingText = '';
      });
      _sendPendingMessage();
    }
  }

  void _cancelSendForRetractedMessage(int messageId) {
    _retractedUserMessageIds.add(messageId);
    _pendingMessages.removeWhere((message) => message.messageId == messageId);
    if (_activeUserMessageId != messageId) return;

    final sendSerial = _activeSendSerial;
    if (sendSerial != null) {
      _canceledSendSerials.add(sendSerial);
    }
    _activeSendSerial = null;
    _activeUserMessageId = null;
    _activeStreamingCharacterId = null;
    if (!mounted) return;
    setState(() {
      _isStreaming = false;
      _streamingText = '';
    });
    _sendPendingMessage();
  }

  Future<void> _confirmRetractUserMessage(PersonaChatMessage message) async {
    if (message.isFromCharacter) return;
    if (!mounted) return;

    _cancelSendForRetractedMessage(message.id);
    final deleted = await _chatService.retractUserMessage(
      _currentCharacterId,
      message.id,
    );
    if (!mounted) return;

    if (deleted == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _chatUiText(
              zh: '这条消息已经不能撤回',
              en: 'This message can no longer be recalled',
            ),
          ),
        ),
      );
      return;
    }

    _messageKeys.remove(message.id);
    await _refreshMessagesFromStore(autoRead: false, scrollToBottom: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_chatUiText(zh: '已撤回', en: 'Message recalled')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool get _shouldAutoReadCurrentReply =>
      mounted &&
      (_autoReadEnabled || _isInlineVoiceMode) &&
      !_isAppInBackground &&
      !_isStreaming &&
      !_voiceModeOpeningInProgress;

  void _autoReadNewestCharacterMessage({
    required List<PersonaChatMessage> previousMessages,
    required List<PersonaChatMessage> updatedMessages,
  }) {
    if (!_shouldAutoReadCurrentReply) {
      if (!_isStreaming) {
        _advanceAutoReadWatermark(updatedMessages);
      }
      return;
    }

    final candidates = personaChatGeneratedReadableMessagesInOrder(
      previousMessages: previousMessages,
      updatedMessages: updatedMessages,
    ).where(_isAfterAutoReadWatermark).toList();

    if (candidates.isEmpty) {
      _advanceAutoReadWatermark(updatedMessages);
      return;
    }

    candidates.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

    final message = candidates.first;
    final messageId = personaChatTtsPlaybackIdForMessage(message);
    // Only advance the watermark past THIS message so the remaining
    // candidates stay visible for the follow-up play-on-completion chain.
    _advanceReadWatermarkForMessage(message);
    if (_lastAutoReadMessageId == messageId) return;
    _lastAutoReadMessageId = messageId;
    unawaited(_handleTtsPlay(messageId, message.content, autoTriggered: true));
  }

  /// Sets the auto-read watermark to just past [message] so queued messages
  /// after it remain eligible for the next TTS pass.
  void _advanceReadWatermarkForMessage(PersonaChatMessage message) {
    _autoReadWatermarkAt = message.timestamp;
    _autoReadWatermarkId = message.id;
  }

  /// Called after each TTS message finishes. If there are still unread
  /// character messages after the watermark, plays the next one in order.
  void _autoReadNextMessageIfAny() {
    if (_playingMessageId != null) return; // still playing
    if (!_shouldAutoReadCurrentReply) return;

    final candidates = _messages
        .where(_isUnreadableAutoReadCandidate)
        .where(_isAfterAutoReadWatermark)
        .toList();

    if (candidates.isEmpty) return;

    candidates.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

    final message = candidates.first;
    final messageId = personaChatTtsPlaybackIdForMessage(message);
    _advanceReadWatermarkForMessage(message);
    if (_lastAutoReadMessageId == messageId) return;
    _lastAutoReadMessageId = messageId;
    unawaited(_handleTtsPlay(messageId, message.content, autoTriggered: true));
  }

  bool _isUnreadableAutoReadCandidate(PersonaChatMessage message) {
    return message.isFromCharacter &&
        message.messageType == 'chat' &&
        message.content.trim().isNotEmpty;
  }

  bool _isAfterAutoReadWatermark(PersonaChatMessage message) {
    final watermarkAt = _autoReadWatermarkAt;
    if (watermarkAt == null) return true;
    if (message.timestamp.isAfter(watermarkAt)) return true;
    return message.timestamp.isAtSameMomentAs(watermarkAt) &&
        message.id > (_autoReadWatermarkId ?? -1);
  }

  void _advanceAutoReadWatermark(List<PersonaChatMessage> messages) {
    PersonaChatMessage? newest;
    for (final message in messages) {
      if (!_isUnreadableAutoReadCandidate(message)) continue;
      if (newest == null ||
          message.timestamp.isAfter(newest.timestamp) ||
          (message.timestamp.isAtSameMomentAs(newest.timestamp) &&
              message.id > newest.id)) {
        newest = message;
      }
    }
    if (newest == null) return;
    _autoReadWatermarkAt = newest.timestamp;
    _autoReadWatermarkId = newest.id;
  }

  Future<void> _setAutoReadEnabled(bool enabled) async {
    if (enabled) {
      _advanceAutoReadWatermark(_messages);
    }
    setState(() => _autoReadEnabled = enabled);
    try {
      await UserStorage.setCompanionAutoReadEnabled(enabled);
      if (!enabled) {
        await _stopTtsPlayback();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showToast(
        enabled ? '自动朗读已开启' : '自动朗读已关闭',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoReadEnabled = !enabled);
      ScaffoldMessenger.of(context).showToast(
        '自动朗读设置保存失败',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _setInlineVoiceMode(bool enabled) async {
    if (enabled == _isInlineVoiceMode) {
      if (enabled) {
        _queueVoiceModeOpening();
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isInlineVoiceMode = enabled);
    if (enabled) {
      _voiceModeSilentFollowUps = 0;
      _voiceModeIdleFollowUpSerial++;
      _queueVoiceModeOpening();
    } else {
      _voiceModeOpeningSerial++;
      _voiceModeIdleFollowUpSerial++;
      _voiceModeOpeningInProgress = false;
      _voiceModeStartQueued = false;
      final wasAgentEnded = _endVoiceModeAfterCurrentReply;
      _endVoiceModeAfterCurrentReply = false;
      _voiceModeSilentFollowUps = 0;
      await _voiceController.cancel();
      await _stopTtsPlayback();
      // Notify the character that the user hung up (unless the agent ended it).
      if (!wasAgentEnded) {
        unawaited(
          _chatService.addCharacterMessage(
            _currentCharacterId,
            '📵 用户挂断了语音通话。',
            isRead: true,
          ),
        );
      }
    }
  }

  Future<void> _stopTtsPlayback() async {
    _ttsRequestSerial++;
    await _audioCompleteSub?.cancel();
    _audioCompleteSub = null;
    await _audioStateSub?.cancel();
    _audioStateSub = null;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _playingMessageId = null;
        _isTtsLoading = false;
      });
    } else {
      _playingMessageId = null;
      _isTtsLoading = false;
    }
  }

  void _handleTtsPlaybackCompleted(int requestSerial, String messageId) {
    if (!mounted ||
        requestSerial != _ttsRequestSerial ||
        _playingMessageId != messageId) {
      return;
    }
    setState(() {
      _playingMessageId = null;
      _isTtsLoading = false;
    });
    if (_endVoiceModeAfterCurrentReply && _isInlineVoiceMode) {
      _endVoiceModeAfterCurrentReply = false;
      unawaited(_setInlineVoiceMode(false));
      return;
    }
    _queueVoiceModeRecordingStart();
    // Chain to the next unread message when running in auto-read / voice mode.
    _autoReadNextMessageIfAny();
  }

  Future<void> _watchTtsPlaybackCompletion(
    int requestSerial,
    String messageId,
  ) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted ||
          requestSerial != _ttsRequestSerial ||
          _playingMessageId != messageId) {
        return;
      }
      if (_audioPlayer.state == PlayerState.completed) {
        _handleTtsPlaybackCompleted(requestSerial, messageId);
        return;
      }
    }
  }

  Future<void> _confirmDeleteMessage({
    required String messageId,
    required String characterId,
  }) async {
    final id = int.tryParse(messageId.split(':').first);
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条消息？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _chatService.deleteMessage(characterId, id);
      await _refreshMessagesFromStore(autoRead: false, scrollToBottom: false);
    } catch (e) {
      debugPrint('deleteMessage failed: $e');
    }
  }

  Future<void> _collectBadCase({
    required String messageId,
    required String text,
  }) async {
    try {
      final id = int.tryParse(messageId.split(':').first);
      if (id == null) return;

      // Collect surrounding context (2 messages before and after).
      final allMessages = _messages.toList();
      final targetIndex = allMessages.indexWhere((m) => m.id == id);
      final contextBefore = <String>[];
      final contextAfter = <String>[];
      if (targetIndex >= 0) {
        for (var i = targetIndex - 1; i >= 0 && contextBefore.length < 3; i--) {
          contextBefore.insert(0,
              '[${allMessages[i].isFromCharacter ? "I" : "U"}] ${allMessages[i].content}');
        }
        for (var i = targetIndex + 1;
            i < allMessages.length && contextAfter.length < 3;
            i++) {
          contextAfter.add(
              '[${allMessages[i].isFromCharacter ? "I" : "U"}] ${allMessages[i].content}');
        }
      }

      await BadCaseCollector.collect(
        characterId: _character?.id ?? '',
        targetMessageId: id,
        targetContent: text,
        targetTimestamp:
            targetIndex >= 0 ? allMessages[targetIndex].timestamp : null,
        contextBefore: contextBefore,
        contextAfter: contextAfter,
      );

      if (!mounted) return;
      setState(() {
        _lastBadCaseSaved = id;
      });
      // Auto-clear the indicator after 2 seconds.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _lastBadCaseSaved == id) {
          setState(() => _lastBadCaseSaved = null);
        }
      });
    } catch (e) {
      // Silently ignore collection failures — non-critical feature.
      debugPrint('collectBadCase failed: $e');
    }
  }

  Future<void> _handleTtsPlay(
    String messageId,
    String text, {
    bool autoTriggered = false,
  }) async {
    if (autoTriggered && !_shouldAutoReadCurrentReply) return;
    if (_isTtsLoading && _playingMessageId == messageId) return;

    if (_playingMessageId == messageId) {
      await _stopTtsPlayback();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }

    await _audioPlayer.stop();
    final requestSerial = ++_ttsRequestSerial;

    final voiceId = _character?.ttsVoiceId;
    if (voiceId == null || voiceId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先在角色设置中配置 TTS 语音 ID')));
      }
      return;
    }

    if (mounted) {
      setState(() {
        _playingMessageId = messageId;
        _isTtsLoading = true;
      });
    }

    try {
      final audioPath = await TtsService.textToSpeech(
        text: text,
        voiceId: voiceId,
      );

      if (mounted) {
        if (requestSerial != _ttsRequestSerial ||
            _isAppInBackground ||
            (autoTriggered && !_shouldAutoReadCurrentReply)) {
          await _stopTtsPlayback();
          return;
        }
        _audioCompleteSub?.cancel();
        _audioCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
          _handleTtsPlaybackCompleted(requestSerial, messageId);
        });
        _audioStateSub?.cancel();
        _audioStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
          if (state == PlayerState.completed) {
            _handleTtsPlaybackCompleted(requestSerial, messageId);
          }
        });
        setState(() => _isTtsLoading = false);
        await _audioPlayer.play(DeviceFileSource(audioPath));
        unawaited(_watchTtsPlaybackCompletion(requestSerial, messageId));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playingMessageId = null;
          _isTtsLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
        _queueVoiceModeRecordingStart();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final viewInsetsBottom = mediaQuery.viewInsets.bottom;
    final safeBottom = mediaQuery.padding.bottom;
    final hasVisibleMediaTray = widget.enableRichCapture && _isMediaTrayOpen;
    final jumpToLatestBottom =
        viewInsetsBottom + safeBottom + (hasVisibleMediaTray ? 204 : 116);
    final mediaTrayBottom = viewInsetsBottom + safeBottom + 96;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _personaStageInk,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _ChatAtmosphereBackground(character: _character),
                  ),
                ),
                Positioned.fill(child: _buildMessageList()),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(bottom: false, child: _buildHeader()),
                ),
                Positioned(
                  top: mediaQuery.padding.top + 62,
                  left: 0,
                  right: 0,
                  child: const ChatTaskCapsule(),
                ),
                if (_showJumpToLatest && !_isSelecting)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: jumpToLatestBottom,
                    child: _buildJumpToLatestPill(),
                  ),
                if (widget.enableRichCapture)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: mediaTrayBottom,
                    child: CompanionMediaTray(
                      isOpen: _isMediaTrayOpen,
                      onImagesPicked: _onImagesPicked,
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: viewInsetsBottom,
                  child: _buildInputBar(),
                ),
                if (_isHeaderActionsOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _isHeaderActionsOpen = false),
                    ),
                  ),
                if (_isHeaderActionsOpen) _buildHeaderActionsOverlay(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final character = _character;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: _FrostedCircleButton(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _personaText,
                  size: 17,
                ),
              ),
            ),
          ],
          if (character != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.push(AppRoutes.aboutI),
              child: _hasUsableHeaderAvatar(character)
                  ? _HeaderImageAvatar(
                      avatar: character.avatar!,
                      size: 42,
                    )
                  : CharacterAvatar(
                      avatar: character.avatar,
                      name: character.name,
                      size: 42,
                      backgroundColor: _personaPanelSoft,
                    ),
            ),
            const Spacer(),
            if (_toyControlService != null || _toyConnecting) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: _toyConnecting
                    ? '玩具连接中'
                    : (_toyConnected ? '玩具已连接' : '玩具未连接'),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _toyConnecting
                        ? const Color(0xFFFACC15)
                        : (_toyConnected
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF94A3B8)),
                    boxShadow: [
                      BoxShadow(
                        color: (_toyConnecting
                                ? const Color(0xFFFACC15)
                                : (_toyConnected
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFF94A3B8)))
                            .withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() => _isHeaderActionsOpen = !_isHeaderActionsOpen);
              },
              child: _FrostedCircleButton(
                child: Icon(
                  _isHeaderActionsOpen
                      ? Icons.close_rounded
                      : Icons.more_horiz_rounded,
                  color: _personaAccent,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasUsableHeaderAvatar(CharacterModel character) {
    final avatar = character.avatar;
    if (avatar == null || avatar.isEmpty || !isImageAvatar(avatar)) {
      return false;
    }
    if (avatar.startsWith('/')) return File(avatar).existsSync();
    return true;
  }

  Widget _buildHeaderActionsOverlay() {
    final top = MediaQuery.paddingOf(context).top + 58;
    final actions = <Widget>[
      _HeaderActionButton(
        icon: Icons.search_rounded,
        label: _chatUiText(zh: '搜索', en: 'Search'),
        onTap: () {
          setState(() => _isHeaderActionsOpen = false);
          unawaited(_openChatSearch());
        },
      ),
      _HeaderActionButton(
        icon: _autoReadEnabled
            ? Icons.record_voice_over_rounded
            : Icons.record_voice_over_outlined,
        label: _autoReadEnabled
            ? _chatUiText(zh: '鍏抽棴鑷姩鏈楄', en: 'Turn off auto read')
            : _chatUiText(zh: '开启自动朗读', en: 'Turn on auto read'),
        active: _autoReadEnabled,
        onTap: () {
          setState(() => _isHeaderActionsOpen = false);
          unawaited(_setAutoReadEnabled(!_autoReadEnabled));
        },
      ),
      if (widget.onOpenSpaces != null)
        _HeaderActionButton(
          icon: Icons.grid_view_rounded,
          label: _chatUiText(zh: '鐢熸椿绌洪棿', en: 'Life space'),
          onTap: () {
            setState(() => _isHeaderActionsOpen = false);
            widget.onOpenSpaces?.call();
          },
        ),
    ];

    return Positioned(
      top: top,
      right: 14,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, -8 * (1 - value)),
              child: Transform.scale(
                scale: 0.96 + value * 0.04,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              actions[i],
              if (i != actions.length - 1) const SizedBox(height: 9),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJumpToLatestPill() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
      child: Center(
        child: GestureDetector(
          onTap: () => unawaited(_returnToLatest()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _personaPanel.withValues(alpha: 0.82),
              border: Border.all(color: _personaAccent.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _personaAccent,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  _chatUiText(zh: '回到最新', en: 'Back to latest'),
                  style: TextStyle(color: _personaAccent, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top + 118;
    final mediaTrayPadding =
        widget.enableRichCapture && _isMediaTrayOpen ? 96.0 : 0.0;
    final bottomPadding = mediaQuery.padding.bottom +
        mediaQuery.viewInsets.bottom +
        168 +
        mediaTrayPadding;

    // Show typing indicator or streaming bubble at the end
    final showStreamingBubble =
        _isStreamingCurrentCharacter && _streamingText.isNotEmpty;
    final showTypingIndicator =
        _isStreamingCurrentCharacter && _streamingText.isEmpty;
    final extraItems = (showStreamingBubble || showTypingIndicator) ? 1 : 0;
    // Extra item at the tail (top of reversed list) for load-more indicator
    final loadMoreItem = (_hasMoreHistory || _isLoadingMore) ? 1 : 0;
    final itemCount = _messages.length + extraItems + loadMoreItem;

    if (_messages.isEmpty && extraItems == 0) {
      return Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        child: _buildEmptyState(),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<OverscrollIndicatorNotification>(
            onNotification: (notification) {
              notification.disallowIndicator();
              return false;
            },
            child: ScrollConfiguration(
              behavior: const _NoChatOverscrollBehavior(),
              child: ListView.builder(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                reverse: true,
                padding: EdgeInsets.fromLTRB(
                  10,
                  topPadding,
                  12,
                  bottomPadding,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  // Typing indicator or streaming message at the bottom (index 0 in reversed list)
                  if (extraItems == 1 && index == 0) {
                    if (showTypingIndicator) {
                      return _buildTypingIndicator();
                    }
                    return _buildStreamingReply(_streamingText);
                  }

                  // Load-more indicator at the top (last index in reversed list)
                  if (loadMoreItem == 1 && index == itemCount - 1) {
                    return _buildLoadMoreIndicator();
                  }

                  final messageIndex = _messageIndexForListIndex(
                    listIndex: index,
                    extraItems: extraItems,
                  );
                  final msg = _messages[messageIndex];
                  final showDate = _shouldShowDateDivider(
                    messageIndex,
                    _messages,
                  );
                  final isHighlighted = msg.id == _highlightedMessageId;
                  final isSelected = _selectedMessageIds.contains(msg.id);

                  return KeyedSubtree(
                    key: _messageKeys.putIfAbsent(msg.id, GlobalKey.new),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? _personaAccent.withValues(alpha: 0.12)
                            : isSelected
                                ? _personaAccent.withValues(alpha: 0.08)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _isSelecting
                          ? GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (_selectedMessageIds.contains(msg.id)) {
                                    _selectedMessageIds.remove(msg.id);
                                  } else {
                                    _selectedMessageIds.add(msg.id);
                                  }
                                });
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 2, right: 6),
                                    child: Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      size: 22,
                                      color: isSelected
                                          ? _personaAccent
                                          : _personaTextMuted.withValues(
                                              alpha: 0.4),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        if (showDate)
                                          _buildDateDivider(msg.timestamp),
                                        if (msg.messageType == 'action')
                                          _buildActionMessage(text: msg.content)
                                        else if (msg.isFromCharacter)
                                          _buildCharacterMessage(msg,
                                              isStreaming: false)
                                        else
                                          _buildBubble(
                                            text: msg.content,
                                            isCharacter: msg.isFromCharacter,
                                            message: msg,
                                            messageId: msg.id.toString(),
                                            attachmentsJson:
                                                msg.attachmentsJson,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              children: [
                                if (showDate) _buildDateDivider(msg.timestamp),
                                if (msg.messageType == 'action')
                                  _buildActionMessage(text: msg.content)
                                else if (msg.isFromCharacter)
                                  _buildCharacterMessage(msg,
                                      isStreaming: false)
                                else
                                  _buildBubble(
                                    text: msg.content,
                                    isCharacter: msg.isFromCharacter,
                                    message: msg,
                                    messageId: msg.id.toString(),
                                    attachmentsJson: msg.attachmentsJson,
                                  ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_isSelecting)
          Positioned(
            bottom: bottomPadding - 56,
            left: 16,
            right: 16,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cancel button
                  GestureDetector(
                    onTap: _exitSelectMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _personaPanel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _personaTextMuted.withValues(alpha: 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 14,
                          color: _personaTextMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Delete button
                  GestureDetector(
                    onTap: _selectedMessageIds.isNotEmpty
                        ? _batchDeleteSelectedMessages
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedMessageIds.isNotEmpty
                            ? Colors.red.withValues(alpha: 0.8)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        _chatUiText(zh: '删除', en: 'Delete'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Record button
                  GestureDetector(
                    onTap: _selectedMessageIds.isNotEmpty
                        ? _batchRecordSelectedMessages
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedMessageIds.isNotEmpty
                            ? _personaAccent
                            : _personaAccent.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: _personaAccent.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        '记录为卡片${_selectedMessageIds.isNotEmpty ? ' (${_selectedMessageIds.length})' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  int _messageIndexForListIndex({
    required int listIndex,
    required int extraItems,
  }) {
    return personaChatMessageIndexForReversedList(
      listIndex: listIndex,
      extraItems: extraItems,
    );
  }

  bool _shouldShowDateDivider(
    int messageIndex,
    List<PersonaChatMessage> messages,
  ) {
    // Always show timestamp for the oldest loaded message
    if (messageIndex == messages.length - 1) return true;
    // Show timestamp when gap between adjacent messages exceeds 10 minutes
    // (WeChat/WhatsApp convention)
    final current = messages[messageIndex].timestamp;
    final previous = messages[messageIndex + 1].timestamp;
    return current.difference(previous).inMinutes.abs() >= 10;
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 52, 32, 24),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _personaPanelSoft.withValues(alpha: 0.94),
                      _personaAccent.withValues(alpha: 0.2),
                    ],
                  ),
                  border: Border.all(
                    color: _personaAccent.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _personaAccent.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: CharacterAvatar(
                  avatar: _character?.avatar,
                  name: _character?.name ?? '',
                  size: 96,
                  backgroundColor: Colors.transparent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _character?.name ?? '',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _personaText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final label = _formatTimeDivider(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _personaPanel.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: _personaTextMuted),
          ),
        ),
      ),
    );
  }

  /// Formats a timestamp for the chat time divider, following WeChat conventions:
  /// - Today: "HH:mm"
  /// - Yesterday: "鏄ㄥぉ HH:mm" / "Yesterday HH:mm"
  /// - This week (within 7 days): "鍛ㄤ笁 HH:mm" / "Wed HH:mm"
  /// - This year: "3鏈?5鏃?HH:mm" / "Mar 15 HH:mm"
  /// - Older: "2024骞?鏈?5鏃?HH:mm" / "Mar 15, 2024 HH:mm"
  String _formatTimeDivider(DateTime date) {
    final now = DateTime.now();
    final locale = UserStorage.l10n.localeName;
    final time = DateFormat('HH:mm', locale).format(date);

    if (_isSameDay(date, now)) {
      return time;
    }

    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return '${UserStorage.l10n.yesterday} $time';
    }

    final daysAgo = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;

    if (daysAgo < 7) {
      final weekday = DateFormat.E(locale).format(date);
      return '$weekday $time';
    }

    if (date.year == now.year) {
      return '${DateFormat.MMMd(locale).format(date)} $time';
    }

    return '${DateFormat.yMMMd(locale).format(date)} $time';
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: _personaAccentCool,
            ),
          ),
        ),
      );
    }
    // Invisible sentinel; the scroll listener handles triggering the load.
    return const SizedBox(height: 1);
  }

  /// Renders a narrative / action description message.
  /// No speech bubble; italic text centred with a subtle divider style,
  /// matching the roleplay convention for stage directions.
  Widget _buildActionMessage({required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Base the italic aside's max width on the *actual* available width
          // (which shrinks in selection mode when a checkbox is prepended),
          // not the full screen width, otherwise the two dividers + gaps can
          // exceed the row and overflow by a few pixels.
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          return Row(
            children: [
              Expanded(
                child: Container(
                  height: 0.5,
                  color: _personaLine.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: available * 0.68,
                  ),
                  child: SelectableText(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      fontStyle: FontStyle.italic,
                      color: _personaTextMuted,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 0.5,
                  color: _personaLine.withValues(alpha: 0.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBubble({
    required String text,
    required bool isCharacter,
    bool isStreaming = false,
    PersonaChatMessage? message,
    String? messageId,
    String? attachmentsJson,
    double characterBottomSpacing = 22,
  }) {
    if (isCharacter) {
      return _buildCharacterBubble(
        text: text,
        isStreaming: isStreaming,
        messageId: messageId,
        attachmentsJson: attachmentsJson,
        bottomSpacing: characterBottomSpacing,
      );
    }

    final userMessage = message;
    final attachmentWidgets =
        attachmentsJson != null && attachmentsJson.isNotEmpty
            ? _buildAttachmentWidgets(
                attachmentsJson,
                message!.id,
                onRecord: userMessage != null
                    ? () => _recordMessage(userMessage)
                    : null,
              )
            : <Widget>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 40),
          Flexible(
            child: Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                // translucent: participate in the gesture arena even when
                // children like SelectionArea or inner GestureDetectors
                // also try to claim the event.  _recordingMessageIds guard
                // prevents double-processing if both inner and outer fire.
                behavior: HitTestBehavior.translucent,
                onLongPress: userMessage != null && !_isSelecting
                    ? () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _isSelecting = true;
                          _selectedMessageIds.add(userMessage.id);
                        });
                      }
                    : null,
                onDoubleTap: userMessage != null && !_isSelecting
                    ? () => _recordMessage(userMessage)
                    : null,
                child: _FrostedChatBubbleSurface(
                  isCharacter: false,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (text.isNotEmpty)
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: _personaText,
                          ),
                        ),
                      if (attachmentWidgets.isNotEmpty) ...[
                        if (text.isNotEmpty) const SizedBox(height: 8),
                        ...attachmentWidgets,
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: text));
                            },
                            child: Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: _personaTextMuted,
                            ),
                          ),
                          if (userMessage != null) ...[
                            const SizedBox(width: 8),
                            Semantics(
                              button: true,
                              label: 'Recall message',
                              child: GestureDetector(
                                onTap: () =>
                                    _confirmRetractUserMessage(userMessage),
                                child: Icon(
                                  Icons.undo_rounded,
                                  size: 12,
                                  color: _personaTextMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingReply(String text) {
    return _buildCharacterMessageContent(text: text, isStreaming: true);
  }

  Widget _buildCharacterMessage(
    PersonaChatMessage message, {
    required bool isStreaming,
  }) {
    return _buildCharacterMessageContent(
      text: message.content,
      isStreaming: isStreaming,
      messageId: message.id.toString(),
      attachmentsJson: message.attachmentsJson,
    );
  }

  Widget _buildCharacterMessageContent({
    required String text,
    required bool isStreaming,
    String? messageId,
    String? attachmentsJson,
  }) {
    var segments = PersonaReplySanitizer.splitVisibleReply(
      text,
      // The companion prompt hardcodes "林埃" as the character's Chinese name.
      // The stored character.name ("I") is the English name and won't match
      // the self-referential text in Chinese actions.
      characterName: '林埃',
      // Strip TTS audio tags ([softly], [low voice], etc.) from what the user
      // sees in chat bubbles. Tags are preserved on the TTS path.
      stripTtsTags: true,
    );
    if (segments.isEmpty && text.trim().isNotEmpty) {
      segments = [
        PersonaReplySegment(
          type: PersonaReplySegmentType.chat,
          text: text.trim(),
        ),
      ];
    }

    final chatBubbleCount = _visibleCharacterChatBubbleCountForSegments(
      segments,
    );
    final hasSingleChatBubble = segments.length == 1 &&
        segments.single.type == PersonaReplySegmentType.chat &&
        chatBubbleCount <= 1;
    if (segments.isEmpty || hasSingleChatBubble) {
      return _buildBubble(
        text: segments.isEmpty ? text : segments.single.text,
        isCharacter: true,
        isStreaming: isStreaming,
        messageId: messageId,
        attachmentsJson: attachmentsJson,
      );
    }

    final children = <Widget>[];
    var chatBubbleIndex = 0;
    final useSplitMessageIds =
        messageId != null && (segments.length > 1 || chatBubbleCount > 1);

    String? nextChatMessageId() {
      if (messageId == null) return null;
      if (!useSplitMessageIds) return messageId;
      return '$messageId:${chatBubbleIndex++}';
    }

    void addChatBubbles({
      required String chatText,
      required bool hasVisibleAfter,
      String? blockAttachmentsJson,
    }) {
      final bubbles = PersonaReplySanitizer.splitChatIntoBubbles(chatText);
      for (var i = 0; i < bubbles.length; i++) {
        final isLastBubbleInBlock = i == bubbles.length - 1;
        final isLastVisibleBubble = isLastBubbleInBlock && !hasVisibleAfter;
        children.add(
          _buildBubble(
            text: bubbles[i],
            isCharacter: true,
            isStreaming: isStreaming,
            messageId: nextChatMessageId(),
            attachmentsJson: isLastBubbleInBlock ? blockAttachmentsJson : null,
            characterBottomSpacing: isLastVisibleBubble ? 22 : 8,
          ),
        );
      }
    }

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final hasVisibleAfter = _hasVisibleSegmentsAfter(segments, i);
      if (segment.type == PersonaReplySegmentType.action) {
        children.add(_buildActionMessage(text: segment.text));
      } else {
        addChatBubbles(
          chatText: segment.text,
          hasVisibleAfter: hasVisibleAfter,
          blockAttachmentsJson: attachmentsJson,
        );
        attachmentsJson = null;
      }
    }

    if (children.isEmpty) {
      return _buildBubble(
        text: text,
        isCharacter: true,
        isStreaming: isStreaming,
        messageId: messageId,
        attachmentsJson: attachmentsJson,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  int _visibleCharacterChatBubbleCountForSegments(
    List<PersonaReplySegment> segments,
  ) =>
      _personaChatVisibleChatBubbleCountForSegments(segments);

  bool _hasVisibleSegmentsAfter(
    List<PersonaReplySegment> segments,
    int index,
  ) {
    for (var i = index + 1; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.type == PersonaReplySegmentType.action) {
        if (segment.text.trim().isNotEmpty) return true;
        continue;
      }
      if (PersonaReplySanitizer.splitChatIntoBubbles(segment.text).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Per-message image byte cache so base64 is decoded once and reused
  /// across ListView rebuilds instead of re-decoding every frame on scroll.
  final Map<int, Uint8List> _imageByteCache = {};

  /// Renders image attachments from a JSON-encoded attachments list below
  /// the text in a user's chat bubble. Each attachment has `base64` (WebP)
  /// and `mimeType` fields.
  /// Double-tap on an image triggers recording via [onRecord].
  List<Widget> _buildAttachmentWidgets(
    String attachmentsJson,
    int messageId, {
    VoidCallback? onRecord,
  }) {
    try {
      final List<dynamic> attachments = jsonDecode(attachmentsJson);
      final widgets = <Widget>[];
      for (var i = 0; i < attachments.length; i++) {
        final att = attachments[i];
        final base64 = att['base64'] as String;
        final cacheKey = messageId * 1000 + i;
        Uint8List? bytes = _imageByteCache[cacheKey];
        if (bytes == null) {
          bytes = Uint8List.fromList(base64Decode(base64));
          _imageByteCache[cacheKey] = bytes;
        }
        widgets.add(
          Padding(
            key: ValueKey('chat-img-$messageId-$i'),
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onDoubleTap: onRecord,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        );
      }
      return widgets;
    } catch (e) {
      debugPrint('Failed to decode chat attachments: $e');
      return [];
    }
  }

  Widget _buildCharacterBubble({
    required String text,
    required bool isStreaming,
    String? messageId,
    String? attachmentsJson,
    double bottomSpacing = 22,
  }) {
    final hasActions = !isStreaming && messageId != null && !_isSelecting;
    final hasAddenda =
        attachmentsJson != null && attachmentsJson.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                onLongPress: hasActions
                    ? () {
                        HapticFeedback.mediumImpact();
                        final msgId = int.tryParse(messageId.split(':').first);
                        setState(() {
                          _isSelecting = true;
                          if (msgId != null) _selectedMessageIds.add(msgId);
                        });
                      }
                    : null,
                child: _CharacterMessageFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: MarkdownBody(
                              data: text,
                              softLineBreak: true,
                              styleSheet: _messageMarkdownStyle,
                            ),
                          ),
                          if (isStreaming) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _personaAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (hasAddenda) ...[
                        const SizedBox(height: 10),
                        MessageAddendumRenderer(
                          attachmentsJson: attachmentsJson,
                          isCharacterBubble: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Align(
              alignment: Alignment.topLeft,
              child: _FramedCharacterAvatar(
                avatar: _character?.avatar,
                name: _character?.name ?? '',
                size: 40,
              ),
            ),
          ),
          const _FrostedChatBubbleSurface(
            isCharacter: true,
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: _TypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return PersonaChatInputBar(
      controller: _textController,
      isStreaming: _isStreaming,
      onSend: _sendMessage,
      hintText: UserStorage.l10n.personaChatInputHint,
      voiceController: _voiceController,
      onVoiceTap: _onVoiceToggle,
      isVoiceInputEnabled:
          _isInlineVoiceMode ? !_isStreaming : !_isVoiceReplyActive,
      isVoiceModeActive: _isInlineVoiceMode,
      onVoiceModeTap: () => unawaited(_setInlineVoiceMode(!_isInlineVoiceMode)),
      onAddTap: widget.enableRichCapture
          ? () => setState(() => _isMediaTrayOpen = !_isMediaTrayOpen)
          : null,
      isAddActive: _isMediaTrayOpen,
      selectedImages: _selectedImages,
      onRemoveImage: _removeImage,
      isCompressing: _isCompressingImages,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

@visibleForTesting
int personaChatVisibleChatBubbleCount(String text) {
  final segments = PersonaReplySanitizer.splitVisibleReply(
    text,
    stripTtsTags: true,
  );
  return _personaChatVisibleChatBubbleCountForSegments(segments);
}

int _personaChatVisibleChatBubbleCountForSegments(
  List<PersonaReplySegment> segments,
) {
  var count = 0;
  for (final segment in segments) {
    if (segment.type != PersonaReplySegmentType.chat) continue;
    count += PersonaReplySanitizer.splitChatIntoBubbles(segment.text).length;
  }
  return count;
}

@visibleForTesting
int personaChatMessageIndexForReversedList({
  required int listIndex,
  required int extraItems,
}) {
  return listIndex - extraItems;
}

@visibleForTesting
int? personaChatFirstNewCharacterMessageId({
  required List<PersonaChatMessage> previousMessages,
  required List<PersonaChatMessage> updatedMessages,
}) {
  final previousIds = previousMessages.map((message) => message.id).toSet();
  final candidates = updatedMessages
      .where(
        (message) =>
            message.isFromCharacter && !previousIds.contains(message.id),
      )
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return candidates.first.id;
}

@visibleForTesting
List<PersonaChatMessage> personaChatGeneratedReadableMessagesInOrder({
  required List<PersonaChatMessage> previousMessages,
  required List<PersonaChatMessage> updatedMessages,
}) {
  final previousIds = previousMessages.map((message) => message.id).toSet();
  final candidates = updatedMessages
      .where(
        (message) =>
            !previousIds.contains(message.id) &&
            message.isFromCharacter &&
            message.messageType == 'chat' &&
            message.content.trim().isNotEmpty,
      )
      .toList();
  candidates.sort((a, b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return candidates;
}

@visibleForTesting
String personaChatTtsPlaybackIdForMessage(PersonaChatMessage message) {
  final segments = PersonaReplySanitizer.splitVisibleReply(
    message.content,
    stripTtsTags: true,
  );
  final hasSplitSpeech = segments.length > 1 &&
      segments.any((segment) => segment.type == PersonaReplySegmentType.chat);
  final hasSplitBubbles =
      _personaChatVisibleChatBubbleCountForSegments(segments) > 1;
  return hasSplitSpeech || hasSplitBubbles
      ? '${message.id}:0'
      : message.id.toString();
}

@visibleForTesting
String personaChatSearchSnippet(String text, String query) {
  final compact = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final q = query.trim();
  if (q.isEmpty || compact.length <= 120) return compact;
  final index = compact.toLowerCase().indexOf(q.toLowerCase());
  if (index < 0) {
    return compact.length <= 120 ? compact : '${compact.substring(0, 120)}...';
  }
  final start = index - 48 < 0 ? 0 : index - 48;
  final end = index + q.length + 72 > compact.length
      ? compact.length
      : index + q.length + 72;
  return '${start > 0 ? '...' : ''}${compact.substring(start, end)}${end < compact.length ? '...' : ''}';
}

class _PersonaChatSearchSheet extends StatefulWidget {
  const _PersonaChatSearchSheet({
    required this.characterId,
    required this.chatService,
    this.characterName,
  });

  final String characterId;
  final PersonaChatService chatService;
  final String? characterName;

  @override
  State<_PersonaChatSearchSheet> createState() =>
      _PersonaChatSearchSheetState();
}

class _PersonaChatSearchSheetState extends State<_PersonaChatSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _results = <PersonaChatMessage>[];
  var _isSearching = false;
  var _query = '';
  var _searchSerial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _runSearch);
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  Future<void> _runSearch() async {
    final query = _query.trim();
    final serial = ++_searchSerial;
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    final results = await widget.chatService.searchMessages(
      widget.characterId,
      query,
      limit: 80,
    );
    if (!mounted || serial != _searchSerial) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: _personaPanel,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _personaLine,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: _personaStageInk.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _personaLine.withValues(alpha: 0.72),
                            ),
                          ),
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            onChanged: _onQueryChanged,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _runSearch(),
                            style: TextStyle(
                              color: _personaText,
                              fontSize: 15,
                              letterSpacing: 0,
                            ),
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: _personaTextMuted,
                                size: 20,
                              ),
                              suffixIcon: _controller.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: _personaTextMuted,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _controller.clear();
                                        _onQueryChanged('');
                                      },
                                    ),
                              hintText: _chatUiText(
                                zh: '搜索聊天记录',
                                en: 'Search chat history',
                              ),
                              hintStyle: TextStyle(
                                color: _personaTextMuted,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          UserStorage.l10n.cancel,
                          style: TextStyle(color: _personaAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final query = _query.trim();
    if (query.isEmpty) {
      return _SearchEmptyState(
        icon: Icons.search_rounded,
        label: _chatUiText(zh: '输入关键词查找这段聊天', en: 'Type to find a message'),
      );
    }
    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: _personaAccent,
        ),
      );
    }
    if (_results.isEmpty) {
      return _SearchEmptyState(
        icon: Icons.search_off_rounded,
        label: _chatUiText(zh: '没有找到匹配的记录', en: 'No matching messages'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: _personaLine.withValues(alpha: 0.5)),
      itemBuilder: (context, index) {
        final message = _results[index];
        return _SearchResultTile(
          message: message,
          query: query,
          characterName: widget.characterName,
          onTap: () => Navigator.pop(context, message),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.message,
    required this.query,
    required this.onTap,
    this.characterName,
  });

  final PersonaChatMessage message;
  final String query;
  final VoidCallback onTap;
  final String? characterName;

  @override
  Widget build(BuildContext context) {
    final locale = UserStorage.l10n.localeName;
    final sender = message.isFromCharacter
        ? (characterName ?? _chatUiText(zh: '瑙掕壊', en: 'Companion'))
        : _chatUiText(zh: '我', en: 'Me');
    final time = DateFormat.yMMMd(locale).add_Hm().format(message.timestamp);
    final snippet = personaChatSearchSnippet(message.content, query);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              message.isFromCharacter
                  ? Icons.auto_awesome_rounded
                  : Icons.person_rounded,
              size: 18,
              color:
                  message.isFromCharacter ? _personaAccent : _personaAccentCool,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _personaText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: TextStyle(
                          color: _personaTextMuted,
                          fontSize: 11,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _HighlightedSnippet(text: snippet, query: query),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _chatUiText(zh: '澶嶅埗', en: 'Copy'),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(
                  Icons.copy_rounded,
                  size: 17,
                  color: _personaTextMuted,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index < 0 || query.isEmpty) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _personaTextMuted,
          fontSize: 13.5,
          height: 1.45,
          letterSpacing: 0,
        ),
      );
    }
    final before = text.substring(0, index);
    final match = text.substring(index, index + query.length);
    final after = text.substring(index + query.length);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              color: _personaStageInk,
              backgroundColor: _personaAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _personaTextMuted,
        fontSize: 13.5,
        height: 1.45,
        letterSpacing: 0,
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: _personaTextMuted),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: _personaTextMuted,
              fontSize: 14,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAtmosphereBackground extends StatefulWidget {
  const _ChatAtmosphereBackground({required this.character});

  final CharacterModel? character;

  @override
  State<_ChatAtmosphereBackground> createState() =>
      _ChatAtmosphereBackgroundState();
}

class _ChatAtmosphereBackgroundState extends State<_ChatAtmosphereBackground> {
  bool? _hasCustomBg;
  String? _cachedBgPath;
  String? _cachedImageKey;

  @override
  void initState() {
    super.initState();
    _refreshCache();
  }

  @override
  void didUpdateWidget(covariant _ChatAtmosphereBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.character?.chatBackground !=
        oldWidget.character?.chatBackground) {
      _refreshCache();
    }
  }

  void _refreshCache() {
    final bgPath = widget.character?.chatBackground;
    if (bgPath != null && bgPath.isNotEmpty) {
      _cachedBgPath = bgPath;
      try {
        final file = File(bgPath);
        _hasCustomBg = file.existsSync();
        if (_hasCustomBg!) {
          final stat = file.statSync();
          _cachedImageKey =
              '$bgPath:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
        } else {
          _cachedImageKey = null;
        }
      } catch (_) {
        _hasCustomBg = false;
        _cachedImageKey = null;
      }
    } else {
      _hasCustomBg = false;
      _cachedBgPath = null;
      _cachedImageKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomBg = _hasCustomBg ?? false;
    final bgPath = _cachedBgPath;
    final tokens = context.hereIamTheme;

    return Stack(
      children: [
        if (hasCustomBg && bgPath != null)
          Positioned.fill(
            child: Image.file(
              File(bgPath),
              key: ValueKey(_cachedImageKey ?? bgPath),
              fit: BoxFit.cover,
            ),
          )
        else
          Positioned.fill(
            child: Image.asset(
              'assets/images/dusky_rose_rain_glass.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              color: tokens.background.withValues(alpha: 0.18),
              colorBlendMode: BlendMode.multiply,
            ),
          ),
        if (!hasCustomBg)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF070608).withValues(alpha: 0.24),
                    tokens.background.withValues(alpha: 0.08),
                    tokens.background.withValues(alpha: 0.22),
                    const Color(0xFF070608).withValues(alpha: 0.78),
                  ],
                  stops: const [0, 0.34, 0.68, 1],
                ),
              ),
            ),
          ),
        if (!hasCustomBg) ...[
          Positioned(
            top: -88,
            left: -72,
            child: _AtmosphereGlow(
              size: 240,
              color: const Color(0xFFD36F7E).withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            top: 112,
            right: -72,
            child: _AtmosphereGlow(
              size: 300,
              color: const Color(0xFFE0A06F).withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            bottom: 96,
            left: -110,
            child: _AtmosphereGlow(
              size: 340,
              color: const Color(0xFF7E4A55).withValues(alpha: 0.20),
            ),
          ),
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.32,
            left: MediaQuery.sizeOf(context).width * 0.18,
            child: _AtmosphereGlow(
              size: 220,
              color: const Color(0xFFD36F7E).withValues(alpha: 0.12),
            ),
          ),
        ],
        if (hasCustomBg)
          // Bottom-up dark gradient: solid dark at bottom (input bar area),
          // fades to transparent around the first message zone so the
          // background image emerges naturally upward. No top overlay.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    tokens.backgroundSoft,
                    tokens.backgroundSoft.withValues(alpha: 0.92),
                    tokens.backgroundSoft.withValues(alpha: 0.55),
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: const [0, 0.10, 0.30, 0.50, 1],
                ),
              ),
            ),
          )
        else
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.16),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.34),
                  ],
                  stops: const [0, 0.2, 0.7, 1],
                ),
              ),
            ),
          ),
        const Positioned.fill(
          child: HereIamRainLayer(
            opacity: 0.0,
            microOpacity: 0.0,
            dropletOpacity: 0.0,
          ),
        ),
      ],
    );
  }
}

@visibleForTesting
class ConversationCaptureRememberedNotice extends StatelessWidget {
  const ConversationCaptureRememberedNotice({super.key, required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final paddingBottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 24,
      right: 24,
      bottom: viewInsetsBottom + paddingBottom + 96,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
              decoration: BoxDecoration(
                color: _personaPanel.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.38),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: _personaAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    UserStorage.l10n.companionRemembered,
                    style: TextStyle(
                      color: _personaText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 1,
                    height: 15,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  TextButton(
                    onPressed: onUndo,
                    style: TextButton.styleFrom(
                      foregroundColor: _personaAccent,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      UserStorage.l10n.undo,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AtmosphereGlow extends StatelessWidget {
  const _AtmosphereGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

class _NoChatOverscrollBehavior extends ScrollBehavior {
  const _NoChatOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _FrostedChatBubbleSurface extends StatelessWidget {
  const _FrostedChatBubbleSurface({
    required this.child,
    required this.isCharacter,
    this.padding = const EdgeInsets.fromLTRB(18, 13, 18, 13),
  });

  final Widget child;
  final bool isCharacter;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = isCharacter
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(24),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(8),
          );
    final tint =
        isCharacter ? const Color(0xFF241319) : const Color(0xFF70403C);

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.88,
      ),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 44,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: const Color(0xFFFFECDD).withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: isCharacter ? 0.24 : 0.26),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFFFECDD).withValues(alpha: 0.16),
                        const Color(0xFFFFECDD).withValues(alpha: 0.055),
                        tint.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.10),
                      ],
                      stops: const [0, 0.38, 0.72, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: RadialGradient(
                      center: isCharacter
                          ? const Alignment(-0.65, -0.78)
                          : const Alignment(0.66, -0.74),
                      radius: 0.92,
                      colors: [
                        const Color(0xFFFFFFFF).withValues(alpha: 0.105),
                        const Color(0xFFFFECDD).withValues(alpha: 0.035),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterMessageFrame extends StatelessWidget {
  const _CharacterMessageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _FrostedChatBubbleSurface(isCharacter: true, child: child);
  }
}

class _FramedCharacterAvatar extends StatelessWidget {
  const _FramedCharacterAvatar({
    required this.avatar,
    required this.name,
    required this.size,
  });

  final String? avatar;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CharacterAvatar(
        avatar: avatar,
        name: name,
        size: size - 3,
        backgroundColor: _personaPanelSoft,
      ),
    );
  }
}

class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF241319).withValues(alpha: 0.24),
            border: Border.all(
              color: const Color(0xFFFFECDD).withValues(alpha: 0.045),
              width: 0.8,
            ),
            gradient: RadialGradient(
              center: const Alignment(-0.45, -0.55),
              radius: 1.05,
              colors: [
                const Color(0xFFFFECDD).withValues(alpha: 0.105),
                const Color(0xFFC86774).withValues(alpha: 0.055),
                Colors.black.withValues(alpha: 0.045),
              ],
              stops: const [0, 0.52, 1],
            ),
          ),
          child: IconTheme(
            data: IconThemeData(color: _personaText),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _HeaderImageAvatar extends StatelessWidget {
  const _HeaderImageAvatar({
    required this.avatar,
    required this.size,
  });

  final String avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(avatar),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: HereIamGlassSurface(
          level: active ? HereIamGlassLevel.hero : HereIamGlassLevel.raised,
          shape: BoxShape.circle,
          width: 40,
          height: 40,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: active ? _personaAccent : _personaText,
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class PersonaAutoReadToggle extends StatelessWidget {
  const PersonaAutoReadToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: enabled,
      label: enabled ? '关闭自动朗读' : '开启自动朗读',
      child: GestureDetector(
        onTap: () => onChanged(!enabled),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            color: enabled
                ? _personaAccent.withValues(alpha: 0.18)
                : _personaPanel.withValues(alpha: 0.62),
            border: Border.all(
              color: enabled
                  ? _personaAccent.withValues(alpha: 0.46)
                  : _personaAccent.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled
                    ? Icons.record_voice_over_rounded
                    : Icons.record_voice_over_outlined,
                color: enabled ? _personaAccent : _personaTextMuted,
                size: 17,
              ),
              const SizedBox.shrink(),
              Text(
                '鑷姩鏈楄',
                style: TextStyle(
                  color: enabled ? _personaAccent : _personaTextMuted,
                  fontSize: 0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TappableUserAvatar extends StatefulWidget {
  const _TappableUserAvatar({
    required this.avatar,
    required this.name,
    required this.size,
    this.onTap,
  });

  final String? avatar;
  final String name;
  final double size;
  final VoidCallback? onTap;

  @override
  State<_TappableUserAvatar> createState() => _TappableUserAvatarState();
}

class _TappableUserAvatarState extends State<_TappableUserAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeIn,
        reverseCurve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _ctrl.forward();

  void _onTapUp(TapUpDetails _) {
    _ctrl.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return _UserAvatar(
        avatar: widget.avatar,
        name: widget.name,
        size: widget.size,
      );
    }
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: _UserAvatar(
          avatar: widget.avatar,
          name: widget.name,
          size: widget.size,
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.avatar,
    required this.name,
    required this.size,
  });

  final String? avatar;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CharacterAvatar(
      avatar:
          avatar ?? (name.isNotEmpty ? name : UserStorage.defaultAvatarSeed),
      name: name,
      size: size,
      backgroundColor: _personaAccentCool.withValues(alpha: 0.22),
    );
  }
}

class PersonaChatInputBar extends StatelessWidget {
  const PersonaChatInputBar({
    super.key,
    required this.controller,
    required this.isStreaming,
    required this.onSend,
    required this.hintText,
    this.voiceController,
    this.onVoiceTap,
    this.isVoiceInputEnabled = true,
    this.onVoiceModeTap,
    this.isVoiceModeActive = false,
    this.onAddTap,
    this.isAddActive = false,
    this.selectedImages = const [],
    this.onRemoveImage,
    this.isCompressing = false,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;
  final String hintText;

  /// Optional: when provided together with [onVoiceTap], renders a mic button
  /// before the send button.
  final VoiceInputController? voiceController;
  final VoidCallback? onVoiceTap;
  final bool isVoiceInputEnabled;
  final VoidCallback? onVoiceModeTap;
  final bool isVoiceModeActive;
  final VoidCallback? onAddTap;
  final bool isAddActive;

  /// Selected image attachments shown as inline preview chips.
  final List<XFile> selectedImages;
  final void Function(int index)? onRemoveImage;
  final bool isCompressing;

  bool _canSend(String value, bool hasImages) =>
      value.trim().isNotEmpty || hasImages;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final hasImages = selectedImages.isNotEmpty || isCompressing;
    final tokens = HereIamThemeRuntime.current;
    final isDark = tokens.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(32, 10, 32, bottomPadding + 24),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final canSend = _canSend(value.text, selectedImages.isNotEmpty);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImages) ...[
                SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              selectedImages.length + (isCompressing ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            if (isCompressing &&
                                index == selectedImages.length) {
                              return SizedBox(
                                width: 56,
                                height: 56,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _personaAccent,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final image = selectedImages[index];
                            return GestureDetector(
                              onTap: () => onRemoveImage?.call(index),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(image.path),
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.6,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _FloatingGlassInputCapsule(
                      isDark: isDark,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (onAddTap != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: _AddButton(
                                enabled: !isStreaming,
                                onTap: onAddTap!,
                                active: isAddActive,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: TextField(
                              controller: controller,
                              minLines: 1,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: TextStyle(
                                  color: _personaTextMuted,
                                  fontSize: 15,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 10,
                                ),
                                border: InputBorder.none,
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                color: _personaText,
                              ),
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              // Input stays enabled during streaming; sending then
                              // queues the message for the next response turn.
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 1),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              child: canSend
                                  ? _SendAndMaybeEndVoiceMode(
                                      key: ValueKey(
                                        isVoiceModeActive
                                            ? 'send-with-voice-end'
                                            : 'send',
                                      ),
                                      onSend: onSend,
                                      onVoiceModeTap: onVoiceModeTap,
                                      showVoiceModeEnd: isVoiceModeActive,
                                    )
                                  : voiceController != null
                                      ? _ChatVoiceActions(
                                          key: const ValueKey('voice-actions'),
                                          voiceController: voiceController,
                                          onVoiceTap: onVoiceTap,
                                          onVoiceModeTap: onVoiceModeTap,
                                          isVoiceModeActive: isVoiceModeActive,
                                          voiceInputEnabled:
                                              isVoiceInputEnabled,
                                          voiceModeEnabled:
                                              isVoiceModeActive || !isStreaming,
                                        )
                                      : const SizedBox(
                                          key: ValueKey('no-send')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatingGlassInputCapsule extends StatelessWidget {
  const _FloatingGlassInputCapsule({required this.child, required this.isDark});

  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return HereIamGlassSurface(
      level: HereIamGlassLevel.raised,
      borderRadius: BorderRadius.circular(27),
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      child: child,
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.enabled,
    required this.onTap,
    required this.active,
  });

  final bool enabled;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Add attachment',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: ClipOval(
          child: RepaintBoundary(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF241319).withValues(alpha: 0.38),
                  gradient: RadialGradient(
                    center: const Alignment(-0.36, -0.44),
                    radius: 1.08,
                    colors: [
                      const Color(
                        0xFFFFECDD,
                      ).withValues(alpha: active ? 0.13 : 0.08),
                      active
                          ? const Color(0xFF4D222B).withValues(alpha: 0.58)
                          : const Color(0xFF3A2123).withValues(alpha: 0.48),
                      const Color(0xFF120B0E).withValues(alpha: 0.72),
                    ],
                    stops: const [0, 0.54, 1],
                  ),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFFFC6B5).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.045),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: const Color(0xFFC0646E).withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: Offset.zero,
                    ),
                  ],
                ),
                child: Icon(
                  active ? Icons.close_rounded : Icons.add_rounded,
                  color: enabled
                      ? const Color(0xFFF6F0EF).withValues(alpha: 0.86)
                      : _personaTextMuted,
                  size: 23,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatVoiceActions extends StatelessWidget {
  const _ChatVoiceActions({
    super.key,
    required this.voiceController,
    required this.onVoiceTap,
    required this.onVoiceModeTap,
    required this.isVoiceModeActive,
    required this.voiceInputEnabled,
    required this.voiceModeEnabled,
  });

  final VoiceInputController? voiceController;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onVoiceModeTap;
  final bool isVoiceModeActive;
  final bool voiceInputEnabled;
  final bool voiceModeEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (voiceController != null && onVoiceTap != null) ...[
          VoiceInputButton(
            controller: voiceController!,
            onTap: onVoiceTap!,
            iconColor: const Color(0xFFF6F0EF).withValues(alpha: 0.84),
            bgColor: const Color(0xFF241319).withValues(alpha: 0.34),
            enabled: voiceInputEnabled,
          ),
          const SizedBox(width: 8),
        ],
        if (onVoiceModeTap != null)
          _VoiceModeButton(
            enabled: voiceModeEnabled,
            active: isVoiceModeActive,
            onTap: onVoiceModeTap!,
          ),
      ],
    );
  }
}

class _SendAndMaybeEndVoiceMode extends StatelessWidget {
  const _SendAndMaybeEndVoiceMode({
    super.key,
    required this.onSend,
    required this.onVoiceModeTap,
    required this.showVoiceModeEnd,
  });

  final VoidCallback onSend;
  final VoidCallback? onVoiceModeTap;
  final bool showVoiceModeEnd;

  @override
  Widget build(BuildContext context) {
    if (!showVoiceModeEnd || onVoiceModeTap == null) {
      return _SendButton(enabled: true, onTap: onSend);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SendButton(enabled: true, onTap: onSend),
        const SizedBox(width: 8),
        _VoiceModeButton(enabled: true, active: true, onTap: onVoiceModeTap!),
      ],
    );
  }
}

class _VoiceModeButton extends StatelessWidget {
  const _VoiceModeButton({
    required this.enabled,
    required this.active,
    required this.onTap,
  });

  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: active,
      label: active ? 'End voice mode' : 'Start voice mode',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF241319).withValues(alpha: 0.30),
                gradient: RadialGradient(
                  center: const Alignment(-0.32, -0.42),
                  radius: 1.12,
                  colors: active
                      ? [
                          const Color(0xFFFFECDD).withValues(alpha: 0.12),
                          const Color(0xFFC0646E).withValues(alpha: 0.38),
                          const Color(0xFF4D222B).withValues(alpha: 0.60),
                        ]
                      : [
                          const Color(0xFFFFECDD).withValues(alpha: 0.07),
                          const Color(0xFF3A2123).withValues(alpha: 0.34),
                          const Color(0xFF120B0E).withValues(alpha: 0.54),
                        ],
                  stops: const [0, 0.56, 1],
                ),
                border: Border.all(
                  color: active
                      ? const Color(0xFFFFC6B5).withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.035),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFFC0646E,
                          ).withValues(alpha: 0.16),
                          blurRadius: 16,
                          offset: Offset.zero,
                        ),
                      ]
                    : null,
              ),
              child: active
                  ? Icon(
                      Icons.close_rounded,
                      color: enabled
                          ? const Color(0xFFF6F0EF).withValues(alpha: 0.88)
                          : _personaTextMuted,
                      size: 23,
                    )
                  : _VoiceBarsIcon(
                      color: enabled
                          ? const Color(0xFFF6F0EF).withValues(alpha: 0.82)
                          : _personaTextMuted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceBarsIcon extends StatelessWidget {
  const _VoiceBarsIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [11.0, 19.0, 23.0, 15.0];
    return SizedBox(
      width: 22,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final height in heights) ...[
            Container(
              width: 2.3,
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            if (height != heights.last) const SizedBox(width: 2.8),
          ],
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send message',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF241319).withValues(alpha: 0.38),
                gradient: RadialGradient(
                  center: const Alignment(-0.36, -0.44),
                  radius: 1.12,
                  colors: enabled
                      ? [
                          const Color(0xFFFFECDD).withValues(alpha: 0.13),
                          const Color(0xFFC0646E).withValues(alpha: 0.48),
                          const Color(0xFF4D222B).withValues(alpha: 0.66),
                        ]
                      : [
                          const Color(0xFFFFECDD).withValues(alpha: 0.06),
                          const Color(0xFF3A2123).withValues(alpha: 0.32),
                          const Color(0xFF120B0E).withValues(alpha: 0.58),
                        ],
                  stops: const [0, 0.56, 1],
                ),
                border: Border.all(
                  color: enabled
                      ? const Color(0xFFFFC6B5).withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.035),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                  if (enabled)
                    BoxShadow(
                      color: const Color(0xFFC0646E).withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: Offset.zero,
                    ),
                ],
              ),
              child: Center(
                child: _PaperPlaneIcon(
                  color: enabled
                      ? const Color(0xFFF6F0EF).withValues(alpha: 0.92)
                      : _personaTextMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperPlaneIcon extends StatelessWidget {
  const _PaperPlaneIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _PaperPlanePainter(color),
    );
  }
}

class _PaperPlanePainter extends CustomPainter {
  const _PaperPlanePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final plane = Path()
      ..moveTo(w * 0.12, h * 0.50)
      ..lineTo(w * 0.88, h * 0.16)
      ..lineTo(w * 0.58, h * 0.88)
      ..lineTo(w * 0.45, h * 0.58)
      ..close();

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawPath(plane, fill);

    final crease = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4D222B).withValues(alpha: 0.44);
    canvas.drawLine(
      Offset(w * 0.45, h * 0.58),
      Offset(w * 0.88, h * 0.16),
      crease,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperPlanePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Animated three-dot typing indicator.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each dot by 0.2
            final delay = i * 0.2;
            final t = (_controller.value - delay) % 1.0;
            // Bounce: peak at 0.3, back to 0 at 0.6
            final offset = t < 0.3
                ? -4.0 * (t / 0.3)
                : t < 0.6
                    ? -4.0 * (1 - (t - 0.3) / 0.3)
                    : 0.0;
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Transform.translate(
                offset: Offset(0, offset),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _personaAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
