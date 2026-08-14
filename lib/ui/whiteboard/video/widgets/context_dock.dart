/// ContextDock — the collapsible work surface docked to the right or bottom
/// of the video player. Holds the subtitle list, annotation editor (when a
/// pending annotation exists), and the saved annotation cards list.
///
/// This is a per-view auxiliary dock, NOT a global permanent sidebar. It
/// fully collapses and leaves when closed. Uses Palm visual language:
/// warm paper surfaces, coffee-text, low-saturation green accents.
library;

import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import '../view_models/video_study_view_model.dart';
import 'subtitle_list_view.dart';
import 'annotation_editor.dart';

class ContextDock extends StatefulWidget {
  final VideoStudyViewModel viewModel;

  const ContextDock({super.key, required this.viewModel});

  @override
  State<ContextDock> createState() => _ContextDockState();
}

class _ContextDockState extends State<ContextDock> {
  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final tokens = Theme.of(context)
            .extension<SpringRainUiTokens>() ??
        SpringRainUiTokens.daylight;

    return Container(
      color: tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _DockHeader(
            title: '字幕 / 时间轴',
            subtitle: _subtitleStatusLabel(vm),
            onClose: () => Navigator.of(context).maybePop(),
          ),
          const Divider(height: 1, color: Color(0x1F5B5843)),
          // Body
          Expanded(
            child: vm.showSaveConfirmation
                ? _SaveConfirmationPane(
                    viewModel: vm,
                    onDismiss: vm.dismissSaveConfirmation,
                  )
                : vm.hasPendingAnnotation
                    ? _PendingAnnotationPane(viewModel: vm)
                    : SubtitleListView(viewModel: vm),
          ),
          // Annotation list (footer)
          if (vm.annotations.isNotEmpty)
            _AnnotationCardsList(viewModel: vm),
        ],
      ),
    );
  }

  String _subtitleStatusLabel(VideoStudyViewModel vm) {
    if (vm.needsSubtitle) return '需要字幕';
    final track = vm.track;
    if (track == null) return '—';
    final source = switch (track.sourceKind) {
      TimedTextSourceKind.platform => '平台字幕',
      TimedTextSourceKind.creator => '创作者字幕',
      TimedTextSourceKind.userImport => '用户导入',
      TimedTextSourceKind.asr => '本机转写',
    };
    return '$source · ${track.cues.length} 条';
  }
}

class _DockHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _DockHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: SpringRainUiTokens.daylightTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: SpringRainUiTokens.daylightTextTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: SpringRainUiTokens.daylightTextSecondary,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _PendingAnnotationPane extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  const _PendingAnnotationPane({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final startMs = viewModel.pendingAnnotationStartMs ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '在 ${VideoStudyViewModel.formatTimecode(startMs)} 创建标注',
            style: const TextStyle(
              color: Color(0xFF43593B),
              fontSize: 13,
              fontFamily: 'Cascadia Code',
            ),
          ),
          const SizedBox(height: 12),
          AnnotationEditor(viewModel: viewModel),
        ],
      ),
    );
  }
}

/// Confirmation shown briefly after an annotation is saved.
class _SaveConfirmationPane extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  final VoidCallback onDismiss;
  const _SaveConfirmationPane({
    required this.viewModel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3E5C9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Color(0xFF43593B)),
                  const SizedBox(width: 8),
                  Text(
                    '标注已保存',
                    style: TextStyle(
                      color: SpringRainUiTokens.daylightTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onDismiss,
              child: Text(
                '返回字幕',
                style: TextStyle(
                  color: SpringRainUiTokens.daylightTextSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnotationCardsList extends StatelessWidget {
  final VideoStudyViewModel viewModel;
  const _AnnotationCardsList({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final annotations = viewModel.annotations;
    return Container(
      decoration: BoxDecoration(
        color: SpringRainUiTokens.daylightSurfaceMuted,
        border: Border(
          top: BorderSide(
            color: SpringRainUiTokens.daylightDivider,
            width: 1,
          ),
        ),
      ),
      child: SizedBox(
        height: 96,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: annotations.length,
          itemBuilder: (context, index) {
            final a = annotations[index];
            return _AnnotationCardThumb(
              annotation: a,
              onTap: () => viewModel.seekTo(a.startMs),
            );
          },
        ),
      ),
    );
  }
}

class _AnnotationCardThumb extends StatelessWidget {
  final UIAnnotation annotation;
  final VoidCallback onTap;

  const _AnnotationCardThumb({
    required this.annotation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = annotation.card.title.isEmpty
        ? '未命名标注'
        : annotation.card.title;
    final timecode = VideoStudyViewModel.formatTimecode(annotation.startMs);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SpringRainUiTokens.daylightSurfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0x1F5B5843),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              timecode,
              style: const TextStyle(
                color: Color(0xFF43593B),
                fontSize: 11,
                fontFamily: 'Cascadia Code',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: SpringRainUiTokens.daylightTextPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}