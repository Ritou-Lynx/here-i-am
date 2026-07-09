import 'dart:ui';

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
import 'package:memex/ui/core/widgets/toast.dart';
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
  static const double _controlWidth = 72;
  static const double _controlHeight = 68;
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
              _right =
                  (_right - e.delta.dx).clamp(0.0, size.width - _controlWidth);
              _bottom = (_bottom - e.delta.dy).clamp(
                  padding.bottom, size.height - _controlHeight - padding.top);
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

class _BallWidget extends StatefulWidget {
  const _BallWidget();

  @override
  State<_BallWidget> createState() => _BallWidgetState();
}

class _BallWidgetState extends State<_BallWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
    _breath = Tween<double>(begin: 1, end: 1.028).animate(
      CurvedAnimation(
        parent: _breathController,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathController,
      builder: (context, child) {
        return Transform.scale(
          scale: _breath.value,
          child: SizedBox(
            width: _FloatingRecordBallState._controlWidth,
            height: _FloatingRecordBallState._controlHeight,
            child: CustomPaint(
              painter: const _DropletShadowPainter(),
              child: ClipPath(
                clipper: const _DropletClipper(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(-0.24, -0.38),
                              radius: 1.12,
                              colors: [
                                const Color(0xFFFFECDD).withValues(alpha: 0.13),
                                const Color(
                                  0xFFFFC4B5,
                                ).withValues(alpha: 0.065),
                                const Color(0xFF74464B).withValues(alpha: 0.34),
                                const Color(0xFF2A1219).withValues(alpha: 0.76),
                                const Color(0xFF080406).withValues(alpha: 0.94),
                              ],
                              stops: const [0, 0.24, 0.48, 0.78, 1],
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _DropletLiquidPainter()),
                        ),
                      ),
                      Center(
                        child: _DropletPlusMark(
                          color:
                              const Color(0xFFF0D5D7).withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DropletPlusMark extends StatelessWidget {
  const _DropletPlusMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 25,
      height: 25,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 18,
            height: 4.2,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC6B5).withValues(alpha: 0.12),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          Container(
            width: 4.2,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC6B5).withValues(alpha: 0.12),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DropletLiquidPainter extends CustomPainter {
  const _DropletLiquidPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final lensWash = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.34, -0.42),
        radius: 0.92,
        colors: [
          const Color(0xFFFFECDD).withValues(alpha: 0.16),
          const Color(0xFFFFC6B5).withValues(alpha: 0.07),
          Colors.transparent,
        ],
        stops: const [0, 0.42, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, lensWash);

    final upperOval = Rect.fromLTWH(
      w * 0.09,
      h * 0.06,
      w * 0.54,
      h * 0.28,
    );
    canvas.save();
    canvas.translate(upperOval.center.dx, upperOval.center.dy);
    canvas.rotate(-0.18);
    canvas.translate(-upperOval.center.dx, -upperOval.center.dy);
    canvas.drawOval(
      upperOval,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.38, -0.35),
          radius: 0.9,
          colors: [
            const Color(0xFFFFF6EF).withValues(alpha: 0.22),
            const Color(0xFFFFC6B5).withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0, 0.36, 1],
        ).createShader(upperOval),
    );
    canvas.restore();

    final crescent = Path()
      ..moveTo(w * 0.26, h * 0.23)
      ..cubicTo(
        w * 0.40,
        h * 0.13,
        w * 0.58,
        h * 0.15,
        w * 0.70,
        h * 0.29,
      );
    canvas.drawPath(
      crescent,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFECDD).withValues(alpha: 0.018)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(
      crescent,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFECDD).withValues(alpha: 0.024)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    final lowerGlow = Rect.fromLTWH(w * 0.50, h * 0.54, w * 0.42, h * 0.34);
    canvas.drawOval(
      lowerGlow,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.34, 0.30),
          radius: 0.88,
          colors: [
            const Color(0xFFC0646E).withValues(alpha: 0.20),
            const Color(0xFFFFC6B5).withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(lowerGlow),
    );

    final depth = Rect.fromLTWH(w * 0.14, h * 0.67, w * 0.62, h * 0.30);
    canvas.drawOval(
      depth,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, 0.4),
          radius: 0.9,
          colors: [
            Colors.black.withValues(alpha: 0.20),
            Colors.transparent,
          ],
        ).createShader(depth),
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFFFFECDD).withValues(alpha: 0.055)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    canvas.drawPath(_dropletPath(size).shift(const Offset(0, 0.4)), rim);
  }

  @override
  bool shouldRepaint(covariant _DropletLiquidPainter oldDelegate) => false;
}

class _DropletClipper extends CustomClipper<Path> {
  const _DropletClipper();

  @override
  Path getClip(Size size) => _dropletPath(size);

  @override
  bool shouldReclip(covariant _DropletClipper oldClipper) => false;
}

class _DropletShadowPainter extends CustomPainter {
  const _DropletShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _dropletPath(size).shift(const Offset(0, 1));
    canvas
      ..drawShadow(path, Colors.black.withValues(alpha: 0.46), 18, true)
      ..drawShadow(
        path,
        const Color(0xFFD36F7E).withValues(alpha: 0.24),
        24,
        true,
      );

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0xFFEECDBF).withValues(alpha: 0.15);
    canvas.drawPath(
      _dropletPath(size).shift(const Offset(0, 0.5)),
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _DropletShadowPainter oldDelegate) => false;
}

Path _dropletPath(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(w * 0.40, h * 0.07)
    ..cubicTo(
      w * 0.63,
      h * 0.00,
      w * 0.92,
      h * 0.15,
      w * 0.94,
      h * 0.45,
    )
    ..cubicTo(
      w * 0.96,
      h * 0.75,
      w * 0.76,
      h * 0.99,
      w * 0.48,
      h * 0.97,
    )
    ..cubicTo(
      w * 0.20,
      h * 0.95,
      w * 0.03,
      h * 0.72,
      w * 0.08,
      h * 0.47,
    )
    ..cubicTo(
      w * 0.12,
      h * 0.24,
      w * 0.23,
      h * 0.12,
      w * 0.40,
      h * 0.07,
    )
    ..close();
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

    // Show progress toast on the parent navigator.
    ScaffoldMessengerState? messenger;
    if (navCtx != null && navCtx.mounted) {
      messenger = ScaffoldMessenger.of(navCtx);
      messenger.showToast('正在记录…', duration: const Duration(seconds: 30));
    }

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        messenger?.clearSnackBars();
        messenger?.showToast('记录失败：未登录', duration: const Duration(seconds: 3));
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

      messenger?.showToast(
        result.isEmpty ? '未能提取有效记录' : '已记录 ${result.cardIds.length} 张卡片',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      messenger?.showToast(
        '记录失败：$e',
        duration: const Duration(seconds: 3),
      );
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
