/// Desktop global floating chat overlay.
///
/// Wraps [DesktopChatOverlay] in a stateful widget that resolves the primary
/// companion characterId asynchronously (mirroring CompanionFirstShell's
/// approach). Mounted in MaterialApp.router's builder Stack so it persists
/// across all GoRoute pages — the floating ball stays visible whether the
/// user is on the home workbench, whiteboard index, card library, or any
/// other route (spine-contract §3.5 / visual-rules §8.6).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/services/character_service.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/ui/desktop/widgets/desktop_chat_overlay.dart';

class GlobalDesktopChatOverlayController extends ChangeNotifier {
  GlobalDesktopChatOverlayController._();

  static final instance = GlobalDesktopChatOverlayController._();

  bool _open = false;
  String? _expectedCharacterId;
  String? _temporaryContextLabel;

  bool get isOpen => _open;
  String? get expectedCharacterId => _expectedCharacterId;
  String? get temporaryContextLabel => _temporaryContextLabel;

  void open({String? expectedCharacterId, String? temporaryContextLabel}) {
    _open = true;
    _expectedCharacterId = expectedCharacterId;
    _temporaryContextLabel = temporaryContextLabel;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    _temporaryContextLabel = null;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _open = false;
    _expectedCharacterId = null;
    _temporaryContextLabel = null;
    notifyListeners();
  }
}

class GlobalDesktopChatOverlay extends StatefulWidget {
  const GlobalDesktopChatOverlay({
    super.key,
    this.controller,
    this.characterIdResolver,
  });

  final GlobalDesktopChatOverlayController? controller;
  final Future<String?> Function()? characterIdResolver;

  @override
  State<GlobalDesktopChatOverlay> createState() =>
      _GlobalDesktopChatOverlayState();
}

/// Mounts the global chat entry in its own overlay layer.
///
/// [MaterialApp.router.builder] is above the router's Navigator, so widgets
/// inserted there cannot use that Navigator's [Overlay]. The floating entry
/// contains tooltips and transient chat controls that require one.
class GlobalDesktopChatOverlayHost extends StatelessWidget {
  const GlobalDesktopChatOverlayHost({
    super.key,
    this.controller,
    this.characterIdResolver,
  });

  final GlobalDesktopChatOverlayController? controller;
  final Future<String?> Function()? characterIdResolver;

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => GlobalDesktopChatOverlay(
            controller: controller,
            characterIdResolver: characterIdResolver,
          ),
        ),
      ],
    );
  }
}

class _GlobalDesktopChatOverlayState extends State<GlobalDesktopChatOverlay> {
  String? _characterId;
  Timer? _characterRetryTimer;

  GlobalDesktopChatOverlayController get _controller =>
      widget.controller ?? GlobalDesktopChatOverlayController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    CharacterService.instance.addListener(_handleCharacterChanged);
    _resolveCharacter();
  }

  @override
  void didUpdateWidget(covariant GlobalDesktopChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController =
        oldWidget.controller ?? GlobalDesktopChatOverlayController.instance;
    if (oldController != _controller) {
      oldController.removeListener(_handleControllerChanged);
      _controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.characterIdResolver != widget.characterIdResolver) {
      _characterRetryTimer?.cancel();
      _characterId = null;
      _resolveCharacter();
    }
  }

  @override
  void dispose() {
    _characterRetryTimer?.cancel();
    _controller.removeListener(_handleControllerChanged);
    CharacterService.instance.removeListener(_handleCharacterChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleCharacterChanged() {
    if (_characterId == null) _resolveCharacter();
  }

  Future<void> _resolveCharacter({int attempt = 0}) async {
    if (_characterId != null) return;
    String? resolvedId;
    try {
      final resolver = widget.characterIdResolver;
      if (resolver != null) {
        resolvedId = await resolver();
      } else {
        final userId = await UserStorage.getUserId();
        if (userId != null) {
          final character =
              await CharacterService.instance.getPrimaryCompanion(userId);
          resolvedId = character?.id;
        }
      }
    } catch (_) {
      // Startup can race user/character seeding. The bounded retry below keeps
      // this transient failure from permanently removing the desktop entry.
    }
    if (!mounted || _characterId != null) return;
    if (resolvedId != null && resolvedId.isNotEmpty) {
      _characterRetryTimer?.cancel();
      setState(() => _characterId = resolvedId);
      return;
    }
    if (attempt >= 4) return;
    _characterRetryTimer?.cancel();
    _characterRetryTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_resolveCharacter(attempt: attempt + 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final characterId = _controller.expectedCharacterId ?? _characterId;
    if (characterId == null) return const SizedBox.shrink();
    final pageContext =
        _controller.temporaryContextLabel ?? _desktopPageContextLabel(context);

    return Positioned.fill(
      child: DesktopChatOverlay(
        open: _controller.isOpen,
        characterId: characterId,
        initialVoiceMode: false,
        temporaryContextLabel: pageContext,
        onOpen: () => _controller.open(
          expectedCharacterId: characterId,
          temporaryContextLabel: pageContext,
        ),
        onClose: _controller.close,
      ),
    );
  }
}

String _desktopPageContextLabel(BuildContext context) {
  String path;
  try {
    path = GoRouterState.of(context).uri.path;
  } catch (_) {
    return '当前工作面';
  }
  if (path == AppRoutes.home) return '首页';
  if (path == AppRoutes.whiteboard || path.startsWith('/whiteboard/')) {
    return '白板';
  }
  if (path == AppRoutes.cardLibrary || path.startsWith('/cards/')) {
    return '卡片库';
  }
  if (path.startsWith('/sources/')) return '来源研读';
  if (path == AppRoutes.linkImport) return '链接导入';
  if (path == AppRoutes.memoryCenter) return '记忆空间';
  if (path == AppRoutes.interests) return '阅读空间';
  if (path == AppRoutes.devRoom) return '任务中心';
  return '当前工作面';
}

/// Whether the global desktop chat overlay should be shown.
bool shouldShowGlobalDesktopChatOverlay() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
