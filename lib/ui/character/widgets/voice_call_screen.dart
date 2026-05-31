import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/data/services/callkit_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/voice_call_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

const _callBg = Color(0xFF0A0C10);
const _callSurface = Color(0xFF161820);
const _callText = Color(0xFFF0EBE0);
const _callMuted = Color(0xFF6E6A63);
const _callAccent = Color(0xFFD4C9B0);
const _callRed = Color(0xFFE05252);
const _callGreen = Color(0xFF4CAF8A);
const _callBlue = Color(0xFF5B9FD4);

// ─────────────────────────────────────────────────────────────────────────────
// Entry-point screen
// ─────────────────────────────────────────────────────────────────────────────

class VoiceCallScreen extends StatefulWidget {
  final String characterId;
  const VoiceCallScreen({super.key, required this.characterId});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  CharacterModel? _character;
  VoiceCallService? _service;
  bool _loading = true;
  String? _loadError;
  bool _subtitlesOn = true;
  bool _popped = false; // guard against double-pop

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _pulseAnim =
      Tween<double>(begin: 0.88, end: 1.0).animate(
    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final userId = await UserStorage.getUserId() ?? '';
      final character = await CharacterService.instance.getCharacter(
        userId,
        widget.characterId,
      );
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.checkinAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

      // Consume any AI-initiated call opening from KVStore.
      final pending = await readPendingCall();
      final openingMessage = pending?.opening;
      await clearPendingCall();

      final service = VoiceCallService(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: widget.characterId,
        voiceId: character?.ttsVoiceId,
        callDao: AppDatabase.instance.voiceCallDao,
      );

      if (!mounted) {
        service.dispose();
        return;
      }

      // Auto-pop when the companion ends the call on its own.
      service.addListener(_onServiceChanged);

      setState(() {
        _character = character;
        _service = service;
        _loading = false;
      });

      unawaited(service.start(openingMessage: openingMessage));
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _loading = false; });
    }
  }

  @override
  void dispose() {
    // Safety net: ensure no stale CallKit "ongoing call" notification survives
    // after the in-app call screen closes.
    CallkitService.instance.endAll();
    _service?.removeListener(_onServiceChanged);
    _service?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Pops the route when the call ends — covers both the red button and the
  /// companion's own end_call (e.g. after lulling the user to sleep).
  void _onServiceChanged() {
    if (_popped) return;
    if (_service?.state == VoiceCallState.ended) {
      _popped = true;
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  void _hangUp() {
    // Sets state to ended → _onServiceChanged pops the route.
    _service?.hangUp();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _callBg,
        body: Center(child: CircularProgressIndicator(color: _callAccent)),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _callBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, style: const TextStyle(color: _callMuted)),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回', style: TextStyle(color: _callAccent)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _service!,
      child: _CallContent(
        character: _character,
        pulseAnim: _pulseAnim,
        subtitlesOn: _subtitlesOn,
        onHangUp: _hangUp,
        onToggleSubtitles: () => setState(() => _subtitlesOn = !_subtitlesOn),
        onOpenHistory: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceCallHistoryScreen(
              characterId: widget.characterId,
              characterName: _character?.name ?? '',
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main call UI
// ─────────────────────────────────────────────────────────────────────────────

class _CallContent extends StatelessWidget {
  final CharacterModel? character;
  final Animation<double> pulseAnim;
  final bool subtitlesOn;
  final VoidCallback onHangUp;
  final VoidCallback onToggleSubtitles;
  final VoidCallback onOpenHistory;

  const _CallContent({
    required this.character,
    required this.pulseAnim,
    required this.subtitlesOn,
    required this.onHangUp,
    required this.onToggleSubtitles,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VoiceCallService>();
    final state = service.state;
    final name = character?.name ?? '对方';

    return Scaffold(
      backgroundColor: _callBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: subtitle toggle + history
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      subtitlesOn ? Icons.closed_caption : Icons.closed_caption_off,
                      color: subtitlesOn ? _callAccent : _callMuted,
                    ),
                    tooltip: subtitlesOn ? '关闭字幕' : '开启字幕',
                    onPressed: onToggleSubtitles,
                  ),
                  IconButton(
                    icon: const Icon(Icons.history_rounded, color: _callMuted),
                    tooltip: '通话记录',
                    onPressed: onOpenHistory,
                  ),
                ],
              ),
            ),

            // Avatar + name + status
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AvatarPulse(
                    character: character,
                    state: state,
                    pulseAnim: pulseAnim,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    name,
                    style: const TextStyle(
                      color: _callText,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StatusLabel(state: state, characterName: name),
                  if (service.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      service.error!,
                      style: const TextStyle(color: _callRed, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // Subtitle area
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: subtitlesOn && (service.lastLine?.isNotEmpty ?? false)
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _callSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          service.lastLine!,
                          style: const TextStyle(
                            color: _callText,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Controls
            _CallControls(
              state: state,
              onHangUp: onHangUp,
              onTogglePtt: () => service.toggleRecording(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _AvatarPulse extends StatelessWidget {
  final CharacterModel? character;
  final VoiceCallState state;
  final Animation<double> pulseAnim;

  const _AvatarPulse({
    required this.character,
    required this.state,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final isSpeaking = state == VoiceCallState.companionSpeaking;
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, child) =>
          Transform.scale(scale: isSpeaking ? pulseAnim.value : 1.0, child: child),
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _borderColor(state), width: 2.5),
          boxShadow: [
            BoxShadow(color: _glowColor(state), blurRadius: 30, spreadRadius: 4),
          ],
        ),
        child: ClipOval(
          child: CharacterAvatar(
            avatar: character?.avatar,
            name: character?.name ?? '?',
            size: 130,
          ),
        ),
      ),
    );
  }

  Color _borderColor(VoiceCallState s) => switch (s) {
        VoiceCallState.companionSpeaking => _callAccent.withValues(alpha: 0.9),
        VoiceCallState.userRecording => _callRed.withValues(alpha: 0.9),
        VoiceCallState.listening => _callGreen.withValues(alpha: 0.7),
        _ => _callMuted.withValues(alpha: 0.4),
      };

  Color _glowColor(VoiceCallState s) => switch (s) {
        VoiceCallState.companionSpeaking => _callAccent.withValues(alpha: 0.18),
        VoiceCallState.userRecording => _callRed.withValues(alpha: 0.22),
        VoiceCallState.listening => _callGreen.withValues(alpha: 0.10),
        _ => Colors.transparent,
      };
}

class _StatusLabel extends StatelessWidget {
  final VoiceCallState state;
  final String characterName;

  const _StatusLabel({required this.state, required this.characterName});

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      VoiceCallState.connecting => '正在接通...',
      VoiceCallState.companionSpeaking => '$characterName 在说话',
      VoiceCallState.listening => '点击麦克风说话',
      VoiceCallState.userRecording => '录音中 — 再次点击停止',
      VoiceCallState.userProcessing => '识别中...',
      VoiceCallState.companionThinking => '思考中...',
      VoiceCallState.ended => '通话已结束',
    };
    return Text(
      label,
      style: const TextStyle(color: _callMuted, fontSize: 14),
    );
  }
}

class _CallControls extends StatelessWidget {
  final VoiceCallState state;
  final VoidCallback onHangUp;
  final VoidCallback onTogglePtt;

  const _CallControls({
    required this.state,
    required this.onHangUp,
    required this.onTogglePtt,
  });

  @override
  Widget build(BuildContext context) {
    final isRecording = state == VoiceCallState.userRecording;
    final isSpeaking = state == VoiceCallState.companionSpeaking;
    final pttActive = state == VoiceCallState.listening ||
        state == VoiceCallState.userRecording ||
        state == VoiceCallState.companionSpeaking;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Hang-up
          _CircleBtn(
            size: 68,
            color: _callRed,
            onTap: onHangUp,
            child: const Icon(Icons.call_end, color: Colors.white, size: 28),
          ),

          // PTT (tap-to-toggle)
          GestureDetector(
            onTap: pttActive ? onTogglePtt : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording
                    ? _callRed.withValues(alpha: 0.15)
                    : isSpeaking
                        ? _callAccent.withValues(alpha: 0.08)
                        : _callSurface,
                border: Border.all(
                  color: isRecording
                      ? _callRed
                      : isSpeaking
                          ? _callAccent.withValues(alpha: 0.6)
                          : pttActive
                              ? _callBlue.withValues(alpha: 0.7)
                              : _callMuted.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                isRecording
                    ? Icons.mic
                    : isSpeaking
                        ? Icons.mic_off
                        : Icons.mic_none,
                color: isRecording
                    ? _callRed
                    : isSpeaking
                        ? _callAccent.withValues(alpha: 0.8)
                        : pttActive
                            ? _callBlue
                            : _callMuted,
                size: 32,
              ),
            ),
          ),

          // Spacer for visual balance
          const SizedBox(width: 68),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final double size;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  const _CircleBtn({
    required this.size,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice call history screen
// ─────────────────────────────────────────────────────────────────────────────

class VoiceCallHistoryScreen extends StatefulWidget {
  final String characterId;
  final String characterName;

  const VoiceCallHistoryScreen({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<VoiceCallHistoryScreen> createState() => _VoiceCallHistoryScreenState();
}

class _VoiceCallHistoryScreenState extends State<VoiceCallHistoryScreen> {
  late Future<List<_SessionWithDuration>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_SessionWithDuration>> _load() async {
    final sessions = await AppDatabase.instance.voiceCallDao
        .sessionsForCharacter(widget.characterId);
    return sessions.map((s) {
      final endedAt = s.endedAt;
      final dur = endedAt != null
          ? Duration(seconds: endedAt - s.startedAt)
          : null;
      return _SessionWithDuration(session: s, duration: dur);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0C10),
        foregroundColor: const Color(0xFFF0EBE0),
        title: Text('${widget.characterName} 的通话记录'),
        elevation: 0,
      ),
      body: FutureBuilder<List<_SessionWithDuration>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: _callAccent));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('暂无通话记录', style: TextStyle(color: _callMuted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E2028)),
            itemBuilder: (context, i) => _SessionTile(
              item: items[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VoiceCallTranscriptScreen(
                    sessionId: items[i].session.id,
                    startedAt: DateTime.fromMillisecondsSinceEpoch(
                        items[i].session.startedAt * 1000),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SessionWithDuration {
  final VoiceCallSession session;
  final Duration? duration;
  const _SessionWithDuration({required this.session, this.duration});
}

class _SessionTile extends StatelessWidget {
  final _SessionWithDuration item;
  final VoidCallback onTap;

  const _SessionTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = item.session;
    final date = DateFormat('MM-dd HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(s.startedAt * 1000));
    final durStr = item.duration != null
        ? '${item.duration!.inMinutes}分${item.duration!.inSeconds % 60}秒'
        : '进行中';
    final summary = s.summary;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        date,
        style: const TextStyle(color: _callText, fontSize: 14),
      ),
      subtitle: summary != null && summary.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _callMuted, fontSize: 13),
              ),
            )
          : null,
      trailing: Text(durStr, style: const TextStyle(color: _callMuted, fontSize: 12)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transcript screen (single call)
// ─────────────────────────────────────────────────────────────────────────────

class VoiceCallTranscriptScreen extends StatefulWidget {
  final String sessionId;
  final DateTime startedAt;

  const VoiceCallTranscriptScreen({
    super.key,
    required this.sessionId,
    required this.startedAt,
  });

  @override
  State<VoiceCallTranscriptScreen> createState() =>
      _VoiceCallTranscriptScreenState();
}

class _VoiceCallTranscriptScreenState
    extends State<VoiceCallTranscriptScreen> {
  late Future<List<VoiceCallMessage>> _future;

  @override
  void initState() {
    super.initState();
    _future = AppDatabase.instance.voiceCallDao
        .messagesForSession(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0C10),
        foregroundColor: const Color(0xFFF0EBE0),
        title: Text(DateFormat('MM月dd日 HH:mm').format(widget.startedAt)),
        elevation: 0,
      ),
      body: FutureBuilder<List<VoiceCallMessage>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: _callAccent));
          }
          final msgs = snap.data ?? [];
          if (msgs.isEmpty) {
            return const Center(
              child: Text('暂无内容', style: TextStyle(color: _callMuted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length,
            itemBuilder: (context, i) {
              final msg = msgs[i];
              final isUser = msg.role == 'user';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    if (!isUser) const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isUser
                              ? const Color(0xFF2C3040)
                              : const Color(0xFF161820),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          msg.content,
                          style: const TextStyle(
                              color: _callText, fontSize: 14, height: 1.5),
                        ),
                      ),
                    ),
                    if (isUser) const SizedBox(width: 8),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation helper
// ─────────────────────────────────────────────────────────────────────────────

void openVoiceCall(
  BuildContext context, {
  required String characterId,
  bool rootNavigator = false,
}) {
  Navigator.of(context, rootNavigator: rootNavigator).push(
    MaterialPageRoute<void>(
      builder: (_) => VoiceCallScreen(characterId: characterId),
    ),
  );
}
