import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/settings/widgets/task_model_assignment_page.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:memex/agent/built_in_tools/asset_analysis_tool.dart';
import 'package:memex/agent/built_in_tools/continuous_reply_tool.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/agent/companion_agent/intimate_scene_planner.dart';
import 'package:memex/agent/companion_agent/intimate_scene_state.dart';
import 'package:memex/agent/companion_agent/sleep_companion_state.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/asr/alibaba_streaming_asr_client.dart';
import 'package:memex/data/services/asr/media_button_service.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/data/services/voice_call_audio_session.dart';
import 'package:memex/ui/character/widgets/hangup_tone.dart';
import 'package:memex/data/services/active_persona_chat_service.dart';
import 'package:memex/data/services/bad_case_collector.dart';
import 'package:memex/data/services/streaming_tts_player.dart';
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
import 'package:memex/data/services/intimacy_profile_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/persona_chat_open_service.dart';
import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/quick_chat_service.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/media_input_attachment.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_backfill_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/shared_draft_service.dart';
import 'package:memex/data/services/reading/reading_share_parser.dart';
import 'package:memex/data/services/reading/transient_fetch_cache.dart';
import 'package:memex/ui/character/widgets/addenda/message_addendum_renderer.dart';
import 'package:memex/ui/character/widgets/voice_input_button.dart';
import 'package:memex/ui/character/widgets/chat_task_capsule.dart';
import 'package:memex/ui/companion/widgets/companion_media_tray.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_tokens.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_color_controller.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/core/widgets/toast.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/ui/core/widgets/here_iam_rain_layer.dart';
import 'package:memex/ui/core/widgets/app_opening_splash.dart';
import 'package:memex/ui/memory/widgets/message_recall_trace_page.dart';
import 'package:memex/utils/tavern_macro.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

/// Resolves the persisted user message that initiated the selected turn.
///
/// User messages point to themselves. Character/action messages point to the
/// nearest older user message only when the time gap is small enough to be a
/// normal reply; this avoids attaching an unrelated proactive check-in to the
/// last conversation from hours earlier.
@visibleForTesting
int? personaChatRecallAnchorMessageId({
  required List<PersonaChatMessage> messagesNewestFirst,
  required int selectedMessageId,
  Duration maxReplyGap = const Duration(minutes: 15),
}) {
  final selectedIndex = messagesNewestFirst
      .indexWhere((message) => message.id == selectedMessageId);
  if (selectedIndex < 0) return null;
  final selected = messagesNewestFirst[selectedIndex];
  if (!selected.isFromCharacter) return selected.id;

  for (var i = selectedIndex + 1; i < messagesNewestFirst.length; i++) {
    final candidate = messagesNewestFirst[i];
    if (candidate.isFromCharacter) continue;
    final gap = selected.timestamp.difference(candidate.timestamp).abs();
    return gap <= maxReplyGap ? candidate.id : null;
  }
  return null;
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
  bool isSleepCoaxing = false,
}) {
  if (forceClose) {
    return '[The user has been silent for about 10 seconds again in chat voice '
        'mode. This is silent follow-up $followUpIndex. They may have fallen '
        'asleep. Say a very soft, brief goodnight or closing line, then call '
        '`end_voice_mode` in this same turn. Do not use markdown, action text, '
        'or parenthetical thoughts.]';
  }
  if (isSleepCoaxing) {
    return '[The user has been silent for about 10 seconds in chat voice mode. '
        'This is silent follow-up $followUpIndex. The user is in a sleep-coaxing '
        'context (they said they are going to sleep or are trying to fall '
        'asleep). Continue low-intensity companionship narration as if in an '
        'aftercare phase: soothing physical contact and gentle touch, soft '
        'low-voice words, and a lingering thread of intimacy / sexual '
        'continuation is welcome. Do NOT ask questions, do NOT rush them to '
        'sleep, do NOT wrap up, do NOT say "睡吧" or "晚安". Keep the narration '
        'flowing continuously — one or two short spoken sentences at a time, '
        'like someone lying beside them in the dark. Narrate from his actions '
        'and perceptions only (he touches, he murmurs, he holds); do NOT '
        'describe the user\'s state (do not write "你睡着了" / "你的呼吸变 '
        '平稳了" / "你闭上了眼睛") — their state is theirs to express. Vary '
        'your wording across follow-ups. Do not use markdown, action text, or '
        'parenthetical thoughts.]';
  }
  return '[The user has been silent for about 10 seconds in chat voice mode. '
      'This is silent follow-up $followUpIndex. The user is NOT trying to '
      'sleep — this is a normal voice conversation and they just went quiet. '
      'Do NOT repeat or rephrase what you said in your previous reply. '
      'Instead, react to the silence itself: you can ask if they are still '
      'there, if they are thinking about something, if they got distracted by '
      'something else, or say a brief "喂？" / "还在吗？" style check-in. '
      'Keep it to one or two short spoken sentences. Vary your wording across '
      'follow-ups. Do not use markdown, action text, or parenthetical '
      'thoughts.]';
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

@visibleForTesting
Widget personaChatStartupLoadingView({bool playVideo = true}) =>
    AppOpeningSplash(playVideo: playVideo);

@visibleForTesting
const personaChatMinimumStartupSplashDuration = Duration(milliseconds: 1800);

/// 1-on-1 chat screen with an AI companion character.
class PersonaChatScreen extends StatefulWidget {
  final String characterId;
  final bool embedded;
  final bool enableRichCapture;
  final bool initialVoiceMode;
  final VoidCallback? onOpenSpaces;
  final VoidCallback? onReady;

  const PersonaChatScreen({
    super.key,
    required this.characterId,
    this.embedded = false,
    this.enableRichCapture = false,
    this.initialVoiceMode = false,
    this.onOpenSpaces,
    this.onReady,
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

/// A single staged message in compose mode (multi-message batch send).
class _ComposeDraft {
  const _ComposeDraft({
    required this.text,
    required this.images,
    required this.timestamp,
  });

  final String text;
  final List<XFile> images;
  final DateTime timestamp;
}

/// A batch of drafts that will be sent to the LLM as a single turn.
///
/// Single-message sends wrap one draft in a batch so the queue and cancel
/// logic stays uniform. When [persistedMessageIds] is non-empty, the drafts
/// were already persisted as visible user messages (queue-while-streaming path)
/// and the send path must reuse those ids instead of re-persisting.
class _PendingBatch {
  _PendingBatch({
    required this.characterId,
    required this.character,
    required this.drafts,
    List<int>? persistedMessageIds,
    this.isContinuous = false,
    this.sceneDirective,
  }) : persistedMessageIds = persistedMessageIds ?? <int>[];

  final String characterId;
  final CharacterModel? character;
  final List<_ComposeDraft> drafts;
  final List<int> persistedMessageIds;

  /// True when this batch is a system-driven continuous-mode turn rather than
  /// something the user typed. Drives the continuous-mode system reminder and
  /// keeps the synthetic sentinel out of the visible message list.
  final bool isContinuous;

  /// Per-turn intimate-scene directive (current beat), injected into the
  /// model's context via `CompanionAgent.chat(sceneDirective:)`.
  final String? sceneDirective;
}

@visibleForTesting
bool personaChatPendingBatchWasAlreadyAnswered({
  required Iterable<int> pendingMessageIds,
  required Set<int> answeredMessageIds,
}) {
  final persistedIds = pendingMessageIds.where((id) => id > 0).toList();
  return persistedIds.isNotEmpty &&
      persistedIds.every(answeredMessageIds.contains);
}

@visibleForTesting
bool personaChatCanDispatchPendingBatch({
  required bool isStreaming,
  required bool isRoleVoiceActive,
}) {
  return !isStreaming && !isRoleVoiceActive;
}

/// Collects adjacent NLS sentences into one user turn.
///
/// NLS can emit `SentenceEnd` and then begin the next sentence almost
/// immediately. A new sentence suspends the pending flush but keeps the text
/// already collected; its eventual `SentenceEnd` appends to the same turn and
/// starts a fresh silence window.
@visibleForTesting
class PersonaChatSentenceDebouncer {
  PersonaChatSentenceDebouncer({required this.onFlush});

  final ValueChanged<String> onFlush;
  final StringBuffer _buffer = StringBuffer();
  Timer? _timer;

  void sentenceBegin() {
    _timer?.cancel();
    _timer = null;
  }

  void sentenceEnd(String text, {required Duration debounceWindow}) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (_buffer.isNotEmpty) _buffer.write(' ');
    _buffer.write(normalized);
    _timer?.cancel();
    _timer = Timer(debounceWindow, _flush);
  }

  void cancel() {
    sentenceBegin();
    _buffer.clear();
  }

  void _flush() {
    _timer = null;
    final text = _buffer.toString().trim();
    _buffer.clear();
    if (text.isNotEmpty) onFlush(text);
  }
}

class _VoiceModeOpening {
  const _VoiceModeOpening({required this.text, required this.playbackId});

  final String text;
  final String playbackId;
}

class _PersonaChatScreenState extends State<PersonaChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _composerFocus = FocusNode();
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
  bool _topicBackfillRunning = false;
  int? _lastBadCaseSaved;
  bool _isLoading = true;
  bool _readyNotificationScheduled = false;
  bool _didNotifyReady = false;
  bool _isStreaming = false;
  late final DateTime _startupSplashStartedAt = DateTime.now();
  String _streamingText = '';
  int _sendSerial = 0;
  int? _activeSendSerial;
  // All user message ids belonging to the active streaming batch. Single
  // message sends populate this with one id. Retracting any one cancels the
  // whole batch.
  final Set<int> _activeUserMessageIds = {};
  // A persisted user message may briefly remain in the pending queue after a
  // racing voice flush. Once a reply is saved for that id, never consume it as
  // a second LLM turn.
  final Set<int> _answeredUserMessageIds = {};
  String? _activeStreamingCharacterId;
  final Set<int> _canceledSendSerials = {};
  final Set<int> _retractedUserMessageIds = {};
  final Set<int> _recordingMessageIds = {};

  // Pending batch queue: user can compose the next message(s) while the
  // character is still generating a response. It auto-sends when streaming
  // ends. Single-message sends also use this queue (one draft per batch) so
  // the cancel/retract logic stays uniform.
  final List<_PendingBatch> _pendingBatches = [];

  // Continuous mode: schedules the next system-driven turn after a reply
  // finishes. Held so it can be canceled on stop / character switch / dispose.
  Timer? _continuousTimer;

  // Compose mode: user has long-pressed the send button and subsequent taps
  // stage drafts instead of sending immediately. Exits after a batch send.
  bool _isComposeMode = false;
  final List<_ComposeDraft> _composeBuffer = [];

  /// Long-press handler on the send button: toggles Compose mode. When active,
  /// subsequent taps stage the current input as a draft instead of sending.
  void _onSendLongPress() {
    if (_isStreaming) return;
    setState(() {
      _isComposeMode = !_isComposeMode;
      // Toggling off discards any staged drafts.
      if (!_isComposeMode) _composeBuffer.clear();
    });
  }

  /// Compose-mode send: stage the current input as a draft and clear the
  /// composer. No-ops when the input is empty.
  void _stageComposeDraft() {
    final text = _textController.text.trim();
    final images = List<XFile>.from(_selectedImages);
    if (text.isEmpty && images.isEmpty) return;
    setState(() {
      _composeBuffer.add(
        _ComposeDraft(text: text, images: images, timestamp: DateTime.now()),
      );
      _clearComposerText(staleText: text);
      _clearImages();
    });
  }

  /// Removes a staged draft by index and returns its text to the composer so
  /// the user can edit and re-stage it.
  void _editComposeDraft(int index) {
    if (index < 0 || index >= _composeBuffer.length) return;
    final draft = _composeBuffer.removeAt(index);
    setState(() {
      _textController.text = draft.text;
      _selectedImages
        ..clear()
        ..addAll(draft.images);
    });
  }

  void _removeComposeDraft(int index) {
    if (index < 0 || index >= _composeBuffer.length) return;
    setState(() => _composeBuffer.removeAt(index));
  }

  /// Sends the staged compose buffer as a single batch. Each draft is
  /// persisted as its own user message, then all drafts are merged into one
  /// LLM call so the character replies once to the whole batch.
  Future<void> _sendComposeBuffer() async {
    if (_composeBuffer.isEmpty) {
      // Empty buffer: exit compose mode without sending.
      setState(() => _isComposeMode = false);
      return;
    }

    final drafts = List<_ComposeDraft>.from(_composeBuffer);
    _composeBuffer.clear();
    setState(() => _isComposeMode = false);

    final sendCharacterId = _currentCharacterId;
    final sendCharacter = _character;

    // While the character is still streaming, queue the batch; it will be sent
    // automatically when the current response finishes. The drafts are staged
    // but not yet persisted — persistence happens when the batch actually
    // fires, so a retracted batch leaves no orphan user messages.
    if (_isStreaming) {
      _pendingBatches.add(
        _PendingBatch(
          characterId: sendCharacterId,
          character: sendCharacter,
          drafts: drafts,
        ),
      );
      return;
    }

    // If a draft has images, compress them before persisting so chat bubbles
    // and DB store the compressed form. Group drafts that need compression.
    final compressedPerDraft = <int, List<Map<String, String>>>{};
    setState(() => _isCompressingImages = true);
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      if (draft.images.isEmpty) continue;
      final compressed = <Map<String, String>>[];
      for (final image in draft.images) {
        compressed.add(await _compressImageForChat(image));
      }
      compressedPerDraft[i] = compressed;
    }
    if (mounted) setState(() => _isCompressingImages = false);

    // Persist each draft as its own visible user message.
    final persistedIds = <int>[];
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      final id = await _chatService.addUserMessage(
        sendCharacterId,
        draft.text,
        timestamp: draft.timestamp,
        attachments: compressedPerDraft[i],
        appendTimeline: false,
      );
      persistedIds.add(id);
    }

    final batch = _PendingBatch(
      characterId: sendCharacterId,
      character: sendCharacter,
      drafts: drafts,
      persistedMessageIds: persistedIds,
    );
    final primaryMessageId = persistedIds.isNotEmpty
        ? persistedIds.first
        : -(DateTime.now().millisecondsSinceEpoch);
    await _runBatchSend(batch, primaryMessageId: primaryMessageId);
  }

  bool _isMediaTrayOpen = false;

  // Image attachment state, moved up from CompanionMediaTray.
  final _selectedImages = <XFile>[];
  bool _isCompressingImages = false;

  // TTS playback state
  final _audioPlayer = AudioPlayer();

  /// TTS AudioContext for voice-call mode: routes the speaker through the
  /// voice-communication stream so the platform AEC receives the TTS output
  /// as its reference signal and cancels it from the mic feed. Without this,
  /// the mic picks up the speaker and ASR transcribes the character's own
  /// voice as user input (echo loop).
  static final AudioContext _voiceCallTtsContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: true,
      audioMode: AndroidAudioMode.inCommunication,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.voiceCommunication,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
  );

  /// Default TTS AudioContext (normal media playback, restored on voice-mode exit).
  static final AudioContext _defaultTtsContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.assistant,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
    ),
  );

  bool _ttsAudioContextApplied = false;
  final Object _mediaButtonOwner = Object();
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<PlayerState>? _audioStateSub;
  StreamSubscription<PersonaChatOpenRequest>? _openRequestSub;
  StreamSubscription<SharedDraft>? _sharedDraftSub;
  Timer? _messageRefreshTimer;

  /// Throttled Dev Room active-runs poll, driven from the 2s message
  /// refresh timer so chat stays appraised of run progress without users
  /// ever having to open the Dev Room screen.
  Timer? _devRunPollTimer;
  DateTime? _lastDevRunPollAt;
  Timer? _rememberedNoticeTimer;
  OverlayEntry? _rememberedNoticeEntry;
  String? _playingMessageId;
  String? _lastAutoReadMessageId;
  DateTime? _autoReadWatermarkAt;
  int? _autoReadWatermarkId;
  bool _isTtsLoading = false;
  bool _autoReadEnabled = false;

  /// Which TTS provider the auto-read button activates. 'elevenlabs' or
  /// 'minimax'. Controlled by the two auto-read buttons in the header; manual
  /// play and inline voice mode both follow this.
  String _activeTtsProvider = 'minimax';
  bool _isInlineVoiceMode = false;
  bool _isVoiceModeMicMuted = false;
  int _voiceModeMicSerial = 0;
  bool _voiceModeStartQueued = false;
  bool _voiceModeOpeningInProgress = false;
  bool _endVoiceModeAfterCurrentReply = false;
  int _voiceModeSilentFollowUps = 0;
  int _voiceModeOpeningSerial = 0;
  int _voiceModeIdleFollowUpSerial = 0;
  int _ttsRequestSerial = 0;
  StreamingTtsSession? _streamingTtsSession;
  late final PersonaChatSentenceDebouncer _sentenceDebouncer =
      PersonaChatSentenceDebouncer(onFlush: _flushSentenceDebounce);
  static const _sentenceDebounceWindow = Duration(milliseconds: 2000);
  // Longer window after a barge-in so the user has time to finish a multi-
  // sentence correction ("不对，我说的是… 其实是…") before we flush.
  static const _bargeInDebounceWindow = Duration(milliseconds: 2500);
  // Set true on barge-in; reverts to normal after the first flush.
  bool _inBargeInFollowUp = false;

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
  OverlayEntry? _bubblePopupOverlay;
  String? _popupMessageId;

  String? _retractToastText;
  String? _retractToastActionLabel;
  VoidCallback? _retractToastAction;
  Timer? _retractToastTimer;

  ToyController? _toyControlService;
  bool _toyConnected = false;
  bool _toyConnecting = false;

  // Pagination state: WeChat/WhatsApp style, load older messages on scroll-up.
  static const int _pageSize = 30;
  static const Duration _recallGracePeriod = Duration(milliseconds: 900);
  static const Duration _batchRecallGracePeriod = Duration(milliseconds: 1200);
  bool _hasMoreHistory = true;
  bool _isLoadingMore = false;
  // True while showing a history window jumped-to from search. Suppresses the
  // periodic refresh timer (which reloads the latest page and would yank the
  // scroll position away from the searched message).
  bool _viewingHistoryWindow = false;

  MarkdownStyleSheet get _messageMarkdownStyle {
    const c = SpringRainChatTokens.springRainDaydream;
    final codeBackground =
        c.brightness == Brightness.dark ? c.backgroundSoft : c.glassFillSoft;
    final baseText = TextStyle(
      fontSize: c.iSize,
      height: c.lineHeight,
      color: c.iColor,
      fontFamily: c.fontFamily,
    );
    final bold = baseText.copyWith(fontWeight: FontWeight.w700);
    final italic = baseText.copyWith(fontStyle: FontStyle.italic);

    return MarkdownStyleSheet(
      p: baseText.copyWith(fontWeight: c.iWeight),
      h1: bold.copyWith(fontSize: c.iSize + 8, height: c.lineHeight),
      h2: bold.copyWith(fontSize: c.iSize + 6, height: c.lineHeight),
      h3: bold.copyWith(fontSize: c.iSize + 4, height: c.lineHeight),
      h4: bold.copyWith(fontSize: c.iSize + 2, height: c.lineHeight),
      h5: bold.copyWith(fontSize: c.iSize + 1, height: c.lineHeight),
      h6: bold.copyWith(fontSize: c.iSize, height: c.lineHeight),
      strong: bold,
      em: italic,
      del: baseText.copyWith(
        decoration: TextDecoration.lineThrough,
        decorationColor: c.iColor.withValues(alpha: 0.6),
      ),
      blockSpacing: 8,
      blockquote: baseText.copyWith(
        fontStyle: FontStyle.italic,
        color: c.iColor.withValues(alpha: 0.86),
      ),
      blockquoteDecoration: BoxDecoration(
        color: c.iColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: c.actionColor.withValues(alpha: c.iAnchorAlpha),
            width: 2,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.all(8),
      listBullet: TextStyle(color: c.actionColor),
      listBulletPadding: const EdgeInsets.only(right: 6),
      checkbox: baseText.copyWith(
        color: c.actionColor,
        fontWeight: FontWeight.w600,
      ),
      tableHead: bold.copyWith(fontSize: c.iSize - 1),
      tableBody: baseText.copyWith(fontSize: c.iSize - 1),
      tablePadding: const EdgeInsets.only(bottom: 4),
      tableCellsPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      tableBorder: TableBorder.all(
        color: c.iColor.withValues(alpha: 0.18),
        width: 1,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      a: TextStyle(
        color: c.actionColor,
        decoration: TextDecoration.underline,
        decorationColor: c.actionColor.withValues(alpha: 0.55),
      ),
      code: TextStyle(
        fontSize: 13,
        color: c.iColor,
        backgroundColor: codeBackground,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: c.iColor.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
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
      if (_isInlineVoiceMode &&
          !_isVoiceModeMicMuted &&
          !_voiceController.isStreaming) {
        _queueVoiceModeStreamingStart();
      }
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
    _voiceController.onStreamingEvent = _onStreamingAsrEvent;
    _voiceController.onBargeInDetected = _onBargeInDetected;
    _voiceController.onStreamingSessionLost = _onStreamingSessionLost;
    _voiceController.onPressToTalkAutoComplete = _onPressToTalkAutoComplete;
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
    // Pick up any message queued from the floating ball quick-chat sheet.
    final pendingMsg = QuickChatService.take(_currentCharacterId);
    if (pendingMsg != null && pendingMsg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_sendMessage(syntheticInput: pendingMsg));
        }
      });
    }
    _sharedDraftSub = SharedDraftService.instance.stream.listen((draft) {
      if (!mounted) return;
      if (draft.text != null && draft.text!.isNotEmpty) {
        _textController.text = draft.text!;
      }
      if (draft.images.isNotEmpty) {
        _onImagesPicked(draft.images);
      }
    });
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
    if (_isInlineVoiceMode) {
      await _toggleVoiceModeMicrophone();
      return;
    }
    if (_isInlineVoiceMode && _isStreaming && !_voiceController.isRecording) {
      return;
    }
    if (_isInlineVoiceMode &&
        _isRoleVoiceActive &&
        !_voiceController.isRecording) {
      // About to start recording (interrupt TTS path).
      unawaited(playRecordStartTone());
      await _interruptRoleVoiceAndStartRecording();
      return;
    }

    // ── Normal chat: press-to-talk via streaming ASR ──────────────────────
    if (!_isInlineVoiceMode) {
      if (_voiceController.isPressToTalk) {
        // Second press: stop and send.
        unawaited(playRecordStopTone());
        final result = await _voiceController.stopPressToTalk();
        if (!mounted) return;
        if (result != null && result.isNotEmpty) {
          _textController.text = result;
          await _sendMessage();
        } else if (_voiceController.lastError != null) {
          _showVoiceInputError(_voiceController.lastError!);
        }
      } else if (_voiceController.state == VoiceInputState.idle) {
        // First press: start streaming recording.
        unawaited(playRecordStartTone());
        await _voiceController.startPressToTalk();
        if (!mounted) return;
        if (_voiceController.lastError != null &&
            !_voiceController.isPressToTalk) {
          _showVoiceInputError(_voiceController.lastError!);
        }
      }
      return;
    }

    // ── Inline voice mode: file-mode fallback (autoStop endpoint) ─────────
    // Play start cue before the toggle so the user gets immediate feedback.
    // Stop cue plays AFTER toggle returns so it isn't captured in the recording.
    final aboutToStart = _voiceController.state == VoiceInputState.idle;
    if (aboutToStart) {
      unawaited(playRecordStartTone());
    }

    final result = await _voiceController.toggle(
      autoStop: true,
      initialSilenceTimeout: _voiceModeIdleFollowUpSilenceTimeout,
      maxRecordingDuration: _voiceModeMaxRecordingDuration,
    );

    if (!aboutToStart) {
      unawaited(playRecordStopTone());
    }
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

  Future<void> _toggleVoiceModeMicrophone() async {
    if (!mounted || !_isInlineVoiceMode) return;
    final micSerial = ++_voiceModeMicSerial;
    final mute = !_isVoiceModeMicMuted;
    setState(() => _isVoiceModeMicMuted = mute);

    if (mute) {
      _voiceModeStartQueued = false;
      _sentenceDebouncer.cancel();
      _inBargeInFollowUp = false;
      if (_voiceController.isStreaming) {
        await _voiceController.cancelStreaming();
      } else {
        await _voiceController.cancel();
      }
      return;
    }

    if (micSerial == _voiceModeMicSerial) {
      _queueVoiceModeStreamingStart(delay: const Duration(milliseconds: 120));
    }
  }

  Future<void> _interruptRoleVoiceAndStartRecording() async {
    await _stopTtsPlayback();
    if (!mounted || !_isInlineVoiceMode || _isVoiceModeMicMuted) return;
    if (_voiceController.isStreaming) {
      // Mic is already open in streaming mode; barge-in is just TTS stop.
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
    if (!mounted || !_isInlineVoiceMode || _isVoiceModeMicMuted) return;
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

  /// Streaming ASR event handler (voice mode only).
  ///
  /// In VoIP call mode the platform AEC cancels speaker echo, so the NLS
  /// server-side VAD fires [SentenceEndEvent] only when the *user* actually
  /// speaks — even while TTS is playing. That event drives barge-in: stop
  /// TTS and dispatch the text.
  ///
  /// - [SentenceEndEvent]: if TTS is playing, stop it (barge-in) then accumulate
  ///   text in a debounce buffer. If no new sentence arrives within
  ///   [_sentenceDebounceWindow] (2.0s), dispatch the combined text to the LLM.
  /// - [SentenceBeginEvent]: suspend any pending flush while preserving the
  ///   previous sentence, so a continuation already in progress stays in the
  ///   same user turn.
  /// - [TranscriptionResultChangedEvent]: no-op.
  void _onStreamingAsrEvent(StreamingAsrEvent event) {
    if (!mounted || !_isInlineVoiceMode || _isVoiceModeMicMuted) return;
    switch (event) {
      case SentenceBeginEvent():
        _sentenceDebouncer.sentenceBegin();
        break;
      case SentenceEndEvent():
        final text = event.text.trim();
        if (text.isEmpty) break;
        if (_isRoleVoiceActive) {
          // User spoke during TTS → barge-in. Stop TTS so the user is heard.
          // With TTS routed through voiceCommunication, the platform AEC
          // cancels speaker echo so this only fires on real user speech. Use a
          // longer debounce window so multi-sentence corrections
          // ("不对，我说的是… 其实是…") merge into one message instead of
          // being dispatched as separate turns.
          debugPrint('Barge-in via NLS SentenceEnd during TTS: "$text"');
          unawaited(_stopTtsPlayback());
          _inBargeInFollowUp = true;
        }
        _sentenceDebouncer.sentenceEnd(
          text,
          debounceWindow: _inBargeInFollowUp
              ? _bargeInDebounceWindow
              : _sentenceDebounceWindow,
        );
        break;
      case TranscriptionResultChangedEvent():
        break;
    }
  }

  void _flushSentenceDebounce(String text) {
    _inBargeInFollowUp = false;
    if (!mounted || !_isInlineVoiceMode || _isVoiceModeMicMuted) return;
    _voiceModeSilentFollowUps = 0;
    _textController.text = text;
    unawaited(_sendMessage());
  }

  void _onBargeInDetected() {
    if (!mounted || !_isInlineVoiceMode || _isVoiceModeMicMuted) return;
    debugPrint('Barge-in: amplitude threshold exceeded, stopping TTS');
    // Mark barge-in follow-up so subsequent NLS SentenceEnd events use the
    // longer debounce window. The amplitude detector fires before the NLS
    // server has processed the audio and emitted SentenceEnd, so without this
    // flag the SentenceEnd would arrive after TTS stopped (_isRoleVoiceActive
    // already false) and take the normal 2.0s path instead of the 2.5s
    // barge-in window — splitting multi-sentence speech into separate messages.
    _inBargeInFollowUp = true;
    unawaited(_stopTtsPlayback());
  }

  /// The NLS streaming session died unexpectedly (server closed the WebSocket,
  /// idle timeout, etc.) while the user is still in voice mode. Re-arm the mic
  /// so the next turn can be recognized. Skipped while TTS is playing or a send
  /// is in flight — those paths re-arm the mic themselves when they finish.
  void _onStreamingSessionLost() {
    if (!mounted || !_isInlineVoiceMode || _isVoiceModeMicMuted) return;
    if (_isRoleVoiceActive || _isStreaming || _isAppInBackground) return;
    debugPrint('Streaming ASR session lost; re-arming mic');
    _queueVoiceModeStreamingStart(delay: const Duration(milliseconds: 400));
  }

  /// Press-to-talk watchdog auto-stopped (max duration reached). Send the
  /// accumulated text as a message, same as if the user pressed the button.
  Future<void> _onPressToTalkAutoComplete(String? text) async {
    if (!mounted) return;
    unawaited(playRecordStopTone());
    if (text != null && text.isNotEmpty) {
      _textController.text = text;
      await _sendMessage();
    }
  }

  Future<void> _runVoiceModeIdleFollowUp() async {
    if (!mounted ||
        !_isInlineVoiceMode ||
        _isVoiceModeMicMuted ||
        _isAppInBackground) {
      return;
    }
    if (_isStreaming || _isRoleVoiceActive) {
      _queueVoiceModeStreamingStart(delay: const Duration(milliseconds: 600));
      return;
    }

    final followUpIndex = ++_voiceModeSilentFollowUps;
    final forceClose = personaChatVoiceIdleFollowUpShouldForceClose(
      followUpIndex,
    );
    bool isSleepCoaxing = false;
    if (AppDatabase.isInitialized) {
      final sleepState = await SleepCompanionStateManager.load(
        AppDatabase.instance,
        _currentCharacterId,
      );
      isSleepCoaxing = sleepState != null;
    }
    final serial = ++_voiceModeIdleFollowUpSerial;
    final text = await _generateVoiceModeIdleFollowUp(
      serial: serial,
      followUpIndex: followUpIndex,
      forceClose: forceClose,
      isSleepCoaxing: isSleepCoaxing,
    );

    if (!mounted ||
        !_isInlineVoiceMode ||
        _isVoiceModeMicMuted ||
        serial != _voiceModeIdleFollowUpSerial) {
      return;
    }

    final spoken = text?.trim();
    if (spoken == null || spoken.isEmpty) {
      _queueVoiceModeStreamingStart(delay: const Duration(milliseconds: 600));
      return;
    }

    if (forceClose) {
      _endVoiceModeAfterCurrentReply = true;
    }
    final followUp = await _persistVoiceModeOpening(spoken);
    if (!mounted ||
        !_isInlineVoiceMode ||
        _isVoiceModeMicMuted ||
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

  void _queueVoiceModeStreamingStart({Duration delay = Duration.zero}) {
    if (_voiceModeStartQueued) return;
    _voiceModeStartQueued = true;
    unawaited(
      Future<void>.delayed(delay).then((_) {
        _voiceModeStartQueued = false;
        unawaited(_startVoiceModeStreamingIfReady());
      }),
    );
  }

  Future<void> _startVoiceModeStreamingIfReady() async {
    if (!mounted ||
        !_isInlineVoiceMode ||
        _isVoiceModeMicMuted ||
        _isAppInBackground ||
        _isVoiceReplyActive ||
        _voiceController.isStreaming ||
        _voiceController.isRecording) {
      return;
    }
    final micSerial = _voiceModeMicSerial;
    await _voiceController.startStreaming();
    if (!mounted) return;
    if (_isVoiceModeMicMuted || micSerial != _voiceModeMicSerial) {
      await _voiceController.cancelStreaming();
      return;
    }
    final error = _voiceController.lastError;
    if (error != null && error.isNotEmpty) {
      _showVoiceInputError(error);
    }
  }

  void _queueVoiceModeOpening() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startVoiceModeWithRoleOpening());
    });
  }

  Future<void> _startVoiceModeRecordingIfReady() async {
    if (!mounted ||
        !_isInlineVoiceMode ||
        _isVoiceModeMicMuted ||
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
    if (_voiceController.isStreaming) {
      await _voiceController.cancelStreaming();
    } else {
      await _voiceController.cancel();
    }
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
          !_voiceController.isStreaming &&
          !_voiceController.isRecording &&
          !_isVoiceModeMicMuted) {
        _queueVoiceModeStreamingStart();
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
    bool isSleepCoaxing = false,
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
          isSleepCoaxing: isSleepCoaxing,
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
      if (forceClose) return '我先不吵你了，闭上眼睛好好睡。晚安。';
      return isSleepCoaxing ? '我在呢，不用说话，闭上眼睛就好。' : '喂？还在吗？';
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
    if (forceClose) return '我先不吵你了，闭上眼睛好好睡。晚安。';
    return isSleepCoaxing ? '我在呢，不用说话，闭上眼睛就好。' : '喂？还在吗？';
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

  Future<void> _waitForMinimumStartupSplash() async {
    final elapsed = DateTime.now().difference(_startupSplashStartedAt);
    final remaining = personaChatMinimumStartupSplashDuration - elapsed;
    if (remaining.inMilliseconds > 0) {
      await Future<void>.delayed(remaining);
    }
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
    final activeProvider = await UserStorage.getTtsProvider();

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
      await _waitForMinimumStartupSplash();
      if (mounted) {
        _advanceAutoReadWatermark(updatedMessages);
        setState(() {
          _character = character;
          _userId = userId;
          _userAvatar = userAvatar;
          _messages = updatedMessages;
          _autoReadEnabled = autoReadEnabled;
          _activeTtsProvider = activeProvider;
          _hasMoreHistory = updatedMessages.length >= _pageSize;
          _isLoading = false;
        });
        _scrollToBottom();
      }
      return;
    }

    await _waitForMinimumStartupSplash();
    if (mounted) {
      _advanceAutoReadWatermark(messages);
      setState(() {
        _character = character;
        _userId = userId;
        _userAvatar = userAvatar;
        _messages = messages;
        _autoReadEnabled = autoReadEnabled;
        _activeTtsProvider = activeProvider;
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

  void _scheduleReadyNotification() {
    final onReady = widget.onReady;
    if (_isLoading ||
        onReady == null ||
        _readyNotificationScheduled ||
        _didNotifyReady) {
      return;
    }
    _readyNotificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readyNotificationScheduled = false;
      if (!mounted || _isLoading || _didNotifyReady) return;
      _didNotifyReady = true;
      onReady();
    });
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
    _dismissBubblePopup();
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
    _composerFocus.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _sentenceDebouncer.cancel();
    _retractToastTimer?.cancel();
    _audioCompleteSub?.cancel();
    _audioStateSub?.cancel();
    _openRequestSub?.cancel();
    _sharedDraftSub?.cancel();
    _streamingTtsSession?.cancel();
    _messageRefreshTimer?.cancel();
    _devRunPollTimer?.cancel();
    _continuousTimer?.cancel();
    ContinuousModeState.instance.cancel();
    IntimateSceneState.instance.end();
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
    if (_popupMessageId != null) _dismissBubblePopup();
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
      // Drive Dev Room active-run polling from the same cadence, but
      // throttle to once every 5 seconds (≤_devRunPollMinInterval) so we
      // don't hammer the Bridge while the user is just chatting. This is
      // what lets dev session progress flow into chat directly without the
      // user ever opening Dev Room.
      unawaited(_maybePollDevAgentRuns());
    });
  }

  static const _devRunPollMinInterval = Duration(seconds: 5);

  Future<void> _maybePollDevAgentRuns() async {
    if (!DevAgentBridgeService.isInitialized) return;
    final now = DateTime.now();
    final last = _lastDevRunPollAt;
    if (last != null && now.difference(last) < _devRunPollMinInterval) return;
    _lastDevRunPollAt = now;
    try {
      await DevAgentBridgeService.instance.refreshActiveRuns();
    } catch (_) {
      // Bridge unreachable / not configured — silently swallow; the Dev
      // Room screen surfaces the same errors where they're actionable.
    }
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
    bool isContinuous = false,
    String? sceneDirective,
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
    final userMessageTime = queuedMessage?.timestamp ?? DateTime.now();

    // 亲密场景开场：确定性触发词 → 规划器产出节拍 → 启动连续 run。
    // 必须是真实用户消息（非 synthetic/队列），且当前没有同角色场景在进行。
    if (!isSynthetic &&
        !isQueuedMessage &&
        !IntimateSceneState.instance.isActiveFor(sendCharacterId) &&
        IntimateScenePhrases.matchesStart(text)) {
      await _startIntimateScene(
        characterId: sendCharacterId,
        character: sendCharacter,
        userText: text,
        userMessageTime: userMessageTime,
      );
      return;
    }

    // 场景进行中：真实用户消息是故事材料（不接管）。高潮信号 → 转 aftercare。
    if (!isSynthetic &&
        !isQueuedMessage &&
        IntimateSceneState.instance.isActiveFor(sendCharacterId) &&
        IntimateScenePhrases.matchesOrgasm(text)) {
      IntimateSceneState.instance.enterAftercare();
      // 延长 run，让 aftercare 持续到她说停或睡着。
      ContinuousModeState.instance
          .startRun(characterId: sendCharacterId, count: 25);
      if (mounted) setState(() {});
    }

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
        _pendingBatches.add(
          _PendingBatch(
            characterId: sendCharacterId,
            character: sendCharacter,
            drafts: [
              _ComposeDraft(
                text: queued.text,
                images: List<XFile>.from(queued.images),
                timestamp: queued.timestamp,
              ),
            ],
            persistedMessageIds: [queued.messageId],
          ),
        );
      }
      return;
    }
    // Synchronous send lock: claim _isStreaming BEFORE the await chain below
    // (_stopTtsPlayback / image compression / addUserMessage) yields the event
    // loop. Without this, a second voice flush arriving during that window sees
    // _isStreaming==false and dispatches a concurrent reply turn → out-of-order
    // / duplicate replies and a clobbered _activeSendSerial/_streamingText.
    // Released by _runBatchSend's existing exit paths, with a catch backstop.
    _isStreaming = true;
    _streamingText = '';

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

    try {
      await _stopTtsPlayback();

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
      final batch = _PendingBatch(
        characterId: sendCharacterId,
        character: sendCharacter,
        drafts: [
          _ComposeDraft(
            text: textToSend,
            images: imagesToSend,
            timestamp: userMessageTime,
          ),
        ],
        persistedMessageIds: isSynthetic ? const [] : [userMessageId],
        isContinuous: isContinuous,
        sceneDirective: sceneDirective,
      );

      await _runBatchSend(batch, primaryMessageId: userMessageId);
    } catch (_) {
      // Backstop: release the synchronous lock if anything before/inside
      // _runBatchSend throws before its own exit paths reset _isStreaming, so a
      // later send can't deadlock. Normal completion never reaches here
      // (_runBatchSend swallows its own errors), so a chained _sendBatch's claim
      // is never clobbered.
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _streamingText = '';
        });
      } else {
        _isStreaming = false;
        _streamingText = '';
      }
      rethrow;
    }
  }

  /// Executes a [batch] as a single LLM turn. When the batch has more than one
  /// draft, the drafts are concatenated with per-message time prefixes and
  /// sent as one user message so the character replies once to the whole batch.
  ///
  /// [primaryMessageId] is the id used for cancel tracking. For multi-draft
  /// batches the full set is tracked in [_activeUserMessageIds] so retracting
  /// any of them cancels the whole batch.
  Future<void> _runBatchSend(
    _PendingBatch batch, {
    required int primaryMessageId,
  }) async {
    final sendCharacterId = batch.characterId;
    final sendCharacter = batch.character;
    final drafts = batch.drafts;
    final isMulti = drafts.length > 1;

    // A real user turn (not a system-driven continuous turn) ends any active
    // continuous run — the user has taken over the conversation. Exception:
    // mid-scene the user's messages are story material, not takeovers.
    if (!batch.isContinuous &&
        !IntimateSceneState.instance.isActiveFor(sendCharacterId)) {
      _continuousTimer?.cancel();
      ContinuousModeState.instance.stopRun();
    }

    final sendSerial = ++_sendSerial;
    _activeSendSerial = sendSerial;
    _activeUserMessageIds
      ..clear()
      ..addAll(batch.persistedMessageIds);
    if (_activeUserMessageIds.isEmpty) {
      _activeUserMessageIds.add(primaryMessageId);
    }
    _activeStreamingCharacterId = sendCharacterId;

    final addedCount = batch.persistedMessageIds.isNotEmpty
        ? batch.persistedMessageIds.length
        : 1;

    final messages = await _chatService.getMessages(
      sendCharacterId,
      limit: _messages.length + addedCount,
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

    final gracePeriod = isMulti ? _batchRecallGracePeriod : _recallGracePeriod;
    await Future<void>.delayed(gracePeriod);
    if (_isSendCanceled(sendSerial, primaryMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }
    for (final id in batch.persistedMessageIds) {
      await _chatService.appendUserMessageTimeline(sendCharacterId, id);
    }
    if (_isSendCanceled(sendSerial, primaryMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }

    // Image analysis per draft via the analyze_assets agent's separately
    // configured model. Each draft's analysis is both injected into the merged
    // LLM input and persisted back to that draft's attachments so Record
    // Organizer can reuse it without re-running the vision model.
    final perDraftAnalysis = <String?>[];
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      String? analysisText;
      if (draft.images.isNotEmpty) {
        try {
          final analysisResources = await UserStorage.getAgentLLMResources(
            AgentDefinitions.analyzeAssets,
            defaultClientKey: LLMConfig.defaultClientKey,
          );
          if (_isSendCanceled(sendSerial, primaryMessageId)) {
            _finishCanceledSend(sendSerial);
            return;
          }
          final analysisTool = AssetAnalysisTool(
            client: analysisResources.client,
            modelConfig: analysisResources.modelConfig,
          );
          final analyses = <String>[];
          for (final image in draft.images) {
            if (_isSendCanceled(sendSerial, primaryMessageId)) {
              _finishCanceledSend(sendSerial);
              return;
            }
            final result = await analysisTool.tool(
              assetPath: image.path,
              prompt: '用1-2句中文简要描述这张图片的内容。'
                  '关注画面中可见的人、物体、文字、场景。'
                  '简洁客观。',
            );
            final cleaned = result
                .replaceFirst(RegExp(r'^#Asset .+ analysis result\n:'), '')
                .trim();
            if (cleaned.isNotEmpty) analyses.add(cleaned);
          }
          if (analyses.isNotEmpty) {
            analysisText = analyses.join(' | ');
            final draftMessageId = i < batch.persistedMessageIds.length
                ? batch.persistedMessageIds[i]
                : null;
            if (draftMessageId != null) {
              try {
                await _chatService.enrichAttachmentsWithAnalysis(
                  draftMessageId,
                  analyses,
                );
              } catch (e) {
                debugPrint(
                    'Failed to persist image analyses to attachments: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('Image analysis failed, falling back to hint: $e');
        }
      }
      perDraftAnalysis.add(analysisText);
    }
    if (_isSendCanceled(sendSerial, primaryMessageId)) {
      _finishCanceledSend(sendSerial);
      return;
    }

    // Get LLM resources
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _finishCanceledSend(sendSerial);
      return;
    }

    final String chatMessage = _composeBatchUserMessage(
      drafts: drafts,
      perDraftAnalysis: perDraftAnalysis,
    );
    final combinedText = drafts.map((d) => d.text).join('\n');
    final linkContext = await _buildLinkConversationContext(combinedText);
    var chatMessageWithContext =
        linkContext == null ? chatMessage : '$linkContext\n\n$chatMessage';
    // One-shot hidden context: if a voice call just ended, tell the model so it
    // carries "we were just on a call / who hung up" naturally. Injected into
    // the LLM input only — not persisted, not shown, not spoken — and consumed
    // so it lands on exactly the next turn (within maxAge).
    final pendingCallEnd = await UserStorage.takePendingCallEnd();
    if (pendingCallEnd != null) {
      final who = pendingCallEnd == 'agent'
          ? 'you (the character) chose to end the call'
          : 'the user (they hung up)';
      final callEndReminder = '<system-reminder type="call-ended">\n'
          'A voice call between you and the user just ended, moments ago. '
          'It was ended by: $who. The user heard a hang-up tone and already '
          'knows the call is over. Do NOT read this note aloud and do NOT '
          'announce "you hung up" / "I hung up" as a system message; simply '
          'carry the context naturally into your next reply (e.g. the chat just '
          'moved from a call back to text, or you ended it to give them space).\n'
          '</system-reminder>';
      chatMessageWithContext = '$callEndReminder\n\n$chatMessageWithContext';
    }

    String lastChunk = '';
    var responsePersisted = false;
    StreamingTtsSession? ttsSession;

    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      if (_isSendCanceled(sendSerial, primaryMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }

      final toyControlService = _readyToyControlService();
      if (toyControlService == null) {
        _connectToyInBackground();
      }

      if (_isInlineVoiceMode) {
        final voiceId = await UserStorage.getActiveTtsVoiceId();
        if (voiceId != null && voiceId.isNotEmpty) {
          final requestSerial = ++_ttsRequestSerial;
          ttsSession = StreamingTtsSession(
            voiceId: voiceId,
            voiceMode: _isInlineVoiceMode,
          );
          await ttsSession.start();
          _streamingTtsSession = ttsSession;
          // Pause mic forwarding to NLS while TTS plays so the speaker output
          // is not picked up by the mic and recognized as user speech (echo
          // loop). Barge-in amplitude polling stays active so the user can
          // interrupt by speaking; on TTS complete the mic resumes forwarding.
          if (_voiceController.isStreaming) {
            _voiceController.pauseAudioForwarding();
          }
          if (mounted) {
            setState(() {
              _playingMessageId = 'streaming:$requestSerial';
              _isTtsLoading = true;
            });
          }
        }
      }

      await for (final chunk in CompanionAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: sendCharacterId,
        userMessage: chatMessageWithContext,
        // Retrieval should use what the user actually said, not hidden link,
        // call-end, image-analysis, or time-prefix context added for the LLM.
        recallQuery: combinedText,
        // Compose mode can persist several user messages that the model sees
        // as one turn. Every member should open the same recall trace.
        recallMessageIds: batch.persistedMessageIds,
        // Images are only passed to the LLM when it supports vision. For
        // text-only models, the image hint above lets the character acknowledge
        // the images without seeing their contents.
        images: null,
        userMessageId: primaryMessageId,
        userMessageTime: drafts.first.timestamp,
        debugErrorOutput: true,
        voiceMode: _isInlineVoiceMode,
        continuousModeInput: batch.isContinuous,
        sceneDirective: batch.sceneDirective,
        toyControlService: toyControlService,
        extraTools: _isInlineVoiceMode ? [_buildEndVoiceModeTool()] : const [],
        turnImageAnalyses: perDraftAnalysis
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList(),
      )) {
        if (_isSendCanceled(sendSerial, primaryMessageId)) {
          break;
        }
        lastChunk = chunk;
        ttsSession?.feedText(chunk);
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
      if (_isSendCanceled(sendSerial, primaryMessageId)) {
        unawaited(ttsSession?.cancel());
        _streamingTtsSession = null;
        if (_isInlineVoiceMode &&
            !_isVoiceModeMicMuted &&
            _voiceController.isStreaming) {
          _voiceController.resumeAudioForwarding();
        }
        _finishCanceledSend(sendSerial);
        return;
      }

      // Persist character response
      final fullResponse = lastChunk.trim();
      if (fullResponse.isNotEmpty) {
        if (_isSendCanceled(sendSerial, primaryMessageId)) {
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
        _markBatchAnswered(batch);

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

      if (_isSendCanceled(sendSerial, primaryMessageId)) {
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
          if (ttsSession != null) {
            _streamingTtsSession = null;
            final playingId = _playingMessageId;
            final reqSerial = _ttsRequestSerial;
            // Advance the auto-read watermark past the just-saved character
            // message. The streaming TTS session already played this reply
            // aloud; without advancing the watermark, _handleTtsPlaybackCompleted
            // → _autoReadNextMessageIfAny would find the just-saved message
            // still "unread" and re-play it through the non-streaming
            // _audioPlayer — producing a delayed echo (two overlapping voices).
            _advanceAutoReadWatermark(updated);
            unawaited(ttsSession.finishAndWait().then((_) {
              if (mounted && playingId != null) {
                _handleTtsPlaybackCompleted(reqSerial, playingId);
              }
            }));
          } else if (_autoReadEnabled || _isInlineVoiceMode) {
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
        _maybeAdvanceContinuousMode();
        // Fire-and-forget lightweight dreaming tick after each reply.
        if (AppDatabase.isInitialized) {
          unawaited(DreamingSchedulerService.triggerLightweightTickStatic(
            AppDatabase.instance,
          ));
        }
      }
    } on CompanionApiException catch (e) {
      // A failed turn ends any active continuous run cleanly (no zombie
      // "still narrating" state with nothing driving it).
      _continuousTimer?.cancel();
      ContinuousModeState.instance.stopRun();
      unawaited(ttsSession?.cancel());
      _streamingTtsSession = null;
      if (_isInlineVoiceMode &&
          !_isVoiceModeMicMuted &&
          _voiceController.isStreaming) {
        _voiceController.resumeAudioForwarding();
      }
      debugPrint('CompanionApiException during send: ${e.cause}');
      if (_isSendCanceled(sendSerial, primaryMessageId)) {
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
        final canRetry = isViewingSendCharacter && primaryMessageId > 0;
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
                    userMessageId: primaryMessageId,
                    text: drafts.first.text,
                    timestamp: drafts.first.timestamp,
                  )
              : null,
        );
        _sendPendingMessage();
      }
    } catch (e) {
      unawaited(ttsSession?.cancel());
      _streamingTtsSession = null;
      if (_isInlineVoiceMode &&
          !_isVoiceModeMicMuted &&
          _voiceController.isStreaming) {
        _voiceController.resumeAudioForwarding();
      }
      if (_isSendCanceled(sendSerial, primaryMessageId)) {
        _finishCanceledSend(sendSerial);
        return;
      }
      final partialResponse = lastChunk.trim();
      if (partialResponse.isNotEmpty && !responsePersisted) {
        if (_isSendCanceled(sendSerial, primaryMessageId)) {
          _finishCanceledSend(sendSerial);
          return;
        }
        await _chatService.addCharacterMessage(
          sendCharacterId,
          partialResponse,
          isRead: !_isAppInBackground,
          timestamp: DateTime.now(),
        );
        _markBatchAnswered(batch);
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

  /// Composes the user-facing message string sent to the LLM for a batch.
  ///
  /// Single-draft batches mirror the legacy formatting (image analysis prefix,
  /// fallback image hint, or raw text). Multi-draft batches join each draft
  /// with its own time-prefixed block separated by a delimiter, signaling to
  /// the character that the user sent several distinct messages in one turn.
  String _composeBatchUserMessage({
    required List<_ComposeDraft> drafts,
    required List<String?> perDraftAnalysis,
  }) {
    if (drafts.length == 1) {
      final draft = drafts.first;
      final analysis = perDraftAnalysis.first;
      final imageCount = draft.images.length;
      if (analysis != null && analysis.isNotEmpty) {
        return draft.text.isNotEmpty
            ? '[Image analysis: $analysis]\n\n${draft.text}'
            : '[Image analysis: $analysis]';
      } else if (imageCount > 0) {
        return draft.text.isNotEmpty
            ? '[The user attached $imageCount image(s) to this message.]\n\n${draft.text}'
            : '[The user sent $imageCount image(s) without text.]';
      }
      return draft.text;
    }

    final buffer = StringBuffer();
    buffer.writeln('The user sent ${drafts.length} messages in one turn. '
        'Please read them as a whole and reply once, addressing each as needed.');
    buffer.writeln();
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      final analysis = perDraftAnalysis[i];
      buffer.writeln('--- message ${i + 1} ---');
      if (analysis != null && analysis.isNotEmpty) {
        buffer.writeln('[Image analysis: $analysis]');
      } else if (draft.images.isNotEmpty) {
        buffer.writeln(
            '[The user attached ${draft.images.length} image(s) to this message.]');
      }
      buffer.writeln(draft.text);
      buffer.writeln();
    }
    buffer.writeln('--- end of batch ---');
    return buffer.toString().trimRight();
  }

  /// Executes a queued [_PendingBatch] (called when streaming finishes and the
  /// next queued batch auto-sends). Multi-draft batches merge into one LLM
  /// call; the persisted user messages from the queue-while-streaming path are
  /// reused without re-persisting.
  Future<void> _sendBatch(_PendingBatch batch) async {
    if (_batchWasAlreadyAnswered(batch)) {
      _sendPendingMessage();
      return;
    }
    // Synchronous send lock for the persist window below (compose batches await
    // image compression + addUserMessage before _runBatchSend would claim it).
    // Stops a concurrent direct _sendMessage from dispatching a second turn.
    _isStreaming = true;
    _streamingText = '';
    // If the batch was queued while streaming (e.g. from Compose mode), its
    // drafts aren't persisted yet. Persist them now so they appear as visible
    // user messages before the character reply streams in.
    if (batch.persistedMessageIds.isEmpty && batch.drafts.isNotEmpty) {
      final persistedIds = <int>[];
      for (var i = 0; i < batch.drafts.length; i++) {
        final draft = batch.drafts[i];
        // Compress images for drafts that still have raw XFiles.
        List<Map<String, String>>? attachments;
        if (draft.images.isNotEmpty) {
          attachments = <Map<String, String>>[];
          setState(() => _isCompressingImages = true);
          for (final image in draft.images) {
            attachments.add(await _compressImageForChat(image));
          }
          if (mounted) setState(() => _isCompressingImages = false);
        }
        final id = await _chatService.addUserMessage(
          batch.characterId,
          draft.text,
          timestamp: draft.timestamp,
          attachments: attachments,
          appendTimeline: false,
        );
        persistedIds.add(id);
      }
      batch.persistedMessageIds.addAll(persistedIds);
    }
    final primaryMessageId = batch.persistedMessageIds.isNotEmpty
        ? batch.persistedMessageIds.first
        : -(DateTime.now().millisecondsSinceEpoch);
    await _runBatchSend(batch, primaryMessageId: primaryMessageId);
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

  bool _batchWasAlreadyAnswered(_PendingBatch batch) {
    return personaChatPendingBatchWasAlreadyAnswered(
      pendingMessageIds: batch.persistedMessageIds,
      answeredMessageIds: _answeredUserMessageIds,
    );
  }

  void _markBatchAnswered(_PendingBatch batch) {
    _answeredUserMessageIds.addAll(
      batch.persistedMessageIds.where((id) => id > 0),
    );
  }

  /// Sends the next queued user turn only after both reply generation and its
  /// spoken playback have finished. Drops any stale queue entry whose persisted
  /// user message already received a reply.
  void _sendPendingMessage() {
    if (!personaChatCanDispatchPendingBatch(
      isStreaming: _isStreaming,
      isRoleVoiceActive: _isRoleVoiceActive,
    )) {
      return;
    }

    while (_pendingBatches.isNotEmpty) {
      final batch = _pendingBatches.removeAt(0);
      if (_batchWasAlreadyAnswered(batch)) continue;
      unawaited(_sendBatch(batch));
      return;
    }
  }

  /// Continuous-mode driver: called after a reply finishes streaming. Starts a
  /// run when the agent requested one during this turn, then schedules the next
  /// synthetic turn until the run drains or the user stops it.
  void _maybeAdvanceContinuousMode() {
    final pending = ContinuousModeState.instance.consumePending();
    if (pending != null) {
      ContinuousModeState.instance.startRun(
        characterId: _currentCharacterId,
        count: pending,
      );
      if (mounted) setState(() {});
    }
    if (_pendingBatches.isNotEmpty) return;
    if (!ContinuousModeState.instance.isActiveFor(_currentCharacterId)) {
      // run 结束（条数耗尽或已停止）→ 若正在场景中，一并结束场景。
      if (IntimateSceneState.instance.isActiveFor(_currentCharacterId)) {
        IntimateSceneState.instance.end();
        if (mounted) setState(() {});
      }
      return;
    }
    if (IntimateSceneState.instance.isActiveFor(_currentCharacterId)) {
      IntimateSceneState.instance.turnCompleted();
    }
    if (!ContinuousModeState.instance.tick(_currentCharacterId)) {
      // 最后一条已经发完：场景随 run 一起收束。
      if (IntimateSceneState.instance.isActiveFor(_currentCharacterId)) {
        IntimateSceneState.instance.end();
        if (mounted) setState(() {});
      }
      return;
    }
    _scheduleNextContinuousTick();
  }

  /// (Re)schedules the next synthetic continuous turn without consuming a tick.
  /// Defer-and-retry while a concurrent turn is streaming OR while the
  /// previous reply's TTS is still playing — the run is paced by playback,
  /// not by a fixed delay, so the user hears each message fully before the
  /// next one starts (sending earlier would `_stopTtsPlayback()` mid-word).
  void _scheduleNextContinuousTick() {
    _continuousTimer?.cancel();
    _continuousTimer = Timer(ContinuousModeState.interTurnDelay, () {
      if (!mounted ||
          !ContinuousModeState.instance.isActiveFor(_currentCharacterId)) {
        return;
      }
      if (_isStreaming || _isTtsLoading || _playingMessageId != null) {
        _scheduleNextContinuousTick();
        return;
      }
      final sceneDirective =
          IntimateSceneState.instance.isActiveFor(_currentCharacterId)
              ? IntimateSceneState.instance.currentDirective()
              : null;
      unawaited(_sendMessage(
        syntheticInput: kContinuousAdvanceSentinel,
        isContinuous: true,
        sceneDirective: sceneDirective,
      ));
    });
  }

  /// 亲密场景开场：持久化触发消息 → 规划器产出节拍表 → 启动连续 run。
  /// 规划失败时降级为单 beat 平铺 run，不让开场卡死。
  Future<void> _startIntimateScene({
    required String characterId,
    required CharacterModel? character,
    required String userText,
    required DateTime userMessageTime,
  }) async {
    final userId = _userId ?? await UserStorage.getUserId();
    await _chatService.addUserMessage(
      characterId,
      userText,
      timestamp: userMessageTime,
      appendTimeline: false,
    );
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.companionAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    // 亲密档案（全局单一份）：她的强度语法/硬边界 → 规划器。
    // 缺失时回退默认（用户首版）。
    final profile = userId == null
        ? IntimacyProfile.defaultProfile()
        : await IntimacyProfileService().load(userId);
    final profileText = profile.buildProfileText();
    // 约 10 分钟语音的初值；按需求 §5 从目标时长倒推，后续磨合。
    const totalMessages = 30;
    IntimateScenePlan? plan;
    try {
      plan = await IntimateScenePlanner.plan(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userText: userText,
        totalMessages: totalMessages,
        profileText: profileText,
      );
    } catch (e) {
      debugPrint('IntimateScenePlanner failed: $e');
    }
    plan ??= const IntimateScenePlan(beats: [
      IntimateSceneBeat(
        intent: '推进场景',
        targetMessageCount: 30,
        notes: '维持激烈高位，变化推进，不要收束',
        escalationLevel: 4,
      ),
    ]);
    IntimateSceneState.instance.start(
      characterId: characterId,
      plan: plan,
      profileText: profileText,
    );
    ContinuousModeState.instance
        .startRun(characterId: characterId, count: plan.totalMessages);
    if (mounted) setState(() {});
    _scheduleNextContinuousTick();
  }

  /// Visible affordance shown while a continuous run is active.
  Widget _buildContinuousModeStopChip() {
    final remaining = ContinuousModeState.instance.remaining;
    final tokens = HereIamThemeRuntime.current;
    return Material(
      color: tokens.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _stopContinuousMode,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_circle_outlined,
                  size: 16, color: tokens.highlight),
              const SizedBox(width: 6),
              Text(
                _chatUiText(
                  zh: '连续叙述中 · 剩余 $remaining 条 · 点按停止',
                  en: 'Narrating… $remaining left · tap to stop',
                ),
                style: TextStyle(fontSize: 12, color: tokens.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stopContinuousMode() {
    _continuousTimer?.cancel();
    ContinuousModeState.instance.stopRun();
    IntimateSceneState.instance.end();
    if (mounted) setState(() {});
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

      // ── Reading link: inject fetched body so Record Organizer can
      //    produce a reading_item card without re-hitting the source.
      //    Mirrors how image analyses are pre-extracted above: we feed
      //    the organizer already-analysed content instead of asking it
      //    to fetch. The transient cache entry was warmed when the link
      //    was first sent; we just await it here. If the cache has
      //    expired or was never warmed, fall back to a fresh fetch.
      var recordInput = cleanedContent;
      final linkParse = parseReadingShare(cleanedContent);
      if (linkParse != null && TransientFetchCache.isInitialized) {
        try {
          final cache = TransientFetchCache.instance;
          final entry = await cache.fetch(
            platform: linkParse.platform,
            url: linkParse.url,
          );
          final body = entry.buildAgentContext();
          if (body != null && body.trim().isNotEmpty) {
            final buf = StringBuffer()
              ..writeln(cleanedContent)
              ..writeln()
              ..writeln('[Link content]')
              ..writeln(body.trim())
              ..writeln()
              ..writeln(
                'The user asked to save this link. Create a reading_item '
                'memory card for it. The body above has already been '
                'fetched — do NOT attempt to fetch the URL again.',
              );
            recordInput = buf.toString();
          }
        } catch (e) {
          debugPrint(
            '[Record] msg#${message.id} link body enrichment failed: $e',
          );
        }
      }

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
          rawInput: recordInput.isNotEmpty ? recordInput : message.content,
          sourceRef: message.id.toString(),
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

    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (selected.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final progress = messenger.showToast(
      _chatUiText(zh: '正在记录…', en: 'Recording…'),
      duration: const Duration(seconds: 30),
    );

    try {
      final allMedia = <MediaInputAttachment>[];
      final buffer = StringBuffer();
      final fsService = FileSystemService.instance;

      for (final msg in selected) {
        final cleanedContent = msg.content
            .replaceFirst(RegExp(r'^\[Image analysis:.*?\](\n\n?)?'), '')
            .trim();
        final existingAnalyses = _extractImageAnalyses(msg.content);

        final attachmentsJson = msg.attachmentsJson;
        if (attachmentsJson != null && attachmentsJson.trim().isNotEmpty) {
          try {
            final List<dynamic> attachments = jsonDecode(attachmentsJson);
            for (var i = 0; i < attachments.length; i++) {
              final att = attachments[i];
              if (att is! Map) continue;
              final attachment = Map<dynamic, dynamic>.from(att);
              if (!_personaChatAttachmentLooksLikeImage(attachment)) continue;
              final mimeType =
                  _personaChatImageMimeTypeForAttachment(attachment);
              final base64 = attachment['base64']?.toString();
              final recoveryPath = personaChatRecoverableImageAttachmentPath(
                attachment,
              );
              if (!personaChatImageAttachmentCanBeRecorded(attachment)) {
                allMedia.add(
                  const MediaInputAttachment(
                    error: 'image attachment has neither bytes nor sourcePath',
                  ),
                );
                continue;
              }

              try {
                final ext = _imageExtForMime(mimeType);
                File? tempFile;
                late final String sourcePathForSave;
                if (base64 != null && base64.isNotEmpty) {
                  try {
                    final bytes = base64Decode(base64);
                    final tempDir = Directory.systemTemp;
                    tempFile = File(
                      '${tempDir.path}${Platform.pathSeparator}record_${msg.id}_$i.$ext',
                    );
                    await tempFile.writeAsBytes(bytes);
                    sourcePathForSave = tempFile.path;
                  } catch (e) {
                    if (recoveryPath == null) rethrow;
                    sourcePathForSave = recoveryPath;
                  }
                } else {
                  sourcePathForSave = recoveryPath!;
                }
                final sourceFile = File(sourcePathForSave);
                if (!await sourceFile.exists()) {
                  throw FileSystemException(
                    'Image source not found for record attachment',
                    sourcePathForSave,
                  );
                }

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
                    index: allMedia.length + 1,
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

                String? analysisText;
                if (i < existingAnalyses.length) {
                  analysisText = existingAnalyses[i];
                }
                if (analysisText == null || analysisText.trim().isEmpty) {
                  final storedAnalysis = attachment['analysis']?.toString();
                  if (storedAnalysis != null &&
                      storedAnalysis.trim().isNotEmpty) {
                    analysisText = storedAnalysis.trim();
                  }
                }
                if (analysisText == null || analysisText.trim().isEmpty) {
                  try {
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
                    analysisText = result
                        .replaceFirst(
                          RegExp(r'^#Asset .+ analysis result\n:'),
                          '',
                        )
                        .trim();
                  } catch (e) {
                    debugPrint(
                      '[BatchRecord] msg#${msg.id} image#$i inline analysis FAILED: $e',
                    );
                  }
                }

                allMedia.add(
                  MediaInputAttachment(
                    savedRelativePath: relativePath,
                    analysisText: analysisText,
                    kind: 'image',
                  ),
                );
              } catch (e) {
                debugPrint(
                  '[BatchRecord] msg#${msg.id} image#$i PROCESSING FAILED: $e',
                );
                allMedia.add(MediaInputAttachment(error: e.toString()));
              }
            }
          } catch (e) {
            debugPrint(
              '[BatchRecord] msg#${msg.id} parse attachmentsJson FAILED: $e',
            );
          }
        }

        final label = msg.isFromCharacter ? '林埃' : '用户';
        if (cleanedContent.isNotEmpty) {
          buffer.writeln('$label: $cleanedContent');
        } else {
          final usableMediaForMsg = allMedia.where((m) => m.isUsable).toList();
          if (usableMediaForMsg.isNotEmpty) {
            final lastAnalysis = usableMediaForMsg.last.analysisText;
            if (lastAnalysis != null && lastAnalysis.isNotEmpty) {
              buffer.writeln('$label: [图片] $lastAnalysis');
            } else {
              buffer.writeln('$label: [图片]');
            }
          }
        }
      }

      final combinedText = buffer.toString().trim();
      if (combinedText.isEmpty && allMedia.isEmpty) {
        progress.close();
        _exitSelectMode();
        return;
      }

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
      final inputMedia = allMedia.isNotEmpty
          ? allMedia
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
          rawInput: combinedText,
          sourceRef: jsonEncode(selected.map((message) => message.id).toList()),
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

  Future<void> _batchAddToTopicThread() async {
    if (_topicBackfillRunning || _selectedMessageIds.isEmpty) return;
    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (selected.isEmpty || !mounted) return;

    final threads =
        await TopicThreadService(db: AppDatabase.instance).getThreads();
    if (!mounted) return;
    if (threads.isEmpty) {
      ScaffoldMessenger.of(context).showToast(
        _chatUiText(
          zh: '还没有话题线索，先在聊天里说"想追踪这个话题"创建',
          en: 'No topic threads yet',
        ),
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final thread = await showModalBottomSheet<TopicThread>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TopicThreadPickerSheet(
        threads: threads,
        onSelected: (t) => Navigator.pop(ctx, t),
      ),
    );
    if (thread == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpringRainUiTokens.daylight.surface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(SpringRainUiTokens.daylight.radius14),
        ),
        title: Text(
          _chatUiText(zh: '加入话题线索？', en: 'Add to topic thread?'),
          style: TextStyle(
            color: SpringRainUiTokens.daylight.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          _chatUiText(
            zh: '将选中 ${selected.length} 条消息的摘要加入话题「${thread.title}」（AI 生成，≤200 字）。',
            en: 'Summarize ${selected.length} selected message(s) into '
                '"${thread.title}" (AI, ≤200 chars).',
          ),
          style: TextStyle(
            color: SpringRainUiTokens.daylight.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_chatUiText(zh: '取消', en: 'Cancel'),
                style: TextStyle(
                    color: SpringRainUiTokens.daylight.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_chatUiText(zh: '加入', en: 'Add'),
                style: TextStyle(color: _personaAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _topicBackfillRunning = true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = messenger.showToast(
      _chatUiText(zh: '正在生成话题摘要…', en: 'Summarizing…'),
      duration: const Duration(seconds: 30),
    );
    try {
      await TopicThreadBackfillService(db: AppDatabase.instance)
          .summarizeAndAppend(
        threadId: thread.id,
        messages: selected,
        characterName: _character?.name ?? '林埃',
      );
      progress.close();
      if (!mounted) return;
      messenger.showToast(
        _chatUiText(
          zh: '已加入话题「${thread.title}」',
          en: 'Added to "${thread.title}"',
        ),
        duration: const Duration(seconds: 3),
      );
    } catch (e, stack) {
      progress.close();
      debugPrint('[AddToThread] failed: $e\n$stack');
      if (mounted) {
        messenger.showToast(
          _chatUiText(zh: '加入话题失败：$e', en: 'Failed: $e'),
          duration: const Duration(seconds: 3),
        );
      }
    } finally {
      if (mounted) setState(() => _topicBackfillRunning = false);
      _exitSelectMode();
    }
  }

  Future<void> _batchDeleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpringRainUiTokens.daylight.surface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(SpringRainUiTokens.daylight.radius14),
        ),
        title: Text(_chatUiText(zh: '删除消息', en: 'Delete messages'),
            style: TextStyle(
              color: SpringRainUiTokens.daylight.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            )),
        content: Text(
            _chatUiText(
              zh: '确定要删除选中的 ${_selectedMessageIds.length} 条消息吗？删除后将不会被提取到记忆中。',
              en: 'Delete ${_selectedMessageIds.length} selected message(s)? They will not be extracted into memory.',
            ),
            style: TextStyle(
              color: SpringRainUiTokens.daylight.textSecondary,
              fontSize: 14,
              height: 1.5,
            )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_chatUiText(zh: '取消', en: 'Cancel'),
                style: TextStyle(
                    color: SpringRainUiTokens.daylight.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _chatUiText(zh: '删除', en: 'Delete'),
              style: TextStyle(color: SpringRainUiTokens.daylight.error),
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

  Future<String?> _buildLinkConversationContext(String text) async {
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

    // Kick off a transient fetch (no entity, no card) so the companion can
    // discuss the actual article body — same pattern as image-analysis
    // injection for image attachments. We await up to a short grace window
    // so the first reply can use the body when the fetch is fast; if the
    // fetch is slow, we proceed with metadata only and let later turns
    // pick up the cached body via the in-memory entry.
    String? articleBody;
    if (TransientFetchCache.isInitialized) {
      try {
        final cache = TransientFetchCache.instance;
        final future = cache.fetch(
          platform: parsed.platform,
          url: parsed.url,
        );
        articleBody = await future
            .timeout(const Duration(seconds: 3))
            .then((entry) => entry.buildAgentContext())
            .catchError((Object _) => null) as String?;
      } catch (_) {
        // Transient fetch is best-effort; never block the chat send.
      }
    }

    if (articleBody != null && articleBody.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('[Link content]')
        ..writeln(articleBody.trim())
        ..writeln();
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
      _activeUserMessageIds.clear();
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

  /// Returns the user message ids that should be deleted from the DB as part
  /// of this retract: at minimum [triggerId], plus any siblings from the
  /// same batch (when the LLM saw them as one merged turn, retracting one
  /// cancels the whole batch and all its persisted messages are deleted).
  List<int> _cancelSendForRetractedMessage(int triggerId) {
    final toRetract = <int>[triggerId];
    _retractedUserMessageIds.add(triggerId);

    // Queued batch: drop the whole batch and flag its persisted ids.
    for (final batch in _pendingBatches) {
      if (batch.persistedMessageIds.contains(triggerId)) {
        for (final id in batch.persistedMessageIds) {
          _retractedUserMessageIds.add(id);
          if (!toRetract.contains(id)) toRetract.add(id);
        }
        _pendingBatches.remove(batch);
        return toRetract;
      }
    }

    // Active streaming send: cancel the whole active batch.
    if (_activeUserMessageIds.contains(triggerId)) {
      final sendSerial = _activeSendSerial;
      if (sendSerial != null) {
        _canceledSendSerials.add(sendSerial);
      }
      for (final id in _activeUserMessageIds) {
        _retractedUserMessageIds.add(id);
        if (!toRetract.contains(id)) toRetract.add(id);
      }
      _activeSendSerial = null;
      _activeUserMessageIds.clear();
      _activeStreamingCharacterId = null;
      if (!mounted) return toRetract;
      setState(() {
        _isStreaming = false;
        _streamingText = '';
      });
      _sendPendingMessage();
    }
    return toRetract;
  }

  Future<void> _confirmRetractUserMessage(PersonaChatMessage message) async {
    if (message.isFromCharacter) return;
    if (!mounted) return;

    final toRetract = _cancelSendForRetractedMessage(message.id);

    // Delete every id flagged for retract. The user-tapped message reports its
    // delete result back; siblings are deleted silently as part of the batch.
    var primaryDeleted = 0;
    for (final id in toRetract) {
      final deleted = await _chatService.retractUserMessage(
        _currentCharacterId,
        id,
      );
      if (id == message.id) primaryDeleted = deleted;
      _messageKeys.remove(id);
    }
    if (!mounted) return;

    if (primaryDeleted == 0 && toRetract.length == 1) {
      _showRetractToast(
        _chatUiText(
          zh: '这条消息已经不能撤回',
          en: 'This message can no longer be recalled',
        ),
      );
      return;
    }

    await _refreshMessagesFromStore(autoRead: false, scrollToBottom: false);
    if (!mounted) return;
    _showRetractToast(
      _chatUiText(
        zh: toRetract.length > 1 ? '已撤回 ${toRetract.length} 条' : '已撤回',
        en: toRetract.length > 1
            ? '${toRetract.length} messages recalled'
            : 'Message recalled',
      ),
      actionLabel: _chatUiText(zh: '重新编辑', en: 'Edit'),
      onAction: () {
        // The retract toast restores the original sent text into the composer.
        // The stale guard is still armed with that same sent text (the message
        // we just retracted was the most recent send), so a plain assignment
        // would trip `_clearComposerIfStaleText` and wipe the field. Disarm the
        // guard and use the programmatic-clear flag to suppress the listener,
        // mirroring `_setComposerTextEmpty`.
        _composerStaleGuard.disarm();
        _isProgrammaticComposerClear = true;
        try {
          _textController.text = message.content;
          _textController.selection = TextSelection.collapsed(
            offset: message.content.length,
          );
        } finally {
          _isProgrammaticComposerClear = false;
        }
        _composerFocus.requestFocus();
      },
    );
  }

  void _showRetractToast(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _retractToastTimer?.cancel();
    setState(() {
      _retractToastText = text;
      _retractToastActionLabel = actionLabel;
      _retractToastAction = onAction;
    });
    _retractToastTimer = Timer(const Duration(seconds: 3), _hideRetractToast);
  }

  void _hideRetractToast() {
    _retractToastTimer?.cancel();
    _retractToastTimer = null;
    if (!mounted) return;
    setState(() {
      _retractToastText = null;
      _retractToastActionLabel = null;
      _retractToastAction = null;
    });
  }

  Widget _buildRetractToast() {
    const c = SpringRainChatTokens.springRainDaydream;
    return GestureDetector(
      onTap: _hideRetractToast,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: c.background.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: c.glassStroke.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _retractToastText!,
                  style: TextStyle(
                    color: c.iColor.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontFamily: c.fontFamily,
                  ),
                ),
                if (_retractToastActionLabel != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      final action = _retractToastAction;
                      _hideRetractToast();
                      action?.call();
                    },
                    child: Text(
                      _retractToastActionLabel!,
                      style: TextStyle(
                        color: c.actionColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: c.fontFamily,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

  /// Toggle auto-read for [provider] ('elevenlabs' or 'minimax').
  ///
  /// If the tapped provider is already active and auto-read is on, turn it
  /// off. If a different provider is active (or auto-read is off), switch to
  /// this provider and turn auto-read on. The active provider is persisted so
  /// manual play and inline voice mode follow the last auto-read choice.
  Future<void> _toggleAutoRead(String provider) async {
    if (_autoReadEnabled && _activeTtsProvider == provider) {
      // Same provider, auto-read is on → turn off.
      setState(() => _autoReadEnabled = false);
      try {
        await UserStorage.setCompanionAutoReadEnabled(false);
        await _stopTtsPlayback();
      } catch (e) {
        if (!mounted) return;
        setState(() => _autoReadEnabled = true);
      }
      return;
    }
    // Switch provider and enable auto-read.
    await UserStorage.setTtsProvider(provider);
    _advanceAutoReadWatermark(_messages);
    setState(() {
      _activeTtsProvider = provider;
      _autoReadEnabled = true;
    });
    try {
      await UserStorage.setCompanionAutoReadEnabled(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoReadEnabled = false);
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
    _voiceModeMicSerial++;
    setState(() {
      _isInlineVoiceMode = enabled;
      _isVoiceModeMicMuted = false;
    });
    if (enabled) {
      // Enter VoIP call audio mode so mic + TTS speaker coexist with AEC.
      unawaited(VoiceCallAudioSession.instance.enter());
      // Route the TTS player through the voice-communication stream so the
      // platform AEC can cancel speaker output from the mic signal.
      unawaited(_applyVoiceCallTtsContext());
      _voiceModeSilentFollowUps = 0;
      _voiceModeIdleFollowUpSerial++;
      _queueVoiceModeOpening();
    } else {
      _voiceModeOpeningSerial++;
      _voiceModeIdleFollowUpSerial++;
      _voiceModeOpeningInProgress = false;
      _voiceModeStartQueued = false;
      _sentenceDebouncer.cancel();
      _inBargeInFollowUp = false;
      // Hang-up must unlock the UI immediately. Invalidate any in-flight LLM
      // turn and force-reset the streaming state, otherwise two paths leave
      // _isStreaming stuck true: (1) the opening / idle-follow-up generators
      // guard their `finally` reset on `serial == _voiceMode*Serial`, which we
      // just bumped, so they skip the reset; (2) a user-message turn keeps
      // streaming past hang-up. Clearing _activeSendSerial also makes the
      // in-flight turn's next _isSendCanceled check bail out before it persists
      // a reply (so no stray "delayed" reply after hang-up).
      _activeSendSerial = null;
      _activeUserMessageIds.clear();
      _pendingBatches.clear();
      if (_isStreaming ||
          _streamingText.isNotEmpty ||
          _playingMessageId != null ||
          _isTtsLoading) {
        setState(() {
          _isStreaming = false;
          _streamingText = '';
          _playingMessageId = null;
          _isTtsLoading = false;
        });
      }
      final wasAgentEnded = _endVoiceModeAfterCurrentReply;
      _endVoiceModeAfterCurrentReply = false;
      _voiceModeSilentFollowUps = 0;
      if (_voiceController.isStreaming) {
        await _voiceController.cancelStreaming();
      } else {
        await _voiceController.cancel();
      }
      await _stopTtsPlayback();
      // Play the hangup tone through just_audio while the VoIP audio session
      // is still active. A new audioplayers AudioPlayer can't acquire audio
      // focus while the VoIP session holds it, producing no sound. just_audio
      // with handleAudioSessionActivation:false plays through the existing
      // active session. We await completion (~0.5s) before tearing down.
      await playHangupTone();
      // Now safe to restore default and exit VoIP call mode.
      await _restoreDefaultTtsContext();
      await VoiceCallAudioSession.instance.exit();
      // End-of-call cue + hidden context for the character. The previous code
      // injected a *character* message ("📵 用户挂断了语音通话。") which auto-read spoke
      // aloud and rendered as a character bubble - both wrong. Instead: stash
      // a one-shot note carrying WHO ended the call; the next turn injects it
      // into the LLM input only (see _runBatchSend) - never a bubble, never TTS.
      // Done for both sides; wasAgentEnded tells us who.
      final endedBy = wasAgentEnded ? 'agent' : 'user';
      unawaited(UserStorage.setPendingCallEnd(endedBy));
    }
  }

  Future<void> _applyVoiceCallTtsContext() async {
    if (_ttsAudioContextApplied) return;
    try {
      await _audioPlayer.setAudioContext(_voiceCallTtsContext);
      _ttsAudioContextApplied = true;
      debugPrint('TTS audio context → voiceCommunication (AEC reference)');
    } catch (e) {
      debugPrint('setAudioContext(voice call) failed: $e');
    }
  }

  Future<void> _restoreDefaultTtsContext() async {
    if (!_ttsAudioContextApplied) return;
    _ttsAudioContextApplied = false;
    try {
      await _audioPlayer.setAudioContext(_defaultTtsContext);
      debugPrint('TTS audio context → restored default');
    } catch (e) {
      debugPrint('setAudioContext(default) failed: $e');
    }
  }

  Future<void> _stopTtsPlayback() async {
    _ttsRequestSerial++;
    final session = _streamingTtsSession;
    _streamingTtsSession = null;
    if (session != null) {
      await session.cancel();
    }
    await _audioCompleteSub?.cancel();
    _audioCompleteSub = null;
    await _audioStateSub?.cancel();
    _audioStateSub = null;
    await _audioPlayer.stop();
    if (_isInlineVoiceMode && !_isVoiceModeMicMuted) {
      if (_voiceController.isStreaming) {
        _voiceController.resumeAudioForwarding();
      } else {
        // NLS session was lost during TTS; re-arm the mic.
        _queueVoiceModeStreamingStart();
      }
    }
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
    if (_pendingBatches.isNotEmpty) {
      _sendPendingMessage();
      if (_isStreaming) return;
    }
    if (_isInlineVoiceMode &&
        !_isVoiceModeMicMuted &&
        _voiceController.isStreaming) {
      _voiceController.resumeAudioForwarding();
    }
    if (_endVoiceModeAfterCurrentReply && _isInlineVoiceMode) {
      _endVoiceModeAfterCurrentReply = false;
      unawaited(_setInlineVoiceMode(false));
      return;
    }
    if (_isInlineVoiceMode) {
      if (!_isVoiceModeMicMuted) {
        if (_voiceController.isStreaming) {
          // Mic already open (streaming ASR). The server VAD will fire
          // SentenceBegin/SentenceEnd when the user speaks. Nothing to do.
          return;
        }
        _queueVoiceModeStreamingStart();
      }
    } else {
      _queueVoiceModeRecordingStart();
    }
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
        backgroundColor: SpringRainUiTokens.daylight.surface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(SpringRainUiTokens.daylight.radius14),
        ),
        title: Text('删除这条消息？',
            style: TextStyle(
              color: SpringRainUiTokens.daylight.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            )),
        content: Text('删除后无法恢复。',
            style: TextStyle(
              color: SpringRainUiTokens.daylight.textSecondary,
              fontSize: 14,
              height: 1.5,
            )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(
                    color: SpringRainUiTokens.daylight.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(color: SpringRainUiTokens.daylight.error)),
          ),
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

    final voiceId = await UserStorage.getActiveTtsVoiceId();
    if (voiceId == null || voiceId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
            const SnackBar(content: Text('请先在声音与互动中配置 TTS Voice ID')));
      }
      return;
    }

    if (mounted) {
      setState(() {
        _playingMessageId = messageId;
        _isTtsLoading = true;
      });
    }
    // Pause mic forwarding while TTS plays to avoid the speaker output being
    // captured by the mic and misrecognized as user speech (echo loop). The
    // barge-in amplitude poller stays armed so the user can still interrupt.
    if (_isInlineVoiceMode && _voiceController.isStreaming) {
      _voiceController.pauseAudioForwarding();
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
        // Ensure the player plays the whole file and doesn't loop.
        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
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
        if (_isInlineVoiceMode &&
            !_isVoiceModeMicMuted &&
            !_voiceController.isStreaming) {
          _queueVoiceModeStreamingStart();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading) {
      _scheduleReadyNotification();
    }
    final mediaQuery = MediaQuery.of(context);
    final viewInsetsBottom = mediaQuery.viewInsets.bottom;
    final hasVisibleMediaTray = widget.enableRichCapture && _isMediaTrayOpen;
    // Estimate: input bar max ~160 + media tray ~104 when open.
    final jumpToLatestBottom =
        viewInsetsBottom + (hasVisibleMediaTray ? 272 : 168);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _personaStageInk,
      body: _isLoading
          ? personaChatStartupLoadingView()
          : Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _ChatAtmosphereBackground(character: _character),
                  ),
                ),
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.03, 0.97, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.14, 0.82, 1.0],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: _buildMessageList(),
                    ),
                  ),
                ),
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
                if (ContinuousModeState.instance
                    .isActiveFor(_currentCharacterId))
                  Positioned(
                    top: mediaQuery.padding.top + 108,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildContinuousModeStopChip()),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: viewInsetsBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_retractToastText != null) _buildRetractToast(),
                      if (widget.enableRichCapture)
                        CompanionMediaTray(
                          isOpen: _isMediaTrayOpen,
                          onImagesPicked: _onImagesPicked,
                        ),
                      _buildInputBar(),
                    ],
                  ),
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
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF12160F).withValues(alpha: 0.5),
                  border: Border.all(
                    color: const Color(0xFFF5EEE0).withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: ClipOval(
                  child: CharacterAvatar(
                    avatar: character.avatar,
                    name: '林埃',
                    size: 42,
                    backgroundColor: Colors.transparent,
                  ),
                ),
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
        icon: Icons.swap_horiz_rounded,
        label: _chatUiText(zh: '切换模型', en: 'Switch model'),
        onTap: () {
          setState(() => _isHeaderActionsOpen = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const TaskModelAssignmentPage(
                initialMode: ModelAssignmentMode.agents,
              ),
            ),
          );
        },
      ),
      _HeaderActionButton(
        icon: _autoReadEnabled && _activeTtsProvider == 'elevenlabs'
            ? Icons.record_voice_over_rounded
            : Icons.record_voice_over_outlined,
        label: _autoReadEnabled && _activeTtsProvider == 'elevenlabs'
            ? _chatUiText(zh: '关闭 ElevenLabs 朗读', en: 'Stop ElevenLabs')
            : _chatUiText(zh: 'ElevenLabs 朗读', en: 'ElevenLabs read'),
        active: _autoReadEnabled && _activeTtsProvider == 'elevenlabs',
        onTap: () => unawaited(_toggleAutoRead('elevenlabs')),
      ),
      _HeaderActionButton(
        icon: _autoReadEnabled && _activeTtsProvider == 'minimax'
            ? Icons.graphic_eq_rounded
            : Icons.graphic_eq_outlined,
        label: _autoReadEnabled && _activeTtsProvider == 'minimax'
            ? _chatUiText(zh: '关闭 MiniMax 朗读', en: 'Stop MiniMax')
            : _chatUiText(zh: 'MiniMax 朗读', en: 'MiniMax read'),
        active: _autoReadEnabled && _activeTtsProvider == 'minimax',
        onTap: () => unawaited(_toggleAutoRead('minimax')),
      ),
      if (widget.onOpenSpaces != null)
        _HeaderActionButton(
          icon: Icons.grid_view_rounded,
          label: _chatUiText(zh: '生活空间', en: 'Life space'),
          onTap: () {
            setState(() => _isHeaderActionsOpen = false);
            widget.onOpenSpaces?.call();
          },
        ),
      _HeaderActionButton(
        icon: Icons.interests_outlined,
        label: _chatUiText(zh: '兴趣', en: 'Interests'),
        onTap: () {
          setState(() => _isHeaderActionsOpen = false);
          context.push(AppRoutes.interests);
        },
      ),
      _HeaderActionButton(
        icon: Icons.person_outline_rounded,
        label: _chatUiText(zh: '个人中心', en: 'Personal center'),
        onTap: () {
          setState(() => _isHeaderActionsOpen = false);
          context.push(AppRoutes.personalCenter);
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
          crossAxisAlignment: CrossAxisAlignment.end,
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
    const c = SpringRainChatTokens.springRainDaydream;
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
                  c.pageMargin,
                  topPadding,
                  c.pageMargin,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (showDate)
                                          _buildDateDivider(msg.timestamp),
                                        if (msg.messageType == 'action')
                                          _buildActionMessage(
                                            text: msg.content,
                                            messageId: msg.id.toString(),
                                            fullMessageText: msg.content,
                                          )
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDate) _buildDateDivider(msg.timestamp),
                                if (msg.messageType == 'action')
                                  _buildActionMessage(
                                    text: msg.content,
                                    messageId: msg.id.toString(),
                                    fullMessageText: msg.content,
                                  )
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
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
                          style: const TextStyle(
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Add to topic thread button
                    GestureDetector(
                      onTap: _selectedMessageIds.isNotEmpty
                          ? _batchAddToTopicThread
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedMessageIds.isNotEmpty
                              ? _personaAccent.withValues(alpha: 0.85)
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
                          '加入话题${_selectedMessageIds.isNotEmpty ? ' (${_selectedMessageIds.length})' : ''}',
                          style: const TextStyle(
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
    const c = SpringRainChatTokens.springRainDaydream;
    final ink = const Color(0xFFD6D4C8).withValues(alpha: c.timeAlpha);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: c.timeGap / 2),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, ink],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: ink,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [ink, Colors.transparent],
                ),
              ),
            ),
          ),
        ],
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
  ///
  /// Plain Text (not selectable): long-press must open the message action
  /// popup like every other message, never text selection.
  Widget _buildActionMessage({
    required String text,
    String? messageId,
    String? fullMessageText,
  }) {
    const c = SpringRainChatTokens.springRainDaydream;
    final hasActions = messageId != null && !_isSelecting;
    final bubbleKey = GlobalKey();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: c.blockGap / 2),
      child: Padding(
        padding: EdgeInsets.only(left: c.iIndent - 10),
        child: GestureDetector(
          key: bubbleKey,
          behavior: HitTestBehavior.translucent,
          onLongPress: hasActions
              ? () {
                  HapticFeedback.mediumImpact();
                  _showBubbleActionPopup(
                    messageId: messageId,
                    text: fullMessageText ?? text,
                    bubbleKey: bubbleKey,
                  );
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: c.actionColor.withValues(alpha: c.iAnchorAlpha),
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              text,
              style: TextStyle(
                fontSize: c.actionSize,
                height: c.lineHeight,
                fontStyle: FontStyle.italic,
                color: c.actionColor,
                fontFamily: c.fontFamily,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
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
    String? fullMessageText,
  }) {
    final userColor = context.watch<SpringRainChatColorController>().userColor;
    if (isCharacter) {
      return _buildCharacterBubble(
        text: text,
        isStreaming: isStreaming,
        messageId: messageId,
        attachmentsJson: attachmentsJson,
        bottomSpacing: characterBottomSpacing,
        fullMessageText: fullMessageText,
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

    final userBubbleKey = GlobalKey();
    final hasActions = userMessage != null && !_isSelecting;

    const c = SpringRainChatTokens.springRainDaydream;
    return Padding(
      padding: EdgeInsets.only(bottom: c.turnGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                key: userBubbleKey,
                behavior: HitTestBehavior.translucent,
                onLongPress: hasActions
                    ? () {
                        HapticFeedback.mediumImpact();
                        _showUserBubbleActionPopup(
                          messageId: messageId ?? '',
                          text: text,
                          bubbleKey: userBubbleKey,
                          userMessage: userMessage,
                        );
                      }
                    : null,
                onDoubleTap: userMessage != null && !_isSelecting
                    ? () => _recordMessage(userMessage)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (text.isNotEmpty)
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: c.userSize,
                          height: c.lineHeight,
                          fontWeight: c.userWeight,
                          letterSpacing: c.userLetterSpacing,
                          color: userColor,
                          fontFamily: c.fontFamily,
                          shadows: [
                            Shadow(
                              color: Colors.black
                                  .withValues(alpha: c.textShadow * 0.6),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    if (attachmentWidgets.isNotEmpty) ...[
                      if (text.isNotEmpty) const SizedBox(height: 8),
                      ...attachmentWidgets,
                    ],
                  ],
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
      // Strip TTS audio tags ([whispers], [sighs], (breath), etc.) from what
      // the user sees in chat bubbles. Tags are preserved on the TTS path.
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
        fullMessageText: text,
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
            fullMessageText: text,
          ),
        );
      }
    }

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final hasVisibleAfter = _hasVisibleSegmentsAfter(segments, i);
      if (segment.type == PersonaReplySegmentType.action) {
        children.add(_buildActionMessage(
          text: segment.text,
          messageId: messageId,
          fullMessageText: text,
        ));
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
        fullMessageText: text,
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
        if (att is! Map) continue;
        final type = att['type'] as String?;

        // Sticker attachments render from asset path, not base64.
        if (type == 'sticker') {
          final assetPath = att['assetPath'] as String?;
          if (assetPath == null || assetPath.isEmpty) continue;
          widgets.add(
            Padding(
              key: ValueKey('chat-sticker-$messageId-$i'),
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Image.asset(
                  assetPath,
                  width: 128,
                  height: 128,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          );
          continue;
        }

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

  Future<void> _openMessageRecallTrace(int selectedMessageId) async {
    final anchorId = personaChatRecallAnchorMessageId(
      messagesNewestFirst: _messages,
      selectedMessageId: selectedMessageId,
    );
    if (anchorId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showToast(
        _chatUiText(
          zh: '这条消息没有对应的用户对话轮次',
          en: 'This message is not linked to a user turn',
        ),
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final anchor =
        _messages.where((message) => message.id == anchorId).firstOrNull ??
            await _chatService.getMessageById(anchorId);
    if (anchor == null || !mounted) return;

    final sourceMessageId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MessageRecallTracePage(
          chatMessageId: anchorId,
          messagePreview: anchor.content,
        ),
      ),
    );
    if (sourceMessageId == null || !mounted) return;
    final source = _messages
            .where((message) => message.id == sourceMessageId)
            .firstOrNull ??
        await _chatService.getMessageById(sourceMessageId);
    if (source != null && mounted) {
      await _jumpToMessage(source);
    }
  }

  void _dismissBubblePopup() {
    _bubblePopupOverlay?.remove();
    _bubblePopupOverlay = null;
    if (_popupMessageId != null && mounted) {
      setState(() => _popupMessageId = null);
    } else {
      _popupMessageId = null;
    }
  }

  void _showUserBubbleActionPopup({
    required String messageId,
    required String text,
    required GlobalKey bubbleKey,
    required PersonaChatMessage userMessage,
  }) {
    _dismissBubblePopup();
    final key = bubbleKey;
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final bubbleSize = renderBox.size;
    final bubblePosition = renderBox.localToGlobal(Offset.zero);
    final token = HereIamThemeRuntime.current;

    _popupMessageId = messageId;
    _bubblePopupOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissBubblePopup,
            ),
          ),
          Positioned(
            left: bubblePosition.dx,
            top: bubblePosition.dy + bubbleSize.height + 6,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: token.surfaceSoft.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: token.accent.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BubblePopupAction(
                      icon: Icons.copy_rounded,
                      label: '复制',
                      onTap: () {
                        _dismissBubblePopup();
                        Clipboard.setData(ClipboardData(text: text));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    ),
                    _BubblePopupAction(
                      icon: Icons.manage_search_rounded,
                      label: '召回',
                      onTap: () {
                        _dismissBubblePopup();
                        unawaited(_openMessageRecallTrace(userMessage.id));
                      },
                    ),
                    _BubblePopupAction(
                      icon: Icons.undo_rounded,
                      label: '撤回',
                      onTap: () {
                        _dismissBubblePopup();
                        _confirmRetractUserMessage(userMessage);
                      },
                    ),
                    _BubblePopupAction(
                      icon: Icons.checklist_rounded,
                      label: '多选',
                      onTap: () {
                        _dismissBubblePopup();
                        setState(() {
                          _isSelecting = true;
                          _selectedMessageIds.add(userMessage.id);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_bubblePopupOverlay!);
  }

  void _showBubbleActionPopup({
    required String messageId,
    required String text,
    required GlobalKey bubbleKey,
  }) {
    _dismissBubblePopup();
    final key = bubbleKey;
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final bubbleSize = renderBox.size;
    final bubblePosition = renderBox.localToGlobal(Offset.zero);
    final token = HereIamThemeRuntime.current;
    final ttsMessageId = messageId.split(':').first;
    final isPlaying = _playingMessageId == ttsMessageId;

    _popupMessageId = messageId;
    _bubblePopupOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissBubblePopup,
            ),
          ),
          Positioned(
            left: bubblePosition.dx,
            top: bubblePosition.dy + bubbleSize.height + 6,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: token.surfaceSoft.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: token.accent.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BubblePopupAction(
                      icon: isPlaying
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                      label: isPlaying ? '停止' : '朗读',
                      accent: token.accent,
                      onTap: () {
                        _dismissBubblePopup();
                        _handleTtsPlay(ttsMessageId, text);
                      },
                    ),
                    _BubblePopupAction(
                      icon: Icons.copy_rounded,
                      label: '复制',
                      onTap: () {
                        _dismissBubblePopup();
                        Clipboard.setData(ClipboardData(text: text));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    ),
                    _BubblePopupAction(
                      icon: Icons.manage_search_rounded,
                      label: '召回',
                      onTap: () {
                        _dismissBubblePopup();
                        final msgId = int.tryParse(
                          messageId.split(':').first,
                        );
                        if (msgId != null) {
                          unawaited(_openMessageRecallTrace(msgId));
                        }
                      },
                    ),
                    _BubblePopupAction(
                      icon: Icons.checklist_rounded,
                      label: '多选',
                      onTap: () {
                        _dismissBubblePopup();
                        final msgId = int.tryParse(
                          messageId.split(':').first,
                        );
                        setState(() {
                          _isSelecting = true;
                          if (msgId != null) _selectedMessageIds.add(msgId);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_bubblePopupOverlay!);
  }

  Widget _buildCharacterBubble({
    required String text,
    required bool isStreaming,
    String? messageId,
    String? attachmentsJson,
    double bottomSpacing = 22,
    String? fullMessageText,
  }) {
    final hasActions = !isStreaming && messageId != null && !_isSelecting;
    final hasAddenda =
        attachmentsJson != null && attachmentsJson.trim().isNotEmpty;
    final bubbleKey = GlobalKey();

    const c = SpringRainChatTokens.springRainDaydream;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Padding(
        padding: EdgeInsets.only(left: c.iIndent - 10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: c.actionColor.withValues(alpha: c.iAnchorAlpha),
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 8),
          child: GestureDetector(
            key: bubbleKey,
            onLongPress: hasActions
                ? () {
                    HapticFeedback.mediumImpact();
                    _showBubbleActionPopup(
                      messageId: messageId,
                      text: fullMessageText ?? text,
                      bubbleKey: bubbleKey,
                    );
                  }
                : null,
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
                        onTapLink: (text, href, title) {
                          if (href == null) return;
                          final uri = Uri.tryParse(href);
                          if (uri == null ||
                              (!uri.isScheme('http') &&
                                  !uri.isScheme('https'))) {
                            return;
                          }
                          unawaited(launchUrl(uri,
                              mode: LaunchMode.externalApplication));
                        },
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
                    messageId: int.tryParse(messageId ?? ''),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    const c = SpringRainChatTokens.springRainDaydream;
    // Sit on i's axis: same right indent + gold anchor bar as a real i turn
    // (spec §3.2 / §22.8). No avatar, no bubble (spec §2.1 / §18) — just a
    // breathing droplet on the speaking point, so the first line of text
    // hands off seamlessly (anchor bar unbroken, same vertical band).
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.only(left: c.iIndent - 10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: c.actionColor.withValues(alpha: c.iAnchorAlpha),
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 8),
          child: const _RainBreathIndicator(),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return PersonaChatInputBar(
      controller: _textController,
      focusNode: _composerFocus,
      isStreaming: _isStreaming,
      onSend: _sendMessage,
      hintText: _isComposeMode
          ? '继续输入，暂存到连发队列'
          : UserStorage.l10n.personaChatInputHint,
      voiceController: _voiceController,
      onVoiceTap: _onVoiceToggle,
      isVoiceInputEnabled: _isInlineVoiceMode ? true : !_isVoiceReplyActive,
      isVoiceModeActive: _isInlineVoiceMode,
      isVoiceModeMicMuted: _isVoiceModeMicMuted,
      onVoiceModeTap: () => unawaited(_setInlineVoiceMode(!_isInlineVoiceMode)),
      onAddTap: widget.enableRichCapture
          ? () => setState(() => _isMediaTrayOpen = !_isMediaTrayOpen)
          : null,
      isAddActive: _isMediaTrayOpen,
      selectedImages: _selectedImages,
      onRemoveImage: _removeImage,
      isCompressing: _isCompressingImages,
      isComposeMode: _isComposeMode,
      composeDrafts: _composeBuffer,
      onStageDraft: _stageComposeDraft,
      onEditDraft: _editComposeDraft,
      onRemoveDraft: _removeComposeDraft,
      onSendBatch: _sendComposeBuffer,
      onExitComposeMode: () => setState(() {
        _isComposeMode = false;
        _composeBuffer.clear();
      }),
      onSendLongPress: _onSendLongPress,
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
  return message.id.toString();
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
    const chat = SpringRainChatTokens.springRainDaydream;

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
              'assets/images/spring_rain_daydream_chat_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
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
                    chat.background.withValues(alpha: 0.08),
                    chat.background.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.34, 0.68, 1],
                ),
              ),
            ),
          ),
        if (false) ...[
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
          // Background image shows through fully; no dark overlay so the
          // custom image is not masked at the bottom.
          const SizedBox.shrink()
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
                    Colors.transparent,
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

class _BubblePopupAction extends StatelessWidget {
  const _BubblePopupAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accent ?? Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: accent ?? Colors.white70,
              ),
            ),
          ],
        ),
      ),
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
    const c = SpringRainChatTokens.springRainDaydream;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: c.glassBlur, sigmaY: c.glassBlur),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.glassFill,
            border: Border.all(color: c.glassStroke, width: 1),
          ),
          child: IconTheme(
            data: IconThemeData(color: c.iColor),
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
    const c = SpringRainChatTokens.springRainDaydream;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: c.glassBlur, sigmaY: c.glassBlur),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    active ? c.glassFill.withValues(alpha: 0.14) : c.glassFill,
                border: Border.all(
                  color: active
                      ? const Color(0xFFA3A866).withValues(alpha: 0.5)
                      : c.glassStroke,
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: active ? const Color(0xFFA3A866) : c.iColor,
                ),
              ),
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
    this.focusNode,
    this.voiceController,
    this.onVoiceTap,
    this.isVoiceInputEnabled = true,
    this.onVoiceModeTap,
    this.isVoiceModeActive = false,
    this.isVoiceModeMicMuted = false,
    this.onAddTap,
    this.isAddActive = false,
    this.selectedImages = const [],
    this.onRemoveImage,
    this.isCompressing = false,
    this.isComposeMode = false,
    this.composeDrafts = const [],
    this.onStageDraft,
    this.onEditDraft,
    this.onRemoveDraft,
    this.onSendBatch,
    this.onExitComposeMode,
    this.onSendLongPress,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
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
  final bool isVoiceModeMicMuted;
  final VoidCallback? onAddTap;
  final bool isAddActive;

  /// Selected image attachments shown as inline preview chips.
  final List<XFile> selectedImages;
  final void Function(int index)? onRemoveImage;
  final bool isCompressing;

  // Compose mode (long-press send button to enter).
  final bool isComposeMode;
  final List<_ComposeDraft> composeDrafts;
  final VoidCallback? onStageDraft;
  final void Function(int index)? onEditDraft;
  final void Function(int index)? onRemoveDraft;
  final VoidCallback? onSendBatch;
  final VoidCallback? onExitComposeMode;
  final VoidCallback? onSendLongPress;

  bool _canSend(String value, bool hasImages) =>
      value.trim().isNotEmpty || hasImages;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final hasImages = selectedImages.isNotEmpty || isCompressing;
    final tokens = HereIamThemeRuntime.current;
    final isDark = tokens.brightness == Brightness.dark;
    const c = SpringRainChatTokens.springRainDaydream;

    return Padding(
      padding: EdgeInsets.fromLTRB(32, 10, 32, bottomPadding + 24),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final canSend = _canSend(value.text, selectedImages.isNotEmpty);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isComposeMode && composeDrafts.isNotEmpty) ...[
                _ComposeDraftTray(
                  drafts: composeDrafts,
                  onEdit: onEditDraft,
                  onRemove: onRemoveDraft,
                ),
                const SizedBox(height: 8),
              ],
              if (isComposeMode) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: onExitComposeMode,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Text(
                          '退出连发',
                          style: TextStyle(
                            color: _personaTextMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    if (composeDrafts.isNotEmpty)
                      GestureDetector(
                        onTap: isStreaming ? null : onSendBatch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _personaAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _personaAccent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            '一起发送 ${composeDrafts.length} 条',
                            style: TextStyle(
                              color: _personaAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
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
                              focusNode: focusNode,
                              minLines: 1,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: TextStyle(
                                  color: c.iColor.withValues(alpha: 0.45),
                                  fontSize: 15,
                                  fontFamily: c.fontFamily,
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
                                color: c.iColor,
                                fontFamily: c.fontFamily,
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
                                            : (isComposeMode
                                                ? 'send-compose'
                                                : 'send'),
                                      ),
                                      onSend: isComposeMode
                                          ? (onStageDraft ?? onSend)
                                          : onSend,
                                      onVoiceModeTap: onVoiceModeTap,
                                      showVoiceModeEnd: isVoiceModeActive,
                                      voiceController: voiceController,
                                      onVoiceTap: onVoiceTap,
                                      isVoiceModeMicMuted: isVoiceModeMicMuted,
                                      isComposeMode: isComposeMode,
                                      onLongPress: isStreaming
                                          ? null
                                          : () {
                                              // Long-press toggles compose mode
                                              // when not currently composing, or
                                              // stages the current input as a
                                              // draft and stays in compose mode
                                              // when already composing.
                                              if (isComposeMode) {
                                                if (canSend) {
                                                  onStageDraft?.call();
                                                }
                                              } else {
                                                onSendLongPress?.call();
                                              }
                                            },
                                    )
                                  : voiceController != null
                                      ? _ChatVoiceActions(
                                          key: const ValueKey('voice-actions'),
                                          voiceController: voiceController,
                                          onVoiceTap: onVoiceTap,
                                          onVoiceModeTap: onVoiceModeTap,
                                          isVoiceModeActive: isVoiceModeActive,
                                          isVoiceModeMicMuted:
                                              isVoiceModeMicMuted,
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
    const c = SpringRainChatTokens.springRainDaydream;
    return ClipRRect(
      borderRadius: BorderRadius.circular(27),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: c.glassBlur, sigmaY: c.glassBlur),
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            color: c.glassFill,
            border: Border.all(color: c.glassStroke),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
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
                  color: const Color(0xFF12160F).withValues(alpha: 0.5),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFF2CA70).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
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
    required this.isVoiceModeMicMuted,
  });

  final VoiceInputController? voiceController;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onVoiceModeTap;
  final bool isVoiceModeActive;
  final bool voiceInputEnabled;
  final bool voiceModeEnabled;
  final bool isVoiceModeMicMuted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (voiceController != null && onVoiceTap != null) ...[
          VoiceInputButton(
            controller: voiceController!,
            onTap: onVoiceTap!,
            iconColor: const Color(0xFFF5EEE0).withValues(alpha: 0.84),
            bgColor: const Color(0xFF12160F).withValues(alpha: 0.4),
            enabled: voiceInputEnabled,
            isMuted: isVoiceModeActive && isVoiceModeMicMuted,
            isCallMode: isVoiceModeActive,
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
    required this.voiceController,
    required this.onVoiceTap,
    required this.isVoiceModeMicMuted,
    this.isComposeMode = false,
    this.onLongPress,
  });

  final VoidCallback onSend;
  final VoidCallback? onVoiceModeTap;
  final bool showVoiceModeEnd;
  final VoiceInputController? voiceController;
  final VoidCallback? onVoiceTap;
  final bool isVoiceModeMicMuted;
  final bool isComposeMode;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (!showVoiceModeEnd || onVoiceModeTap == null) {
      return _SendButton(
        enabled: true,
        onTap: onSend,
        isComposeMode: isComposeMode,
        onLongPress: onLongPress,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SendButton(
          enabled: true,
          onTap: onSend,
          isComposeMode: isComposeMode,
          onLongPress: onLongPress,
        ),
        const SizedBox(width: 8),
        if (voiceController != null && onVoiceTap != null) ...[
          VoiceInputButton(
            controller: voiceController!,
            onTap: onVoiceTap!,
            iconColor: const Color(0xFFF5EEE0).withValues(alpha: 0.84),
            bgColor: const Color(0xFF12160F).withValues(alpha: 0.4),
            isMuted: isVoiceModeMicMuted,
            isCallMode: true,
          ),
          const SizedBox(width: 8),
        ],
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
                color: const Color(0xFF12160F).withValues(alpha: 0.5),
                border: Border.all(
                  color: active
                      ? const Color(0xFFF2CA70).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFFF2CA70,
                          ).withValues(alpha: 0.12),
                          blurRadius: 14,
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

/// Horizontal scrollable tray showing staged compose-mode drafts. Each draft
/// is a compact chip with edit (tap) and remove (long-press or the trailing
/// close icon) actions.
class _ComposeDraftTray extends StatelessWidget {
  const _ComposeDraftTray({
    required this.drafts,
    required this.onEdit,
    required this.onRemove,
  });

  final List<_ComposeDraft> drafts;
  final void Function(int index)? onEdit;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: drafts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final draft = drafts[index];
          final preview = draft.text.isEmpty
              ? (draft.images.isNotEmpty ? '[图片 ${draft.images.length}]' : '')
              : draft.text;
          return GestureDetector(
            onTap: onEdit == null ? null : () => onEdit!(index),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _personaAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _personaAccent.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _personaAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: _personaAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _personaText,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onRemove == null ? null : () => onRemove!(index),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: _personaTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onTap,
    this.isComposeMode = false,
    this.onLongPress,
  });

  final bool enabled;
  final VoidCallback onTap;
  final bool isComposeMode;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: isComposeMode ? 'Stage message' : 'Send message',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
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
                color: const Color(0xFF12160F).withValues(alpha: 0.5),
                border: Border.all(
                  color: enabled
                      ? const Color(0xFFF2CA70).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                  if (enabled)
                    BoxShadow(
                      color: const Color(0xFFF2CA70).withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: Offset.zero,
                    ),
                ],
              ),
              child: Center(
                child: isComposeMode
                    ? Icon(
                        Icons.add_rounded,
                        color: enabled
                            ? const Color(0xFFF6F0EF).withValues(alpha: 0.92)
                            : _personaTextMuted,
                        size: 22,
                      )
                    : _PaperPlaneIcon(
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
/// Typing indicator for the 春雨昼眠 (Spring Rain Daydream) skin.
///
/// Replaces the legacy framed-avatar + frosted-bubble + bouncing red dots,
/// which violated spec §2.1 (no chat bubbles) and §18 (no avatars). This is a
/// quiet, on-axis signal that "i is about to speak": a warm-ivory droplet that
/// breathes, ringed by faint raindrop ripples carrying directional light.
///
/// The ripple is deliberately NOT three animating circles. Each wavefront is a
/// soft glowing band with a cross-section falloff (inner shoulder → bright
/// crest → soft outer tail), so it reads as light refracted on a water crest
/// rather than a flat stroked circle; a top-bright / bottom-dim modulate pass
/// then lights every ring and the droplet from above (the 光影), and the core
/// droplet carries a small specular glint so it reads as a wet sphere.
class _RainBreathIndicator extends StatefulWidget {
  const _RainBreathIndicator();

  @override
  State<_RainBreathIndicator> createState() => _RainBreathIndicatorState();
}

class _RainBreathIndicatorState extends State<_RainBreathIndicator>
    with SingleTickerProviderStateMixin {
  /// One seamless master loop. Breathing completes 2 cycles per loop (period
  /// ~2.4s) and the ripple emits 3 wavefronts per loop (one every ~1.6s) —
  /// both inside the calm range settled on in design, and phase-locked so the
  /// loop never visibly restarts.
  static const int _loopMs = 4800;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _loopMs),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const c = SpringRainChatTokens.springRainDaydream;
    // Keep the layout height equal to one line of i text so the indicator and
    // the real first line occupy the same vertical band (no jump on handoff).
    // The ripple paints beyond this box — CustomPaint is unclipped by default.
    final lineHeight = c.iSize * c.lineHeight;
    return SizedBox(
      width: 44,
      height: lineHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size(44, lineHeight),
          painter: _RainRipplePainter(t: _controller.value, ivory: c.iColor),
        ),
      ),
    );
  }
}

class _RainRipplePainter extends CustomPainter {
  _RainRipplePainter({required this.t, required this.ivory});

  /// Master-loop phase, 0..1.
  final double t;

  /// i's text color (warm ivory #F5EEE0 @96%) — the droplet + ripple hue.
  final Color ivory;

  // --- tunables, kept together so the feel is easy to adjust ---
  static const double _dotCx =
      12; // inset a touch so the outer ripple clears the anchor bar
  static const double _dotBaseR = 3.1; // resting droplet radius
  static const double _breathAmp = 0.30; // ±30% radius swing while breathing
  static const int _breathCycles = 2; // breaths per master loop (~2.4s each)
  static const int _ringCount = 3; // wavefronts alive at once
  static const double _ringRStart = 5.0; // emitted just outside the droplet
  static const double _ringRMax = 18.0; // farthest reach before fading out
  static const double _ringWidth = 2.4; // crest band half-thickness
  static const double _ringPeakAlpha = 0.40; // brightest crest alpha
  static const double _lightTop = 1.0; // directional light: full at top
  static const double _lightBottom = 0.62; // …dimmer toward the bottom

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(_dotCx, size.height / 2);

    // Isolate the drawing in a layer so the directional-light pass modulates
    // only the ripple, never the app background behind it.
    canvas.saveLayer(
      Rect.fromLTWH(-40, -40, size.width + 80, size.height + 80),
      Paint(),
    );

    _drawRipples(canvas, center);
    _drawDroplet(canvas, center);
    _applyDirectionalLight(canvas, center);
    _drawSpecularGlint(canvas, center);

    canvas.restore();
  }

  /// Concentric glowing wavefronts. The leading one is brightest; each older
  /// one expands and decays. Cross-section gradient = inner shoulder, bright
  /// crest, soft outer tail — the core of the "lit water" look.
  void _drawRipples(Canvas canvas, Offset center) {
    for (var k = 0; k < _ringCount; k++) {
      // Evenly phase-offset emissions advancing with the master loop.
      final p = (t + k / _ringCount) % 1.0;
      final eased = 1 - math.pow(1 - p, 3).toDouble(); // easeOutCubic expand
      final r = _ringRStart + (_ringRMax - _ringRStart) * eased;
      // Ease in over the first sliver (no pop at the droplet edge), then fade
      // out as the wavefront dies.
      final fadeIn = (p / 0.12).clamp(0.0, 1.0);
      final fadeOut = math.pow(1 - p, 1.4).toDouble();
      final a = _ringPeakAlpha * fadeIn * fadeOut;
      if (a <= 0.003) continue;
      _drawGlowRing(canvas, center, r, a);
    }
  }

  void _drawGlowRing(Canvas canvas, Offset center, double r, double alpha) {
    final outer = r + _ringWidth * 2.2;
    final s = (r / outer).clamp(0.0, 1.0); // crest position as a gradient stop
    final hw = _ringWidth / outer; // crest half-width as a stop fraction

    // Strictly non-decreasing stops so RadialGradient never asserts.
    final stops = <double>[
      0.0,
      (s - hw * 1.8).clamp(0.0, 1.0),
      (s - hw * 0.4).clamp(0.0, 1.0),
      s,
      (s + hw * 0.7).clamp(0.0, 1.0),
      (s + hw * 2.0).clamp(0.0, 1.0),
      1.0,
    ];
    for (var i = 1; i < stops.length; i++) {
      if (stops[i] < stops[i - 1]) stops[i] = stops[i - 1];
    }
    final colors = <Color>[
      ivory.withValues(alpha: 0),
      ivory.withValues(alpha: 0),
      ivory.withValues(alpha: alpha * 0.40), // inner shoulder
      ivory.withValues(alpha: alpha), // bright crest
      ivory.withValues(alpha: alpha * 0.45), // outer shoulder
      ivory.withValues(alpha: 0),
      ivory.withValues(alpha: 0),
    ];
    final paint = Paint()
      ..shader = RadialGradient(colors: colors, stops: stops)
          .createShader(Rect.fromCircle(center: center, radius: outer));
    canvas.drawCircle(center, outer, paint);
  }

  /// The breathing warm-ivory droplet: a soft halo around a luminous core.
  void _drawDroplet(Canvas canvas, Offset center) {
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * _breathCycles * t);
    final r = _dotBaseR * (1 - _breathAmp + 2 * _breathAmp * breath);

    // Halo.
    final haloR = r * 3.4;
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          ivory.withValues(alpha: 0.22 + 0.16 * breath),
          ivory.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: haloR));
    canvas.drawCircle(center, haloR, halo);

    // Luminous core: a slightly whiter hot-center melting into ivory.
    final hot = Color.lerp(ivory, const Color(0xFFFFFFFF), 0.55)!;
    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          hot.withValues(alpha: 0.85),
          ivory.withValues(alpha: 0.78 + 0.14 * breath),
          ivory.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.7));
    canvas.drawCircle(center, r * 1.7, core);
  }

  /// Top-bright / bottom-dim multiply pass — the directional light that gives
  /// the ripple and droplet volume (lit from above).
  void _applyDirectionalLight(Canvas canvas, Offset center) {
    final rect = Rect.fromCircle(center: center, radius: _ringRMax + 8);
    final top = (0xFF * _lightTop).round().clamp(0, 255);
    final bottom = (0xFF * _lightBottom).round().clamp(0, 255);
    final light = Paint()
      ..blendMode = BlendMode.modulate
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.fromARGB(255, top, top, top),
          Color.fromARGB(255, bottom, bottom, bottom),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, light);
  }

  /// A tiny wet-highlight glint on the upper-left of the droplet. Drawn after
  /// the light pass so it stays a pure, undimmed specular point.
  void _drawSpecularGlint(Canvas canvas, Offset center) {
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * _breathCycles * t);
    final r = _dotBaseR * (1 - _breathAmp + 2 * _breathAmp * breath);
    final glint = Offset(center.dx - r * 0.32, center.dy - r * 0.38);
    final gr = r * 0.5;
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6)
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFFFFF).withValues(alpha: 0.55 + 0.25 * breath),
          const Color(0xFFFFFFFF).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: glint, radius: gr));
    canvas.drawCircle(glint, gr, paint);
  }

  @override
  bool shouldRepaint(_RainRipplePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.ivory != ivory;
}

class _TopicThreadPickerSheet extends StatelessWidget {
  const _TopicThreadPickerSheet({
    required this.threads,
    required this.onSelected,
  });

  final List<TopicThread> threads;
  final ValueChanged<TopicThread> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: _personaPanel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: threads.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final t = threads[i];
            return ListTile(
              title: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _personaText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  )),
              subtitle: Text(
                '${t.currentStage.isEmpty ? '暂无阶段' : t.currentStage}'
                '${t.tags.isNotEmpty ? ' · ${t.tags}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _personaTextMuted, fontSize: 12),
              ),
              onTap: () => onSelected(t),
            );
          },
        ),
      ),
    );
  }
}
