/// Subtitle list view — scrollable cue list with click-to-seek and
/// reverse highlight (playback position → active cue highlight).
///
/// Each cue shows a time code (Cascadia Code) and the cue text. The active
/// cue is highlighted with Palm accentSoft background. Clicking a cue seeks
/// the player to that cue's start time (if canSeek is true).
///
/// A small green square next to each cue's time code is the annotation
/// creation button — clicking it opens the annotation editor pre-filled
/// with the cue's time range.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/player_adapter.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';
import '../view_models/video_study_view_model.dart';

typedef SubtitleFileBytesPicker = Future<Uint8List?> Function();

class SubtitleListView extends StatefulWidget {
  final VideoStudyViewModel viewModel;
  final SubtitleFileBytesPicker? fileBytesPicker;

  const SubtitleListView({
    super.key,
    required this.viewModel,
    this.fileBytesPicker,
  });

  @override
  State<SubtitleListView> createState() => _SubtitleListViewState();
}

class _SubtitleListViewState extends State<SubtitleListView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveCue = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final track = vm.track;

    if (vm.needsSubtitle || track == null || track.cues.isEmpty) {
      return Column(
        children: [
          if (vm.availableCaptionTracks.length > 1)
            _CaptionTrackPicker(viewModel: vm),
          Expanded(
            child: _NeedsSubtitleView(
              hasImportCapability: true,
              reason: vm.subtitleFetchStatus == SubtitleAutoFetchStatus.failed
                  ? vm.subtitleFetchMessage
                  : null,
              failureLabel: vm.subtitleFailureLabel,
              onImport: () => _showImportDialog(context),
            ),
          ),
        ],
      );
    }

    // Auto-scroll to active cue
    final activeIdx = vm.activeCueIndex;
    if (activeIdx != _lastActiveCue && activeIdx >= 0) {
      _lastActiveCue = activeIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCue(activeIdx);
      });
    }

    return Column(
      children: [
        if (vm.availableCaptionTracks.length > 1)
          _CaptionTrackPicker(viewModel: vm),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: track.cues.length,
            itemBuilder: (context, index) {
              final cue = track.cues[index];
              final isActive = index == activeIdx;

              return _CueItem(
                cue: cue,
                isActive: isActive,
                canSeek: vm.canSeek,
                onTap: () => vm.seekToCue(index),
                onAnnotate:
                    vm.canCreateTimeAnchorNow && !vm.hasPendingAnnotation
                        ? () => vm.beginAnnotation(cueIndex: index)
                        : null,
                hasAnnotation: vm.annotations.any(
                  (a) => a.startMs == cue.startMs && a.endMs == cue.endMs,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _scrollToCue(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 64.0;
    final offset = (index * itemHeight) -
        (_scrollController.position.viewportDimension / 3);
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _SubtitleImportDialog(
        fileBytesPicker: widget.fileBytesPicker,
        onImport: (text) {
          widget.viewModel.loadSubtitleFromText(text);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _CaptionTrackPicker extends StatelessWidget {
  const _CaptionTrackPicker({required this.viewModel});

  final VideoStudyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final selected = viewModel.selectedCaptionTrack;
    return Container(
      key: const ValueKey('youtube_caption_track_picker'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CC 轨道',
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const ValueKey('youtube_caption_track_dropdown'),
                    isExpanded: true,
                    value: selected?.selectionKey,
                    hint: const Text('选择字幕轨'),
                    items: [
                      for (final candidate in viewModel.availableCaptionTracks)
                        DropdownMenuItem(
                          value: candidate.selectionKey,
                          child: Text(
                            candidate.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: viewModel.subtitleFetchStatus ==
                            SubtitleAutoFetchStatus.fetching
                        ? null
                        : (key) {
                            if (key == null) return;
                            for (final candidate
                                in viewModel.availableCaptionTracks) {
                              if (candidate.selectionKey == key) {
                                viewModel.selectPlatformSubtitleTrack(
                                  candidate,
                                );
                                break;
                              }
                            }
                          },
                  ),
                ),
              ),
            ],
          ),
          if (viewModel.subtitleFetchStatus == SubtitleAutoFetchStatus.failed &&
              viewModel.subtitleFetchMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              '${viewModel.subtitleFailureLabel == null ? '' : '${viewModel.subtitleFailureLabel}：'}'
              '${viewModel.subtitleFetchMessage}',
              key: const ValueKey('youtube_caption_track_error'),
              style: whiteboardUiTextStyle(
                color: tokens.error,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CueItem extends StatelessWidget {
  final TimedTextCue cue;
  final bool isActive;
  final bool canSeek;
  final VoidCallback onTap;
  final VoidCallback? onAnnotate;
  final bool hasAnnotation;

  const _CueItem({
    required this.cue,
    required this.isActive,
    required this.canSeek,
    required this.onTap,
    required this.onAnnotate,
    required this.hasAnnotation,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);

    return Semantics(
      selected: isActive,
      button: canSeek,
      label: '字幕 ${VideoStudyViewModel.formatTimecode(cue.startMs)}',
      child: InkWell(
        key: ValueKey('subtitle_cue_${cue.cueId}'),
        onTap: canSeek ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: isActive
                ? tokens.actionSoft.withValues(alpha: 0.35)
                : Colors.transparent,
            border: Border(bottom: BorderSide(color: tokens.divider)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          VideoStudyViewModel.formatTimecode(cue.startMs),
                          style: richTextCodeTextStyle(
                            color: isActive ? tokens.action : tokens.textMuted,
                            fontSize: 12,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 36,
                      child: IconButton(
                        key: ValueKey('annotate_${cue.cueId}'),
                        tooltip: hasAnnotation ? '再建一条标注' : '创建时间标注',
                        onPressed: onAnnotate,
                        padding: EdgeInsets.zero,
                        icon: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: hasAnnotation
                                ? tokens.action
                                : tokens.action.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    cue.text,
                    style: whiteboardUiTextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      height: 1.65,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeedsSubtitleView extends StatelessWidget {
  final bool hasImportCapability;
  final VoidCallback onImport;
  final String? reason;
  final String? failureLabel;

  const _NeedsSubtitleView({
    required this.hasImportCapability,
    required this.onImport,
    this.reason,
    this.failureLabel,
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
            Icon(Icons.subtitles_outlined, size: 40, color: tokens.textFaint),
            const SizedBox(height: 12),
            Text(
              '需要字幕',
              style: whiteboardUiTextStyle(
                color: tokens.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            if (failureLabel != null) ...[
              Text(
                '失败分类：$failureLabel',
                key: const ValueKey('subtitle_failure_category'),
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              reason != null && reason!.isNotEmpty
                  ? reason!
                  : '平台未提供可靠字幕\n导入 SRT 或 VTT 文件开始研读',
              textAlign: TextAlign.center,
              style: whiteboardUiTextStyle(
                color: tokens.textFaint,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            if (hasImportCapability) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('导入字幕'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.action,
                  foregroundColor: tokens.canvas,
                  minimumSize: const Size(44, 44),
                  textStyle: whiteboardUiTextStyle(fontSize: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubtitleImportDialog extends StatefulWidget {
  final void Function(String text) onImport;
  final SubtitleFileBytesPicker? fileBytesPicker;
  const _SubtitleImportDialog({
    required this.onImport,
    this.fileBytesPicker,
  });

  @override
  State<_SubtitleImportDialog> createState() => _SubtitleImportDialogState();
}

class _SubtitleImportDialogState extends State<_SubtitleImportDialog> {
  final _controller = TextEditingController();
  String? _fileError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.surfaceRaised,
      title: Text(
        '导入字幕',
        style: whiteboardUiTextStyle(
          color: tokens.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('选择 SRT / VTT 文件'),
            ),
            if (_fileError != null) ...[
              const SizedBox(height: 6),
              Text(
                _fileError!,
                style: whiteboardUiTextStyle(color: tokens.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: '或粘贴 SRT / VTT 内容…',
                border: OutlineInputBorder(),
              ),
              style: whiteboardUiTextStyle(
                color: tokens.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_controller.text.trim().isNotEmpty) {
              widget.onImport(_controller.text);
            }
          },
          child: const Text('导入'),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    try {
      final bytes = widget.fileBytesPicker == null
          ? await _pickSubtitleFileBytes()
          : await widget.fileBytesPicker!();
      if (bytes == null) {
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.trim().isEmpty) {
        setState(() => _fileError = '字幕文件为空。');
        return;
      }
      setState(() {
        _fileError = null;
        _controller.text = text;
      });
    } catch (_) {
      setState(
        () => _fileError = '字幕文件读取失败，请确认文件仍可访问后重试。',
      );
    }
  }

  Future<Uint8List?> _pickSubtitleFileBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt'],
      withData: true,
    );
    if (result == null) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null) throw const FormatException('unreadable subtitle file');
    return bytes;
  }
}
