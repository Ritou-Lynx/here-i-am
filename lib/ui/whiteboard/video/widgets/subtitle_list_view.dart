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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/player_adapter.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import '../view_models/video_study_view_model.dart';

class SubtitleListView extends StatefulWidget {
  final VideoStudyViewModel viewModel;

  const SubtitleListView({super.key, required this.viewModel});

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
      return _NeedsSubtitleView(
        hasImportCapability: true,
        reason: vm.subtitleFetchStatus == SubtitleAutoFetchStatus.failed
            ? vm.subtitleFetchMessage
            : null,
        onImport: () => _showImportDialog(context),
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

    return ListView.builder(
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
          onAnnotate: () => vm.beginAnnotation(cueIndex: index),
          hasAnnotation: vm.annotations.any(
            (a) => a.startMs == cue.startMs && a.endMs == cue.endMs,
          ),
        );
      },
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
        onImport: (text) {
          widget.viewModel.loadSubtitleFromText(text);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _CueItem extends StatelessWidget {
  final TimedTextCue cue;
  final bool isActive;
  final bool canSeek;
  final VoidCallback onTap;
  final VoidCallback onAnnotate;
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
    final tokens = Theme.of(context).extension<SpringRainUiTokens>() ??
        SpringRainUiTokens.daylight;

    return InkWell(
      onTap: canSeek ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? tokens.accentSoft : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? tokens.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time code + annotation button
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    VideoStudyViewModel.formatTimecode(cue.startMs),
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF43593B)
                          : const Color(0xFF8F8E88),
                      fontSize: 12,
                      fontFamily: 'Cascadia Code',
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    key: ValueKey('annotate_${cue.cueId}'),
                    onTap: onAnnotate,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: hasAnnotation
                            ? const Color(0xFF43593B)
                            : const Color(0x6643593B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Cue text
            Expanded(
              child: Text(
                cue.text,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF293025)
                      : const Color(0xFF58402E),
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedsSubtitleView extends StatelessWidget {
  final bool hasImportCapability;
  final VoidCallback onImport;
  final String? reason;

  const _NeedsSubtitleView({
    required this.hasImportCapability,
    required this.onImport,
    this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.subtitles_outlined,
              size: 40,
              color: SpringRainUiTokens.daylightTextTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              '需要字幕',
              style: TextStyle(
                color: SpringRainUiTokens.daylightTextSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              reason != null && reason!.isNotEmpty
                  ? reason!
                  : '平台未提供可靠字幕\n导入 SRT 或 VTT 文件开始研读',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SpringRainUiTokens.daylightTextTertiary,
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
                  backgroundColor: SpringRainUiTokens.daylightAccent,
                  foregroundColor: SpringRainUiTokens.daylightTextOnAccent,
                  textStyle: const TextStyle(fontSize: 14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
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
  const _SubtitleImportDialog({required this.onImport});

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
    return AlertDialog(
      backgroundColor: SpringRainUiTokens.daylightSurfaceRaised,
      title: const Text(
        '导入字幕',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                style: const TextStyle(
                  color: SpringRainUiTokens.daylightError,
                  fontSize: 12,
                ),
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        setState(() => _fileError = '无法读取字幕文件。');
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
    } catch (error) {
      setState(() => _fileError = '字幕文件读取失败：$error');
    }
  }
}
