import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/persona_chat_open_service.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/companion/widgets/floating_record_ball.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/result.dart';
import 'package:provider/provider.dart';

import 'companion_life_space_screen.dart';

/// Companion-first app shell.
///
/// Chat is the default home. Existing Memex surfaces remain available as
/// supporting views while the new conversation-capture pipeline evolves.
class CompanionFirstShell extends StatefulWidget {
  const CompanionFirstShell({super.key});

  @override
  State<CompanionFirstShell> createState() => _CompanionFirstShellState();
}

class _CompanionFirstShellState extends State<CompanionFirstShell> {
  final _logger = getLogger('CompanionFirstShell');
  String? _characterId;
  PersonaChatOpenRequest? _pendingOpenRequest;
  bool _startVoiceMode = false;
  bool _isLoading = true;
  StreamSubscription<PersonaChatOpenRequest>? _openChatSub;

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
      final characters = (await MemexRouter().fetchCharacters()).valueOrThrow;
      final enabled =
          characters.where((character) => character.enabled).toList();
      final remembered =
          await UserStorage.getLastActiveCompanionCharacterId(userId);
      final requested = _pendingOpenRequest;
      _pendingOpenRequest = null;
      final characterId = resolveCompanionFirstCharacterId(
        enabledCharacterIds: enabled.map((character) => character.id),
        rememberedCharacterId: requested?.characterId ?? remembered,
      );

      if (characterId != null) {
        await UserStorage.setLastActiveCompanionCharacterId(
            userId, characterId);
      }

      if (!mounted) return;
      setState(() {
        _characterId = characterId;
        _startVoiceMode = requested?.startVoiceMode == true &&
            requested?.characterId == characterId;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to load the initial companion', e, stackTrace);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOpenChatRequest(PersonaChatOpenRequest request) async {
    final characterId = request.characterId;
    _pendingOpenRequest = request;
    if (_isLoading) return;

    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    try {
      final characters = (await MemexRouter().fetchCharacters()).valueOrThrow;
      final enabledIds = characters
          .where((character) => character.enabled)
          .map((character) => character.id)
          .toSet();
      if (!enabledIds.contains(characterId)) return;

      await UserStorage.setLastActiveCompanionCharacterId(userId, characterId);
      if (!mounted) return;
      _pendingOpenRequest = null;
      setState(() {
        _startVoiceMode = request.startVoiceMode;
        _characterId = characterId;
      });
    } catch (e, stackTrace) {
      _logger.warning(
        'Failed to open requested companion chat',
        e,
        stackTrace,
      );
    }
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
    return Stack(
      children: [
        PersonaChatScreen(
          key: ValueKey('companion-chat-$characterId'),
          characterId: characterId,
          embedded: true,
          enableRichCapture: true,
          initialVoiceMode: _startVoiceMode,
          onOpenSpaces: _openLifeSpace,
        ),
        const FloatingRecordBall(),
      ],
    );
  }
}

@visibleForTesting
Route<void> companionLifeSpaceRoute({
  required TimelineViewModel timelineViewModel,
}) {
  return MaterialPageRoute<void>(
    builder: (_) => CompanionLifeSpaceScreen(
      timelineViewModel: timelineViewModel,
    ),
  );
}

/// Picks the last active enabled character, falling back to the first enabled
/// character. Character privileges are intentionally not part of this choice.
@visibleForTesting
String? resolveCompanionFirstCharacterId({
  required Iterable<String> enabledCharacterIds,
  String? rememberedCharacterId,
}) {
  final ids = enabledCharacterIds.toList(growable: false);
  if (ids.isEmpty) return null;
  if (rememberedCharacterId != null && ids.contains(rememberedCharacterId)) {
    return rememberedCharacterId;
  }
  return ids.first;
}

class _NoCompanionView extends StatelessWidget {
  const _NoCompanionView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            UserStorage.l10n.addCharacter,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
