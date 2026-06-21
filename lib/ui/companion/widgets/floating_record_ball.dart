import 'package:flutter/material.dart';
import 'package:memex/data/services/record_organizer_service.dart';
import 'package:memex/utils/user_storage.dart';

/// Floating action ball that lets the user quickly save a fact, plan, or note
/// to User-truth from any screen in the app.
///
/// Drag to reposition. Tap to open the quick-save sheet.
class FloatingRecordBall extends StatefulWidget {
  const FloatingRecordBall({super.key});

  @override
  State<FloatingRecordBall> createState() => _FloatingRecordBallState();
}

class _FloatingRecordBallState extends State<FloatingRecordBall> {
  double _right = 16;
  double _bottom = 110;
  Offset? _panStart;
  bool _didMove = false;

  void _onPanStart(DragStartDetails d) {
    _panStart = d.globalPosition;
    _didMove = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    setState(() {
      _right = (_right - d.delta.dx).clamp(0.0, size.width - 56.0);
      _bottom = (_bottom - d.delta.dy)
          .clamp(padding.bottom, size.height - 56.0 - padding.top);
    });
    if (_panStart != null &&
        (d.globalPosition - _panStart!).distance > 6) {
      _didMove = true;
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (!_didMove) _showQuickSave();
    _panStart = null;
  }

  void _showQuickSave() {
    if (!RecordOrganizerService.isInitialized) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickSaveSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!RecordOrganizerService.isInitialized) return const SizedBox.shrink();
    return Positioned(
      right: _right,
      bottom: _bottom,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
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

// ─── Quick-save bottom sheet ───────────────────────────────────────────────

class _QuickSaveSheet extends StatefulWidget {
  const _QuickSaveSheet();

  @override
  State<_QuickSaveSheet> createState() => _QuickSaveSheetState();
}

class _QuickSaveSheetState extends State<_QuickSaveSheet> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null || !mounted) return;
      final charId =
          await UserStorage.getLastActiveCompanionCharacterId(userId);
      final result = await RecordOrganizerService.instance.recordFromText(
        userId: userId,
        sourceCharacterId: charId ?? '_system',
        text: text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty
                ? '未能提取有效记录'
                : '已记录：${result.entityTitles.join("、")}',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFAF7F2),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  '记录一下',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3D2B1F),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '事实、想法、计划……',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF8A6F4E)),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF3D2B1F),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8A6F4E),
                      disabledBackgroundColor:
                          const Color(0xFF8A6F4E).withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '保存',
                            style: TextStyle(
                              fontSize: 15,
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
    );
  }
}
