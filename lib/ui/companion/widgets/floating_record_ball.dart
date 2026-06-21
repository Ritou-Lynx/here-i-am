import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/services/record_organizer_service.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart'
    show PersonaChatInputBar;
import 'package:memex/utils/user_storage.dart';

/// Floating action ball that lets the user quickly save a fact, plan, or note
/// to User-truth from any screen in the app.
///
/// [navigatorKey] is used to obtain the correct BuildContext for showing
/// bottom sheets — the ball lives above the Navigator in the widget tree,
/// so it cannot use its own context directly.
///
/// Drag to reposition. Tap to open the quick-save sheet.
class FloatingRecordBall extends StatefulWidget {
  const FloatingRecordBall({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<FloatingRecordBall> createState() => _FloatingRecordBallState();
}

class _FloatingRecordBallState extends State<FloatingRecordBall> {
  double _right = 16;
  double _bottom = 110;
  // Track drag so we can skip _showQuickSave after a real drag gesture
  bool _dragging = false;

  void _showQuickSave() {
    if (!RecordOrganizerService.isInitialized) return;
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;
    showModalBottomSheet<void>(
      context: navContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickSaveSheet(navigatorKey: widget.navigatorKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: _right,
      bottom: _bottom,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _dragging = false,
        onPointerMove: (e) {
          if (e.delta.distance > 3) {
            _dragging = true;
            final size = MediaQuery.of(context).size;
            final padding = MediaQuery.of(context).padding;
            setState(() {
              _right = (_right - e.delta.dx).clamp(0.0, size.width - 56.0);
              _bottom = (_bottom - e.delta.dy)
                  .clamp(padding.bottom, size.height - 56.0 - padding.top);
            });
          }
        },
        onPointerUp: (_) {
          if (!_dragging) _showQuickSave();
        },
        child: const _BallWidget(),
      ),
    );
  }
}

class _BallWidget extends StatelessWidget {
  const _BallWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF5EFE7).withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.edit_note_rounded,
        size: 26,
        color: Color(0xFF8A6F4E),
      ),
    );
  }
}

// ─── Quick-save sheet — reuses PersonaChatInputBar ────────────────────────

class _QuickSaveSheet extends StatefulWidget {
  const _QuickSaveSheet({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_QuickSaveSheet> createState() => _QuickSaveSheetState();
}

class _QuickSaveSheetState extends State<_QuickSaveSheet> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  List<XFile> _images = [];
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isNotEmpty) setState(() => _images = [..._images, ...picked]);
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _images.isEmpty) || _saving) return;
    setState(() => _saving = true);
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null || !mounted) return;
      final charId =
          await UserStorage.getLastActiveCompanionCharacterId(userId);
      final result = await RecordOrganizerService.instance.recordFromText(
        userId: userId,
        sourceCharacterId: charId ?? '_system',
        text: text.isNotEmpty ? text : '[图片记录 ${_images.length} 张]',
      );
      if (!mounted) return;
      Navigator.pop(context);
      final navCtx = widget.navigatorKey.currentContext;
      if (navCtx != null) {
        ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(
          content: Text(result.isEmpty
              ? '未能提取有效记录'
              : '已记录：${result.entityTitles.join("、")}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PersonaChatInputBar(
      controller: _controller,
      isStreaming: _saving,
      onSend: _save,
      hintText: '记录一下……',
      onAddTap: _pickImages,
      isAddActive: _images.isNotEmpty,
      selectedImages: _images,
      onRemoveImage: (i) => setState(() => _images.removeAt(i)),
    );
  }
}
