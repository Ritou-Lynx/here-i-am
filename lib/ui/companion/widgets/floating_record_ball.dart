import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memex/agent/built_in_tools/asset_analysis_tool.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/media_input_attachment.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart'
    show PersonaChatInputBar;
import 'package:memex/ui/companion/widgets/companion_media_tray.dart';
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
    if (!RecordOrganizerServiceV3.isInitialized) return;
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

// ─── Quick-save sheet — full chat input experience ────────────────────────────

class _QuickSaveSheet extends StatefulWidget {
  const _QuickSaveSheet({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_QuickSaveSheet> createState() => _QuickSaveSheetState();
}

class _QuickSaveSheetState extends State<_QuickSaveSheet> {
  final _controller = TextEditingController();
  final _images = <XFile>[];
  bool _saving = false;
  bool _isMediaTrayOpen = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onImagesPicked(List<XFile> images) {
    setState(() {
      for (final img in images) {
        if (!_images.any((i) => i.path == img.path)) _images.add(img);
      }
      _isMediaTrayOpen = false;
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _images.isEmpty) || _saving) return;

    // Capture everything we need BEFORE dismissing the sheet.
    final capturedImages = List<XFile>.from(_images);
    final capturedText = text;
    final navCtx = widget.navigatorKey.currentContext;

    // Dismiss sheet immediately — processing happens in background.
    _controller.clear();
    setState(() {
      _images.clear();
      _saving = true;
    });
    if (mounted) Navigator.pop(context);

    // Show progress snackbar on the parent navigator.
    ScaffoldMessengerState? messenger;
    if (navCtx != null && navCtx.mounted) {
      messenger = ScaffoldMessenger.of(navCtx);
      messenger.showSnackBar(const SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('正在记录…'),
          ],
        ),
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ));
    }

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        messenger?.clearSnackBars();
        messenger?.showSnackBar(const SnackBar(
          content: Text('记录失败：未登录'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      // ── Pre-process selected images ──────────────────────────
      final media = <MediaInputAttachment>[];
      if (capturedImages.isNotEmpty) {
        final fsService = FileSystemService.instance;
        for (var i = 0; i < capturedImages.length; i++) {
          final xFile = capturedImages[i];
          try {
            final ext = xFile.path.split('.').lastOrNull ?? 'jpg';
            final bytes = await xFile.readAsBytes();
            final (filename, relativePath) = await fsService.saveAssetFromBytes(
              userId: userId,
              bytes: bytes,
              assetType: 'img',
              index: i + 1,
              format: ext,
            );

            // Run inline image analysis
            String? analysisText;
            try {
              final analysisResources = await UserStorage.getAgentLLMResources(
                AgentDefinitions.analyzeAssets,
                defaultClientKey: LLMConfig.defaultClientKey,
              );
              final analysisTool = AssetAnalysisTool(
                client: analysisResources.client,
                modelConfig: analysisResources.modelConfig,
              );
              final absPath = fsService.toAbsolutePath(relativePath);
              final result = await analysisTool.tool(
                assetPath: absPath,
                prompt: '用1-2句中文简要描述这张图片的内容。'
                    '关注画面中可见的人、物体、文字、场景。'
                    '简洁客观。',
              );
              analysisText = result
                  .replaceFirst(RegExp(r'^#Asset .+ analysis result\n:'), '')
                  .trim();
            } catch (e) {
              debugPrint('Image analysis failed in floating ball: $e');
            }

            media.add(MediaInputAttachment(
              savedRelativePath: relativePath,
              analysisText: analysisText,
              kind: 'image',
            ));
          } catch (e) {
            debugPrint('Failed to save image in floating ball: $e');
            media.add(MediaInputAttachment(error: e.toString()));
          }
        }
      }

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final inputMedia = media.isNotEmpty
          ? media
              .map((m) => {
                    'kind': m.kind,
                    if (m.savedRelativePath != null)
                      'path': m.savedRelativePath!,
                    if (m.analysisText != null) 'analysis': m.analysisText!,
                  })
              .toList()
          : null;
      final result = await RecordOrganizerServiceV3.instance.organizeAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        source: RecordSource(sourceKind: 'fab', rawInput: capturedText),
        inputMedia: inputMedia,
      );

      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text(result.isEmpty
            ? '未能提取有效记录'
            : '已记录 ${result.cardIds.length} 张卡片'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text('记录失败：$e'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // viewInsets.bottom == keyboard height; moves the entire sheet above the keyboard
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompanionMediaTray(
            isOpen: _isMediaTrayOpen,
            onImagesPicked: _onImagesPicked,
          ),
          PersonaChatInputBar(
            controller: _controller,
            isStreaming: _saving,
            onSend: _save,
            hintText: '记录一下……',
            onAddTap: () =>
                setState(() => _isMediaTrayOpen = !_isMediaTrayOpen),
            isAddActive: _isMediaTrayOpen,
            selectedImages: _images,
            onRemoveImage: (i) => setState(() => _images.removeAt(i)),
          ),
        ],
      ),
    );
  }
}
