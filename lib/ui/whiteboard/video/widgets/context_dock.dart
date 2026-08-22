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
  _DockSection _section = _DockSection.subtitles;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_followAnnotationWorkflow);
  }

  @override
  void didUpdateWidget(covariant ContextDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      oldWidget.viewModel.removeListener(_followAnnotationWorkflow);
      widget.viewModel.addListener(_followAnnotationWorkflow);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_followAnnotationWorkflow);
    super.dispose();
  }

  void _followAnnotationWorkflow() {
    final vm = widget.viewModel;
    if ((vm.hasPendingAnnotation || vm.showSaveConfirmation) &&
        _section != _DockSection.notes &&
        mounted) {
      setState(() => _section = _DockSection.notes);
    }
  }

  void _selectSection(_DockSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

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
          _DockHeader(
            title: '研读辅助',
            subtitle: _section == _DockSection.subtitles
                ? _subtitleStatusLabel(vm)
                : '${vm.annotations.length} 条视频笔记',
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
          _DockTabs(
            selected: _section,
            noteCount: vm.annotations.length,
            onSelected: _selectSection,
          ),
          Divider(height: 1, color: tokens.divider),
          // Body
          Expanded(
            child: _section == _DockSection.subtitles
                ? KeyedSubtree(
                    key: const ValueKey('video_subtitles_tab_content'),
                    child: SubtitleListView(viewModel: vm),
                  )
                : _VideoNotesPane(viewModel: vm),
          ),
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

enum _DockSection { subtitles, notes }

class _DockTabs extends StatelessWidget {
  const _DockTabs({
    required this.selected,
    required this.noteCount,
    required this.onSelected,
  });

  final _DockSection selected;
  final int noteCount;
  final ValueChanged<_DockSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: _DockTab(
              key: const ValueKey('video_dock_tab_subtitles'),
              label: '字幕',
              selected: selected == _DockSection.subtitles,
              onTap: () => onSelected(_DockSection.subtitles),
            ),
          ),
          Expanded(
            child: _DockTab(
              key: const ValueKey('video_dock_tab_notes'),
              label: noteCount == 0 ? '视频笔记' : '视频笔记 $noteCount',
              selected: selected == _DockSection.notes,
              onTap: () => onSelected(_DockSection.notes),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? tokens.action : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: whiteboardUiTextStyle(
                color: selected ? tokens.action : tokens.textMuted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentTimeAnnotationBar extends StatelessWidget {
  const _CurrentTimeAnnotationBar({required this.viewModel});

  final VideoStudyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.showSaveConfirmation) {
      return _SaveConfirmationPane(
        viewModel: viewModel,
        onDismiss: viewModel.dismissSaveConfirmation,
      );
    }
    if (viewModel.hasPendingAnnotation) {
      return _PendingAnnotationPane(viewModel: viewModel);
    }
    if (viewModel.annotations.isNotEmpty) {
      return _AnnotationCardsList(viewModel: viewModel);
    }
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          viewModel.canCreateTimeAnchorNow
              ? '尚无视频笔记\n可按当前位置或区间创建'
              : '当前播放器无法读取时间\n不能伪造可恢复的时间标注',
          key: const ValueKey('video_notes_empty'),
          textAlign: TextAlign.center,
          style: whiteboardUiTextStyle(
            color: tokens.textFaint,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

class _CurrentTimeAnnotationBar extends StatelessWidget {
  const _CurrentTimeAnnotationBar({
    required this.viewModel,
    this.compact = false,
  });

  final VideoStudyViewModel viewModel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final rangeStart = viewModel.rangeSelectionStartMs;
    final controls = <Widget>[
      Text(
        compact
            ? VideoStudyViewModel.formatTimecode(viewModel.positionMs)
            : '当前位置 ${VideoStudyViewModel.formatTimecode(viewModel.positionMs)}',
        key: const ValueKey('video_current_position_label'),
        style: richTextCodeTextStyle(color: tokens.textMuted, fontSize: 11),
      ),
      OutlinedButton.icon(
        key: const ValueKey('video_annotate_current_position'),
        onPressed:
            viewModel.hasPendingAnnotation || viewModel.isCapturingTimeBoundary
                ? null
                : () => viewModel.beginPointAnnotationAtCurrent(),
        icon: const Icon(Icons.add_comment_outlined, size: 15),
        label: Text(compact ? '当前点' : '在当前位置添加标注'),
      ),
      if (rangeStart == null)
        TextButton.icon(
          key: const ValueKey('video_begin_range_annotation'),
          onPressed: viewModel.hasPendingAnnotation ||
                  viewModel.isCapturingTimeBoundary
              ? null
              : () => viewModel.beginRangeSelectionAtCurrent(),
          icon: const Icon(Icons.first_page_rounded, size: 15),
          label: const Text('开始区间'),
        )
      else ...[
        Text(
          '起点 ${VideoStudyViewModel.formatTimecode(rangeStart)}',
          style: richTextCodeTextStyle(color: tokens.action, fontSize: 11),
        ),
        TextButton.icon(
          key: const ValueKey('video_finish_range_annotation'),
          onPressed: viewModel.isCapturingTimeBoundary
              ? null
              : () => viewModel.finishRangeSelectionAtCurrent(),
          icon: const Icon(Icons.last_page_rounded, size: 15),
          label: Text(compact ? '结束并标注' : '以当前位置结束并标注'),
        ),
        IconButton(
          tooltip: '取消区间',
          onPressed: viewModel.cancelRangeSelection,
          icon: const Icon(Icons.close_rounded, size: 16),
        ),
      ],
    ];
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
        child: Row(spacing: 8, children: controls),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: controls,
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
            tooltip: '关闭字幕与视频笔记',
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
    final endMs = viewModel.pendingAnnotationEndMs ?? startMs;
    final rangeLabel = viewModel.pendingAnnotationIsPoint == false
        ? '${VideoStudyViewModel.formatTimecode(startMs)}–${VideoStudyViewModel.formatTimecode(endMs)}'
        : VideoStudyViewModel.formatTimecode(startMs);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '在 $rangeLabel 创建标注',
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

class _VideoNotesPane extends StatelessWidget {
  const _VideoNotesPane({required this.viewModel});

  final VideoStudyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    late final Widget content;
    if (viewModel.showSaveConfirmation) {
      content = _SaveConfirmationPane(
        viewModel: viewModel,
        onDismiss: viewModel.dismissSaveConfirmation,
      );
    } else if (viewModel.hasPendingAnnotation) {
      content = _PendingAnnotationPane(viewModel: viewModel);
    } else if (viewModel.annotations.isEmpty) {
      content = _EmptyVideoNotes(
        canCreate: viewModel.canCreateTimeAnchorNow,
      );
    } else {
      content = _AnnotationCardsList(viewModel: viewModel);
    }
    return KeyedSubtree(
      key: const ValueKey('video_notes_tab_content'),
      child: content,
    );
  }
}

class _EmptyVideoNotes extends StatelessWidget {
  const _EmptyVideoNotes({required this.canCreate});

  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      key: const ValueKey('video_notes_empty_state'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_alt_outlined, size: 36, color: tokens.textFaint),
            const SizedBox(height: 10),
            Text(
              '还没有视频笔记',
              style: whiteboardUiTextStyle(
                color: tokens.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canCreate
                  ? '可在当前位置创建点笔记或时间区间笔记'
                  : '当前播放器无法读取时间，暂不能创建时间笔记',
              textAlign: TextAlign.center,
              style: whiteboardUiTextStyle(
                color: tokens.textFaint,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
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
                '返回视频笔记',
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
    return ListView.separated(
      key: const ValueKey('video_notes_list'),
      padding: const EdgeInsets.all(12),
      itemCount: annotations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final annotation = annotations[index];
        return _AnnotationCardThumb(
          key: ValueKey('video_note_card_${annotation.card.cardId}'),
          annotation: annotation,
          onTap: () => viewModel.seekTo(annotation.startMs),
        );
      },
    );
  }
}

class _AnnotationCardThumb extends StatelessWidget {
  final UIAnnotation annotation;
  final VoidCallback onTap;

  const _AnnotationCardThumb({
    super.key,
    required this.annotation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final title = annotation.card.title.isEmpty
        ? '未命名标注'
        : annotation.card.title;
    final start = VideoStudyViewModel.formatTimecode(annotation.startMs);
    final timecode = annotation.isPoint ||
            annotation.endMs == annotation.startMs
        ? start
        : '$start–${VideoStudyViewModel.formatTimecode(annotation.endMs)}';
    final summary = annotation.card.body.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.divider, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
