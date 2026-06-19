import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:memex/agent/built_in_tools/asset_analysis_tool.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/asr/media_button_service.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/data/services/active_persona_chat_service.dart';
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
import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/reading/reading_capture_service.dart';
import 'package:memex/ui/character/widgets/addenda/message_addendum_renderer.dart';
import 'package:memex/ui/character/widgets/voice_input_button.dart';
import 'package:memex/ui/character/widgets/chat_task_capsule.dart';
import 'package:memex/ui/companion/widgets/companion_media_tray.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:intl/intl.dart';

const _personaStageInk = Color(0xFF080B12);
const _personaPanel = Color(0xFF101217);
const _personaPanelSoft = Color(0xFF1B1D24);
const _personaText = Color(0xFFF2ECE0);
const _personaTextMuted = Color(0xFF9E9A94);
const _personaAccent = Color(0xFFE4D6BD);
const _personaAccentCool = Color(0xFF6F7E91);
const _personaLine = Color(0xFF343A45);
const _personaCharacterBubble = Color(0xD9101115);
const _personaUserBubble = Color(0xFFE8DEC8);
const _personaUserBorder = Color(0xFFEFE4CD);
const _voiceModeIdleFollowUpSilenceTimeout = Duration(seconds: 60);
const _voiceModeMaxRecordingDuration = Duration(seconds: 120);
const _voiceModeMaxSilentFollowUps = 8;

String _chatUiText({required String zh, required String en}) {
  return UserStorage.l10n.localeName.toLowerCase().startsWith('zh') ? zh : en;
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
  const _VoiceModeOpening({
    required this.text,
    required this.playbackId,
  });

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
  bool _isLoading = true;
  bool _isStreaming = false;
  String _streamingText = '';
  int _sendSerial = 0;
  int? _activeSendSerial;
  int? _activeUserMessageId;
  String? _activeStreamingCharacterId;
  final Set<int> _canceledSendSerials = {};
  final Set<int> _retractedUserMessageIds = {};

  // Pending message queue 鈥?user can compose the next message while the
  // character is still generating a response. It auto-sends when streaming ends.
  final List<_PendingPersonaChatMessage> _pendingMessages = [];

  bool _isMediaTrayOpen = false;

  // Image attachment state 鈥?moved up from CompanionMediaTray
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
  final _messageKeys = <int, GlobalKey>{};
  Timer? _highlightTimer;
  int? _highlightedMessageId;
  bool _isHeaderActionsOpen = false;
  bool _showJumpToLatest = false;

  ToyController? _toyControlService;
  bool _toyConnected = false;
  bool _toyConnecting = false;

  // Pagination state 鈥?WeChat/WhatsApp style: load older messages on scroll-up
  static const int _pageSize = 30;
  static const Duration _recallGracePeriod = Duration(milliseconds: 900);
  bool _hasMoreHistory = true;
  bool _isLoadingMore = false;

  // Cached MarkdownStyleSheet 鈥?avoid recreating on every build
  static final _cachedMarkdownStyle = MarkdownStyleSheet(
    p: const TextStyle(
      fontSize: 15,
      height: 1.68,
      color: _personaText,
    ),
    strong: const TextStyle(
      fontWeight: FontWeight.w700,
      color: _personaText,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    listBullet: const TextStyle(color: _personaAccent),
    code: const TextStyle(
      fontSize: 13,
      color: _personaText,
      backgroundColor: Color(0xFF241615),
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF241615),
      borderRadius: BorderRadius.circular(8),
    ),
  );

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
    unawaited(
        ActivePersonaChatService.instance.markActive(_currentCharacterId));
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
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
    debugPrint('VoiceInputKey: logical=${event.logicalKey.debugName} '
        'physical=${event.physicalKey.debugName} '
        'char=${event.character}');

    // Volume keys deliberately excluded 鈥?they conflict with TTS volume control.
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
    unawaited(Future<void>.delayed(delay).then((_) {
      _voiceModeStartQueued = false;
      unawaited(_startVoiceModeRecordingIfReady());
    }));
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

    final character = await CharacterService.instance
        .getCharacter(userId, _currentCharacterId);
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
    if (widget.enableRichCapture) {
      unawaited(_scheduleConversationCapture(
        force: true,
        trigger: 'leave_chat',
      ));
    }
    unawaited(
      ActivePersonaChatService.instance.clear(
        characterId: _currentCharacterId,
      ),
    );
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
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
    super.dispose();
  }

  /// Triggered when user scrolls toward the top (older messages).
  /// Since the list is reversed, maxScrollExtent = oldest direction.
  void _onScroll() {
    final pos = _scrollController.position;
    final shouldShowJump = pos.pixels > 180;
    if (shouldShowJump != _showJumpToLatest && mounted) {
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
    if (_refreshPersonaChatMessageAdded()) return;
    final previousMessages = List<PersonaChatMessage>.of(_messages);
    // New message arrived 鈥?reload the latest page and keep any older
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
        ConversationCaptureService.instance.undoOperations(
          message.operationIds,
        ),
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
    unawaited(_refreshMessagesFromStore(
      autoRead: _autoReadEnabled,
      scrollToBottom: true,
    ));
    return true;
  }

  void _startMessageRefreshTimer() {
    _messageRefreshTimer?.cancel();
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isLoading || _isStreaming || _isAppInBackground) return;
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
  }) async {
    final isQueuedMessage = queuedMessage != null;
    final text = queuedMessage?.text ?? _textController.text.trim();
    final hasText = text.isNotEmpty;
    final queuedImages = queuedMessage?.images;
    final hasImages = queuedImages?.isNotEmpty ?? _selectedImages.isNotEmpty;
    if (!hasText && !hasImages) return;

    final sendCharacterId =
        queuedMessage?.characterId ?? forcedCharacterId ?? _currentCharacterId;
    final sendCharacter = queuedMessage?.character ??
        (forcedCharacterId == null ? _character : forcedCharacter);

    // While the character is still typing, queue the message 鈥?it will be sent
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
    final isExplicitMemoryRequest =
        hasText && _isExplicitMemoryRequest(textToSend);

    // Compress images for chat bubble display and DB storage.
    List<Map<String, String>>? compressedAttachments;
    if (hasImages && !isQueuedMessage) {
      setState(() => _isCompressingImages = true);
      compressedAttachments = [];
      for (final image in imagesToSend) {
        final compressed = await _compressImageForChat(image);
        if (compressed != null) {
          compressedAttachments.add(compressed);
        }
      }
      if (mounted) setState(() => _isCompressingImages = false);
    }

    // Persist user message with attachments
    final userMessageId = queuedMessage?.messageId ??
        await _chatService.addUserMessage(
          sendCharacterId,
          textToSend,
          timestamp: userMessageTime,
          attachments: compressedAttachments,
          appendTimeline: false,
        );
    final sendSerial = ++_sendSerial;
    _activeSendSerial = sendSerial;
    _activeUserMessageId = userMessageId;
    _activeStreamingCharacterId = sendCharacterId;

    // Reload messages to show user's message (preserve loaded history depth)
    final messages = await _chatService.getMessages(
      sendCharacterId,
      limit: _messages.length + 1,
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
    // Analysis runs once; results feed both the chat context and the
    // background card pipeline.
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
            prompt: 'Describe this image briefly in 1-2 sentences. '
                'Focus on what is visible: people, objects, text, scenes. '
                'Be concise and objective.',
          );
          // Strip the "#Asset ... analysis result\n:" prefix.
          final cleaned = result
              .replaceFirst(RegExp(r'^#Asset .+ analysis result\n:'), '')
              .trim();
          if (cleaned.isNotEmpty) analyses.add(cleaned);
        }
        if (analyses.isNotEmpty) {
          imageAnalysisText = analyses.join(' | ');
        }
      } catch (e) {
        debugPrint('Image analysis failed, falling back to hint: $e');
      }
    }
    if (_isSendCanceled(sendSerial, userMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }

    // Fire background Memex processing for images (fire-and-forget)
    if (hasImages) {
      unawaited(
        MemexRouter()
            .submitInput(text: textToSend, images: imagesToSend)
            .then<void>((_) {})
            .catchError((e) => debugPrint('Background submitInput failed: $e')),
      );
    }

    // Reading Companion: if the user's message contains a recognised
    // reading link (xiaohongshu / wechat / generic article), capture it as
    // a reading_item entity in the background. The companion will emit a
    // separate "鏀跺埌浜? message with a reading_card addendum on success.
    // Failures and non-reading messages are silent 鈥?most chat messages
    // aren't reading links.
    if (textToSend.trim().isNotEmpty && ReadingCaptureService.isInitialized) {
      unawaited(
        ReadingCaptureService.instance
            .captureFromUserMessage(
              text: textToSend,
              userMessageId: userMessageId,
              preferredCharacterId: sendCharacterId,
            )
            .then<void>((_) {})
            .catchError(
                (e) => debugPrint('Background reading capture failed: $e')),
      );
    }

    if (widget.enableRichCapture && !isExplicitMemoryRequest) {
      unawaited(_scheduleConversationCapture(
        characterId: sendCharacterId,
        trigger: 'user_message',
      ));
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

      // Build user message 鈥?inject image analysis when available.
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

      final toyControlService =
          await _ensureToyConnected(timeout: const Duration(seconds: 22));
      if (_isSendCanceled(sendSerial, userMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }

      await for (final chunk in CompanionAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: sendCharacterId,
        userMessage: chatMessage,
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
        await _chatService.addCharacterMessage(
          sendCharacterId,
          fullResponse,
          isRead: !_isAppInBackground,
          timestamp: DateTime.now(),
        );
        if (widget.enableRichCapture) {
          unawaited(_scheduleConversationCapture(
            characterId: sendCharacterId,
            force: isExplicitMemoryRequest,
            trigger: isExplicitMemoryRequest
                ? 'explicit_memory_fallback'
                : 'character_message',
          ));
        }
        responsePersisted = true;

        if (_isAppInBackground && sendCharacter != null) {
          final preview = fullResponse.length > 100
              ? '${fullResponse.substring(0, 100)}...'
              : fullResponse;
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
        final firstNewCharacterMessageId =
            personaChatFirstNewCharacterMessageId(
          previousMessages: messages,
          updatedMessages: updated,
        );
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
          if (firstNewCharacterMessageId != null) {
            _scrollToMessage(firstNewCharacterMessageId, alignment: 0.12);
          } else {
            _scrollToBottom();
          }
        } else {
          unawaited(_refreshMessagesFromStore(
            autoRead: _autoReadEnabled,
            scrollToBottom: false,
          ));
        }
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
        if (widget.enableRichCapture) {
          unawaited(_scheduleConversationCapture(
            characterId: sendCharacterId,
            force: isExplicitMemoryRequest,
            trigger: isExplicitMemoryRequest
                ? 'explicit_memory_fallback'
                : 'character_message',
          ));
        }
      }

      final updated = await _chatService.getMessages(
        sendCharacterId,
        limit: messages.length + 20,
      );
      if (mounted) {
        final isViewingSendCharacter = _currentCharacterId == sendCharacterId;
        final firstNewCharacterMessageId =
            personaChatFirstNewCharacterMessageId(
          previousMessages: messages,
          updatedMessages: updated,
        );
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
          if (firstNewCharacterMessageId != null) {
            _scrollToMessage(firstNewCharacterMessageId, alignment: 0.12);
          } else {
            _scrollToBottom();
          }
        } else if (partialResponse.isEmpty && isViewingSendCharacter) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to get response: $e')),
          );
        } else if (!isViewingSendCharacter) {
          unawaited(_refreshMessagesFromStore(
            autoRead: _autoReadEnabled,
            scrollToBottom: false,
          ));
        }
        _sendPendingMessage();
      }
    }
  }

  void _clearComposerText({String? staleText}) {
    final token = ++_composerClearToken;
    // Force the IME to finalize any composing region before we clear.
    // Without this, Chinese IMEs may commit composing text *after* we
    // read/clear the field, leaving residue that doesn't match staleText.
    _textController.clearComposing();
    _setComposerTextEmpty();

    // Aggressive clear: IMEs (especially Chinese) can restore composing
    // text across multiple frames with timing that varies by device and
    // keyboard. Rather than trying to match exact text (which fails when
    // the IME commits a different form than what we captured as staleText),
    // we simply nuke any text that reappears for a short window after send.
    void clearIfTextReappeared() {
      if (!mounted || token != _composerClearToken) return;
      if (_textController.text.isNotEmpty) {
        _textController.clearComposing();
        _setComposerTextEmpty();
      }
    }

    scheduleMicrotask(clearIfTextReappeared);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      clearIfTextReappeared();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => clearIfTextReappeared(),
      );
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 100))
          .then((_) => clearIfTextReappeared()),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 200))
          .then((_) => clearIfTextReappeared()),
    );
  }

  void _setComposerTextEmpty() {
    _textController.value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
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
      compressedAttachments = [];
      for (final image in images) {
        final compressed = await _compressImageForChat(image);
        if (compressed != null) {
          compressedAttachments.add(compressed);
        }
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
    unawaited(_sendMessage(
      forcedCharacterId: pending.characterId,
      forcedCharacter: pending.character,
      queuedMessage: pending,
    ));
  }

  Future<void> _scheduleConversationCapture({
    String? characterId,
    bool force = false,
    String trigger = 'message_threshold',
  }) async {
    if (!ConversationCaptureService.isInitialized) return;
    final userId = _userId ?? await UserStorage.getUserId();
    if (userId == null) return;
    await ConversationCaptureService.instance.noteConversationActivity(
      userId: userId,
      characterId: characterId ?? _currentCharacterId,
      force: force,
      trigger: trigger,
    );
  }

  bool _isExplicitMemoryRequest(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('记住') ||
        normalized.contains('记下来') ||
        normalized.contains('remember this') ||
        normalized.contains('remember that');
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
  /// Follows the pattern from [AssetAnalysisTool]: resize to max 2048px,
  /// WebP quality 85, then base64-encode. Returns null on failure.
  Future<Map<String, String>?> _compressImageForChat(XFile image) async {
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        image.path,
        minWidth: 2048,
        minHeight: 2048,
        quality: 85,
        format: CompressFormat.webp,
        autoCorrectionAngle: true,
        keepExif: false,
      );
      if (compressed == null) return null;
      // Use direct encode instead of compute() 鈥?avoid isolate issues on Android.
      final base64 = base64Encode(compressed);
      return {'mimeType': 'image/webp', 'base64': base64};
    } catch (e) {
      debugPrint('Failed to compress image for chat: $e');
      return null;
    }
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
    await _jumpToMessage(selected);
  }

  Future<void> _jumpToMessage(PersonaChatMessage message) async {
    final newerCount = await _chatService.countMessagesNewerThan(
      _currentCharacterId,
      message,
    );
    final neededDepth = newerCount + 1;
    final limit =
        neededDepth > _messages.length ? neededDepth : _messages.length;
    final messages = await _chatService.getMessages(
      _currentCharacterId,
      limit: limit,
    );
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() {
      _messages = messages;
      _hasMoreHistory = messages.length >= limit;
      _highlightedMessageId = message.id;
      _showJumpToLatest = true;
    });
    _scrollToMessage(message.id);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  void _scrollToMessage(int messageId, {double alignment = 0.45}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 24), () {
        if (!mounted) return;
        final messageContext = _messageKeys[messageId]?.currentContext;
        if (messageContext == null || !messageContext.mounted) return;
        unawaited(
          Scrollable.ensureVisible(
            messageContext,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: alignment,
          ),
        );
      });
    });
  }

  void _showCopiedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_chatUiText(zh: '已复制', en: 'Copied')),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 120,
      ),
    );
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
          content: Text(_chatUiText(
            zh: '杩欐潯娑堟伅宸茬粡涓嶈兘鎾ゅ洖',
            en: 'This message can no longer be recalled',
          )),
        ),
      );
      return;
    }

    _messageKeys.remove(message.id);
    await _refreshMessagesFromStore(
      autoRead: false,
      scrollToBottom: false,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_chatUiText(zh: '已撤回', en: 'Message recalled')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _switchCharacter() async {
    await _stopTtsPlayback();
    await _voiceController.cancel();

    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    final characters = await CharacterService.instance.getAllCharacters(userId);
    final enabled = characters.where((c) => c.enabled).toList();
    if (enabled.length <= 1 || !mounted) return;

    final selected = await _CharacterSwitcherSheet.show(
      context,
      characters: enabled,
      currentId: _currentCharacterId,
    );

    if (selected != null && selected.id != _currentCharacterId && mounted) {
      // NOTE: switching the active chat target must NOT change the primary
      // companion. The primary companion (who sends proactive check-in pushes)
      // is set explicitly via the dedicated action in the switcher sheet.
      // Switch to new character
      setState(() {
        _currentCharacterId = selected.id;
        _isLoading = true;
        _hasMoreHistory = true;
        _isLoadingMore = false;
        _lastAutoReadMessageId = null;
        _autoReadWatermarkAt = null;
        _autoReadWatermarkId = null;
        _voiceModeStartQueued = false;
        _isInlineVoiceMode = false;
      });
      await ActivePersonaChatService.instance.markActive(_currentCharacterId);
      await _init();
    }
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
    _advanceAutoReadWatermark(updatedMessages);
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoReadEnabled = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save auto read setting: $e')),
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
      _endVoiceModeAfterCurrentReply = false;
      _voiceModeSilentFollowUps = 0;
      await _voiceController.cancel();
      await _stopTtsPlayback();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('璇峰厛鍦ㄨ鑹茶缃腑閰嶇疆 TTS 璇煶 ID')),
        );
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
        _audioCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
          _handleTtsPlaybackCompleted(requestSerial, messageId);
        });
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
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
        _queueVoiceModeRecordingStart();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                Column(
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top),
                    _buildHeader(),
                    const ChatTaskCapsule(),
                    Expanded(child: _buildMessageList()),
                    if (widget.enableRichCapture)
                      CompanionMediaTray(
                        isOpen: _isMediaTrayOpen,
                        onImagesPicked: _onImagesPicked,
                      ),
                    _buildInputBar(),
                  ],
                ),
                if (_showJumpToLatest) _buildJumpToLatestButton(),
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

    final content = Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const _FrostedCircleButton(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _personaText,
                  size: 17,
                ),
              ),
            ),
          ],
          if (character != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _switchCharacter,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _personaAccent.withValues(alpha: 0.72),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.42),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CharacterAvatar(
                        avatar: character.avatar,
                        name: character.name,
                        size: 41,
                        backgroundColor: _personaPanelSoft,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        character.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: _personaText,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: _personaAccent,
                    ),
                  ],
                ),
              ),
            ),
            // Toy connection indicator
            if (_toyControlService != null || _toyConnecting) ...[
              const SizedBox(width: 6),
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

    return content;
  }

  Widget _buildHeaderActionsOverlay() {
    final top = MediaQuery.of(context).padding.top + 58;
    final actions = <Widget>[
      _HeaderActionButton(
        icon: Icons.search_rounded,
        label: _chatUiText(zh: '鎼滅储', en: 'Search'),
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

  Widget _buildJumpToLatestButton() {
    return Positioned(
      right: 18,
      bottom: MediaQuery.of(context).padding.bottom + 102,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        ),
        child: Tooltip(
          message: _chatUiText(zh: '回到最新消息', en: 'Back to latest'),
          child: GestureDetector(
            onTap: _scrollToBottom,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _personaPanel.withValues(alpha: 0.78),
                border: Border.all(
                  color: _personaAccent.withValues(alpha: 0.26),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.36),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _personaAccent,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    // Show typing indicator or streaming bubble at the end
    final showStreamingBubble =
        _isStreamingCurrentCharacter && _streamingText.isNotEmpty;
    final showTypingIndicator =
        _isStreamingCurrentCharacter && _streamingText.isEmpty;
    final extraItems = (showStreamingBubble || showTypingIndicator) ? 1 : 0;
    // Extra item at the tail (top of reversed list) for load-more indicator
    final loadMoreItem = (_hasMoreHistory || _isLoadingMore) ? 1 : 0;
    final itemCount = _messages.length + extraItems + loadMoreItem;

    if (_messages.isEmpty && extraItems == 0) return _buildEmptyState();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
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

        return KeyedSubtree(
          key: _messageKeys.putIfAbsent(msg.id, GlobalKey.new),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isHighlighted
                  ? _personaAccent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                if (showDate) _buildDateDivider(msg.timestamp),
                if (msg.messageType == 'action')
                  _buildActionMessage(text: msg.content)
                else if (msg.isFromCharacter)
                  _buildCharacterMessage(
                    msg,
                    isStreaming: false,
                  )
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
                style: const TextStyle(
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
            style: const TextStyle(fontSize: 11, color: _personaTextMuted),
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

    final daysAgo = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;

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
      return const Padding(
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
    // Invisible sentinel 鈥?the scroll listener handles triggering the load.
    return const SizedBox(height: 1);
  }

  /// Renders a narrative / action description message.
  /// No speech bubble 鈥?italic text centred with a subtle divider style,
  /// matching the roleplay convention for stage directions.
  Widget _buildActionMessage({required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Row(
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
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              child: SelectableText(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
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
  }) {
    if (isCharacter) {
      return _buildCharacterBubble(
        text: text,
        isStreaming: isStreaming,
        messageId: messageId,
        attachmentsJson: attachmentsJson,
      );
    }

    final attachmentWidgets =
        attachmentsJson != null && attachmentsJson.isNotEmpty
            ? _buildAttachmentWidgets(attachmentsJson)
            : <Widget>[];
    final userMessage = message;

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
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.88,
                ),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: BoxDecoration(
                  color: _personaUserBubble.withValues(alpha: 0.9),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(
                    color: _personaUserBorder.withValues(alpha: 0.82),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _personaUserBorder.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (text.isNotEmpty)
                      SelectionArea(
                        child: Text(
                          text,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: Color(0xFF2D2923),
                          ),
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
                            _showCopiedSnackBar();
                          },
                          child: const Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: Color(0xFF8A857C),
                          ),
                        ),
                        if (userMessage != null) ...[
                          const SizedBox(width: 12),
                          Semantics(
                            button: true,
                            label: 'Recall message',
                            child: GestureDetector(
                              onTap: () =>
                                  _confirmRetractUserMessage(userMessage),
                              child: const Icon(
                                Icons.undo_rounded,
                                size: 15,
                                color: Color(0xFF8A857C),
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
          SizedBox(
            width: 34,
            child: Align(
              alignment: Alignment.topRight,
              child: _UserAvatar(
                avatar: _userAvatar,
                name: _userId ?? '',
                size: 34,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingReply(String text) {
    return _buildCharacterMessageContent(
      text: text,
      isStreaming: true,
    );
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
    final segments = PersonaReplySanitizer.splitVisibleReply(text);
    if (segments.length <= 1 &&
        (segments.isEmpty ||
            segments.single.type == PersonaReplySegmentType.chat)) {
      return _buildBubble(
        text: segments.isEmpty ? text : segments.single.text,
        isCharacter: true,
        isStreaming: isStreaming,
        messageId: messageId,
        attachmentsJson: attachmentsJson,
      );
    }

    final children = <Widget>[];
    final chatTexts = <String>[];
    var chatBubbleIndex = 0;

    String? nextChatMessageId() {
      if (messageId == null) return null;
      if (segments.length <= 1) return messageId;
      return '$messageId:${chatBubbleIndex++}';
    }

    for (final segment in segments) {
      if (segment.type == PersonaReplySegmentType.action) {
        if (chatTexts.isNotEmpty) {
          children.add(_buildBubble(
            text: chatTexts.join('\n'),
            isCharacter: true,
            isStreaming: isStreaming,
            messageId: nextChatMessageId(),
            attachmentsJson: attachmentsJson,
          ));
          chatTexts.clear();
          attachmentsJson = null;
        }
        children.add(_buildActionMessage(text: segment.text));
      } else {
        chatTexts.add(segment.text);
      }
    }
    if (chatTexts.isNotEmpty) {
      children.add(_buildBubble(
        text: chatTexts.join('\n'),
        isCharacter: true,
        isStreaming: isStreaming,
        messageId: nextChatMessageId(),
        attachmentsJson: attachmentsJson,
      ));
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

  /// Renders image attachments from a JSON-encoded attachments list below
  /// the text in a user's chat bubble. Each attachment has `base64` (WebP)
  /// and `mimeType` fields.
  List<Widget> _buildAttachmentWidgets(String attachmentsJson) {
    try {
      final List<dynamic> attachments = jsonDecode(attachmentsJson);
      return attachments.map((att) {
        final base64 = att['base64'] as String;
        final bytes = base64Decode(base64);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        );
      }).toList();
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
  }) {
    final isPlaying = messageId != null && _playingMessageId == messageId;
    final showSpeaker = !isStreaming && messageId != null;
    final hasAddenda =
        attachmentsJson != null && attachmentsJson.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.topLeft,
              child: _FramedCharacterAvatar(
                avatar: _character?.avatar,
                name: _character?.name ?? '',
                size: 32,
              ),
            ),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.topLeft,
              child: _CharacterMessageFrame(
                child: SelectionArea(
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
                              styleSheet: _cachedMarkdownStyle,
                            ),
                          ),
                          if (isStreaming) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
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
                      if (showSpeaker) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _handleTtsPlay(messageId, text),
                              child: Icon(
                                isPlaying
                                    ? Icons.volume_up
                                    : Icons.volume_up_outlined,
                                size: 16,
                                color: isPlaying
                                    ? _personaAccent
                                    : _personaTextMuted,
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: text));
                                _showCopiedSnackBar();
                              },
                              child: const Icon(
                                Icons.copy_rounded,
                                size: 15,
                                color: _personaTextMuted,
                              ),
                            ),
                          ],
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: _personaCharacterBubble,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border.all(
                color: _personaLine.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: _personaLine.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const _TypingDots(),
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
      onVoiceModeTap: () => unawaited(
        _setInlineVoiceMode(!_isInlineVoiceMode),
      ),
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
      .where((message) =>
          message.isFromCharacter && !previousIds.contains(message.id))
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
      .where((message) =>
          !previousIds.contains(message.id) &&
          message.isFromCharacter &&
          message.messageType == 'chat' &&
          message.content.trim().isNotEmpty)
      .toList();
  candidates.sort((a, b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return candidates;
}

@visibleForTesting
String personaChatTtsPlaybackIdForMessage(PersonaChatMessage message) {
  final segments = PersonaReplySanitizer.splitVisibleReply(message.content);
  final hasSplitSpeech = segments.length > 1 &&
      segments.any((segment) => segment.type == PersonaReplySegmentType.chat);
  return hasSplitSpeech ? '${message.id}:0' : message.id.toString();
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
            decoration: const BoxDecoration(
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
                            style: const TextStyle(
                              color: _personaText,
                              fontSize: 15,
                              letterSpacing: 0,
                            ),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: _personaTextMuted,
                                size: 20,
                              ),
                              suffixIcon: _controller.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
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
                                zh: '鎼滅储鑱婂ぉ璁板綍',
                                en: 'Search chat history',
                              ),
                              hintStyle: const TextStyle(
                                color: _personaTextMuted,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          UserStorage.l10n.cancel,
                          style: const TextStyle(color: _personaAccent),
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
      return const Center(
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
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: _personaLine.withValues(alpha: 0.5),
      ),
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
                          style: const TextStyle(
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
                        style: const TextStyle(
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
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 17,
                  color: _personaTextMuted,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_chatUiText(zh: '已复制', en: 'Copied')),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      width: 120,
                    ),
                  );
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
  const _HighlightedSnippet({
    required this.text,
    required this.query,
  });

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
        style: const TextStyle(
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
            style: const TextStyle(
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
      style: const TextStyle(
        color: _personaTextMuted,
        fontSize: 13.5,
        height: 1.45,
        letterSpacing: 0,
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.icon,
    required this.label,
  });

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
            style: const TextStyle(
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

class _ChatAtmosphereBackground extends StatelessWidget {
  const _ChatAtmosphereBackground({required this.character});

  final CharacterModel? character;

  @override
  Widget build(BuildContext context) {
    final bgPath = character?.chatBackground;
    final hasCustomBg =
        bgPath != null && bgPath.isNotEmpty && File(bgPath).existsSync();

    return Stack(
      children: [
        if (hasCustomBg)
          Positioned.fill(
            child: Image.file(
              File(bgPath),
              fit: BoxFit.cover,
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF070A11),
                  Color(0xFF131923),
                  Color(0xFF060607),
                ],
                stops: [0, 0.54, 1],
              ),
            ),
          ),
        if (!hasCustomBg && character != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.22,
              child: Transform.scale(
                scale: 1.5,
                alignment: Alignment.centerRight,
                child: Align(
                  alignment: const Alignment(0.92, -0.16),
                  child: CharacterAvatar(
                    avatar: character!.avatar,
                    name: character!.name,
                    size: MediaQuery.sizeOf(context).shortestSide * 0.95,
                    backgroundColor: _personaPanelSoft,
                  ),
                ),
              ),
            ),
          ),
        if (!hasCustomBg)
          Positioned.fill(
            child: CustomPaint(
              painter: _ChatTexturePainter(),
            ),
          ),
        if (!hasCustomBg) ...[
          Positioned(
            top: -88,
            left: -72,
            child: _AtmosphereGlow(
              size: 240,
              color: const Color(0xFF40516A).withValues(alpha: 0.2),
            ),
          ),
          Positioned(
            top: 84,
            right: -96,
            child: _AtmosphereGlow(
              size: 280,
              color: _personaAccent.withValues(alpha: 0.08),
            ),
          ),
          Positioned(
            bottom: 76,
            left: -120,
            child: _AtmosphereGlow(
              size: 320,
              color: const Color(0xFF334154).withValues(alpha: 0.15),
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
                    const Color(0xFF080B12),
                    const Color(0xFF080B12).withValues(alpha: 0.92),
                    const Color(0xFF080B12).withValues(alpha: 0.55),
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
      ],
    );
  }
}

class _ChatTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var y = 48.0; y < size.height; y += 72) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + 18),
        linePaint,
      );
    }

    final dotPaint = Paint()
      ..color = _personaAccent.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    for (var y = 36.0; y < size.height; y += 56) {
      for (var x = 24.0; x < size.width; x += 64) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@visibleForTesting
class ConversationCaptureRememberedNotice extends StatelessWidget {
  const ConversationCaptureRememberedNotice({
    super.key,
    required this.onUndo,
  });

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Positioned(
      left: 24,
      right: 24,
      bottom: mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom + 96,
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
                color: _personaPanel.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _personaAccent.withValues(alpha: 0.22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _personaAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    UserStorage.l10n.companionRemembered,
                    style: const TextStyle(
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
                      style: const TextStyle(
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
  const _AtmosphereGlow({
    required this.size,
    required this.color,
  });

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
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
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
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.88,
      ),
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
      decoration: BoxDecoration(
        color: _personaCharacterBubble,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
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
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _personaPanel.withValues(alpha: 0.62),
        border: Border.all(color: _personaAccent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: IconTheme(
        data: const IconThemeData(color: _personaText),
        child: child,
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
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? _personaAccent.withValues(alpha: 0.18)
                : _personaPanel.withValues(alpha: 0.68),
            border: Border.all(
              color: active
                  ? _personaAccent.withValues(alpha: 0.5)
                  : _personaAccent.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? _personaAccent : _personaText,
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

@visibleForTesting
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasImages = selectedImages.isNotEmpty || isCompressing;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottomPadding + 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: _personaAccent.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, -2),
            ),
          ],
        ),
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
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              if (isCompressing &&
                                  index == selectedImages.length) {
                                return const SizedBox(
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
                                          color: Colors.black
                                              .withValues(alpha: 0.6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
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
                    if (onAddTap != null) ...[
                      _AddButton(
                        enabled: !isStreaming,
                        onTap: onAddTap!,
                        active: isAddActive,
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
                          hintStyle: const TextStyle(
                            color: _personaTextMuted,
                            fontSize: 15,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
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
                          : _ChatVoiceActions(
                              key: const ValueKey('voice-actions'),
                              voiceController: voiceController,
                              onVoiceTap: onVoiceTap,
                              onVoiceModeTap: onVoiceModeTap,
                              isVoiceModeActive: isVoiceModeActive,
                              voiceInputEnabled: isVoiceInputEnabled,
                              voiceModeEnabled:
                                  isVoiceModeActive || !isStreaming,
                            ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
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
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? _personaAccent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: active
                  ? _personaAccent.withValues(alpha: 0.52)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Icon(
            active ? Icons.close_rounded : Icons.add_rounded,
            color: enabled ? _personaAccent : _personaTextMuted,
            size: 24,
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
            iconColor: _personaAccent,
            bgColor: _personaPanelSoft,
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
        _VoiceModeButton(
          enabled: true,
          active: true,
          onTap: onVoiceModeTap!,
        ),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? _personaAccent.withValues(alpha: 0.16)
                : _personaPanelSoft,
            border: Border.all(
              color: active
                  ? _personaAccent.withValues(alpha: 0.42)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: active
              ? Icon(
                  Icons.close_rounded,
                  color: enabled ? _personaAccent : _personaTextMuted,
                  size: 23,
                )
              : _VoiceBarsIcon(
                  color: enabled ? _personaAccent : _personaTextMuted,
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
    const heights = [12.0, 20.0, 16.0, 23.0];
    return SizedBox(
      width: 22,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final height in heights) ...[
            Container(
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            if (height != heights.last) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onTap,
  });

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? _personaAccent.withValues(alpha: 0.78)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: enabled
                  ? _personaAccent.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _personaAccent.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.send_rounded,
            color: enabled ? const Color(0xFF5B5346) : _personaTextMuted,
            size: 22,
          ),
        ),
      ),
    );
  }
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
                  decoration: const BoxDecoration(
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

/// Bottom sheet for switching companion characters.
class _CharacterSwitcherSheet extends StatefulWidget {
  final List<CharacterModel> characters;
  final String? currentId;

  const _CharacterSwitcherSheet({
    required this.characters,
    this.currentId,
  });

  static Future<CharacterModel?> show(
    BuildContext context, {
    required List<CharacterModel> characters,
    String? currentId,
  }) {
    return showModalBottomSheet<CharacterModel>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CharacterSwitcherSheet(
        characters: characters,
        currentId: currentId,
      ),
    );
  }

  @override
  State<_CharacterSwitcherSheet> createState() =>
      _CharacterSwitcherSheetState();
}

class _CharacterSwitcherSheetState extends State<_CharacterSwitcherSheet> {
  late List<CharacterModel> _chars;

  @override
  void initState() {
    super.initState();
    _chars = List<CharacterModel>.from(widget.characters);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Container(
      decoration: BoxDecoration(
        color: _personaPanel.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.switchCompanion,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _personaText,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _chars.length,
                itemBuilder: (context, index) {
                  final char = _chars[index];
                  final isCurrent = char.id == widget.currentId;
                  return ListTile(
                    leading: CharacterAvatar(
                      avatar: char.avatar,
                      name: char.name,
                      size: 40,
                      backgroundColor: _personaAccent.withValues(alpha: 0.18),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            char.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  isCurrent ? FontWeight.w600 : FontWeight.w400,
                              color: _personaText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: char.tags.isNotEmpty
                        ? Text(
                            char.tags.join(' 路 '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _personaTextMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle,
                            color: _personaAccent, size: 20)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: isCurrent
                        ? () => Navigator.pop(context)
                        : () => Navigator.pop(context, char),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
