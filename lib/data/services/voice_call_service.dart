import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/asr/alibaba_asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/conversation_capture_service.dart';
import 'package:memex/data/services/tts_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/voice_call_dao.dart';
import 'package:memex/utils/logger.dart';

enum VoiceCallState {
  connecting,
  companionSpeaking,
  listening,
  userRecording,
  userProcessing,
  companionThinking,
  ended,
}

enum VoiceCallDirection {
  userToCompanion,
  companionToUser,
}

enum VoiceCallInputMode {
  pushToTalk,
  streaming,
}

/// A single spoken turn stored in memory for transcript display and DB write.
class CallTurn {
  final String role; // 'user' or 'companion'
  final String text;
  final DateTime time;
  const CallTurn({required this.role, required this.text, required this.time});
}

/// Orchestrates the full voice call pipeline.
///
/// PTT (tap-to-toggle) → ASR → CompanionAgent.run() → sentence-TTS → repeat.
/// Transcript is persisted to VoiceCallMessages; post-call summary written to
/// character memory.
class VoiceCallService extends ChangeNotifier {
  static final Logger _logger = getLogger('VoiceCallService');
  static const _uuid = Uuid();
  static final AudioContext _playbackAudioContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: true,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {AVAudioSessionOptions.defaultToSpeaker},
    ),
  );

  final LLMClient client;
  final ModelConfig modelConfig;
  final String userId;
  final String characterId;
  final String? voiceId;
  final VoiceCallDao callDao;
  final VoiceCallDirection direction;

  VoiceCallState _state = VoiceCallState.connecting;
  String? _error;
  String? _lastLine; // current/last spoken text for subtitle display
  final List<CallTurn> _transcript = [];
  String? _sessionId;

  StatefulAgent? _agent;
  final _player = AudioPlayer();
  final _recorder = AudioRecorder();
  String? _recordingPath;
  bool _speaking = false;
  VoiceCallInputMode _inputMode = VoiceCallInputMode.pushToTalk;
  StreamSubscription<Uint8List>? _streamingAudioSub;
  final List<int> _streamingSpeechBuffer = [];
  bool _streamingSpeechActive = false;
  int _streamingSilenceMs = 0;
  int _streamingSpeechMs = 0;
  bool _streamingCommitInFlight = false;
  bool _streamingCaptureStarting = false;
  static const double _streamingSpeechRmsThreshold = 0.012;
  static const int _streamingEndSilenceMs = 900;
  static const int _streamingMinSpeechMs = 450;
  static const int _streamingMaxSpeechMs = 12000;

  // Idle follow-up: when the user stays silent in [listening], the companion
  // proactively speaks again ("怎么不说话了？" / continue the topic / lull to
  // sleep). After too many unanswered follow-ups, the call ends gracefully.
  Timer? _idleTimer;
  int _consecutiveFollowUps = 0;
  bool _pendingEndCall = false; // set by the end_call tool
  static const Duration _idleTimeout = Duration(seconds: 80);
  static const int _maxFollowUps = 4; // after this many → force graceful end

  VoiceCallState get state => _state;
  VoiceCallInputMode get inputMode => _inputMode;
  bool get isStreamingMode => _inputMode == VoiceCallInputMode.streaming;
  bool get isStreamingCaptureActive => _streamingAudioSub != null;
  String get streamingDraft => _streamingCommitInFlight ? '识别中...' : '';
  String? get error => _error;
  String? get lastLine => _lastLine;
  List<CallTurn> get transcript => List.unmodifiable(_transcript);

  VoiceCallService({
    required this.client,
    required this.modelConfig,
    required this.userId,
    required this.characterId,
    required this.callDao,
    this.voiceId,
    this.direction = VoiceCallDirection.userToCompanion,
  });

  // ---------------------------------------------------------------------------
  // Start / greeting
  // ---------------------------------------------------------------------------

  Future<void> start({String? openingMessage}) async {
    _sessionId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await callDao.createSession(
      VoiceCallSessionsCompanion.insert(
        id: _sessionId!,
        characterId: characterId,
        userId: userId,
        startedAt: now,
      ),
    );

    _agent = await CompanionAgent.createForVoiceCall(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
      characterId: characterId,
      extraTools: [_buildEndCallTool()],
    );
    // Voice-call mode: no action text or parenthetical thoughts.
    _agent?.state.systemReminders['voice_call_mode'] =
        '## VOICE CALL MODE (active)\n'
        'This is a live voice call. Your words are spoken aloud via TTS. Rules:\n'
        '- NO action text (*nods*, *laughs*, etc.)\n'
        '- NO parenthetical thoughts （...） or (...)\n'
        '- NO markdown formatting (no **, *, #, >, `)\n'
        '- Speak naturally as if on a phone call\n'
        '- Keep responses short and conversational\n'
        '\n'
        '## Silence & ending the call\n'
        '- If the user goes quiet, you may receive a system note saying they have\n'
        '  been silent. React like a real person on a phone: gently ask if they\n'
        '  are still there, or keep the conversation going — vary your wording.\n'
        '- BEDTIME / lulling to sleep: if the user wants you to help them sleep,\n'
        '  keep speaking softly and continuously. Every so often, check quietly\n'
        '  whether they are still awake ("还醒着吗？"). When they have clearly\n'
        '  fallen asleep (no response for a while), say a soft goodnight and call\n'
        '  the `end_call` tool to hang up.\n'
        '- Call `end_call` whenever the conversation has naturally ended or the\n'
        '  user has clearly left or fallen asleep. Say your farewell in your\n'
        '  spoken reply first, THEN call end_call.';
    _agent?.state.systemReminders['voice_call_direction'] =
        direction == VoiceCallDirection.companionToUser
            ? '## CALL DIRECTION\n'
                'You initiated this call to the user. The user answered your '
                'incoming call. Never ask why they called you or imply that '
                'they initiated the call. Continue naturally from your reason '
                'for reaching out.'
            : '## CALL DIRECTION\n'
                'The user initiated this call to you. You answered their call. '
                'Greet them naturally and let them lead with why they called.';

    String? greeting =
        (openingMessage?.trim().isEmpty ?? true) ? null : openingMessage;

    if (greeting == null) {
      _state = VoiceCallState.companionThinking;
      notifyListeners();
      greeting = await _generateGreeting();
    }

    if (greeting != null && greeting.isNotEmpty) {
      await _speakAndRecord('companion', greeting);
    }

    if (_pendingEndCall) {
      await _autoEndCall();
      return;
    }
    if (_state != VoiceCallState.ended) {
      _enterListening();
    }
  }

  Future<String?> _generateGreeting() async {
    if (_agent == null) return null;
    try {
      final history = await _agent!.run(
        [
          UserMessage([
            TextPart(
              direction == VoiceCallDirection.companionToUser
                  ? '[The user answered your incoming call. You called them. '
                      'Open naturally with your reason for reaching out. Never '
                      'ask why they called you. One or two conversational '
                      'sentences, spoken words only.]'
                  : '[You answered the user\'s call. Greet them naturally, as '
                      'if you just picked up the phone. One or two '
                      'conversational sentences, spoken words only.]',
            ),
          ])
        ],
        useStream: false,
      );
      for (final msg in history.reversed) {
        if (msg is ModelMessage) {
          final t = msg.textOutput ?? '';
          if (t.trim().isNotEmpty) return t.trim();
        }
      }
    } catch (e) {
      _logger.warning('_generateGreeting: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // PTT — tap to start, tap again to stop
  // ---------------------------------------------------------------------------

  Future<void> toggleRecording() async {
    if (isStreamingMode) {
      await toggleStreamingMode();
      return;
    }
    if (_state == VoiceCallState.companionSpeaking) {
      await interruptSpeech();
      return;
    }
    if (_state == VoiceCallState.listening) {
      await _startRecording();
    } else if (_state == VoiceCallState.userRecording) {
      await _stopRecording();
    }
  }

  Future<void> toggleStreamingMode() async {
    if (isStreamingMode) {
      _inputMode = VoiceCallInputMode.pushToTalk;
      await _stopStreamingCapture(discardDraft: true);
      if (_state == VoiceCallState.listening) {
        _startIdleTimer();
      }
      notifyListeners();
      return;
    }

    _inputMode = VoiceCallInputMode.streaming;
    _error = null;
    _consecutiveFollowUps = 0;
    if (_state == VoiceCallState.userRecording) {
      await cancelRecording();
    }
    if (_state == VoiceCallState.listening) {
      await _startStreamingCapture();
    } else {
      notifyListeners();
    }
  }

  Future<void> interruptSpeech() async {
    if (!_speaking) return;
    _speaking = false;
    await _player.stop().catchError((_) => null);
    // User is taking over — start recording right away.
    await _startRecording();
  }

  Future<void> cancelRecording() async {
    if (_state != VoiceCallState.userRecording) return;
    try {
      await _recorder.stop();
    } catch (e) {
      _logger.warning('cancelRecording: $e');
    }
    final path = _recordingPath;
    _recordingPath = null;
    if (path != null) _deleteFile(path);
    _enterListening();
  }

  Future<void> _startRecording() async {
    _error = null;
    if (isStreamingMode) return;
    _cancelIdleTimer();
    // Any user action resets the unanswered-follow-up counter.
    _consecutiveFollowUps = 0;
    if (!await _recorder.hasPermission()) {
      _error = '麦克风权限未授予';
      notifyListeners();
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'voice_call_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
            audioManagerMode: AudioManagerMode.modeNormal,
          ),
        ),
        path: path,
      );
      _recordingPath = path;
      _state = VoiceCallState.userRecording;
      notifyListeners();
    } catch (e) {
      _error = '启动录音失败: $e';
      _logger.warning('_startRecording: $e');
      notifyListeners();
    }
  }

  Future<void> _stopRecording() async {
    _state = VoiceCallState.userProcessing;
    notifyListeners();

    String? recorded;
    try {
      recorded = await _recorder.stop();
    } catch (e) {
      _logger.warning('_stopRecording: $e');
      _enterListening();
      return;
    }

    final path = recorded ?? _recordingPath;
    _recordingPath = null;
    if (path == null) {
      _enterListening();
      return;
    }

    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1024) {
      _deleteFile(path);
      _enterListening();
      return;
    }

    try {
      final config = await AsrConfig.load();
      if (config == null) {
        _error = 'ASR 未配置，请在设置 → 语音输入中填写阿里 NLS 凭证';
        _deleteFile(path);
        _enterListening();
        return;
      }
      final text = await AlibabaAsrClient(config).recognize(file);
      _deleteFile(path);
      if (text.trim().isEmpty) {
        _enterListening();
        return;
      }
      await _onUserTurn(text.trim());
    } catch (e) {
      _logger.warning('ASR: $e');
      _deleteFile(path);
      _enterListening();
    }
  }

  // ---------------------------------------------------------------------------
  // Agent turn
  // ---------------------------------------------------------------------------

  Future<void> _onUserTurn(String userText) async {
    if (_state == VoiceCallState.ended) return;
    if (_agent == null) return;

    _cancelIdleTimer();
    _consecutiveFollowUps = 0; // user spoke — reset silence counter
    await _stopStreamingCapture(discardDraft: true);
    await _recordTurn('user', userText);

    _state = VoiceCallState.companionThinking;
    notifyListeners();

    try {
      final history = await _agent!.run(
        [
          UserMessage([TextPart(userText)])
        ],
        useStream: false,
      );
      if (_state == VoiceCallState.ended) return;

      final response = _extractText(history);
      if (response.isNotEmpty) {
        await _speakAndRecord('companion', response);
      }
    } catch (e) {
      _logger.warning('agent turn: $e');
    }

    if (_pendingEndCall) {
      await _autoEndCall();
      return;
    }
    if (_state != VoiceCallState.ended) {
      _enterListening();
    }
  }

  // ---------------------------------------------------------------------------
  // Idle follow-up — companion speaks again after user silence
  // ---------------------------------------------------------------------------

  void _enterListening() {
    if (_state == VoiceCallState.ended) return;
    // If the user is currently recording (via interruptSpeech), don't override
    // their recording state. The speech call chain (_speakAndRecord →
    // _speakText) returns asynchronously after interruption, and its caller
    // unconditionally calls _enterListening(). Without this guard, the button
    // flashes red (userRecording) then immediately back to blue (listening).
    if (_state == VoiceCallState.userRecording) return;
    _state = VoiceCallState.listening;
    notifyListeners();
    if (isStreamingMode) {
      unawaited(_startStreamingCapture());
    }
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () => unawaited(_onIdleTimeout()));
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<void> _onIdleTimeout() async {
    if (_state != VoiceCallState.listening) return;
    _consecutiveFollowUps++;
    final forceClose = _consecutiveFollowUps > _maxFollowUps;
    await _runFollowUpTurn(forceClose: forceClose);
  }

  Future<void> _runFollowUpTurn({bool forceClose = false}) async {
    if (_state == VoiceCallState.ended || _agent == null) return;
    _cancelIdleTimer();
    await _stopStreamingCapture(discardDraft: true);
    _state = VoiceCallState.companionThinking;
    notifyListeners();

    final prompt = forceClose
        ? _forceCloseFollowUpPrompt()
        : _idleFollowUpPrompt(_consecutiveFollowUps);

    try {
      final history = await _agent!.run(
        [
          UserMessage([TextPart(prompt)])
        ],
        useStream: false,
      );
      if (_state == VoiceCallState.ended) return;
      final response = _extractText(history);
      if (response.isNotEmpty) {
        await _speakAndRecord('companion', response);
      }
    } catch (e) {
      _logger.warning('follow-up turn: $e');
    }

    if (forceClose || _pendingEndCall) {
      await _autoEndCall();
      return;
    }
    if (_state != VoiceCallState.ended) {
      _enterListening();
    }
  }

  String _idleFollowUpPrompt(int n) =>
      '[用户已经沉默了一会儿（这是第 $n 次没有回应）。像真人打电话时一样自然反应：'
      '轻声问问对方怎么了、是不是走神了、还在不在听，或者顺着刚才的话题继续说下去——'
      '换一种说法，不要重复之前说过的。如果你判断对方可能睡着了或离开了，温柔地说句话'
      '并调用 end_call 结束通话。只说你要说的话，简短自然，不要描述动作。]';

  String _forceCloseFollowUpPrompt() =>
      '[用户已经很久没有回应了，很可能睡着了或离开了。温柔地说一句简短的告别或晚安。'
      '说完之后这通电话就会自动挂断。只说告别的话，简短自然，不要描述动作。]';

  String _extractText(List<LLMMessage> history) {
    for (final msg in history.reversed) {
      if (msg is ModelMessage) {
        final t = msg.textOutput ?? '';
        if (t.trim().isNotEmpty) return t;
      }
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // TTS
  // ---------------------------------------------------------------------------

  Future<void> _speakAndRecord(String role, String text) async {
    final clean = _stripMarkdown(text);
    if (clean.isEmpty) return;
    if (role == 'companion') await _recordTurn(role, clean);
    await _speakText(clean);
  }

  Future<void> _speakText(String text) async {
    if (voiceId == null || voiceId!.isEmpty) return;
    final spokenText = _normalizeTtsText(text);
    if (spokenText.isEmpty) return;

    await _stopStreamingCapture(discardDraft: true);
    _speaking = true;
    try {
      if (!_speaking || _state == VoiceCallState.ended) return;

      _state = VoiceCallState.companionSpeaking;
      _lastLine = spokenText;
      notifyListeners();

      try {
        final path = await TtsService.textToSpeech(
          text: spokenText,
          voiceId: voiceId!,
        );
        if (!_speaking || _state == VoiceCallState.ended) return;
        await _playTtsFile(path, spokenText: spokenText);
      } catch (e) {
        _logger.warning('TTS error: $e');
      }
    } finally {
      _speaking = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Transcript persistence
  // ---------------------------------------------------------------------------

  Future<void> _recordTurn(String role, String text) async {
    final now = DateTime.now();
    _transcript.add(CallTurn(role: role, text: text, time: now));
    if (_sessionId == null) return;
    try {
      await callDao.addMessage(
        VoiceCallMessagesCompanion.insert(
          sessionId: _sessionId!,
          role: role,
          content: text,
          createdAt: now.millisecondsSinceEpoch ~/ 1000,
        ),
      );
    } catch (e) {
      _logger.warning('addMessage: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Hangup & post-call summary
  // ---------------------------------------------------------------------------

  /// Build the tool the companion calls to hang up on its own (e.g. once it
  /// judges the user has fallen asleep). It just flips a flag; the service
  /// speaks any farewell text first, then ends the call.
  Tool _buildEndCallTool() {
    return Tool(
      name: 'end_call',
      description:
          'End the current voice call. Call this when the conversation has '
          'naturally finished, or when the user has clearly left or fallen '
          'asleep. Say your goodbye in your spoken reply FIRST, then call this.',
      parameters: {
        'type': 'object',
        'properties': {
          'reason': {
            'type': 'string',
            'description': 'Brief reason (e.g. "user asleep", "said goodbye").',
          },
        },
        'required': <String>[],
      },
      executable: (String? reason) async {
        _pendingEndCall = true;
        _logger.info('end_call requested: $reason');
        return 'Call will end after your farewell is spoken.';
      },
    );
  }

  /// User-initiated hangup (tapping the red button).
  void hangUp() {
    _cancelIdleTimer();
    unawaited(_stopStreamingCapture(discardDraft: true));
    _speaking = false;
    _state = VoiceCallState.ended;
    notifyListeners();
    _player.stop().catchError((_) => null);
    _recorder.stop().catchError((_) => null);
    unawaited(_finalizeSession());
  }

  /// Companion-initiated graceful hangup (via end_call tool or follow-up cap).
  /// The farewell has already been spoken by the caller.
  Future<void> _autoEndCall() async {
    if (_state == VoiceCallState.ended) return;
    _cancelIdleTimer();
    await _stopStreamingCapture(discardDraft: true);
    _speaking = false;
    await _player.stop().catchError((_) => null);
    await _recorder.stop().catchError((_) => null);
    _state = VoiceCallState.ended;
    notifyListeners(); // screen listens for `ended` and pops the route
    await _finalizeSession();
  }

  Future<void> _finalizeSession() async {
    if (_sessionId == null) return;
    final endedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Compute call duration.
    final startTs =
        _transcript.isNotEmpty ? _transcript.first.time : DateTime.now();
    final durationSec = endedAt - startTs.millisecondsSinceEpoch ~/ 1000;
    final durStr = _formatDuration(durationSec);

    // B plan: LLM extracts key facts → MemoryWrite + returns summary text.
    String? summary;
    if (_transcript.length >= 2 && _agent != null) {
      summary = await _buildPostCallSummary();
    }

    // Persist session end + summary to DB.
    try {
      await callDao.endSession(_sessionId!, endedAt: endedAt, summary: summary);
    } catch (e) {
      _logger.warning('endSession: $e');
    }

    // ALWAYS write a PersonaChatMessage so the timeline.jsonl is updated.
    // This is what makes future agent sessions (text chat AND voice call) aware
    // that a call happened. Without this, the companion has no memory of it.
    try {
      final callRecord = _buildCallRecord(durStr, summary);
      await PersonaChatService.instance.addCharacterMessage(
        characterId,
        callRecord,
        timestamp: DateTime.now(),
        isRead: true, // already seen — no unread badge
      );
      if (ConversationCaptureService.isInitialized) {
        await ConversationCaptureService.instance.noteConversationActivity(
          userId: userId,
          characterId: characterId,
          force: true,
          trigger: 'voice_call_end',
        );
      }
      _logger.info('Call record written to PersonaChatMessages: $callRecord');
    } catch (e) {
      _logger.warning('write call record: $e');
    }
  }

  String _buildCallRecord(String duration, String? summary) {
    if (summary != null && summary.trim().isNotEmpty) {
      return '（📞 语音通话 $duration）$summary';
    }
    if (_transcript.isEmpty) {
      return '（📞 语音通话 — 未说话）';
    }
    return '（📞 语音通话 $duration）';
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '$m分$s秒' : '$m分钟';
  }

  Future<String?> _buildPostCallSummary() async {
    if (_agent == null || _transcript.isEmpty) return null;
    final transcriptText = _transcript
        .map((t) => '${t.role == 'user' ? '用户' : '角色'}: ${t.text}')
        .join('\n');
    try {
      final history = await _agent!.run(
        [
          UserMessage([
            TextPart(
              '[通话结束。请根据以下通话记录，做两件事：\n'
              '1. 用 MemoryWrite 将关键事实性内容写入角色记忆（用户说的重要信息、'
              '   决定、情绪状态 — 不要记过渡语和废话）。\n'
              '2. 用一两句话总结本次通话的核心内容，直接返回那段文字，不要其他说明。\n\n'
              '通话记录：\n$transcriptText',
            ),
          ]),
        ],
        useStream: false,
      );
      for (final msg in history.reversed) {
        if (msg is ModelMessage) {
          final t = msg.textOutput ?? '';
          if (t.trim().isNotEmpty) return t.trim();
        }
      }
    } catch (e) {
      _logger.warning('post-call summary: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*{1,3}|_{1,3}'), '')
        .replaceAll(RegExp(r'`+'), '')
        .replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'（[^）]{0,40}）'), '') // 中文括号心理活动
        .replaceAll(RegExp(r'\([^)]{0,40}\)'), '') // 英文括号
        .trim();
  }

  static String _normalizeTtsText(String text) {
    final parts = text.split(RegExp(r'(?<=[。！？!?；;\n])\s*'));
    if (parts.isEmpty && text.isNotEmpty) return text.trim();
    return text.replaceAll(RegExp(r'\s*\n+\s*'), ' ').trim();
  }

  Future<void> _playTtsFile(
    String audioPath, {
    required String spokenText,
  }) async {
    await _applyPlaybackAudioContext();
    if (!_speaking || _state == VoiceCallState.ended) return;
    try {
      await _player.play(DeviceFileSource(audioPath));
      await _player.onPlayerComplete.first.timeout(
        _playbackTimeout(spokenText),
      );
    } on TimeoutException {
      _logger.warning('TTS playback timed out; recovering call state');
      await _player.stop().catchError((_) => null);
    }
  }

  static Duration _playbackTimeout(String text) {
    final estimatedSeconds = (text.trim().length / 3.0).ceil() + 12;
    return Duration(seconds: estimatedSeconds.clamp(20, 180));
  }

  Future<void> _applyPlaybackAudioContext() async {
    try {
      await _player.setAudioContext(_playbackAudioContext);
    } catch (e) {
      _logger.fine('Playback audio context skipped: $e');
    }
  }

  void _deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.delete();
    } catch (_) {}
  }

  Future<void> _startStreamingCapture() async {
    if (!isStreamingMode ||
        _state != VoiceCallState.listening ||
        _streamingAudioSub != null ||
        _streamingCaptureStarting ||
        _streamingCommitInFlight) {
      return;
    }

    _streamingCaptureStarting = true;
    _error = null;
    try {
      final asrConfig = await AsrConfig.load();
      if (asrConfig == null) {
        _error = 'ASR 未配置，请在设置 → 语音输入中填写阿里 NLS 凭证';
        _inputMode = VoiceCallInputMode.pushToTalk;
        notifyListeners();
        return;
      }
      if (!await _recorder.hasPermission()) {
        _error = '麦克风权限未授予';
        _inputMode = VoiceCallInputMode.pushToTalk;
        notifyListeners();
        return;
      }

      _resetStreamingSpeechBuffer();
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
            audioManagerMode: AudioManagerMode.modeNormal,
          ),
        ),
      );
      _streamingAudioSub = audioStream.listen(
        _handleStreamingAudioChunk,
        onError: (Object e, StackTrace st) {
          _logger.warning('streaming audio: $e');
          _error = '流式录音中断: $e';
          unawaited(_stopStreamingCapture(discardDraft: true));
          notifyListeners();
        },
      );
      notifyListeners();
    } catch (e) {
      _logger.warning('_startStreamingCapture: $e');
      _error = '启动流式语音失败: $e';
      _inputMode = VoiceCallInputMode.pushToTalk;
      await _stopStreamingCapture(discardDraft: true);
      notifyListeners();
    } finally {
      _streamingCaptureStarting = false;
    }
  }

  void _handleStreamingAudioChunk(Uint8List chunk) {
    if (_streamingCommitInFlight ||
        !isStreamingMode ||
        _state != VoiceCallState.listening) {
      return;
    }

    final durationMs = _pcmChunkDurationMs(chunk.length);
    final isSpeech = _pcmRms(chunk) >= _streamingSpeechRmsThreshold;
    if (isSpeech) {
      _streamingSpeechActive = true;
      _streamingSilenceMs = 0;
    }
    if (!_streamingSpeechActive) return;

    _streamingSpeechBuffer.addAll(chunk);
    _streamingSpeechMs += durationMs;
    if (!isSpeech) {
      _streamingSilenceMs += durationMs;
    }

    final shouldCommit = (_streamingSpeechMs >= _streamingMinSpeechMs &&
            _streamingSilenceMs >= _streamingEndSilenceMs) ||
        _streamingSpeechMs >= _streamingMaxSpeechMs;
    if (shouldCommit) {
      unawaited(_commitStreamingSpeechBuffer());
    }
  }

  Future<void> _commitStreamingSpeechBuffer() async {
    if (_streamingCommitInFlight ||
        !isStreamingMode ||
        _state != VoiceCallState.listening) {
      return;
    }

    if (_streamingSpeechMs < _streamingMinSpeechMs ||
        _streamingSpeechBuffer.isEmpty) {
      _resetStreamingSpeechBuffer();
      return;
    }

    _streamingCommitInFlight = true;
    final pcmBytes = Uint8List.fromList(_streamingSpeechBuffer);
    _resetStreamingSpeechBuffer();
    notifyListeners();
    await _stopStreamingCapture(discardDraft: false);
    try {
      final text = await _recognizeStreamingPcm(pcmBytes);
      if (text.trim().isNotEmpty) {
        await _onUserTurn(text.trim());
      }
    } catch (e) {
      _logger.warning('streaming ASR: $e');
      _error = '流式语音识别失败: $e';
      notifyListeners();
    } finally {
      _streamingCommitInFlight = false;
      if (isStreamingMode && _state == VoiceCallState.listening) {
        unawaited(_startStreamingCapture());
      }
    }
  }

  Future<void> _stopStreamingCapture({required bool discardDraft}) async {
    final sub = _streamingAudioSub;
    _streamingAudioSub = null;
    if (sub != null) {
      await sub.cancel().catchError((_) {});
    }
    await _recorder.stop().catchError((_) => null);
    if (discardDraft) {
      _resetStreamingSpeechBuffer();
    }
  }

  Future<String> _recognizeStreamingPcm(Uint8List pcmBytes) async {
    final config = await AsrConfig.load();
    if (config == null) {
      throw Exception('ASR 未配置');
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'voice_call_stream_\${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    final file = File(path);
    await file.writeAsBytes(_buildPcmWavBytes(pcmBytes));
    try {
      return await AlibabaAsrClient(config).recognize(file);
    } finally {
      _deleteFile(path);
    }
  }

  void _resetStreamingSpeechBuffer() {
    _streamingSpeechBuffer.clear();
    _streamingSpeechActive = false;
    _streamingSilenceMs = 0;
    _streamingSpeechMs = 0;
  }

  static int _pcmChunkDurationMs(int byteLength) {
    return (byteLength * 1000 / 32000).round().clamp(1, 10000);
  }

  static double _pcmRms(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return 0;
    final aligned = Uint8List.fromList(pcmBytes);
    final samples = Int16List.view(aligned.buffer);
    if (samples.isEmpty) return 0;

    var sumSquares = 0.0;
    for (final sample in samples) {
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
    }
    return sqrt(sumSquares / samples.length);
  }

  static Uint8List _buildPcmWavBytes(Uint8List pcmBytes) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = pcmBytes.length;
    final bytes = Uint8List(44 + dataSize);
    final data = ByteData.sublistView(bytes);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * channels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, channels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    bytes.setRange(44, bytes.length, pcmBytes);
    return bytes;
  }

  @override
  void dispose() {
    _cancelIdleTimer();
    unawaited(_stopStreamingCapture(discardDraft: true));
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }
}
