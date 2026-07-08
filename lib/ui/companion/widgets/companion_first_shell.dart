import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/persona_chat_open_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
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
  DreamingSchedulerService? _dreamingScheduler;
  PersonaChatOpenRequest? _pendingOpenRequest;
  bool _startVoiceMode = false;
  bool _isLoading = true;
  Object? _loadError;
  Timer? _retryTimer;
  StreamSubscription<PersonaChatOpenRequest>? _openChatSub;

  /// Called from notification payload handlers. Voice-mode boot only; the
  /// target character is always the singleton I, so we ignore the requested
  /// characterId.
  Future<void> switchToCharacter(
    String characterId, {
    bool startVoiceMode = false,
  }) async {
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

    // Start the dreaming lightweight tick while the companion shell is visible.
    if (AppDatabase.isInitialized) {
      _dreamingScheduler = DreamingSchedulerService(
        db: AppDatabase.instance,
      );
      _dreamingScheduler!.startForegroundTick();
    }
  }

  @override
  void dispose() {
    _dreamingScheduler?.stopForegroundTick();
    _retryTimer?.cancel();
    _openChatSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialCharacter({int attempt = 0}) async {
    _retryTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    final userId = await UserStorage.getUserId();
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final primary = await _loadPrimaryCompanion(userId);
      if (primary == null && attempt < 2) {
        _logger.warning(
          'No primary companion resolved during startup; retrying ($attempt)',
        );
        _retryTimer = Timer(
          const Duration(milliseconds: 600),
          () => unawaited(_loadInitialCharacter(attempt: attempt + 1)),
        );
        return;
      }

      final requested = _pendingOpenRequest;
      _pendingOpenRequest = null;

      if (!mounted) return;
      setState(() {
        _characterId = primary?.id;
        _startVoiceMode = requested?.startVoiceMode == true;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to load the I', e, stackTrace);
      if (attempt < 2) {
        _retryTimer = Timer(
          const Duration(milliseconds: 600),
          () => unawaited(_loadInitialCharacter(attempt: attempt + 1)),
        );
        return;
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e;
        });
      }
    }
  }

  Future<CharacterModel?> _loadPrimaryCompanion(String userId) async {
    // Go through MemexRouter first so FileSystemService / DB are initialized.
    final characters = (await MemexRouter().fetchCharacters()).valueOrThrow;
    final primary = characters
            .where((c) => c.isPrimaryCompanion && c.enabled)
            .firstOrNull ??
        characters.where((c) => c.enabled).firstOrNull;
    if (primary != null) return primary;

    // Reinstall-over-data can briefly report an empty roster before the
    // singleton I seed is visible to the shell. CharacterService owns seeding,
    // so ask it directly before treating startup as failed.
    final seededPrimary =
        await CharacterService.instance.getPrimaryCompanion(userId);
    if (seededPrimary != null && seededPrimary.enabled) {
      return seededPrimary;
    }

    final seededCharacters =
        await CharacterService.instance.getAllCharacters(userId);
    return seededCharacters
            .where((c) => c.isPrimaryCompanion && c.enabled)
            .firstOrNull ??
        seededCharacters.where((c) => c.enabled).firstOrNull;
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
      companionLifeSpaceRoute(),
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
    if (characterId == null) {
      return _NoCompanionView(
        error: _loadError,
        onRetry: () => unawaited(_loadInitialCharacter()),
      );
    }
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
Route<void> companionLifeSpaceRoute() {
  return MaterialPageRoute<void>(
    builder: (_) => const CompanionLifeSpaceScreen(),
  );
}

class _NoCompanionView extends StatelessWidget {
  const _NoCompanionView({
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AgentLogoLoading(),
              const SizedBox(height: 16),
              const Text(
                '正在初始化 I...',
                textAlign: TextAlign.center,
              ),
              if (hasError) ...[
                const SizedBox(height: 12),
                Text(
                  '初始化暂时没有完成，点一下重试即可继续。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
