import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/persona_chat_open_service.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

import 'companion_life_space_screen.dart';

/// Companion-first app shell.
///
/// Single-companion architecture: the home is always chat with the singleton
/// I. No selection, no swipe, no multi-character routing.
class CompanionFirstShell extends StatefulWidget {
  const CompanionFirstShell({super.key});

  @override
  State<CompanionFirstShell> createState() => CompanionFirstShellState();
}

class CompanionFirstShellState extends State<CompanionFirstShell> {
  final _logger = getLogger('CompanionFirstShell');
  String? _characterId;
  PersonaChatOpenRequest? _pendingOpenRequest;
  bool _startVoiceMode = false;
  bool _isLoading = true;
  StreamSubscription<PersonaChatOpenRequest>? _openChatSub;

  /// Called from notification payload handlers. Voice-mode boot only; the
  /// target character is always the singleton I, so we ignore the requested
  /// characterId.
  Future<void> switchToCharacter(String characterId,
      {bool startVoiceMode = false}) async {
    if (_isLoading) {
      _pendingOpenRequest = PersonaChatOpenRequest(
        characterId: characterId,
        startVoiceMode: startVoiceMode,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _startVoiceMode = startVoiceMode);
  }

  @override
  void initState() {
    super.initState();
    _pendingOpenRequest = PersonaChatOpenService.instance.consumePending();
    _openChatSub = PersonaChatOpenService.instance.requests.listen(
      _handleOpenChatRequest,
    );
    _loadInitialCharacter();
  }

  @override
  void dispose() {
    _openChatSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialCharacter() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Goes through MemexRouter so FileSystemService / DB are guaranteed
      // initialized for this user before we touch CharacterService.
      final characters = (await MemexRouter().fetchCharacters()).valueOrThrow;
      final primary = characters
              .where((c) => c.isPrimaryCompanion && c.enabled)
              .firstOrNull ??
          characters.where((c) => c.enabled).firstOrNull;
      final requested = _pendingOpenRequest;
      _pendingOpenRequest = null;

      if (!mounted) return;
      setState(() {
        _characterId = primary?.id;
        _startVoiceMode = requested?.startVoiceMode == true;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to load the I', e, stackTrace);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOpenChatRequest(PersonaChatOpenRequest request) async {
    PersonaChatOpenService.instance.markHandled(request);
    if (_isLoading) {
      _pendingOpenRequest = request;
      return;
    }
    if (!mounted) return;
    setState(() => _startVoiceMode = request.startVoiceMode);
  }

  void _openLifeSpace() {
    Navigator.push(
      context,
      companionLifeSpaceRoute(
        timelineViewModel: context.read<TimelineViewModel>(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: AgentLogoLoading()),
      );
    }

    final characterId = _characterId;
    if (characterId == null) return const _NoCompanionView();
    return PersonaChatScreen(
      key: ValueKey('companion-chat-$characterId'),
      characterId: characterId,
      embedded: true,
      enableRichCapture: true,
      initialVoiceMode: _startVoiceMode,
      onOpenSpaces: _openLifeSpace,
    );
  }
}

@visibleForTesting
Route<void> companionLifeSpaceRoute({
  TimelineViewModel? timelineViewModel,
}) {
  return MaterialPageRoute<void>(
    builder: (_) => const CompanionLifeSpaceScreen(),
  );
}

class _NoCompanionView extends StatelessWidget {
  const _NoCompanionView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '正在初始化 I...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
