/// Desktop global floating chat overlay.
///
/// Wraps [DesktopChatOverlay] in a stateful widget that resolves the primary
/// companion characterId asynchronously (mirroring CompanionFirstShell's
/// approach). Mounted in MaterialApp.router's builder Stack so it persists
/// across all GoRoute pages — the floating ball stays visible whether the
/// user is on the home workbench, whiteboard index, card library, or any
/// other route (spine-contract §3.5 / visual-rules §8.6).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:memex/data/services/character_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/ui/desktop/widgets/desktop_chat_overlay.dart';

class GlobalDesktopChatOverlay extends StatefulWidget {
  const GlobalDesktopChatOverlay({super.key});

  @override
  State<GlobalDesktopChatOverlay> createState() =>
      _GlobalDesktopChatOverlayState();
}

class _GlobalDesktopChatOverlayState extends State<GlobalDesktopChatOverlay> {
  String? _characterId;
  bool _chatOpen = false;

  @override
  void initState() {
    super.initState();
    _resolveCharacter();
  }

  Future<void> _resolveCharacter() async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (mounted && character != null) {
        setState(() => _characterId = character.id);
      }
    } catch (_) {
      // Silently fail — no floating ball if character can't be resolved.
    }
  }

  @override
  Widget build(BuildContext context) {
    final characterId = _characterId;
    if (characterId == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: DesktopChatOverlay(
        open: _chatOpen,
        characterId: characterId,
        initialVoiceMode: false,
        onOpen: () => setState(() => _chatOpen = true),
        onClose: () => setState(() => _chatOpen = false),
      ),
    );
  }
}

/// Whether the global desktop chat overlay should be shown.
bool shouldShowGlobalDesktopChatOverlay() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}