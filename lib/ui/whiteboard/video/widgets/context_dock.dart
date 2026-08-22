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
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import '../view_models/video_study_view_model.dart';
import 'subtitle_list_view.dart';
import 'annotation_editor.dart';
import 'timeline_anchor_bar.dart';

class ContextDock extends StatefulWidget {
  final VideoStudyViewModel viewModel;
  final DockOrientation? displayOrientation;
  final bool orientationLocked;

  const ContextDock({
    super.key,
    required this.viewModel,
    this.displayOrientation,
    this.orientationLocked = false,
  });

  @override
  State<ContextDock> createState() => _ContextDockState();
}

class _ContextDockState extends State<ContextDock> {
  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final tokens = DesktopWorkspaceTokens.of(context);
    final orientation = widget.displayOrientation ?? vm.dockOrientation;

    return Container(
      key: const ValueKey('video_context_dock'),
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _DockHeader(
            title: '字幕 / 时间轴',
            subtitle: _subtitleStatusLabel(vm),
            orientation: orientation,
            onToggleOrientation: widget.orientationLocked
                ? null
                : () => vm.setDockOrientation(
                    vm.dockOrientation == DockOrientation.right
                        ? DockOrientation.bottom
                        : DockOrientation.right,
                  ),
            onClose: () => vm.setDockVisible(false),
          ),
          Divider(height: 1, color: tokens.divider),
          // Study timeline with time anchors — lives in the dock (not overlaid
          // on the player) so it never overlaps a native player's progress bar.
          if (vm.canReadPosition)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TimelineAnchorBar(viewModel: vm),
            ),
          if (vm.canCreateTimeAnchorNow)
            _CurrentTimeAnnotationBar(viewModel: vm),
          if (vm.canReadPosition) Divider(height: 1, color: tokens.divider),
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
          if (vm.annotations.isNotEmpty) _AnnotationCardsList(viewModel: vm),
        ],
      ),
    );
  }

  String _subtitleStatusLabel(VideoStudyViewModel vm) {
    if (vm.hasRuntimePlaybackSurface && !vm.canReadPosition) {
      return '可播放 · 时间研读受限';
    }
    if (vm.subtitleFetchStatus == SubtitleAutoFetchStatus.fetching) {
      return '自动获取字幕中…';
    }
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

class _CurrentTimeAnnotationBar extends StatelessWidget {
  const _CurrentTimeAnnotationBar({required this.viewModel});

  final VideoStudyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final rangeStart = viewModel.rangeSelectionStartMs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '当前位置 ${VideoStudyViewModel.formatTimecode(viewModel.positionMs)}',
            key: const ValueKey('video_current_position_label'),
            style: richTextCodeTextStyle(
              color: tokens.textMuted,
              fontSize: 11,
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('video_annotate_current_position'),
            onPressed: viewModel.hasPendingAnnotation
                ? null
                : viewModel.beginPointAnnotationAtCurrent,
            icon: const Icon(Icons.add_comment_outlined, size: 15),
            label: const Text('在当前位置添加标注'),
          ),
          if (rangeStart == null)
            TextButton.icon(
              key: const ValueKey('video_begin_range_annotation'),
              onPressed: viewModel.hasPendingAnnotation
                  ? null
                  : viewModel.beginRangeSelectionAtCurrent,
              icon: const Icon(Icons.first_page_rounded, size: 15),
              label: const Text('开始区间'),
            )
          else ...[
            Text(
              '起点 ${VideoStudyViewModel.formatTimecode(rangeStart)}',
              style: richTextCodeTextStyle(
                color: tokens.action,
                fontSize: 11,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('video_finish_range_annotation'),
              onPressed: viewModel.finishRangeSelectionAtCurrent,
              icon: const Icon(Icons.last_page_rounded, size: 15),
              label: const Text('以当前位置结束并标注'),
            ),
            IconButton(
              tooltip: '取消区间',
              onPressed: viewModel.cancelRangeSelection,
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class _DockHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final DockOrientation orientation;
  final VoidCallback? onToggleOrientation;
  final VoidCallback onClose;

  const _DockHeader({
    required this.title,
    required this.subtitle,
    required this.orientation,
    required this.onToggleOrientation,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
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
                  style: whiteboardUiTextStyle(
                    color: tokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  key: const ValueKey('subtitle_status'),
                  subtitle,
                  style: whiteboardUiTextStyle(
                    color: tokens.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: onToggleOrientation == null
                ? '窗口较窄，已自动停靠底部'
                : orientation == DockOrientation.right
                ? '停靠到底部'
                : '停靠到右侧',
            icon: Icon(
              orientation == DockOrientation.right
                  ? Icons.view_stream_outlined
                  : Icons.view_column_outlined,
              size: 18,
            ),
            color: tokens.textMuted,
            disabledColor: tokens.textFaint,
            onPressed: onToggleOrientation,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            key: const ValueKey('video_close_dock'),
            tooltip: '关闭字幕与标注',
            icon: const Icon(Icons.close, size: 18),
            color: tokens.textMuted,
            onPressed: onClose,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
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
    final tokens = DesktopWorkspaceTokens.of(context);
    final startMs = viewModel.pendingAnnotationStartMs ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '在 ${VideoStudyViewModel.formatTimecode(startMs)} 创建标注',
            style: richTextCodeTextStyle(color: tokens.action, fontSize: 13),
          ),
          const SizedBox(height: 12),
          AnnotationEditor(
            viewModel: viewModel,
            initialQuote: viewModel.pendingAnnotationSuggestedQuote,
          ),
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
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.actionSoft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 18, color: tokens.action),
                  const SizedBox(width: 8),
                  Text(
                    '标注已保存',
                    style: whiteboardUiTextStyle(
                      color: tokens.textPrimary,
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
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
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
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.divider, width: 1)),
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

  const _AnnotationCardThumb({required this.annotation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
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
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.divider, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              timecode,
              style: richTextCodeTextStyle(
                color: tokens.action,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: whiteboardUiTextStyle(
                color: tokens.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
