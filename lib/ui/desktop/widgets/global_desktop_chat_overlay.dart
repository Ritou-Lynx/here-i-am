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
import 'package:go_router/go_router.dart';

import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/db/app_database.dart';
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

class _GlobalDesktopChatOverlayState extends State<GlobalDesktopChatOverlay> {
  String? _characterId;
  DesktopTaskStripData? _taskStrip;
  bool _wasOpen = false;

  GlobalDesktopChatOverlayController get _controller =>
      widget.controller ?? GlobalDesktopChatOverlayController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    _resolveCharacter();
    _loadTaskStrip();
  }

  @override
  void didUpdateWidget(covariant GlobalDesktopChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController =
        oldWidget.controller ?? GlobalDesktopChatOverlayController.instance;
    if (oldController == _controller) return;
    oldController.removeListener(_handleControllerChanged);
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final opened = _controller.isOpen && !_wasOpen;
    _wasOpen = _controller.isOpen;
    setState(() {});
    if (opened) _loadTaskStrip();
  }

  Future<void> _resolveCharacter() async {
    try {
      final resolver = widget.characterIdResolver;
      if (resolver != null) {
        final id = await resolver();
        if (mounted) setState(() => _characterId = id);
        return;
      }
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final character = await CharacterService.instance.getPrimaryCompanion(
        userId,
      );
      if (mounted && character != null) {
        setState(() => _characterId = character.id);
      }
    } catch (_) {
      // Silently fail — no floating ball if character can't be resolved.
    }
  }

  Future<void> _loadTaskStrip() async {
    if (!AppDatabase.isInitialized) return;
    try {
      final rooms = await TaskRoomService(
        db: AppDatabase.instance,
      ).listTaskRooms(limit: 50);
      DesktopTaskStripData? taskStrip;
      for (final room in rooms) {
        final status = TaskStatus.fromString(room.status);
        if (status.isTerminal) continue;
        taskStrip = DesktopTaskStripData(
          title: room.title,
          statusLabel: _taskStatusLabel(status),
          needsAttention: status == TaskStatus.waitingForUser ||
              status == TaskStatus.blocked,
        );
        break;
      }
      if (mounted) setState(() => _taskStrip = taskStrip);
    } catch (_) {
      // The task strip is optional; chat remains available if tasks fail.
    }
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
        taskStrip: _taskStrip,
        onOpenTasks: () {
          _controller.close();
          context.go(AppRoutes.devRoom);
        },
        onOpen: () => _controller.open(
          expectedCharacterId: characterId,
          temporaryContextLabel: pageContext,
        ),
        onClose: _controller.close,
      ),
    );
  }
}

String _taskStatusLabel(TaskStatus status) {
  return switch (status) {
    TaskStatus.pending => '待开始',
    TaskStatus.running => '进行中',
    TaskStatus.blocked => '已阻塞',
    TaskStatus.waitingForUser => '等待确认',
    TaskStatus.completed => '已完成',
    TaskStatus.failed => '失败',
    TaskStatus.cancelled => '已取消',
    TaskStatus.archived => '已归档',
  };
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
